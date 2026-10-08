export interface Route {
  path: string[];
  query: URLSearchParams;
}

export function parseHash(hash = location.hash): Route {
  const raw = hash.replace(/^#\/?/, '');
  const q = raw.indexOf('?');
  const p = q >= 0 ? raw.slice(0, q) : raw;
  return {
    path: p
      .split('/')
      .filter(Boolean)
      .map((s) => {
        try {
          return decodeURIComponent(s);
        } catch {
          return s;
        }
      }),
    query: new URLSearchParams(q >= 0 ? raw.slice(q + 1) : ''),
  };
}

export function go(hash: string): void {
  if (location.hash === hash) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = hash;
}

/** A view renders into `root` and may return a cleanup function. */
export type View = (root: HTMLElement, route: Route) => void | (() => void) | Promise<void | (() => void)>;
