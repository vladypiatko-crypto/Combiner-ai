import { describe, expect, it } from 'vitest';
import { extractGame } from '../src/ai/extract';
import { manualPrompt, systemPrompt, userPrompt } from '../src/ai/prompt';
import { decodeShare, encodeShare } from '../src/data/share';
import { injectSdk, parseControls } from '../src/player/sandbox';

const GAME = '<!doctype html><html><head><title>Blockrim</title><meta name="combiner-controls" content="a:Jump b:Mine c:Place_Block"></head><body><canvas></canvas><script>1</script></body></html>';

describe('extractGame', () => {
  it('reads title, tagline and fenced html', () => {
    const g = extractGame(`TITLE: Dragon Miner\nTAGLINE: Mine the sky.\n\`\`\`html\n${GAME}\n\`\`\``);
    expect(g.title).toBe('Dragon Miner');
    expect(g.tagline).toBe('Mine the sky.');
    expect(g.html).toBe(GAME);
    expect(g.complete).toBe(true);
  });

  it('handles markdown bold labels and partial streams', () => {
    const g = extractGame('**TITLE:** Snake Kart\n```html\n<!doctype html><html><body><script>let a = 1');
    expect(g.title).toBe('Snake Kart');
    expect(g.html).toContain('<script>let a = 1');
    expect(g.complete).toBe(false);
  });

  it('accepts a bare html document and falls back to <title>', () => {
    const g = extractGame(`Sure! Here it is:\n${GAME}\nEnjoy`);
    expect(g.html).toBe(GAME);
    expect(g.title).toBe('Blockrim');
    expect(g.complete).toBe(true);
  });

  it('rejects replies without a game', () => {
    expect(extractGame('I cannot help with that.').html).toBeUndefined();
  });
});

describe('prompts', () => {
  it('only mention multiplayer when asked', () => {
    expect(systemPrompt(false)).not.toContain('Combiner.net.send');
    expect(systemPrompt(true)).toContain('Combiner.net.send');
  });

  it('includes both games and the twist', () => {
    const p = userPrompt({ a: 'Minecraft', b: 'Skyrim', twist: 'dragons', multiplayer: false });
    expect(p).toContain('Game A: Minecraft');
    expect(p).toContain('Game B: Skyrim');
    expect(p).toContain('Twist: dragons');
    expect(manualPrompt({ a: 'A', b: 'B', twist: '', multiplayer: true })).toContain('OUTPUT FORMAT');
  });
});

describe('sandbox helpers', () => {
  it('parses control labels', () => {
    expect(parseControls(GAME)).toEqual({ touch: false, labels: { a: 'Jump', b: 'Mine', c: 'Place Bloc' } });
    expect(parseControls('<meta name="combiner-controls" content="touch">').touch).toBe(true);
    expect(parseControls('<html></html>').labels).toEqual({ a: 'A' });
  });

  it('injects the SDK before any game script', () => {
    const out = injectSdk(GAME);
    expect(out.indexOf('window.Combiner')).toBeGreaterThan(0);
    expect(out.indexOf('window.Combiner')).toBeLessThan(out.indexOf('<script>1</script>'));
    expect(out).toContain('name="viewport"');
    expect(injectSdk('<canvas></canvas>')).toMatch(/^<!doctype html>/);
  });
});

describe('share links', () => {
  it('round-trips a game through a compressed URL payload', async () => {
    const game = { v: 1 as const, title: 'Blockrim ✨', games: ['Minecraft', 'Skyrim'] as [string, string], html: GAME.repeat(20) };
    const payload = await encodeShare(game);
    expect(payload).toMatch(/^[zj][A-Za-z0-9_-]+$/);
    expect(payload.length).toBeLessThan(GAME.length * 20);
    expect(await decodeShare(payload)).toEqual(game);
  });

  it('rejects damaged links', async () => {
    await expect(decodeShare('zAAAA')).rejects.toThrow();
  });
});
