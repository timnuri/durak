extends SceneTree
## Checks the GDScript rules against games recorded from the JavaScript reference (tools/make_traces.js),
## then plays bot games for crashes.  godot --headless --path game -s res://tests/test_core.gd -- traces.json
func _key(acts: Array) -> String:
	var a := []
	for x in acts:
		a.append(str(x.k) + (":" + str(int(x.c)) if x.has("c") else "") + ("@" + str(int(x.i)) if x.has("i") else ""))
	a.sort()
	return " ".join(a)
func _init():
	var args := OS.get_cmdline_user_args()
	var fails := 0
	if args.size() > 0:
		var traces = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
		for g in traces.size():
			var t = traces[g]
			var deck := []
			for c in t.deck: deck.append(int(c))
			var m := Core.new_game(t.cfg, {"deck": deck, "first": int(t.first)})
			var s: Dictionary = m.s
			var bad := ""
			for k in t.steps.size():
				var st = t.steps[k]
				for p in s.n:
					if _key(Core.actions(s, p)) != st.keys[p]:
						bad = "game %d step %d seat %d actions:\n gd %s\n js %s" % [g, k, p, _key(Core.actions(s, p)), st.keys[p]]; break
				if bad != "": break
				var act := {"k": st.act.k}
				if st.act.has("c"): act.c = int(st.act.c)
				if st.act.has("i"): act.i = int(st.act.i)
				var r := Core.apply(s, int(st.seat), act)
				if not r.ok: bad = "game %d step %d: %s" % [g, k, r.error]; break
				var evs := []
				for e in r.ev: evs.append(e.t)
				if ",".join(evs) != st.ev: bad = "game %d step %d events gd %s js %s" % [g, k, ",".join(evs), st.ev]; break
			if bad == "" and s.over:
				if int(t.final.result.fool) != s.result.fool: bad = "game %d fool %d vs %d" % [g, s.result.fool, int(t.final.result.fool)]
			if bad == "" and not s.over: bad = "game %d did not end" % g
			if bad != "":
				fails += 1
				if fails < 5: print("FAIL ", bad)
		print("traces checked: ", traces.size(), " failed: ", fails)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var games := 0
	for cfg in [{"players": 2}, {"players": 4, "transfer": {"enabled": true}}, {"players": 6, "deckSize": 52}, {"players": 3, "hiddenTrump": {"enabled": true}, "trumpSwap": {"enabled": true}}]:
		for g in 6:
			var m := Core.new_game(cfg, {"rng": rng})
			var s: Dictionary = m.s
			var n := 0
			while not s.over and n < 4000:
				n += 1
				var p: int = Core.pending(s)[0]
				var lvl := "hard" if (g == 0 and p == 0) else ("easy" if p % 2 else "normal")
				var a = Core.choose(s, p, lvl, rng)
				if a == null: print("FAIL bot no move"); fails += 1; break
				var r := Core.apply(s, p, a)
				if not r.ok: print("FAIL bot illegal ", a); fails += 1; break
			if not s.over: print("FAIL bot game did not end"); fails += 1
			games += 1
	print("bot games: ", games)
	print("RESULT ", "OK" if fails == 0 else "FAIL")
	quit(1 if fails else 0)
