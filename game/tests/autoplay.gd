extends SceneTree
## Whole matches through the real screen: my moves go through the same function as a tap. Fast animations.
var main
func _init():
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	for i in 5: await process_frame
	main.fast = true; main.pref.sound = false; main.pref.shape = OS.get_environment("SHAPE") if OS.get_environment("SHAPE") != "" else main.pref.shape; main._apply_look()
	var cfgs := [{"players": 2}, {"players": 3, "transfer": {"enabled": true}}, {"players": 4, "deckSize": 52}, {"players": 6, "deckSize": 52},
		{"players": 2, "deckSize": 24, "hiddenTrump": {"enabled": true}}, {"players": 3, "trumpSwap": {"enabled": true}, "firstTrickLimit": 5}]
	if OS.get_environment("ONLY") != "": cfgs = [cfgs[int(OS.get_environment("ONLY"))]]
	var ok := 0; var fails := 0
	for cfg in cfgs:
		main._start_match(cfg, "normal")
		var t0 := Time.get_ticks_msec(); var last := ""; var last_t := t0
		while true:
			await create_timer(0.02).timeout
			var m = main.match_d
			if m == null: print("FAIL no match"); fails += 1; break
			if m.s.over: ok += 1; break
			var key := str(m.s.table) + str(m.s.phase) + str(m.s.done) + str(m.s.hands.map(func(h): return h.size()))
			if key != last: last = key; last_t = Time.get_ticks_msec()
			if Time.get_ticks_msec() - last_t > int(OS.get_environment("STUCK_MS") if OS.get_environment("STUCK_MS") != "" else "90000"): print("FAIL stuck ", cfg, " ", m.s.phase, " pend ", Core.pending(m.s), " busy ", main.busy, " dealing ", main.dealing, " choose ", Core.choose(m.s, 0, "normal", main.rng), " acts ", Core.actions(m.s, 0), " table ", m.s.table); fails += 1; break
			if main.busy or main.dealing: continue
			if not Core.pending(m.s).has(0): continue
			var a = Core.choose(m.s, 0, "normal", main.rng)
			if a != null: main._do_mine(a)
		main._close_overlay()
	print("matches finished: ", ok, " failed: ", fails)
	print("RESULT ", "OK" if fails == 0 else "FAIL")
	quit()
