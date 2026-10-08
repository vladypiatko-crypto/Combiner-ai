import { h } from '../ui/dom';
import type { PadLabels, PadState } from './controls';
import { SDK_SOURCE } from './sdk';

export interface ControlsMeta {
  /** True when the game wants raw touches instead of the on-screen pad. */
  touch: boolean;
  labels: PadLabels;
}

/** Read `<meta name="combiner-controls" content="a:Jump b:Fire">` from a game. */
export function parseControls(html: string): ControlsMeta {
  const m = /<meta[^>]+name=["']combiner-controls["'][^>]*>/i.exec(html);
  const content = m ? (/content=["']([^"']*)["']/i.exec(m[0])?.[1] ?? '') : '';
  const tokens = content.trim().split(/\s+/).filter(Boolean);
  const buttons = tokens.map((t) => /^([abc]):(.+)$/i.exec(t)).filter((m): m is RegExpExecArray => !!m);
  if (tokens.some((t) => t.toLowerCase() === 'touch') && !buttons.length) return { touch: true, labels: {} };
  const labels: PadLabels = {};
  for (const m of buttons) labels[m[1].toLowerCase() as 'a' | 'b' | 'c'] = m[2].replace(/_/g, ' ').slice(0, 10);
  if (!labels.a && !labels.b && !labels.c) labels.a = 'A';
  return { touch: false, labels };
}

/** Insert the Combiner SDK as the very first script of the document. */
export function injectSdk(html: string): string {
  // One line, so error line numbers still match the game's own source.
  const tag = `<script>${SDK_SOURCE.replace(/\s*\n\s*/g, ' ')}</script>`;
  const viewport = /<meta[^>]+name=["']viewport["']/i.test(html)
    ? ''
    : '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">';
  const head = /<head[^>]*>/i.exec(html);
  if (head) return html.slice(0, head.index + head[0].length) + viewport + tag + html.slice(head.index + head[0].length);
  const root = /<html[^>]*>/i.exec(html);
  if (root) return html.slice(0, root.index + root[0].length) + `<head>${viewport}${tag}</head>` + html.slice(root.index + root[0].length);
  return `<!doctype html><html><head><meta charset="utf-8">${viewport}${tag}</head><body>${html}</body></html>`;
}

export interface SandboxEvents {
  onError?: (message: string, line: number) => void;
  onNetSend?: (data: unknown) => void;
  onScore?: (score: number) => void;
  onOver?: (won: boolean, score: number) => void;
  onReady?: () => void;
}

/**
 * Runs untrusted game HTML in an iframe with `sandbox="allow-scripts"` only.
 * Without `allow-same-origin` the game gets an opaque origin: it cannot read
 * this app's localStorage (API keys), cookies or IndexedDB.
 */
export class SandboxRunner {
  iframe: HTMLIFrameElement;
  private listener: (e: MessageEvent) => void;
  private lastInput = '';

  constructor(
    container: HTMLElement,
    html: string,
    private events: SandboxEvents = {},
  ) {
    this.iframe = h('iframe', {
      title: 'Game',
      sandbox: 'allow-scripts allow-pointer-lock',
      allow: 'autoplay *; gamepad *; fullscreen *',
      referrerpolicy: 'no-referrer',
    });
    this.iframe.srcdoc = injectSdk(html);
    this.listener = (e: MessageEvent) => {
      if (e.source !== this.iframe.contentWindow) return;
      const m = e.data;
      if (!m || m.__cmb !== 1) return;
      if (m.type === 'error') this.events.onError?.(String(m.message), Number(m.line) || 0);
      else if (m.type === 'net-send') this.events.onNetSend?.(m.data);
      else if (m.type === 'score') this.events.onScore?.(Number(m.score) || 0);
      else if (m.type === 'over') this.events.onOver?.(!!m.won, Number(m.score) || 0);
      else if (m.type === 'ready') this.events.onReady?.();
    };
    window.addEventListener('message', this.listener);
    container.appendChild(this.iframe);
    this.iframe.addEventListener('load', () => this.focus());
  }

  private post(msg: Record<string, unknown>): void {
    this.iframe.contentWindow?.postMessage({ __cmb: 1, ...msg }, '*');
  }

  sendInput(s: PadState): void {
    const key = `${s.x.toFixed(2)},${s.y.toFixed(2)},${+s.a}${+s.b}${+s.c}`;
    if (key === this.lastInput) return;
    this.lastInput = key;
    this.post({ type: 'input', state: s });
  }

  deliverNet(from: string, data: unknown): void {
    this.post({ type: 'net', from, data });
  }

  setPlayers(players: { id: string; name: string; color: string }[], me: string, isHost: boolean): void {
    this.post({ type: 'players', players, me, isHost });
  }

  focus(): void {
    try {
      this.iframe.focus();
      this.iframe.contentWindow?.focus();
    } catch {
      /* ignore */
    }
  }

  destroy(): void {
    window.removeEventListener('message', this.listener);
    this.iframe.remove();
  }
}
