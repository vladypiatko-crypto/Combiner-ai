import { FEATURED, allMashups, mashupInfo, parseMashupId, randomMashup } from '../data/mashups';
import { listCreations, recentPlays } from '../data/store';
import { BASE_GAMES, BASE, HEROES, WORLDS } from '../engine/registry';
import { go } from '../router';
import type { View } from '../router';
import { btn, layout, mashupCard, thumb } from '../ui/components';
import { h, timeAgo } from '../ui/dom';

/** The instant combiner: pick a hero game and a world game, play right away. */
export function fusionLab(initialHero = 'blockcraft', initialWorld = 'dragonrealm'): HTMLElement {
  let hero = initialHero;
  let world = initialWorld;
  const result = h('div', { class: 'lab-result' });
  const heroChips = h('div', { class: 'chips', role: 'radiogroup', 'aria-label': 'Play as' });
  const worldChips = h('div', { class: 'chips', role: 'radiogroup', 'aria-label': 'In the world of' });

  const chip = (id: string, kind: 'hero' | 'world') => {
    const g = BASE[id];
    const el = h(
      'button',
      {
        class: 'chip',
        type: 'button',
        role: 'radio',
        title: `${g.name} (inspired by ${g.inspiredBy})`,
        onClick: () => {
          if (kind === 'hero') hero = id;
          else world = id;
          update();
        },
      },
      h('span', { class: 'emoji' }, g.emoji),
      g.name,
    );
    el.dataset.id = id;
    return el;
  };
  for (const g of BASE_GAMES) {
    heroChips.appendChild(chip(g.id, 'hero'));
    worldChips.appendChild(chip(g.id, 'world'));
  }

  const update = () => {
    for (const el of heroChips.children) {
      const on = (el as HTMLElement).dataset.id === hero;
      el.classList.toggle('on', on);
      el.setAttribute('aria-checked', String(on));
    }
    for (const el of worldChips.children) {
      const on = (el as HTMLElement).dataset.id === world;
      el.classList.toggle('on', on);
      el.classList.toggle('cool', on);
      el.setAttribute('aria-checked', String(on));
    }
    const m = mashupInfo(hero, world);
    result.replaceChildren(
      h('a', { href: `#/m/${m.id}`, 'aria-label': `About ${m.title}` }, thumb(hero, world, 384, 216)),
      h(
        'div',
        null,
        h('div', { class: 'title' }, m.title),
        h('p', { style: 'color:var(--muted);margin-bottom:6px' }, m.subtitle),
        h('p', { class: 'hint' }, `${HEROES[hero].name}: ${HEROES[hero].verbs}. Goal: ${WORLDS[world].objective}.`),
        h(
          'div',
          { class: 'btn-row' },
          btn('Play now', { class: 'primary', icon: 'play', href: `#/play/${m.id}` }),
          btn('', {
            class: 'icon',
            icon: 'dice',
            title: 'Random mashup',
            onClick: () => {
              ({ hero, world } = randomMashup());
              update();
            },
          }),
          btn('Remix with AI', {
            class: 'ghost',
            icon: 'sparkles',
            href: `#/create?a=${encodeURIComponent(BASE[hero].inspiredBy)}&b=${encodeURIComponent(BASE[world].inspiredBy)}`,
          }),
        ),
      ),
    );
  };
  update();
  return h(
    'section',
    { class: 'card lab', id: 'lab' },
    h('div', null, h('div', { class: 'lab-label' }, 'Play as the hero from'), heroChips),
    h('div', null, h('div', { class: 'lab-label' }, 'In the world of'), worldChips),
    result,
  );
}

export const homeView: View = async (root) => {
  const featured = h(
    'div',
    { class: 'grid' },
    ...FEATURED.map((id) => parseMashupId(id))
      .filter(Boolean)
      .map((p) => mashupCard(mashupInfo(p!.hero, p!.world))),
  );
  const mine = h('div');
  const recent = h('div');

  root.appendChild(
    layout(
      'home',
      h(
        'section',
        { class: 'hero' },
        h('h1', null, 'Mash up ', h('span', { class: 'grad-text' }, 'any two games'), '.'),
        h(
          'p',
          { class: 'lead' },
          'Drop the hero of one game into the world of another and play it instantly — on your phone or PC. Free, no download, no account. Invite friends with a link, or describe any combo and let AI build it.',
        ),
        h(
          'div',
          { class: 'badges' },
          h('span', { class: 'pill ok' }, '100% free'),
          h('span', { class: 'pill' }, '📱 Phone + 💻 PC'),
          h('span', { class: 'pill' }, '64 instant mashups'),
          h('span', { class: 'pill' }, '👥 Multiplayer links'),
          h('span', { class: 'pill' }, '✨ AI creator'),
        ),
        h(
          'div',
          { class: 'btn-row' },
          btn('Combine now', {
            class: 'primary',
            icon: 'combine',
            onClick: () => document.getElementById('lab')?.scrollIntoView({ behavior: 'smooth', block: 'start' }),
          }),
          btn('Create with AI', { class: 'cool', icon: 'sparkles', href: '#/create' }),
        ),
      ),
      fusionLab(),
      recent,
      h('section', null, h('div', { class: 'section-head' }, h('h2', null, 'Featured mashups'), h('a', { href: '#/combine' }, 'See all 64 →')), featured),
      mine,
      h(
        'section',
        null,
        h('h2', null, 'How it works'),
        h(
          'div',
          { class: 'steps' },
          step(1, 'Pick two games', 'Choose whose hero you play and whose world you play in. Every combo works — 64 of them.'),
          step(
            2,
            'Play anywhere',
            'Runs in the browser with touch controls on phones and keyboard or gamepad on PC. Add it to your home screen to play offline.',
          ),
          step(
            3,
            'Create & share',
            'Describe any mashup — even real games like "Minecraft × Skyrim" — and AI builds a playable version. Share it with a link or play together.',
          ),
        ),
      ),
      h(
        'footer',
        { class: 'footer' },
        h(
          'p',
          null,
          'Combiner is free and open source. The built-in games are original homages; the famous games they nod to belong to their owners and are not affiliated with Combiner.',
        ),
      ),
    ),
  );

  const recentIds = recentPlays()
    .filter((id) => parseMashupId(id))
    .slice(0, 4);
  if (recentIds.length) {
    recent.replaceWith(
      h(
        'section',
        null,
        h('div', { class: 'section-head' }, h('h2', null, 'Jump back in')),
        h('div', { class: 'grid' }, ...recentIds.map((id) => parseMashupId(id)!).map((p) => mashupCard(mashupInfo(p.hero, p.world)))),
      ),
    );
  }

  const creations = await listCreations();
  if (creations.length) {
    mine.replaceWith(
      h(
        'section',
        null,
        h('div', { class: 'section-head' }, h('h2', null, 'Your creations'), h('a', { href: '#/library' }, 'Library →')),
        h(
          'div',
          { class: 'grid' },
          ...creations
            .slice(0, 4)
            .map((c) =>
              h(
                'a',
                { class: 'mcard', href: `#/play/lib/${c.id}` },
                h('div', { class: 'thumb ai' }, h('div', { class: 'ai', style: 'position:absolute;inset:0' }, '✨')),
                h(
                  'div',
                  { class: 'meta' },
                  h('div', { class: 'name' }, c.title),
                  h('div', { class: 'sub' }, `${c.games.join(' × ')} · ${timeAgo(c.updatedAt)}`),
                ),
              ),
            ),
        ),
      ),
    );
  }
};

function step(n: number, title: string, text: string): HTMLElement {
  return h('div', { class: 'card step' }, h('div', { class: 'num' }, String(n)), h('h3', null, title), h('p', { class: 'hint', style: 'margin:0' }, text));
}

export const combineView: View = (root) => {
  const groups = BASE_GAMES.map((g) =>
    h(
      'section',
      null,
      h('div', { class: 'section-head' }, h('h2', null, `${g.emoji} Play as the ${HEROES[g.id].name}`), h('p', null, `from ${g.name}`)),
      h(
        'div',
        { class: 'grid' },
        ...allMashups()
          .filter((m) => m.hero === g.id)
          .map(mashupCard),
      ),
    ),
  );
  root.appendChild(
    layout(
      'combine',
      h(
        'section',
        { class: 'hero' },
        h('h1', null, 'All mashups'),
        h('p', { class: 'lead' }, '8 games × 8 games = 64 playable mashups. Pick one, or roll the dice.'),
      ),
      h(
        'div',
        { class: 'btn-row', style: 'margin-bottom:16px' },
        btn('Random mashup', { class: 'primary', icon: 'dice', onClick: () => go(`#/play/${(({ hero, world }) => `${hero}-x-${world}`)(randomMashup())}`) }),
      ),
      fusionLab(),
      ...groups,
    ),
  );
};
