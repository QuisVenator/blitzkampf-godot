extends NetScenario
## Listen server: the host plays too, and a client joins it.


func run_server() -> void:
	check("host has its own local player", main.local_player != null and main.local_player.peer_id == 1)
	var joined := await wait_until(func() -> bool: return players().size() == 2)
	check("client joined next to the host", joined)
	var host_player := main.local_player
	var client_player: Player
	for player in players():
		if player != host_player:
			client_player = player
	check("host's own body is simulated and local", host_player.is_multiplayer_authority() and host_player.is_local)
	# The host walks too; the client must see it.
	script_local_player().frame.move = Vector2(0, -1)
	var start := host_player.global_position
	var moved := await wait_until(func() -> bool: return host_player.global_position.distance_to(start) > 4.0)
	check("host can move", moved)
	await wait_until(func() -> bool: return players().size() == 1, 25.0)
	check("client's player removed after it left", players().size() == 1)


func run_client() -> void:
	var both := await wait_until(func() -> bool: return players().size() == 2)
	check("client sees the host's player and its own", both)
	var host_player := player_of(1)
	check("host's player is shown as a character here", host_player != null and not host_player.is_local and host_player.get_node("Visual").visible)
	check("client sees the weapon in the host's hands", await wait_until(func() -> bool: return host_player.held_primary == &"pistol"))
	var start := host_player.global_position
	var saw := await wait_until(func() -> bool: return host_player.global_position.distance_to(start) > 4.0, 15.0)
	check("client saw the host move", saw)
