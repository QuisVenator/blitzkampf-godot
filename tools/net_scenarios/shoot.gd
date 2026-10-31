extends NetScenario
## Client 0 shoots client 1 across the arena: the server judges the hit, and the
## victim's own client sees its health drop (replicated).


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	await wait_seconds(0.5)
	var shooter := players()[0]
	var victim := players()[1]
	shooter.teleport(Vector3(10, 0, 6), 0.0)
	victim.teleport(Vector3(10, 0, -4), 0.0)
	var killer: Array[Node] = []
	victim.died.connect(func(attacker: Node) -> void: killer.append(attacker))
	var hurt := await wait_until(func() -> bool: return victim.health < 100, 15.0)
	check("server applied damage from a remote shooter", hurt)
	var dead := await wait_until(func() -> bool: return not killer.is_empty(), 15.0)
	check("victim died and kill is credited to the shooter", dead and killer[0] == shooter)
	check("shooter unharmed", shooter.health == 100)
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
		scripted.frame.fire = true
		await wait_seconds(3.0)
		scripted.frame.fire = false
	else:
		var damaged := await wait_until(func() -> bool: return me.health < 100, 15.0)
		check("victim client sees its replicated health drop", damaged)
		var dead := await wait_until(func() -> bool: return not me.alive, 15.0)
		check("victim client sees itself dead", dead)
		await wait_seconds(0.5)
