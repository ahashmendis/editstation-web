# EDITSTATION launch teaser ("coming soon")

A 20.5-second vertical motion graphic (1080×1920, 30 fps) with an original synthesised soundtrack,
for Reels / TikTok / Shorts. Everything is generated from code in this folder: no stock footage,
samples or downloads. It sits outside the app; nothing in `src/` or `supabase/` depends on it.

## Files

| File                 | What it is                                                                       |
| -------------------- | -------------------------------------------------------------------------------- |
| `teaser.html`        | Page holding the 1080×1920 canvas; loads the Geist fonts from `fonts/`           |
| `teaser.js`          | The animation. `window.renderAt(t)` draws the frame for time `t` (pure function) |
| `cues.json`          | Single source of timing: scene cues for the picture, `sfx` list for the sound    |
| `render-frames.mjs`  | Playwright (Chromium) renders every frame and pipes PNGs into ffmpeg             |
| `sfx.mjs`            | Pure-Node synth: music bed + SFX, mixed to `teaser-audio.wav`                    |
| `fonts/`             | Geist + Geist Mono (copied from `node_modules/next`, SIL OFL)                    |
| `frames-preview/`    | Key frames used to review legibility and safe areas                              |
| `teaser-silent.webm` | VP9 video, no audio                                                              |
| `teaser-audio.wav`   | 48 kHz stereo 16-bit soundtrack, exactly 20.5 s                                  |
| `teaser.mp4`         | Final social file: H.264 High + AAC 192k, `+faststart`                           |

## Script (times in seconds, from `cues.json`)

| Time        | Picture                                                                                                          | Sound                              |
| ----------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| 0.10–1.85   | Hook: "STOP / CHASING / EDITORS." slams in word by word, purple clip bar                                         | 2 impacts + sub-drop, swish, drone |
| 1.85–3.55   | "Send the project. We manage the edit." + no-account line                                                        | Whoosh; 120 BPM bed starts         |
| 3.55–8.50   | Three-track timeline (You / Lenscape / Editor): 11 clips snap in, playhead sweeps                                | Ticks, 11 snaps, airy sweep        |
| 8.50–12.90  | Benefits: Vetted editors · Clear briefs, pay agreed · 3 revision rounds included (not a marketplace, no bidding) | Impact per beat                    |
| 12.90–14.90 | "Two ways in.": Send a project (no account) / Join as an editor (apply, get verified)                            | Whoosh, 2 snaps                    |
| 14.90–16.40 | Pull-in with converging light streaks                                                                            | Riser with accelerating roll       |
| 16.40–18.35 | Logo: mark draws, three sparks pop, mark settles into the EDIT/STATION lockup                                    | Sub-drop, 3 shimmers, swish        |
| 18.05–20.50 | "Coming soon" + "by Lenscape Studios", held about 2 s                                                            | Chime, warm chord fades out        |

Copy only states product facts from `docs/` and the landing page; there are no prices, dates or stats.

Key text stays inside the Reels/TikTok safe area: left of x = 950 (right 12%) and above y = 1536
(bottom 20%). Decorative graphics (glow, outlined numbers, streaks) may cross those lines.

## Re-render

Run from this folder. Needs Node 24 and the repo's `node_modules` (`@playwright/test` with Chromium).

```sh
node sfx.mjs                      # 1. soundtrack -> teaser-audio.wav (about 2 s)
node render-frames.mjs            # 2. frames -> teaser-silent.webm + teaser.mp4 (a few minutes)
node render-frames.mjs --preview  # key frames -> frames-preview/
node render-frames.mjs --preview 0.5 9.1   # specific times
```

To change timing, edit `cues.json` and run both steps again: picture and sound read the same cues.
To preview in a browser, serve this folder over HTTP (the page fetches `cues.json`), then open
`teaser.html?t=12.5` for one frame or `teaser.html?play` for real-time playback.

ffmpeg binaries used by `render-frames.mjs` (override with environment variables):

- `FFMPEG_FULL` (default `../ffmpeg-tool/node_modules/ffmpeg-static/ffmpeg.exe`): libx264 + AAC.
  Encodes `teaser.mp4` straight from the PNG frames plus the WAV, and the WebM from PNGs.
- `FFMPEG_VP9` (default Playwright's `%LOCALAPPDATA%\ms-playwright\ffmpeg-1013\ffmpeg-win64.exe`):
  fallback for the WebM only when no full ffmpeg is present (it has no audio encoders and decodes
  only MJPEG, so it is fed quality-100 JPEGs).

## Muxing manually

`render-frames.mjs` already writes `teaser.mp4`. To build it from the two intermediate files
with any full ffmpeg instead (one generation of loss from the VP9 file):

```sh
ffmpeg -y -i teaser-silent.webm -i teaser-audio.wav -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -profile:v high -preset slow -crf 18 -pix_fmt yuv420p -r 30 -s 1080x1920 \
  -c:a aac -b:a 192k -ar 48000 -t 20.5 -movflags +faststart teaser.mp4
```
