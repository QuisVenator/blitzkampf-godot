extends NetScenario
## A client with 80 ms of lag each way fires: the magazine and tracer answer at
## once (prediction), and the count settles on the server's, also after shots
## the server refuses because a reload had already started.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	var weapons := players()[0].get_node("WeaponManager") as WeaponManager
	await wait_until(func() -> bool: return players().is_empty(), 30.0)
	check("server ran", true)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var me := main.local_player
	var weapons := me.get_node("WeaponManager") as WeaponManager
	await wait_until(func() -> bool: return weapons.primary.definition != null and me._synced)
	await wait_seconds(0.5)
	var scripted := script_local_player()
	var full := weapons.primary.in_mag
	var tracers := [0]
	var effects := weapons.get_node("ShotEffects")
	effects.child_entered_tree.connect(func(_node: Node) -> void: tracers[0] += 1)

	# One shot: ammo and tracer within 3 ticks, far less than the 160 ms round trip.
	scripted.frame.fire = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	scripted.frame.fire = false
	check("magazine drops at once", weapons.primary.in_mag == full - 1)
	check("tracer appears at once", tracers[0] > 0)
	await wait_seconds(0.8)
	check("count agrees with the server afterwards (%d)" % weapons.primary.in_mag, weapons.primary.in_mag == full - 1)

	# Fire while the reload is starting: whatever the server refuses must not stick.
	scripted.frame.reload_pressed = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	scripted.frame.reload_pressed = false
	scripted.frame.fire = true
	await wait_seconds(0.4)
	scripted.frame.fire = false
	await wait_seconds(weapons.primary.definition.reload_duration + 1.0)
	check("after reload and refused shots the magazine is full again (%d of %d)" % [weapons.primary.in_mag, full], weapons.primary.in_mag == full)
