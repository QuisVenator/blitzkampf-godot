extends SceneTree
## Headless gameplay smoke test with scripted input.
## Run: godot --headless --path . -s res://tools/smoke_test.gd
## Exits non-zero if any check fails.

var _failures := 0
var _main: Node
var _player: Player
var _weapons: WeaponManager
var _hits := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_player = _main.get_node("Player")
	_weapons = _player.get_node("WeaponManager")
	_weapons.hit_confirmed.connect(func() -> void: _hits += 1)
	GameInput.force_active = true

	await _frames(30)
	_check("player settles on floor", _player.is_on_floor())
	_check("player stands at ground level", absf(_player.global_position.y) < 0.05)
	_check("spawn z", is_equal_approx(_player.global_position.z, 8.0))

	# Walking, sprinting (start at the south wall so there is room to run).
	_player.teleport(Vector3(0, 0, 19), 0.0)
	await _frames(5)
	Input.action_press(&"move_forward")
	await _frames(40)
	_check_near("walk speed ~7", _player.horizontal_speed(), 7.0, 0.1)
	Input.action_press(&"sprint")
	await _frames(30)
	_check_near("sprint speed ~11", _player.horizontal_speed(), 11.0, 0.1)

	# Slide: fresh crouch press while sprinting.
	Input.action_press(&"crouch")
	await _frames(3)
	_check("slide started", _player.stance == Player.Stance.SLIDING)
	_check("slide speed >= 10.9", _player.horizontal_speed() >= 10.9)
	await _frames(20)
	var mid_slide := _player.horizontal_speed()
	await _frames(20)
	_check("slide decays", _player.horizontal_speed() < mid_slide)
	Input.action_release(&"crouch")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _frames(5)
	_check("stands after releasing crouch", _player.stance == Player.Stance.STANDING)
	await _frames(10)
	_check_near("instant stop on no input", _player.horizontal_speed(), 0.0, 0.01)

	# Jump.
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	_check("jump leaves floor", not _player.is_on_floor() and _player.velocity.y > 0.0)
	await _frames(90)
	_check("lands again", _player.is_on_floor())

	# Shooting a target dead ahead (spawn faces -Z at x=0, target at z=-14).
	_player.teleport(Vector3(0, 0, 8), 0.0)
	await _frames(5)
	Input.action_press(&"aim")
	await _frames(2)
	var mag_before := _weapons.in_mag
	Input.action_press(&"fire")
	await _frames(3)
	Input.action_release(&"fire")
	_check("ammo decremented", _weapons.in_mag == mag_before - 1)
	_check("target hit while aiming", _hits >= 1)
	Input.action_release(&"aim")

	# Reload.
	Input.action_press(&"reload")
	await _frames(2)
	Input.action_release(&"reload")
	_check("reloading", _weapons.is_reloading())
	await _frames(90)
	_check("reload finished", not _weapons.is_reloading() and _weapons.in_mag == _weapons.definition.magazine_size)
	_check("reserve reduced by one round", _weapons.reserve == _weapons.definition.reserve_ammo - 1)

	# Pickup from a spawner that only offers shotguns at (10, 0.04, -12).
	_player.teleport(Vector3(10, 0, -11), 0.0)
	await _frames(10)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("picked up shotgun", _weapons.definition.id == &"shotgun")
	await _frames(5)
	var dropped := _main.get_children().filter(func(n: Node) -> bool: return n is DroppedWeapon)
	_check("old weapon was dropped", dropped.size() == 1)

	# Walk over to the dropped pistol and take it back: it keeps its ammo.
	await _frames(90)
	var landed := dropped[0] as DroppedWeapon
	_player.teleport(Vector3(landed.global_position.x, 0, landed.global_position.z), 0.0)
	await _frames(5)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("picked dropped pistol back up", _weapons.definition.id == &"pistol")
	_check("dropped pistol kept its ammo", _weapons.in_mag == 8 and _weapons.reserve == 23)

	print("smoke test: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	var ok := absf(actual - expected) <= tolerance
	print("%s %s (got %.3f, want %.3f)" % ["PASS" if ok else "FAIL", label, actual, expected])
	if not ok:
		_failures += 1
