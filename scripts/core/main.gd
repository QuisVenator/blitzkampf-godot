extends Node3D
## Wires the pieces together: places the player, captures the mouse (the pause menu releases it), and
## connects gameplay signals to the HUD and sound effects.

@onready var _player: Player = $Player
@onready var _weapons: WeaponManager = $Player/WeaponManager
@onready var _hud: Hud = $Hud
@onready var _sfx: Sfx = $Sfx


func _ready() -> void:
	_player.spawn()
	_hud.bind(_player, _weapons)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_player.jumped.connect(_sfx.play.bind(&"jump"))
	_player.stepped.connect(_sfx.play.bind(&"footstep"))
	_weapons.fired.connect(func(definition: WeaponDefinition) -> void: _sfx.play(&"fire", definition.fire_pitch_scale))
	_weapons.hit_confirmed.connect(_sfx.play.bind(&"hit"))
	_weapons.reload_started.connect(func(_definition: WeaponDefinition) -> void: _sfx.play(&"reload"))
	_weapons.picked_up.connect(_sfx.play.bind(&"pickup"))

