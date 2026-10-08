import { MashupInfo } from '../data/mashups';
import { BASE } from '../engine/registry';
import { drawThumb } from '../player/engineRunner';
import { Child, h, svg } from './dom';
import { icons } from './icons';

const queue: (() => void)[] = [];
let pumping = false;

function pump(): void {
  if (pumping) return;
  pumping = true;
  const run = () => {
    const job = queue.shift();
    if (!job) {
      pumping = false;
      return;
    }
    job();
    // Spread thumbnail rendering over frames so scrolling stays smooth.
    if ('requestIdleCallback' in window) requestIdleCallback(run, { timeout: 200 });
    else setTimeout(run, 16);
  };
  run();
}

const observer =
  typeof IntersectionObserver !== 'undefined'
    ? new IntersectionObserver(
        (entries) => {
          for (const e of entries) {
            if (!e.isIntersecting) continue;
            observer!.unobserve(e.target);
            const fn = (e.target as HTMLElement & { _draw?: () => void })._draw;
            if (fn) {
              queue.push(fn);
              pump();
            }
          }
        },
        { rootMargin: '200px' },
      )
    : null;

/** A live-rendered still of a mashup, drawn lazily when scrolled into view. */
export function thumb(hero: string, world: string, w = 320, hh = 200): HTMLElement {
  const canvas = h('canvas', { width: w, height: hh });
  const box = h('div', { class: 'thumb' }, canvas, h('span', { class: 'tag' }, `${BASE[hero].emoji}${BASE[world].emoji}`));
  const draw = () => {
    try {
      drawThumb(canvas, hero, world);
    } catch (err) {
      console.warn('thumb failed', err);
    }
  };
  if (observer) {
    (box as HTMLElement & { _draw?: () => void })._draw = draw;
    observer.observe(box);
  } else draw();
  return box;
}

export function mashupCard(m: MashupInfo): HTMLElement {
  return h(
    'a',
    { class: 'mcard', href: `#/m/${m.id}` },
    thumb(m.hero, m.world),
    h('div', { class: 'meta' }, h('div', { class: 'name' }, m.title), h('div', { class: 'sub' }, m.subtitle)),
  );
}

export function icon(name: keyof typeof icons): SVGElement {
  return svg(icons[name]);
}

export function btn(label: Child, opts: { class?: string; icon?: keyof typeof icons; onClick?: (e: MouseEvent) => void; href?: string; title?: string } = {}): HTMLElement {
  const content = [opts.icon ? icon(opts.icon) : null, label];
  if (opts.href) return h('a', { class: `btn ${opts.class ?? ''}`, href: opts.href, title: opts.title }, ...content);
  return h('button', { class: `btn ${opts.class ?? ''}`, type: 'button', onClick: opts.onClick, title: opts.title, 'aria-label': opts.title }, ...content);
}

export function layout(active: string, ...content: Child[]): HTMLElement {
  const nav = (href: string, key: string, label: string, ic: keyof typeof icons) =>
    h('a', { href, class: active === key ? 'active' : '' }, icon(ic), h('span', null, label));
  const top = (href: string, key: string, label: string) => h('a', { href, class: active === key ? 'active' : '' }, label);
  return h(
    'div',
    { class: 'app' },
    h(
      'header',
      { class: 'topbar' },
      h(
        'div',
        { class: 'wrap' },
        h('a', { class: 'logo', href: '#/' }, h('img', { src: './icons/icon.svg', alt: '' }), 'Combiner'),
        h('nav', { class: 'topnav' }, top('#/', 'home', 'Play'), top('#/combine', 'combine', 'All mashups'), top('#/create', 'create', 'Create with AI'), top('#/library', 'library', 'My games')),
        h('div', { class: 'spacer' }),
        h('a', { class: 'btn icon ghost', href: '#/settings', title: 'Settings', 'aria-label': 'Settings' }, icon('settings')),
      ),
    ),
    h('main', { class: 'wrap' }, ...content),
    h(
      'nav',
      { class: 'tabbar' },
      nav('#/', 'home', 'Play', 'home'),
      nav('#/combine', 'combine', 'Mashups', 'combine'),
      nav('#/create', 'create', 'Create', 'sparkles'),
      nav('#/library', 'library', 'My games', 'library'),
    ),
  );
}
