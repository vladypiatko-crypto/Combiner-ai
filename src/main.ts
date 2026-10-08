import './styles.css';
import { parseHash } from './router';
import type { View } from './router';
import { btn, layout } from './ui/components';
import { clear, h } from './ui/dom';
import { combineView, homeView } from './views/home';
import { mashupView } from './views/mashup';
import { joinView, playView } from './views/play';
import { createView } from './views/create';
import { libraryView, sharedView } from './views/library';
import { settingsView } from './views/settings';

const routes: Record<string, View> = {
  '': homeView,
  combine: combineView,
  m: mashupView,
  play: playView,
  join: joinView,
  create: createView,
  library: libraryView,
  settings: settingsView,
  s: sharedView,
};

const app = document.getElementById('app')!;
let cleanup: (() => void) | void;
let renderId = 0;

async function render(): Promise<void> {
  const id = ++renderId;
  try {
    cleanup?.();
  } catch (err) {
    console.error(err);
  }
  cleanup = undefined;
  clear(app);
  const route = parseHash();
  const view = routes[route.path[0] ?? ''];
  if (!view) {
    app.appendChild(layout('', h('div', { class: 'empty-state' }, h('div', { class: 'emoji' }, '🧭'), h('p', null, 'Page not found.'), btn('Home', { href: '#/', class: 'primary' }))));
    return;
  }
  const fullscreen = route.path[0] === 'play' || route.path[0] === 'join';
  document.body.style.overflow = fullscreen ? 'hidden' : '';
  if (!fullscreen) window.scrollTo(0, 0);
  try {
    const result = await view(app, route);
    if (id !== renderId) {
      // The user navigated away while this view was loading.
      if (typeof result === 'function') result();
      return;
    }
    cleanup = result;
  } catch (err) {
    console.error(err);
    app.appendChild(h('div', { class: 'wrap' }, h('p', { class: 'err' }, `Something broke: ${(err as Error).message}`), btn('Home', { href: '#/' })));
  }
}

window.addEventListener('hashchange', () => void render());
void render();

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  });
}
