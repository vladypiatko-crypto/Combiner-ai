import { EMPTY, TILE, hashString, isSolid } from './core';
import { drawEnt, drawHero, drawSnake, drawTile, poseFromHero } from './art';
import type { Game } from './game';

type Ctx = CanvasRenderingContext2D;

/** World pixels per CSS pixel for the current screen. */
export function computeScale(game: Game, cssW: number, cssH: number): number {
  const L = game.level;
  if (L.camera === 'fixed') return Math.min(cssW / L.pxW, cssH / L.pxH);
  return Math.max(1, Math.min(cssH / (15 * TILE), cssW / (12 * TILE)));
}

const shadeCache = new Map<string, string[]>();
function shades(color: string, step: number): string[] {
  const key = `${color}/${step}`;
  let s = shadeCache.get(key);
  if (s) return s;
  const n = parseInt(color.slice(1), 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  s = [-2, -1, 0, 1, 2]
    .map((k) => k * step)
    .map((d) => `rgb(${Math.max(0, Math.min(255, r + d))},${Math.max(0, Math.min(255, g + d))},${Math.max(0, Math.min(255, b + d))})`);
  shadeCache.set(key, s);
  return s;
}

export function renderGame(game: Game, ctx: Ctx, cw: number, ch: number, dpr: number): void {
  const L = game.level;
  const s = computeScale(game, cw / dpr, ch / dpr) * dpr;
  game.setView(cw / s, ch / s);
  if (L.camera === 'fixed') game.updateCamera(0);

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.imageSmoothingEnabled = false;
  const sky = ctx.createLinearGradient(0, 0, 0, ch);
  sky.addColorStop(0, L.theme.bg[0]);
  sky.addColorStop(1, L.theme.bg[1]);
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, cw, ch);
  drawDecor(game, ctx, cw, ch, s);

  const sh = game.shake;
  const ox = Math.round(-game.cam.x * s + (sh ? (Math.random() - 0.5) * sh * s : 0));
  const oy = Math.round(-game.cam.y * s + (sh ? (Math.random() - 0.5) * sh * s : 0));
  ctx.setTransform(s, 0, 0, s, ox, oy);

  const tx0 = Math.max(0, Math.floor(game.cam.x / TILE) - 1);
  const ty0 = Math.max(0, Math.floor(game.cam.y / TILE) - 1);
  const tx1 = Math.min(L.w - 1, Math.ceil((game.cam.x + game.viewW) / TILE) + 1);
  const ty1 = Math.min(L.h - 1, Math.ceil((game.cam.y + game.viewH) / TILE) + 1);

  // Ground for top-down worlds.
  if (L.view === 'top' && L.theme.ground) {
    const checker = L.theme.decor === 'grid';
    const gs = shades(L.theme.ground, checker ? 5 : 2);
    for (let ty = ty0; ty <= ty1; ty++)
      for (let tx = tx0; tx <= tx1; tx++) {
        if (isSolid(L.get(tx, ty)) && L.getArt(tx, ty) !== 12 && L.getArt(tx, ty) !== 13) continue;
        ctx.fillStyle = checker ? gs[(tx + ty) % 2 ? 1 : 3] : gs[(((tx * 73856093) ^ (ty * 19349663)) >>> 0) % 5];
        ctx.fillRect(tx * TILE, ty * TILE, TILE, TILE);
      }
  }

  // Tiles.
  const variants = L.theme.variants;
  for (let ty = ty0; ty <= ty1; ty++)
    for (let tx = tx0; tx <= tx1; tx++) {
      const t = L.get(tx, ty);
      if (t === EMPTY) continue;
      const art = L.getArt(tx, ty);
      const style = (art ? variants?.[art] : undefined) ?? L.theme.tiles[t];
      if (style) drawTile(ctx, style, tx, ty, L, game.time);
    }

  // Entities (duplicated across edges in wrap-around worlds).
  const vx0 = game.cam.x - 48;
  const vy0 = game.cam.y - 48;
  const vx1 = game.cam.x + game.viewW + 48;
  const vy1 = game.cam.y + game.viewH + 48;
  for (const e of game.ents) {
    if (e.dead) continue;
    if (L.wrap) {
      for (const dx of [-L.pxW, 0, L.pxW])
        for (const dy of [-L.pxH, 0, L.pxH]) {
          if (dx || dy) {
            const nx = e.x + dx;
            const ny = e.y + dy;
            if (nx + e.w < 0 || ny + e.h < 0 || nx > L.pxW || ny > L.pxH) continue;
          }
          ctx.save();
          ctx.translate(dx, dy);
          drawEnt(ctx, e, game);
          ctx.restore();
        }
      continue;
    }
    if (e.x + e.w < vx0 || e.y + e.h < vy0 || e.x > vx1 || e.y > vy1) continue;
    drawEnt(ctx, e, game);
  }

  // Other racers in a multiplayer race.
  for (const [, g] of game.ghosts) {
    ctx.save();
    ctx.globalAlpha = 0.5;
    const pose = {
      ...poseFromHero(game.hero),
      x: g.x,
      y: g.y,
      face: g.face,
      fx: g.face,
      fy: 0,
      hop: 0,
      power: 0,
      attack: { kind: '', t: 0, dx: 1, dy: 0 },
      moving: true,
    };
    if (game.heroDef.move[L.view] === 'grid') {
      ctx.fillStyle = g.color;
      ctx.beginPath();
      ctx.arc(g.x + 6, g.y + 6, 7, 0, Math.PI * 2);
      ctx.fill();
    } else {
      drawHero(ctx, game.heroDef.id, pose, L.view);
    }
    ctx.globalAlpha = 0.9;
    ctx.font = 'bold 7px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = g.color;
    ctx.fillText(g.name.slice(0, 12), g.x + game.hero.w / 2, g.y - 10);
    ctx.restore();
  }

  // Hero.
  const h = game.hero;
  const blink = h.inv > 0 && Math.floor(h.inv * 14) % 2 === 0;
  if (!blink || game.state !== 'play') {
    const pose = poseFromHero(h);
    if (game.heroDef.move[L.view] === 'grid') drawSnake(ctx, pose);
    else drawHero(ctx, game.heroDef.id, pose, L.view);
  }

  // Particles.
  for (const p of game.parts) {
    const a = Math.max(0, Math.min(1, p.life / p.max));
    ctx.globalAlpha = a;
    if (p.text) {
      ctx.font = 'bold 8px system-ui, sans-serif';
      ctx.textAlign = 'left';
      ctx.lineWidth = 2;
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.strokeText(p.text, p.x, p.y);
      ctx.fillStyle = p.color;
      ctx.fillText(p.text, p.x, p.y);
    } else {
      ctx.fillStyle = p.color;
      ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
    }
  }
  ctx.globalAlpha = 1;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
}

function drawDecor(game: Game, ctx: Ctx, cw: number, ch: number, s: number): void {
  const L = game.level;
  const seed = hashString(L.theme.bg[0]);
  const rand = (i: number, k: number) => {
    let x = Math.imul(seed ^ Math.imul(i + 1, 0x9e3779b1) ^ Math.imul(k + 1, 0x85ebca6b), 0xc2b2ae35);
    x ^= x >>> 15;
    x = Math.imul(x, 0x27d4eb2f);
    x ^= x >>> 13;
    return (x >>> 0) / 4294967296;
  };
  switch (L.theme.decor) {
    case 'clouds': {
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      const span = cw + 200 * s;
      for (let i = 0; i < 9; i++) {
        const x = ((rand(i, 1) * 3000 - game.cam.x * 0.35) * s) % span;
        const px = x < -100 * s ? x + span : x;
        const py = rand(i, 2) * 0.35 * ch + 10 * s;
        const r = (8 + rand(i, 3) * 8) * s;
        ctx.beginPath();
        ctx.arc(px, py, r, 0, Math.PI * 2);
        ctx.arc(px + r, py - r * 0.4, r * 1.1, 0, Math.PI * 2);
        ctx.arc(px + r * 2.1, py, r * 0.9, 0, Math.PI * 2);
        ctx.fill();
      }
      break;
    }
    case 'hills': {
      for (const [k, color, par, hgt] of [
        [0, '#a8e6a1', 0.2, 0.32],
        [1, '#73c26b', 0.45, 0.22],
      ] as const) {
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.moveTo(0, ch);
        for (let x = 0; x <= cw + 10; x += 10) {
          const wx = x / s + game.cam.x * par;
          const y = ch - (Math.sin(wx / (60 + k * 30)) * 0.5 + 0.5) * ch * hgt - ch * 0.06;
          ctx.lineTo(x, y);
        }
        ctx.lineTo(cw, ch);
        ctx.fill();
      }
      break;
    }
    case 'stars': {
      for (let i = 0; i < 120; i++) {
        const x = (rand(i, 1) * cw - game.cam.x * 0.05 * s + cw) % cw;
        const y = (rand(i, 2) * ch - game.cam.y * 0.05 * s + ch) % ch;
        const tw = 0.4 + 0.6 * Math.abs(Math.sin(game.time * (0.5 + rand(i, 3)) + i));
        ctx.fillStyle = `rgba(255,255,255,${tw * (0.3 + rand(i, 4) * 0.7)})`;
        const sz = rand(i, 5) > 0.9 ? 2 : 1;
        ctx.fillRect(x, y, sz * Math.max(1, s / 3), sz * Math.max(1, s / 3));
      }
      break;
    }
    default:
      break;
  }
  if (L.theme.decor === 'snow') {
    // Drawn over the ground later would hide it, so snow is overlaid in the HUD pass instead.
    game.vars.snow = 1;
  }
}

/** Light snowfall overlay for Dragon Realm, drawn after the world. */
export function renderOverlay(game: Game, ctx: Ctx, cw: number, ch: number, dpr: number): void {
  if (game.level.theme.decor !== 'snow') return;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = 'rgba(255,255,255,0.75)';
  for (let i = 0; i < 70; i++) {
    const sp = 18 + (i % 7) * 6;
    const x = ((i * 137.5 + Math.sin(game.time + i) * 12) * dpr + game.time * 8 * dpr - game.cam.x * 0.6 * dpr) % cw;
    const y = (i * 89.3 * dpr + game.time * sp * dpr - game.cam.y * 0.6 * dpr) % ch;
    const sz = (1 + (i % 3)) * dpr;
    ctx.fillRect(x < 0 ? x + cw : x, y < 0 ? y + ch : y, sz, sz);
  }
}
