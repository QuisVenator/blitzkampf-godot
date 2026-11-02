class_name ViewmodelView
extends SubViewportContainer
## Draws the local player's weapons and hands with a camera of their own, on top of
## the world: they never clip into walls and have their own field of view.
## The viewmodel sits in a `SubViewport` (transparent background) that shares the
## world's 3D scene; the world camera doesn't draw `LAYER` and this camera draws
## nothing else. Each frame the viewmodel camera copies the world camera's pose.

## Visual layer (a bit value) of everything that belongs to the viewmodel.
const LAYER := 2

var world_camera: Camera3D

@onready var camera: Camera3D = $SubViewport/Camera
@onready var primary_holder: Node3D = $SubViewport/Camera/WeaponHolder
@onready var secondary_holder: Node3D = $SubViewport/Camera/WeaponHolderLeft


func _ready() -> void:
	# Runs after the player has placed its camera for this frame.
	process_priority = 100


## `world` is the player's normal camera.
func bind(world: Camera3D) -> void:
	world_camera = world
	world.cull_mask &= ~LAYER


func _process(_delta: float) -> void:
	if world_camera:
		camera.global_transform = world_camera.global_transform


## Puts `node` and everything visual below it on the viewmodel layer.
static func assign_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = LAYER
	for child in node.get_children():
		assign_layer(child)
