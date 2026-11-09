extends Node
## Дурак: menus, settings and the match against the computer.
## Rules and bots: Core (scripts/core.gd). The table: table3d.gd. All screens are built here in code.

const Table3D := preload("res://scripts/table3d.gd")
const SAVE := "user://match.save"
const PREFS := "user://prefs.save"
const NAMES := ["Арман", "Айгерим", "Данияр", "Дина", "Ерлан", "Алия", "Тимур", "Мадина", "Санжар", "Жанна", "Руслан", "Катя", "Марат", "Асель"]
const UI := {
	"cabinet": {"bg": Color("2a170c"), "panel": Color(0.16, 0.09, 0.05, 0.9), "line": Color(1, 0.76, 0.47, 0.3), "text": Color("fff3e0"), "muted": Color("e1c6a4"), "acc": Color("ffb62e"), "acc_text": Color("2a1300")},
	"casino": {"bg": Color("0b3324"), "panel": Color(0.03, 0.15, 0.1, 0.9), "line": Color(0.47, 1, 0.75, 0.28), "text": Color("eafff4"), "muted": Color("b8e6cf"), "acc": Color("ffd23f"), "acc_text": Color("2a1a00")},
	"neon": {"bg": Color("1a0b40"), "panel": Color(0.08, 0.04, 0.19, 0.9), "line": Color(0.47, 0.86, 1, 0.4), "text": Color("f2ecff"), "muted": Color("c4b6ff"), "acc": Color("34e7ff"), "acc_text": Color("08031a")},
	"day": {"bg": Color("f3e3c8"), "panel": Color(1, 0.98, 0.94, 0.94), "line": Color(0.55, 0.35, 0.12, 0.3), "text": Color("3a2410"), "muted": Color("7a5a3a"), "acc": Color("ff8a1f"), "acc_text": Color("ffffff")},
}

var pref := {"theme": "cabinet", "shape": "round", "face": "vt", "back": "blue", "speed": 1.0, "sort": "suit", "sound": true, "hints": true,
	"opp": 1, "level": "normal", "preset": "classic", "rules": {}, "deckSize": 36, "handSize": 6}
var table: Node3D
var ui: Control
var screens := {}
var screen := "home"
var history: Array = []
var C: Dictionary = UI.cabinet
var font_body: Font
var font_bold: Font
var font_title: Font
var rng := RandomNumberGenerator.new()
var fast := false            # tests: everything at once

# match state
var match_d = null           # {s, names, level, input}
var ME := 0
var busy := false
var dealing := false
var sel := -1
var deck_n := 0
var bot_timer: SceneTreeTimer = null
var bot_gen := 0

# game screen widgets
var hand_box: Control
var status_lbl: Label
var btn_take: Button
var btn_pass: Button
var btn_swap: Button
var btn_transfer: Button
var trump_lbl: Label
var deck_lbl: Label
var labels_box: Control
var toast_lbl: Label
var overlay_box: Control
var hand_cards := {}         # card -> TextureRect

# ------------------------------------------------------------------ start
func _ready() -> void:
	rng.randomize()
	_load_prefs()
	get_tree().set_auto_accept_quit(false)
	var sym: Font = load("res://fonts/DejaVuSans-Bold.ttf")          # ♠♥♦♣ ☰ are not in Inter
	font_body = load("res://fonts/Inter-SemiBold.otf"); font_body.fallbacks = [sym]
	font_bold = load("res://fonts/Inter-ExtraBold.otf"); font_bold.fallbacks = [sym]
	var lora := FontVariation.new(); lora.base_font = load("res://fonts/Lora.ttf"); lora.variation_opentype = {"wght": 700}
	font_title = lora
	table = Table3D.new()
	add_child(table)
	var layer := CanvasLayer.new(); add_child(layer)
	ui = Control.new(); ui.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(ui)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	_apply_look()
	_show("home")
	get_viewport().size_changed.connect(_on_resize)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_back_pressed(what == NOTIFICATION_WM_CLOSE_REQUEST)
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save_match()

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: _back_pressed(false)

func _load_prefs() -> void:
	if FileAccess.file_exists(PREFS):
		var f := FileAccess.open(PREFS, FileAccess.READ)
		var d = f.get_var()
		if typeof(d) == TYPE_DICTIONARY:
			for k in d: pref[k] = d[k]
	if not UI.has(pref.theme): pref.theme = "cabinet"
func _save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE); f.store_var(pref)

func _apply_look() -> void:
	C = UI[pref.theme]
	table.speed = 40.0 if fast else float(pref.speed)
	table.set_look(pref)
	if match_d:
		table.set_counts(_counts())
		table.set_deck(deck_n, Core.visible_trump(match_d.s))
		_render_hand()

func _on_resize() -> void:
	if screen == "game" and match_d:
		table.set_view_bottom(_hand_inset()); _layout_hand(); _place_labels()

# ------------------------------------------------------------------ widgets
func _sb(bg: Color, radius := 22, border: Color = Color(0, 0, 0, 0), bw := 0, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(radius)
	if bw > 0: s.border_color = border; s.set_border_width_all(bw)
	if shadow > 0: s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = shadow; s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s
func _label(text: String, size := 28, color: Color = Color(0, 0, 0, 0), font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", font if font else font_body)
	l.add_theme_color_override("font_color", color if color.a > 0 else C.text)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
func _style_button(b: Button, kind := "normal", radius := 26) -> void:
	var bg: Color = C.panel; var fg: Color = C.text; var border: Color = C.line
	if kind == "primary": bg = C.acc; fg = C.acc_text; border = C.acc
	elif kind == "warn": bg = Color("e2522f"); fg = Color.WHITE; border = bg
	elif kind == "alt": bg = Color("2f86e2"); fg = Color.WHITE; border = bg
	elif kind == "on": bg = C.acc.darkened(0.05); fg = C.acc_text; border = C.acc
	b.add_theme_stylebox_override("normal", _sb(bg, radius, border, 2, 6))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.06), radius, border, 2, 6))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), radius, border, 2, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.3), radius, border, 1, 0))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", fg.darkened(0.4))
	b.add_theme_font_override("font", font_bold)
func _button(text: String, sub := "", kind := "normal", h := 104) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, h)
	_style_button(b, kind)
	if sub == "":
		b.text = text; b.add_theme_font_size_override("font_size", 32)
	else:
		var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 0)
		var fg: Color = C.acc_text if kind == "primary" else C.text
		v.add_child(_label(text, 34, fg, font_bold, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_label(sub, 22, fg.lerp(Color(fg, 0.0), 0.3) if kind == "primary" else C.muted, font_body, HORIZONTAL_ALIGNMENT_CENTER))
		b.add_child(v)
	b.pressed.connect(func(): _snd("click"))
	return b
func _group(title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(C.panel, 28, C.line, 2))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	if title != "": v.add_child(_label(title.to_upper(), 21, C.muted))
	v.set_meta("panel", p)
	return v
func _seg(options: Array, value, on_pick: Callable, vertical := false) -> BoxContainer:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for o in options:
		var b := Button.new(); b.text = o[1]; b.custom_minimum_size = Vector2(0, 70)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 24)
		b.clip_text = false; b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_button(b, "on" if str(o[0]) == str(value) else "normal", 18)
		var v = o[0]
		b.pressed.connect(func(): _snd("click"); on_pick.call(v))
		box.add_child(b)
	return box
func _stepper(value: int, on_change: Callable) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	for d in [-1, 1]:
		var b := Button.new(); b.text = "−" if d < 0 else "+"; b.custom_minimum_size = Vector2(76, 66)
		_style_button(b, "normal", 18); b.add_theme_font_size_override("font_size", 34)
		b.pressed.connect(func(): _snd("click"); on_change.call(value + d))
		if d < 0: h.add_child(b)
		else:
			var l := _label(str(value), 32, C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER); l.custom_minimum_size = Vector2(56, 0)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(l); h.add_child(b)
	return h
func _toggle(on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new(); c.button_pressed = on
	c.toggled.connect(func(v): _snd("click"); on_change.call(v))
	c.scale = Vector2(1.6, 1.6)
	c.custom_minimum_size = Vector2(110, 60)
	return c
func _row(text: String, right: Control, help := "") -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	var l := _label(text, 27); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l); h.add_child(right); v.add_child(h)
	if help != "": v.add_child(_label(help, 21, C.muted))
	return v

## a sheet screen: title bar with «‹», scrolling content, optional bottom button
func _sheet(title: String, bottom: Control = null) -> VBoxContainer:
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(C.bg, 0.9); bg.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(bg)
	var m := MarginContainer.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 26)
	m.add_theme_constant_override("margin_top", 40); m.add_theme_constant_override("margin_bottom", 30)
	root.add_child(m)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 16); m.add_child(col)
	var bar := HBoxContainer.new(); bar.add_theme_constant_override("separation", 14)
	var bk := Button.new(); bk.text = "‹"; bk.custom_minimum_size = Vector2(84, 84); _style_button(bk, "normal", 22); bk.add_theme_font_size_override("font_size", 52)
	bk.pressed.connect(_back)
	bar.add_child(bk)
	var t := _label(title, 50, C.text, font_title); t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.add_child(t)
	col.add_child(bar)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation", 18)
	sc.add_child(content)
	if bottom: col.add_child(bottom)
	root.set_meta("content", content); root.set_meta("scroll", sc)
	content.set_meta("root", root)
	return content

# ------------------------------------------------------------------ screens
func _show(name: String, no_history := false) -> void:
	if not no_history and name != screen: history.append(screen)
	screen = name
	for c in ui.get_children(): c.queue_free()
	screens = {}
	match name:
		"home": _build_home(); _menu_scene()
		"setup": _build_setup()
		"look": _build_look()
		"how": _build_how()
		"game": _build_game()
func _back() -> void:
	var to: String = history.pop_back() if history.size() else "home"
	if to == "game" and match_d == null: to = "home"
	_show(to, true)
	if to == "game": _enter_game_ui()

var _exit_armed := false
func _back_pressed(close_request: bool) -> void:
	if close_request and screen == "home": get_tree().quit(); return
	if overlay_box and is_instance_valid(overlay_box):
		var oid: String = overlay_box.get_meta("id", "")
		_close_overlay()
		if oid == "end": _leave()
		return
	if screen == "game":
		if sel >= 0: sel = -1; table.highlight([]); _refresh_ui(); return
		_overlay_exit(); return
	if screen != "home": _back(); return
	if _exit_armed: get_tree().quit(); return
	_exit_armed = true
	_toast_global("Нажмите «Назад» ещё раз, чтобы выйти")
	get_tree().create_timer(2.0).timeout.connect(func(): _exit_armed = false)

func _menu_scene() -> void:
	if match_d: return
	table.view_bottom = 0
	var n: int = mini(pref.opp + 1, 6)
	table.new_match(n, 0, 20, -1)
	var c := []
	for k in n: c.append(0 if k == 0 else 6)
	table.set_counts(c)
	table.set_view_bottom(_vs().y * 0.42)

func _vs() -> Vector2: return ui.get_viewport_rect().size

func _build_home() -> void:
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); ui.add_child(root)
	var shade := ColorRect.new(); shade.set_anchors_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new(); g.set_color(0, Color(C.bg, 0.0)); g.set_color(1, Color(C.bg, 0.95)); g.add_point(0.45, Color(C.bg, 0.2))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new(); tr.texture = gt; tr.set_anchors_preset(Control.PRESET_FULL_RECT); tr.stretch_mode = TextureRect.STRETCH_SCALE; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	shade.queue_free()
	var m := MarginContainer.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 34)
	m.add_theme_constant_override("margin_top", 60); m.add_theme_constant_override("margin_bottom", 50)
	root.add_child(m)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 18); m.add_child(col)
	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; col.add_child(sp)
	var title := _label("Дурак", 150, C.acc, font_title, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7)); title.add_theme_constant_override("shadow_offset_y", 6); title.add_theme_constant_override("shadow_outline_size", 18)
	col.add_child(title)
	col.add_child(_label("КАРТОЧНАЯ ИГРА", 24, C.muted, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 40); col.add_child(sp2)
	var has_save := _has_save()
	if has_save:
		var bc := _button("Продолжить", "вернуться к партии", "primary", 116)
		bc.pressed.connect(func(): _resume()); col.add_child(bc)
	var bp := _button("Играть", "с компьютером", "normal" if has_save else "primary", 116)
	bp.pressed.connect(func(): _show("setup")); col.add_child(bp)
	var bo := _button("Онлайн", "с живыми игроками · скоро", "normal", 116)
	bo.pressed.connect(func(): _overlay_info("🌐", "Онлайн скоро", "Игра с живыми соперниками по сети появится в одном из следующих обновлений: комнаты для друзей, быстрый поиск соперника и рейтинг."))
	col.add_child(bo)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 16)
	var bl := _button("Оформление", "", "normal", 96); bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bl.pressed.connect(func(): _show("look"))
	var bh := _button("Как играть", "", "normal", 96); bh.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bh.pressed.connect(func(): _show("how"))
	row.add_child(bl); row.add_child(bh); col.add_child(row)
	col.add_child(_label("версия 2.0", 20, Color(C.muted, 0.7), font_body, HORIZONTAL_ALIGNMENT_CENTER))

func _cur_input() -> Dictionary:
	var base: Dictionary
	if pref.preset == "custom": base = Core.merge(Core.defaults(), pref.rules)
	else: base = Core.apply_preset({}, pref.preset)
	base.players = pref.opp + 1; base.deckSize = pref.deckSize; base.handSize = pref.handSize
	return base
func _set_rule(path: String, v) -> void:
	var cur := _cur_input()
	Core.path_set(cur, path, v)
	pref.rules = Core.rule_view(cur)
	pref.preset = Core.match_preset(cur)
	_save_prefs(); _rebuild()
func _rebuild() -> void:
	var sc: ScrollContainer = null
	if ui.get_child_count() > 0 and ui.get_child(0).has_meta("scroll"): sc = ui.get_child(0).get_meta("scroll")
	var y := sc.scroll_vertical if sc else 0
	_show(screen, true)
	await get_tree().process_frame
	if ui.get_child_count() > 0:
		for c in ui.get_children():
			if c.has_meta("scroll") and not c.is_queued_for_deletion(): c.get_meta("scroll").scroll_vertical = y

var _more_open := false
func _build_setup() -> void:
	var v := Core.validate(_cur_input())
	var cfg: Dictionary = v.cfg
	var start := _button("Начать игру", "", "primary", 110)
	start.disabled = not v.ok
	start.pressed.connect(func(): _start_match(_cur_input(), pref.level))
	var c := _sheet("Новая игра", start)
	ui.add_child(c.get_meta("root"))
	var g := _group("Соперников")
	var opts := []
	for n in [1, 2, 3, 4, 5]: opts.append([n, str(n)])
	g.add_child(_seg(opts, pref.opp, func(n): pref.opp = n; _save_prefs(); _rebuild(); _menu_scene()))
	var np: int = pref.opp + 1
	g.add_child(_label("За столом %d %s: вы и %d %s." % [np, _pl(np, "игрок", "игрока", "игроков"), pref.opp, _pl(pref.opp, "соперник", "соперника", "соперников")], 22, C.muted))
	c.add_child(g.get_meta("panel"))
	var gm := _group("Режим")
	for p in Core.PRESETS:
		var b := Button.new(); b.custom_minimum_size = Vector2(0, 108)
		_style_button(b, "on" if pref.preset == p.id else "normal", 22)
		var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.offset_left = 22; vb.offset_right = -22; vb.offset_top = 10; vb.alignment = BoxContainer.ALIGNMENT_CENTER
		var fg: Color = C.acc_text if pref.preset == p.id else C.text
		vb.add_child(_label(p.name, 30, fg, font_bold)); vb.add_child(_label(p.desc, 21, fg.lerp(C.muted, 0.4)))
		b.add_child(vb)
		var pid: String = p.id
		b.pressed.connect(func():
			_snd("click")
			pref.preset = pid
			if pid == "custom": pref.rules = Core.rule_view(cfg); _more_open = true
			_save_prefs(); _rebuild())
		gm.add_child(b)
	c.add_child(gm.get_meta("panel"))
	var gl := _group("Сила соперников")
	gl.add_child(_seg([["easy", "Новички"], ["normal", "Опытные"], ["hard", "Мастера"]], pref.level, func(x): pref.level = x; _save_prefs(); _rebuild()))
	c.add_child(gl.get_meta("panel"))
	var gd := _group("Колода")
	gd.add_child(_seg([[24, "24 карты"], [36, "36 карт"], [52, "52 карты"]], pref.deckSize, func(x): pref.deckSize = x; _save_prefs(); _rebuild()))
	gd.add_child(_row("Карт на руках", _stepper(pref.handSize, func(x): pref.handSize = clampi(x, 2, 8); _save_prefs(); _rebuild())))
	c.add_child(gd.get_meta("panel"))
	var gr := _group("")
	var fold := Button.new(); fold.text = ("▾  " if _more_open else "▸  ") + "Все правила"; fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(fold, "normal", 18); fold.add_theme_font_size_override("font_size", 30); fold.custom_minimum_size = Vector2(0, 80)
	fold.pressed.connect(func(): _more_open = not _more_open; _rebuild())
	gr.add_child(fold)
	if _more_open:
		var last := ""
		for f in Core.schema():
			if f.has("depends") and Core.path_get(cfg, f.depends[0]) != f.depends[1]: continue
			if f.group != last:
				last = f.group
				gr.add_child(_label(Core.GROUPS[f.group].to_upper(), 21, C.acc))
			var val = Core.path_get(cfg, f.path)
			var path: String = f.path
			if f.type == "bool":
				gr.add_child(_row(f.label, _toggle(val, func(x): _set_rule(path, x)), f.get("help", "")))
			elif f.type == "int":
				var mn: int = f.min; var mx: int = f.max
				gr.add_child(_row(f.label, _stepper(val, func(x): _set_rule(path, clampi(x, mn, mx))), f.get("help", "")))
			else:
				gr.add_child(_label(f.label, 27))
				gr.add_child(_seg(f.options, val, func(x): _set_rule(path, x), true))
			var sep := HSeparator.new(); sep.add_theme_color_override("separator", C.line); gr.add_child(sep)
	c.add_child(gr.get_meta("panel"))
	for e in v.errors:
		var ge := _group("")
		ge.get_meta("panel").add_theme_stylebox_override("panel", _sb(Color("5a1a10", 0.9), 26, Color("ff6f5e"), 2))
		ge.add_child(_label(e.message, 24, Color.WHITE))
		for sg in e.suggest:
			var b := _button(sg.label, "", "normal", 76); b.add_theme_font_size_override("font_size", 24)
			var patch: Dictionary = sg.patch
			b.pressed.connect(func():
				if patch.has("players"): pref.opp = patch.players - 1
				if patch.has("deckSize"): pref.deckSize = patch.deckSize
				if patch.has("handSize"): pref.handSize = patch.handSize
				var rest := patch.duplicate(true)
				for k in Core.TABLE_KEYS: rest.erase(k)
				if not rest.is_empty():
					pref.rules = Core.rule_view(Core.merge(_cur_input(), rest)); pref.preset = "custom"
				_save_prefs(); _rebuild(); _menu_scene())
			ge.add_child(b)
		c.add_child(ge.get_meta("panel"))

func _build_look() -> void:
	var c := _sheet("Оформление")
	ui.add_child(c.get_meta("root"))
	var gt := _group("Тема")
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 14); grid.add_theme_constant_override("v_separation", 14)
	for k in Table3D.THEMES:
		var b := Button.new(); b.custom_minimum_size = Vector2(0, 130); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var th: Dictionary = Table3D.THEMES[k]
		var col: Color = th.felt if th.surface == "felt" else th.wood
		b.add_theme_stylebox_override("normal", _sb(th.bg.lerp(col, 0.45), 24, C.acc if pref.theme == k else Color(1, 1, 1, 0.15), 5 if pref.theme == k else 2))
		b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("normal")); b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.text = th.name; b.add_theme_font_override("font", font_bold); b.add_theme_font_size_override("font_size", 30)
		var fc := Color.WHITE if k != "day" else Color("3a2410")
		for st in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(st, fc)
		var key: String = k
		b.pressed.connect(func(): _snd("click"); pref.theme = key; _save_prefs(); _apply_look(); _rebuild())
		grid.add_child(b)
	gt.add_child(grid); c.add_child(gt.get_meta("panel"))
	var gs := _group("Стол")
	gs.add_child(_seg([["round", "Овальный"], ["square", "Прямоугольный"]], pref.shape, func(x): pref.shape = x; _save_prefs(); _apply_look(); _rebuild()))
	c.add_child(gs.get_meta("panel"))
	var gf := _group("Карты")
	var hf := HBoxContainer.new(); hf.add_theme_constant_override("separation", 14)
	for f in [["vt", "Винтаж"], ["ru", "Русские"], ["pk", "Покерные"]]:
		hf.add_child(_pic_button("res://cards/%s/1-13.webp" % f[0], f[1], pref.face == f[0], func(): pref.face = f[0]; _save_prefs(); _apply_look(); _rebuild()))
	gf.add_child(hf); c.add_child(gf.get_meta("panel"))
	var gb := _group("Рубашка")
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10)
	for k in Table3D.BACKS:
		var key: String = k
		hb.add_child(_pic_button("res://cards/backs/%s.webp" % k, "", pref.back == k, func(): pref.back = key; _save_prefs(); _apply_look(); _rebuild()))
	gb.add_child(hb); c.add_child(gb.get_meta("panel"))
	var gg := _group("Игра")
	gg.add_child(_label("Скорость анимации", 27))
	gg.add_child(_seg([[0.7, "Медленно"], [1.0, "Обычно"], [1.6, "Быстро"]], pref.speed, func(x): pref.speed = x; _save_prefs(); _apply_look(); _rebuild()))
	gg.add_child(_label("Мои карты", 27))
	gg.add_child(_seg([["suit", "По мастям"], ["rank", "По старшинству"]], pref.sort, func(x): pref.sort = x; _save_prefs(); _rebuild()))
	gg.add_child(_row("Звук", _toggle(pref.sound, func(x): pref.sound = x; _save_prefs())))
	gg.add_child(_row("Подсвечивать карты, которыми можно ходить", _toggle(pref.hints, func(x): pref.hints = x; _save_prefs())))
	c.add_child(gg.get_meta("panel"))

func _pic_button(path: String, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new(); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 200 if text != "" else 150)
	_style_button(b, "on" if on else "normal", 18)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.offset_top = 10; v.offset_bottom = -8; v.offset_left = 6; v.offset_right = -6
	var tr := TextureRect.new(); tr.texture = load(path); tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	if text != "": v.add_child(_label(text, 22, C.acc_text if on else C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(v)
	b.pressed.connect(func(): _snd("click"); cb.call())
	return b

func _build_how() -> void:
	var c := _sheet("Как играть")
	ui.add_child(c.get_meta("root"))
	for part in [["Цель", "Избавиться от всех карт. Кто остался с картами последним, тот и дурак."],
		["Раздача и козырь", "Каждому раздают по 6 карт. Карта под колодой показывает козырную масть. Козырь бьёт любую карту другой масти."],
		["Ход", "Атакующий кладёт карту. Защищающийся бьёт её старшей картой той же масти или козырем. Остальные могут подкидывать карты того же достоинства, что уже лежат на столе."],
		["Беру и Бито", "Не можете отбиться — «Беру», карты со стола уходят к вам. Отбились от всего — атакующие нажимают «Бито», карты уходят в сброс, ход переходит к вам."],
		["Переводной", "Пока ни одна карта не побита, защищающийся может положить карту того же достоинства и перевести атаку на следующего игрока."],
		["Как ходить", "Нажмите на карту или перетащите её на стол. Если карту можно положить по-разному, нажмите свою карту, потом карту на столе, которую бьёте, или кнопку «Перевести»."]]:
		var g := _group(part[0]); g.add_child(_label(part[1], 26)); c.add_child(g.get_meta("panel"))

func _pl(n: int, a: String, b: String, c: String) -> String:
	var m10 := n % 10; var m100 := n % 100
	if m10 == 1 and m100 != 11: return a
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14): return b
	return c

# ------------------------------------------------------------------ overlays
func _overlay(id: String) -> VBoxContainer:
	_close_overlay()
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(dim)
	var center := CenterContainer.new(); center.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(center)
	var p := PanelContainer.new(); p.custom_minimum_size = Vector2(_vs().x * 0.84, 0)
	var sb := _sb(C.bg, 40, C.line, 2, 20); sb.content_margin_left = 34; sb.content_margin_right = 34; sb.content_margin_top = 34; sb.content_margin_bottom = 34
	p.add_theme_stylebox_override("panel", sb)
	center.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 16); p.add_child(v)
	root.set_meta("id", id)
	overlay_box = root
	ui.add_child(root)
	return v
func _close_overlay() -> void:
	if overlay_box and is_instance_valid(overlay_box): overlay_box.queue_free()
	overlay_box = null
func _overlay_info(icon: String, title: String, text: String) -> void:
	var v := _overlay("info")
	v.add_child(_label(icon, 90, C.text, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label(title, 52, C.text, font_title, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label(text, 26, C.muted, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	var b := _button("Понятно", "", "primary", 100); b.pressed.connect(_close_overlay); v.add_child(b)
func _overlay_pause() -> void:
	var v := _overlay("pause")
	v.add_child(_label("Пауза", 56, C.text, font_title, HORIZONTAL_ALIGNMENT_CENTER))
	var b1 := _button("Продолжить", "", "primary", 100); b1.pressed.connect(_close_overlay); v.add_child(b1)
	var b2 := _button("Новая партия", "те же правила", "normal", 110); b2.pressed.connect(func(): _close_overlay(); _start_match(match_d.input, match_d.level)); v.add_child(b2)
	var b3 := _button("Оформление", "", "normal", 100); b3.pressed.connect(func(): _close_overlay(); _show("look")); v.add_child(b3)
	var b4 := _button("Выйти в меню", "партия сохранится", "normal", 110); b4.pressed.connect(func(): _close_overlay(); _leave()); v.add_child(b4)
func _overlay_exit() -> void:
	var v := _overlay("exit")
	v.add_child(_label("Выйти из партии?", 46, C.text, font_title, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("Партия сохранится, её можно продолжить из главного меню.", 26, C.muted, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	var b1 := _button("Выйти в меню", "", "primary", 100); b1.pressed.connect(func(): _close_overlay(); _leave()); v.add_child(b1)
	var b2 := _button("Остаться", "", "normal", 100); b2.pressed.connect(_close_overlay); v.add_child(b2)

# ------------------------------------------------------------------ the match
func _counts() -> Array:
	var a := []
	for h in match_d.s.hands: a.append(h.size())
	return a
func _has_save() -> bool: return FileAccess.file_exists(SAVE)
func _save_match() -> void:
	if match_d == null: return
	if match_d.s.over:
		if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(SAVE)
		return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_var({"s": match_d.s, "names": match_d.names, "level": match_d.level, "input": match_d.input})

func _start_match(input: Dictionary, level: String) -> void:
	_close_overlay()
	var g := Core.new_game(input, {"rng": rng})
	if g.is_empty(): _toast_global("Эти правила не подходят: проверьте настройки"); return
	var names := ["Вы"]
	var pool := NAMES.duplicate(); pool.shuffle()
	for i in g.s.n - 1: names.append(pool[i])
	match_d = {"s": g.s, "names": names, "level": level, "input": input}
	bot_gen += 1
	sel = -1
	history = ["home"]
	_show("game", true)
	_enter_game_ui()
	var draws: Array = g.ev.filter(func(e): return e.t == "draw")
	deck_n = g.s.stock.size() + draws.size()
	dealing = true; busy = true
	table.new_match(g.s.n, ME, deck_n, Core.visible_trump(g.s))
	var zeros := []
	for p in g.s.n: zeros.append(0)
	table.set_counts(zeros)
	_render_hand([])
	_refresh_ui()
	_snd("shuffle")
	var dealt := []
	for e in draws:
		deck_n -= 1
		deck_lbl.text = str(deck_n)
		table.draw(e.p, e.c if e.p == ME else -1, false, deck_n, _hand_target())
		if e.p == ME:
			await get_tree().create_timer(0.07 / table.speed).timeout
			dealt.append(e.c); _render_hand(dealt)
		else:
			await get_tree().create_timer(0.07 / table.speed).timeout
	await get_tree().create_timer(0.35 / table.speed).timeout
	dealing = false; busy = false
	table.set_counts(_counts())
	_render_hand()
	await _play_events(g.ev.filter(func(e): return e.t != "draw"), Vector2.ZERO)
	_after()

func _resume() -> void:
	var f := FileAccess.open(SAVE, FileAccess.READ)
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY: return
	match_d = d
	bot_gen += 1
	history = ["home"]
	_show("game", true)
	_enter_game_ui()
	deck_n = match_d.s.stock.size()
	table.new_match(match_d.s.n, ME, deck_n, Core.visible_trump(match_d.s))
	table.set_counts(_counts())
	table.set_table(match_d.s.table)
	_render_hand(); _refresh_ui(); _schedule()

func _leave() -> void:
	bot_gen += 1
	_save_match()
	match_d = null; busy = false; sel = -1
	table.highlight([])
	table.new_match(1 + pref.opp, 0, 20, -1)
	history = []
	_show("home", true)

# ------------------------------------------------------------------ game screen
func _build_game() -> void:
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	labels_box = Control.new(); labels_box.set_anchors_preset(Control.PRESET_FULL_RECT); labels_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(labels_box)
	# top bar
	var top := HBoxContainer.new(); top.position = Vector2(20, 30); top.size = Vector2(_vs().x - 40, 90); top.add_theme_constant_override("separation", 12)
	var menu := Button.new(); menu.text = "☰"; menu.custom_minimum_size = Vector2(90, 90); _style_button(menu, "normal", 24); menu.add_theme_font_size_override("font_size", 40)
	menu.add_theme_font_override("font", font_body)
	menu.pressed.connect(_overlay_pause)
	top.add_child(menu)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	var tp := PanelContainer.new(); tp.add_theme_stylebox_override("panel", _sb(C.panel, 24, C.line, 2))
	trump_lbl = _label("", 28, C.text, font_bold); trump_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; trump_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tp.add_child(trump_lbl); top.add_child(tp)
	var dp := PanelContainer.new(); dp.add_theme_stylebox_override("panel", _sb(C.panel, 24, C.line, 2))
	deck_lbl = _label("0", 30, C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER); deck_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; deck_lbl.custom_minimum_size = Vector2(110, 0)
	deck_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	dp.add_child(deck_lbl); top.add_child(dp)
	root.add_child(top)
	# bottom: status, buttons, my hand
	var bottom := VBoxContainer.new(); bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	status_lbl = _label("", 28, C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	status_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); status_lbl.add_theme_constant_override("outline_size", 8)
	bottom.add_child(status_lbl)
	var acts := HBoxContainer.new(); acts.alignment = BoxContainer.ALIGNMENT_CENTER; acts.add_theme_constant_override("separation", 14); acts.custom_minimum_size = Vector2(0, 96)
	acts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_swap = _act_button("Обменять козырь", "normal", func(): _do_mine({"k": "swap"}))
	btn_transfer = _act_button("Перевести", "alt", func():
		for a in _acts_for(sel):
			if a.k == "t": _do_mine(a); return)
	btn_take = _act_button("Беру", "warn", func(): _do_mine({"k": "take"}))
	btn_pass = _act_button("Бито", "primary", func(): _do_mine({"k": "pass"}))
	for b in [btn_swap, btn_transfer, btn_take, btn_pass]: acts.add_child(b)
	bottom.add_child(acts)
	hand_box = Control.new(); hand_box.custom_minimum_size = Vector2(0, _vs().y * 0.22); hand_box.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.add_child(hand_box)
	var pad := Control.new(); pad.custom_minimum_size = Vector2(0, 14); bottom.add_child(pad)
	toast_lbl = _label("", 26, C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var tpnl := PanelContainer.new(); tpnl.add_theme_stylebox_override("panel", _sb(C.panel, 22, C.acc, 2, 8))
	tpnl.add_child(toast_lbl); tpnl.position = Vector2(_vs().x * 0.08, 140); tpnl.custom_minimum_size = Vector2(_vs().x * 0.84, 0); tpnl.visible = false
	tpnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tpnl)
	toast_lbl.set_meta("panel", tpnl)
	hand_cards = {}
func _act_button(text: String, kind: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(220, 92)
	_style_button(b, kind, 28); b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(func(): _snd("click"); cb.call())
	b.visible = false
	return b

func _enter_game_ui() -> void:
	await get_tree().process_frame
	table.set_view_bottom(_hand_inset())
	_build_labels()
	_render_hand(); _refresh_ui()

func _hand_inset() -> float: return _vs().y * 0.21 + 140.0
func _hand_target() -> Vector2:
	var r := hand_box.get_global_rect() if hand_box else Rect2(0, _vs().y * 0.75, _vs().x, _vs().y * 0.25)
	return r.get_center()

func _toast(text: String, secs := 2.2) -> void:
	if toast_lbl == null: return
	toast_lbl.text = text
	var p: Control = toast_lbl.get_meta("panel"); p.visible = true
	var my := Time.get_ticks_msec()
	toast_lbl.set_meta("t", my)
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(toast_lbl) and toast_lbl.get_meta("t") == my: p.visible = false)
func _toast_global(text: String) -> void:
	var l := _label(text, 26, C.text, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", _sb(C.panel, 22, C.acc, 2, 8)); p.add_child(l)
	p.position = Vector2(_vs().x * 0.1, _vs().y - 200); p.custom_minimum_size = Vector2(_vs().x * 0.8, 0)
	ui.add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

# ---------- labels over the heads
func _build_labels() -> void:
	for c in labels_box.get_children(): c.queue_free()
	for p in match_d.s.n:
		if p == ME: continue
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.alignment = BoxContainer.ALIGNMENT_END
		var bubble := PanelContainer.new(); bubble.add_theme_stylebox_override("panel", _sb(Color.WHITE, 22, Color.WHITE, 0, 6))
		var bl := _label("", 26, Color("222222"), font_bold, HORIZONTAL_ALIGNMENT_CENTER); bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		bubble.add_child(bl); bubble.visible = false
		v.add_child(bubble)
		var pnl := PanelContainer.new(); pnl.add_theme_stylebox_override("panel", _sb(C.panel, 30, C.line, 2, 6))
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8)
		var role := _label("", 18, C.acc_text, font_bold); role.autowrap_mode = TextServer.AUTOWRAP_OFF
		var rp := PanelContainer.new(); rp.add_theme_stylebox_override("panel", _sb(C.acc, 16)); rp.add_child(role); rp.visible = false
		var nm := _label(match_d.names[p], 24, C.text, font_bold); nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		var cnt := _label("0", 22, C.acc, font_bold); cnt.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(rp); h.add_child(nm); h.add_child(cnt)
		pnl.add_child(h); v.add_child(pnl)
		v.set_meta("p", p); v.set_meta("bubble", bubble); v.set_meta("bl", bl); v.set_meta("role", role); v.set_meta("rp", rp); v.set_meta("cnt", cnt); v.set_meta("pnl", pnl)
		labels_box.add_child(v)
	_place_labels()
func _place_labels() -> void:
	if labels_box == null or not is_instance_valid(labels_box): return
	for v in labels_box.get_children():
		var pos: Vector2 = table.label_pos(v.get_meta("p"))
		var sz: Vector2 = v.get_combined_minimum_size()
		v.size = sz
		v.position = Vector2(clampf(pos.x - sz.x / 2, 8, _vs().x - sz.x - 8), maxf(130.0, pos.y - sz.y))
func _say(p: int, text: String) -> void:
	if p == ME or labels_box == null: return
	for v in labels_box.get_children():
		if v.get_meta("p") != p: continue
		var b: Control = v.get_meta("bubble")
		v.get_meta("bl").text = text; b.visible = true
		var my := Time.get_ticks_msec(); b.set_meta("t", my)
		get_tree().create_timer(1.6 / table.speed if table.speed > 5 else 1.6).timeout.connect(func():
			if is_instance_valid(b) and b.get_meta("t") == my: b.visible = false; _place_labels())
	_place_labels()
func _update_labels() -> void:
	if match_d == null or labels_box == null or not is_instance_valid(labels_box): return
	var s: Dictionary = match_d.s
	table.set_counts(_counts())
	var pend := Core.pending(s)
	for v in labels_box.get_children():
		var p: int = v.get_meta("p")
		v.get_meta("cnt").text = str(s.hands[p].size())
		var r := "" if s.over else ("ходит" if p == s.att else ("отбивается" if p == s.def else ""))
		v.get_meta("role").text = r
		v.get_meta("rp").visible = r != ""
		var turn: bool = not s.over and pend.has(p) and (s.phase != "throw" or p == s.att)
		v.get_meta("pnl").add_theme_stylebox_override("panel", _sb(C.panel, 30, C.acc if turn else C.line, 4 if turn else 2, 6))
		v.modulate.a = 0.55 if s.out[p] else 1.0
	_place_labels()

# ---------- my hand
func _sort_key(c: int, trump: int) -> int:
	var tr := 1 if Core.suit(c) == trump else 0
	if pref.sort == "rank": return tr * 1000 + Core.rank(c) * 10 + Core.suit(c)
	return tr * 1000 + Core.suit(c) * 20 + Core.rank(c)
var hand_order: Array = []
func _render_hand(cards = null) -> void:
	if hand_box == null or not is_instance_valid(hand_box) or match_d == null: return
	var list: Array = (cards if cards != null else match_d.s.hands[ME]).duplicate()
	var trump: int = match_d.s.trump
	list.sort_custom(func(a, b): return _sort_key(a, trump) < _sort_key(b, trump))
	hand_order = list
	var keep := {}
	for c in list:
		keep[c] = true
		if not hand_cards.has(c):
			var tr := TextureRect.new()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.set_meta("card", c)
			tr.gui_input.connect(_card_input.bind(tr))
			hand_box.add_child(tr)
			hand_cards[c] = tr
		hand_cards[c].texture = load(table.face_path(c))
	for c in hand_cards.keys():
		if not keep.has(c): hand_cards[c].queue_free(); hand_cards.erase(c)
	_layout_hand()
func _layout_hand() -> void:
	if hand_box == null or not is_instance_valid(hand_box): return
	var n := hand_order.size()
	if n == 0: return
	var W := _vs().x; var H := hand_box.custom_minimum_size.y
	var ch := minf(H * 0.92, 330.0); var cw := ch / 1.5
	var arc := minf(24.0, n * 3.0)
	var swing := ch * sin(deg_to_rad(arc / 2.0))
	var max_spread := W - cw - 2.0 * swing - 20.0
	var step := minf(cw * 0.6, max_spread / maxf(n - 1, 1)) if n > 1 else 0.0
	var total := step * (n - 1) + cw
	var x0 := (W - total) / 2.0
	var acts := _my_actions()
	var playable := {}
	for a in acts:
		if a.has("c"): playable[a.c] = true
	var strict := _my_turn_strict()
	for i in n:
		var c: int = hand_order[i]
		var tr: TextureRect = hand_cards[c]
		if tr.get_meta("drag", false): continue
		var tt := 0.0 if n == 1 else float(i) / float(n - 1) - 0.5
		var lift := (1.0 - pow(tt * 2.0, 2.0)) * 22.0
		var up := 44.0 if c == sel else 0.0
		tr.size = Vector2(cw, ch); tr.pivot_offset = Vector2(cw / 2, ch)
		var target := Vector2(x0 + i * step, H - ch - lift - up + 10)
		tr.z_index = i + (100 if c == sel else 0)
		var tw := create_tween().set_parallel()
		tw.tween_property(tr, "position", target, 0.18)
		tw.tween_property(tr, "rotation_degrees", tt * arc, 0.18)
		var dim: bool = pref.hints and not busy and strict and not playable.has(c) and not playable.is_empty()
		tr.modulate = Color(0.62, 0.6, 0.58) if dim else (Color(1.12, 1.08, 0.95) if pref.hints and not busy and playable.has(c) and sel < 0 else Color.WHITE)
var _drag_from := Vector2.ZERO
var _drag_card := -1
func _card_input(e: InputEvent, tr: TextureRect) -> void:
	var c: int = tr.get_meta("card")
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT or e is InputEventScreenTouch:
		var pressed: bool = e.pressed
		if pressed:
			if busy: return
			_drag_from = e.global_position if e is InputEventMouseButton else tr.get_global_transform() * e.position
			_drag_card = c
		elif _drag_card == c:
			_drag_card = -1
			var gp: Vector2 = e.global_position if e is InputEventMouseButton else tr.get_global_transform() * e.position
			if tr.get_meta("drag", false):
				tr.set_meta("drag", false)
				if gp.y < hand_box.get_global_rect().position.y - 10: _drop_card(c, gp)
				else: _layout_hand()
			else:
				_tap_card(c)
	elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and _drag_card == c:
		var gp2: Vector2 = e.global_position if e is InputEventMouseMotion else tr.get_global_transform() * e.position
		if not tr.get_meta("drag", false) and gp2.distance_to(_drag_from) > 24 and not _acts_for(c).is_empty():
			tr.set_meta("drag", true); tr.z_index = 200; tr.rotation = 0
		if tr.get_meta("drag", false):
			tr.global_position = gp2 - tr.size * Vector2(0.5, 0.6)

func _my_actions() -> Array:
	if match_d == null or match_d.s.over or dealing: return []
	return Core.actions(match_d.s, ME)
func _acts_for(c: int) -> Array:
	return _my_actions().filter(func(a): return a.get("c", -99) == c)
func _my_turn_strict() -> bool:
	if match_d == null: return false
	var s: Dictionary = match_d.s
	return (s.phase == "lead" and s.att == ME) or (s.phase == "defend" and s.def == ME)
func _tap_card(c: int) -> void:
	if busy or match_d == null: return
	var acts := _acts_for(c)
	if acts.is_empty():
		if sel >= 0: sel = -1; table.highlight([]); _refresh_ui()
		else: _nudge()
		return
	if sel == c: sel = -1; table.highlight([]); _refresh_ui(); return
	var beats := acts.filter(func(a): return a.k == "b")
	var tr := acts.filter(func(a): return a.k == "t")
	var att := acts.filter(func(a): return a.k == "a")
	if att.size() and beats.is_empty() and tr.is_empty(): _do_mine(att[0]); return
	if beats.size() == 1 and tr.is_empty() and att.is_empty(): _do_mine(beats[0]); return
	if tr.size() and beats.is_empty() and att.is_empty(): _do_mine(tr[0]); return
	sel = c
	table.highlight(beats.map(func(a): return a.i))
	_refresh_ui()
func _drop_card(c: int, gp: Vector2) -> void:
	var acts := _acts_for(c)
	var slot: int = table.pick_slot(gp)
	for a in acts:
		if a.k == "b" and a.i == slot: _do_mine(a); return
	for a in acts:
		if a.k == "a": _do_mine(a); return
	var bs := acts.filter(func(a): return a.k == "b")
	var t := acts.filter(func(a): return a.k == "t")
	if bs.size() == 1 and t.is_empty(): _do_mine(bs[0]); return
	if t.size() and bs.is_empty(): _do_mine(t[0]); return
	sel = c; table.highlight(bs.map(func(a): return a.i)); _refresh_ui()
func _nudge() -> void:
	var s: Dictionary = match_d.s
	if s.phase == "defend" and s.def == ME: _toast("Эта карта не бьёт. Можно взять — «Беру»", 1.6)
	elif _my_actions().is_empty(): _toast("Сейчас ход другого игрока", 1.3)
	elif s.phase != "lead": _toast("Подкинуть можно только карту того же достоинства, что на столе", 1.8)

func _unhandled_input(e: InputEvent) -> void:
	if screen != "game" or busy or sel < 0: return
	var released: bool = (e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and not e.pressed)
	if not released: return
	var slot: int = table.pick_slot(e.position)
	for a in _acts_for(sel):
		if a.k == "b" and a.i == slot: _do_mine(a); return

# ---------- acting
func _card_screen(c: int) -> Vector2:
	if hand_cards.has(c): return hand_cards[c].get_global_rect().get_center()
	return _hand_target()
func _do_mine(act: Dictionary) -> void:
	if busy or match_d == null: return
	var from := _card_screen(act.c) if act.has("c") else Vector2.ZERO
	sel = -1; table.highlight([])
	_perform(ME, act, from)
func _perform(seat: int, act: Dictionary, from: Vector2) -> void:
	var r := Core.apply(match_d.s, seat, act)
	if not r.ok: _toast(r.error, 1.5); _refresh_ui(); return
	bot_gen += 1
	busy = true
	_refresh_ui()
	await _play_events(r.ev, from)
	busy = false
	_after()
func _after() -> void:
	if match_d == null: return
	_save_match()
	_refresh_ui()
	if match_d.s.over: _show_end(); return
	_schedule()
func _schedule() -> void:
	if match_d == null or match_d.s.over or busy: return
	var s: Dictionary = match_d.s
	var pend := Core.pending(s).filter(func(p): return p != ME)
	if pend.is_empty(): return
	var p: int = pend[0]
	if s.phase == "throw":
		for i in s.n:
			var q: int = (s.att + i) % s.n
			if pend.has(q): p = q; break
	var mine_too := not Core.actions(s, ME).is_empty()
	var think := 0.01 if table.speed > 5 else (1.3 if mine_too else 0.65) + rng.randf() * 0.45
	bot_gen += 1
	var my := bot_gen
	await get_tree().create_timer(think).timeout
	if my != bot_gen or match_d == null or busy: return
	var act = Core.choose(match_d.s, p, match_d.level, rng)
	if act == null: return
	_perform(p, act, Vector2.ZERO)

func _play_events(ev: Array, from: Vector2) -> void:
	for e in ev:
		if match_d == null: return
		await _play_event(e, from)
func _play_event(e: Dictionary, from: Vector2) -> void:
	var s: Dictionary = match_d.s
	match e.t:
		"attack", "transfer", "beat":
			var kind := "a" if e.t == "attack" else ("t" if e.t == "transfer" else "b")
			if e.t == "transfer": _say(e.p, "Перевожу!")
			_snd("slap")
			if e.p == ME:
				var pos := from if from != Vector2.ZERO else _card_screen(e.c)
				if hand_cards.has(e.c): hand_cards[e.c].visible = false
				hand_order.erase(e.c)
				_layout_hand()
				await table.i_play(e.c, kind, e.i, pos)
				_render_hand()
			else:
				await table.opponent_plays(e.p, e.c, kind, e.i)
				_update_labels()
		"take":
			_say(e.p, "Беру"); await table.nod(e.p)
		"pass":
			_say(e.p, "Пас" if e.taking else "Бито"); await get_tree().create_timer(0.25 / table.speed).timeout
		"collect":
			_snd("take")
			await table.take(e.p, _hand_target())
			if e.p == ME: _render_hand()
			_update_labels()
		"discard":
			_snd("take"); await table.discard()
		"draw":
			deck_n = maxi(0, deck_n - 1)
			deck_lbl.text = str(deck_n)
			var last: bool = e.pub and e.c == s.trumpCard
			await table.draw(e.p, e.c if e.p == ME else -1, last, deck_n, _hand_target())
			if e.p == ME: _render_hand()
			_update_labels()
		"turn":
			_update_labels(); await get_tree().create_timer(0.2 / table.speed).timeout
		"swap":
			_say(e.p, "Меняю козырь")
			table.set_deck(deck_n, e.give)
			if e.p == ME: _render_hand()
			_toast(("Вы обменяли" if e.p == ME else match_d.names[e.p] + " обменял(а)") + " младший козырь")
			await get_tree().create_timer(0.6 / table.speed).timeout
		"reveal":
			_toast("Открылась скрытая карта: козырь теперь " + Core.SUIT_NAME[e.trump] if e.changed else "Открылась скрытая карта: козырь прежний", 2.6)
			table.set_deck(deck_n, Core.visible_trump(s))
			_refresh_trump()
			await get_tree().create_timer(0.9 / table.speed).timeout
		"over":
			await get_tree().create_timer(0.5 / table.speed).timeout

func _refresh_trump() -> void:
	if match_d == null or trump_lbl == null: return
	var t: int = match_d.s.trump
	trump_lbl.text = "Козырь  " + Core.SUIT_SYMBOL[t] + " " + Core.SUIT_NAME[t]
	trump_lbl.add_theme_color_override("font_color", Color("ff5a4a") if t == 1 or t == 2 else C.text)

func _refresh_ui() -> void:
	if match_d == null or status_lbl == null or not is_instance_valid(status_lbl): return
	var s: Dictionary = match_d.s
	_refresh_trump()
	deck_lbl.text = "колода " + str(deck_n)
	_update_labels()
	var acts := [] if busy else _my_actions()
	var has := func(k): return acts.any(func(a): return a.k == k)
	btn_take.visible = has.call("take")
	btn_pass.visible = has.call("pass")
	btn_pass.text = "Пас" if s.taking else "Бито"
	btn_swap.visible = has.call("swap")
	var sel_t := sel >= 0 and _acts_for(sel).any(func(a): return a.k == "t")
	btn_transfer.visible = sel_t
	var st := ""; var mine := false
	var n: Array = match_d.names
	if s.over: st = ""
	elif dealing: st = "Раздача…"
	elif sel >= 0:
		st = "Нажмите карту на столе или «Перевести»" if sel_t else "Нажмите карту на столе, которую бьёте"; mine = true
	elif s.phase == "lead":
		mine = s.att == ME; st = "Ваш ход: положите карту" if mine else "Ходит " + n[s.att] + "…"
	elif s.phase == "defend":
		if s.def == ME: mine = true; st = "Отбивайтесь" + (", переводите" if s.cfg.transfer.enabled else "") + " или берите"
		else: st = "Отбивается " + n[s.def] + "…"
	else:
		if has.call("pass"): mine = true; st = (n[s.def] + " берёт. Подкиньте или «Пас»") if s.taking else "Всё побито. Подкиньте или «Бито»"
		elif s.def == ME and s.taking: st = "Вы берёте. Ждём, подкинут ли ещё…"
		else: st = (n[s.def] + " берёт…") if s.taking else "Подкидывают…"
	status_lbl.text = st
	status_lbl.add_theme_color_override("font_color", C.acc if mine else C.text)
	_layout_hand()

func _show_end() -> void:
	var s: Dictionary = match_d.s
	var r: Dictionary = s.result
	var n: Array = match_d.names
	var icon := "🏆"; var title := "Победа!"; var text := ""
	if r.fool == ME: icon = "🃏"; title = "Вы дурак!"; text = "В этот раз карты остались у вас. Отыграетесь?"
	elif r.fool < 0: icon = "🤝"; title = "Ничья"; text = "Карты ходили по кругу слишком долго." if r.reason == "stalemate" else "Последние игроки вышли одновременно."
	else: text = n[r.fool] + " остаётся в дураках."
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(SAVE)
	await get_tree().create_timer(0.5 / table.speed).timeout
	var v := _overlay("end")
	v.add_child(_label(icon, 96, C.text, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label(title, 60, C.acc if r.fool != ME else Color("ff6f5e"), font_title, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label(text, 26, C.muted, font_body, HORIZONTAL_ALIGNMENT_CENTER))
	var place := 1
	for grp in r.places:
		for p in grp:
			var row := HBoxContainer.new()
			var a := _label(n[p], 28, C.acc if p == ME else C.text, font_bold); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := _label("дурак" if p == r.fool else "%d место" % place, 26, Color("ff6f5e") if p == r.fool else C.muted, font_body, HORIZONTAL_ALIGNMENT_RIGHT)
			row.add_child(a); row.add_child(b); v.add_child(row)
		place += grp.size()
	var b1 := _button("Ещё раз", "", "primary", 100); b1.pressed.connect(func(): _start_match(match_d.input, match_d.level)); v.add_child(b1)
	var b2 := _button("В меню", "", "normal", 100); b2.pressed.connect(func(): _close_overlay(); _leave()); v.add_child(b2)

# ------------------------------------------------------------------ sound (made on the fly)
var _players: Array = []
func _snd(kind: String) -> void:
	if not pref.sound or table.speed > 5: return
	var p: AudioStreamPlayer = null
	for q in _players:
		if not q.playing: p = q; break
	if p == null:
		if _players.size() >= 6: return
		p = AudioStreamPlayer.new(); add_child(p); _players.append(p)
	p.stream = _noise(kind)
	p.volume_db = -6.0 if kind == "slap" else -12.0
	p.play()
var _snd_cache := {}
func _noise(kind: String) -> AudioStreamWAV:
	if _snd_cache.has(kind): return _snd_cache[kind]
	var rate := 22050
	var secs := 0.5 if kind == "shuffle" else (0.05 if kind == "click" else 0.1)
	var n := int(rate * secs)
	var data := PackedByteArray(); data.resize(n * 2)
	var r := RandomNumberGenerator.new(); r.seed = 3
	var prev := 0.0
	var smooth := 0.35 if kind == "slap" else (0.6 if kind == "take" else 0.2)
	for i in n:
		var k := float(i) / n
		var env := absf(sin(k * 40.0)) * (1.0 - k) if kind == "shuffle" else pow(1.0 - k, 4.0)
		var x := r.randf_range(-1, 1)
		prev = prev * smooth + x * (1.0 - smooth)
		var v := int(clampf(prev * env * 0.9, -1, 1) * 32000)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = rate; w.data = data
	_snd_cache[kind] = w
	return w

func _process(_d: float) -> void:
	if screen == "game" and match_d and Engine.get_process_frames() % 6 == 0: _place_labels()
