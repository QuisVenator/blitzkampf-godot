extends NetScenario
## A client driven through the real keyboard/mouse source (LocalInput, fed by synthetic
## Input events) sprints, jumps, looks around and aims against a listen server.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 2)
	await wait_seconds(2.0)
	var p := player_of(players()[0].peer_id if players()[0].peer_id != 1 else players()[1].peer_id)
	check("server sees the client aiming", p.get_node("WeaponManager").is_aiming())
	await wait_until(func() -> bool: return players().size() == 1, 30.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var me := main.local_player
	await wait_until(func() -> bool: return me._synced)
	GameInput.force_active = true
	await wait_seconds(0.5)
	var start := me.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"aim")
	Input.action_press(&"sprint")
	var last := me.global_position
	var jumps := 0
	var deadline := Time.get_ticks_msec() + 5000
	var step := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		step += 1
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(sin(step / 30.0) * 6.0, 0)
		Input.parse_input_event(motion)
		if step % 70 == 0:
			Input.action_press(&"jump")
		elif step % 70 == 5:
			Input.action_release(&"jump")
		if me.global_position.distance_to(last) > 1.5:
			jumps += 1
			print("TELEPORT ", last, " -> ", me.global_position)
		last = me.global_position
	print("teleports ", jumps)
	print("CLIENT pos ", me.global_position, " start ", start, " err ", me._error_offset)
	var server_pos := Vector3(me.snapshot[Player.Snap.POS_X], me.snapshot[Player.Snap.POS_Y], me.snapshot[Player.Snap.POS_Z])
	print("CLIENT snapshot ", server_pos)
	check("moved without being snapped back", jumps == 0)
	check("own weapon mirror is aiming", me.get_node("WeaponManager").is_aiming())
