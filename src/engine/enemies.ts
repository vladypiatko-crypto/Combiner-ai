import { BREAK, Ent, TILE, approach, clamp, len, makeEnt, norm, overlap } from './core';
import type { Game } from './game';
import { moveBody } from './level';

/** Per-frame behaviour for every entity type. */
export function updateEnt(game: Game, e: Ent, dt: number): void {
  e.t += dt;
  if (e.hurt > 0) e.hurt -= dt;
  switch (e.type) {
    case 'zombie':
      walker(game, e, dt, 28, 46, 7);
      break;
    case 'creeper':
      creeper(game, e, dt);
      break;
    case 'goomba':
      walker(game, e, dt, 26, 26, 0);
      break;
    case 'koopa':
      walker(game, e, dt, 32, 32, 0);
      break;
    case 'draugr':
      chaser(game, e, dt, 26, 44, 9 * TILE);
      break;
    case 'wolf':
      chaser(game, e, dt, 30, 72, 8 * TILE);
      break;
    case 'dragon':
      dragon(game, e, dt);
      break;
    case 'bat':
      bat(game, e, dt);
      break;
    case 'spiky':
      bouncer(game, e, dt);
      break;
    case 'rock':
      drift(game, e, dt);
      break;
    case 'ghost':
      ghost(game, e, dt);
      break;
    case 'fireball':
    case 'bullet':
      friendlyShot(game, e, dt);
      break;
    case 'fire':
      e.x += e.vx * dt;
      e.y += e.vy * dt;
      if (e.t > (e.data.life ?? 2.5)) e.dead = true;
      break;
    case 'bomb':
      bomb(game, e, dt);
      break;
    case 'ball':
      ball(game, e, dt);
      break;
  }
}

// ---------------------------------------------------------------- side view

function walker(game: Game, e: Ent, dt: number, patrol: number, chase: number, sight: number): void {
  const h = game.hero;
  const dx = h.x - e.x;
  const dy = h.y - e.y;
  let speed = patrol;
  if (sight && Math.abs(dx) < sight * TILE && Math.abs(dy) < 3 * TILE) {
    e.dir = Math.sign(dx) || e.dir;
    speed = chase;
  }
  if (h.power > 0 && sight) e.dir = -Math.sign(dx) || e.dir;
  e.vx = approach(e.vx, e.dir * speed, 500 * dt);
  e.vy = Math.min(e.vy + 1000 * dt, 600);
  const res = moveBody(game.level, e, dt);
  if (res.hitX) {
    if (speed === chase && e.onGround && sight) e.vy = -260;
    else e.dir = -e.dir;
  }
  if (e.y > game.level.pxH + 40) e.dead = true;
}

function creeper(game: Game, e: Ent, dt: number): void {
  const [hx, hy] = game.heroCenter();
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  const d = len(hx - cx, hy - cy);
  if (e.data.fuse) {
    e.data.fuse -= dt;
    e.vx = approach(e.vx, 0, 600 * dt);
    e.vy = Math.min(e.vy + 1000 * dt, 600);
    moveBody(game.level, e, dt);
    if (e.data.fuse <= 0) {
      e.dead = true;
      game.breakTilesInCircle(cx, cy, 34);
      game.burst(cx, cy, '#ffffff', 18, 160, 200);
      game.burst(cx, cy, '#7d7d7d', 14, 120, 200);
      game.addShake(7);
      game.sfx('boom');
      if (d < 44) game.damageHero(2, cx, cy);
      for (const o of game.enemies()) if (o !== e && len(o.x - e.x, o.y - e.y) < 40) game.hurtEnemy(o, 3, cx, cy, 300);
    }
    return;
  }
  if (d < 26) e.data.fuse = 1;
  walker(game, e, dt, 18, 38, 8);
}

function bat(game: Game, e: Ent, dt: number): void {
  e.x += (e.vx || -24) * dt;
  e.data.baseY = (e.data.baseY ?? e.y) + e.vy * dt;
  e.vy = approach(e.vy, 0, 300 * dt);
  e.y = e.data.baseY + Math.sin(e.t * 3 + e.id) * 18;
  if (e.x < game.cam.x - 80) e.dead = true;
}

function bomb(game: Game, e: Ent, dt: number): void {
  e.vy = Math.min(e.vy + 320 * dt, 260);
  const res = moveBody(game.level, e, dt);
  if (res.hitY || res.hitX) {
    e.dead = true;
    game.burst(e.x + 4, e.y + 4, '#ffb347', 10, 90, 100);
    game.sfx('boom');
  }
}

// ---------------------------------------------------------------- top view

function chaser(game: Game, e: Ent, dt: number, wander: number, chase: number, sight: number): void {
  const [hx, hy] = game.heroCenter();
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  const d = len(hx - cx, hy - cy);
  let tx: number;
  let ty: number;
  if (d < sight) {
    const [nx, ny] = norm(hx - cx, hy - cy);
    const flee = game.hero.power > 0 ? -1 : 1;
    tx = nx * chase * flee;
    ty = ny * chase * flee;
  } else {
    e.data.wt = (e.data.wt ?? 0) - dt;
    if (e.data.wt <= 0) {
      const a = game.rng.range(0, Math.PI * 2);
      e.data.wx = Math.cos(a);
      e.data.wy = Math.sin(a);
      e.data.wt = game.rng.range(1, 2.5);
    }
    tx = (e.data.wx ?? 0) * wander;
    ty = (e.data.wy ?? 0) * wander;
  }
  e.vx = approach(e.vx, tx, 420 * dt);
  e.vy = approach(e.vy, ty, 420 * dt);
  const res = moveBody(game.level, e, dt);
  if (res.hitX || res.hitY) e.data.wt = 0;
  if (Math.abs(e.vx) > 2) e.dir = Math.sign(e.vx);
}

function dragon(game: Game, e: Ent, dt: number): void {
  const [hx, hy] = game.heroCenter();
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  const L = game.level;
  e.data.pt = (e.data.pt ?? 0) + dt;
  const phase = e.data.phase ?? 0;
  e.data.invulnerable = phase === 1 ? 1 : 0;
  if (phase === 0) {
    // Circle the hero and breathe fire.
    e.data.ang = (e.data.ang ?? 0) + dt * 0.9;
    const tx = hx + Math.cos(e.data.ang) * 105;
    const ty = hy + Math.sin(e.data.ang) * 80;
    e.vx = approach(e.vx, (tx - cx) * 2.2, 400 * dt);
    e.vy = approach(e.vy, (ty - cy) * 2.2, 400 * dt);
    e.data.fire = (e.data.fire ?? 0.8) - dt;
    if (e.data.fire <= 0) {
      e.data.fire = 0.75;
      const [nx, ny] = norm(hx - cx, hy - cy);
      const spread = game.rng.range(-0.15, 0.15);
      game.spawn(
        makeEnt('proj', 'fire', cx - 5, cy - 5, 10, 10, {
          vx: (nx * Math.cos(spread) - ny * Math.sin(spread)) * 130,
          vy: (ny * Math.cos(spread) + nx * Math.sin(spread)) * 130,
          data: { life: 2.4 },
        }),
      );
      game.sfx('shoot');
    }
    if (e.data.pt > 3.2) {
      e.data.phase = 1;
      e.data.pt = 0;
      const [nx, ny] = norm(hx - cx, hy - cy);
      e.vx = nx * 230;
      e.vy = ny * 230;
      game.banner('The dragon swoops!', 1);
    }
  } else if (phase === 1) {
    // Swoop through the hero's position (invulnerable while diving).
    if (e.data.pt > 1.0) {
      e.data.phase = 2;
      e.data.pt = 0;
    }
  } else {
    // Land and rest: the time to strike.
    e.vx = approach(e.vx, 0, 500 * dt);
    e.vy = approach(e.vy, 0, 500 * dt);
    if (e.data.pt > 1.8) {
      e.data.phase = 0;
      e.data.pt = 0;
    }
  }
  e.x = clamp(e.x + e.vx * dt, 0, L.pxW - e.w);
  e.y = clamp(e.y + e.vy * dt, 0, L.pxH - e.h);
  if (Math.abs(e.vx) > 5) e.dir = Math.sign(e.vx);
}

function bouncer(game: Game, e: Ent, dt: number): void {
  const pvx = e.vx;
  const pvy = e.vy;
  const res = moveBody(game.level, e, dt);
  e.vx = res.hitX ? -pvx : pvx;
  e.vy = res.hitY ? -pvy : pvy;
  const sp = len(e.vx, e.vy);
  const target = e.data.speed ?? 55;
  if (sp > 0.1) {
    e.vx = approach(e.vx, (e.vx / sp) * target, 200 * dt);
    e.vy = approach(e.vy, (e.vy / sp) * target, 200 * dt);
  } else {
    e.vx = target;
    e.vy = target;
  }
}

function drift(game: Game, e: Ent, dt: number): void {
  const L = game.level;
  e.x += e.vx * dt;
  e.y += e.vy * dt;
  if (L.wrap) {
    e.x = ((e.x % L.pxW) + L.pxW) % L.pxW;
    e.y = ((e.y % L.pxH) + L.pxH) % L.pxH;
  }
  const sp = len(e.vx, e.vy);
  const min = 22;
  if (sp < min) {
    e.vx += (e.vx / (sp || 1)) * 30 * dt + (sp < 1 ? 10 : 0);
    e.vy += (e.vy / (sp || 1)) * 30 * dt;
  } else if (sp > 110) {
    e.vx *= 0.98;
    e.vy *= 0.98;
  }
}

// ---------------------------------------------------------------- maze ghosts

const DIRS = [
  { bit: 1, x: 0, y: -1 },
  { bit: 2, x: 1, y: 0 },
  { bit: 4, x: 0, y: 1 },
  { bit: 8, x: -1, y: 0 },
];

export function cellCenter(cx: number, cy: number): [number, number] {
  return [(1 + 3 * cx) * TILE + TILE, (1 + 3 * cy) * TILE + TILE];
}

function ghost(game: Game, e: Ent, dt: number): void {
  const m = game.level.maze;
  if (!m) return;
  const d = e.data;
  if (game.time < (d.release ?? 0) && !d.eaten) {
    e.y += Math.sin(e.t * 6) * 0.3;
    return;
  }
  const frightened = game.hero.power > 0 && !d.eaten;
  d.frightened = frightened ? 1 : 0;
  e.data.harmless = d.eaten ? 1 : 0;
  const speed = d.eaten ? 150 : frightened ? 36 : 50 + game.goal().progress * 22;
  const [tx, ty] = cellCenter(d.tx, d.ty);
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  const dist = len(tx - cx, ty - cy);
  const step = speed * dt;
  if (dist > step) {
    e.x += ((tx - cx) / dist) * step;
    e.y += ((ty - cy) / dist) * step;
    if (Math.abs(tx - cx) > 1) e.dir = Math.sign(tx - cx);
    return;
  }
  e.x = tx - e.w / 2;
  e.y = ty - e.h / 2;
  d.cx = d.tx;
  d.cy = d.ty;
  if (d.eaten && d.cx === m.houseX && d.cy === m.houseY) {
    d.eaten = 0;
    e.hp = e.maxHp;
  }
  // Pick the next cell.
  const open = m.open[d.cy * m.cols + d.cx];
  const h = game.hero;
  const hcx = Math.floor((h.x + h.w / 2) / (3 * TILE));
  const hcy = Math.floor((h.y + h.h / 2) / (3 * TILE));
  let gx = hcx;
  let gy = hcy;
  if (d.eaten) {
    gx = m.houseX;
    gy = m.houseY;
  } else if (d.kind === 1) {
    gx = hcx + Math.round(h.fx * 3);
    gy = hcy + Math.round(h.fy * 3);
  } else if (d.kind === 2 && game.rng.chance(0.5)) {
    gx = game.rng.int(0, m.cols - 1);
    gy = game.rng.int(0, m.rows - 1);
  } else if (d.kind === 3 && len(hcx - d.cx, hcy - d.cy) < 4) {
    gx = 0;
    gy = m.rows - 1;
  }
  let best = -1;
  let bestScore = frightened ? -Infinity : Infinity;
  const options = DIRS.filter((dir) => open & dir.bit);
  const forward = options.filter((dir) => !(dir.x === -d.dx && dir.y === -d.dy));
  const pool = forward.length ? forward : options;
  for (let i = 0; i < pool.length; i++) {
    const dir = pool[i];
    const s = len(d.cx + dir.x - gx, d.cy + dir.y - gy) + game.rng.range(0, 0.3);
    if (frightened ? s > bestScore : s < bestScore) {
      bestScore = s;
      best = i;
    }
  }
  if (best >= 0) {
    const dir = pool[best];
    d.dx = dir.x;
    d.dy = dir.y;
    d.tx = d.cx + dir.x;
    d.ty = d.cy + dir.y;
  }
}

// ---------------------------------------------------------------- projectiles

function friendlyShot(game: Game, e: Ent, dt: number): void {
  const L = game.level;
  if (e.t > (e.data.life ?? 1)) {
    e.dead = true;
    return;
  }
  if (e.data.bounce) e.vy = Math.min(e.vy + 900 * dt, 400);
  const pvy = e.vy;
  if (L.wrap) {
    e.x = (((e.x + e.vx * dt) % L.pxW) + L.pxW) % L.pxW;
    e.y = (((e.y + e.vy * dt) % L.pxH) + L.pxH) % L.pxH;
  } else {
    const res = moveBody(L, e, dt);
    if (res.hitY && e.data.bounce && pvy > 0) {
      e.vy = -210;
    } else if (res.hitX || res.hitY) {
      const t = res.tileX ?? res.tileY;
      if (t && L.get(t[0], t[1]) === BREAK) game.breakTile(t[0], t[1]);
      e.dead = true;
      game.burst(e.x + e.w / 2, e.y + e.h / 2, '#ffb347', 4, 50, 0);
      return;
    }
    if (e.data.bounce && e.vx === 0) e.dead = true;
  }
  for (const o of game.ents) {
    if (o.kind === 'enemy' && !o.dead && !o.data.eaten && overlap(e, o)) {
      game.hurtEnemy(o, 1, e.x - e.vx * 0.05, e.y - e.vy * 0.05, 120);
      e.dead = true;
      return;
    }
  }
}

function ball(game: Game, e: Ent, dt: number): void {
  const L = game.level;
  const h = game.hero;
  const speed = e.data.speed ?? 180;
  const owned = !!e.data.owner;
  if (owned && e.data.held) {
    e.x = h.x + h.w / 2 - e.w / 2;
    e.y = game.view === 'side' ? h.y - e.h - 1 : h.y + h.h / 2 - e.h / 2 + h.fy * 10;
    if (game.view === 'top') e.x += h.fx * 14;
    return;
  }
  if (owned) {
    e.data.out = (e.data.out ?? 0) + dt;
    if (e.data.recall || e.data.out > 7 || e.y > L.pxH + 20 || e.x < -20 || e.x > L.pxW + 20) {
      // Fly home through walls.
      const [nx, ny] = norm(h.x + h.w / 2 - e.x, h.y - e.y);
      e.x += nx * 320 * dt;
      e.y += ny * 320 * dt;
      if (len(h.x + h.w / 2 - e.x, h.y - e.y) < 14) {
        e.data.held = 1;
        e.data.recall = 0;
      }
      return;
    }
  } else if (e.data.wait) {
    // World ball waiting to relaunch.
    e.data.wait -= dt;
    e.x = h.x + h.w / 2 - e.w / 2;
    e.y = Math.max(h.y - 40, 2 * TILE);
    if (e.data.wait <= 0) {
      e.data.wait = 0;
      const a = game.rng.range(-0.5, 0.5) - Math.PI / 2;
      e.vx = Math.cos(a) * speed;
      e.vy = Math.sin(a) * speed;
    }
    return;
  }
  const pvx = e.vx;
  const pvy = e.vy;
  const res = moveBody(L, e, dt);
  e.vx = res.hitX ? -pvx : pvx;
  e.vy = res.hitY ? -pvy : pvy;
  if (res.tileX) game.breakTile(res.tileX[0], res.tileX[1]);
  if (res.tileY) game.breakTile(res.tileY[0], res.tileY[1]);
  // Enemies.
  for (const o of game.ents) {
    if (o.kind === 'enemy' && !o.dead && !o.data.eaten && overlap(e, o)) {
      game.hurtEnemy(o, 1, e.x, e.y, 140);
      const [nx, ny] = norm(e.x + e.w / 2 - (o.x + o.w / 2), e.y + e.h / 2 - (o.y + o.h / 2));
      e.vx = nx * speed;
      e.vy = ny * speed;
      break;
    }
  }
  // Bounce off the hero like a paddle.
  const hb = game.heroDef.move[game.view] === 'grid' ? { x: h.x - 2, y: h.y - 2, w: h.w + 4, h: h.h + 4 } : h;
  if (overlap(e, hb)) {
    const bx = e.x + e.w / 2;
    const by = e.y + e.h / 2;
    const hx = h.x + h.w / 2;
    const hy = h.y + h.h / 2;
    if (game.view === 'side' && by < hy) {
      const off = clamp((bx - hx) / (h.w / 2 + e.w / 2), -1, 1) * 1.05;
      e.vx = Math.sin(off) * speed;
      e.vy = -Math.cos(off) * speed;
      e.y = h.y - e.h - 0.5;
    } else {
      const [nx, ny] = norm(bx - hx, by - hy);
      e.vx = nx * speed;
      e.vy = ny * speed;
    }
    if (owned) e.data.out = 0;
    game.sfx('hit');
  }
  // Keep the ball from getting stuck going perfectly flat.
  const sp = len(e.vx, e.vy) || 1;
  e.vx = (e.vx / sp) * speed;
  e.vy = (e.vy / sp) * speed;
  if (Math.abs(e.vy) < speed * 0.22) e.vy = Math.sign(e.vy || -1) * speed * 0.22;
  if (Math.abs(e.vx) < speed * 0.08) e.vx = Math.sign(e.vx || 1) * speed * 0.08;
}
