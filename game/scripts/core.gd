class_name Core
## Rules of «Дурак» for 2–6 players, without a screen: settings, the match, the bots.
## A port of the tested JavaScript core (core/ in the old sources). A match is a plain Dictionary `s`;
## apply() changes it and returns the events (what happened) for the screen to animate.
## Cards: id = suit * 13 + (value - 2); suits 0 spades, 1 hearts, 2 diamonds, 3 clubs; value 2..14.
## Seats are numbered clockwise. Phases: "lead" (first card), "defend", "throw" (everybody may add or pass).

const DECK_LOW := {24: 9, 36: 6, 52: 2}
const SUIT_SYMBOL := ["♠", "♥", "♦", "♣"]
const SUIT_NAME := ["пики", "червы", "бубны", "трефы"]

static func suit(c: int) -> int: return c / 13
static func rank(c: int) -> int: return c % 13
static func value(c: int) -> int: return c % 13 + 2
static func make(s: int, v: int) -> int: return s * 13 + (v - 2)
static func build_deck(n: int) -> Array:
	var d := []
	for su in 4:
		for v in range(DECK_LOW[n], 15):
			d.append(make(su, v))
	return d
static func shuffle(a: Array, rng: RandomNumberGenerator) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]; a[i] = a[j]; a[j] = t
	return a

# ------------------------------------------------------------------ settings
static func defaults() -> Dictionary:
	return {
		"players": 2, "deckSize": 36, "handSize": 6,
		"transfer": {"enabled": false, "chain": true},
		"throwIn": "all", "attackLimit": 6, "firstTrickLimit": 6, "noTrumpThrow": false,
		"drawOrder": "standard", "firstAttacker": "lowestTrump", "firstAttackerFallback": "random",
		"endgame": {"simultaneousOut": "draw", "stalemateRounds": 14},
		"hiddenTrump": {"enabled": false, "reveal": "afterTrumpCard", "afterReveal": "draw"},
		"trumpSwap": {"enabled": false},
	}

const TABLE_KEYS := ["players", "deckSize", "handSize"]
const GROUPS := {"main": "Основные правила", "extra": "Дополнительные правила", "special": "Особые режимы"}

static func schema() -> Array:
	return [
		{"path": "transfer.enabled", "group": "main", "type": "bool", "label": "Переводной дурак", "help": "Защищающийся может перевести атаку на следующего игрока картой того же достоинства."},
		{"path": "transfer.chain", "group": "main", "type": "bool", "label": "Переводить несколько раз подряд", "help": "Если выключено, в одном круге переводят только один раз.", "depends": ["transfer.enabled", true]},
		{"path": "throwIn", "group": "main", "type": "enum", "label": "Кто подкидывает", "options": [["attacker", "Только атакующий"], ["neighbors", "Соседи защищающегося"], ["all", "Все, кроме защищающегося"]]},
		{"path": "attackLimit", "group": "main", "type": "int", "min": 1, "max": 8, "label": "Максимум карт в атаке", "help": "Обычно 6. Не больше, чем карт у защищающегося."},
		{"path": "firstTrickLimit", "group": "main", "type": "int", "min": 1, "max": 8, "label": "Максимум карт в первом отбое", "help": "По турнирным правилам в первый отбой больше 5 карт не подкидывают."},
		{"path": "drawOrder", "group": "main", "type": "enum", "label": "Порядок добора", "options": [["standard", "Атакующий, остальные, защищающийся последним"], ["clockwise", "По кругу от атакующего"], ["defenderFirst", "Сначала защищающийся"]]},
		{"path": "firstAttacker", "group": "main", "type": "enum", "label": "Кто ходит первым", "options": [["lowestTrump", "У кого младший козырь"], ["random", "Случайный игрок"], ["seat0", "Вы"]]},
		{"path": "endgame.simultaneousOut", "group": "main", "type": "enum", "label": "Если последние вышли одновременно", "options": [["draw", "Ничья"], ["defenderLoses", "Проигрывает защищавшийся"], ["attackerLoses", "Проигрывает атаковавший"]]},
		{"path": "noTrumpThrow", "group": "extra", "type": "bool", "label": "Козыри подкидывать нельзя", "help": "Подкидывать можно только некозырные карты."},
		{"path": "endgame.stalemateRounds", "group": "extra", "type": "int", "min": 4, "max": 100, "label": "Ничья после стольких взятий подряд", "help": "Защита от бесконечной игры, когда колода кончилась."},
		{"path": "hiddenTrump.enabled", "group": "special", "type": "bool", "label": "Скрытый козырь", "help": "Под козырной картой лежит закрытая. Когда козырную заберут, закрытая откроется и может сменить козырь."},
		{"path": "hiddenTrump.reveal", "group": "special", "type": "enum", "label": "Когда открывается скрытая карта", "options": [["afterTrumpCard", "Как заберут козырную"], ["withLastCard", "Когда её возьмёт игрок"]], "depends": ["hiddenTrump.enabled", true]},
		{"path": "hiddenTrump.afterReveal", "group": "special", "type": "enum", "label": "Что с ней после открытия", "options": [["draw", "Достаётся игроку"], ["marker", "Лежит указателем козыря"]], "depends": ["hiddenTrump.enabled", true]},
		{"path": "trumpSwap.enabled", "group": "special", "type": "bool", "label": "Обмен младшего козыря", "help": "Начинающий атаку может обменять младший козырь на открытую козырную карту."},
	]

const PRESETS := [
	{"id": "classic", "name": "Подкидной", "desc": "Классика: подкидывают все, кроме защищающегося.", "rules": {}},
	{"id": "transfer", "name": "Переводной", "desc": "Атаку можно перевести дальше картой того же достоинства.", "rules": {"transfer": {"enabled": true}}},
	{"id": "extra", "name": "Турнирный", "desc": "В первый отбой не больше 5 карт, можно обменять младший козырь.", "rules": {"firstTrickLimit": 5, "trumpSwap": {"enabled": true}}},
	{"id": "hidden", "name": "Скрытый козырь", "desc": "Под козырем лежит закрытая карта и может сменить козырь.", "rules": {"hiddenTrump": {"enabled": true}}},
	{"id": "custom", "name": "Свои правила", "desc": "Всё настраиваете сами в «Все правила».", "rules": null},
]

static func path_get(o: Dictionary, p: String):
	var cur = o
	for part in p.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part): return null
		cur = cur[part]
	return cur
static func path_set(o: Dictionary, p: String, v) -> void:
	var parts := p.split(".")
	var cur := o
	for i in parts.size() - 1:
		if typeof(cur.get(parts[i])) != TYPE_DICTIONARY: cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = v
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if typeof(over[k]) == TYPE_DICTIONARY and typeof(out.get(k)) == TYPE_DICTIONARY:
			out[k] = merge(out[k], over[k])
		else:
			out[k] = over[k] if typeof(over[k]) != TYPE_DICTIONARY else over[k].duplicate(true)
	return out

static func cards_word(n: int) -> String:
	var m10 := n % 10; var m100 := n % 100
	if m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14): return "карты"
	if m10 == 1 and m100 != 11: return "карта"
	return "карт"
static func stock_needed(cfg: Dictionary) -> int: return 2 if cfg.hiddenTrump.enabled else 1
static func max_players(deck: int, hand: int, need: int) -> int: return mini(6, (deck - need) / hand)

## Settings in, a checked full copy out: {ok, cfg, errors: [{message, suggest: [{label, patch}]}]}
static func validate(input: Dictionary) -> Dictionary:
	var cfg := merge(defaults(), input)
	cfg.players = clampi(int(cfg.players), 2, 6)
	if not DECK_LOW.has(int(cfg.deckSize)): cfg.deckSize = 36
	cfg.deckSize = int(cfg.deckSize)
	cfg.handSize = clampi(int(cfg.handSize), 2, 8)
	for f in schema():
		if f.type == "int": path_set(cfg, f.path, clampi(int(path_get(cfg, f.path)), f.min, f.max))
	var errors := []
	var need := stock_needed(cfg)
	var used: int = cfg.players * cfg.handSize
	if used + need > cfg.deckSize:
		var sg := []
		var mp := max_players(cfg.deckSize, cfg.handSize, need)
		if mp >= 2: sg.append({"label": "Не больше %d игроков за столом" % mp, "patch": {"players": mp}})
		for sz in [24, 36, 52]:
			if cfg.players * cfg.handSize + need <= sz and sz > cfg.deckSize:
				sg.append({"label": "Колода на %d карт" % sz, "patch": {"deckSize": sz}}); break
		var mh: int = (cfg.deckSize - need) / cfg.players
		if mh >= 2: sg.append({"label": "По %d %s на руках" % [mh, cards_word(mh)], "patch": {"handSize": mh}})
		errors.append({"message": "Для %d игроков в колоде на %d карт не хватает карт: %d уходит в руки, а после раздачи должно остаться минимум %d." % [cfg.players, cfg.deckSize, used, need], "suggest": sg})
	if cfg.hiddenTrump.enabled and cfg.hiddenTrump.afterReveal == "marker" and cfg.hiddenTrump.reveal == "withLastCard":
		errors.append({"message": "Карта-указатель не достаётся игроку, поэтому её нельзя открывать в момент, когда её берут.",
			"suggest": [{"label": "Открывать, как заберут козырную", "patch": {"hiddenTrump": {"reveal": "afterTrumpCard"}}},
				{"label": "Пусть карта достаётся игроку", "patch": {"hiddenTrump": {"afterReveal": "draw"}}}]})
	return {"ok": errors.is_empty(), "cfg": cfg, "errors": errors}

static func rule_view(cfg: Dictionary) -> Dictionary:
	var o := cfg.duplicate(true)
	for k in TABLE_KEYS: o.erase(k)
	return o
static func apply_preset(current: Dictionary, id: String) -> Dictionary:
	var base := defaults()
	for k in TABLE_KEYS:
		if current.has(k): base[k] = current[k]
	for p in PRESETS:
		if p.id == id:
			if p.rules == null: return merge(base, rule_view(current))
			return merge(base, p.rules)
	return base
static func match_preset(cfg: Dictionary) -> String:
	var rv := JSON.stringify(_sorted(rule_view(validate(cfg).cfg)))
	for p in PRESETS:
		if p.rules == null: continue
		if JSON.stringify(_sorted(rule_view(merge(defaults(), p.rules)))) == rv: return p.id
	return "custom"
static func _sorted(d):
	if typeof(d) != TYPE_DICTIONARY: return d
	var keys = d.keys(); keys.sort()
	var out := {}
	for k in keys: out[k] = _sorted(d[k])
	return out

# ------------------------------------------------------------------ the match
static func next_alive(s: Dictionary, from: int) -> int:
	for i in range(1, s.n + 1):
		var p: int = (from + i) % s.n
		if s.hands[p].size() > 0: return p
	return -1
static func alive_seats(s: Dictionary) -> Array:
	var a := []
	for p in s.n:
		if s.hands[p].size() > 0: a.append(p)
	return a
static func open_count(s: Dictionary) -> int:
	var k := 0
	for x in s.table:
		if x.d < 0: k += 1
	return k
static func all_beaten(s: Dictionary) -> bool: return s.table.size() > 0 and open_count(s) == 0
static func rank_mask(s: Dictionary) -> int:
	var m := 0
	for x in s.table:
		m |= 1 << rank(x.a)
		if x.d >= 0: m |= 1 << rank(x.d)
	return m
static func can_beat(a: int, d: int, trump: int) -> bool:
	if suit(d) == suit(a): return rank(d) > rank(a)
	return suit(d) == trump and suit(a) != trump
static func limit_for(s: Dictionary, def: int) -> int:
	var l: int = mini(s.cfg.attackLimit, s.hands[def].size())
	if s.round == 0: l = mini(l, s.cfg.firstTrickLimit)
	return l
static func throwers(s: Dictionary) -> Array:
	var d: int = s.def
	var pol: String = s.cfg.throwIn
	var cand := []
	if pol == "attacker": cand = [s.att]
	elif pol == "neighbors":
		cand = [s.att]
		var nb := next_alive(s, d)
		if nb != -1 and nb != s.att: cand.append(nb)
	else:
		for p in s.n: cand.append(p)
	return cand.filter(func(q): return q != d and s.hands[q].size() > 0)
static func can_add_more(s: Dictionary) -> bool:
	if s.table.size() >= s.limit: return false
	if not s.taking and open_count(s) + 1 > s.hands[s.def].size(): return false
	return true
static func low_trump(s: Dictionary) -> int: return make(s.trump, DECK_LOW[s.cfg.deckSize])

static func transfer_target(s: Dictionary) -> int:
	var t: Dictionary = s.cfg.transfer
	if not t.enabled or s.phase != "defend" or s.taking or s.table.is_empty(): return -1
	for x in s.table:
		if x.d >= 0: return -1
	if not t.chain and s.transfers > 0: return -1
	var nd := next_alive(s, s.def)
	if nd == -1 or nd == s.def: return -1
	if s.table.size() + 1 > limit_for(s, nd): return -1
	return nd

## Everything this seat may do now: {k: "a"|"b"|"t"|"take"|"pass"|"swap", c, i}
static func actions(s: Dictionary, seat: int) -> Array:
	var out := []
	if s.over or seat < 0 or seat >= s.n: return out
	var h: Array = s.hands[seat]
	if s.phase == "lead":
		if seat != s.att: return out
		for c in h: out.append({"k": "a", "c": c})
		# trump swap
		if s.cfg.trumpSwap.enabled and not s.marker and s.stock.size() >= 2 and s.stock.has(s.trumpCard):
			var low := low_trump(s)
			if s.trumpCard != low and h.has(low): out.append({"k": "swap"})
		return out
	if s.phase == "defend" and seat == s.def:
		for i in s.table.size():
			if s.table[i].d >= 0: continue
			for c in h:
				if can_beat(s.table[i].a, c, s.trump): out.append({"k": "b", "c": c, "i": i})
		if transfer_target(s) >= 0:
			var r := rank(s.table[0].a)
			for c in h:
				if rank(c) == r: out.append({"k": "t", "c": c})
		out.append({"k": "take"})
		return out
	if not throwers(s).has(seat): return out
	if can_add_more(s):
		var m := rank_mask(s)
		for c in h:
			if not ((m >> rank(c)) & 1): continue
			if s.cfg.noTrumpThrow and suit(c) == s.trump: continue
			out.append({"k": "a", "c": c})
	if s.phase == "throw" and not s.done[seat]: out.append({"k": "pass"})
	return out

static func same_act(a: Dictionary, b: Dictionary) -> bool:
	return a.k == b.k and a.get("c", -9) == b.get("c", -9) and a.get("i", -9) == b.get("i", -9)
static func is_legal(s: Dictionary, seat: int, act: Dictionary) -> bool:
	for a in actions(s, seat):
		if same_act(a, act): return true
	return false
## Seats the game waits for.
static func pending(s: Dictionary) -> Array:
	if s.over: return []
	if s.phase == "lead": return [s.att]
	if s.phase == "defend": return [s.def]
	return throwers(s).filter(func(p): return not s.done[p])

static func _draw_one(s: Dictionary, p: int, ev: Array) -> void:
	var c: int = s.stock.pop_back()
	var pub: bool = c == s.trumpCard
	s.hands[p].append(c)
	if pub: s.known[p].append(c)
	ev.append({"t": "draw", "p": p, "c": c, "pub": pub})
	# hidden trump
	var hd = s.hidden
	if hd != null and not hd.revealed:
		if s.cfg.hiddenTrump.reveal == "afterTrumpCard":
			if s.stock.size() == 1:
				var H: int = s.stock[0]
				var from: int = s.trump
				hd.revealed = true; s.trump = suit(H); s.trumpCard = H
				var marker: bool = s.cfg.hiddenTrump.afterReveal == "marker"
				if marker: s.stock.pop_front(); s.marker = true
				ev.append({"t": "reveal", "c": H, "trump": s.trump, "from": from, "changed": s.trump != from, "marker": marker})
		elif s.stock.is_empty():
			var from2: int = s.trump
			hd.revealed = true; s.trump = suit(c); s.trumpCard = c
			ev[ev.size() - 1].pub = true
			if not s.known[p].has(c): s.known[p].append(c)
			ev.append({"t": "reveal", "c": c, "trump": s.trump, "from": from2, "changed": s.trump != from2, "marker": false, "taken": p})

static func _draw_order(s: Dictionary, att: int, def: int) -> Array:
	var order := []
	if s.cfg.drawOrder == "clockwise":
		for i in s.n: order.append((att + i) % s.n)
		return order
	for i in s.n:
		var p: int = (att + i) % s.n
		if p != def: order.append(p)
	if s.cfg.drawOrder == "defenderFirst": order.push_front(def)
	else: order.append(def)
	return order
static func _refill(s: Dictionary, ev: Array) -> void:
	for p in _draw_order(s, s.att, s.def):
		while s.hands[p].size() < s.cfg.handSize and s.stock.size() > 0: _draw_one(s, p, ev)

static func _begin_round(s: Dictionary, ev: Array) -> void:
	s.table = []; s.taking = false; s.transfers = 0
	for i in s.n: s.done[i] = false
	s.phase = "lead"
	s.limit = limit_for(s, s.def)
	ev.append({"t": "turn", "att": s.att, "def": s.def})
static func _finish(s: Dictionary, fool: int, groups: Array, reason: String, ev: Array) -> void:
	s.over = true; s.phase = "over"
	s.result = {"fool": fool, "places": groups, "reason": reason}
	ev.append({"t": "over", "fool": fool, "places": groups, "reason": reason})
static func _end_round(s: Dictionary, took: bool, ev: Array) -> void:
	var att: int = s.att
	var def: int = s.def
	var cards := []
	for x in s.table:
		cards.append(x.a)
		if x.d >= 0: cards.append(x.d)
	if took:
		for c in cards: s.hands[def].append(c); s.known[def].append(c)
		ev.append({"t": "collect", "p": def, "cards": cards})
	else:
		s.discard.append_array(cards)
		ev.append({"t": "discard", "cards": cards})
	s.table = []; s.taking = false
	_refill(s, ev)
	s.round += 1
	if s.stock.is_empty():
		var gone := []
		for i in s.n:
			if not s.out[i] and s.hands[i].is_empty(): s.out[i] = true; gone.append(i)
		if not gone.is_empty(): s.places.append(gone)
	var alive := alive_seats(s)
	if s.stock.is_empty():
		s.stale = s.stale + 1 if took else 0
		if alive.size() == 1:
			var g: Array = s.places.duplicate(true); g.append([alive[0]])
			_finish(s, alive[0], g, "normal", ev); return
		if alive.is_empty():
			var pol: String = s.cfg.endgame.simultaneousOut
			if pol == "draw": _finish(s, -1, s.places.duplicate(true), "simultaneous", ev); return
			var fool: int = def if pol == "defenderLoses" else att
			var groups: Array = s.places.slice(0, s.places.size() - 1)
			var last: Array = s.places[s.places.size() - 1].filter(func(x): return x != fool)
			if not last.is_empty(): groups.append(last)
			groups.append([fool])
			_finish(s, fool, groups, "simultaneous", ev); return
		if s.stale >= s.cfg.endgame.stalemateRounds:
			var g2: Array = s.places.duplicate(true); g2.append(alive)
			_finish(s, -1, g2, "stalemate", ev); return
	else:
		s.stale = 0
	s.att = next_alive(s, def) if took else (def if s.hands[def].size() > 0 else next_alive(s, def))
	s.def = next_alive(s, s.att)
	_begin_round(s, ev)
static func _round_should_end(s: Dictionary) -> bool:
	if s.phase != "throw": return false
	if s.table.size() >= s.limit: return true
	if not s.taking and s.hands[s.def].is_empty(): return true
	for p in throwers(s):
		if not s.done[p]: return false
	return true
static func _clear_done(s: Dictionary) -> void:
	for i in s.n: s.done[i] = false

static func step(s: Dictionary, seat: int, act: Dictionary, ev: Array) -> Array:
	match act.k:
		"a":
			s.hands[seat].erase(act.c); s.known[seat].erase(act.c)
			s.table.append({"a": act.c, "d": -1})
			ev.append({"t": "attack", "p": seat, "c": act.c, "i": s.table.size() - 1})
			_clear_done(s)
			s.phase = "throw" if s.taking else "defend"
		"b":
			s.hands[seat].erase(act.c); s.known[seat].erase(act.c)
			s.table[act.i].d = act.c
			ev.append({"t": "beat", "p": seat, "c": act.c, "i": act.i})
			if all_beaten(s): _clear_done(s); s.phase = "throw"
		"t":
			var nd := transfer_target(s)
			s.hands[seat].erase(act.c); s.known[seat].erase(act.c)
			s.table.append({"a": act.c, "d": -1})
			s.att = seat; s.def = nd; s.transfers += 1
			s.limit = limit_for(s, s.def)
			_clear_done(s)
			ev.append({"t": "transfer", "p": seat, "c": act.c, "i": s.table.size() - 1, "to": nd})
		"take":
			s.taking = true; _clear_done(s); s.phase = "throw"
			ev.append({"t": "take", "p": seat})
		"pass":
			s.done[seat] = true
			ev.append({"t": "pass", "p": seat, "taking": s.taking})
		"swap":
			var low := low_trump(s)
			var old: int = s.trumpCard
			var idx: int = s.stock.find(old)
			s.hands[seat].erase(low); s.hands[seat].append(old)
			s.stock[idx] = low; s.trumpCard = low
			s.known[seat].erase(low); s.known[seat].append(old)
			ev.append({"t": "swap", "p": seat, "give": low, "take": old})
			return ev
	if not s.over and _round_should_end(s): _end_round(s, s.taking, ev)
	return ev

## The checked entry point: {ok, ev | error}
static func apply(s: Dictionary, seat: int, act: Dictionary) -> Dictionary:
	if s.over: return {"ok": false, "error": "Партия уже закончена."}
	if not is_legal(s, seat, act): return {"ok": false, "error": "Сейчас так ходить нельзя."}
	return {"ok": true, "ev": step(s, seat, act, [])}

## input: settings; opts: {deck: Array (index 0 = bottom), first: int, rng}
static func new_game(input: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var v := validate(input)
	if not v.ok: push_error("rules not valid"); return {}
	var cfg: Dictionary = v.cfg
	var n: int = cfg.players
	var rng: RandomNumberGenerator = opts.get("rng", RandomNumberGenerator.new())
	if not opts.has("rng"): rng.randomize()
	var deck: Array = opts.deck.duplicate() if opts.has("deck") else shuffle(build_deck(cfg.deckSize), rng)
	var s := {"cfg": cfg, "n": n, "hands": [], "known": [], "done": [], "out": [], "stock": deck,
		"trump": -1, "trumpCard": -1, "marker": false, "hidden": null, "table": [], "att": 0, "def": 1,
		"phase": "lead", "taking": false, "limit": 0, "transfers": 0, "discard": [], "places": [],
		"round": 0, "stale": 0, "over": false, "result": null}
	for p in n:
		s.hands.append([]); s.known.append([]); s.done.append(false); s.out.append(false)
	var ti := 1 if cfg.hiddenTrump.enabled else 0
	s.trumpCard = s.stock[ti]
	s.trump = suit(s.trumpCard)
	if cfg.hiddenTrump.enabled: s.hidden = {"revealed": false}
	var ev := []
	for k in cfg.handSize:
		for p in n: _draw_one(s, p, ev)
	var first: int = opts.get("first", -1)
	if first < 0:
		if cfg.firstAttacker == "seat0": first = 0
		elif cfg.firstAttacker == "random": first = rng.randi_range(0, n - 1)
		else:
			var best := -1; var bv := 99
			for p in n:
				for c in s.hands[p]:
					if suit(c) == s.trump and rank(c) < bv: bv = rank(c); best = p
			first = best if best >= 0 else (0 if cfg.firstAttackerFallback == "seat0" else rng.randi_range(0, n - 1))
	s.att = first
	s.def = next_alive(s, first)
	_begin_round(s, ev)
	return {"s": s, "ev": ev}

## The face-up trump card on the table (under the deck, or the marker), or -1
static func visible_trump(s: Dictionary) -> int:
	if s.marker: return s.trumpCard
	return s.trumpCard if s.stock.has(s.trumpCard) else -1

# ------------------------------------------------------------------ bots
const P_NORMAL := {"flub": 0.0, "thrTake": 0.625, "thrIn": 0.5, "thrEnd": 0.75, "trumpCostMax": 0.5, "transferTrump": 0.25}
const P_EASY := {"flub": 0.22, "thrTake": 0.375, "thrIn": 0.25, "thrEnd": 0.375, "trumpCostMax": 1.125, "transferTrump": 0.25}
const EPS := 1e-9
static func rel_of(s: Dictionary, c: int) -> float:
	var lo: int = DECK_LOW[s.cfg.deckSize] - 2
	return float(rank(c) - lo) / float(12 - lo)
static func val(c: int, tr: int) -> int: return rank(c) + (20 if suit(c) == tr else 0)
static func _find_k(acts: Array, k: String):
	for a in acts:
		if a.k == k: return a
	return null
static func plan_defense(s: Dictionary, seat: int):
	var h: Array = s.hands[seat]
	var tr: int = s.trump
	var idx := []
	for i in s.table.size():
		if s.table[i].d < 0: idx.append(i)
	idx.sort_custom(func(x, y): return val(s.table[x].a, tr) > val(s.table[y].a, tr))
	var used := {}
	var plan := []
	for i in idx:
		var a: int = s.table[i].a
		var best := -1; var bv := 999
		for c in h:
			if used.has(c): continue
			if can_beat(a, c, tr) and val(c, tr) < bv: bv = val(c, tr); best = c
		if best < 0: return null
		used[best] = true
		plan.append({"c": best, "i": i})
	return plan

## A bot's move. level: "easy" | "normal" | "hard"
static func choose(s: Dictionary, seat: int, level: String, rng: RandomNumberGenerator):
	var acts := actions(s, seat)
	if acts.is_empty(): return null
	if acts.size() == 1: return acts[0]
	if level == "hard": return _choose_hard(s, seat, rng)
	var P: Dictionary = P_EASY if level == "easy" else P_NORMAL
	if P.flub > 0 and rng.randf() < P.flub: return acts[rng.randi_range(0, acts.size() - 1)]
	var swap = _find_k(acts, "swap")
	if swap != null: return swap
	var h: Array = s.hands[seat]
	var tr: int = s.trump
	var stock_n: int = s.stock.size()
	if s.phase == "lead":
		var cnt := []; cnt.resize(13); cnt.fill(0)
		for c in h: cnt[rank(c)] += 1
		var best = null; var bs := 1e9
		for a in acts:
			if a.k != "a": continue
			var sc: float = val(a.c, tr) - 1.4 * (cnt[rank(a.c)] - 1)
			if sc < bs: bs = sc; best = a
		return best if best != null else acts[0]
	if s.phase == "throw" or seat != s.def:
		var low = null; var lv := 1e9
		for a in acts:
			if a.k == "a" and val(a.c, tr) < lv: lv = val(a.c, tr); low = a
		var pass_act = _find_k(acts, "pass")
		if low == null: return pass_act if pass_act != null else acts[0]
		var is_tr: bool = suit(low.c) == tr
		var r := rel_of(s, low.c)
		var go: bool
		if s.taking: go = stock_n == 0 if is_tr else (r <= P.thrTake + EPS or stock_n == 0)
		else: go = (stock_n == 0 and h.size() == 1) or (not is_tr and r <= (P.thrEnd if stock_n == 0 else P.thrIn) + EPS)
		if pass_act == null: return low if go else null
		return low if go else pass_act
	var take = _find_k(acts, "take")
	var tb = null; var tv := 1e9
	for a in acts:
		if a.k == "t" and val(a.c, tr) < tv: tv = val(a.c, tr); tb = a
	if tb != null and (suit(tb.c) != tr or rel_of(s, tb.c) <= P.transferTrump + EPS): return tb
	var plan = plan_defense(s, seat)
	if plan == null: return take
	if stock_n >= 3:
		for x in plan:
			var att: int = s.table[x.i].a
			if suit(x.c) == tr and suit(att) != tr and rel_of(s, x.c) >= P.trumpCostMax - EPS and rel_of(s, att) <= 0.5 + EPS: return take
	return {"k": "b", "c": plan[0].c, "i": plan[0].i}

## One possible deal of the cards this seat cannot see (only public facts are used).
static func deal_unseen(s: Dictionary, me: int, rng: RandomNumberGenerator) -> Dictionary:
	var t := s.duplicate(true)
	var seen := {}
	for c in s.hands[me]: seen[c] = 1
	for x in s.table:
		seen[x.a] = 1
		if x.d >= 0: seen[x.d] = 1
	for c in s.discard: seen[c] = 1
	if s.marker: seen[s.trumpCard] = 1
	for p in s.n:
		if p != me:
			for c in s.known[p]: seen[c] = 1
	var vt := visible_trump(s)
	var in_pile: bool = not s.marker and vt >= 0
	var t_idx := 1 if (s.hidden != null and not s.hidden.revealed) else 0
	if in_pile: seen[vt] = 1
	var unseen := build_deck(s.cfg.deckSize).filter(func(c): return not seen.has(c))
	shuffle(unseen, rng)
	var k := 0
	for p in s.n:
		if p == me: continue
		var need: int = s.hands[p].size() - s.known[p].size()
		var hh: Array = s.known[p].duplicate()
		hh.append_array(unseen.slice(k, k + need)); k += need
		t.hands[p] = hh
	var pile := []
	for i in s.stock.size():
		if in_pile and i == t_idx: pile.append(vt)
		else: pile.append(unseen[k]); k += 1
	t.stock = pile
	return t
static func _playout(t: Dictionary, rng: RandomNumberGenerator, cap: int) -> void:
	var n := 0
	while not t.over and n < cap:
		n += 1
		var pend := pending(t)
		if pend.is_empty(): break
		var act = choose(t, pend[0], "normal", rng)
		if act == null: break
		step(t, pend[0], act, [])
static func _choose_hard(s: Dictionary, me: int, rng: RandomNumberGenerator):
	var acts := actions(s, me)
	var swap = _find_k(acts, "swap")
	if swap != null: return swap
	var fallback = choose(s, me, "normal", rng)
	var score := []; score.resize(acts.size()); score.fill(0.0)
	var start := Time.get_ticks_msec()
	for j in 24:
		if j >= 6 and Time.get_ticks_msec() - start > 450: break
		var d := deal_unseen(s, me, rng)
		var seed := rng.randi()
		for i in acts.size():
			var t := d.duplicate(true)
			step(t, me, acts[i], [])
			var r := RandomNumberGenerator.new(); r.seed = seed + j
			_playout(t, r, 500)
			score[i] += 0.5 if (not t.over or t.result.fool == -1) else (0.0 if t.result.fool == me else 1.0)
	var bi := 0
	for i in range(1, acts.size()):
		if score[i] > score[bi] + 1e-9: bi = i
		elif absf(score[i] - score[bi]) < 1e-9 and fallback != null and same_act(acts[i], fallback): bi = i
	return acts[bi]
