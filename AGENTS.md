# Agent guidance: Blitzkampf (Godot)

Godot 4.7 re-implementation of the arena-shooter prototype in `../blitzkampf/` (three.js). That project is a **reference for gameplay and tuning numbers only**, not a structural template: where it worked around three.js limitations (hand-rolled collision, fixed-tick accumulator, procedural meshes, DOM HUD, WebAudio synthesis) this project uses the native Godot approach. Don't port code line by line; ask what the idiomatic Godot way is.

Status: single-player test arena is playable (movement, 3 weapons, targets, pickups, HUD, placeholder SFX). Not started: multiplayer, more maps, real art/audio.

## Stack and project settings

- GDScript with static typing; `class_name` on anything referenced from another script. Keep warnings clean.
- Renderer: **GL Compatibility** (keep it; web-export friendly). Physics: **Jolt**. Avoid features Compatibility lacks (e.g. don't rely on `Decal`/SDFGI/volumetrics).
- 60 Hz physics tick with **physics interpolation enabled** (project settings). Gravity is the project setting `physics/3d/default_gravity = 20`, read via `get_gravity()`; never hard-code it.
- Input goes through the **Input Map** (actions in `project.godot`), never raw keycodes. Gameplay code queries input via `GameInput` (`scripts/core/game_input.gd`), which reports nothing while the mouse isn't captured (the "Click to play" state).
- Named physics layers: 1 `world`, 2 `player`, 3 `target`, 4 `pickup`, 5 `prop` (dropped weapon bodies). Bullets hit world+target; the player collides with world only; pickup `Area3D`s are on `pickup`.

## Layout

```
scenes/main.tscn            entry: arena + player + HUD + Sfx (scripts/core/main.gd wires signals)
scenes/maps/                maps are .tscn scenes, greyboxed with CSGBox3D (use_collision)
scenes/player/              player.tscn (CharacterBody3D, top-level Head/Camera3D, WeaponHolder, WeaponManager)
scenes/weapons/             one *_model.tscn per weapon (with a "Muzzle" Marker3D), dropped_weapon, weapon_spawner
scenes/world/, scenes/ui/   target, HUD
resources/weapons/*.tres    WeaponDefinition data, resources/player/movement_settings.tres
audio/sfx/*.wav             placeholder sounds (regenerate: tools/generate_placeholder_sfx.gd)
scripts/<area>/             snake_case.gd files mirroring the scene areas
tools/                      smoke_test.gd, generate_placeholder_sfx.gd
```

## Architecture rules

- Scenes + nodes + signals: call down, signal up. `WeaponManager` and `Player` expose signals; HUD, `Sfx` and `Main` listen. Nothing reaches up into the HUD.
- Data in `Resource`s and `@export` vars, not constant files or magic numbers. Movement tuning is `MovementSettings` (`resources/player/movement_settings.tres`); weapon stats are `WeaponDefinition`. **Add a weapon = a new `.tres` + model scene, not a code branch.**
- Player movement is a `CharacterBody3D` with Quake-style accel/friction (`QuakeMovement`) feeding `velocity`, then `move_and_slide()`. Floor/slope/wall handling is the engine's job. No RigidBody player.
- Mouse look runs in `_unhandled_input` (never tick-coupled). Yaw/pitch are plain floats on `Player`; the `Head` node is `top_level` with interpolation off and is positioned each render frame from `get_global_transform_interpolated()`. Don't parent the camera to the interpolated body or you get look lag/jitter.
- Cosmetic motion (recoil, flashes, crosshair gap, eye height, spawner spin/bob) uses `Tween`s, not per-frame damp code. Dropped weapons are real `RigidBody3D`s.
- Weapon logic lives in `WeaponManager` (child of `Player`): firing via `intersect_ray`, spread, ammo, reload, pickup, drop. Pickups are `PickupArea`s (spawners and dropped weapons both use one); `pickup_priority` makes dropped weapons win over spawners.
- Sounds are played by name through `Sfx` (`scripts/audio/sfx.gd`); swap sounds by replacing the `.wav` files.
- Maps are authored in the Godot editor as `.tscn`; there is no JSON map format or custom editor (the Godot editor is the map editor). Place `PlayerSpawn` (group `player_spawn`), targets and `WeaponSpawner` instances (`offers` is an exported array of `WeaponDefinition`).

## Gameplay decisions carried over (don't relitigate)

- Sprint is just a higher speed cap, no stamina. Walk 7, sprint 11, crouch 3.5 m/s. Jump 7. Holding jump re-jumps on landing.
- Grounded with no input stops instantly; friction applies while steering. Air accel 30, air speed cap 7.
- Crouch is a held stance (Ctrl). A fresh crouch press while sprinting + grounded + moving starts a **slide**: entry speed at least 11, momentum-locked (friction only, no steering), speed held flat for 0.15 s then decays, ends on crouch release, leaving the ground, or dropping to crouch speed. You only stand up if there is headroom (`ShapeCast3D`).
- Weapons fire hitscan, automatic while held, gated by per-weapon cooldown. Ammo is **per weapon instance**: picking up a weapon (F, edge-triggered) always drops the held one with its remaining ammo, even if it's the same type. Fresh spawner weapons are fully stocked. Reload is R, blocks firing, no auto-reload; empty mag can't fire.
- Spread is a flat set of named per-state fields on `WeaponDefinition` (ADS / hip standing / hip moving, moving = horizontal speed > 0.5 m/s). The crosshair renders the same spread value the shot uses. Add a state by adding a field, not a multiplier system.
- Spawners offer a random weapon from their list and respawn 8 s after pickup. Tracer lasts 0.1 s; impact marks are capped at 60 (oldest recycled) so scatter patterns stay visible.

## Differences from the three.js version (intentional)

- `move_and_slide()` collision instead of an AABB sweep, so there is no bit-exact determinism for client prediction. If multiplayer arrives, rethink prediction against Godot's high-level multiplayer rather than reviving the old shared-kinematics idea.
- Crash/diagnostics logging dropped (browser-only); use Godot's debugger and monitors.
- Weapon models are scenes instead of procedural meshes, ready to be replaced by Blender/glTF models.

## Workflow

- Run the game: `godot --path .` (or the Godot MCP `run_project` / `get_debug_output`). Debug overlay: backtick.
- After adding scripts with `class_name` or new assets, refresh the class cache/imports: `godot --headless --path . --import`.
- Headless smoke test (scripted input: walk, sprint, slide, jump, shoot, reload, pickup/drop): `godot --headless --path . -s res://tools/smoke_test.gd`; exits non-zero on failure. Keep it passing and extend it when adding gameplay. It uses `GameInput.force_active` because the headless display server doesn't keep the mouse mode.
- Regenerate placeholder sounds: `godot --headless --path . -s res://tools/generate_placeholder_sfx.gd`, then re-import.
- Don't hand-edit `.godot/`. Hand-editing `.tscn`/`.tres` is fine for small changes (keep ids unique, re-run the smoke test afterwards); prefer the editor for anything structural. Set project settings via the editor or `ProjectSettings` API, not by guessing the `project.godot` format.
- This working directory may not be a git repository; only commit when asked.

## Future work

- Multiplayer (Godot high-level multiplayer; server-authoritative pickups, ammo and hit registration, and spread rolls).
- Blender-authored props/weapons via Godot's native glTF import; replace the primitive weapon model scenes.
- Real audio, more maps, optional viewmodel `SubViewport` (no wall clipping, separate FOV), ADS FOV zoom.
