extends SceneTree
## Look at imported models side by side.  -- out.png
func _init():
	var a := OS.get_cmdline_user_args()
	await process_frame
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.2, 0.2, 0.22)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6); env.environment.ambient_light_energy = 0.6
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); sun.light_energy = 1.5; root.add_child(sun)
	var items := ["res://models/Xbot.glb", "res://models/room/ChairDamaskPurplegold.glb", "res://models/room/SheenChair.glb",
		"res://models/room/GlamVelvetSofa.glb", "res://models/room/DiffuseTransmissionPlant.glb", "res://models/room/GlassVaseFlowers.glb"]
	var x := -4.0
	for p in items:
		var m: Node3D = load(p).instantiate(); root.add_child(m)
		for c in m.find_children("*", "Camera3D", true, false): c.free()
		for c in m.find_children("*", "Light3D", true, false): c.free()
		var aabb := _aabb(m, Transform3D())
		var h := aabb.size.y
		var s := 1.0
		if p.contains("Michelle") or p.contains("Xbot"): aabb = AABB(Vector3(-0.4, 0, -0.2), Vector3(0.8, 1.7, 0.4))
		if p.contains("Vase") or p.contains("Candle"): s = 3.0
		m.scale = Vector3.ONE * s
		m.position = Vector3(x, -aabb.position.y * s, 0)
		print(p, " aabb ", aabb)
		x += maxf(aabb.size.x * s, 0.5) + 0.2
	var cam := Camera3D.new(); root.add_child(cam); cam.look_at_from_position(Vector3(1.5, 1.4, 5.0), Vector3(1.5, 0.8, 0)); cam.fov = 70; cam.current = true
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[0])
	quit()
func _aabb(n: Node, _xf: Transform3D) -> AABB:
	var out := AABB(); var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		if first: out = b; first = false
		else: out = out.merge(b)
	return out
