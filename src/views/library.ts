import { mashupInfo, parseMashupId } from '../data/mashups';
import { appUrl, decodeShare, encodeShare } from '../data/share';
import { Creation, deleteCreation, listCreations, newId, recentPlays, saveCreation } from '../data/store';
import { extractGame } from '../ai/extract';
import type { View } from '../router';
import { btn, layout, mashupCard } from '../ui/components';
import { download, h, modal, shareLink, timeAgo, toast } from '../ui/dom';

export const libraryView: View = async (root) => {
  const listEl = h('div', { class: 'list' });
  const fileInput = h('input', { type: 'file', accept: '.html,text/html', class: 'sr-only' });

  const render = async () => {
    const items = await listCreations();
    if (!items.length) {
      listEl.replaceChildren(
        h(
          'div',
          { class: 'empty-state card' },
          h('div', { class: 'emoji' }, '🎮'),
          h('p', null, 'Nothing here yet. Games you create with AI are saved on this device.'),
          btn('Create your first mashup', { class: 'primary', icon: 'sparkles', href: '#/create' }),
        ),
      );
      return;
    }
    listEl.replaceChildren(...items.map(row));
  };

  const row = (c: Creation) =>
    h(
      'div',
      { class: 'lrow' },
      h('div', { style: 'font-size:1.8rem' }, c.multiplayer ? '👥' : '✨'),
      h('div', { class: 'lmain' }, h('div', { class: 'name' }, c.title), h('div', { class: 'sub' }, `${c.games.join(' × ')} · ${timeAgo(c.updatedAt)} · ${(c.html.length / 1024).toFixed(0)} KB`)),
      btn('', { class: 'icon primary', icon: 'play', title: 'Play', href: `#/play/lib/${c.id}` }),
      btn('', { class: 'icon', icon: 'edit', title: 'Edit with AI', href: `#/create?edit=${c.id}` }),
      btn('', {
        class: 'icon',
        icon: 'share',
        title: 'Share link',
        onClick: async () => {
          const payload = await encodeShare({ v: 1, title: c.title, tagline: c.tagline, games: c.games, twist: c.twist, html: c.html, multiplayer: c.multiplayer });
          await shareLink(appUrl(`/s/${payload}`), c.title, `${c.title} — made with Combiner`);
        },
      }),
      btn('', { class: 'icon', icon: 'download', title: 'Download', onClick: () => download(`${c.title.replace(/[^\w-]+/g, '-').toLowerCase()}.html`, c.html) }),
      btn('', {
        class: 'icon danger',
        icon: 'trash',
        title: 'Delete',
        onClick: () => {
          const m = modal(
            h('h2', null, `Delete “${c.title}”?`),
            h('p', { class: 'hint' }, 'It is only stored on this device, so this cannot be undone. Share or download it first if you want to keep it.'),
            h(
              'div',
              { class: 'btn-row' },
              btn('Delete', {
                class: 'primary',
                onClick: async () => {
                  await deleteCreation(c.id);
                  m.close();
                  toast('Deleted');
                  await render();
                },
              }),
              btn('Cancel', { class: 'ghost', onClick: () => m.close() }),
            ),
          );
        },
      }),
    );

  fileInput.addEventListener('change', async () => {
    const f = fileInput.files?.[0];
    if (!f) return;
    const text = await f.text();
    const g = extractGame(text);
    if (!g.html) return toast('That file does not look like a game.');
    const now = Date.now();
    await saveCreation({
      id: newId(),
      title: g.title || f.name.replace(/\.html?$/i, ''),
      tagline: '',
      games: ['Imported', 'game'],
      twist: '',
      html: g.html,
      multiplayer: /Combiner\.net/.test(g.html),
      createdAt: now,
      updatedAt: now,
      history: [],
    });
    toast('Imported!');
    fileInput.value = '';
    await render();
  });

  const recent = recentPlays()
    .map(parseMashupId)
    .filter((p): p is { hero: string; world: string } => !!p)
    .slice(0, 8);

  root.appendChild(
    layout(
      'library',
      h('section', { class: 'hero' }, h('h1', null, 'My games'), h('p', { class: 'lead' }, 'Your AI creations live on this device. Share them as links — the whole game travels inside the link.')),
      h(
        'div',
        { class: 'btn-row', style: 'margin-bottom:14px' },
        btn('New mashup', { class: 'primary', icon: 'sparkles', href: '#/create' }),
        h('label', { class: 'btn', style: 'cursor:pointer' }, fileInput, 'Import .html'),
      ),
      listEl,
      recent.length
        ? h('section', null, h('h2', null, 'Recently played'), h('div', { class: 'grid' }, ...recent.map((p) => mashupCard(mashupInfo(p.hero, p.world)))))
        : null,
    ),
  );
  await render();
};

export const sharedView: View = async (root, route) => {
  const payload = route.path[1] ?? '';
  let game;
  try {
    game = await decodeShare(payload);
  } catch (err) {
    root.appendChild(layout('', h('div', { class: 'empty-state' }, h('div', { class: 'emoji' }, '🔗'), h('p', null, `This link is broken: ${(err as Error).message}`), btn('Home', { href: '#/' }))));
    return;
  }
  const g = game;
  const games = g.games ?? ['?', '?'];
  root.appendChild(
    layout(
      '',
      h(
        'section',
        { class: 'hero' },
        h('p', { class: 'pill' }, '🔗 Shared with you'),
        h('h1', { style: 'margin-top:12px' }, g.title),
        g.tagline ? h('p', { class: 'lead' }, g.tagline) : null,
        h('p', { class: 'hint' }, `A ${games.join(' × ')} mashup made with Combiner${g.multiplayer ? ' · multiplayer' : ''}.`),
        h(
          'div',
          { class: 'btn-row' },
          btn('Play', { class: 'primary', icon: 'play', href: `#/play/s/${payload}` }),
          btn('Save to my games', {
            icon: 'save',
            onClick: async () => {
              const now = Date.now();
              const id = newId();
              await saveCreation({ id, title: g.title, tagline: g.tagline ?? '', games: [games[0], games[1]], twist: g.twist ?? '', html: g.html, multiplayer: !!g.multiplayer, createdAt: now, updatedAt: now, history: [] });
              toast('Saved! You can now remix it with AI.');
              location.hash = `#/create?edit=${id}`;
            },
          }),
        ),
        h('p', { class: 'hint', style: 'margin-top:16px' }, '🛡️ Shared games run in a locked sandbox: they cannot see your saved games, settings or keys.'),
      ),
    ),
  );
};
