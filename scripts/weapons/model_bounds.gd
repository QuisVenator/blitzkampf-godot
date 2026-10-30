class_name ModelBounds
extends RefCounted
## Helpers for weapon models of arbitrary size and origin.


## Bounding box of every mesh under `root`, in `root`'s local space.
## `root` must be inside the scene tree.
static func local_aabb(root: Node3D) -> AABB:
	var to_local := root.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var box := to_local * mesh_node.global_transform * mesh_node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Moves `root` so its bounding-box centre sits at its parent's origin (for
## spinning pickups and dropped weapons). Returns the box size.
static func center_in_parent(root: Node3D) -> Vector3:
	var box := local_aabb(root)
	root.position = -box.get_center()
	return box.size
