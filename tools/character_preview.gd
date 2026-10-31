extends SceneTree
## Renders the character in a few poses to PNGs for visual checks:
## godot --path . -s res://tools/character_preview.gd -- <output dir>
## (needs a display; not for headless runs)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/"
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 800)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.38, 0.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = Vector3(20, 0.1, 20)
	floor_mesh.position.y = -0.05
	world.add_child(floor_mesh)

	var poses := [
		["stand", 0.0, false, true, true, 0.0],
		["run", 7.0, false, true, true, 0.0],
		["crouch", 0.0, true, true, true, 0.0],
		["air", 0.0, false, false, true, 0.0],
		["dead", 0.0, false, true, false, 0.0],
		["up", 0.0, false, true, true, 0.8],
	]
	var pistol: WeaponDefinition = load("res://resources/weapons/pistol.tres")
	var smg: WeaponDefinition = load("res://resources/weapons/smg.tres")
	var wanted := OS.get_cmdline_user_args().slice(1)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	for p: Array in poses:
		if not wanted.is_empty() and not (p[0] in wanted):
			continue
		var m := CharacterModel.new()
		world.add_child(m)
		m.set_weapons(pistol, smg)
		for view in ["front", "side"]:
			cam.position = Vector3(0, 1.1, -4.0) if view == "front" else Vector3(4.0, 1.1, 0.0)
			cam.look_at(Vector3(0, 0.9, 0))
			for step in 30:
				m.update(p[1], p[2], p[3], p[4], p[5])
				await process_frame
			vp.get_texture().get_image().save_png("%s/char_%s_%s.png" % [out, p[0], view])
		m.queue_free()
	quit()
