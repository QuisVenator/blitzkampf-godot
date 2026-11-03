extends NetScenario
## The server plays a TrenchBroom map (`--map=test_arena_map`); a client that knows
## nothing about it builds the same map, sees the spawners' replicated state and gets a player.


func run_server() -> void:
	check("server built the requested map", Net.map_id == &"test_arena_map")
	check("server has the map's three spawners", _spawners().size() == 3)
	var joined := await wait_until(func() -> bool: return players().size() == 1)
	check("client joined after building the map", joined)
	await wait_seconds(1.0)


func run_client() -> void:
	var has_player := await wait_until(func() -> bool: return main.local_player != null)
	check("client got a player", has_player)
	check("client learned the server's map", Net.map_id == &"test_arena_map")
	var spawners := _spawners()
	check("client built the same three spawners", spawners.size() == 3)
	var synced := await wait_until(func() -> bool: return _spawners().all(func(s: WeaponSpawner) -> bool: return s.stocked and s.offer_index >= 0))
	check("spawner state reached the client", synced)
	var names: Array = spawners.map(func(s: WeaponSpawner) -> String: return str(s.name))
	names.sort()
	check("spawner nodes are named like the server's", names.all(func(n: String) -> bool: return n.ends_with("_weapon_spawner")))
	check("client's map has the spawn markers", get_tree().get_nodes_in_group(&"player_spawn").size() == 2)


func _spawners() -> Array[WeaponSpawner]:
	var found: Array[WeaponSpawner] = []
	for node in main.get_node("Map").find_children("*", "WeaponSpawner", true, false):
		found.append(node)
	return found
