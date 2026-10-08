import { PROVIDERS, testProvider } from '../ai/providers';
import { DEFAULT_MODELS, ProviderId, getSettings, listCreations, saveCreation, saveSettings } from '../data/store';
import type { View } from '../router';
import { btn, layout } from '../ui/components';
import { download, h, toast } from '../ui/dom';

export const settingsView: View = (root) => {
  const s = getSettings();

  const name = h('input', { class: 'input', value: s.name, maxlength: 20 });
  name.addEventListener('change', () => saveSettings({ name: name.value.trim().slice(0, 20) || s.name }));
  const color = h('input', { type: 'color', value: s.color, style: 'width:56px;height:46px;border:0;background:none' });
  color.addEventListener('change', () => saveSettings({ color: color.value }));

  const cards = PROVIDERS.map((p) => {
    const radio = h('input', { type: 'radio', name: 'provider', value: p.id });
    radio.checked = s.provider === p.id;
    const body = h('div', { class: 'body' });
    if (p.keyHint) body.appendChild(h('p', { class: 'hint' }, p.keyHint, p.keyUrl ? h('span', null, ' ', h('a', { href: p.keyUrl, target: '_blank', rel: 'noopener noreferrer' }, 'Get a key →')) : null));
    if (p.id !== 'manual') {
      if (p.id === 'custom') {
        const base = h('input', { class: 'input', value: getSettings().customBase, placeholder: 'https://api.groq.com/openai/v1' });
        base.addEventListener('change', () => saveSettings({ customBase: base.value.trim() }));
        body.appendChild(h('label', { class: 'field' }, h('span', null, 'Base URL'), base));
      }
      const key = h('input', { class: 'input', type: 'password', autocomplete: 'off', value: getSettings().keys[p.id] ?? '', placeholder: 'API key' });
      key.addEventListener('change', () => saveSettings({ keys: { ...getSettings().keys, [p.id]: key.value.trim() } }));
      body.appendChild(h('label', { class: 'field' }, h('span', null, 'API key'), key));
      let model: HTMLInputElement | HTMLSelectElement;
      const current = getSettings().models[p.id] || DEFAULT_MODELS[p.id];
      if (p.models) {
        model = h('select', { class: 'input' }, ...p.models.map((m) => h('option', { value: m.id, selected: m.id === current }, m.label)));
      } else {
        model = h('input', { class: 'input', value: current, placeholder: 'model id' });
      }
      model.addEventListener('change', () => saveSettings({ models: { ...getSettings().models, [p.id]: model.value.trim() } }));
      body.appendChild(h('label', { class: 'field' }, h('span', null, 'Model'), model));
      const result = h('span', { class: 'hint' });
      body.appendChild(
        h(
          'div',
          { class: 'btn-row', style: 'align-items:center' },
          btn('Test connection', {
            class: 'small',
            onClick: async () => {
              saveSettings({ provider: p.id });
              result.textContent = 'Testing…';
              try {
                const reply = await testProvider(p.id);
                result.textContent = `✓ Works (“${reply.slice(0, 30)}”)`;
              } catch (err) {
                result.textContent = `✗ ${(err as Error).message}`;
              }
            },
          }),
          result,
        ),
      );
    }
    const card = h('label', { class: `provider ${radio.checked ? 'on' : ''}` }, h('div', { class: 'ph' }, radio, h('span', null, p.name), h('span', { class: 'spacer', style: 'flex:1' }), h('span', { class: 'pill' }, p.cost)), body);
    radio.addEventListener('change', () => {
      saveSettings({ provider: p.id as ProviderId });
      for (const c of root.querySelectorAll('.provider')) c.classList.remove('on');
      card.classList.add('on');
    });
    return card;
  });

  const sound = h('input', { type: 'checkbox' });
  sound.checked = s.sound;
  sound.addEventListener('change', () => saveSettings({ sound: sound.checked }));
  const touch = h(
    'select',
    { class: 'input' },
    h('option', { value: 'auto', selected: s.touch === 'auto' }, 'Automatic (on phones and tablets)'),
    h('option', { value: 'on', selected: s.touch === 'on' }, 'Always show'),
    h('option', { value: 'off', selected: s.touch === 'off' }, 'Never show'),
  );
  touch.addEventListener('change', () => saveSettings({ touch: touch.value as 'auto' | 'on' | 'off' }));

  const turnUrl = h('input', { class: 'input', value: s.turnUrl, placeholder: 'turn:your.server:3478 (optional)' });
  const turnUser = h('input', { class: 'input', value: s.turnUser, placeholder: 'username' });
  const turnPass = h('input', { class: 'input', type: 'password', value: s.turnPass, placeholder: 'password' });
  for (const el of [turnUrl, turnUser, turnPass]) el.addEventListener('change', () => saveSettings({ turnUrl: turnUrl.value.trim(), turnUser: turnUser.value.trim(), turnPass: turnPass.value }));

  const importInput = h('input', { type: 'file', accept: '.json,application/json', class: 'sr-only' });
  importInput.addEventListener('change', async () => {
    const f = importInput.files?.[0];
    if (!f) return;
    try {
      const data = JSON.parse(await f.text());
      const items = Array.isArray(data.creations) ? data.creations : [];
      for (const c of items) if (c && typeof c.id === 'string' && typeof c.html === 'string') await saveCreation(c);
      toast(`Imported ${items.length} games`);
    } catch {
      toast('Could not read that backup file');
    }
  });

  root.appendChild(
    layout(
      'settings',
      h('section', { class: 'hero' }, h('h1', null, 'Settings'), h('p', { class: 'lead' }, 'Everything is stored only on this device.')),
      h(
        'section',
        { class: 'card' },
        h('h2', null, 'You'),
        h('div', { style: 'display:flex;gap:10px;align-items:end' }, h('label', { class: 'field', style: 'flex:1;margin:0' }, h('span', null, 'Name in multiplayer'), name), color),
      ),
      h(
        'section',
        { class: 'card' },
        h('h2', null, 'AI for creating games'),
        h('p', { class: 'hint' }, 'Pick how new mashups are generated. Keys are saved in this browser only and sent directly to the provider you choose — never to Combiner. Games you play run in a sandbox that cannot read them.'),
        h('div', { class: 'provider-list' }, ...cards),
      ),
      h(
        'section',
        { class: 'card' },
        h('h2', null, 'Play'),
        h('label', { class: 'check', style: 'margin-bottom:14px' }, sound, 'Sound effects'),
        h('label', { class: 'field' }, h('span', null, 'On-screen controls'), touch),
      ),
      h(
        'section',
        { class: 'card' },
        h('h2', null, 'Multiplayer network'),
        h('p', { class: 'hint' }, 'Games connect players directly (peer-to-peer). If friends on strict mobile or school networks cannot join, add a TURN relay server here.'),
        h('label', { class: 'field' }, h('span', null, 'TURN server'), turnUrl),
        h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:10px' }, turnUser, turnPass),
      ),
      h(
        'section',
        { class: 'card' },
        h('h2', null, 'Your data'),
        h(
          'div',
          { class: 'btn-row' },
          btn('Back up my games', {
            icon: 'download',
            onClick: async () => download(`combiner-backup-${new Date().toISOString().slice(0, 10)}.json`, JSON.stringify({ v: 1, creations: await listCreations() }), 'application/json'),
          }),
          h('label', { class: 'btn', style: 'cursor:pointer' }, importInput, 'Restore backup'),
        ),
      ),
    ),
  );
};
