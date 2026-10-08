// Combiner service worker: makes the app installable and playable offline.
// Hashed build assets are cache-first; the page itself is network-first so
// new deploys show up on the next visit. Cross-origin requests (AI providers,
// multiplayer signalling) are never touched.
const CACHE = 'combiner-v1';
const SHELL = ['./', './manifest.webmanifest', './icons/icon.svg', './icons/icon-192.png'];

// Cache the app shell plus the hashed JS/CSS that index.html points at, so the
// very first visit is enough to play offline afterwards.
self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      await cache.addAll(SHELL);
      const html = await (await cache.match('./')).text();
      const assets = [...html.matchAll(/(?:src|href)="(\.\/assets\/[^"]+)"/g)].map((m) => m[1]);
      await cache.addAll(assets);
    })(),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.includes('/assets/')) {
    event.respondWith(
      caches.match(req, { ignoreVary: true }).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok) caches.open(CACHE).then((c) => c.put(req, res.clone()));
            return res;
          }),
      ),
    );
    return;
  }

  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req, { ignoreVary: true }).then((hit) => hit || caches.match('./', { ignoreVary: true }))),
  );
});
