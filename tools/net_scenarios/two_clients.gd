extends NetScenario
## Two clients see each other; one walks and the other sees it move; both leave.
## Client 0 walks, client 1 watches.


func run_server() -> void:
	var joined := await wait_until(func() -> bool: return players().size() == 2)
	check("both clients joined", joined)
	var gone := await wait_until(func() -> bool: return players().is_empty(), 25.0)
	check("both players removed after leaving", gone)


func run_client() -> void:
	var both := await wait_until(func() -> bool: return players().size() == 2)
	check("client %d sees both players" % client_index(), both)
	var me := main.local_player
	var other: Player
	for player in players():
		if player != me:
			other = player
	check("one player is local, the other is not", me != null and other != null and not other.is_local)
	check("the other player shows a stand-in body", other != null and other.get_node("Visual").visible)
	check("own stand-in body is hidden", not me.get_node("Visual").visible)

	if client_index() == 0:
		var scripted := script_local_player()
		await wait_seconds(1.0)
		scripted.frame.move = Vector2(0, -1)
		await wait_seconds(1.5)
		scripted.frame.move = Vector2.ZERO
		await wait_seconds(1.0)
	else:
		var start := other.global_position
		var saw_it := await wait_until(func() -> bool: return other.global_position.distance_to(start) > 4.0, 15.0)
		check("client 1 saw client 0 move", saw_it)
