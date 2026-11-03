extends NetScenario
## Client 0 shoots client 1 across the arena: the server judges the hit, and the
## victim's own client sees its health drop (replicated). The shooter keeps firing (and
## reloads when the magazine is empty) until its client sees the victim die, so a few
## missed shots only delay the kill; a shooter that can't kill within `KILL_TIMEOUT` fails.

const KILL_TIMEOUT := 20.0


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	await wait_seconds(0.5)
	var shooter := players()[0]
	var victim := players()[1]
	shooter.teleport(Vector3(10, 0, 6), 0.0)
	victim.teleport(Vector3(10, 0, -4), 0.0)
	var killer: Array[Node] = []
	victim.died.connect(func(attacker: Node) -> void: killer.append(attacker))
	var shots := [0]
	var hits := [0]
	(shooter.get_node("WeaponManager") as WeaponManager).fired.connect(func(_definition: WeaponDefinition) -> void: shots[0] += 1)
	victim.damaged.connect(func(_amount: int, _attacker: Node) -> void: hits[0] += 1)
	var hurt := await wait_until(func() -> bool: return victim.health < 100, KILL_TIMEOUT)
	check("server applied damage from a remote shooter", hurt)
	var dead := await wait_until(func() -> bool: return not killer.is_empty(), KILL_TIMEOUT)
	check("victim died and kill is credited to the shooter", dead and killer[0] == shooter)
	check("shooter unharmed", shooter.health == 100)
	# A stationary victim dead ahead must be hit by nearly every shot (a lag compensation bug once made
	# it half of them); the shots fired after the kill count as misses, hence the margin.
	check("most shots hit a stationary target (%d of %d)" % [hits[0], shots[0]], hits[0] * 10 >= shots[0] * 6)
	await wait_until(func() -> bool: return players().is_empty(), 25.0)


func run_client() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	var me := main.local_player
	var scripted := script_local_player()
	# The server places one player at (10, 6) (shooter) and one at (10, -4) (victim);
	# x > 9 tells that apart from the spawn markers.
	await wait_until(func() -> bool: return me.global_position.x > 9.0)
	if me.global_position.z > 5.0:
		scripted.frame.yaw = 0.0
		var weapons := me.get_node("WeaponManager") as WeaponManager
		var victim: Player = players().filter(func(p: Player) -> bool: return not p.is_local)[0]
		var deadline := Time.get_ticks_msec() + int(KILL_TIMEOUT * 1000.0)
		while victim.alive and Time.get_ticks_msec() < deadline:
			scripted.frame.fire = true
			scripted.frame.reload_pressed = weapons.primary.in_mag == 0 and not weapons.is_reloading()
			await get_tree().physics_frame
		scripted.frame.fire = false
		await wait_seconds(0.5)
	else:
		var shooter: Player = players().filter(func(p: Player) -> bool: return not p.is_local)[0]
		var heard: Array[StringName] = []
		(shooter.get_node("WeaponManager") as WeaponManager).heard.connect(func(sound: StringName, _at: Vector3, _pitch: float) -> void: heard.append(sound))
		var damaged := await wait_until(func() -> bool: return me.health < 100, KILL_TIMEOUT)
		check("victim client hears the shooter's gunshots", await wait_until(func() -> bool: return &"fire" in heard))
		check("victim client sees its replicated health drop", damaged)
		var dead := await wait_until(func() -> bool: return not me.alive, KILL_TIMEOUT)
		check("victim client sees itself dead", dead)
		await wait_seconds(0.5)
