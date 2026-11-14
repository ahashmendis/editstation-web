// Synthesises the teaser soundtrack in pure Node: no samples, no dependencies.
//   node sfx.mjs   ->  teaser-audio.wav (48 kHz, stereo, 16-bit PCM), exactly cues.duration long.
//
// Two layers, both timed from cues.json (the same file teaser.js reads):
//  - a music bed: low drone under the hook, a 120 BPM pulse (kick, offbeat hats, 8th-note bass,
//    side-chained pad) through the middle, then a warm chord after the logo drop;
//  - SFX from the cues.sfx list: impacts, sub-drops, whooshes, swishes, ticks, clip snaps, the
//    playhead sweep, a riser, spark shimmers and a closing chime.
// Everything is deterministic (seeded noise), so re-running produces an identical file.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CUES = JSON.parse(readFileSync(join(HERE, "cues.json"), "utf8"));
const SR = 48000;
const N = Math.round(CUES.duration * SR);
const TAU = Math.PI * 2;

// ---------- buses ----------
const bus = () => [new Float32Array(N), new Float32Array(N)];
const music = bus();
const sfx = bus();
const send = bus(); // reverb send

function rng(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}
let seedCounter = 1;
const noiseGen = () => {
  const r = rng(seedCounter++ * 7919);
  return () => r() * 2 - 1;
};

/** Render a voice: fn(tt, i) returns a mono sample for tt seconds after start. */
function voice(target, start, length, fn, { gain = 1, pan = 0, rev = 0, panFn = null } = {}) {
  const s0 = Math.round(start * SR);
  const len = Math.round(length * SR);
  for (let i = 0; i < len; i++) {
    const idx = s0 + i;
    if (idx < 0) continue;
    if (idx >= N) break;
    const v = fn(i / SR, i) * gain;
    const p = panFn ? panFn(i / SR) : pan;
    const a = ((p + 1) * Math.PI) / 4;
    const l = v * Math.cos(a);
    const r = v * Math.sin(a);
    target[0][idx] += l;
    target[1][idx] += r;
    if (rev) {
      send[0][idx] += l * rev;
      send[1][idx] += r * rev;
    }
  }
}

// Chamberlin state-variable filter with per-sample cutoff.
function svf(q = 0.7) {
  let low = 0;
  let band = 0;
  return (x, fc) => {
    const f = 2 * Math.sin((Math.PI * Math.min(fc, 7500)) / SR);
    low += f * band;
    const high = x - low - q * band;
    band += f * high;
    return { low, band, high };
  };
}
const env = (tt, a, d) => (tt < a ? tt / a : Math.exp(-(tt - a) / d));
const expSweep = (a, b, k) => a * Math.pow(b / a, Math.min(1, Math.max(0, k)));
const saw = (ph) => 2 * (ph - Math.floor(ph + 0.5));
const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);

// ---------- SFX ----------
function impact(t, g) {
  // Pitched kick body + noise crack + low tail.
  let ph = 0;
  voice(
    sfx,
    t,
    1.0,
    (tt) => {
      const f = 45 + 130 * Math.exp(-tt * 22);
      ph += f / SR;
      return Math.sin(TAU * ph) * env(tt, 0.002, 0.32) * 0.95;
    },
    { gain: g },
  );
  const n = noiseGen();
  const lp = svf(0.9);
  voice(
    sfx,
    t,
    0.4,
    (tt) => lp(n(), expSweep(6000, 500, tt / 0.2)).low * env(tt, 0.001, 0.06) * 0.8,
    {
      gain: g,
      rev: 0.35,
    },
  );
  const n2 = noiseGen();
  const bp = svf(0.5);
  voice(sfx, t, 0.3, (tt) => bp(n2(), 1800).band * env(tt, 0.001, 0.035) * 0.6, {
    gain: g,
    rev: 0.5,
    pan: 0.15,
  });
}

function subdrop(t, g) {
  impact(t, g * 0.9);
  let ph = 0;
  voice(
    sfx,
    t,
    2.2,
    (tt) => {
      const f = expSweep(95, 28, tt / 1.4);
      ph += f / SR;
      return Math.tanh(Math.sin(TAU * ph) * 1.6) * env(tt, 0.004, 0.75) * 0.8;
    },
    { gain: g },
  );
}

function whoosh(t, g, { pre = 0.38, post = 0.3, lo = 250, hi = 4200, seedPan = -1 } = {}) {
  const n = noiseGen();
  const f = svf(1.1);
  const n2 = noiseGen();
  const f2 = svf(1.4);
  const len = pre + post;
  voice(
    sfx,
    t - pre,
    len,
    (tt) => {
      const k = tt / len;
      const peak = pre / len;
      const shape = k < peak ? Math.pow(k / peak, 2.2) : Math.pow(1 - (k - peak) / (1 - peak), 1.6);
      const fc =
        k < peak ? expSweep(lo, hi, k / peak) : expSweep(hi, lo * 2, (k - peak) / (1 - peak));
      return (f(n(), fc).band * 0.9 + f2(n2(), fc * 1.6).band * 0.5) * shape;
    },
    { gain: g, rev: 0.3, panFn: (tt) => seedPan * (1 - (2 * tt) / len) * 0.7 },
  );
}

function swish(t, g) {
  whoosh(t, g * 0.8, { pre: 0.14, post: 0.16, lo: 1200, hi: 7000, seedPan: 1 });
}

function tick(t, g, pan = 0) {
  voice(sfx, t, 0.05, (tt) => Math.sin(TAU * 2600 * tt) * env(tt, 0.0005, 0.008), {
    gain: g * 0.6,
    pan,
    rev: 0.2,
  });
}

let snapCount = 0;
function snap(t, g) {
  const pan = [-0.35, 0.3, -0.15, 0.4, 0, -0.4, 0.2][snapCount++ % 7];
  const n = noiseGen();
  const hp = svf(0.6);
  voice(sfx, t, 0.03, (tt) => hp(n(), 5000).high * env(tt, 0.0003, 0.004) * 0.9, {
    gain: g,
    pan,
    rev: 0.25,
  });
  let ph = 0;
  voice(
    sfx,
    t,
    0.08,
    (tt) => {
      ph += expSweep(1500, 700, tt / 0.04) / SR;
      return Math.sin(TAU * ph) * env(tt, 0.0008, 0.018) * 0.45;
    },
    { gain: g, pan, rev: 0.3 },
  );
  let ph2 = 0;
  voice(
    sfx,
    t,
    0.1,
    (tt) => {
      ph2 += (110 + 80 * Math.exp(-tt * 60)) / SR;
      return Math.sin(TAU * ph2) * env(tt, 0.001, 0.03) * 0.6;
    },
    { gain: g, pan: pan * 0.3 },
  );
}

function sweep(t, g, dur) {
  // The playhead gliding across the timeline: airy filtered noise + a soft rising tone.
  const n = noiseGen();
  const f = svf(1.6);
  let ph = 0;
  voice(
    sfx,
    t,
    dur,
    (tt) => {
      const k = tt / dur;
      const shape = Math.sin(Math.PI * k);
      ph += expSweep(320, 640, k) / SR;
      return (f(n(), expSweep(500, 3500, k)).band * 0.5 + Math.sin(TAU * ph) * 0.12) * shape;
    },
    { gain: g, rev: 0.4, panFn: (tt) => -0.6 + (1.2 * tt) / dur },
  );
}

function riser(t, g, dur) {
  // Low A drone underneath so the gap between the bed and the drop never goes empty.
  let pd = 0;
  voice(
    sfx,
    t - 0.1,
    dur + 0.1,
    (tt) => {
      pd += 55 / SR;
      const a = Math.min(1, tt / 0.3) * (0.6 + 0.4 * (tt / (dur + 0.1)));
      return (Math.sin(TAU * pd) + 0.3 * Math.sin(TAU * pd * 2)) * a * 0.35;
    },
    { gain: g },
  );
  const n = noiseGen();
  const f = svf(0.9);
  let p1 = 0;
  let p2 = 0;
  voice(
    sfx,
    t,
    dur,
    (tt) => {
      const k = tt / dur;
      const amp = 0.2 + 0.8 * Math.pow(k, 1.7);
      const fr = expSweep(110, 880, Math.pow(k, 1.3));
      p1 += fr / SR;
      p2 += (fr * 1.007) / SR;
      const tone = (saw(p1) + saw(p2)) * 0.18;
      const noise = f(n(), expSweep(300, 7000, k)).band * 0.8;
      // Tremolo that speeds up toward the drop.
      const trem = 0.75 + 0.25 * Math.sin(TAU * expSweep(4, 22, k) * tt);
      return (tone + noise) * amp * trem;
    },
    { gain: g, rev: 0.35 },
  );
  // Accelerating noise hits in the last second (snare-roll feel).
  const rollStart = t + dur - 1.0;
  let x = 0;
  let step = 0.125;
  while (x < 1.0 - 0.02) {
    const at = rollStart + x;
    const kk = x / 1.0;
    const nn = noiseGen();
    const bp = svf(0.7);
    voice(sfx, at, 0.08, (tt) => bp(nn(), 2200).band * env(tt, 0.001, 0.025), {
      gain: g * (0.15 + 0.5 * kk),
      rev: 0.3,
    });
    x += step;
    if (x > 0.5) step = 0.0625;
  }
}

let sparkCount = 0;
function spark(t, g) {
  const r = rng(4242 + sparkCount * 31);
  const pan = [-0.3, 0.05, 0.35][sparkCount++ % 3];
  const base = [2093, 2637, 3136][sparkCount % 3];
  for (let j = 0; j < 6; j++) {
    const fr = base * [1, 1.5, 2, 2.76, 3.01, 4.2][j] * (1 + (r() - 0.5) * 0.004);
    const dec = 0.18 + r() * 0.35;
    const amp = 0.22 / (1 + j * 0.6);
    voice(
      sfx,
      t + j * 0.012,
      1.2,
      (tt) =>
        Math.sin(TAU * fr * tt + 0.002 * Math.sin(TAU * 6 * tt) * fr) * env(tt, 0.002, dec) * amp,
      {
        gain: g,
        pan: pan + (r() - 0.5) * 0.3,
        rev: 0.7,
      },
    );
  }
}

function chime(t, g) {
  [69, 73, 76, 81].forEach((n, j) => {
    const fr = midi(n + 12);
    voice(
      sfx,
      t + j * 0.03,
      3.0,
      (tt) =>
        (Math.sin(TAU * fr * tt) + 0.3 * Math.sin(TAU * fr * 2.01 * tt) * Math.exp(-tt * 3)) *
        env(tt, 0.004, 0.9) *
        0.16,
      {
        gain: g,
        pan: -0.3 + j * 0.2,
        rev: 0.8,
      },
    );
  });
}

// ---------- music bed ----------
const c = CUES.cues;
const beat = 60 / CUES.bpm;

// Hook drone: low A swelling into the first cut.
{
  let p1 = 0;
  let p2 = 0;
  const lp = svf(0.8);
  voice(
    music,
    0,
    c.scene2 + 0.4,
    (tt) => {
      p1 += 55 / SR;
      p2 += 55.4 / SR;
      const swell =
        Math.min(1, tt / 0.15) * (tt > c.scene2 ? Math.max(0, 1 - (tt - c.scene2) / 0.4) : 1);
      const body = Math.sin(TAU * p1) * 0.5 + lp(saw(p2), 380).low * 0.35;
      return body * swell * (0.5 + 0.5 * Math.min(1, tt / 1.6));
    },
    { gain: 0.5 },
  );
}

// 120 BPM section.
const progression = [57, 53, 48, 55]; // A, F, C, G roots (one bar each, 4 beats)
const chordOf = (root) => (root === 57 || root === 52 ? [0, 3, 7] : [0, 4, 7]);
const beats = [];
for (let b = CUES.beatStart; b < CUES.beatEnd - 1e-6; b += beat) beats.push(b);

beats.forEach((b, i) => {
  // Kick
  let ph = 0;
  voice(
    music,
    b,
    0.35,
    (tt) => {
      ph += (48 + 90 * Math.exp(-tt * 35)) / SR;
      return Math.sin(TAU * ph) * env(tt, 0.002, 0.11);
    },
    { gain: 0.55 },
  );
  // Offbeat hat
  const n = noiseGen();
  const hp = svf(0.5);
  voice(music, b + beat / 2, 0.06, (tt) => hp(n(), 7000).high * env(tt, 0.0005, 0.012), {
    gain: 0.12,
    pan: i % 2 ? 0.25 : -0.25,
  });
});

// Bass 8ths + pad, bar by bar.
for (let bar = 0; ; bar++) {
  const t0 = CUES.beatStart + bar * 4 * beat;
  if (t0 >= CUES.beatEnd - 1e-6) break;
  const root = progression[bar % 4];
  const barLen = Math.min(4 * beat, CUES.beatEnd - t0);
  for (let e = 0; e < 8 && e * beat * 0.5 < barLen; e++) {
    const fr = midi(root - 24);
    let p1 = 0;
    let p2 = 0;
    const lp = svf(0.9);
    voice(
      music,
      t0 + e * beat * 0.5,
      0.24,
      (tt) => {
        p1 += fr / SR;
        p2 += (fr * 1.005) / SR;
        const x = (saw(p1) + saw(p2)) * 0.5;
        return lp(x, 180 + 1100 * Math.exp(-tt * 28)).low * env(tt, 0.003, 0.09);
      },
      { gain: 0.42 },
    );
  }
  chordOf(root).forEach((iv, j) => {
    const fr = midi(root - 12 + iv + 12);
    let p1 = 0;
    let p2 = 0;
    const lp = svf(0.8);
    voice(
      music,
      t0,
      barLen + 0.4,
      (tt) => {
        p1 += fr / SR;
        p2 += (fr * 1.006) / SR;
        const a = Math.min(1, tt / 0.25) * Math.min(1, Math.max(0, (barLen + 0.4 - tt) / 0.4));
        return lp(saw(p1) + saw(p2), 1100).low * a * 0.12;
      },
      { gain: 0.6, pan: -0.4 + j * 0.4, rev: 0.25 },
    );
  });
}

// Outro chord after the logo drop: Fmaj9 colour resolving the A-minor loop, slow filter bloom.
{
  const notes = [41, 53, 57, 60, 64, 67];
  notes.forEach((n, j) => {
    const fr = midi(n);
    let p1 = 0;
    let p2 = 0;
    const lp = svf(0.7);
    const len = CUES.duration - c.logo;
    voice(
      music,
      c.logo,
      len,
      (tt) => {
        p1 += fr / SR;
        p2 += (fr * 1.004) / SR;
        const a = Math.min(1, tt / 0.04) * (0.55 + 0.45 * Math.exp(-tt / 0.8));
        const cutoff = 500 + 1400 * Math.min(1, tt / 2.5);
        return lp(saw(p1) * 0.6 + saw(p2) * 0.6, cutoff).low * a * (j === 0 ? 0.28 : 0.1);
      },
      { gain: 0.75, pan: j === 0 ? 0 : -0.5 + (j - 1) * 0.25, rev: 0.4 },
    );
  });
}

// ---------- SFX from the cue list ----------
for (const s of CUES.sfx) {
  const g = s.gain ?? 1;
  switch (s.type) {
    case "impact":
      impact(s.t, g);
      break;
    case "subdrop":
      subdrop(s.t, g);
      break;
    case "whoosh":
      whoosh(s.t, g);
      break;
    case "swish":
      swish(s.t, g);
      break;
    case "tick":
      tick(s.t, g);
      break;
    case "snap":
      snap(s.t, g);
      break;
    case "sweep":
      sweep(s.t, g, s.dur ?? 2);
      break;
    case "riser":
      riser(s.t, g, s.dur ?? 1.5);
      break;
    case "spark":
      spark(s.t, g);
      break;
    case "chime":
      chime(s.t, g);
      break;
    default:
      throw new Error(`unknown sfx type ${s.type}`);
  }
}

// ---------- reverb (Schroeder/Freeverb-lite on the send bus) ----------
function reverb(input, offset) {
  const out = new Float32Array(N);
  const combs = [1557, 1617, 1491, 1422, 1277, 1356].map((d) => ({
    buf: new Float32Array(d + offset),
    i: 0,
    store: 0,
  }));
  const aps = [556, 441, 341].map((d) => ({ buf: new Float32Array(d + offset), i: 0 }));
  const fb = 0.8;
  const damp = 0.3;
  for (let n = 0; n < N; n++) {
    const x = input[n] * 0.12;
    let y = 0;
    for (const cb of combs) {
      const o = cb.buf[cb.i];
      cb.store = o * (1 - damp) + cb.store * damp;
      cb.buf[cb.i] = x + cb.store * fb;
      cb.i = (cb.i + 1) % cb.buf.length;
      y += o;
    }
    for (const ap of aps) {
      const o = ap.buf[ap.i];
      const v = y + o * 0.5;
      ap.buf[ap.i] = v;
      ap.i = (ap.i + 1) % ap.buf.length;
      y = o - v * 0.5;
    }
    out[n] = y;
  }
  return out;
}
const wetL = reverb(send[0], 0);
const wetR = reverb(send[1], 23);

// ---------- mix ----------
// Side-chain: the bed ducks on every kick and under each impact.
const duckTimes = CUES.sfx
  .filter((s) => s.type === "impact" || s.type === "subdrop")
  .map((s) => s.t);
function bedGain(t) {
  let g = 1;
  if (t >= CUES.beatStart && t < CUES.beatEnd) {
    const sinceBeat = (t - CUES.beatStart) % beat;
    g *= 1 - 0.45 * Math.exp(-sinceBeat * 9);
  }
  for (const d of duckTimes) if (t >= d && t < d + 0.6) g *= 1 - 0.5 * Math.exp(-(t - d) * 6);
  // Bed thins out under the riser.
  if (t >= c.riser && t < c.logo) g *= 1 - 0.75 * ((t - c.riser) / (c.logo - c.riser));
  return g;
}

const L = new Float32Array(N);
const R = new Float32Array(N);
for (let n = 0; n < N; n++) {
  const t = n / SR;
  const bg = bedGain(t) * 0.8;
  L[n] = music[0][n] * bg + sfx[0][n] + wetL[n];
  R[n] = music[1][n] * bg + sfx[1][n] + wetR[n];
}

// Gentle saturation, fades, then normalise to -1 dBFS.
const drive = 1.4;
const fadeIn = Math.round(0.004 * SR);
const fadeOut = Math.round(0.9 * SR);
let peak = 0;
for (let n = 0; n < N; n++) {
  let f = 1;
  if (n < fadeIn) f = n / fadeIn;
  if (n > N - fadeOut) f = Math.pow((N - n) / fadeOut, 1.5);
  L[n] = (Math.tanh(L[n] * drive) / Math.tanh(drive)) * f;
  R[n] = (Math.tanh(R[n] * drive) / Math.tanh(drive)) * f;
  peak = Math.max(peak, Math.abs(L[n]), Math.abs(R[n]));
}
const norm = Math.pow(10, -1 / 20) / (peak || 1);

// ---------- write WAV ----------
const data = Buffer.alloc(N * 4);
let sumSq = 0;
for (let n = 0; n < N; n++) {
  const l = L[n] * norm;
  const r = R[n] * norm;
  sumSq += l * l + r * r;
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l)) * 32767), n * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r)) * 32767), n * 4 + 2);
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + data.length, 4);
header.write("WAVE", 8);
header.write("fmt ", 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20); // PCM
header.writeUInt16LE(2, 22); // stereo
header.writeUInt32LE(SR, 24);
header.writeUInt32LE(SR * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(data.length, 40);
const out = join(HERE, "teaser-audio.wav");
writeFileSync(out, Buffer.concat([header, data]));
const rmsDb = 10 * Math.log10(sumSq / (2 * N));
console.log(
  `wrote ${out}: ${(N / SR).toFixed(3)}s, ${N} samples @ ${SR} Hz stereo 16-bit, RMS ${rmsDb.toFixed(1)} dBFS`,
);
