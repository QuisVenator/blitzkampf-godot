class_name Hud
extends CanvasLayer
## Heads-up display. Purely reactive: Main hands it the player and weapon
## manager once, and it listens to their signals.

const STATS_INTERVAL := 0.5

var _player: Player
var _weapons: WeaponManager
var _hits := 0
var _in_mag := 0
var _reserve := 0
var _reloading := false
var _stats_time := 0.0
var _tick_count := 0

@onready var _crosshair: Crosshair = $Root/Crosshair
@onready var _hitmarker: Hitmarker = $Root/Hitmarker
@onready var _hits_label: Label = $Root/Info/HitsLabel
@onready var _weapon_label: Label = $Root/Info/WeaponLabel
@onready var _ammo_label: Label = $Root/Info/AmmoLabel
@onready var _stats_label: Label = $Root/StatsLabel
@onready var _debug_label: Label = $Root/DebugLabel
@onready var _prompt: Control = $Root/Prompt


func bind(player: Player, weapons: WeaponManager) -> void:
	_player = player
	_weapons = weapons
	weapons.weapon_changed.connect(_on_weapon_changed)
	weapons.ammo_changed.connect(_on_ammo_changed)
	weapons.reloading_changed.connect(_on_reloading_changed)
	weapons.spread_changed.connect(_crosshair.set_spread)
	weapons.hit_confirmed.connect(_on_hit_confirmed)

	_on_weapon_changed(weapons.definition)
	_on_ammo_changed(weapons.in_mag, weapons.reserve)
	_crosshair.set_spread(weapons.current_spread_deg())
	_update_hits()


func set_prompt_visible(shown: bool) -> void:
	_prompt.visible = shown


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		_debug_label.visible = not _debug_label.visible


func _physics_process(_delta: float) -> void:
	_tick_count += 1


func _process(delta: float) -> void:
	_stats_time += delta
	if _stats_time >= STATS_INTERVAL:
		_stats_label.text = "FPS: %d | Tick: %d" % [Engine.get_frames_per_second(), roundi(_tick_count / _stats_time)]
		_stats_time = 0.0
		_tick_count = 0

	if _debug_label.visible and _player:
		var v := _player.velocity
		_debug_label.text = "Weapon: %s\nSpeed: %.2f (H: %.2f V: %.2f)" % [_weapons.definition.display_name, v.length(), _player.horizontal_speed(), v.y]


func _on_weapon_changed(definition: WeaponDefinition) -> void:
	_weapon_label.text = "Weapon: %s" % definition.display_name


func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	_in_mag = in_mag
	_reserve = reserve
	_update_ammo()


func _on_reloading_changed(reloading: bool) -> void:
	_reloading = reloading
	_update_ammo()


func _on_hit_confirmed() -> void:
	_hits += 1
	_update_hits()
	_hitmarker.flash()


func _update_ammo() -> void:
	_ammo_label.text = "Reloading..." if _reloading else "Ammo: %d / %d" % [_in_mag, _reserve]


func _update_hits() -> void:
	_hits_label.text = "Hits: %d" % _hits
