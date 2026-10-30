class_name WeaponSpawner
extends Node3D
## A map-placed pad offering one random weapon from `offers`. Re-rolls a new
## offer each time it becomes available again.

const MARKER_BASE_HEIGHT := 0.45
const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.08
const BOB_HALF_PERIOD := 1.25

@export var offers: Array[WeaponDefinition] = []
@export var respawn_delay := 8.0

@onready var _marker: Node3D = $Marker
@onready var _spinner: Node3D = $Marker/Spinner
@onready var _pickup: PickupArea = $PickupArea
@onready var _respawn_timer: Timer = $RespawnTimer


func _ready() -> void:
	_pickup.pickup_priority = 1
	_pickup.collected.connect(_on_collected)
	_respawn_timer.wait_time = respawn_delay
	_respawn_timer.timeout.connect(_roll_offer)
	_start_animation()
	_roll_offer()


func _start_animation() -> void:
	var spin := create_tween().set_loops()
	spin.tween_property(_spinner, "rotation:y", TAU, TAU / SPIN_SPEED).from(0.0)

	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_marker, "position:y", MARKER_BASE_HEIGHT + BOB_HEIGHT, BOB_HALF_PERIOD).from(MARKER_BASE_HEIGHT - BOB_HEIGHT)
	bob.tween_property(_marker, "position:y", MARKER_BASE_HEIGHT - BOB_HEIGHT, BOB_HALF_PERIOD)


func _roll_offer() -> void:
	if offers.is_empty():
		return
	var offer: WeaponDefinition = offers.pick_random()
	for child in _spinner.get_children():
		child.queue_free()
	_spinner.add_child(offer.model.instantiate())

	_pickup.definition = offer
	_pickup.ammo_in_mag = -1
	_pickup.ammo_reserve = -1
	_pickup.available = true
	_marker.visible = true


func _on_collected() -> void:
	_pickup.available = false
	_marker.visible = false
	_respawn_timer.start()
