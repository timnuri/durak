extends SceneTree
## Screenshots of the real game.  -- outdir [theme]
var main
func snap(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/" + name + ".png")
func _init():
	var a := OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	for i in 5: await process_frame
	if a.size() > 1: main.pref.theme = a[1]; main._apply_look()
	main.pref.opp = int(a[2]) if a.size() > 2 else 3
	if main.pref.opp >= 5: main.pref.deckSize = 52
	main._show("home", true); main._menu_scene()
	await snap("home")
	main._show("setup"); main._more_open = true; main._rebuild()
	await snap("setup")
	main._start_match(main._cur_input(), "normal")
	await create_timer(6.0).timeout
	await snap("game1")
	await create_timer(4.0).timeout
	await snap("game2")
	quit()
