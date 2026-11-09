extends SceneTree
## Renders the table to a PNG.  -- out.png players theme shape
func _init():
	var a := OS.get_cmdline_user_args()
	var t = load("res://scripts/table3d.gd").new()
	get_root().add_child(t)
	await process_frame
	t.set_look({"theme": a[2] if a.size() > 2 else "cabinet", "shape": a[3] if a.size() > 3 else "round"})
	var n := int(a[1]) if a.size() > 1 else 3
	t.view_bottom = 300
	t.new_match(n, 0, 20, 13 + 6)
	var c := []
	for k in n: c.append(6)
	t.set_counts(c)
	t.set_table([{"a": 12, "d": 10}, {"a": 21, "d": -1}])
	for i in 20: await process_frame
	t.frame_camera()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[0])
	quit()
