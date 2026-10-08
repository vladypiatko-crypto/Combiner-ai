import { getSettings } from '../data/store';
import type { SfxName } from '../engine/types';

// Tiny WebAudio synth: no audio files to download.
let ctx: AudioContext | null = null;
let noise: AudioBuffer | null = null;

export function unlockAudio(): void {
  try {
    if (!ctx) ctx = new AudioContext();
    if (ctx.state === 'suspended') void ctx.resume();
  } catch {
    ctx = null;
  }
}

function tone(type: OscillatorType, f0: number, f1: number, dur: number, vol = 0.12, delay = 0): void {
  if (!ctx) return;
  const t = ctx.currentTime + delay;
  const o = ctx.createOscillator();
  const g = ctx.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ctx.destination);
  o.start(t);
  o.stop(t + dur + 0.02);
}

function hiss(dur: number, vol = 0.15, cutoff = 1800): void {
  if (!ctx) return;
  if (!noise) {
    noise = ctx.createBuffer(1, ctx.sampleRate * 0.5, ctx.sampleRate);
    const d = noise.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }
  const t = ctx.currentTime;
  const src = ctx.createBufferSource();
  src.buffer = noise;
  const f = ctx.createBiquadFilter();
  f.type = 'lowpass';
  f.frequency.value = cutoff;
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g).connect(ctx.destination);
  src.start(t);
  src.stop(t + dur);
}

let last: Partial<Record<SfxName, number>> = {};

export function sfx(name: SfxName): void {
  if (!ctx || !getSettings().sound) return;
  const now = performance.now();
  if (now - (last[name] ?? 0) < 45) return;
  last[name] = now;
  switch (name) {
    case 'jump':
      tone('square', 330, 660, 0.09, 0.06);
      break;
    case 'hit':
      tone('square', 220, 110, 0.06, 0.08);
      break;
    case 'hurt':
      tone('sawtooth', 320, 90, 0.25, 0.1);
      break;
    case 'pickup':
      tone('sine', 880, 1320, 0.07, 0.1);
      tone('sine', 1320, 1760, 0.07, 0.08, 0.06);
      break;
    case 'break':
      hiss(0.08, 0.12, 2500);
      break;
    case 'shoot':
      tone('square', 900, 260, 0.08, 0.05);
      break;
    case 'power':
      [523, 659, 784, 1047].forEach((f, i) => tone('triangle', f, f, 0.09, 0.08, i * 0.06));
      break;
    case 'boom':
      hiss(0.4, 0.25, 600);
      tone('sine', 120, 40, 0.35, 0.2);
      break;
    case 'place':
      tone('triangle', 260, 200, 0.05, 0.1);
      break;
    case 'shout':
      tone('sawtooth', 140, 70, 0.4, 0.12);
      hiss(0.35, 0.12, 900);
      break;
    case 'win':
      [523, 659, 784, 1047, 1319].forEach((f, i) => tone('square', f, f, 0.14, 0.06, i * 0.1));
      break;
    case 'lose':
      [392, 330, 262, 196].forEach((f, i) => tone('triangle', f, f * 0.98, 0.18, 0.1, i * 0.14));
      break;
  }
}

export function resetSfx(): void {
  last = {};
}
