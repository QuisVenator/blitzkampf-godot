extends SceneTree
## Builds the first-person weapon scenes (gun + hands + animations) with default poses:
##   godot --headless --path . -s res://tools/make_viewmodels.gd [-- pistol smg shotgun]
## Run it once to get a starting point, then fine-tune the saved scenes in the editor.
## It overwrites scenes/weapons/<id>_viewmodel.tscn, so don't re-run it after tuning
## (or tune a copy).

const HANDS := preload("res://assets/models/viewmodel/hands.glb")
const FINGERS := ["index", "middle", "ring", "pinky"]

## Per weapon: where each hand sits relative to the gun's grip origin (metres, degrees)
## and how far each finger joint is curled towards the palm (degrees).
const POSES := {
	&"smg": {
		"right": {"position": Vector3(0.03, -0.025, 0.07), "rotation": Vector3(0, 0, -90),
			"index": [25, 30, 20], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [10, 20, 10]},
		"left": {"position": Vector3(-0.03, -0.03, 0.07), "rotation": Vector3(0, 0, 90),
			"index": [60, 70, 50], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [0, 10, 10]},
	},
	&"shotgun": {
		"right": {"position": Vector3(0.03, -0.025, 0.07), "rotation": Vector3(0, 0, -90),
			"index": [25, 30, 20], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [10, 20, 10]},
		"left": {"position": Vector3(-0.03, -0.03, -0.25), "rotation": Vector3(0, 0, 90),
			"index": [60, 70, 50], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [0, 10, 10]},
	},
	&"pistol": {
		"right": {"position": Vector3(0.03, -0.025, 0.07), "rotation": Vector3(0, 0, -90),
			"index": [25, 30, 20], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [10, 20, 10]},
		"left": {"position": Vector3(-0.03, -0.03, 0.07), "rotation": Vector3(0, 0, 90),
			"index": [60, 70, 50], "middle": [70, 80, 60], "ring": [70, 80, 60], "pinky": [70, 80, 60], "thumb": [0, 10, 10]},
	},
}


func _initialize() -> void:
	var wanted: Array = OS.get_cmdline_user_args()
	for id: StringName in POSES:
		if wanted.is_empty() or String(id) in wanted:
			_save(id)
	quit()


func _save(id: StringName) -> void:
	# Build the hands in memory to get the posed transforms, then write the scene as
	# text: packing the instance would embed the imported meshes in every scene.
	var hands := HANDS.instantiate()
	var overrides: Array[Node3D] = []
	_pose_hand(hands, "R", POSES[id]["right"], overrides)
	_pose_hand(hands, "L", POSES[id]["left"], overrides)

	var animations_path := "res://scenes/weapons/%s_viewmodel_animations.tres" % id
	var library := _make_animations()
	print("saved ", animations_path, " ", ResourceSaver.save(library, animations_path))

	var camera_transform := Transform3D(Basis(Vector3.UP, 0.0628319), Vector3(0.22, -0.26, -0.42)).affine_inverse()
	var text := PackedStringArray()
	text.append("[gd_scene format=3]\n")
	text.append('[ext_resource type="Script" path="res://scripts/weapons/weapon_viewmodel.gd" id="1_script"]')
	text.append('[ext_resource type="PackedScene" path="res://scenes/weapons/%s_model.tscn" id="2_gun"]' % id)
	text.append('[ext_resource type="PackedScene" path="res://assets/models/viewmodel/hands.glb" id="3_hands"]')
	text.append('[ext_resource type="AnimationLibrary" path="%s" id="4_animations"]' % animations_path)
	text.append('[ext_resource type="Script" path="res://scripts/weapons/editor_only.gd" id="5_editor_only"]\n')
	text.append('[node name="%sViewmodel" type="Node3D" node_paths=PackedStringArray("support_hand")]' % String(id).capitalize())
	text.append('script = ExtResource("1_script")')
	text.append('support_hand = NodePath("Rig/Hands/hand_L")\n')
	text.append('[node name="Rig" type="Node3D" parent="."]\n')
	text.append('[node name="Gun" parent="Rig" instance=ExtResource("2_gun")]\n')
	text.append('[node name="Hands" parent="Rig" instance=ExtResource("3_hands")]\n')
	for node in overrides:
		var path := hands.get_path_to(node)
		var parent := hands.get_path_to(node.get_parent())
		var parent_path := "Rig/Hands" if parent == NodePath(".") else "Rig/Hands/%s" % parent
		text.append('[node name="%s" parent="%s" index="%d"]' % [node.name, parent_path, node.get_index()])
		text.append("transform = %s\n" % var_to_str(node.transform))
	text.append('[node name="AnimationPlayer" type="AnimationPlayer" parent="."]')
	text.append('libraries = {&"": ExtResource("4_animations")}\n')
	text.append('[node name="PreviewCamera" type="Camera3D" parent="."]')
	text.append("transform = %s" % var_to_str(camera_transform))
	text.append('script = ExtResource("5_editor_only")')
	text.append("near = 0.05\n")
	text.append('[editable path="Rig/Hands"]')

	var path := "res://scenes/weapons/%s_viewmodel.tscn" % id
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(text) + "\n")
	file.close()
	print("saved ", path)


## Poses a hand and collects every node it changed.
func _pose_hand(hands: Node3D, side: String, pose: Dictionary, changed: Array[Node3D]) -> void:
	var hand := hands.get_node("hand_" + side) as Node3D
	hand.position = pose["position"]
	hand.rotation_degrees = pose["rotation"]
	changed.append(hand)
	for finger in FINGERS + ["thumb"]:
		var joint := hand.get_node("%s_01_%s" % [finger, side]) as Node3D
		for degrees: float in pose[finger]:
			joint.rotation_degrees.x = -degrees
			changed.append(joint)
			joint = joint.get_child(2) as Node3D if joint.get_child_count() > 2 else null
			if joint == null:
				break


## "draw", "fire", "fire_ads" and "reload", each starting and ending at the default pose.
func _make_animations() -> AnimationLibrary:
	var library := AnimationLibrary.new()

	var draw := Animation.new()
	draw.length = 0.3
	_key(draw, "Rig:position", [[0.0, Vector3(0.02, -0.25, 0.1)], [0.3, Vector3.ZERO]])
	_key(draw, "Rig:rotation", [[0.0, Vector3(deg_to_rad(-45), 0, deg_to_rad(10))], [0.3, Vector3.ZERO]])
	library.add_animation("draw", draw)

	for entry in [["fire", 0.07, 4.0], ["fire_ads", 0.025, 1.5]]:
		var fire := Animation.new()
		fire.length = 0.2
		_key(fire, "Rig:position", [[0.0, Vector3.ZERO], [0.04, Vector3(0, 0.005, entry[1])], [0.2, Vector3.ZERO]])
		_key(fire, "Rig:rotation", [[0.0, Vector3.ZERO], [0.04, Vector3(deg_to_rad(entry[2]), 0, 0)], [0.2, Vector3.ZERO]])
		library.add_animation(entry[0], fire)

	var reload := Animation.new()
	reload.length = 1.2
	var dipped := Vector3(0, -0.06, 0.03)
	var tilted := Vector3(deg_to_rad(-20), 0, deg_to_rad(15))
	_key(reload, "Rig:position", [[0.0, Vector3.ZERO], [0.25, dipped], [0.9, dipped], [1.2, Vector3.ZERO]])
	_key(reload, "Rig:rotation", [[0.0, Vector3.ZERO], [0.25, tilted], [0.9, tilted], [1.2, Vector3.ZERO]])
	library.add_animation("reload", reload)
	return library


## `keys` = [[time, value], ...], eased out.
func _key(animation: Animation, path: String, keys: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	for key in keys:
		animation.track_insert_key(track, key[0], key[1], 0.4)
