# Agent guidance: Blitzkampf (Godot)

Godot 4.7 re-implementation of the arena-shooter prototype in `../blitzkampf/` (three.js). That project is a **reference for gameplay and tuning numbers only**, not a structural template: where it worked around three.js limitations (hand-rolled collision, fixed-tick accumulator, procedural meshes, DOM HUD, WebAudio synthesis) this project uses the native Godot approach. Don't port code line by line; ask what the idiomatic Godot way is.

Open work is tracked in `TODO.md`; update it when finishing or adding tasks.

Status: single-player test arena is playable (movement, 3 weapons, targets, pickups, HUD, placeholder SFX). Multiplayer: players connect, spawn, move and can shoot each other, pick up and drop weapons, and see a Tab scoreboard (server-authoritative, no prediction yet; see `TODO.md` M4+). Not started: more maps, real art/audio.

## Stack and project settings

- GDScript with static typing; `class_name` on anything referenced from another script. Keep warnings clean.
- Renderer: **GL Compatibility** (keep it; web-export friendly). Physics: **Jolt**. Avoid features Compatibility lacks (e.g. don't rely on `Decal`/SDFGI/volumetrics).
- 60 Hz physics tick with **physics interpolation enabled** (project settings). Gravity is the project setting `physics/3d/default_gravity = 20`, read via `get_gravity()`; never hard-code it.
- Input goes through the **Input Map** (actions in `project.godot`), never raw keycodes. Gameplay code queries input via `GameInput` (`scripts/core/game_input.gd`), which reports nothing while the mouse isn't captured. The mouse is captured on start. Esc opens the **pause menu** (`PauseMenu`, pauses the scene tree, frees the cursor); Esc/Resume captures it again.
- Named physics layers: 1 `world`, 2 `player`, 3 `target`, 4 `pickup`, 5 `prop` (dropped weapon bodies). Bullets hit world+player+target; the player collides with world only; pickup `Area3D`s are on `pickup`.

## Layout

```
scenes/main.tscn            entry: arena + player + HUD + Sfx (scripts/core/main.gd wires signals)
scenes/maps/                maps are .tscn scenes, greyboxed with CSGBox3D (use_collision)
scenes/player/              player.tscn (CharacterBody3D, top-level Head/Camera3D, WeaponHolder, WeaponManager)
scenes/ui/pause_menu.tscn   pause menu (process mode Always); options live in the GameSettings autoload
scenes/weapons/             one *_model.tscn per weapon (imported model + "Muzzle" and "Sight" Marker3Ds), dropped_weapon, weapon_spawner
assets/models/quaternius_guns/  Quaternius Ultimate Gun Pack FBXs (CC0, see LICENSE.txt) used for the weapon models
assets/models/blasters/     Kenney Blaster Kit GLBs (CC0), tried first and currently unused
scenes/world/, scenes/ui/   target, HUD
resources/weapons/*.tres    WeaponDefinition data, resources/player/movement_settings.tres
audio/sfx/*.wav             placeholder sounds (regenerate: tools/generate_placeholder_sfx.gd)
scripts/<area>/             snake_case.gd files mirroring the scene areas
tools/                      smoke_test.gd, generate_placeholder_sfx.gd
```

## Architecture rules

- The only autoload is `GameSettings` (`scripts/core/game_settings.gd`): persisted display options (`user://settings.cfg`), applied at startup. Because autoloads don't exist yet when a `-s` test script compiles, `tools/` scripts must not reference scripts that use `GameSettings` by class type (e.g. type the pause menu as `CanvasLayer`).

- Scenes + nodes + signals: call down, signal up. `WeaponManager` and `Player` expose signals; HUD, `Sfx` and `Main` listen. Nothing reaches up into the HUD.
- Data in `Resource`s and `@export` vars, not constant files or magic numbers. Movement tuning is `MovementSettings` (`resources/player/movement_settings.tres`); weapon stats are `WeaponDefinition`. **Add a weapon = a new `.tres` + model scene, not a code branch.**
- Player movement is a `CharacterBody3D` with Quake-style accel/friction (`QuakeMovement`) feeding `velocity`, then `move_and_slide()`. Floor/slope/wall handling is the engine's job. No RigidBody player.
- **Input is a source, not a call**: gameplay never reads `Input`/`GameInput`. Each `Player` has a `PlayerInput` node; `input.frame()` returns that physics tick's `InputFrame` (move, yaw/pitch, held buttons, edge events), sampled once per tick from an `InputSource` (`LocalInput` = keyboard/mouse via `GameInput`, `ScriptedInput` = tests/bots; the network will add another). `Player` and `WeaponManager` consume frames only. A bot or remote player is a normal `Player` with a different source. Weapons are looked up by id through `WeaponCatalog` (`resources/weapons/catalog.tres`; add new weapons there).
- Mouse look is handled by the source in `PlayerInput._unhandled_input` (never tick-coupled; `input.look_yaw/look_pitch` are live). Yaw/pitch are plain floats on `Player` that follow them each render frame; the `Head` node is `top_level` with interpolation off and is positioned each render frame from `get_global_transform_interpolated()`. Don't parent the camera to the interpolated body or you get look lag/jitter.
- Cosmetic motion (recoil, flashes, crosshair gap, eye height, spawner spin/bob) uses `Tween`s, not per-frame damp code. Dropped weapons are real `RigidBody3D`s (keep `continuous_cd` on, or thrown weapons sometimes tunnel through the floor).
- Weapon logic lives in `WeaponManager` (child of `Player`): firing via `intersect_ray`, spread, ammo, reload, pickup, drop. Pickups are `PickupArea`s (spawners and dropped weapons both use one); `pickup_priority` makes dropped weapons win over spawners.
- Sounds are played by name through `Sfx` (`scripts/audio/sfx.gd`); swap sounds by replacing the `.wav` files.
- Maps are authored in the Godot editor as `.tscn`; there is no JSON map format or custom editor (the Godot editor is the map editor). Place `PlayerSpawn` (group `player_spawn`), targets and `WeaponSpawner` instances (`offers` is an exported array of `WeaponDefinition`).

## Multiplayer

- **Server-authoritative on Godot's high-level multiplayer (ENet)**. Roles: single player (offline peer, same code path), `--host` (listen server, plays too), `--server` (dedicated, headless), `--join=<address>`. `Net` (autoload, `scripts/net/net.gd`) owns the peer, role, CLI parsing (after `--`: `--host`, `--server`, `--join=`, `--port=`, `--scenario=`) and the join handshake with a protocol-version check (`Net.protocol_version`, bump it when the network protocol changes). The entry scene is `scenes/ui/main_menu.tscn`; a CLI role skips it. `Main` calls `Net.start()` and spawns one `Player` per peer with a `MultiplayerSpawner` (`_spawn_player`, node name = peer id).
- **Authority split**: the `Player` body (and its `WeaponManager`) is simulated only on the server (`is_multiplayer_authority()` guards in `_physics_process`); clients show replicated state (`StateSync` MultiplayerSynchronizer: position, velocity, yaw, pitch, stance, health, alive; setters on `stance`/`health`/`alive` react on clients). Input travels client to server as `InputFrame` packets (`NetInput` sends on the owning client every tick, `RemoteInput` serves them on the server; edge events are running counters so a lost packet loses nothing). `Player.is_local` marks the body this machine's human plays: it gets the camera, HUD and viewmodels; others get the `Visual` stand-in capsule.
- Never reference the `Net` autoload from scripts that `tools/` scripts type (`Player`, `WeaponManager`, `PlayerInput`...): `-s` scripts compile before autoloads exist. Use Godot's built-in `multiplayer` there.
- **Weapons online**: `WeaponManager` logic runs on the server only. The owning client holds a mirror fed by `_rpc_*` methods (weapon, ammo, reloading, aiming, spread, fired, hit/pickup events; requested in full when the player node appears, since earlier updates would hit a missing node) and re-emits the usual signals, so HUD/viewmodel/Sfx are unchanged. Every peer gets `_rpc_shot` (tracer + impact); other players' shots have no sound yet. Dropped weapons are created through the `DropSpawner` (`MultiplayerSpawner`, group `drop_spawner`, spawn function `WeaponManager.spawn_dropped`; data carries the weapon id, ammo and throw velocities); clients freeze them and show the replicated transform. `WeaponSpawner` replicates `offer_index`/`stocked`; `Target` flashes via RPC. Score (`Player.kills/deaths`) replicates for the `Scoreboard` (hold Tab). Bump `Net.protocol_version` when RPCs or replicated properties change.
- Pause behaviour online is "mouse released, game keeps running". Client-side prediction and interpolation come later (M4).

## Gameplay decisions carried over (don't relitigate)

- Sprint is just a higher speed cap, no stamina. Walk 7, sprint 11, crouch 3.5 m/s. Jump 7. Holding jump re-jumps on landing.
- Grounded with no input stops instantly; friction applies while steering. Air accel 30, air speed cap 7.
- Crouch is a held stance (Ctrl). A fresh crouch press while sprinting + grounded + moving starts a **slide**: entry speed at least 11, momentum-locked (friction only, no steering), speed held flat for 0.15 s then decays, ends on crouch release, leaving the ground, or dropping to crouch speed. You only stand up if there is headroom (`ShapeCast3D`).
- **Aiming down sights** (hold RMB, cancelled by reloading): `WeaponManager` tweens the weapon holder so the model's `Sight` marker sits on the camera axis `ads_sight_distance` in front of the camera, and zooms to the weapon's `ads_fov` over `ads_time`; releasing returns to the hip pose captured from `player.tscn`. All three are `WeaponDefinition` fields. Recoil moves the model node itself, not the holder, so it never fights the aim tween.
- **Akimbo**: `WeaponManager` has two `WeaponSlot`s, primary (right hand, `WeaponHolder`) and secondary (left, `WeaponHolderLeft`). `WeaponDefinition.one_handed` (pistol, SMG) weapons can be paired; two-handed ones (shotgun) always take the primary slot alone. With two weapons there is **no ADS**: LMB (`fire`) shoots the primary, RMB (`fire_secondary`, same button as `aim`) the secondary. This default mapping may become configurable later (the roles are separate Input Map actions). Each slot has its own ammo, cooldown and spread. R reloads every non-full weapon one after the other, left first (full weapons are skipped, nothing happens if all are full), and nothing can fire while any reload is running or queued; the crosshair shows the widest. Pickup rules: F with a one-handed primary adds/replaces the **secondary**; G replaces the **primary** (and swaps a lone weapon); a one-handed pickup over a two-handed primary replaces it; picking up a two-handed weapon drops everything held. Replaced weapons are dropped with their ammo.
- **Health and damage**: `Player` has `health` (100), `take_damage(amount, attacker)`, signals `health_changed`/`damaged`/`died`/`respawned`. Anything damageable exposes `take_damage(amount, attacker)` (`Target` ignores the amount and just flashes). Damage comes from `WeaponDefinition.damage` per hit. Dying drops everything held, locks controls (body still falls) and respawns after `respawn_delay` (3 s) at a random `player_spawn` marker (`Player.spawn()`, also used for the first spawn) with the starting weapon. The player's capsule on layer 2 is the hitbox bullets test; the shooter's own body is excluded from the ray.
- Weapons fire hitscan, automatic while held, gated by per-weapon cooldown. Ammo is **per weapon instance**: picking up a weapon (F/G, edge-triggered) always drops the weapon it replaces with its remaining ammo, even if it's the same type. Fresh spawner weapons are fully stocked. Reload is R, blocks firing, no auto-reload; empty mag can't fire.
- Spread is a flat set of named per-state fields on `WeaponDefinition` (ADS / hip standing / hip moving, moving = horizontal speed > 0.5 m/s). The crosshair renders the same spread value the shot uses. Add a state by adding a field, not a multiplier system.
- Spawners offer a random weapon from their list and respawn 8 s after pickup. Tracer lasts 0.1 s; impact marks are capped at 60 (oldest recycled) so scatter patterns stay visible.

## Differences from the three.js version (intentional)

- `move_and_slide()` collision instead of an AABB sweep, so there is no bit-exact determinism for client prediction. If multiplayer arrives, rethink prediction against Godot's high-level multiplayer rather than reviving the old shared-kinematics idea.
- Crash/diagnostics logging dropped (browser-only); use Godot's debugger and monitors.
- Weapon models are scenes wrapping imported models (currently Quaternius' CC0 Ultimate Gun Pack: pistol = Pistol_2, SMG = SubmachineGun_4, shotgun = Shotgun_3) instead of procedural meshes. The pack's FBXs are ~10x too big and face +X, so each model scene rotates the model 90 degrees about Y and scales it by 0.12 on its `Model` node. `Muzzle` and `Sight` are children of that `Model` node (positions in the model's native units), so the scale is the only number to change to resize a weapon; you may also want to adjust `ads_sight_distance` and the hip pose in `player.tscn`. To swap a model, change the instance in the `*_model.tscn` so the barrel points along -Z, and reposition its `Muzzle` (tracer origin, barrel tip) and `Sight` (rear-sight top; lines up with screen centre when aiming) markers. Model origin should be near the grip, since the viewmodel holder positions the hand. Pickups and dropped weapons re-centre whatever model they show (`ModelBounds`), and the dropped weapon's collider is sized from the model's bounds.

## Workflow

- Network tests: `godot --headless --path . -s res://tools/net_test.gd [-- scenario ...]` starts a dedicated server (or host) and client processes per scenario in `tools/net_scenarios/` (connect, two_clients, shoot, version_mismatch, host); results and logs land in `user://nettest/`. Add a scenario by subclassing `NetScenario` (`run_server`/`run_client`) and listing it in `net_test.gd`. By hand: `tools/run_local.sh [clients]` opens a host and N client windows (only the focused one gets input). Second machine: same git revision and Godot version, `godot --path . -- --join=<host LAN address>`, UDP port 7777 open. Simulate lag with `sudo tc qdisc add dev lo root netem delay 60ms 10ms loss 2%` (undo: `tc qdisc del dev lo root`).

- Run the game: `godot --path .` (or the Godot MCP `run_project` / `get_debug_output`). Debug overlay: backtick.
- After adding scripts with `class_name` or new assets, refresh the class cache/imports: `godot --headless --path . --import`. If a GLB was imported before its external texture existed, delete its entries in `.godot/imported/` and import again (touching the file isn't enough).
- Headless smoke test (scripted input: walk, sprint, slide, jump, shoot, reload, pickup/drop, akimbo): `godot --headless --path . -s res://tools/smoke_test.gd`; exits non-zero on failure. Keep it passing and extend it when adding gameplay. It uses `GameInput.force_active` because the headless display server doesn't keep the mouse mode.
- Regenerate placeholder sounds: `godot --headless --path . -s res://tools/generate_placeholder_sfx.gd`, then re-import.
- Don't hand-edit `.godot/`. Hand-editing `.tscn`/`.tres` is fine for small changes (keep ids unique, re-run the smoke test afterwards); prefer the editor for anything structural. Set project settings via the editor or `ProjectSettings` API, not by guessing the `project.godot` format.
- This working directory may not be a git repository; only commit when asked.

## Future work

- Multiplayer (Godot high-level multiplayer; server-authoritative pickups, ammo and hit registration, and spread rolls).
- Blender-authored props/weapons via Godot's native glTF import; replace the Kenney stand-in weapon models.
- Real audio, more maps, optional viewmodel `SubViewport` (no wall clipping, separate FOV), reload/draw animations.
