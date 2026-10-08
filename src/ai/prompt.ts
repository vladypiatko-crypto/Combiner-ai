export interface MashupRequest {
  a: string;
  b: string;
  twist: string;
  multiplayer: boolean;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

const MULTIPLAYER = `
Multiplayer (required for this game): the host app connects players peer-to-peer and exposes window.Combiner.net:
- Combiner.net.send(data): broadcast a small JSON-serialisable object to every other player (at most ~15 messages per second).
- Combiner.net.onMessage((data, fromId) => { ... })
- Combiner.net.onPlayers((players) => { ... }): players is [{ id, name, color }]. Combiner.net.me is your own id and Combiner.net.isHost is true for the room creator.
- Every player runs their own copy of the game. Broadcast your own player state about 10 times per second and draw the other players from what you receive (use their colors and names). Let the host decide shared things (enemy spawns, pickups, round timer) and broadcast them.
- The game must still be fully playable alone, when Combiner.net.players is empty or Combiner is undefined (always check \`window.Combiner\` exists before using it).`;

export function systemPrompt(multiplayer: boolean): string {
  return `You are Combiner, a world-class HTML5 game developer. You fuse two games into one small, polished, instantly fun "mashup" that runs in a web browser on phones and computers.

OUTPUT FORMAT (follow exactly):
TITLE: <catchy mashup name, max 4 words>
TAGLINE: <one-sentence pitch>
\`\`\`html
<!doctype html>
...the complete game...
\`\`\`
Write nothing after the code block.

TECHNICAL RULES (the game runs inside a sandboxed iframe):
- One self-contained HTML file: all code inline in <script> and <style>. No external images, fonts, sounds or network requests. Draw everything with the Canvas 2D API (shapes, gradients, emoji or inline SVG are fine). Prefer plain canvas; only if truly needed you may load one pinned library from https://cdn.jsdelivr.net/npm/ (for example three@0.160.0 for 3D).
- Fill the whole viewport (no scrollbars, no margins) and adapt to any size and orientation: tall phones (390x600), tablets and wide desktops. Handle resize and devicePixelRatio so the canvas stays crisp. Keep text readable on a phone (at least 16 CSS px).
- Never call alert(), confirm(), prompt() or window.open(). localStorage may not persist: wrap it in try/catch.
- Use requestAnimationFrame with delta time (clamp large deltas) and keep 60 fps on a mid-range phone.
- Sound is optional: synthesize it with WebAudio and create/resume the AudioContext on the first keydown or pointerdown.

CONTROLS (very important):
- Keyboard: Arrow keys AND WASD to move, Space = button A, X = button B, C = button C. Listen on window for keydown/keyup and check event.key or event.code.
- On touch screens the host app shows its own joystick and A/B/C buttons that send exactly those key events. Do NOT draw your own on-screen d-pad or buttons.
- Declare the buttons you use in <head>, labels max 8 characters, _ for spaces, e.g. <meta name="combiner-controls" content="a:Jump b:Attack c:Build">
- Optional analog input: window.Combiner && window.Combiner.input gives {x, y} in -1..1 from the joystick plus booleans left/right/up/down/a/b/c.
- Exception: if the game is naturally tap/drag based (puzzle, slingshot, slicing...), use pointer events (pointerdown/pointermove/pointerup) instead and declare <meta name="combiner-controls" content="touch">.
- Start on a title screen that shows the name, a one-line goal and the controls, and begins on Space, Enter, A or a tap. After game over or victory, the same keys or a tap restart.

DESIGN RULES:
- Truly fuse the games: bring the hero and core mechanic of Game A into the world, enemies and objective of Game B, unless the twist asks for a different blend. Both games must be recognisable within 5 seconds of play.
- Fun first: a clear on-screen goal, score, rising difficulty, a win condition and a lose condition, juicy feedback (particles, screen shake, hit flashes, squash and stretch) and a readable HUD.
- Evoke the source games with original names and original procedural art; do not reproduce logos or copyrighted sprites.
- Aim for 400-900 lines. Write complete, working code with no placeholders or TODOs. Double-check for runtime errors (undefined variables, wrong canvas sizes, unhandled states).
- Optional: call window.Combiner && Combiner.setScore(score) when the score changes and Combiner.gameOver(won, score) at the end.${multiplayer ? MULTIPLAYER : ''}`;
}

export function userPrompt(r: MashupRequest): string {
  return [
    `Game A: ${r.a.trim()}`,
    `Game B: ${r.b.trim()}`,
    `Twist: ${r.twist.trim() || 'Surprise me: pick the most fun way to combine them.'}`,
    `Multiplayer: ${r.multiplayer ? 'yes, 2-8 players via Combiner.net' : 'no, single player'}`,
    '',
    'Make the mashup.',
  ].join('\n');
}

export function assistantEcho(title: string, tagline: string, html: string): string {
  return `TITLE: ${title}\nTAGLINE: ${tagline}\n\`\`\`html\n${html}\n\`\`\``;
}

export function refinePrompt(change: string): string {
  return `Update the game: ${change.trim()}\n\nKeep everything that already works. Return the complete updated file in the same format (TITLE, TAGLINE, then the full html code block).`;
}

export function fixPrompt(error: string): string {
  return `The game crashed in the browser with this error:\n${error.trim()}\n\nFind and fix the cause (and any similar bugs). Return the complete fixed file in the same format (TITLE, TAGLINE, then the full html code block).`;
}

/** One block of text to paste into any free chatbot (ChatGPT, Gemini, Claude…). */
export function manualPrompt(r: MashupRequest): string {
  return `${systemPrompt(r.multiplayer)}\n\n---\n\n${userPrompt(r)}`;
}

export const IDEAS: [string, string, string][] = [
  ['Minecraft', 'Skyrim', 'Mine and build blocks while hunting a dragon'],
  ['Flappy Bird', 'Dark Souls', 'Brutal boss fights where you can only flap'],
  ['Tetris', 'Pac-Man', 'Falling pieces build the maze while ghosts chase you'],
  ['Fruit Ninja', 'Snake', 'Swipe to slice fruit that your snake then eats'],
  ['Angry Birds', 'Breakout', 'Slingshot birds into a brick wall'],
  ['Geometry Dash', 'Space Invaders', 'Auto-runner that shoots invaders to the beat'],
  ['Pong', 'Doom', 'Paddle-deflect fireballs back at demons'],
  ['Among Us', 'Pac-Man', 'Do tasks in a maze while an impostor ghost hunts'],
  ['Mario Kart', 'Snake', 'Racers leave tails that become walls'],
  ['Pokémon', 'Asteroids', 'Catch space creatures by shooting rocks off them'],
];

export const SUGGESTED_GAMES = [
  'Minecraft',
  'Skyrim',
  'Super Mario Bros.',
  'Tetris',
  'Pac-Man',
  'Flappy Bird',
  'Snake',
  'Asteroids',
  'Breakout',
  'Space Invaders',
  'Angry Birds',
  'Fruit Ninja',
  'Geometry Dash',
  'Among Us',
  'Doom',
  'Dark Souls',
  'Pokémon',
  'Zelda',
  'Mario Kart',
  'Pong',
  'Stardew Valley',
  'Portal',
  'Celeste',
  'Hollow Knight',
  'Vampire Survivors',
  'Crossy Road',
  'Subway Surfers',
  'Fortnite',
  'Rocket League',
  'Chess',
];
