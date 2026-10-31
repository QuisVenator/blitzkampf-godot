extends NetScenario
## A client built with a different protocol version is turned away.


func run_server() -> void:
	await wait_seconds(5.0)
	check("mismatched client never got a player", players().is_empty())


func run_client() -> void:
	# Main returns to the menu (freeing this scenario) when rejected, so report
	# straight from the signal.
	Net.connection_lost.connect(func(reason: String) -> void:
		check("client was rejected with a version message", reason.begins_with("Version mismatch"))
		finish())
	await wait_seconds(10.0)
