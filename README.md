# NEON RIFT — high-speed arena combat (Android demo)

A small single-player third-person action game built in **Godot 4.7** for Android.
It is a gameplay study of fast, S4 League–style arena combat: responsive sprinting,
jumping, air control, dodges, wall kicks, weapon swapping, melee combos and gunplay —
with an original identity, original code and legally usable assets only.

- **Install:** sideload `dist/NeonRift.apk` (arm64, Android 7.0+, landscape).
  Enable "Install unknown apps" for your file manager/browser, then open the APK.
- **Engine:** Godot 4.7.2 (Mobile/Vulkan renderer with automatic OpenGL ES 3 fallback).
- **Assets:** CC0 packs by Quaternius, Kenney and OpenGameArt artists, OFL fonts, plus
  original shaders, VFX and synthesized sounds — see [CREDITS.md](CREDITS.md).

## What's in the demo

| Area | Details |
|---|---|
| Arena | *Stratos Deck* — a floating sky platform at dusk: raised core with ramps, four towers joined by high walkways, wall-jump walls, pillars, cover, 6 jump pads, 5 repair kits, energy barrier, neon city below, broadcast drones |
| Player | One fighter (styled mannequin android) with 4 weapons, stamina (SP), overdrive meter |
| Enemies | **Striker** (fast blade fighter: telegraphed combos, dash slashes, dodges, circling), **Gunner** (keeps range, strafes, telegraphed bursts of dodgeable bolts), **Brute** (big, super-armored, charges and ground slams) |
| Modes | **Wave Assault** (5 escalating waves, score, combo multiplier, rank) and **Training Ground** (passive, respawning targets) |

### Movement (S4 League rules)
Movement follows S4 League's rules (researched from public wikis and player guides; no
game data was used):
- **Strafing**: the body always faces where the camera looks; the stick moves you relative
  to the camera (strafe and backpedal animations with spine twist).
- **Speed depends on your weapon**: blade 92 %, rifle and rail 83 %, scatter 79 % of the
  top speed, lower while firing or scoped (rail 67 %, scatter 75 %).
- **Sprint**: double-tap forward (or tap SPRINT / flick the stick forward twice). It lasts
  while you keep pushing forward and drains 5 SP/s; at 0 SP you can only run.
- **Somersault jump** with a fixed height (~1.9 m) and a short delay after each landing
  (firing a gun just before landing skips it).
- **Air dash / bunny hop**: sprinting in mid-air drops you faster, so sprint-jumps become
  quick low hops.
- **Side dodge**: JUMP while pushing left/right (20 SP): a duck-and-slide on the ground, a
  sideways aerial in the air. No invulnerability, but flinches can't interrupt it. The end
  lag can be jump-canceled (JUMP with the stick centred), and an air dodge can be
  jump-canceled too → **wave dashing** (costs SP fast). Sprinting also cancels the end lag.
- **Wall jump** (20 SP): only during a jump (not after walking off a ledge), next to a
  wall. You bounce off like a mirror — angle in = angle out (run in straight for the high
  180° kick, diagonally to travel along the wall). Kicking near the top of a wall vaults
  you over it (the "reverse wall jump").
- **Crouch** (toggle on touch, Ctrl on PC): ducks gunfire; no attacking while crouched.
- **Recoveries**: knocked flying → JUMP to land on your feet; knocked down → dodge to get
  up; staggered → dodge out ("faint") for 90 SP.
- **SP**: 100 max, refills at 22/s after 0.6 s. No wall running and no invulnerable dash.
- **Jump pads** launch you on exact ballistic arcs to towers and walkways.

### Combat
| Weapon | Primary | Special |
|---|---|---|
| **Arc Blade** | 3-hit combo (knockdown finisher), sprint → lunging dash slash, air slash → plunge slam | Heavy spin slash (AOE knockdown, costs SP) |
| **Pulse Rifle** | Automatic hitscan with tracers | Bouncing pulse grenade |
| **Scatter Cannon** | 9-pellet blast, staggers up close | **Recoil jump** — launch yourself with a point-blank blast |
| **Rail Lancer** | Piercing beam (multi-hit) | Scope zoom |

- Soft lock-on for melee, aim assist (bullet magnetism + reticle friction) for guns.
- Hit reactions: flinch, stagger, knockdown with get-up invulnerability, poise system.
- You can walk while slashing; cancel attack recovery with a dodge, jump or sprint;
  combos, hit-stop, camera shake, haptics.
- **Overdrive** (charges from damage): 8 s of +20 % speed, +35 % damage, infinite SP,
  activation blast and slow motion.
- Enemy attacks are telegraphed (glint, sound, **!** marker) so they can be dodged
  (enemies side-dodge under the same rules: Strikers cartwheel, the others slide);
  off-screen threat arrows and hit-direction indicators keep you aware.

### Presentation
- Layered animation: phase-synced locomotion blending, upper-body aiming layer with
  spine twist for strafing/backpedalling, crossfaded full-body action layer, procedural
  leaning, somersault/cartwheel flips, dodge afterimages.
- VFX: blade trails, slash arcs, sparks, hit flashes, muzzle flashes, tracers, rail beams,
  explosions, shockwaves, spawn beams, damage numbers, speed lines, dissolve-in/out.
- Procedural sky (ringed planet, stars, clouds), glow, ACES tonemapping, fog, dynamic
  shadows, emissive neon, animated jump pads and hex energy barrier.
- Music: driving drum & bass battle loop (seamless 32-bar loop) and a menu theme; ~60 SFX.

## Controls

**Touch (default on phones)**
- Left thumb: floating stick (flick it forward twice to sprint).
- Right side: drag to look. Hold **ATTACK** and drag to aim while firing.
- Buttons: ATTACK, SPECIAL, JUMP (becomes a side dodge while the stick points left/right —
  the icon switches to an arrow), SPRINT, CROUCH (toggle), RELOAD (guns), OVERDRIVE
  (lightning, when charged).
- Weapon tabs (top right) switch instantly; pause button top-right.
- Android back button pauses.

**Keyboard / mouse / gamepad (for testing on PC)**
WASD move · double-tap W sprint · mouse look · LMB attack · RMB special · Space jump ·
A/D + Space dodge · Ctrl crouch · Shift overdrive · Z camera view (centre/right/left) ·
1–4 or mouse wheel weapons · R reload · Esc pause. Gamepad: A jump/dodge, B crouch,
L3 sprint, R3 camera view.

**Settings:** look sensitivity, scoped sensitivity, mouse sensitivity, invert Y, aim assist,
camera view (centre/right/left shoulder), optional sprint-by-pushing-the-stick,
button size/opacity, left-handed layout, vibration, graphics quality (Low/Medium/High),
frame-rate cap (30/60/90/120), FPS counter, volumes.

## Building the APK

Requirements: Godot **4.7.2** editor (`godot` on PATH) with Android export templates,
Android SDK (build-tools 36.x, platform 36), JDK 17+ and (optionally) `xvfb-run` for the
shader baker.

```bash
./tools/build_apk.sh          # -> build/NeonRift.apk (signed, arm64-v8a)
```

Release signing uses `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`; if unset, the
script creates a local keystore in `build/` (not committed). The export enables Godot's
shader baker so shaders are precompiled (no first-use stutter on phones).

To open the project in the editor, open `game/project.godot`.

## Tests & tools

```bash
cd game
# S4 movement rules (sprint, jump, dodges, wave dash, mirror/reverse wall jumps, recoveries...)
godot --headless --path . --fixed-fps 60 res://tests/movement_test.tscn
# Synthetic multi-touch test of the on-screen controls
godot --headless --path . --fixed-fps 60 res://scenes/arena.tscn -- --touch-test --touch
# Autoplay bot (logs stats each second); add --mode=training or --god as needed
godot --headless --path . --fixed-fps 60 res://scenes/arena.tscn -- --bot --quit-frame=7200
# Screenshots: -- --shots=/tmp/out --shot-frames=60,120 --quit-frame=121 (needs a display)
# Character close-up sheet (materials, accessories, dissolve, near-camera fade; needs a display)
godot --path . --rendering-method mobile res://tests/closeup_film.tscn -- /tmp/closeup.png
```

- `game/tools/build_character_assets.gd` extracts the used animations from the Universal
  Animation Library GLBs into one library and builds standalone mannequin scenes.
- `tools/synth_sfx.py` regenerates the original synthesized sound effects.

## Project layout

```
game/
  scenes/            main_menu.tscn, arena.tscn (thin scenes; content is built in code)
  scripts/autoload/  settings, audio (pooled SFX + music), game (flow, input map), vfx
  scripts/core/      actor, weapon controller/DB, projectile, animation controller, visuals
  scripts/player/    player movement/combat, third-person camera
  scripts/enemy/     enemy AI
  scripts/world/     arena builder, jump pads, pickups, drones
  scripts/game/      arena root, wave director
  scripts/ui/        HUD, touch controls, menus, settings, theme
  shaders/           character, blade, trails, panels, neon, sky, barrier, VFX...
  assets/            models, animations, textures, audio, fonts (see CREDITS.md)
tools/               build_apk.sh, synth_sfx.py
```

## Legal

Neon Rift is an original fan-made gameplay study. S4 League was used purely as a
reference for game feel; no characters, maps, weapons, UI, sounds, names or branding from
it (or any other commercial game) are used. All third-party assets are CC0 or OFL; see
[CREDITS.md](CREDITS.md).
