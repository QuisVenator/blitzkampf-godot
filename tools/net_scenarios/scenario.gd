class_name NetScenario
extends Node
## Base for network test scenarios. `tools/net_test.gd` starts one server and N
## clients (separate headless processes) that each load the same scenario script;
## `start()` dispatches to `run_server()` (dedicated server or host) or `run_client()`. Each process
## writes its checks to the file given by `--result=` and exits non-zero on failure.

const TIMEOUT := 40.0

var main: Main
var failures := 0
var lines: PackedStringArray = []

# Kept because scenes can change under us (a rejected client returns to the menu).
var _tree: SceneTree


func start(game: Main) -> void:
	main = game
	_tree = get_tree()
	_tree.create_timer(TIMEOUT).timeout.connect(func() -> void:
		check("finished within %d s" % int(TIMEOUT), false)
		finish())
	if Net.role == Net.Role.SERVER or Net.role == Net.Role.HOST:
		await run_server()
	else:
		await run_client()
	finish()


## Override: the server's side of the scenario (return when it has seen enough).
func run_server() -> void:
	pass


## Override: a client's side. `client_index()` tells clients apart.
func run_client() -> void:
	pass


func client_index() -> int:
	return int(Net.arg("client-index", "0"))


func check(label: String, condition: bool) -> void:
	lines.append("%s %s" % ["PASS" if condition else "FAIL", label])
	print(lines[-1])
	if not condition:
		failures += 1


## Polls every physics frame until `condition` is true or `timeout` seconds pass.
func wait_until(condition: Callable, timeout := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func players() -> Array[Player]:
	var result: Array[Player] = []
	for child in main.get_node("Players").get_children():
		if child is Player:
			result.append(child)
	return result


func player_of(peer: int) -> Player:
	return main.get_node("Players").get_node_or_null(str(peer)) as Player


## Sets a client's own player to be driven by a script.
func script_local_player() -> ScriptedInput:
	var scripted := ScriptedInput.new()
	main.local_player.input.source = scripted
	return scripted


func finish() -> void:
	var path := Net.arg("result")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string("\n".join(lines) + "\n")
	_tree.quit(1 if failures > 0 else 0)
