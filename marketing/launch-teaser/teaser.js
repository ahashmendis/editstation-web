// EDITSTATION "coming soon" teaser. Every pixel is a pure function of time t (seconds):
// window.renderAt(t) draws the frame for t onto a 1080x1920 canvas. No Math.random, no clocks.
// Timings come from cues.json (shared with sfx.mjs so picture and sound stay in sync).
"use strict";

(() => {
  const W = 1080;
  const H = 1920;
  // Safe area for Reels/TikTok: text stays left of x=950 (right 12%) and above y=1536 (bottom 20%).
  const SAFE_L = 90;
  const SAFE_R = 930;
  const SAFE_W = SAFE_R - SAFE_L;
  const SAFE_CX = (SAFE_L + SAFE_R) / 2;

  // Brand tokens (src/app/globals.css dark theme, converted from oklch).
  const C = {
    bg: "#0c0b11",
    card: "#15131c",
    muted: "#1d1a25",
    border: "#2a2733",
    fg: "#f6f6f7",
    mfg: "#a7a6b2",
    primary: "#9643e5",
    brandText: "#b17ff0",
    secondary: "#26232f",
  };

  // Logo geometry, copied verbatim from src/components/logo-mark.tsx (400-unit grid).
  const LOGO = {
    torso:
      "M50 304C56 240 86 191 150 191H172C186 191 195 201 195 215V270.5H140L130.5 240A4.5 4.5 0 0 0 121.5 242L132.5 279.5H195V304Z",
    screen: "M227 195H375L350 293H200Z",
    sparks: [
      [287, 141, 302, 161],
      [332, 118, 332, 151],
      [381, 138, 363, 161],
    ],
    // Drawn bounds of the figure inside the 400 box (desk line 17..357 + sparks to 387).
    bx: 11,
    bw: 376,
    by: 84,
    bh: 232,
  };
  const SCREEN_PERIMETER = 148 + Math.hypot(25, 98) + 150 + Math.hypot(27, 98);

  const canvas = document.getElementById("stage");
  const ctx = canvas.getContext("2d");
  let CUES = null;
  let P = null; // Path2D cache

  // ---------- math ----------
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, k) => a + (b - a) * k;
  const prog = (t, a, d) => clamp((t - a) / d);
  const eOutCubic = (k) => 1 - Math.pow(1 - k, 3);
  const eInCubic = (k) => k * k * k;
  const eInOutCubic = (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
  const eOutExpo = (k) => (k >= 1 ? 1 : 1 - Math.pow(2, -10 * k));
  const eOutBack = (k, s = 1.70158) => 1 + (s + 1) * Math.pow(k - 1, 3) + s * Math.pow(k - 1, 2);
  function mulberry32(seed) {
    return () => {
      seed |= 0;
      seed = (seed + 0x6d2b79f5) | 0;
      let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  }

  // ---------- text ----------
  function font(weight, size, mono = false) {
    ctx.font = `${weight} ${size}px ${mono ? '"Geist Mono"' : "Geist"}, system-ui, sans-serif`;
  }
  function tracking(size, em) {
    ctx.letterSpacing = `${(size * em).toFixed(2)}px`;
  }
  function measure(str, weight, size, em = -0.04, mono = false) {
    font(weight, size, mono);
    tracking(size, em);
    return ctx.measureText(str).width;
  }
  function fitSize(str, weight, max, maxW, em = -0.04) {
    const w = measure(str, weight, 100, em);
    return Math.min(max, (100 * maxW) / w);
  }
  function drawText(str, x, y, o) {
    const { size, weight = 700, color = C.fg, align = "left", em = -0.04, mono = false } = o;
    font(weight, size, mono);
    tracking(size, em);
    ctx.textAlign = align;
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = color;
    ctx.fillText(str, x, y);
  }

  // ---------- background ----------
  let grain = [];
  function buildGrain() {
    const rnd = mulberry32(1337);
    grain = [0, 1, 2, 3].map(() => {
      const c = document.createElement("canvas");
      c.width = 540;
      c.height = 960;
      const g = c.getContext("2d");
      const img = g.createImageData(540, 960);
      for (let i = 0; i < img.data.length; i += 4) {
        const v = Math.floor(rnd() * 255);
        img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
        img.data[i + 3] = 255;
      }
      g.putImageData(img, 0, 0);
      return c;
    });
  }

  function background(t, glow) {
    ctx.fillStyle = C.bg;
    ctx.fillRect(0, 0, W, H);
    // Slowly drifting purple glow.
    const gx = 540 + Math.sin(t * 0.35) * 120;
    const gy = glow.y + Math.cos(t * 0.27) * 80;
    const r = ctx.createRadialGradient(gx, gy, 0, gx, gy, glow.r);
    r.addColorStop(0, `rgba(150,67,229,${0.26 * glow.a})`);
    r.addColorStop(0.45, `rgba(150,67,229,${0.08 * glow.a})`);
    r.addColorStop(1, "rgba(150,67,229,0)");
    ctx.fillStyle = r;
    ctx.fillRect(0, 0, W, H);
    // Faint editing-ruler grid along the top and bottom.
    ctx.fillStyle = "rgba(255,255,255,0.035)";
    for (let x = 0; x < W; x += 40) {
      const tall = x % 200 === 0;
      ctx.fillRect(x, 0, 2, tall ? 34 : 18);
      ctx.fillRect(x, H - (tall ? 34 : 18), 2, tall ? 34 : 18);
    }
  }

  function finish(t) {
    // Vignette.
    const v = ctx.createRadialGradient(540, 900, 500, 540, 960, 1250);
    v.addColorStop(0, "rgba(0,0,0,0)");
    v.addColorStop(1, "rgba(0,0,0,0.55)");
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, W, H);
    // Film grain (deterministic: chosen by frame index).
    const f = Math.round(t * CUES.fps);
    ctx.save();
    ctx.globalAlpha = 0.045;
    ctx.globalCompositeOperation = "overlay";
    ctx.drawImage(grain[f % grain.length], 0, 0, W, H);
    ctx.restore();
  }

  function timecode(t, alpha) {
    if (alpha <= 0) return;
    const f = Math.round(t * CUES.fps);
    const s = Math.floor(f / 30);
    const tc = `00:00:${String(s).padStart(2, "0")}:${String(f % 30).padStart(2, "0")}`;
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = C.primary;
    ctx.beginPath();
    ctx.arc(SAFE_L + 8, 186, 7, 0, Math.PI * 2);
    ctx.fill();
    drawText(tc, SAFE_L + 26, 195, { size: 26, weight: 500, color: C.mfg, mono: true, em: 0.02 });
    ctx.restore();
  }

  // ---------- camera shake & flashes ----------
  function impacts() {
    const c = CUES.cues;
    return [
      [c.hook1, 22, "#ffffff"],
      [c.hook2, 22, "#ffffff"],
      [c.hook3, 30, C.primary],
      [c.benefit1, 14, C.primary],
      [c.benefit2, 14, C.primary],
      [c.benefit3, 14, C.primary],
      [c.logo, 26, "#ffffff"],
    ];
  }
  function shake(t) {
    let x = 0;
    let y = 0;
    impacts().forEach(([t0, a], i) => {
      const dt = t - t0;
      if (dt < 0 || dt > 0.5) return;
      const e = a * Math.exp(-dt * 14);
      x += e * Math.sin(dt * 95 + i * 1.7);
      y += e * Math.cos(dt * 81 + i * 2.3);
    });
    return [x, y];
  }
  function flashes(t) {
    impacts().forEach(([t0, , color]) => {
      const dt = t - t0;
      if (dt < 0 || dt > 0.25) return;
      ctx.save();
      ctx.globalAlpha = 0.32 * Math.exp(-dt * 22);
      ctx.fillStyle = color;
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    });
  }

  // A word that slams in: scale 1.7 -> 1 with a short motion-blur trail.
  function slamText(str, x, y, o, t, t0, dur = 0.16) {
    if (t < t0) return;
    font(o.weight || 800, o.size);
    tracking(o.size, o.em ?? -0.045);
    const w = ctx.measureText(str).width;
    const cx = x + w / 2;
    const cy = y - o.size * 0.36;
    const draw = (tt, alpha) => {
      const k = prog(tt, t0, dur);
      const s = lerp(o.from ?? 1.7, 1, eOutExpo(k));
      const a = prog(tt, t0, 0.035) * alpha;
      if (a <= 0) return;
      ctx.save();
      ctx.globalAlpha = a;
      ctx.translate(cx, cy);
      ctx.scale(s, s);
      ctx.translate(-cx, -cy);
      drawText(str, x, y, o);
      ctx.restore();
    };
    for (let g = 3; g >= 1; g--) draw(t - g * 0.014, 0.22 / g);
    draw(t, 1);
  }

  // A line that rises out of a mask.
  function riseText(str, x, y, o, t, t0, dur = 0.5) {
    const k = eOutCubic(prog(t, t0, dur));
    if (k <= 0) return;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, y - o.size * 1.05, W, o.size * 1.35);
    ctx.clip();
    ctx.globalAlpha = (o.alpha ?? 1) * clamp(k * 1.6);
    drawText(str, x, y + (1 - k) * o.size * 1.1, o);
    ctx.restore();
  }

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, r);
  }

  // ---------- scene 1: hook ----------
  function sceneHook(t) {
    const c = CUES.cues;
    if (t > c.scene2 + 0.25) return;
    const exit = eInCubic(prog(t, c.scene2, 0.2));
    const lines = [
      ["STOP", C.fg, c.hook1],
      ["CHASING", C.fg, c.hook2],
      ["EDITORS.", C.brandText, c.hook3],
    ];
    ctx.save();
    ctx.globalAlpha = 1 - exit;
    ctx.translate(0, -exit * 260);
    let y = 640;
    const sizes = lines.map(([s]) => fitSize(s, 800, 290, SAFE_W, -0.045));
    lines.forEach(([str, color, t0], i) => {
      const size = sizes[i];
      y += size * 0.86;
      slamText(str, SAFE_L - size * 0.03, y, { size, color, weight: 800 }, t, t0);
      if (i === 2) {
        // Purple clip bar wipes in under the last word.
        const k = eOutExpo(prog(t, c.slash, 0.3));
        if (k > 0) {
          ctx.fillStyle = C.primary;
          roundRect(SAFE_L, y + 34, SAFE_W * k, 26, 8);
          ctx.fill();
          ctx.fillStyle = "rgba(255,255,255,0.85)";
          ctx.fillRect(SAFE_L + SAFE_W * k - 4, y + 22, 4, 50);
        }
      }
      y += size * 0.06;
    });
    ctx.restore();
  }

  // ---------- scene 2: promise ----------
  function scenePromise(t) {
    const c = CUES.cues;
    if (t < c.scene2 || t > c.scene3 + 0.25) return;
    const exit = eInCubic(prog(t, c.scene3, 0.2));
    ctx.save();
    ctx.globalAlpha = 1 - exit;
    ctx.translate(-exit * 300, 0);
    const s1 = fitSize("Send the project.", 700, 120, SAFE_W, -0.045);
    const s2 = fitSize("We manage the edit.", 700, 120, SAFE_W, -0.045);
    const s = Math.min(s1, s2);
    riseText(
      "Send the project.",
      SAFE_L,
      860,
      { size: s, weight: 700, em: -0.045 },
      t,
      c.scene2 + 0.04,
    );
    riseText(
      "We manage the edit.",
      SAFE_L,
      860 + s * 1.12,
      { size: s, weight: 700, em: -0.045, color: C.brandText },
      t,
      c.scene2 + 0.22,
    );
    ["No account needed. Lenscape Studios", "runs it from brief to delivery."].forEach((line, i) =>
      riseText(
        line,
        SAFE_L,
        860 + s * 1.12 + 120 + i * 56,
        { size: 40, weight: 400, em: -0.01, color: C.mfg },
        t,
        c.scene2 + 0.5 + i * 0.08,
      ),
    );
    ctx.restore();
  }

  // ---------- scene 3: the three-track timeline ----------
  const TRACKS = [
    {
      name: "You",
      clips: [
        ["Send", 0, 17],
        ["Feedback ×3", 58, 82],
        ["Receive", 84, 100],
      ],
    },
    {
      name: "Lenscape",
      accent: true,
      clips: [
        ["Review", 3, 21],
        ["Assign", 23, 40],
        ["Check", 66, 82],
        ["Deliver", 84, 100],
      ],
    },
    {
      name: "Editor",
      clips: [
        ["Brief + pay", 28, 51],
        ["Edit", 53, 64],
        ["Revise", 66, 82],
      ],
    },
  ];
  const TL = {
    x: 70,
    y: 690,
    w: 880,
    h: 650,
    laneL: 100,
    laneR: 920,
    rowY: 866,
    rowH: 92,
    labelH: 46,
    pitch: 156,
  };

  function sceneTimeline(t) {
    const c = CUES.cues;
    // Hard cut on the first benefit impact (the flash covers it).
    if (t < c.scene3 || t >= c.benefit1) return;
    const exit = 0;
    ctx.save();
    ctx.globalAlpha = 1 - exit;
    const zs = 1 + exit * 0.15;
    ctx.translate(540, 960);
    ctx.scale(zs, zs);
    ctx.translate(-540, -960);

    // Title
    const ts = fitSize("From brief to delivery.", 700, 96, SAFE_W, -0.045);
    riseText(
      "From brief to delivery.",
      SAFE_L,
      600,
      { size: ts, weight: 700, em: -0.045 },
      t,
      c.scene3 + 0.05,
    );

    // Panel
    const pk = eOutCubic(prog(t, c.scene3 + 0.05, 0.4));
    ctx.save();
    ctx.globalAlpha *= pk;
    const ps = lerp(0.94, 1, pk);
    ctx.translate(TL.x + TL.w / 2, TL.y + TL.h / 2);
    ctx.scale(ps, ps);
    ctx.translate(-(TL.x + TL.w / 2), -(TL.y + TL.h / 2));
    ctx.shadowColor = "rgba(150,67,229,0.35)";
    ctx.shadowBlur = 80;
    ctx.shadowOffsetY = 30;
    ctx.fillStyle = C.card;
    roundRect(TL.x, TL.y, TL.w, TL.h, 28);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.strokeStyle = C.border;
    ctx.lineWidth = 2;
    ctx.stroke();

    // Header
    drawText("One project, three tracks", TL.x + 32, TL.y + 58, {
      size: 30,
      weight: 600,
      em: -0.01,
    });
    const sweepK = eInOutCubic(prog(t, c.sweepStart, c.sweepEnd - c.sweepStart));
    const phX = lerp(TL.laneL, TL.laneR, sweepK);
    const phT = sweepK * 9.99;
    const tc = `00:00:${String(Math.floor(phT)).padStart(2, "0")}:${String(Math.floor((phT % 1) * 30)).padStart(2, "0")}`;
    drawText(tc, TL.x + TL.w - 32, TL.y + 58, {
      size: 26,
      weight: 500,
      mono: true,
      em: 0,
      align: "right",
      color: C.brandText,
    });
    ctx.fillStyle = C.border;
    ctx.fillRect(TL.x, TL.y + 88, TL.w, 2);

    // Ruler
    const rulerY = TL.y + 128;
    const lw = TL.laneR - TL.laneL;
    for (let i = 0; i <= 10; i++) {
      const x = TL.laneL + (lw * i) / 10;
      ctx.fillStyle = C.border;
      ctx.fillRect(x, rulerY - 6, 2, 22);
      if (i % 2 === 0 && i < 10) {
        drawText(`00:${String(i).padStart(2, "0")}`, x + 8, rulerY + 12, {
          size: 21,
          weight: 500,
          mono: true,
          em: 0,
          color: C.mfg,
        });
      }
    }
    ctx.fillStyle = C.border;
    ctx.fillRect(TL.laneL, rulerY + 22, lw, 2);

    // Tracks + clips
    let clipIndex = 0;
    const order = [];
    TRACKS.forEach((tr, ti) => tr.clips.forEach((cl) => order.push([cl[1], ti, cl])));
    order.sort((a, b) => a[0] - b[0]);
    const clipCue = new Map(order.map((o, i) => [o[2], c.clips[i]]));

    TRACKS.forEach((tr, ti) => {
      const rowTop = TL.rowY + ti * TL.pitch;
      const y = rowTop + TL.labelH;
      const lk = eOutCubic(prog(t, c.tracks + ti * 0.1, 0.3));
      if (lk <= 0) return;
      ctx.save();
      ctx.globalAlpha *= lk;
      drawText(tr.name, TL.laneL + 2, rowTop + 30, {
        size: 28,
        weight: 600,
        em: -0.01,
        color: tr.accent ? C.brandText : C.mfg,
      });
      ctx.fillStyle = "rgba(255,255,255,0.045)";
      roundRect(TL.laneL, y, lw * lk, TL.rowH, 14);
      ctx.fill();
      ctx.restore();

      tr.clips.forEach((cl) => {
        clipIndex++;
        const [label, a, b] = cl;
        const t0 = clipCue.get(cl);
        const k = prog(t, t0, 0.24);
        if (k <= 0) return;
        const x = TL.laneL + (lw * a) / 100;
        const w = (lw * (b - a)) / 100 - 6;
        const off = (1 - eOutBack(k, 2.2)) * 140;
        const cy = y + 8;
        const ch = TL.rowH - 16;
        const passed = clamp((phX - x) / 40);
        ctx.save();
        ctx.globalAlpha *= clamp(k * 3);
        ctx.translate(off, 0);
        if (tr.accent) {
          ctx.fillStyle = C.primary;
          roundRect(x, cy, w, ch, 10);
          ctx.fill();
        } else {
          ctx.fillStyle = C.secondary;
          roundRect(x, cy, w, ch, 10);
          ctx.fill();
          ctx.strokeStyle = passed > 0 ? `rgba(177,127,240,${0.25 + 0.6 * passed})` : "#3d3949";
          ctx.lineWidth = 2;
          ctx.stroke();
        }
        if (passed > 0) {
          ctx.fillStyle = `rgba(255,255,255,${0.1 * passed})`;
          roundRect(x, cy, w, ch, 10);
          ctx.fill();
        }
        // Label, shrunk to fit the clip if needed.
        let size = 29;
        const mw = measure(label, 600, size, -0.01);
        if (mw > w - 26) size = Math.max(16, (size * (w - 26)) / mw);
        drawText(label, x + 14, cy + ch / 2 + size * 0.36, {
          size,
          weight: 600,
          em: -0.01,
          color: tr.accent ? "#ffffff" : C.fg,
        });
        // Landing flash.
        const fl = 1 - prog(t, t0 + 0.12, 0.2);
        if (k >= 0.5 && fl > 0) {
          ctx.fillStyle = `rgba(255,255,255,${0.55 * fl})`;
          roundRect(x, cy, w, ch, 10);
          ctx.fill();
        }
        ctx.restore();
      });
    });

    // Playhead
    const phA = prog(t, c.tracks + 0.3, 0.3);
    if (phA > 0) {
      ctx.save();
      ctx.globalAlpha *= phA;
      const top = rulerY - 14;
      const bot = TL.rowY + 2 * TL.pitch + TL.labelH + TL.rowH + 14;
      const gl = ctx.createLinearGradient(phX - 30, 0, phX + 30, 0);
      gl.addColorStop(0, "rgba(177,127,240,0)");
      gl.addColorStop(0.5, `rgba(177,127,240,${0.18 + 0.2 * (sweepK > 0 && sweepK < 1 ? 1 : 0)})`);
      gl.addColorStop(1, "rgba(177,127,240,0)");
      ctx.fillStyle = gl;
      ctx.fillRect(phX - 30, top, 60, bot - top);
      ctx.fillStyle = C.brandText;
      ctx.fillRect(phX - 1.5, top, 3, bot - top);
      ctx.translate(phX, top);
      ctx.rotate(Math.PI / 4);
      roundRect(-11, -11, 22, 22, 4);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore(); // panel

    // Caption
    riseText(
      "Lenscape Studios manages every step.",
      SAFE_L,
      TL.y + TL.h + 100,
      { size: 38, weight: 500, em: -0.015, color: C.mfg },
      t,
      c.sweepStart + 0.1,
    );
    ctx.restore();
  }

  // ---------- scene 4: benefits ----------
  const BENEFITS = [
    { lines: ["Vetted", "editors."], sub: "Every editor is verified by Lenscape Studios." },
    { lines: ["Clear briefs.", "Pay agreed."], sub: "No editing starts before the pay is agreed." },
    { lines: ["3 revision", "rounds included."], sub: "Not a marketplace. No bidding." },
  ];

  function sceneBenefits(t) {
    const c = CUES.cues;
    const starts = [c.benefit1, c.benefit2, c.benefit3, c.entry];
    for (let i = 0; i < 3; i++) {
      const t0 = starts[i];
      const t1 = starts[i + 1];
      if (t < t0 || t >= t1 + (i === 2 ? 0.22 : 0)) continue;
      const b = BENEFITS[i];
      const exit = i === 2 ? eInCubic(prog(t, t1, 0.2)) : 0;
      ctx.save();
      ctx.globalAlpha = 1 - exit;
      ctx.translate(0, -exit * 260);

      // Giant outlined index number, decorative.
      const nk = eOutCubic(prog(t, t0, 0.6));
      ctx.save();
      ctx.globalAlpha *= 0.09 * nk;
      font(800, 620);
      tracking(620, -0.06);
      ctx.textAlign = "right";
      ctx.strokeStyle = C.brandText;
      ctx.lineWidth = 3;
      ctx.strokeText(String(i + 1).padStart(2, "0"), 1040 + (1 - nk) * 80, 1430);
      ctx.restore();

      drawText(`0${i + 1} / 03`, SAFE_L, 650, {
        size: 30,
        weight: 500,
        mono: true,
        em: 0.04,
        color: C.brandText,
      });
      const size = Math.min(...b.lines.map((l) => fitSize(l, 800, 170, SAFE_W, -0.05)));
      let y = 700;
      b.lines.forEach((line, li) => {
        y += size * 0.95;
        slamText(
          line,
          SAFE_L - size * 0.02,
          y,
          {
            size,
            weight: 800,
            em: -0.05,
            color: li === b.lines.length - 1 ? C.brandText : C.fg,
            from: 1.35,
          },
          t,
          t0 + li * 0.07,
          0.18,
        );
      });
      // Clip-bar accent under the headline.
      const bk = eOutExpo(prog(t, t0 + 0.16, 0.35));
      if (bk > 0) {
        ctx.fillStyle = C.primary;
        roundRect(SAFE_L, y + 40, 260 * bk, 14, 7);
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,0.12)";
        roundRect(SAFE_L + 272, y + 40, (SAFE_W - 272) * bk, 14, 7);
        ctx.fill();
      }
      riseText(
        b.sub,
        SAFE_L,
        y + 140,
        { size: 40, weight: 500, em: -0.015, color: C.mfg },
        t,
        t0 + 0.24,
        0.45,
      );
      ctx.restore();
    }
  }

  // ---------- scene 5: two ways in ----------
  function sceneEntry(t) {
    const c = CUES.cues;
    if (t < c.entry || t > c.logo) return;
    // During the riser everything is pulled toward the camera and fades.
    const r = prog(t, c.riser, c.logo - c.riser);
    const pull = eInCubic(r);
    ctx.save();
    ctx.globalAlpha = 1 - clamp(pull * 1.4);
    const zs = 1 + pull * 0.35;
    ctx.translate(SAFE_CX, 960);
    ctx.scale(zs, zs);
    ctx.translate(-SAFE_CX, -960);

    const ts = fitSize("Two ways in.", 700, 110, SAFE_W, -0.045);
    riseText("Two ways in.", SAFE_L, 660, { size: ts, weight: 700, em: -0.045 }, t, c.entry + 0.04);

    const cards = [
      {
        t0: c.card1,
        y: 750,
        kicker: "FOR CLIENTS",
        title: "Send a project",
        sub: "No account needed.",
        fill: true,
      },
      {
        t0: c.card2,
        y: 1010,
        kicker: "FOR VIDEO EDITORS",
        title: "Join as an editor",
        sub: "Apply and get verified.",
        fill: false,
      },
    ];
    cards.forEach((cd) => {
      const k = prog(t, cd.t0, 0.32);
      if (k <= 0) return;
      const off = (1 - eOutBack(k, 1.6)) * 220;
      ctx.save();
      ctx.globalAlpha *= clamp(k * 3);
      ctx.translate(off, 0);
      const h = 220;
      if (cd.fill) {
        const g = ctx.createLinearGradient(SAFE_L, cd.y, SAFE_R, cd.y + h);
        g.addColorStop(0, "#a352f0");
        g.addColorStop(1, "#7a2fc8");
        ctx.fillStyle = g;
        ctx.shadowColor = "rgba(150,67,229,0.5)";
        ctx.shadowBlur = 70;
        ctx.shadowOffsetY = 24;
        roundRect(SAFE_L, cd.y, SAFE_W, h, 28);
        ctx.fill();
        ctx.shadowColor = "transparent";
      } else {
        ctx.fillStyle = C.card;
        roundRect(SAFE_L, cd.y, SAFE_W, h, 28);
        ctx.fill();
        ctx.strokeStyle = "rgba(177,127,240,0.55)";
        ctx.lineWidth = 3;
        ctx.stroke();
      }
      const px = SAFE_L + 44;
      drawText(cd.kicker, px, cd.y + 60, {
        size: 24,
        weight: 500,
        mono: true,
        em: 0.08,
        color: cd.fill ? "rgba(255,255,255,0.78)" : C.brandText,
      });
      const tsz = Math.min(74, fitSize(cd.title, 700, 74, SAFE_W - 180, -0.035));
      drawText(cd.title, px, cd.y + 140, { size: tsz, weight: 700, em: -0.035, color: "#ffffff" });
      drawText(cd.sub, px, cd.y + 188, {
        size: 32,
        weight: 400,
        em: -0.01,
        color: cd.fill ? "rgba(255,255,255,0.85)" : C.mfg,
      });
      // Arrow
      const ax = SAFE_R - 70 + Math.sin(prog(t, cd.t0 + 0.3, 0.6) * Math.PI) * 10;
      const ay = cd.y + h / 2;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 6;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      ctx.moveTo(ax - 26, ay);
      ctx.lineTo(ax + 22, ay);
      ctx.moveTo(ax + 4, ay - 18);
      ctx.lineTo(ax + 22, ay);
      ctx.lineTo(ax + 4, ay + 18);
      ctx.stroke();
      ctx.restore();
    });
    ctx.restore();
  }

  // ---------- riser transition ----------
  function sceneRiser(t) {
    const c = CUES.cues;
    if (t < c.riser || t > c.logo + 0.4) return;
    const r = prog(t, c.riser, c.logo - c.riser);
    const after = prog(t, c.logo, 0.4);
    const rnd = mulberry32(99);
    ctx.save();
    // Converging speed streaks.
    const n = 70;
    for (let i = 0; i < n; i++) {
      const ang = rnd() * Math.PI * 2;
      const speed = 0.6 + rnd() * 0.8;
      const phase = rnd();
      const d = 1 - ((phase + r * speed * 2.2) % 1);
      const dist = 120 + d * 1100;
      const len = 40 + eInCubic(r) * 260;
      const cx = 540;
      const cy = 820;
      const x1 = cx + Math.cos(ang) * dist;
      const y1 = cy + Math.sin(ang) * dist * 1.3;
      const x2 = cx + Math.cos(ang) * (dist + len);
      const y2 = cy + Math.sin(ang) * (dist + len) * 1.3;
      ctx.strokeStyle = `rgba(177,127,240,${0.5 * r * (1 - after) * (1 - d * 0.5)})`;
      ctx.lineWidth = 2 + rnd() * 2;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }
    // Core glow building to the drop.
    const core = eInCubic(r) * (1 - after);
    const g = ctx.createRadialGradient(540, 820, 0, 540, 820, 520);
    g.addColorStop(0, `rgba(200,160,255,${0.55 * core})`);
    g.addColorStop(0.3, `rgba(150,67,229,${0.35 * core})`);
    g.addColorStop(1, "rgba(150,67,229,0)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    // Horizontal light line just before the drop.
    const ln = prog(t, c.logo - 0.25, 0.25) * (1 - after);
    if (ln > 0) {
      const lw = eInCubic(ln) * 1080;
      ctx.fillStyle = `rgba(255,255,255,${0.9 * ln})`;
      ctx.fillRect(540 - lw / 2, 818, lw, 4);
    }
    ctx.restore();
  }

  // ---------- scene 6: logo reveal ----------
  function drawMark(t, x, y, scale, alpha) {
    const c = CUES.cues;
    const t0 = c.logo;
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(x, y);
    ctx.scale(scale, scale);
    ctx.fillStyle = C.fg;
    ctx.strokeStyle = C.fg;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    // Head
    const hk = eOutBack(prog(t, t0, 0.28), 2.4);
    if (hk > 0) {
      ctx.save();
      ctx.translate(168, 135);
      ctx.scale(hk, hk);
      ctx.beginPath();
      ctx.arc(0, 0, 51, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    // Torso wipes up from the desk
    const tk = eOutCubic(prog(t, t0 + 0.05, 0.38));
    if (tk > 0) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 304 - 120 * tk, 400, 130 * tk);
      ctx.clip();
      ctx.fill(P.torso);
      ctx.restore();
    }
    // Screen outline draws itself
    const sk = eInOutCubic(prog(t, t0 + 0.15, 0.42));
    if (sk > 0) {
      ctx.save();
      ctx.lineWidth = 16;
      ctx.setLineDash([SCREEN_PERIMETER * sk, SCREEN_PERIMETER]);
      ctx.stroke(P.screen);
      ctx.restore();
    }
    // Camera dot
    const dk = eOutBack(prog(t, t0 + 0.5, 0.2), 3);
    if (dk > 0) {
      ctx.beginPath();
      ctx.arc(285, 250, 12 * dk, 0, Math.PI * 2);
      ctx.fill();
    }
    // Desk line grows outward from the centre
    const lk = eOutExpo(prog(t, t0 + 0.08, 0.45));
    if (lk > 0) {
      ctx.lineWidth = 16;
      ctx.beginPath();
      ctx.moveTo(187 - 170 * lk, 308);
      ctx.lineTo(187 + 170 * lk, 308);
      ctx.stroke();
    }
    // Sparks pop, each with a tiny particle burst
    c.sparks.forEach((st, i) => {
      const [x1, y1, x2, y2] = LOGO.sparks[i];
      const k = eOutBack(prog(t, st, 0.18), 2.2);
      if (k <= 0) return;
      // Inner end is the one nearer the laptop (x1,y1 at the bottom-left for 0, bottom for 1, bottom-right for 2).
      const ix = i === 1 ? x2 : i === 0 ? x2 : x2;
      const iy = i === 1 ? y2 : y2;
      const ox = i === 1 ? x1 : x1;
      const oy = i === 1 ? y1 : y1;
      const shimmer = 0.85 + 0.15 * Math.sin((t - st) * 9 + i * 2);
      ctx.save();
      ctx.strokeStyle = C.primary;
      ctx.shadowColor = "rgba(177,127,240,0.9)";
      ctx.shadowBlur = 22 * shimmer;
      ctx.lineWidth = 12;
      ctx.beginPath();
      ctx.moveTo(ix, iy);
      ctx.lineTo(lerp(ix, ox, k), lerp(iy, oy, k));
      ctx.stroke();
      ctx.restore();
      const pk = prog(t, st, 0.55);
      if (pk > 0 && pk < 1) {
        const rnd = mulberry32(500 + i);
        const dirx = ox - ix;
        const diry = oy - iy;
        const base = Math.atan2(diry, dirx);
        for (let j = 0; j < 7; j++) {
          const a = base + (rnd() - 0.5) * 1.6;
          const sp = 30 + rnd() * 50;
          const d = eOutCubic(pk) * sp;
          ctx.fillStyle = `rgba(200,165,255,${(1 - pk) * 0.95})`;
          ctx.beginPath();
          ctx.arc(ox + Math.cos(a) * d, oy + Math.sin(a) * d, 3.5 * (1 - pk) + 1, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    });
    ctx.restore();
  }

  function sceneLogo(t) {
    const c = CUES.cues;
    if (t < c.logo) return;

    // Lockup layout: mark | divider | EDITSTATION, fitted to the safe width.
    let fs = 112;
    let markH = 150;
    const gap = 34;
    const lay = () => {
      const editW = measure("EDIT", 800, fs, -0.03);
      const stW = measure("STATION", 800, fs, -0.03);
      const markScale = markH / LOGO.bh;
      const markW = LOGO.bw * markScale;
      return { editW, stW, markScale, markW, total: markW + gap + 4 + gap + editW + stW };
    };
    let L = lay();
    if (L.total > SAFE_W) {
      const f = SAFE_W / L.total;
      fs *= f;
      markH *= f;
      L = lay();
    }
    const lockY = 860; // vertical centre of the lockup
    const lockX = SAFE_CX - L.total / 2;

    // Mark: big and centred, then shrinks into the lockup.
    const mv = eInOutCubic(prog(t, c.wordmark, 0.5));
    const bigH = 300;
    const bigScale = bigH / LOGO.bh;
    const bigX = 540 - (LOGO.bx + LOGO.bw / 2) * bigScale;
    const bigY = 840 - (LOGO.by + LOGO.bh / 2) * bigScale;
    const smX = lockX - LOGO.bx * L.markScale;
    const smY = lockY - (LOGO.by + LOGO.bh / 2) * L.markScale;
    const sc = lerp(bigScale, L.markScale, mv);
    drawMark(t, lerp(bigX, smX, mv), lerp(bigY, smY, mv), sc, 1);

    // Divider + wordmark slide out from behind the divider.
    const divX = lockX + L.markW + gap;
    const dk = eOutExpo(prog(t, c.wordmark + 0.25, 0.3));
    if (dk > 0) {
      ctx.fillStyle = C.primary;
      const dh = fs * 0.95 * dk;
      ctx.fillRect(divX, lockY - dh / 2, 4, dh);
    }
    const wk = eOutExpo(prog(t, c.wordmark + 0.32, 0.55));
    if (wk > 0) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(divX + 6, 0, W, H);
      ctx.clip();
      const tx = divX + 4 + gap - (1 - wk) * (L.editW + L.stW + gap);
      const base = lockY + fs * 0.36;
      drawText("EDIT", tx, base, { size: fs, weight: 800, em: -0.03, color: C.fg });
      drawText("STATION", tx + L.editW, base, {
        size: fs,
        weight: 800,
        em: -0.03,
        color: C.primary,
      });
      ctx.restore();
    }

    // Coming soon: letters rise one by one.
    const cs = "Coming soon";
    const csSize = Math.min(132, fitSize(cs, 700, 132, SAFE_W, -0.045));
    font(700, csSize);
    tracking(csSize, -0.045);
    const csW = ctx.measureText(cs).width;
    let cx = SAFE_CX - csW / 2;
    const csY = 1150;
    for (let i = 0; i < cs.length; i++) {
      const ch = cs[i];
      font(700, csSize);
      tracking(csSize, -0.045);
      const cw = ctx.measureText(ch).width;
      const k = eOutCubic(prog(t, c.comingSoon + i * 0.025, 0.45));
      if (k > 0) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, csY - csSize, W, csSize * 1.3);
        ctx.clip();
        ctx.globalAlpha = clamp(k * 1.5);
        drawText(ch, cx, csY + (1 - k) * csSize, { size: csSize, weight: 700, em: -0.045 });
        ctx.restore();
      }
      cx += cw;
    }
    // Byline
    const bk = eOutCubic(prog(t, c.byline, 0.5));
    if (bk > 0) {
      ctx.save();
      ctx.globalAlpha = bk;
      const by = 1236 + (1 - bk) * 20;
      drawText("by Lenscape Studios", SAFE_CX, by, {
        size: 42,
        weight: 500,
        em: -0.01,
        color: C.mfg,
        align: "center",
      });
      ctx.restore();
    }
    // Small clip-bar flourish under the byline.
    const fk = eOutExpo(prog(t, c.byline + 0.2, 0.5));
    if (fk > 0) {
      ctx.fillStyle = C.primary;
      roundRect(SAFE_CX - 60 * fk, 1290, 120 * fk, 8, 4);
      ctx.fill();
    }
  }

  // ---------- frame ----------
  function glowFor(t) {
    const c = CUES.cues;
    if (t < c.scene2) return { y: 900, r: 1000, a: 0.6 + 0.4 * prog(t, c.hook3, 0.3) };
    if (t < c.logo) return { y: 960, r: 1100, a: 0.75 };
    return {
      y: 840,
      r: lerp(700, 1000, eOutCubic(prog(t, c.logo, 1.2))),
      a: 1 + 0.08 * Math.sin(t * 2.4),
    };
  }

  function renderAt(t) {
    if (!CUES) throw new Error("teaser not initialised");
    ctx.save();
    ctx.letterSpacing = "0px";
    background(t, glowFor(t));
    const [sx, sy] = shake(t);
    ctx.save();
    ctx.translate(sx, sy);
    sceneHook(t);
    scenePromise(t);
    sceneTimeline(t);
    sceneBenefits(t);
    sceneEntry(t);
    sceneRiser(t);
    sceneLogo(t);
    ctx.restore();
    timecode(
      t,
      t < CUES.cues.riser
        ? 0.75 * prog(t, CUES.cues.scene2, 0.3)
        : 0.75 * (1 - prog(t, CUES.cues.riser, 0.4)),
    );
    flashes(t);
    finish(t);
    ctx.restore();
    return true;
  }

  async function init(cues) {
    CUES = cues;
    P = { torso: new Path2D(LOGO.torso), screen: new Path2D(LOGO.screen) };
    await Promise.all([
      document.fonts.load('800 100px "Geist"'),
      document.fonts.load('500 30px "Geist Mono"'),
    ]);
    await document.fonts.ready;
    buildGrain();
    return document.fonts.check('800 100px "Geist"');
  }

  window.renderAt = renderAt;
  window.teaserReady = fetch("cues.json")
    .then((r) => r.json())
    .then(init)
    .then((fontOk) => {
      // Manual preview: teaser.html?t=12.5 shows one frame; ?play loops the timeline in real time.
      const q = new URLSearchParams(location.search);
      if (q.has("t")) renderAt(Number(q.get("t")));
      else if (q.has("play")) {
        const start = performance.now();
        const loop = () => {
          renderAt(((performance.now() - start) / 1000) % CUES.duration);
          requestAnimationFrame(loop);
        };
        loop();
      } else renderAt(CUES.duration - 0.01);
      return { fontOk, duration: CUES.duration, fps: CUES.fps };
    });
})();
