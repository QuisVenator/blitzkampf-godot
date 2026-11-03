class_name CapsuleRay
extends RefCounted
## Ray against a vertical capsule, by maths instead of a physics query. Lag
## compensation tests shots against where a body *was*, and moving the real
## physics body there for the query isn't reliable (the physics space only sees
## body moves at its next step).


## Returns {"distance", "normal"} for the first hit of the ray (unit `direction`)
## on the capsule standing at `foot` (bottom of the shape) with the given total
## `height` (caps included) and `radius`, or an empty Dictionary for a miss.
static func intersect(origin: Vector3, direction: Vector3, foot: Vector3, height: float, radius: float) -> Dictionary:
	var a := foot + Vector3.UP * radius
	var b := foot + Vector3.UP * (height - radius)
	var ba := b - a
	var oa := origin - a
	var baba := ba.dot(ba)
	var bard := ba.dot(direction)
	var baoa := ba.dot(oa)
	var t := -1.0
	# Which end cap to test: the one the ray crosses the capsule's axis range at (below the
	# cylinder part: the bottom cap; above it: the top cap). A ray parallel to the axis
	# (vertical) meets whichever cap it comes at first.
	var cap_is_bottom := direction.dot(ba) >= 0.0
	var quad_a := baba - bard * bard
	if quad_a > 0.000001:
		var quad_b := baba * direction.dot(oa) - baoa * bard
		var quad_c := baba * oa.dot(oa) - baoa * baoa - radius * radius * baba
		var disc := quad_b * quad_b - quad_a * quad_c
		if disc < 0.0:
			return {}
		t = (-quad_b - sqrt(disc)) / quad_a
		var along := baoa + t * bard
		if t >= 0.0 and along > 0.0 and along < baba:
			return {"distance": t, "normal": _normal(origin + direction * t, a, ba, baba)}
		cap_is_bottom = along <= 0.0
		t = -1.0
	var centre := a if cap_is_bottom else b
	var oc := origin - centre
	var half := direction.dot(oc)
	var cap_disc := half * half - (oc.dot(oc) - radius * radius)
	if cap_disc < 0.0:
		return {}
	t = -half - sqrt(cap_disc)
	var point := origin + direction * t
	# The sphere's other half is the cylinder part (already ruled out) or the capsule's inside.
	if (cap_is_bottom and (point - a).dot(ba) > 0.0) or (not cap_is_bottom and (point - b).dot(ba) < 0.0):
		return {}
	if t < 0.0:
		return {}
	return {"distance": t, "normal": _normal(origin + direction * t, a, ba, baba)}


## Surface normal at `hit`: away from the nearest point of the capsule's axis segment.
static func _normal(hit: Vector3, a: Vector3, ba: Vector3, baba: float) -> Vector3:
	var axis_point := a + ba * clampf((hit - a).dot(ba) / baba, 0.0, 1.0)
	return (hit - axis_point).normalized()
