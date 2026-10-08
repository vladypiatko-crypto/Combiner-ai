import type { Input } from '../engine/types';

const KEYMAP: Record<string, keyof Input | 'left' | 'right' | 'down'> = {
  ArrowLeft: 'left',
  KeyA: 'left',
  ArrowRight: 'right',
  KeyD: 'right',
  ArrowUp: 'up',
  KeyW: 'up',
  ArrowDown: 'down',
  KeyS: 'down',
  Space: 'a',
  KeyZ: 'a',
  KeyK: 'a',
  Enter: 'a',
  KeyX: 'b',
  KeyJ: 'b',
  KeyC: 'c',
  KeyL: 'c',
  ShiftLeft: 'c',
};

/** Keyboard state for the built-in engine (arrows/WASD + Space/X/C). */
export class Keyboard {
  private down = new Set<string>();
  private onDown = (e: KeyboardEvent) => {
    const k = KEYMAP[e.code];
    if (!k) return;
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    e.preventDefault();
    this.down.add(k);
  };
  private onUp = (e: KeyboardEvent) => {
    const k = KEYMAP[e.code];
    if (k) this.down.delete(k);
  };
  private onBlur = () => this.down.clear();

  attach(): void {
    window.addEventListener('keydown', this.onDown);
    window.addEventListener('keyup', this.onUp);
    window.addEventListener('blur', this.onBlur);
  }

  detach(): void {
    window.removeEventListener('keydown', this.onDown);
    window.removeEventListener('keyup', this.onUp);
    window.removeEventListener('blur', this.onBlur);
    this.down.clear();
  }

  read(): Input {
    const d = this.down;
    return {
      x: (d.has('right') ? 1 : 0) - (d.has('left') ? 1 : 0),
      y: (d.has('down') ? 1 : 0) - (d.has('up') ? 1 : 0),
      a: d.has('a'),
      b: d.has('b'),
      c: d.has('c'),
      up: d.has('up'),
    };
  }
}

/** First connected gamepad, standard mapping. */
export function readGamepad(): Input | null {
  const pads = navigator.getGamepads?.() ?? [];
  for (const p of pads) {
    if (!p || !p.connected) continue;
    const b = (i: number) => !!p.buttons[i]?.pressed;
    let x = p.axes[0] ?? 0;
    let y = p.axes[1] ?? 0;
    if (b(14)) x = -1;
    if (b(15)) x = 1;
    if (b(12)) y = -1;
    if (b(13)) y = 1;
    return { x, y, a: b(0), b: b(2) || b(1), c: b(3) || b(5), up: false };
  }
  return null;
}

export function mergeInputs(...inputs: (Input | null | undefined)[]): Input {
  const out: Input = { x: 0, y: 0, a: false, b: false, c: false, up: false };
  for (const i of inputs) {
    if (!i) continue;
    out.x += i.x;
    out.y += i.y;
    out.a ||= i.a;
    out.b ||= i.b;
    out.c ||= i.c;
    out.up ||= i.up;
  }
  out.x = Math.max(-1, Math.min(1, out.x));
  out.y = Math.max(-1, Math.min(1, out.y));
  return out;
}
