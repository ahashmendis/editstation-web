# Reel style

Edit this file any time (or ask Claude to). The /reel skill reads it before every reel.

## Colours (EditStation brand)

- Background: `#0B0A10` (near-black)
- Text: `#F5F3FA`
- Accent: `#9643E5` (brand purple) — only on what matters

## Font

- Geist (same as the website). Font files: `../../node_modules/geist/dist/fonts/` or copy into `public/`.

## Voice

- Free local voice: Kokoro (`kokoro-js`, model `onnx-community/Kokoro-82M-v1.0-ONNX`, dtype `q8`), voice **`am_michael`** (US English, male).
- Word timing: Remotion Whisper (`@remotion/install-whisper-cpp`, whisper.cpp 1.5.5, model `base.en`, installed in `whisper.cpp/`).

## Brand assets

- Logo mark + wordmark: `../../src/components/logo-mark.tsx`, `../../src/components/wordmark.tsx` (icon + purple divider + EDIT/STATION).

## Check thresholds

- Nothing still for more than **1 second**.
- No more than **2 things moving at once**.
