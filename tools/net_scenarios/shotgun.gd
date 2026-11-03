extends NetScenario
## Client 0 shoots client 1 with a shotgun at close range: the server rolls the pellets (the
## shooter's client rolled the same ones for its tracers), the pellets' damage adds up to one
## hit, and the victim's client hears one gunshot per shot, not one per pellet.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	await wait_seconds(0.5)
	var shooter := players()[0]
	var victim := players()[1]
	shooter.teleport(Vector3(10, 0, 6), 0.0)
	victim.teleport(Vector3(10, 0, 2), 0.0)
	var weapons := shooter.get_node("WeaponManager") as WeaponManager
	weapons.equip(WeaponManager.PRIMARY, load("res://resources/weapons/shotgun.tres"))
	var shots := [0]
	weapons.fired.connect(func(_definition: WeaponDefinition) -> void: shots[0] += 1)
	await wait_until(func() -> bool: return victim.health < 100, 15.0)
	var first_damage := 100 - victim.health
	check("one shotgun shot hurt the victim with several pellets (%d damage)" % first_damage, first_damage >= 48 and first_damage % 12 == 0)
	var dead := await wait_until(func() -> bool: return not victim.alive, 15.0)
	check("and the next shot killed it", dead and shots[0] <= 3)
	await wait_until(func() -> bool: return players().is_empty(), 25.0)


func run_client() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	var me := main.local_player
	var scripted := script_local_player()
	await wait_until(func() -> bool: return me.global_position.x > 9.0)
	if me.global_position.z > 5.0:
		scripted.frame.yaw = 0.0
		# Wait for the server to put the shotgun in our hands.
		var weapons := me.get_node("WeaponManager") as WeaponManager
		await wait_until(func() -> bool: return weapons.primary.definition != null and weapons.primary.definition.id == &"shotgun")
		await wait_seconds(0.3)
		var effects := weapons.get_node("ShotEffects")
		var before := effects.get_child_count()
		scripted.frame.fire = true
		await wait_seconds(0.15)
		scripted.frame.fire = false
		check("the shooter sees all pellets' tracers at once", effects.get_child_count() - before >= weapons.primary.definition.pellets)
		scripted.frame.fire = true
		await wait_seconds(3.0)
		scripted.frame.fire = false
	else:
		var shooter: Player = players().filter(func(p: Player) -> bool: return not p.is_local)[0]
		var heard: Array[StringName] = []
		(shooter.get_node("WeaponManager") as WeaponManager).heard.connect(func(sound: StringName, _at: Vector3, _pitch: float) -> void: heard.append(sound))
		await wait_until(func() -> bool: return not me.alive, 15.0)
		var shots_heard := heard.count(&"fire")
		check("the victim hears a gunshot per shot, not per pellet (%d heard)" % shots_heard, shots_heard >= 1 and shots_heard <= 4)
		await wait_seconds(0.5)
