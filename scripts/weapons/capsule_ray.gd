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
	var quad_a := baba - bard * bard
	if quad_a > 0.000001:
		var quad_b := baba * direction.dot(oa) - baoa * bard
		var quad_c := baba * oa.dot(oa) - baoa * baoa - radius * radius * baba
		var disc := quad_b * quad_b - quad_a * quad_c
		if disc < 0.0:
			return {}
		t = (-quad_b - sqrt(disc)) / quad_a
		var along := baoa + t * bard
		if along <= 0.0 or along >= baba:
			t = -1.0
	if t < 0.0:
		# The caps: the sphere at whichever end the ray is nearer to.
		var centre := a if direction.dot(ba) >= 0.0 else b
		var oc := origin - centre
		var half := direction.dot(oc)
		var disc := half * half - (oc.dot(oc) - radius * radius)
		if disc < 0.0:
			return {}
		t = -half - sqrt(disc)
		var point := origin + direction * t
		if (point - a).dot(ba) > 0.0 and (point - b).dot(ba) < 0.0:
			return {}  # that is the cylinder part, already ruled out
	if t < 0.0:
		return {}
	var hit := origin + direction * t
	var axis_point := a + ba * clampf((hit - a).dot(ba) / baba, 0.0, 1.0)
	return {"distance": t, "normal": (hit - axis_point).normalized()}
