class_name DebugCommands
extends RefCounted
## Console commands. They run on the server (or in single player) on behalf of the
## player who typed them; `run()` returns the text to print. Add a command by
## adding an entry to `_commands` and a `_cmd_*` method.
##
## `main` is typed `Node` so tool scripts can use this class without pulling in the
## `Net` autoload through `Main`. It needs `players()`, `spawn_bot()` and `clear_bots()`.

## name -> [usage, one-line help]
const _HELP := {
	"help": ["help", "list commands"],
	"players": ["players", "list players and bots"],
	"weapons": ["weapons", "list weapon ids"],
	"give": ["give <weapon> [primary|secondary] [target]", "put a fresh weapon in a hand"],
	"ammo": ["ammo [target]", "refill all held weapons"],
	"damage": ["damage <amount> [target]", "hurt a player"],
	"heal": ["heal [target]", "restore full health"],
	"kill": ["kill [target]", "kill a player"],
	"respawn": ["respawn [target]", "respawn now at a spawn point"],
	"tp": ["tp <x> <y> <z> [target]", "teleport"],
	"bot": ["bot [count]", "add AI bots"],
	"botclear": ["botclear", "remove all bots"],
	"botmode": ["botmode auto|idle|wander|fight", "how bots behave: auto mixes standing/walking and bursts/pauses; idle stands still, never shoots; wander walks, never shoots; fight always shoots"],
}

var _main: Node
var _caller: Player


## `caller` is the player of whoever typed the command (the default target); may be null.
func run(main: Node, caller: Player, line: String) -> String:
	_main = main
	_caller = caller
	var words := Array(line.strip_edges().split(" ", false))
	if words.is_empty():
		return ""
	var command: String = words.pop_front().to_lower()
	if not _HELP.has(command):
		return "Unknown command '%s'. Try 'help'." % command
	return call("_cmd_" + command, words)


func _cmd_help(_args: Array) -> String:
	var lines: Array[String] = []
	for name: String in _HELP:
		lines.append("%-42s %s" % [_HELP[name][0], _HELP[name][1]])
	lines.append("Targets: me, a player id, botN, or all. Default is you.")
	return "\n".join(lines)


func _cmd_players(_args: Array) -> String:
	var lines: Array[String] = []
	for player: Player in _main.players():
		var tag := " (you)" if player == _caller else ""
		lines.append("%s%s  id %d  health %d  kills %d deaths %d%s" % [player.display_name(), tag, player.peer_id, player.health, player.kills, player.deaths, "" if player.alive else "  dead"])
	return "\n".join(lines)


func _cmd_weapons(_args: Array) -> String:
	var ids: Array[String] = []
	for definition in WeaponCatalog.get_default().weapons:
		ids.append(String(definition.id))
	return ", ".join(ids)


func _cmd_give(args: Array) -> String:
	if args.is_empty():
		return "Usage: " + _HELP["give"][0]
	var definition := WeaponCatalog.get_default().find(StringName(args[0]))
	if definition == null:
		return "No weapon '%s'. See 'weapons'." % args[0]
	var hand := WeaponManager.PRIMARY
	var rest := args.slice(1)
	if not rest.is_empty() and rest[0] in ["primary", "secondary"]:
		hand = WeaponManager.SECONDARY if rest[0] == "secondary" else WeaponManager.PRIMARY
		rest = rest.slice(1)
	return _each_target(rest, func(player: Player) -> String:
		var error := _weapons_of(player).give(hand, definition)
		return error if error != "" else "%s now holds %s" % [player.display_name(), definition.display_name])


func _cmd_ammo(args: Array) -> String:
	return _each_target(args, func(player: Player) -> String:
		_weapons_of(player).refill()
		return "%s: ammo refilled" % player.display_name())


func _cmd_damage(args: Array) -> String:
	if args.is_empty() or not String(args[0]).is_valid_int():
		return "Usage: " + _HELP["damage"][0]
	var amount := int(args[0])
	return _each_target(args.slice(1), func(player: Player) -> String:
		player.take_damage(amount, null)
		return "%s: %d health" % [player.display_name(), player.health])


func _cmd_heal(args: Array) -> String:
	return _each_target(args, func(player: Player) -> String:
		if not player.alive:
			return "%s is dead" % player.display_name()
		player.health = player.max_health
		return "%s: healed" % player.display_name())


func _cmd_kill(args: Array) -> String:
	return _each_target(args, func(player: Player) -> String:
		player.take_damage(player.health, null)
		return "%s: killed" % player.display_name())


func _cmd_respawn(args: Array) -> String:
	return _each_target(args, func(player: Player) -> String:
		player.spawn()
		return "%s: respawned" % player.display_name())


func _cmd_tp(args: Array) -> String:
	if args.size() < 3 or not (String(args[0]).is_valid_float() and String(args[1]).is_valid_float() and String(args[2]).is_valid_float()):
		return "Usage: " + _HELP["tp"][0]
	var destination := Vector3(float(args[0]), float(args[1]), float(args[2]))
	return _each_target(args.slice(3), func(player: Player) -> String:
		player.teleport(destination, player.yaw)
		return "%s teleported" % player.display_name())


func _cmd_bot(args: Array) -> String:
	var count := int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else 1
	count = clampi(count, 1, 16)
	for i in count:
		_main.spawn_bot()
	return "Added %d bot(s)" % count


func _cmd_botmode(args: Array) -> String:
	var modes := {"auto": BotInput.Mode.AUTO, "idle": BotInput.Mode.IDLE, "wander": BotInput.Mode.WANDER, "fight": BotInput.Mode.FIGHT}
	if args.is_empty() or not modes.has(args[0]):
		return "Usage: %s (now: %s)" % [_HELP["botmode"][0], BotInput.Mode.keys()[BotInput.mode].to_lower()]
	BotInput.mode = modes[args[0]]
	return "Bots now: " + args[0]


func _cmd_botclear(_args: Array) -> String:
	return "Removed %d bot(s)" % _main.clear_bots()


func _weapons_of(player: Player) -> WeaponManager:
	return player.get_node("WeaponManager") as WeaponManager


## Runs `action` for the target named by the first of `args` (default: the caller)
## and joins the results.
func _each_target(args: Array, action: Callable) -> String:
	var spec: String = args[0] if not args.is_empty() else "me"
	var targets: Array[Player] = []
	if spec == "all":
		targets.assign(_main.players())
	else:
		var found := _find_player(spec)
		if found == null:
			return "No player '%s'. See 'players'." % spec
		targets.append(found)
	var lines: Array[String] = []
	for player in targets:
		lines.append(action.call(player))
	return "\n".join(lines)


func _find_player(spec: String) -> Player:
	if spec == "me":
		return _caller
	var id := -1
	if spec.begins_with("bot") and spec.substr(3).is_valid_int():
		id = Player.BOT_ID_BASE + int(spec.substr(3))
	elif spec.is_valid_int():
		id = int(spec)
	for player: Player in _main.players():
		if player.peer_id == id:
			return player
	return null
