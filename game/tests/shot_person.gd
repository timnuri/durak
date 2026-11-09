extends SceneTree
func _init():
	var a := OS.get_cmdline_user_args()
	var t = load("res://scripts/table3d.gd").new()
	get_root().add_child(t)
	await process_frame
	t.set_look({"theme": a[2] if a.size() > 2 else "cabinet"})
	t.new_match(2, 0, 20, 19)
	t.set_counts([0, 6])
	for i in 10: await process_frame
	var p = t.people[1]
	var views := [Vector3(0, 1.3, 0.6), Vector3(1.6, 1.2, -0.9), Vector3(0.3, 1.25, -0.4)]
	var v: Vector3 = views[int(a[1])]
	t.cam.global_transform = Transform3D(Basis.looking_at(p.global_position + Vector3.UP * 0.9 - v), v)
	t.cam.v_offset = 0
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[0])
	quit()
