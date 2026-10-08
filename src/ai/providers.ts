import { ProviderId, getSettings, modelFor } from '../data/store';
import type { ChatMessage } from './prompt';

export interface GenerateOptions {
  system: string;
  messages: ChatMessage[];
  signal: AbortSignal;
  onText: (delta: string) => void;
  onThinking?: (delta: string) => void;
}

export interface ProviderInfo {
  id: ProviderId;
  name: string;
  cost: string;
  keyUrl?: string;
  keyHint?: string;
  models?: { id: string; label: string }[];
}

export const PROVIDERS: ProviderInfo[] = [
  {
    id: 'manual',
    name: 'Copy & paste into any chatbot',
    cost: 'Free · no key',
    keyHint: 'Combiner copies a ready-made prompt. Paste it into ChatGPT, Gemini, Claude, DeepSeek or Copilot (free tiers work), then paste the answer back.',
  },
  {
    id: 'openrouter',
    name: 'OpenRouter free models',
    cost: 'Free key · no card',
    keyUrl: 'https://openrouter.ai/keys',
    keyHint: 'Sign up at openrouter.ai, create a key, paste it here. The "openrouter/free" model routes to whichever free model is available.',
  },
  {
    id: 'gemini',
    name: 'Google Gemini',
    cost: 'Free tier key',
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHint: 'Create a free API key in Google AI Studio. Free-tier limits apply.',
  },
  {
    id: 'anthropic',
    name: 'Anthropic Claude',
    cost: 'Your own key · paid',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    keyHint: 'Best quality games. Uses your Claude API key straight from your browser.',
    models: [
      { id: 'claude-opus-5-5', label: 'Claude Opus 5.5 (best)' },
      { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5 (faster)' },
      { id: 'claude-haiku-5-5', label: 'Claude Haiku 5.5 (cheapest)' },
    ],
  },
  {
    id: 'custom',
    name: 'Any OpenAI-compatible API',
    cost: 'Groq, Together, LM Studio, Ollama…',
    keyHint: 'Base URL ending in /v1, plus a key and model name. Local servers (LM Studio, Ollama) need CORS enabled.',
  },
];

export function providerInfo(id: ProviderId): ProviderInfo {
  return PROVIDERS.find((p) => p.id === id)!;
}

export function providerReady(id: ProviderId): boolean {
  const s = getSettings();
  if (id === 'manual') return true;
  if (id === 'custom') return !!s.customBase && !!modelFor('custom');
  return !!s.keys[id];
}

/** Stream a reply from the chosen provider. Keys never leave the device except to that provider. */
export async function generate(id: ProviderId, opts: GenerateOptions): Promise<void> {
  switch (id) {
    case 'anthropic':
      return anthropic(opts);
    case 'gemini':
      return gemini(opts);
    case 'openrouter':
      return openaiCompatible(opts, 'https://openrouter.ai/api/v1', getSettings().keys.openrouter ?? '', modelFor('openrouter'), true);
    case 'custom':
      return openaiCompatible(opts, getSettings().customBase.replace(/\/+$/, ''), getSettings().keys.custom ?? '', modelFor('custom'), false);
    default:
      throw new Error('Copy-paste mode does not call an AI directly.');
  }
}

async function anthropic(o: GenerateOptions): Promise<void> {
  const { default: Anthropic } = await import('@anthropic-ai/sdk');
  const client = new Anthropic({ apiKey: getSettings().keys.anthropic ?? '', dangerouslyAllowBrowser: true });
  const model = modelFor('anthropic');
  const stream = client.beta.messages.stream(
    {
      model,
      max_tokens: 64000,
      system: o.system,
      messages: o.messages,
      thinking: { type: 'adaptive', display: 'summarized' },
      output_config: { effort: 'medium' },
      // Re-run on a fallback model if a safety classifier declines (not offered for Haiku).
      ...(model.startsWith('claude-haiku') ? {} : { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' as const }),
    },
    { signal: o.signal },
  );
  try {
    for await (const ev of stream) {
      if (ev.type !== 'content_block_delta') continue;
      if (ev.delta.type === 'text_delta') o.onText(ev.delta.text);
      else if (ev.delta.type === 'thinking_delta') o.onThinking?.(ev.delta.thinking);
    }
    const final = await stream.finalMessage();
    if (final.stop_reason === 'refusal') throw new Error('Claude declined this request. Try rephrasing your twist.');
  } catch (err) {
    if (err instanceof Anthropic.APIUserAbortError) throw err;
    if (err instanceof Anthropic.AuthenticationError) throw new Error('Claude rejected the API key. Check it in Settings.');
    if (err instanceof Anthropic.RateLimitError) throw new Error('Claude rate limit reached. Wait a minute and try again.');
    if (err instanceof Anthropic.APIError) throw new Error(`Claude error: ${err.message}`);
    throw err;
  }
}

async function* sse(res: Response): AsyncGenerator<string> {
  const reader = res.body!.getReader();
  const dec = new TextDecoder();
  let buf = '';
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i: number;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).replace(/\r$/, '');
      buf = buf.slice(i + 1);
      if (line.startsWith('data:')) yield line.slice(5).trim();
    }
  }
  if (buf.startsWith('data:')) yield buf.slice(5).trim();
}

async function httpError(res: Response, who: string): Promise<Error> {
  let detail = '';
  try {
    const body = await res.text();
    try {
      const j = JSON.parse(body);
      detail = j.error?.message || j.message || body;
    } catch {
      detail = body;
    }
  } catch {
    /* ignore */
  }
  detail = String(detail).slice(0, 300);
  if (res.status === 401 || res.status === 403) return new Error(`${who} rejected the key (${res.status}). Check it in Settings. ${detail}`);
  if (res.status === 429)
    return new Error(`${who} is rate-limiting free requests right now. Wait a minute, pick another model, or use copy & paste mode. ${detail}`);
  if (res.status === 402) return new Error(`${who} says this model needs credits. Pick a free model. ${detail}`);
  return new Error(`${who} error ${res.status}: ${detail}`);
}

async function gemini(o: GenerateOptions): Promise<void> {
  const model = modelFor('gemini');
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': getSettings().keys.gemini ?? '' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: o.system }] },
      contents: o.messages.map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
      generationConfig: { maxOutputTokens: 32768 },
    }),
    signal: o.signal,
  });
  if (!res.ok) throw await httpError(res, 'Gemini');
  for await (const data of sse(res)) {
    if (!data) continue;
    const j = JSON.parse(data);
    if (j.error) throw new Error(`Gemini: ${j.error.message}`);
    for (const part of j.candidates?.[0]?.content?.parts ?? []) {
      if (typeof part.text !== 'string') continue;
      if (part.thought) o.onThinking?.(part.text);
      else o.onText(part.text);
    }
  }
}

async function openaiCompatible(o: GenerateOptions, base: string, key: string, model: string, openrouter: boolean): Promise<void> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (key) headers.Authorization = `Bearer ${key}`;
  if (openrouter) {
    headers['HTTP-Referer'] = location.origin;
    headers['X-Title'] = 'Combiner';
  }
  const res = await fetch(`${base}/chat/completions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ model, stream: true, messages: [{ role: 'system', content: o.system }, ...o.messages] }),
    signal: o.signal,
  });
  const who = openrouter ? 'OpenRouter' : 'The AI server';
  if (!res.ok) throw await httpError(res, who);
  for await (const data of sse(res)) {
    if (!data || data === '[DONE]') continue;
    let j;
    try {
      j = JSON.parse(data);
    } catch {
      continue;
    }
    if (j.error) throw new Error(`${who}: ${j.error.message ?? JSON.stringify(j.error)}`);
    const d = j.choices?.[0]?.delta;
    if (!d) continue;
    const thinking = d.reasoning ?? d.reasoning_content;
    if (typeof thinking === 'string' && thinking) o.onThinking?.(thinking);
    if (typeof d.content === 'string' && d.content) o.onText(d.content);
  }
}

/** Quick connectivity check for the Settings page. */
export async function testProvider(id: ProviderId): Promise<string> {
  const ctrl = new AbortController();
  let text = '';
  const timer = setTimeout(() => ctrl.abort(), 60000);
  try {
    await generate(id, {
      system: 'Reply with the single word OK.',
      messages: [{ role: 'user', content: 'Say OK.' }],
      signal: ctrl.signal,
      onText: (d) => {
        text += d;
        if (text.length > 0) ctrl.abort();
      },
    });
  } catch (err) {
    if (!(ctrl.signal.aborted && text)) throw err;
  } finally {
    clearTimeout(timer);
  }
  return text.trim() || 'Connected';
}
