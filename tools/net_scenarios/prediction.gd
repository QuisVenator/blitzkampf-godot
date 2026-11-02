extends NetScenario
## A client with 80 ms of lag each way and 3% packet loss walks, sprints, jumps and
## crouches. Its own body must answer at once (prediction), the corrections must
## stay small, and after stopping it must agree with the server's position.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	await wait_until(func() -> bool: return players().is_empty(), 30.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var me := main.local_player
	await wait_until(func() -> bool: return me._synced)
	await wait_seconds(0.5)
	var scripted := script_local_player()

	var start := me.global_position
	scripted.frame.move = Vector2(0, -1)
	await wait_seconds(0.15)
	check("body answers input before the server could (prediction)", me.global_position.distance_to(start) > 0.3)

	var worst := 0.0
	var deadline := Time.get_ticks_msec() + 4000
	var step := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		step += 1
		scripted.frame.yaw = sin(step / 40.0) * 1.5
		scripted.frame.sprint = (step / 60) % 2 == 0
		scripted.frame.jump = step % 90 == 0
		scripted.frame.crouch = (step / 50) % 3 == 2
		worst = maxf(worst, me._error_offset.length())
	check("corrections stay small (worst %.2f m)" % worst, worst < 0.5)

	scripted.frame = InputFrame.new()
	await wait_seconds(1.5)
	var server_pos := Vector3(me.snapshot[Player.Snap.POS_X], me.snapshot[Player.Snap.POS_Y], me.snapshot[Player.Snap.POS_Z])
	var gap := me.global_position.distance_to(server_pos)
	check("client agrees with the server once idle (gap %.3f m)" % gap, gap < 0.1)
