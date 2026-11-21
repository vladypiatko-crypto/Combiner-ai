# Ragdoll Rumble

A side-view, ragdoll-physics party brawler for Roblox. You fight as **your own avatar** in a
3D world viewed from the side. Everyone moves only left and right (plus jumps), punches,
blocks and grabs the weapons that fall from the sky. The last one standing wins the round,
and the first to 5 round wins is the champion.

## Play it

**Option A: just open it**
1. Open `build/RagdollRumble.rbxlx` in Roblox Studio (File → Open from File).
2. Press **Play**. Bots fill the empty slots, so you can brawl solo right away.
3. To test multiplayer, use Test → Clients and Servers with 2 or more players.

**Option B: live-sync with Rojo** (edit code in VS Code and Studio updates instantly)
```bash
rojo serve
```
Then click **Connect** in the Rojo Studio plugin.

To rebuild the place file:
```bash
rojo build default.project.json -o build/RagdollRumble.rbxlx
```

> Avatar type: the project sets R15 (`StarterPlayer.GameSettingsAvatar`). If you publish,
> also set Game Settings → Avatar → **R15**. The custom animations and ragdolls target R15 rigs.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Move | A / D | Left stick | ◀ ▶ |
| Jump / double-jump flip | W / Space (again in the air) | A | JUMP |
| Crouch / fast-fall | S | Stick down | ▼ |
| Punch / shoot / swing | Left click (or J/Z) | R2 | HIT |
| Block (tap to parry) | Right click / Shift (or K/X) | L2 | BLOCK |
| Throw your weapon | F / E / Q | X / B | THROW |
| Aim | Mouse | Right stick (auto-aims otherwise) | auto-aim |

## What's in it

- **Your own avatar, locked to a 2.5D plane.** A side camera frames every fighter like a
  couch fighting game, with zoom and screen shake.
- **Real ragdolls.** Big hits, explosions, stacked combos and KOs turn bodies into
  physics ragdolls (built from the avatar's own joints). Corpses can still be juggled.
- **Custom procedural animations, no uploaded assets:** a fighting stance, run cycle,
  jumps and falls, landing squash, jab-jab combos, block, guns that aim at your cursor,
  sword swings, throws, recoil, flinches, double-jump front flips and a victory pose.
  Every client animates every fighter, so everyone sees them.
- **8 weapons:** Popper (pistol), Scattergun, Buzzer (SMG), Longshot (sniper), Edge (sword
  that deflects bullets when blocking), Bonker (home-run bat), Fizzbomb (grenades) and
  Boomtube (rockets). Empty guns get tossed, and thrown weapons hurt.
- **Blocking and parries.** Block from the front to cut melee damage. Block right as a hit
  lands to parry, which ragdolls the attacker.
- **8 arenas with gimmicks:** Rooftop Rumble, Wheel of Woe (orbiting platforms), Saw Mill
  (conveyor plus saws), Swing Temple (pendulum platforms), Ice Floe (bobbing floes), Lift Off
  (elevators over spikes), Sunset Pillars and Neon Crossfire (a spinning bar that bats you
  away). After 60 s the ink rises (sudden death).
- **VFX:** sparks, impact rings, paint splats in the victim's color that stick to the map,
  muzzle flashes, tracers, shell casings, layered explosions, launch trails, slash trails,
  damage numbers, KO popups, weapon-drop beams and confetti.
- **SFX:** every sound is a layered recipe of built-in Roblox sounds processed with
  distortion, EQ, echo and reverb (see `src/client/Audio.luau`). Swap any `id` for your
  own `rbxassetid://` to re-skin it.
- **Bots** with their own colorful mannequin avatars. They chase, grab weapons, block,
  shoot, avoid ledges and double-jump back to the stage.
- **HUD:** scoreboard with avatar headshots and win pips, countdown, banners, kill feed,
  HP and ammo panel, crosshair, low-HP vignette, champion screen and touch controls.

## Tweak it

- `src/shared/Config.luau`: movement, damage, knockback, round rules, bot count, colors
- `src/shared/Weapons.luau`: weapon stats and their 3D models (built from boxes)
- `src/shared/Maps.luau`: arena layouts. Blocks are 2D rectangles extruded into 3D, and
  `motion` makes moving platforms and saws.
- `src/client/Animator.luau`: all the custom animations
- `src/client/Audio.luau`: sound recipes

## How it works

| Where | What |
| --- | --- |
| `src/server/init.server.luau` | rounds, spawning avatars and bots, weapon drops, state relay |
| `src/server/Combat.luau` | health, knockback, ragdolls, weapons, pickups, rockets, grenades, hit validation |
| `src/server/Arena.luau` | builds the 3D arenas, moving platforms (physics), hazards, lighting |
| `src/server/Bots.luau` | bot avatars and AI |
| `src/client/Controller.luau` | your fighter: movement, attacks, hit detection, knockback |
| `src/client/Animator.luau` | procedural R15 animation for everyone |
| `src/client/*` | camera, effects, sounds, HUD, name tags, input |
| `src/shared/*` | config, maps, weapons, rig and ragdoll helpers, motion, remotes |

Your client moves your avatar instantly and reports its own hits. The server validates
every hit (range, timing, ammo) and owns health, ragdolls, weapons, projectiles and bots.

`tools/check.sh` compile-checks every script with the Luau compiler and runs the arena
sanity tests (spawns on solid ground, deterministic shotgun spread).
