import { allMashups, mashupInfo, parseMashupId } from '../data/mashups';
import { appUrl } from '../data/share';
import { bestScores } from '../data/store';
import { ABILITY_LABEL } from '../engine/types';
import { BASE, HEROES, WORLDS } from '../engine/registry';
import type { View } from '../router';
import { btn, icon, layout, mashupCard, thumb } from '../ui/components';
import { formatTime, h, shareLink } from '../ui/dom';

const KEYS = ['Space', 'X', 'C'];

export const mashupView: View = (root, route) => {
  const p = parseMashupId(route.path[1] ?? '');
  if (!p) {
    root.appendChild(layout('', h('div', { class: 'empty-state' }, h('div', { class: 'emoji' }, '🤔'), h('p', null, 'That mashup does not exist.'), btn('Back home', { href: '#/' }))));
    return;
  }
  const { hero, world } = p;
  const m = mashupInfo(hero, world);
  const hd = HEROES[hero];
  const wd = WORLDS[world];
  const buttons = hd.buttons[wd.view];
  const best = bestScores()[m.id];

  const controls = h(
    'dl',
    { class: 'kv' },
    h('dt', null, 'Move'),
    h('dd', null, h('kbd', null, '←↑↓→'), ' / ', h('kbd', null, 'WASD'), ' or the on-screen stick'),
    ...buttons.flatMap((ab, i) => (ab ? [h('dt', null, ABILITY_LABEL[ab]), h('dd', null, h('kbd', null, KEYS[i]), ` or the ${'ABC'[i]} button`)] : [])),
  );

  const related = allMashups()
    .filter((x) => x.id !== m.id && (x.hero === hero || x.world === world))
    .sort(() => Math.random() - 0.5)
    .slice(0, 4);

  root.appendChild(
    layout(
      '',
      h('a', { class: 'back', href: '#/combine' }, icon('back'), 'All mashups'),
      h(
        'div',
        { class: 'detail' },
        h('a', { href: `#/play/${m.id}`, 'aria-label': `Play ${m.title}` }, thumb(hero, world, 640, 400)),
        h(
          'div',
          null,
          h('h1', { style: 'font-size:2.2rem' }, m.title),
          h('p', { style: 'color:var(--muted);font-weight:700' }, m.subtitle),
          h(
            'div',
            { class: 'badges', style: 'display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px' },
            h('span', { class: 'pill' }, `${BASE[hero].emoji} hero from ${BASE[hero].name}`),
            h('span', { class: 'pill' }, `${BASE[world].emoji} world of ${BASE[world].name}`),
            best ? h('span', { class: 'pill ok' }, `🏆 best ${best.score} in ${formatTime(best.time)}`) : null,
          ),
          h('p', null, m.pitch),
          h('p', { class: 'hint' }, `Inspired by ${BASE[hero].inspiredBy} × ${BASE[world].inspiredBy}. The ${hd.name.toLowerCase()} can ${hd.verbs}.`),
          h(
            'div',
            { class: 'btn-row', style: 'margin:16px 0' },
            btn('Play', { class: 'primary', icon: 'play', href: `#/play/${m.id}` }),
            btn('Play with friends', { class: 'cool', icon: 'users', href: `#/play/${m.id}?host=1` }),
            btn('Remix with AI', {
              icon: 'sparkles',
              href: `#/create?a=${encodeURIComponent(BASE[hero].inspiredBy)}&b=${encodeURIComponent(BASE[world].inspiredBy)}&twist=${encodeURIComponent(`Play ${BASE[world].inspiredBy}'s world as the ${BASE[hero].inspiredBy} hero`)}`,
            }),
            btn('', { class: 'icon', icon: 'share', title: 'Share', onClick: () => void shareLink(appUrl(`/m/${m.id}`), m.title, `${m.title}: ${m.subtitle}`) }),
          ),
          h('div', { class: 'card' }, h('h3', null, 'Goal'), h('p', null, wd.objective), h('h3', null, 'Controls'), controls),
        ),
      ),
      related.length
        ? h('section', null, h('h2', null, 'More like this'), h('div', { class: 'grid' }, ...related.map(mashupCard)))
        : null,
    ),
  );
};
