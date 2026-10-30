# TODO

Rough order of intent, not a commitment. Tick items off (and move them to Done) as they land.

## Next up
- [ ] Pause menu: add more options (mouse sensitivity, volume, key rebinding, akimbo button scheme)
- [ ] Movement ideas (collect and estimate; tune via `MovementSettings` / `QuakeMovement`)
- [ ] Reload animation (viewmodel; left hand first when akimbo)
- [ ] Sniper weapons: scope overlay, higher zoom, hidden viewmodel while scoped (new `WeaponDefinition` mode, not a code branch)

## Later
- [ ] Health, damage and respawn (foundation for character model, melee and multiplayer)
- [ ] Player hitbox (together with health/damage)
- [ ] Character model (rig, animations, third-person body); decide on multiplayer first
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

## Done
- [x] Pause menu (Esc) with Resume, resolution, fullscreen, Quit; settings persisted in `user://settings.cfg`
- [x] Movement, 3 weapons, targets, pickups/drops, HUD, placeholder SFX
- [x] Aiming down sights, Quaternius weapon models
- [x] Akimbo for one-handed weapons (F replaces left, G replaces right; two-handed drops both)
- [x] Reload order for akimbo (left then right, skip full, no firing meanwhile)
