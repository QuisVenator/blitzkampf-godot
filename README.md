# Blitzkampf

A fast arena shooter in Godot 4.7 (GL Compatibility, Jolt physics). Work in progress.

- Quake-style movement with sprint, slide, stairs, ledge climbing and wall running
- Pistol, SMG and shotgun (akimbo for the one-handed ones), first-person hands, pickups and drops
- Server-authoritative multiplayer with client prediction and lag compensation (single player, host, dedicated server, join)
- Levels built in [TrenchBroom](https://trenchbroom.github.io/) through [FuncGodot](https://github.com/func-godot/func_godot_plugin), with a map selector in the menu

## Run

Needs Godot 4.7.

```
godot --path .                       # menu: single player / host / join
godot --path . -- --host             # listen server
godot --headless --path . -- --server --map=test_arena_map
godot --path . -- --join=<address>   # UDP port 7777
```

Tests: `godot --headless --path . -s res://tools/smoke_test.gd` and `godot --headless --path . -s res://tools/net_test.gd`.

## More

- `AGENTS.md`: architecture, conventions, networking and the map pipeline (including the one-time TrenchBroom setup)
- `TODO.md`: open work

Third-party assets keep their own licences (see the `LICENSE`/`License` files next to them): Quaternius gun pack and character library (CC0), Kenney Blaster Kit (CC0), FuncGodot (MIT).
