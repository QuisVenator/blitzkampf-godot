extends NetScenario
## One client joins a dedicated server, walks, and leaves.


func run_server() -> void:
	var joined := await wait_until(func() -> bool: return players().size() == 1)
	check("client joined and got a player", joined)
	if not joined:
		return
	var player := players()[0]
	check("player owned by the client's peer", player.peer_id == int(str(player.name)) and player.peer_id != 1)
	var start := player.global_position
	var moved := await wait_until(func() -> bool: return player.global_position.distance_to(start) > 4.0)
	check("server simulated the client's input", moved)
	check("server player is the simulating side", player.is_multiplayer_authority() and not player.is_local)
	var left := await wait_until(func() -> bool: return players().is_empty(), 15.0)
	check("player removed after the client left", left)


func run_client() -> void:
	var has_player := await wait_until(func() -> bool: return main.local_player != null)
	check("client has a local player", has_player)
	await wait_seconds(0.5)
	check("exactly one player visible", players().size() == 1)
	var player := main.local_player
	check("local player knows its peer id", player.peer_id == multiplayer.get_unique_id())
	check("local player is not simulated here", not player.is_multiplayer_authority())
	var scripted := script_local_player()
	var start := player.global_position
	scripted.frame.move = Vector2(0, -1)
	var moved := await wait_until(func() -> bool: return player.global_position.distance_to(start) > 4.0)
	check("replicated position follows the walk", moved)
	scripted.frame.move = Vector2.ZERO
	await wait_seconds(0.3)
