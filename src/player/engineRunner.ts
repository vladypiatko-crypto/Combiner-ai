import { Game } from '../engine/game';
import { renderGame, renderOverlay } from '../engine/render';
import type { GameEvent, Input } from '../engine/types';
import { h } from '../ui/dom';
import type { PadState } from './controls';
import { Keyboard, mergeInputs, readGamepad } from './input';
import { sfx } from './sfx';

export interface EngineRunnerOptions {
  heroId: string;
  worldId: string;
  seed?: number;
  aspect?: number;
  onEvent?: (e: GameEvent) => void;
}

/** Drives a Game on a canvas with a fixed 60 Hz simulation step. */
export class EngineRunner {
  game: Game;
  canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private kb = new Keyboard();
  private pad: PadState = { x: 0, y: 0, a: false, b: false, c: false };
  private raf = 0;
  private last = 0;
  private acc = 0;
  private paused = false;
  private ro: ResizeObserver;
  private onVis = () => {
    if (document.hidden) this.paused = true;
    else {
      this.paused = false;
      this.last = performance.now();
    }
  };

  constructor(
    private container: HTMLElement,
    opts: EngineRunnerOptions,
  ) {
    this.canvas = h('canvas', { 'aria-label': 'Game screen' });
    container.appendChild(this.canvas);
    this.ctx = this.canvas.getContext('2d', { alpha: false })!;
    const aspect = opts.aspect ?? (container.clientWidth && container.clientHeight ? container.clientWidth / container.clientHeight : 16 / 9);
    this.game = new Game({
      heroId: opts.heroId,
      worldId: opts.worldId,
      seed: opts.seed,
      aspect,
      onEvent: (e) => {
        if (e.type === 'sfx') sfx(e.name);
        opts.onEvent?.(e);
      },
    });
    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(container);
    this.resize();
    this.kb.attach();
    document.addEventListener('visibilitychange', this.onVis);
  }

  get aspect(): number {
    return this.game.aspect;
  }

  private resize(): void {
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    const w = Math.max(1, Math.round(this.container.clientWidth * dpr));
    const hh = Math.max(1, Math.round(this.container.clientHeight * dpr));
    if (this.canvas.width !== w || this.canvas.height !== hh) {
      this.canvas.width = w;
      this.canvas.height = hh;
    }
    this.draw();
  }

  setPad(s: PadState): void {
    this.pad = s;
  }

  start(): void {
    this.last = performance.now();
    const loop = (t: number) => {
      this.raf = requestAnimationFrame(loop);
      const dt = Math.min(0.1, (t - this.last) / 1000);
      this.last = t;
      if (this.paused) return;
      this.acc += dt;
      const input: Input = mergeInputs(this.kb.read(), readGamepad(), { ...this.pad, up: false });
      this.game.setInput(input);
      let steps = 0;
      while (this.acc >= 1 / 60 && steps < 5) {
        this.game.step(1 / 60);
        this.acc -= 1 / 60;
        steps++;
      }
      if (steps === 5) this.acc = 0;
      this.draw();
    };
    this.raf = requestAnimationFrame(loop);
  }

  pause(p: boolean): void {
    this.paused = p;
    this.last = performance.now();
  }

  private draw(): void {
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    renderGame(this.game, this.ctx, this.canvas.width, this.canvas.height, dpr);
    renderOverlay(this.game, this.ctx, this.canvas.width, this.canvas.height, dpr);
  }

  restart(seed?: number): void {
    this.game.reset(seed ?? this.game.seed);
    this.acc = 0;
  }

  destroy(): void {
    cancelAnimationFrame(this.raf);
    this.ro.disconnect();
    this.kb.detach();
    document.removeEventListener('visibilitychange', this.onVis);
    this.canvas.remove();
  }
}

/** Render a still frame of a mashup for cards and previews. */
export function drawThumb(canvas: HTMLCanvasElement, heroId: string, worldId: string): void {
  const w = canvas.width;
  const hh = canvas.height;
  const game = new Game({ heroId, worldId, aspect: w / hh });
  game.setInput({ x: 0.6, y: 0, a: false, b: false, c: false, up: false });
  for (let i = 0; i < 40; i++) game.step(1 / 60);
  game.parts = [];
  const ctx = canvas.getContext('2d', { alpha: false });
  if (!ctx) return;
  // Thumbnails are tiny: zoom in a bit more than the live game does.
  renderGame(game, ctx, w, hh, game.level.camera === 'fixed' ? 1 : Math.max(1, Math.min(w / 260, hh / 160)));
}
