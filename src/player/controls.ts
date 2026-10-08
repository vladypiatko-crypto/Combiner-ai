import { getSettings } from '../data/store';
import { h } from '../ui/dom';

export interface PadState {
  x: number;
  y: number;
  a: boolean;
  b: boolean;
  c: boolean;
}

export interface PadLabels {
  a?: string;
  b?: string;
  c?: string;
}

export function wantsTouchControls(): boolean {
  const pref = getSettings().touch;
  if (pref === 'on') return true;
  if (pref === 'off') return false;
  return matchMedia('(pointer: coarse)').matches || navigator.maxTouchPoints > 0;
}

/**
 * On-screen gamepad: a floating joystick on the left half and up to three
 * action buttons on the right. Multi-touch via pointer events.
 */
export class TouchPad {
  el: HTMLElement;
  private state: PadState = { x: 0, y: 0, a: false, b: false, c: false };
  private stickId = -1;
  private origin = { x: 0, y: 0 };
  private base: HTMLElement;
  private knob: HTMLElement;
  private hint: HTMLElement;
  private btns: HTMLElement;

  constructor(
    labels: PadLabels,
    private onChange: (s: PadState) => void,
  ) {
    this.base = h('div', { class: 'stick-base', style: 'display:none' });
    this.knob = h('div', { class: 'stick-knob', style: 'display:none' });
    this.hint = h('div', { class: 'hint-text' }, 'drag to move');
    const zone = h('div', { class: 'zone' }, this.hint, this.base, this.knob);
    zone.addEventListener('pointerdown', (e) => this.stickDown(e, zone));
    zone.addEventListener('pointermove', (e) => this.stickMove(e));
    for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) zone.addEventListener(ev, (e) => this.stickUp(e));
    this.btns = h('div', { class: 'btns' });
    this.el = h('div', { class: 'pad' }, zone, this.btns);
    this.el.addEventListener('contextmenu', (e) => e.preventDefault());
    this.setLabels(labels);
  }

  setLabels(labels: PadLabels): void {
    this.btns.replaceChildren();
    for (const k of ['a', 'b', 'c'] as const) {
      const label = labels[k];
      if (!label) continue;
      const b = h('div', { class: `pbtn ${k}`, role: 'button', 'aria-label': label }, label);
      const set = (v: boolean) => {
        if (this.state[k] === v) return;
        this.state[k] = v;
        b.classList.toggle('down', v);
        if (v && navigator.vibrate) navigator.vibrate(8);
        this.onChange({ ...this.state });
      };
      b.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        b.setPointerCapture(e.pointerId);
        set(true);
      });
      for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) b.addEventListener(ev, () => set(false));
      this.btns.appendChild(b);
    }
  }

  private stickDown(e: PointerEvent, zone: HTMLElement): void {
    if (this.stickId !== -1) return;
    e.preventDefault();
    this.stickId = e.pointerId;
    zone.setPointerCapture(e.pointerId);
    const r = zone.getBoundingClientRect();
    this.origin = { x: e.clientX - r.left, y: e.clientY - r.top };
    for (const el of [this.base, this.knob]) {
      el.style.display = 'block';
      el.style.left = `${this.origin.x}px`;
      el.style.top = `${this.origin.y}px`;
    }
    this.hint.style.display = 'none';
    this.zoneRect = r;
  }

  private zoneRect: DOMRect | null = null;

  private stickMove(e: PointerEvent): void {
    if (e.pointerId !== this.stickId || !this.zoneRect) return;
    const R = 46;
    let dx = e.clientX - this.zoneRect.left - this.origin.x;
    let dy = e.clientY - this.zoneRect.top - this.origin.y;
    const d = Math.hypot(dx, dy);
    if (d > R) {
      dx = (dx / d) * R;
      dy = (dy / d) * R;
    }
    this.knob.style.left = `${this.origin.x + dx}px`;
    this.knob.style.top = `${this.origin.y + dy}px`;
    this.state.x = dx / R;
    this.state.y = dy / R;
    this.onChange({ ...this.state });
  }

  private stickUp(e: PointerEvent): void {
    if (e.pointerId !== this.stickId) return;
    this.stickId = -1;
    this.base.style.display = 'none';
    this.knob.style.display = 'none';
    this.state.x = 0;
    this.state.y = 0;
    this.onChange({ ...this.state });
  }

  read(): PadState {
    return { ...this.state };
  }
}
