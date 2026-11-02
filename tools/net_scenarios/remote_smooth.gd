extends NetScenario
## A remote player must move smoothly on a client even though the dedicated server
## sends several copies of each snapshot per tick (it sends once per rendered frame).
## A wandering bot runs at a steady speed; its drawn speed must not stutter.

const MAX_SPEED_STDDEV := 1.5


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	BotInput.mode = BotInput.Mode.WANDER
	main.spawn_bot()
	await wait_until(func() -> bool: return players().is_empty(), 20.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var found := []
	await wait_until(func() -> bool:
		for player in players():
			if player.is_bot:
				found.append(player)
		return not found.is_empty())
	var bot: Player = found[0]
	await wait_seconds(1.0)
	var speeds: Array[float] = []
	var last := bot.global_position
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		speeds.append(bot.global_position.distance_to(last) / get_process_delta_time())
		last = bot.global_position
	var mean := 0.0
	for speed in speeds:
		mean += speed
	mean /= speeds.size()
	var variance := 0.0
	for speed in speeds:
		variance += (speed - mean) * (speed - mean)
	var deviation := sqrt(variance / speeds.size())
	print("drawn speed %.2f m/s, deviation %.2f" % [mean, deviation])
	check("the bot is moving (%.1f m/s)" % mean, mean > 2.0)
	check("its drawn speed is steady (deviation %.2f)" % deviation, deviation < MAX_SPEED_STDDEV)
