extends SceneTree
## Headless gameplay smoke test with scripted input.
## Run: godot --headless --path . -s res://tools/smoke_test.gd
## Exits non-zero if any check fails.

var _failures := 0
var _main: Node
var _player: Player
var _weapons: WeaponManager
var _hint_definition: WeaponDefinition
var _hint_choice := false
var _hits := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_player = _main.local_player
	_weapons = _player.get_node("WeaponManager")
	_weapons.hit_confirmed.connect(func() -> void: _hits += 1)
	_weapons.pickup_hint_changed.connect(func(d: WeaponDefinition, c: bool) -> void:
		_hint_definition = d
		_hint_choice = c)
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
	_check("the view widens in a fast slide (fov %.1f)" % _player.camera.fov, _player.camera.fov > 80.0)
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
	await _frames(100)
	_check("the view relaxes back when slow (fov %.1f)" % _player.camera.fov, _player.camera.fov < 75.5)

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
	var sight := _weapons.primary.holder.get_child(0).find_child("Sight", true, false) as Node3D
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
	_check("prompt names the shotgun in reach", _hint_definition != null and _hint_definition.id == &"shotgun" and not _hint_choice)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("picked up shotgun", _weapons.primary.definition.id == &"shotgun")
	await _frames(5)
	var dropped := _main.get_node("Drops").get_children().filter(func(n: Node) -> bool: return n is DroppedWeapon)
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

	await _test_ledge()
	await _test_stairs()
	await _test_wall_run()
	await _test_shotgun_and_smg()
	await _test_akimbo()
	await _test_pause()
	await _test_bot()
	await _test_health()
	await _test_console()

	print("smoke test: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Jumping at BoxA (top 1.5 m) climbs it; BoxB (top 2 m) is too high; walking into it does nothing.
func _test_ledge() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_release(&"crouch")
	await _frames(20)
	_player.teleport(Vector3(5, 0, -2.5), 0.0)
	await _frames(5)
	Input.action_press(&"move_forward")
	await _frames(20)
	_check("walking into a ledge does not climb it", _player.global_position.y < 0.1)
	_player.teleport(Vector3(5, 0, -2.5), 0.0)
	await _frames(5)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	var climbed := false
	for i in 60:
		await _frames(1)
		if _player.is_on_floor() and absf(_player.global_position.y - 1.5) < 0.05:
			climbed = true
			break
	Input.action_release(&"move_forward")
	await _frames(10)
	_check("jump toward a low ledge climbs it", climbed)
	_check("climb ends over the ledge", _player.global_position.z < -4.0)
	_player.teleport(Vector3(-6, 0, 5.5), 0.0)
	await _frames(5)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await _frames(60)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	_check("a too-high ledge is not climbed", _player.global_position.y < 1.5)
	await _frames(20)


## Six steps of 25 cm (50 cm deep) built here, walked up and down; then a 60 cm wall, which stays a wall.
func _test_stairs() -> void:
	Input.action_release(&"move_forward")
	var body := StaticBody3D.new()
	for i in 6:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 0.25 * (i + 1), 0.5)
		shape.shape = box
		shape.position = Vector3(0.0, box.size.y / 2.0, -0.25 - 0.5 * i)
		body.add_child(shape)
	var wall := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3.0, 0.6, 0.5)
	wall.shape = wall_box
	wall.position = Vector3(0.0, 0.3, -6.25)
	body.add_child(wall)
	# Away from everything else in the arena; the south wall is at z = 20.
	body.position = Vector3(-14.0, 0.0, 17.0)
	_main.add_child(body)
	await _frames(2)
	_player.teleport(Vector3(-14.0, 0.0, 19.0), 0.0)
	await _frames(10)
	Input.action_press(&"move_forward")
	var top := 0.0
	var eye := _player.head.global_position.y
	var eye_dips := 0
	var eye_jump := 0.0
	for i in 70:
		await _frames(1)
		top = maxf(top, _player.global_position.y)
		var now := _player.head.global_position.y
		if i < 45 and now < eye - 0.002:
			eye_dips += 1
		if i < 45:  # the climb itself; later the walk runs off the top and falls
			eye_jump = maxf(eye_jump, absf(now - eye))
		eye = now
	_check("walks up stairs without jumping (top %.2f)" % top, absf(top - 1.5) < 0.05)
	_check("the view glides up the stairs (no dips, biggest jump %.2f m)" % eye_jump, eye_dips == 0 and eye_jump < 0.15)
	_check("a 60 cm wall stops a walk", _player.global_position.z > 17.0 - 6.5 - 0.5)
	Input.action_release(&"move_forward")
	_player.teleport(Vector3(-14.0, 1.55, 17.0 - 3.0), 0.0)
	_player.input.set_look(PI, 0.0)
	await _frames(5)
	Input.action_press(&"move_forward")
	var airborne := 0
	for i in 60:
		await _frames(1)
		if not _player.get("_grounded"):
			airborne += 1
	Input.action_release(&"move_forward")
	_check("walks down stairs staying on them", airborne == 0 and _player.global_position.y < 0.05)
	body.queue_free()
	_player.input.set_look(0.0, 0.0)
	await _frames(5)


## A long wall at x = -11.5: a fast airborne body alongside it runs on it (sinking slowly, keeping its
## speed), a jump press throws it off the wall, a low start or a head-on wall is no run.
func _test_wall_run() -> void:
	Input.action_release(&"move_forward")
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 10.0, 40.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(-12.0, 5.0, -2.0)
	_main.add_child(body)
	await _frames(2)

	_player.teleport(Vector3(-11.2, 3.0, 16.0), 0.0)
	await _frames(10)
	_player.velocity = Vector3(0.0, 0.0, -9.0)
	Input.action_press(&"move_forward")
	await _frames(25)
	var running: bool = _player.get("_wall_run")
	_check("a fast jump along a wall starts a wall run", running)
	_check("the run keeps its speed (%.1f)" % _player.horizontal_speed(), _player.horizontal_speed() > 9.0)
	_check("and barely sinks", _player.global_position.y > 2.0)
	_check("the view leans away from the wall (roll %.2f)" % _player.get("_view_roll"), absf(_player.get("_view_roll")) > 0.05)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	_check("a jump press wall-jumps off the wall", not _player.get("_wall_run") and _player.velocity.x > 4.0 and _player.velocity.y > 4.0)
	await _frames(6)
	_check("the cooldown stops an instant re-grab", not _player.get("_wall_run"))
	Input.action_release(&"move_forward")
	await _frames(60)

	_player.teleport(Vector3(-11.2, 0.2, 16.0), 0.0)
	await _frames(5)
	_player.velocity = Vector3(0.0, 0.0, -9.0)
	Input.action_press(&"move_forward")
	var started := false
	for i in 40:
		await _frames(1)
		started = started or _player.get("_wall_run")
	Input.action_release(&"move_forward")
	_check("no wall run near the floor", not started)

	_player.teleport(Vector3(-8.0, 3.0, 5.0), PI / 2.0)
	_player.input.set_look(PI / 2.0, 0.0)
	await _frames(5)
	_player.velocity = Vector3(-9.0, 0.0, 0.0)
	Input.action_press(&"move_forward")
	started = false
	for i in 30:
		await _frames(1)
		started = started or _player.get("_wall_run")
	Input.action_release(&"move_forward")
	_check("no wall run head-on into a wall", not started)
	body.queue_free()
	_player.input.set_look(0.0, 0.0)
	await _frames(30)


## Console commands run offline through the same path as on a server.
func _test_console() -> void:
	var commands := DebugCommands.new()
	commands.run(_main, _player, "give shotgun")
	_check("console: give shotgun", _weapons.primary.definition.id == &"shotgun" and not _weapons.is_akimbo())
	commands.run(_main, _player, "give pistol")
	commands.run(_main, _player, "give smg secondary")
	_check("console: give secondary", _weapons.is_akimbo())
	_check("console: two-handed can't go secondary", commands.run(_main, _player, "give shotgun secondary").contains("two-handed"))
	commands.run(_main, _player, "damage 40")
	_check("console: damage", _player.health == _player.max_health - 40)
	commands.run(_main, _player, "heal")
	_check("console: heal", _player.health == _player.max_health)
	_check("console: unknown command", commands.run(_main, _player, "nonsense").begins_with("Unknown"))
	var before: int = _main.players().size()
	commands.run(_main, _player, "bot 2")
	await _frames(3)
	_check("console: bots added", _main.players().size() == before + 2)
	await _frames(120)
	commands.run(_main, _player, "botclear")
	await _frames(3)
	_check("console: bots removed", _main.players().size() == before)


## Akimbo: pairing one-handed weapons, per-hand firing, F/G replacement, two-handed pickups.
## The shotgun fires all its pellets (a tracer and an impact mark each, against a wall); the SMG's
## recoil animation restarts with every shot (it once showed only every other one).
func _test_shotgun_and_smg() -> void:
	_player.teleport(Vector3(0, 0, 8), 0.0)
	await _frames(10)
	var shotgun: WeaponDefinition = load("res://resources/weapons/shotgun.tres")
	_weapons.equip(WeaponManager.PRIMARY, shotgun)
	await _frames(40)
	var effects := _weapons.get_node("ShotEffects")
	var before := effects.get_child_count()
	await _press(&"fire")
	_check("a shotgun shot fires %d pellets (tracer + mark each)" % shotgun.pellets, effects.get_child_count() - before == shotgun.pellets * 2)

	var smg: WeaponDefinition = load("res://resources/weapons/smg.tres")
	_weapons.equip(WeaponManager.PRIMARY, smg)
	await _frames(60)
	var rig := _weapons.primary.viewmodel.get_node("Rig") as Node3D
	var shots: Array[int] = [0]
	_weapons.fired.connect(func(_definition: WeaponDefinition) -> void: shots[0] += 1)
	var kicks := 0
	var was_kicking := false
	Input.action_press(&"fire")
	for i in 42:
		await _frames(1)
		var kicking := rig.position.z > 0.03
		kicks += 1 if kicking and not was_kicking else 0
		was_kicking = kicking
	Input.action_release(&"fire")
	_check("the SMG recoils on every shot (%d kicks, %d shots)" % [kicks, shots[0]], shots[0] >= 6 and absi(kicks - shots[0]) <= 1)
	_weapons.equip(WeaponManager.PRIMARY, load("res://resources/weapons/pistol.tres"))
	await _frames(40)


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
	_check("prompt offers a choice for a one-handed weapon", _hint_definition == smg and _hint_choice)
	await _press(&"interact")
	_check("F adds a second one-handed weapon", _weapons.is_akimbo() and _weapons.secondary.definition == smg)
	_check("secondary keeps its ammo", _weapons.secondary.in_mag == 10 and _weapons.secondary.reserve == 20)
	_check("nothing dropped when pairing", _dropped_count() == dropped_before)
	_check("left viewmodel shown", _weapons.secondary.holder.get_child_count() == 1)

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
	_check("left viewmodel removed", _weapons.secondary.holder.get_child_count() == 0)

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
	bot.peer_id = 2
	bot.is_local = false
	_main.get_node("Players").add_child(bot)
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
	_main.get_node("Drops").add_child(dropped)
	dropped.global_position = _player.global_position + Vector3(0, 0.3, 0)


func _dropped_count() -> int:
	return _main.get_node("Drops").get_children().filter(func(n: Node) -> bool: return n is DroppedWeapon).size()


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
