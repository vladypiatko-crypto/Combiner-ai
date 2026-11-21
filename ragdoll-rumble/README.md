# Ragdoll Rumble

A side-view, ragdoll-physics party brawler for Roblox. You fight as **your own avatar** in a
3D world viewed from the side, moving only left and right. Punch, block, grab the weapons
that fall from the sky, and send people flying. The last one standing wins the round, and
the first to 5 round wins is the champion.

## Play it

1. Open `build/RagdollRumble.rbxlx` in Roblox Studio (File → Open from File) and press **Play**.
2. You spawn in **The Arcade** (the lobby). Punch the training dummies, roll crates, or stand
   in the portal / press **READY UP**. The match starts when the timer runs out (or as soon
   as everyone is ready). Bots fill the empty slots.
3. Multiplayer test: Test → Clients and Servers.

### Two Studio settings worth turning on

- **Game Settings → Security → Enable Studio Access to API Services**, so coins and crate
  items save. Without it the game still works; progress just isn't saved, and the HUD tells you.
- **Game Settings → Security → Allow Mesh / Image APIs** (if your Studio shows it). The
  Blender models are built in-game with EditableMesh. If that's blocked, the game falls back
  to part-built models automatically. The admin panel's Players tab shows which mode you're in.

Also keep **Avatar type = R15**. The project already sets it, but if you publish, check
Game Settings → Avatar.

### Live sync with Rojo

```bash
rojo serve
```

Then Connect in the Rojo plugin. To rebuild the place file:

```bash
rojo build default.project.json -o build/RagdollRumble.rbxlx
```

## Controls

| Action                  | Keyboard / mouse               | Gamepad    | Touch          |
| ----------------------- | ------------------------------ | ---------- | -------------- |
| Move                    | A / D                          | Left stick | ◀ ▶            |
| Jump / double-jump flip | W / Space (again in the air)   | A          | JUMP           |
| Crouch / fast-fall      | S                              | Stick down | ▼              |
| Punch / shoot / swing   | Left click (or J / Z)          | R2         | HIT            |
| Block (tap = parry)     | Right click / Shift (or K / X) | L2         | BLOCK          |
| Throw your weapon       | F / Q                          | X / B      | THROW          |
| Use a lobby station     | E                              | Y          | tap the prompt |
| Controls help           | H                              | Select     |                |
| Admin panel             | F2 or `                        |            | ADMIN button   |

## What's in it

- **Your avatar on a 2.5D plane** with a couch-fighter camera that frames everyone.
- **Real ragdolls** from your avatar's own joints (big hits, explosions, stacked combos, KOs).
- **Procedural animations, no uploaded assets.** Spring-driven joints give a fighting stance,
  a run cycle with torso twist, jumps and falls, landing squash, jab combos, block, aiming
  that follows your cursor, sword swings with slash arcs, throws, recoil, flinches, front
  flips and a victory dance.
- **Lobby (The Arcade):** crate machine, locker, ready portal, a live leaderboard, the 3D logo,
  and a training zone with dummies and free weapons to test.
- **Crates:** Finisher Crates (an effect that plays when you KO someone) and Entrance Crates
  (an effect when you spawn). 24 items across 8 rarities, from Common up to Glitched
  (1 in 30,000). Rolls get a full reveal: a spinning 3D crate, a slowing name ticker,
  tier-by-tier build-up flashes, strobes for Mythic, rainbow for Celestial, a glitch screen
  for Glitched, then a reveal card. Legendary+ pulls are announced to the whole server.
- **Coins:** +15 per KO, +30 per round win, +150 for a match win, +20 for playing. Saved
  with DataStore.
- **Admin panel** (Studio testers, the game owner, or `Config.ADMINS`), all validated
  server-side:
  - Match: start, skip, end, pick the next map, sudden death.
  - Bots: on/off, fill count, difficulty, passive, sparring bots.
  - Players: heal, KO, god mode, ragdoll, coins.
  - Weapons: give or drop any weapon.
  - Crates: force a rarity, luck, free rolls.
  - Debug: server error/warning console.
- **Blender models** (`blender/build_models.py`): all 8 weapons, both crates, the gacha
  machine, locker, trophy, portal, lamps, saw blades, spikes, the logo and the VFX meshes.
  Previews are in `blender/renders/`, and OBJ copies are in `blender/exports/`.
- **VFX / SFX:** paint splats, slash arcs, star bursts, zoom-punch on heavy hits, layered
  explosions, tracers, muzzle flashes and more. Sounds are layered recipes of built-in
  Roblox sounds run through distortion, EQ, echo and reverb.
- **8 arenas with gimmicks** plus sudden-death rising ink.
- **UI:** profile chip with your headshot and coins, phase pill, fighter bar with
  HP / damage trails / win pips / KO stamps, kill feed, results podium, locker, settings
  (volume, shake, damage numbers, reduce flashing, quick rolls, FPS), and touch controls.

## Tweak it

| File                        | What                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------- |
| `src/shared/Config.luau`    | movement, damage, rounds, coins, crate cost, bots, admins                                             |
| `src/shared/Cosmetics.luau` | crate items and their "1 in N" odds                                                                   |
| `src/shared/Weapons.luau`   | weapon stats                                                                                          |
| `src/shared/Maps.luau`      | arenas + the lobby layout                                                                             |
| `src/client/Animator.luau`  | every animation                                                                                       |
| `src/client/Audio.luau`     | sound recipes (swap in your own `rbxassetid://` if you like)                                          |
| `blender/build_models.py`   | the models. Run `blender --background --python blender/build_models.py` to regenerate `MeshData.luau` |

## How it works

Your client moves your avatar instantly and reports its own hits. The server validates every
hit (range, timing, ammo, same zone) and owns health, ragdolls, weapons, projectiles, bots,
coins, data, crate rolls and admin actions. The lobby (y ≈ 1000) and the arena (y ≈ 0) exist
at the same time, so the lobby stays live while a match runs.

`tools/check.sh` compile-checks every script with the Luau compiler and runs the tests
(arena spawns stand on solid ground, deterministic spreads, crate odds).
