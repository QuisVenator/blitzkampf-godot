class_name WeaponSpawner
extends Node3D
## A map-placed pad offering one random weapon from `offers`. Re-rolls a new
## offer each time it becomes available again. The server decides the offer and
## whether it is stocked; `offer_index` and `stocked` are replicated (see the
## Sync node) and the setters redraw the pad on every peer.

const MARKER_BASE_HEIGHT := 0.45
const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.08
const BOB_HALF_PERIOD := 1.25

@export var offers: Array[WeaponDefinition] = []
@export var respawn_delay := 8.0

## Index into `offers` of the weapon on the pad, -1 before the first roll.
var offer_index := -1:
	set(value):
		offer_index = value
		_refresh()
var stocked := false:
	set(value):
		stocked = value
		_refresh()

var _shown_index := -1

@onready var _marker: Node3D = $Marker
@onready var _spinner: Node3D = $Marker/Spinner
@onready var _pickup: PickupArea = $PickupArea
@onready var _respawn_timer: Timer = $RespawnTimer
@onready var _sync: MultiplayerSynchronizer = $Sync


func _ready() -> void:
	_pickup.pickup_priority = 1
	_pickup.collected.connect(_on_collected)
	_respawn_timer.wait_time = respawn_delay
	_respawn_timer.timeout.connect(_roll_offer)
	_start_animation()
	if is_multiplayer_authority():
		# Nobody sees the replicated state until their client has built the map (`show_to`).
		_sync.public_visibility = false
		_roll_offer()
	_refresh()


## Server: starts replicating this spawner to `peer` (its client has the map now).
func show_to(peer: int) -> void:
	_sync.set_visibility_for(peer, true)


## Called by FuncGodot right after a TrenchBroom `weapon_spawner` entity became this node
## (after `_ready`). `weapons` is a bit mask over `WeaponDefinition.map_bit`; no bit set = every weapon.
func _func_godot_apply_properties(properties: Dictionary) -> void:
	respawn_delay = properties.get("respawn_delay", respawn_delay)
	_respawn_timer.wait_time = respawn_delay
	var mask: int = properties.get("weapons", 0)
	offers = []
	for definition in WeaponCatalog.get_default().weapons:
		if mask == 0 or mask & (1 << definition.map_bit):
			offers.append(definition)
	if is_multiplayer_authority():
		_roll_offer()
	_refresh()


func _start_animation() -> void:
	var spin := create_tween().set_loops()
	spin.tween_property(_spinner, "rotation:y", TAU, TAU / SPIN_SPEED).from(0.0)

	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_marker, "position:y", MARKER_BASE_HEIGHT + BOB_HEIGHT, BOB_HALF_PERIOD).from(MARKER_BASE_HEIGHT - BOB_HEIGHT)
	bob.tween_property(_marker, "position:y", MARKER_BASE_HEIGHT - BOB_HEIGHT, BOB_HALF_PERIOD)


func _roll_offer() -> void:
	if offers.is_empty():
		return
	offer_index = randi() % offers.size()
	stocked = true


## Redraws the pad for the current `offer_index` / `stocked`.
func _refresh() -> void:
	if not is_node_ready() or offer_index < 0 or offer_index >= offers.size():
		return
	var offer := offers[offer_index]
	if _shown_index != offer_index:
		_shown_index = offer_index
		for child in _spinner.get_children():
			child.queue_free()
		var model := offer.model.instantiate() as Node3D
		_spinner.add_child(model)
		ModelBounds.center_in_parent(model)

	_pickup.definition = offer
	_pickup.ammo_in_mag = -1
	_pickup.ammo_reserve = -1
	_pickup.available = stocked
	_marker.visible = stocked


func _on_collected() -> void:
	stocked = false
	_respawn_timer.start()
