extends NetScenario
## Lag compensation: a client with 80 ms of lag each way shoots at a bot that strafes
## at up to 6 m/s, aiming at where it sees the bot. Without rewinding the server
## would aim 2 m behind it; with it the shots must land.

const AMPLITUDE := 3.0
const OMEGA := 2.0
const DISTANCE := 5.0
const SHOOT_SECONDS := 6.0


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	var shooter := players()[0]
	var weapons := shooter.get_node("WeaponManager") as WeaponManager
	BotInput.mode = BotInput.Mode.IDLE
	var bot := main.spawn_bot()
	await wait_seconds(0.5)

	# Somewhere in the arena with a clear view along one direction.
	var forward := _find_clear_spot(shooter)
	check("found open ground for the duel", forward != Vector3.ZERO)
	var side := forward.cross(Vector3.UP)
	var centre := shooter.global_position + forward * DISTANCE
	bot.max_health = 100000
	bot.health = bot.max_health
	var hits := [0]
	bot.damaged.connect(func(_amount: int, _attacker: Node) -> void: hits[0] += 1)
	var shots := [0]
	weapons.fired.connect(func(_definition: WeaponDefinition) -> void: shots[0] += 1)

	var started := Time.get_ticks_msec()
	# Runs until the client has finished shooting and left.
	while is_instance_valid(weapons) and Time.get_ticks_msec() - started < 30000:
		await get_tree().physics_frame
		if not is_instance_valid(weapons):
			break
		var t := (Time.get_ticks_msec() - started) / 1000.0
		bot.global_position = centre + side * sin(t * OMEGA) * AMPLITUDE
		bot.velocity = Vector3.ZERO
		weapons.primary.in_mag = 99
	print("shots %d, hits %d" % [shots[0], hits[0]])
	check("enough shots were fired (%d)" % shots[0], shots[0] >= 10)
	check("moving target is hit despite the lag (%d of %d)" % [hits[0], shots[0]], hits[0] >= shots[0] / 2)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var me := main.local_player
	await wait_until(func() -> bool: return me._synced)
	var scripted := script_local_player()
	var found := []
	await wait_until(func() -> bool:
		for player in players():
			if player.is_bot:
				found.append(player)
		return not found.is_empty())
	var bot: Player = found[0]
	await wait_seconds(1.5)  # the server moves us to the duel spot; let the client resync
	var deadline := Time.get_ticks_msec() + int(SHOOT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var target := bot.global_position + Vector3.UP * 0.9
		var to := target - me.head.global_position
		scripted.frame.yaw = atan2(-to.x, -to.z)
		scripted.frame.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		scripted.frame.aim = true
		scripted.frame.fire = true


## Moves `shooter` to a spawn marker with open space around and returns the
## direction (unit, horizontal) to duel along.
func _find_clear_spot(shooter: Player) -> Vector3:
	var space := shooter.get_world_3d().direct_space_state
	for spawn in shooter.get_tree().get_nodes_in_group(&"player_spawn"):
		var origin := (spawn as Node3D).global_position + Vector3.UP * 1.2
		for i in 8:
			var forward := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
			var side := forward.cross(Vector3.UP)
			var clear := true
			for lateral in [-AMPLITUDE - 0.5, 0.0, AMPLITUDE + 0.5]:
				var target: Vector3 = origin + forward * DISTANCE + side * lateral
				var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
				clear = clear and space.intersect_ray(query).is_empty()
			if clear:
				shooter.global_position = (spawn as Node3D).global_position
				shooter.velocity = Vector3.ZERO
				return forward
	return Vector3.ZERO
