import { extractGame } from '../ai/extract';
import { IDEAS, SUGGESTED_GAMES, assistantEcho, fixPrompt, manualPrompt, refinePrompt, systemPrompt, userPrompt, type ChatMessage, type MashupRequest } from '../ai/prompt';
import { generate, providerInfo, providerReady } from '../ai/providers';
import { appUrl, encodeShare } from '../data/share';
import { Creation, getCreation, getSettings, modelFor, newId, saveCreation } from '../data/store';
import { SandboxRunner } from '../player/sandbox';
import { go } from '../router';
import type { View } from '../router';
import { btn, layout } from '../ui/components';
import { copyText, download, h, nodes, shareLink, toast } from '../ui/dom';

const CHATBOTS: [string, string][] = [
  ['ChatGPT', 'https://chatgpt.com/'],
  ['Gemini', 'https://gemini.google.com/app'],
  ['Claude', 'https://claude.ai/new'],
  ['DeepSeek', 'https://chat.deepseek.com/'],
  ['Copilot', 'https://copilot.microsoft.com/'],
];

export const createView: View = async (root, route) => {
  const q = route.query;
  const editId = q.get('edit');
  let draft: Creation | null = editId ? ((await getCreation(editId)) ?? null) : null;
  let runner: SandboxRunner | null = null;
  let abort: AbortController | null = null;
  let lastError = '';

  // ------------------------------------------------------------------ form
  const list = h('datalist', { id: 'games-list' }, ...SUGGESTED_GAMES.map((g) => h('option', { value: g })));
  const gameA = h('input', { class: 'input', list: 'games-list', placeholder: 'e.g. Minecraft', value: draft?.games[0] ?? q.get('a') ?? '', maxlength: 80 });
  const gameB = h('input', { class: 'input', list: 'games-list', placeholder: 'e.g. Skyrim', value: draft?.games[1] ?? q.get('b') ?? '', maxlength: 80 });
  const twist = h('textarea', { class: 'input', placeholder: 'Optional: how should they combine? e.g. "Play Skyrim as a Minecraft player: mine, build and fight dragons"', maxlength: 600 });
  twist.value = draft?.twist ?? q.get('twist') ?? '';
  const multi = h('input', { type: 'checkbox' });
  multi.checked = draft?.multiplayer ?? false;

  const request = (): MashupRequest | null => {
    const a = gameA.value.trim();
    const b = gameB.value.trim();
    if (!a || !b) {
      toast('Name two games first');
      (a ? gameB : gameA).focus();
      return null;
    }
    return { a, b, twist: twist.value, multiplayer: multi.checked };
  };

  const ideas = h(
    'div',
    { class: 'ideas' },
    ...IDEAS.map(([a, b, t]) =>
      h(
        'button',
        {
          type: 'button',
          onClick: () => {
            gameA.value = a;
            gameB.value = b;
            twist.value = t;
          },
        },
        `${a} × ${b}`,
      ),
    ),
  );

  const settings = getSettings();
  const pinfo = providerInfo(settings.provider);
  const ready = providerReady(settings.provider);
  const providerLine = h(
    'p',
    { class: 'hint', style: 'margin:8px 0 14px' },
    'AI: ',
    h('strong', null, pinfo.name),
    settings.provider !== 'manual' ? ` · ${modelFor(settings.provider)}` : '',
    !ready ? h('span', { class: 'err' }, ' · needs a key') : '',
    ' · ',
    h('a', { href: '#/settings' }, 'change'),
  );

  // ------------------------------------------------------------------ preview + progress
  const preview = h('div', { class: 'preview' });
  const status = h('div', { class: 'progress' });
  const result = h('div');
  const refineInput = h('textarea', { class: 'input', placeholder: 'Change something: "make it harder", "add a boss", "use pixel art", "add a double jump"…', style: 'min-height:70px' });

  const showEmpty = () => {
    preview.replaceChildren(
      h(
        'div',
        { class: 'empty' },
        h('div', null, h('div', { style: 'font-size:3rem' }, '✨'), h('p', null, 'Your mashup will appear here.'), h('p', { class: 'hint' }, 'Pick two games, add a twist and hit Generate.')),
      ),
    );
  };

  const mount = (html: string) => {
    runner?.destroy();
    preview.replaceChildren();
    lastError = '';
    runner = new SandboxRunner(preview, html, {
      onError: (message, line) => {
        lastError = `${message}${line ? ` (line ${line})` : ''}`;
        renderResult();
      },
    });
  };

  const renderResult = () => {
    if (!draft) {
      result.replaceChildren();
      return;
    }
    const d = draft;
    result.replaceChildren(
      ...nodes(
      h('h2', { style: 'margin-top:14px' }, d.title),
      d.tagline ? h('p', { style: 'color:var(--muted)' }, d.tagline) : null,
      lastError
        ? h(
            'div',
            { class: 'card', style: 'border-color:var(--bad);margin-bottom:12px' },
            h('p', { class: 'err', style: 'margin:0 0 8px' }, `⚠️ ${lastError}`),
            btn('Fix with AI', { class: 'small primary', icon: 'wand', onClick: () => void runAI('fix', fixPrompt(lastError)) }),
          )
        : null,
      h(
        'div',
        { class: 'btn-row', style: 'margin-bottom:14px' },
        btn('Play fullscreen', { class: 'primary', icon: 'play', href: `#/play/lib/${d.id}` }),
        d.multiplayer ? btn('Play with friends', { class: 'cool', icon: 'users', href: `#/play/lib/${d.id}?host=1` }) : null,
        btn('Share link', {
          icon: 'share',
          onClick: async () => {
            const payload = await encodeShare({ v: 1, title: d.title, tagline: d.tagline, games: d.games, twist: d.twist, html: d.html, multiplayer: d.multiplayer });
            const url = appUrl(`/s/${payload}`);
            if (url.length > 60000) toast('Heads up: this game is big, some chat apps may cut the link. Download the file instead.', 4000);
            await shareLink(url, d.title, `${d.title} — a ${d.games.join(' × ')} mashup made with Combiner`);
          },
        }),
        btn('', { class: 'icon', icon: 'download', title: 'Download .html', onClick: () => download(`${d.title.replace(/[^\w-]+/g, '-').toLowerCase() || 'mashup'}.html`, d.html) }),
        d.history?.length
          ? btn('Undo', {
              icon: 'refresh',
              class: 'ghost',
              onClick: async () => {
                const prev = d.history!.shift()!;
                d.html = prev;
                await saveCreation(d);
                mount(d.html);
                renderResult();
              },
            })
          : null,
      ),
      h('label', { class: 'field' }, h('span', null, 'Refine it'), refineInput),
      btn('Apply change', {
        icon: 'wand',
        onClick: () => {
          if (!refineInput.value.trim()) return refineInput.focus();
          void runAI('refine', refinePrompt(refineInput.value));
        },
      }),
      ),
    );
  };

  // ------------------------------------------------------------------ generation
  const setBusy = (busy: boolean) => {
    for (const b of root.querySelectorAll<HTMLButtonElement>('button[data-gen]')) b.disabled = busy;
  };

  const finish = async (text: string, req: MashupRequest, mode: 'new' | 'refine' | 'fix' | 'manual') => {
    const g = extractGame(text);
    if (!g.html) {
      status.replaceChildren(h('p', { class: 'err' }, 'The AI reply did not contain a game. Try again, or pick another model in Settings.'));
      return;
    }
    const now = Date.now();
    if (!draft || mode === 'new' || mode === 'manual') {
      draft = {
        id: newId(),
        title: g.title || `${req.a} × ${req.b}`,
        tagline: g.tagline || '',
        games: [req.a, req.b],
        twist: req.twist,
        html: g.html,
        multiplayer: req.multiplayer,
        provider: mode === 'manual' ? 'manual' : getSettings().provider,
        model: mode === 'manual' ? undefined : modelFor(getSettings().provider),
        createdAt: now,
        updatedAt: now,
        history: [],
      };
    } else {
      draft.history = [draft.html, ...(draft.history ?? [])].slice(0, 5);
      draft.html = g.html;
      if (g.title) draft.title = g.title;
      if (g.tagline) draft.tagline = g.tagline;
    }
    await saveCreation(draft);
    history.replaceState(null, '', `#/create?edit=${draft.id}`);
    status.replaceChildren(
      h(
        'p',
        { style: 'color:var(--ok);font-weight:700' },
        g.complete ? '✓ Saved to your library.' : '⚠️ The reply was cut off before the end — the game may not work. Try “Refine: finish the code” or another model.',
      ),
    );
    refineInput.value = '';
    mount(draft.html);
    renderResult();
  };

  const runAI = async (mode: 'new' | 'refine' | 'fix', followUp?: string) => {
    const req = draft && mode !== 'new' ? { a: draft.games[0], b: draft.games[1], twist: draft.twist, multiplayer: draft.multiplayer } : request();
    if (!req) return;
    const s = getSettings();
    if (s.provider === 'manual') {
      if (mode === 'new') return void copyManual();
      const text = `${manualPrompt(req)}\n\n---\n\nHere is the current game:\n${assistantEcho(draft!.title, draft!.tagline, draft!.html)}\n\n${followUp}`;
      toast((await copyText(text)) ? 'Prompt with your game copied — paste it into a chatbot, then paste the answer below.' : 'Copy failed', 4000);
      manualBox.open = true;
      return;
    }
    if (!providerReady(s.provider)) {
      toast('Add an API key first (or switch to free copy & paste mode).', 3500);
      go('#/settings');
      return;
    }
    const messages: ChatMessage[] = [{ role: 'user', content: userPrompt(req) }];
    if (draft && mode !== 'new') {
      messages.push({ role: 'assistant', content: assistantEcho(draft.title, draft.tagline, draft.html) });
      messages.push({ role: 'user', content: followUp! });
    }
    abort = new AbortController();
    const ctrl = abort;
    let text = '';
    let thinking = '';
    const statusLine = h('span', null, mode === 'new' ? 'Designing your mashup…' : 'Updating the game…');
    const thinkingEl = h('div', { class: 'thinking' });
    status.replaceChildren(
      h('div', { style: 'display:flex;gap:10px;align-items:center' }, h('div', { class: 'spinner' }), statusLine, h('div', { class: 'spacer', style: 'flex:1' }), btn('Cancel', { class: 'small ghost', onClick: () => ctrl.abort() })),
      thinkingEl,
    );
    setBusy(true);
    const started = performance.now();
    try {
      await generate(s.provider, {
        system: systemPrompt(req.multiplayer),
        messages,
        signal: ctrl.signal,
        onText: (d) => {
          text += d;
          const kb = (text.length / 1024).toFixed(1);
          const g = extractGame(text);
          statusLine.textContent = g.html ? `Writing ${g.title ? `“${g.title}”` : 'the game'}… ${kb} KB` : `Planning… ${kb} KB`;
        },
        onThinking: (d) => {
          thinking = (thinking + d).slice(-400);
          thinkingEl.textContent = thinking;
        },
      });
      await finish(text, req, mode);
      const secs = Math.round((performance.now() - started) / 1000);
      toast(`Done in ${secs}s`);
    } catch (err) {
      if (ctrl.signal.aborted) {
        status.replaceChildren(h('p', { class: 'hint' }, 'Cancelled.'));
        if (text) await finish(text, req, mode);
      } else {
        status.replaceChildren(h('p', { class: 'err' }, (err as Error).message || 'Something went wrong.'));
      }
    } finally {
      setBusy(false);
      abort = null;
    }
  };

  // ------------------------------------------------------------------ copy & paste mode
  const pasteArea = h('textarea', { class: 'input', placeholder: 'Paste the chatbot’s whole answer (or just the HTML) here…', style: 'min-height:120px' });
  const manualBox = h(
    'details',
    { class: 'card', style: 'margin-top:14px' },
    h('summary', { style: 'cursor:pointer;font-weight:800' }, '📋 Free mode: use any chatbot'),
    h('p', { class: 'hint', style: 'margin-top:10px' }, '1. Copy the prompt. 2. Paste it into a free chatbot. 3. Paste its answer here and press Load.'),
    h('div', { class: 'btn-row', style: 'margin-bottom:10px' }, ...CHATBOTS.map(([name, url]) => h('a', { class: 'btn small', href: url, target: '_blank', rel: 'noopener noreferrer' }, name))),
    pasteArea,
    h(
      'div',
      { class: 'btn-row', style: 'margin-top:10px' },
      btn('Copy prompt', { icon: 'copy', onClick: () => void copyManual() }),
      btn('Load game', {
        class: 'primary',
        icon: 'play',
        onClick: () => {
          const text = pasteArea.value;
          const req = request() ?? { a: 'Game A', b: 'Game B', twist: twist.value, multiplayer: multi.checked };
          if (!extractGame(text).html) return toast('No HTML found in what you pasted.');
          const sameGames = draft && draft.games[0] === req.a && draft.games[1] === req.b;
          void finish(text, req, sameGames ? 'refine' : 'manual').then(() => (pasteArea.value = ''));
        },
      }),
    ),
  );

  const copyManual = async () => {
    const req = request();
    if (!req) return;
    manualBox.open = true;
    toast((await copyText(manualPrompt(req))) ? 'Prompt copied! Paste it into any chatbot.' : 'Copy failed', 3000);
  };

  // ------------------------------------------------------------------ page
  const isManual = settings.provider === 'manual';
  root.appendChild(
    layout(
      'create',
      list,
      h(
        'section',
        { class: 'hero' },
        h('h1', null, 'Create with ', h('span', { class: 'grad-text' }, 'AI')),
        h('p', { class: 'lead' }, 'Name any two games — real or made up — and get a playable mashup that runs on phones and PCs. Refine it by chatting, then share it with a link.'),
      ),
      h(
        'div',
        { class: 'studio' },
        h(
          'div',
          null,
          h(
            'div',
            { class: 'card' },
            h(
              'div',
              { class: 'vs' },
              h('label', { class: 'field' }, h('span', null, 'Game A (hero)'), gameA),
              h('div', { class: 'x' }, '×'),
              h('label', { class: 'field' }, h('span', null, 'Game B (world)'), gameB),
            ),
            ideas,
            h('label', { class: 'field' }, h('span', null, 'Twist'), twist),
            h('label', { class: 'check' }, multi, 'Multiplayer (friends join with a link)'),
            providerLine,
            h(
              'div',
              { class: 'btn-row' },
              isManual
                ? btn('Copy prompt', { class: 'primary', icon: 'copy', onClick: () => void copyManual() })
                : h('button', { class: 'btn primary', type: 'button', 'data-gen': '1', onClick: () => void runAI('new') }, '✨ Generate mashup'),
              isManual ? btn('Use an AI key instead', { class: 'ghost small', href: '#/settings' }) : null,
            ),
          ),
          manualBox,
        ),
        h('div', null, preview, h('div', { style: 'margin-top:12px' }, status), result),
      ),
    ),
  );
  if (isManual) manualBox.open = true;

  if (draft) {
    mount(draft.html);
    renderResult();
    const fix = q.get('fix');
    if (fix) {
      lastError = fix;
      renderResult();
      result.scrollIntoView({ behavior: 'smooth' });
    }
  } else showEmpty();

  return () => {
    abort?.abort();
    runner?.destroy();
  };
};
