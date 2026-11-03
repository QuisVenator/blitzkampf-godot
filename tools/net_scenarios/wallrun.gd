extends NetScenario
## A client with 80 ms of lag and 3% loss runs along the arena's west wall (the server puts it there,
## airborne and fast). Client and server must both be wall running, the client's prediction must
## agree with the server (small corrections), and the run must end without a lasting disagreement.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	var player := players()[0]
	await wait_seconds(2.0)
	player.teleport(Vector3(-19.6, 2.5, 15.0), 0.0)
	player.velocity = Vector3(0.0, 0.0, -9.0)
	var ran := false
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		ran = ran or player.get("_wall_run")
	check("server runs the player along the wall", ran)
	await wait_seconds(6.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var me := main.local_player
	await wait_until(func() -> bool: return me._synced)
	var scripted := script_local_player()
	scripted.frame.move = Vector2(0, -1)
	# Wait for the server's teleport next to the wall.
	await wait_until(func() -> bool: return me.global_position.x < -15.0, 15.0)
	var ran := false
	var worst := 0.0
	var settled := Time.get_ticks_msec() + 1000  # the teleport itself makes the client snap and re-sync first
	var deadline := settled + 1300
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		ran = ran or me.get("_wall_run")
		if Time.get_ticks_msec() > settled:
			worst = maxf(worst, me._error_offset.length())
	check("client predicts the wall run", ran)
	check("corrections stay small (worst %.2f m)" % worst, worst < 0.5)
	scripted.frame = InputFrame.new()
	await wait_seconds(2.0)
	var server_pos := Vector3(me.snapshot[Player.Snap.POS_X], me.snapshot[Player.Snap.POS_Y], me.snapshot[Player.Snap.POS_Z])
	var gap := me.global_position.distance_to(server_pos)
	check("client agrees with the server afterwards (gap %.3f m)" % gap, gap < 0.1)
