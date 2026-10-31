extends SceneTree
## Multi-process network tests. For each scenario this starts a headless dedicated
## server and N headless clients as separate processes of this same project, waits
## for them to finish, and reports their checks (see tools/net_scenarios/).
## Run: godot --headless --path . -s res://tools/net_test.gd [scenario ...]
## Exits non-zero if any process fails. Each run uses a random port, so it can run
## beside a manual session.

## [scenario name, client count, extra client args, server args]
const SCENARIOS := [
	["connect", 1, [], ["--server"]],
	["two_clients", 2, [], ["--server"]],
	["shoot", 2, [], ["--server"]],
	["weapons", 1, [], ["--server"]],
	["prediction", 1, ["--net-lag=80", "--net-loss=3"], ["--server"]],
	["console", 1, [], ["--server", "--cheats"]],
	["version_mismatch", 1, ["--protocol=999"], ["--server"]],
	["host", 1, [], ["--host"]],
	["realinput", 1, [], ["--host"]],
]
const CLIENT_START_DELAY := 1.5
const PROCESS_TIMEOUT := 60.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	var dir := ProjectSettings.globalize_path("user://nettest")
	DirAccess.make_dir_recursive_absolute(dir)
	for entry in SCENARIOS:
		if not wanted.is_empty() and not (entry[0] in wanted):
			continue
		await _run_scenario(entry[0], entry[1], entry[2], entry[3], dir)
	print("net test: %s" % ("FAILED" if _failed else "OK"))
	quit(1 if _failed else 0)


func _run_scenario(scenario: String, clients: int, client_args: Array, server_args: Array, dir: String) -> void:
	print("== %s (%d client%s)" % [scenario, clients, "" if clients == 1 else "s"])
	var port := 20000 + randi() % 30000
	var pids: Array[int] = []
	var names: Array[String] = []
	var server_arguments: Array = server_args.duplicate()
	server_arguments.append("--port=%d" % port)
	pids.append(_spawn("server", scenario, server_arguments, dir))
	names.append("server")
	await create_timer(CLIENT_START_DELAY).timeout
	for i in clients:
		var args: Array = ["--join=127.0.0.1", "--port=%d" % port, "--client-index=%d" % i]
		args.append_array(client_args)
		pids.append(_spawn("client%d" % i, scenario, args, dir))
		names.append("client%d" % i)
		await create_timer(0.5).timeout

	var deadline := Time.get_ticks_msec() + int(PROCESS_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline and pids.any(func(pid: int) -> bool: return OS.is_process_running(pid)):
		await create_timer(0.25).timeout
	for i in pids.size():
		var name := names[i]
		if OS.is_process_running(pids[i]):
			print("  %s: TIMEOUT (killed)" % name)
			OS.kill(pids[i])
			_failed = true
			continue
		var code := OS.get_process_exit_code(pids[i])
		var result := _read("%s/%s_%s.txt" % [dir, scenario, name])
		for line in result.split("\n", false):
			print("  [%s] %s" % [name, line])
		if code != 0 or result.contains("FAIL ") or result.is_empty():
			print("  %s: FAILED (exit code %d); log: %s/%s_%s.log" % [name, code, dir, scenario, name])
			_failed = true


func _spawn(name: String, scenario: String, args: Array, dir: String) -> int:
	var base := "%s/%s_%s" % [dir, scenario, name]
	DirAccess.remove_absolute(base + ".txt")
	var arguments: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", base + ".log", "--", "--scenario=" + scenario, "--result=" + base + ".txt"]
	arguments.append_array(args)
	return OS.create_process(OS.get_executable_path(), PackedStringArray(arguments))


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
