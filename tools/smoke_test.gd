extends SceneTree
## Headless gameplay smoke test with scripted input.
## Run: godot --headless --path . -s res://tools/smoke_test.gd
## Exits non-zero if any check fails.

var _failures := 0
var _main: Node
var _player: Player
var _weapons: WeaponManager
var _hits := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_player = _main.get_node("Player")
	_weapons = _player.get_node("WeaponManager")
	_weapons.hit_confirmed.connect(func() -> void: _hits += 1)
	GameInput.force_active = true

	await _frames(30)
	_check("player settles on floor", _player.is_on_floor())
	_check("player stands at ground level", absf(_player.global_position.y) < 0.05)
	var spawn_zs := get_nodes_in_group(&"player_spawn").map(func(n: Node3D) -> float: return n.global_position.z)
	_check("spawned at a player_spawn marker", spawn_zs.any(func(z: float) -> bool: return is_equal_approx(_player.global_position.z, z)))

	# Walking, sprinting (start at the south wall so there is room to run).
	_player.teleport(Vector3(0, 0, 19), 0.0)
	await _frames(5)
	Input.action_press(&"move_forward")
	await _frames(40)
	_check_near("walk speed ~7", _player.horizontal_speed(), 7.0, 0.1)
	Input.action_press(&"sprint")
	await _frames(30)
	_check_near("sprint speed ~11", _player.horizontal_speed(), 11.0, 0.1)

	# Slide: fresh crouch press while sprinting.
	Input.action_press(&"crouch")
	await _frames(3)
	_check("slide started", _player.stance == Player.Stance.SLIDING)
	_check("slide speed >= 10.9", _player.horizontal_speed() >= 10.9)
	await _frames(20)
	var mid_slide := _player.horizontal_speed()
	await _frames(20)
	_check("slide decays", _player.horizontal_speed() < mid_slide)
	Input.action_release(&"crouch")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _frames(5)
	_check("stands after releasing crouch", _player.stance == Player.Stance.STANDING)
	await _frames(10)
	_check_near("instant stop on no input", _player.horizontal_speed(), 0.0, 0.01)

	# Jump.
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	_check("jump leaves floor", not _player.is_on_floor() and _player.velocity.y > 0.0)
	await _frames(90)
	_check("lands again", _player.is_on_floor())

	# Shooting a target dead ahead (spawn faces -Z at x=0, target at z=-14).
	_player.teleport(Vector3(0, 0, 8), 0.0)
	await _frames(5)
	Input.action_press(&"aim")
	await _frames(2)
	var mag_before := _weapons.primary.in_mag
	Input.action_press(&"fire")
	await _frames(3)
	Input.action_release(&"fire")
	_check("ammo decremented", _weapons.primary.in_mag == mag_before - 1)
	_check("target hit while aiming", _hits >= 1)
	Input.action_release(&"aim")
	await create_timer(0.6).timeout
	_check_near("hip fov restored", _player.camera.fov, 75.0, 0.1)

	# Aiming down sights: zoomed FOV, and the model's Sight marker sits on the camera axis.
	Input.action_press(&"aim")
	await create_timer(0.7).timeout
	_check("aiming", _weapons.is_aiming())
	_check_near("ads fov", _player.camera.fov, _weapons.primary.definition.ads_fov, 0.1)
	var sight := _player.camera.get_node("WeaponHolder").get_child(0).find_child("Sight", true, false) as Node3D
	var sight_local := _player.camera.to_local(sight.global_position)
	_check_near("sight centred horizontally", sight_local.x, 0.0, 0.002)
	_check_near("sight centred vertically", sight_local.y, 0.0, 0.002)
	Input.action_release(&"aim")
	await create_timer(0.4).timeout
	_check("not aiming after release", not _weapons.is_aiming())

	# Reload.
	Input.action_press(&"reload")
	await _frames(2)
	Input.action_release(&"reload")
	_check("reloading", _weapons.is_reloading())
	await _frames(90)
	_check("reload finished", not _weapons.is_reloading() and _weapons.primary.in_mag == _weapons.primary.definition.magazine_size)
	_check("reserve reduced by one round", _weapons.primary.reserve == _weapons.primary.definition.reserve_ammo - 1)

	# Pickup from a spawner that only offers shotguns at (10, 0.04, -12).
	_player.teleport(Vector3(10, 0, -11), 0.0)
	await _frames(10)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("picked up shotgun", _weapons.primary.definition.id == &"shotgun")
	await _frames(5)
	var dropped := _main.get_children().filter(func(n: Node) -> bool: return n is DroppedWeapon)
	_check("old weapon was dropped", dropped.size() == 1)

	# Walk over to the dropped pistol and take it back: it keeps its ammo.
	await _frames(90)
	var landed := dropped[0] as DroppedWeapon
	_player.teleport(landed.global_position + Vector3(0, 0.05, 0), 0.0)
	await _frames(5)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("picked dropped pistol back up", _weapons.primary.definition.id == &"pistol")
	_check("dropped pistol kept its ammo", _weapons.primary.in_mag == 8 and _weapons.primary.reserve == 23)

	await _test_akimbo()
	await _test_pause()
	await _test_bot()
	await _test_health()

	print("smoke test: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Akimbo: pairing one-handed weapons, per-hand firing, F/G replacement, two-handed pickups.
func _test_akimbo() -> void:
	var pistol: WeaponDefinition = load("res://resources/weapons/pistol.tres")
	var smg: WeaponDefinition = load("res://resources/weapons/smg.tres")
	var shotgun: WeaponDefinition = load("res://resources/weapons/shotgun.tres")
	_player.teleport(Vector3(0, 0, 8), 0.0)
	await _frames(5)
	_check("holding a lone pistol", _weapons.primary.definition == pistol and not _weapons.is_akimbo())
	var dropped_before := _dropped_count()

	_spawn_dropped(smg, 10, 20)
	await _frames(20)
	await _press(&"interact")
	_check("F adds a second one-handed weapon", _weapons.is_akimbo() and _weapons.secondary.definition == smg)
	_check("secondary keeps its ammo", _weapons.secondary.in_mag == 10 and _weapons.secondary.reserve == 20)
	_check("nothing dropped when pairing", _dropped_count() == dropped_before)
	_check("left viewmodel shown", _player.camera.get_node("WeaponHolderLeft").get_child_count() == 1)

	# No aiming while akimbo; each button shoots its own hand.
	Input.action_press(&"aim")
	await create_timer(0.4).timeout
	_check("no ADS while akimbo", not _weapons.is_aiming())
	_check_near("fov stays at hip", _player.camera.fov, 75.0, 0.1)
	var primary_mag := _weapons.primary.in_mag
	Input.action_release(&"aim")
	await _frames(2)
	Input.action_press(&"fire_secondary")
	await _frames(3)
	Input.action_release(&"fire_secondary")
	_check("RMB fires the secondary only", _weapons.secondary.in_mag < 10 and _weapons.primary.in_mag == primary_mag)
	var secondary_mag := _weapons.secondary.in_mag
	await create_timer(0.3).timeout
	Input.action_press(&"fire")
	await _frames(3)
	Input.action_release(&"fire")
	_check("LMB fires the primary only", _weapons.primary.in_mag == primary_mag - 1 and _weapons.secondary.in_mag == secondary_mag)

	# Reload: left first then right, skipping full weapons, no firing meanwhile.
	await create_timer(0.3).timeout
	var left_before := _weapons.secondary.in_mag
	await _press(&"reload")
	_check("left reloads first", _weapons.secondary.is_reloading() and not _weapons.primary.is_reloading())
	Input.action_press(&"fire")
	await _frames(3)
	Input.action_release(&"fire")
	_check("cannot fire while a weapon reloads", _weapons.primary.in_mag == primary_mag - 1)
	await create_timer(smg.reload_duration).timeout
	_check("then right reloads", _weapons.secondary.in_mag == smg.magazine_size and _weapons.primary.is_reloading())
	await create_timer(pistol.reload_duration + 0.2).timeout
	_check("both reloaded", not _weapons.is_reloading() and _weapons.primary.in_mag == pistol.magazine_size)
	await _press(&"reload")
	_check("nothing to reload when both full", not _weapons.is_reloading())
	Input.action_press(&"fire")
	await _frames(3)
	Input.action_release(&"fire")
	primary_mag = _weapons.primary.in_mag + 1
	await _press(&"reload")
	_check("only the non-full weapon reloads", _weapons.primary.is_reloading() and not _weapons.secondary.is_reloading())
	await create_timer(pistol.reload_duration + 0.2).timeout
	secondary_mag = _weapons.secondary.in_mag
	primary_mag = _weapons.primary.in_mag + 1

	# F replaces the secondary, G the primary.
	_spawn_dropped(pistol, 5, 6)
	await _frames(20)
	await _press(&"interact")
	_check("F replaces the secondary", _weapons.secondary.definition == pistol and _weapons.secondary.in_mag == 5)
	_check("primary untouched by F", _weapons.primary.definition == pistol and _weapons.primary.in_mag == primary_mag - 1)
	_check("replaced secondary was dropped", _dropped_count() == dropped_before + 1)

	_spawn_dropped(smg, 3, 4)
	await _frames(20)
	await _press(&"interact_alt")
	_check("G replaces the primary", _weapons.primary.definition == smg and _weapons.primary.in_mag == 3)
	_check("secondary untouched by G", _weapons.secondary.definition == pistol and _weapons.secondary.in_mag == 5)
	_check("replaced primary was dropped", _dropped_count() == dropped_before + 2)

	# A two-handed weapon takes the place of everything held.
	_spawn_dropped(shotgun, 2, 7)
	await _frames(20)
	await _press(&"interact")
	_check("two-handed pickup is alone in the primary", _weapons.primary.definition == shotgun and not _weapons.is_akimbo())
	_check("both held weapons were dropped", _dropped_count() == dropped_before + 4)
	_check("left viewmodel removed", _player.camera.get_node("WeaponHolderLeft").get_child_count() == 0)

	# One-handed over a two-handed primary replaces it instead of pairing.
	_spawn_dropped(pistol, 4, 4)
	await _frames(20)
	await _press(&"interact")
	_check("one-handed replaces a two-handed primary", _weapons.primary.definition == pistol and not _weapons.is_akimbo())
	# G with a lone one-handed weapon swaps it rather than pairing.
	_spawn_dropped(smg, 9, 9)
	await _frames(20)
	await _press(&"interact_alt")
	_check("G swaps a lone primary", _weapons.primary.definition == smg and not _weapons.is_akimbo())


## Esc pauses the tree and shows the menu; Esc again resumes.
func _test_pause() -> void:
	# Typed as CanvasLayer: this -s script compiles before autoloads (GameSettings) exist.
	var menu := _main.get_node("PauseMenu") as CanvasLayer
	_check("pause menu hidden at start", not menu.visible and not paused)
	_send_escape()
	await _frames(2)
	_check("Esc pauses and shows the menu", paused and menu.visible)
	var before := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(10)
	Input.action_release(&"move_forward")
	_check("player frozen while paused", _player.global_position.is_equal_approx(before))
	_send_escape()
	await _frames(2)
	_check("Esc resumes", not paused and not menu.visible)


## A second Player driven by ScriptedInput (the same path a bot or remote player
## will use): it walks, shoots the real player and gets the kill credit.
func _test_bot() -> void:
	var catalog := WeaponCatalog.get_default()
	_check("catalog finds weapons by id", catalog.find(&"smg") != null and catalog.find(&"smg").id == &"smg" and catalog.find(&"nope") == null)

	var bot := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	var script := ScriptedInput.new()
	bot.get_node("PlayerInput").source = script
	_main.add_child(bot)
	bot.teleport(Vector3(0, 0, 4), 0.0)
	_player.respawn_delay = 100.0
	_player.teleport(Vector3(0, 0, -8), 0.0)
	await _frames(10)

	script.frame.move = Vector2(0, -1)
	await _frames(30)
	_check("scripted player walks", bot.global_position.z < 4.0 - 2.0 and bot.horizontal_speed() > 6.0)
	script.frame.move = Vector2.ZERO
	await _frames(10)

	var killer: Array[Node] = []
	_player.died.connect(func(attacker: Node) -> void: killer.append(attacker))
	script.frame.yaw = 0.0
	script.frame.fire = true
	await create_timer(2.0).timeout
	script.frame.fire = false
	_check("scripted player shot the player", _player.health < 100)
	_check("kill is credited to the shooter", killer.size() == 1 and killer[0] == bot)
	_check("shooter isn't hurt by own shots", bot.health == 100)

	# Mouse look goes through PlayerInput and moves the view without waiting for a tick.
	_player.teleport(Vector3(0, 0, 8), 0.0)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	# (The window's stretch transform scales `relative`, so only check direction.)
	_check("mouse look turns the view", _player.yaw < -0.1 and is_equal_approx(_player.yaw, _player.input.look_yaw))

	# Put the real player back for the remaining tests.
	bot.queue_free()
	_player.respawn_delay = 0.5
	_player.spawn()
	await _frames(5)


## Damage, death (drops weapons, no control), respawn with a fresh loadout.
func _test_health() -> void:
	_player.respawn_delay = 0.5
	_player.teleport(Vector3(0, 0, 8), 0.0)
	_player.take_damage(30, null)
	_check("damage reduces health", _player.health == 70 and _player.alive)
	var dropped_before := _dropped_count()
	_player.take_damage(100, null)
	_check("dies at zero health", _player.health == 0 and not _player.alive)
	await _frames(3)
	_check("dead player drops weapon", _dropped_count() > dropped_before)
	var dead_at := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(15)
	Input.action_release(&"move_forward")
	_check("dead player can't move", _player.global_position.distance_to(dead_at) < 0.05)
	_player.take_damage(10, null)
	_check("no damage while dead", _player.health == 0)
	await create_timer(0.7).timeout
	_check("respawns alive at full health", _player.alive and _player.health == 100)
	_check("respawn restores starting weapon", _weapons.primary.definition.id == &"pistol" and not _weapons.is_akimbo())


func _send_escape() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


func _spawn_dropped(definition: WeaponDefinition, mag: int, spare: int) -> void:
	var dropped := (load("res://scenes/weapons/dropped_weapon.tscn") as PackedScene).instantiate() as DroppedWeapon
	dropped.setup(definition, mag, spare)
	_main.add_child(dropped)
	dropped.global_position = _player.global_position + Vector3(0, 0.3, 0)


func _dropped_count() -> int:
	return _main.get_children().filter(func(n: Node) -> bool: return n is DroppedWeapon).size()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	var ok := absf(actual - expected) <= tolerance
	print("%s %s (got %.3f, want %.3f)" % ["PASS" if ok else "FAIL", label, actual, expected])
	if not ok:
		_failures += 1
