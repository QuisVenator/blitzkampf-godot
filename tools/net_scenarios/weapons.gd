extends NetScenario
## One client: its weapon mirror matches the server, ammo drops when it shoots,
## picking up from a spawner (G replaces the primary) swaps the weapon, empties the pad on both sides and
## shows the dropped pistol on both.


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	var player := players()[0]
	var spawner := main.find_child("SpawnerA", true, false) as WeaponSpawner
	await wait_seconds(0.5)
	player.teleport(spawner.global_position + Vector3(0, 0.1, 1.0), 0.0)
	var picked := await wait_until(func() -> bool: return not spawner.stocked, 20.0)
	check("server: spawner emptied by the client's pickup", picked)
	await wait_seconds(0.5)
	check("server: a dropped pistol exists", main.get_node("Drops").get_child_count() == 1)
	await wait_until(func() -> bool: return players().is_empty(), 25.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null)
	var weapons := main.local_player.get_node("WeaponManager") as WeaponManager
	var synced := await wait_until(func() -> bool: return weapons.primary.definition != null)
	check("client mirrors the starting weapon", synced and weapons.primary.definition.id == &"pistol")
	check("client has viewmodel", weapons.primary.viewmodel != null)
	var scripted := script_local_player()
	var mag := weapons.primary.in_mag
	var shots: Array[int] = []
	weapons.fired.connect(func(_d: WeaponDefinition) -> void: shots.append(1))
	scripted.frame.fire = true
	await wait_seconds(0.3)
	scripted.frame.fire = false
	await wait_seconds(0.3)
	check("client sees fired events", not shots.is_empty())
	check("client ammo drops with shots", weapons.primary.in_mag < mag)

	var spawner := main.find_child("SpawnerA", true, false) as WeaponSpawner
	var near := await wait_until(func() -> bool: return main.local_player.global_position.distance_to(spawner.global_position) < 2.0)
	check("client is moved next to the spawner", near)
	var offered := spawner.offers[spawner.offer_index]
	check("client sees spawner stocked", spawner.stocked)
	await wait_seconds(0.3)
	scripted.frame.interact_alt_pressed = true
	var swapped := await wait_until(func() -> bool: return weapons.primary.definition != null and weapons.primary.definition.id == offered.id)
	check("client's weapon state follows the pickup", swapped)
	var emptied := await wait_until(func() -> bool: return not spawner.stocked)
	check("client sees spawner emptied", emptied)
	var dropped := await wait_until(func() -> bool: return main.get_node("Drops").get_child_count() >= 1)
	check("client sees the dropped weapon", dropped)
	await wait_seconds(0.5)
