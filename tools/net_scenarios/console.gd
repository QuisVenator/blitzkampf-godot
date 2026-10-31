extends NetScenario
## A client uses console commands on a server started with --cheats: give a weapon,
## take damage, add a bot. The bot then fights it (bots shoot visible enemies).


func run_server() -> void:
	await wait_until(func() -> bool: return players().size() == 1)
	var bot_seen := await wait_until(func() -> bool: return players().any(func(p: Player) -> bool: return p.is_bot), 20.0)
	check("server: bot was added by the client's command", bot_seen)
	await wait_until(func() -> bool: return players().size() == 1, 30.0)


func run_client() -> void:
	await wait_until(func() -> bool: return main.local_player != null and main.local_player.alive)
	var me := main.local_player
	var weapons := me.get_node("WeaponManager") as WeaponManager
	await wait_until(func() -> bool: return weapons.primary.definition != null)
	main.submit_command("give shotgun")
	var got := await wait_until(func() -> bool: return weapons.primary.definition.id == &"shotgun")
	check("give puts the weapon in the client's hands", got)
	main.submit_command("damage 30")
	var hurt := await wait_until(func() -> bool: return me.health == 70)
	check("damage reaches the client", hurt)
	main.submit_command("heal")
	check("heal restores health", await wait_until(func() -> bool: return me.health == 100))

	main.submit_command("botmode fight")
	main.submit_command("bot")
	var bot_there := await wait_until(func() -> bool: return players().size() == 2)
	check("client sees the bot", bot_there)
	# The bot sees us across the arena or wanders to us and shoots.
	var bot: Player = players().filter(func(p: Player) -> bool: return p.is_bot)[0]
	var attacked := await wait_until(func() -> bool: return me.health < 100 or not me.alive, 25.0)
	check("the bot attacks the client", attacked)
	main.submit_command("botclear")
	var gone := await wait_until(func() -> bool: return players().size() == 1)
	check("botclear removes the bot", gone)
	check("bot node is freed", not is_instance_valid(bot) or bot.is_queued_for_deletion() or gone)
