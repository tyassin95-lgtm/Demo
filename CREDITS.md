# Credits & Licenses

**Neon Rift** is an original fan-made gameplay study. It is *inspired by the feel* of
fast arena action games (such as S4 League), but it contains **no assets, names, UI,
maps, sounds, characters, or branding** from S4 League or any other commercial game.
All code, level design, shaders, VFX and UI were written for this project.

Every third-party asset below was downloaded from the creator's official page, and
its license was checked at download time (license files are kept next to the assets
where the pack shipped one).

## 3D models & animations

| Asset | Author | Source | License | Used for |
|---|---|---|---|---|
| Universal Animation Library (Standard) | Quaternius | https://quaternius.itch.io/universal-animation-library (via https://quaternius.com/packs/universalanimationlibrary.html) | CC0 1.0 | Mannequin character + locomotion, jump, roll, sword, pistol, hit and death animations |
| Universal Animation Library 2 (Standard) | Quaternius | https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0 | Female mannequin, sword combo/dash, slide, ninja jump, knockback, get-up animations |
| Sci-Fi Essentials Kit (Standard) | Quaternius | https://quaternius.itch.io/sci-fi-essentials-kit | CC0 1.0 | Weapon models (rifle, sniper, revolver), health pack, crates, barrel, eye drone (ambient broadcast drones) |
| Modular Sci-Fi MegaKit (Standard) | Quaternius | https://quaternius.itch.io/modular-sci-fi-megakit | CC0 1.0 | Corner column model and trim textures (grit detail texture for the procedural panels) |
| Universal Base Characters (Standard) | Quaternius | https://quaternius.itch.io/universal-base-characters (via https://quaternius.com) | CC0 1.0 (`game/assets/characters/esper/License_Quaternius_UBC.txt`) | Male and female fighter bodies, eyes, eyebrows and hairstyles. The outfits are **original**: painted into the body texture by `tools/make_outfits.py` (the painted stubble is removed from the male face); hair and irises are tinted in the shader |

Textures from these packs were downscaled to 512 px for mobile (smaller APK and VRAM use). The fighter
scenes and head-space hair meshes are built from the Universal Base Characters glTFs by
`game/tools/build_esper_assets.gd`; the unmodified 1024 px skin textures used as painting input are kept in
`art/esper/`. Animations were
extracted into a single library (`game/assets/characters/mannequin_anims.res`)
by `game/tools/build_character_assets.gd`; the source GLBs are kept for reference.

## Visual effects textures

| Asset | Author | Source | License |
|---|---|---|---|
| Particle Pack (1.1) | Kenney (kenney.nl) | https://kenney.nl/assets/particle-pack | CC0 1.0 |

## Sound effects

| Asset | Author | Source | License |
|---|---|---|---|
| Sci-Fi Sounds | Kenney | https://kenney.nl/assets/sci-fi-sounds | CC0 1.0 |
| Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | CC0 1.0 |
| Interface Sounds | Kenney | https://kenney.nl/assets/interface-sounds | CC0 1.0 |
| Digital Audio | Kenney | https://kenney.nl/assets/digital-audio | CC0 1.0 |
| RPG Audio | Kenney | https://kenney.nl/assets/rpg-audio | CC0 1.0 |
| `gen_*.ogg` (whooshes, blade swings, blade hits, jump pad, overdrive, landing, etc.) | Original, synthesized for this project | `tools/synth_sfx.py` | Same as the project |

Kenney files were renamed by purpose (e.g. `laserSmall_000.ogg` → `rifle_shot_1.ogg`);
the mapping is listed in `game/assets/audio/sfx/SOURCES.txt`.

## Music

| Track | Author | Source | License | Notes |
|---|---|---|---|---|
| Hyper Ultra-Racing | cynicmusic | https://opengameart.org/content/hyper-ultra-racing | CC0 1.0 | Battle music. Cut to a seamless 32-bar loop (168 BPM) |
| Cyberpunk Moonlight Sonata | Joth | https://opengameart.org/content/cyberpunk-moonlight-sonata | CC0 1.0 | Menu music (v2 file). Re-encoded to OGG |

## Fonts

| Font | Author | Source | License |
|---|---|---|---|
| Orbitron | The Orbitron Project Authors (Matt McInerney) | https://github.com/google/fonts/tree/main/ofl/orbitron | SIL Open Font License 1.1 (`game/assets/fonts/Orbitron-OFL.txt`) |
| Rajdhani | Indian Type Foundry | https://github.com/google/fonts/tree/main/ofl/rajdhani | SIL Open Font License 1.1 (`game/assets/fonts/Rajdhani-OFL.txt`) |

## Engine & tools

- [Godot Engine 4.7.2](https://godotengine.org) — MIT License. Godot's own license and
  third-party notices are available in the engine (`Engine.get_license_text()`) and at
  https://godotengine.org/license.
- Jolt Physics (bundled with Godot) — MIT License.

## Thanks

Huge thanks to **Quaternius**, **Kenney**, **cynicmusic**, **Joth**, and the font authors
for releasing their work so generously.
