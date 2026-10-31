class_name CharacterModel
extends Node3D
## The third-person body of a player: the Quaternius mannequin with an
## AnimationTree built here, plus the weapons held in its hands. Everyone else
## sees this; the local player hides it and sees viewmodels instead.
##
## The tree: a state machine for the whole body (standing / crouching / air /
## dead; standing and crouching blend idle and run by speed), overlaid on the
## upper body by an aiming pose that blends up/down with the look pitch. Call
## `update()` each frame with the body's state.

const MODEL := preload("res://assets/models/characters/ual/UAL1_Standard.glb")

## Speeds (m/s) at which each locomotion clip plays at full weight.
const WALK_SPEED := 2.5
const RUN_SPEED := 7.0
const SPRINT_SPEED := 11.0
const CROUCH_RUN_SPEED := 3.5
## Look pitch (radians) at which the up/down aim pose is fully applied.
const FULL_AIM_PITCH := deg_to_rad(60.0)
const BLEND_TIME := 0.15
## Bones driven by the aiming overlay (everything from the waist up).
const UPPER_BODY: Array[String] = [
	"spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]
const SKELETON_PATH := "Armature/Skeleton3D"

## Held weapons are placed relative to the aiming pose: each weapon points along
## the character's forward axis, positioned at the hand plus this offset (in the
## character's space: x right, y up, -z forward). Tune with tools/character_preview.gd.
const REFERENCE_POSE := &"Pistol_Aim_Neutral"
const GRIP_OFFSETS: Array[Vector3] = [Vector3(0.03, -0.03, -0.02), Vector3(-0.1, -0.03, -0.02)]

var _tree: AnimationTree
var _loco: AnimationNodeStateMachinePlayback
var _hands: Array[Node3D] = []
var _held: Array[Node3D] = [null, null]
var _held_ids: Array[StringName] = [&"", &""]
var _state := &""

@onready var _skeleton: Skeleton3D


func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	# glTF characters face +Z; the game's forward is -Z.
	model.rotation.y = PI
	add_child(model)
	_skeleton = model.get_node(SKELETON_PATH) as Skeleton3D
	var grips := _calibrate_grips(model)
	var bones := ["hand_r", "hand_l"]
	for i in bones.size():
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bones[i]
		_skeleton.add_child(attachment)
		var grip := Node3D.new()
		grip.transform = grips[i]
		attachment.add_child(grip)
		_hands.append(grip)
	_build_tree(model)


## Poses the skeleton in the aiming pose once and works out, per hand, the
## transform that makes a weapon child point forward from the hand. Using the
## pose itself (rather than hard-coded bone angles) keeps it right if the model
## or animation is swapped.
func _calibrate_grips(model: Node3D) -> Array[Transform3D]:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.play(REFERENCE_POSE)
	player.seek(player.current_animation_length, true)
	player.pause()
	_skeleton.force_update_all_bone_transforms()
	var to_character := global_transform.affine_inverse() * _skeleton.global_transform
	var grips: Array[Transform3D] = []
	var bones := ["hand_r", "hand_l"]
	for i in bones.size():
		var hand := to_character * _skeleton.get_bone_global_pose(_skeleton.find_bone(bones[i]))
		var wanted := Transform3D(Basis.IDENTITY, hand.origin + GRIP_OFFSETS[i])
		grips.append(hand.affine_inverse() * wanted)
	player.stop()
	return grips


## `speed` horizontal m/s, `pitch` radians (positive looks up).
func update(speed: float, crouched: bool, grounded: bool, alive: bool, pitch: float) -> void:
	var target: StringName = &"dead" if not alive else (&"air" if not grounded else (&"crouch" if crouched else &"stand"))
	if target != _state:
		_state = target
		_loco.travel(target)
	_tree.set("parameters/loco/stand/blend_position", speed)
	_tree.set("parameters/loco/crouch/blend_position", speed)
	_tree.set("parameters/aim/blend_position", clampf(pitch / FULL_AIM_PITCH, -1.0, 1.0))
	_tree.set("parameters/upper/blend_amount", 1.0 if alive and grounded else 0.0)


## Shows the held weapons; pass null for an empty hand. Index 0 = right, 1 = left.
func set_weapons(primary: WeaponDefinition, secondary: WeaponDefinition) -> void:
	_set_held(0, primary)
	_set_held(1, secondary)


func _set_held(hand: int, definition: WeaponDefinition) -> void:
	var id: StringName = definition.id if definition else &""
	if id == _held_ids[hand]:
		return
	_held_ids[hand] = id
	if _held[hand]:
		_held[hand].queue_free()
		_held[hand] = null
	if definition:
		_held[hand] = definition.model.instantiate()
		_hands[hand].add_child(_held[hand])


func _build_tree(model: Node3D) -> void:
	var stand := AnimationNodeBlendSpace1D.new()
	stand.min_space = 0.0
	stand.max_space = SPRINT_SPEED
	_add_point(stand, "Idle", 0.0)
	_add_point(stand, "Walk", WALK_SPEED)
	_add_point(stand, "Jog_Fwd", RUN_SPEED)
	_add_point(stand, "Sprint", SPRINT_SPEED)

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = CROUCH_RUN_SPEED
	_add_point(crouch, "Crouch_Idle", 0.0)
	_add_point(crouch, "Crouch_Fwd", CROUCH_RUN_SPEED)

	var air := AnimationNodeAnimation.new()
	air.animation = &"Jump"
	var dead := AnimationNodeAnimation.new()
	dead.animation = &"Death01"

	var states := AnimationNodeStateMachine.new()
	var names: Array[StringName] = [&"stand", &"crouch", &"air", &"dead"]
	states.add_node(&"stand", stand)
	states.add_node(&"crouch", crouch)
	states.add_node(&"air", air)
	states.add_node(&"dead", dead)
	for from in names:
		for to in names:
			if from != to:
				var transition := AnimationNodeStateMachineTransition.new()
				transition.xfade_time = BLEND_TIME
				states.add_transition(from, to, transition)

	var aim := AnimationNodeBlendSpace1D.new()
	aim.min_space = -1.0
	aim.max_space = 1.0
	_add_point(aim, "Pistol_Aim_Down", -1.0)
	_add_point(aim, "Pistol_Aim_Neutral", 0.0)
	_add_point(aim, "Pistol_Aim_Up", 1.0)

	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for bone in UPPER_BODY:
		upper.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)

	var root := AnimationNodeBlendTree.new()
	root.add_node(&"loco", states)
	root.add_node(&"aim", aim)
	root.add_node(&"upper", upper)
	root.connect_node(&"upper", 0, &"loco")
	root.connect_node(&"upper", 1, &"aim")
	root.connect_node(&"output", 0, &"upper")

	_tree = AnimationTree.new()
	_tree.tree_root = root
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(model.find_child("AnimationPlayer", true, false))
	_tree.active = true
	_loco = _tree.get("parameters/loco/playback")
	_loco.start(&"stand")
	_state = &"stand"


func _add_point(space: AnimationNodeBlendSpace1D, animation: StringName, position: float) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	space.add_blend_point(node, position, -1, StringName("%s" % animation))
