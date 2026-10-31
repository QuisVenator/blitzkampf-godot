class_name Scoreboard
extends CanvasLayer
## Hold Tab to list every player with kills and deaths, best first. Reads the
## replicated `Player` fields, so it needs no network code of its own.

const REFRESH_INTERVAL := 0.25

@export var players_path: NodePath

var _time := 0.0

@onready var _players: Node = get_node(players_path)
@onready var _table: Label = $Panel/Table


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	visible = Input.is_action_pressed(&"scoreboard")
	_time += delta
	if visible and _time >= REFRESH_INTERVAL:
		_time = 0.0
		_refresh()


func _refresh() -> void:
	var rows: Array[Player] = []
	for child in _players.get_children():
		if child is Player:
			rows.append(child)
	rows.sort_custom(func(a: Player, b: Player) -> bool: return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	var lines := ["%-14s %6s %7s" % ["Player", "Kills", "Deaths"]]
	for player in rows:
		var label := "Player %d" % player.peer_id
		lines.append("%-14s %6d %7d" % [label + (" (you)" if player.is_local else ""), player.kills, player.deaths])
	_table.text = "\n".join(lines)
