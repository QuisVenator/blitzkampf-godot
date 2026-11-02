# TODO

Rough order of intent, not a commitment. Tick items off (and move them to Done) as they land.

## Next up
- [ ] Pause menu: add more options (mouse sensitivity, volume, key rebinding, akimbo button scheme)
- [ ] Movement ideas (collect and estimate; tune via `MovementSettings` / `QuakeMovement`)
- [ ] Reload animation (viewmodel; left hand first when akimbo)
- [ ] Sniper weapons: scope overlay, higher zoom, hidden viewmodel while scoped (new `WeaponDefinition` mode, not a code branch)

## Multiplayer path (plan: server-authoritative, ENet, listen-server + headless dedicated; see AGENTS.md when it lands)
- [x] Lag compensation for hit registration (rewind player poses to the shooter's view time)
- [ ] M3 leftovers: kill feed, match end / round limits
- [ ] Better bots: navigation mesh pathing, pick up weapons, difficulty levels, bot names/count in the menu

## Later
- [ ] Health, damage and respawn (foundation for character model, melee and multiplayer)
- [ ] Player hitbox (together with health/damage)
- [ ] Melee weapons (close-range hit shape, swing animations; may need a weapon-slot rethink)
- [ ] Multiplayer (Godot high-level multiplayer; server-authoritative pickups, ammo, hits, spread)
- [ ] Real audio, more maps, optional viewmodel `SubViewport`

## Ideas / open questions
- [ ] Make the akimbo button scheme configurable (LMB/RMB roles are separate Input Map actions)
- [ ] Hide the crosshair while aiming down sights?
- [ ] Delete unused Kenney Blaster Kit assets (`assets/models/blasters/`)
- [ ] Debug helpers: teleport / free-fly camera
- [ ] Reload sound plays once per weapon when akimbo; maybe once
- [ ] Lighting is dimmer than the three.js original

## Character follow-ups
- [ ] First-person arms in the viewmodel (instead of the floating gun)
- [ ] Better animations: strafe/backwards locomotion, slide, reload/shoot/hit reactions, two-handed poses for the shotgun, akimbo arm poses (Universal Animation Library Pro or Universal Base Characters for a nicer mesh)
- [ ] Footstep/hit-reaction sync, head hitbox (Hit_Head animation exists)

## Done
- [x] Third-person character model (Quaternius mannequin) with animation tree, held weapons and replicated held-weapon ids
- [x] On-screen pickup prompt (`WeaponManager.pickup_hint_changed` -> HUD `PickupLabel`; shows F/G choices when a one-handed weapon meets a one-handed primary)
- [x] Positional sounds for other players (shots, reloads, pickups, jumps, footsteps)
- [x] Debug console (F1) with give/damage/heal/kill/tp/bot commands; simple AI bots (`BotInput`); `console` net scenario
- [x] M4 Smooth feel: `NetSim` lag/loss flags, remote-player interpolation, client prediction + reconciliation (`prediction` net scenario)
- [x] M3 Networked combat: weapon/ammo mirror for the owner, shot tracers/impacts for everyone, dropped weapons via spawner, synced pickups/targets, kills/deaths + Tab scoreboard, `weapons` net scenario
- [x] M2 Connect/spawn/replicate: `Net` autoload + handshake/version check, main menu (single/host/join), spawner, input forwarding, state sync, third-person stand-in bodies, `tools/net_test.gd` (server+clients as processes), `tools/run_local.sh`
- [x] M1 Input split: `InputFrame` + `PlayerInput` with `LocalInput`/`ScriptedInput` sources, `WeaponCatalog`; a scripted bot player can walk and shoot in the smoke test
- [x] M0 Combat basics: health, damage, death (drops weapons), respawn at a random spawn, HUD health, `take_damage`, players hit by hitscan
- [x] Pause menu (Esc) with Resume, resolution, fullscreen, Quit; settings persisted in `user://settings.cfg`
- [x] Movement, 3 weapons, targets, pickups/drops, HUD, placeholder SFX
- [x] Aiming down sights, Quaternius weapon models
- [x] Akimbo for one-handed weapons (F replaces left, G replaces right; two-handed drops both)
- [x] Reload order for akimbo (left then right, skip full, no firing meanwhile)
