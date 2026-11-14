// Renders teaser.html frame by frame with Playwright (Chromium) and encodes the frames.
//
//   node render-frames.mjs                 full render -> teaser-silent.webm (+ teaser.mp4 if a full
//                                          ffmpeg and teaser-audio.wav are available)
//   node render-frames.mjs --preview       key frames only -> frames-preview/*.png
//   node render-frames.mjs --preview 0.3 9.1   specific times (seconds) -> frames-preview/
//
// Every frame is renderAt(frame / fps): deterministic, so re-renders are identical.
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const HERE = dirname(fileURLToPath(import.meta.url));
const CUES = JSON.parse(readFileSync(join(HERE, "cues.json"), "utf8"));
const { fps, width, height, duration } = CUES;
const FRAMES = Math.round(duration * fps);

const LOCALAPPDATA = process.env.LOCALAPPDATA ?? "C:/Users/ahash/AppData/Local";
// Playwright's bundled ffmpeg: VP9 only, no audio. Override with FFMPEG_VP9.
const FFMPEG_VP9 =
  process.env.FFMPEG_VP9 ?? join(LOCALAPPDATA, "ms-playwright/ffmpeg-1013/ffmpeg-win64.exe");
// A full ffmpeg (libx264 + aac). Override with FFMPEG_FULL.
const FFMPEG_FULL =
  process.env.FFMPEG_FULL ?? join(HERE, "../ffmpeg-tool/node_modules/ffmpeg-static/ffmpeg.exe");

const PREVIEW_TIMES = [0.2, 0.95, 2.6, 4.9, 7.2, 9.0, 11.9, 13.9, 16.95, 19.8];

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".json": "application/json",
  ".woff2": "font/woff2",
};

function serve() {
  return new Promise((resolve) => {
    const server = createServer((req, res) => {
      const path =
        decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/^\/+/, "") ||
        "teaser.html";
      const file = join(HERE, path);
      if (!file.startsWith(HERE) || !existsSync(file)) {
        res.writeHead(404).end();
        return;
      }
      res.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
      res.end(readFileSync(file));
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function encoder(bin, args, label, fmt = "png") {
  const p = spawn(bin, args, { stdio: ["pipe", "ignore", "pipe"] });
  let err = "";
  p.stderr.on("data", (d) => (err = (err + d).slice(-4000)));
  const done = new Promise((res, rej) =>
    p.on("close", (code) =>
      code === 0 ? res() : rej(new Error(`${label} ffmpeg exited ${code}\n${err}`)),
    ),
  );
  return { p, done, label, fmt };
}

function write(enc, buf) {
  return new Promise((res) => (enc.p.stdin.write(buf) ? res() : enc.p.stdin.once("drain", res)));
}

async function main() {
  const args = process.argv.slice(2);
  const preview = args.includes("--preview");
  const times = args.filter((a) => !a.startsWith("--")).map(Number);

  const server = await serve();
  const url = `http://127.0.0.1:${server.address().port}/teaser.html`;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
  page.on("pageerror", (e) => console.error("[page]", e.message));
  await page.goto(url);
  const info = await page.evaluate(() => window.teaserReady);
  if (!info.fontOk) console.warn("Warning: Geist did not load; a system font was used.");
  const clip = { x: 0, y: 0, width, height };
  const shot = async (t) => {
    await page.evaluate((tt) => window.renderAt(tt), t);
    return page.screenshot({ type: "png", clip });
  };

  try {
    if (preview) {
      const dir = join(HERE, "frames-preview");
      mkdirSync(dir, { recursive: true });
      for (const t of times.length ? times : PREVIEW_TIMES) {
        const f = Math.round(t * fps);
        const file = join(dir, `frame-${String(f).padStart(4, "0")}-t${(f / fps).toFixed(2)}.png`);
        writeFileSync(file, await shot(f / fps));
        console.log("wrote", file);
      }
      return;
    }

    const encoders = [];
    const hasFull = existsSync(FFMPEG_FULL);
    // A full ffmpeg decodes PNG (lossless frames in). Playwright's bundled ffmpeg only decodes
    // MJPEG, so it is fed quality-100 JPEGs instead.
    const webmBin = hasFull ? FFMPEG_FULL : FFMPEG_VP9;
    const webmFmt = hasFull ? "png" : "jpeg";
    if (existsSync(webmBin)) {
      encoders.push(
        encoder(
          webmBin,
          [
            "-y",
            "-loglevel",
            "error",
            "-f",
            "image2pipe",
            "-framerate",
            String(fps),
            "-c:v",
            webmFmt === "png" ? "png" : "mjpeg",
            "-i",
            "-",
            "-c:v",
            "libvpx-vp9",
            "-pix_fmt",
            "yuv420p",
            "-b:v",
            "0",
            "-crf",
            "22",
            "-deadline",
            "good",
            "-cpu-used",
            "2",
            "-row-mt",
            "1",
            "-r",
            String(fps),
            join(HERE, "teaser-silent.webm"),
          ],
          "webm",
          webmFmt,
        ),
      );
    } else console.warn("No ffmpeg found; skipping teaser-silent.webm");

    const wav = join(HERE, "teaser-audio.wav");
    if (hasFull && existsSync(wav)) {
      encoders.push(
        encoder(
          FFMPEG_FULL,
          [
            "-y",
            "-loglevel",
            "error",
            "-f",
            "image2pipe",
            "-framerate",
            String(fps),
            "-c:v",
            "png",
            "-i",
            "-",
            "-i",
            wav,
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-c:v",
            "libx264",
            "-profile:v",
            "high",
            "-preset",
            "slow",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            "-r",
            String(fps),
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-ar",
            "48000",
            "-t",
            String(duration),
            "-movflags",
            "+faststart",
            join(HERE, "teaser.mp4"),
          ],
          "mp4",
        ),
      );
    } else
      console.warn(
        "Full ffmpeg or teaser-audio.wav missing; skipping teaser.mp4 (run node sfx.mjs first)",
      );

    if (!encoders.length) throw new Error("No encoder available");
    const t0 = Date.now();
    for (let f = 0; f < FRAMES; f++) {
      await page.evaluate((tt) => window.renderAt(tt), f / fps);
      const bufs = {};
      for (const e of encoders) {
        bufs[e.fmt] ??= await page.screenshot(
          e.fmt === "png" ? { type: "png", clip } : { type: "jpeg", quality: 100, clip },
        );
        await write(e, bufs[e.fmt]);
      }
      if (f % 30 === 0) process.stdout.write(`\rframe ${f}/${FRAMES}`);
    }
    for (const e of encoders) e.p.stdin.end();
    await Promise.all(encoders.map((e) => e.done));
    console.log(
      `\rrendered ${FRAMES} frames (${duration}s @ ${fps}fps) in ${((Date.now() - t0) / 1000).toFixed(1)}s:`,
      encoders.map((e) => e.label).join(", "),
    );
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
