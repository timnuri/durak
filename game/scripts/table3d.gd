extends Node3D
## The 3D table: a dark room, a lamp over an oval or rectangular table, the opponents sitting evenly around it.
## The human player is the camera; his own cards are 2D at the bottom of the screen (main.gd).
## Every move is an async function; the game awaits them one after another.
## Nothing gives a hand away: an opponent takes a random card from his fan, new cards go into a random place,
## and the deck is dealt from without a hand.

const PersonScript := preload("res://scripts/person.gd")
const TABLE_Y := 0.74
const CW := 0.29
const CH := 0.435
const FAN_SCALE := 0.62
var RX := 0.85
var RZ := 1.1

const THEMES := {
	"cabinet": {"name": "Кабинет", "bg": Color("1a0f08"), "surface": "wood", "wood": Color("6a3a1e"), "rim": Color("3e1f0e"), "felt": Color("6a3a1e"),
		"inlay": Color("d9a54a"), "lamp": Color("ffcf95"), "lamp_e": 9.0, "amb": Color("5a3a24"), "amb_e": 0.35, "body": Color("17110d"), "rim_tint": 0.5,
		"bokeh": [Color("ffb45a"), Color("ffd9a0")], "exposure": 1.0, "floor": Color("1e130c"), "wall": Color("24170f")},
	"casino": {"name": "Казино", "bg": Color("06140f"), "surface": "felt", "wood": Color("5a2c14"), "rim": Color("3a1a0a"), "felt": Color("0f6a38"),
		"inlay": Color("f0c75a"), "lamp": Color("fff0d8"), "lamp_e": 9.5, "amb": Color("3a5a4a"), "amb_e": 0.4, "body": Color("101512"), "rim_tint": 0.5,
		"bokeh": [Color("ffd77a"), Color("fff0c0")], "exposure": 1.05, "floor": Color("0d1a14"), "wall": Color("0f2a20")},
	"neon": {"name": "Неон", "bg": Color("07031a"), "surface": "felt", "wood": Color("1a1430"), "rim": Color("120c26"), "felt": Color("1c1f5e"),
		"inlay": Color("3ff0ff"), "lamp": Color("d9c8ff"), "lamp_e": 8.0, "amb": Color("40308a"), "amb_e": 0.45, "body": Color("0d0b1e"), "rim_tint": 0.7,
		"bokeh": [Color("ff3fd0"), Color("3fe0ff")], "exposure": 1.05, "floor": Color("0a0620"), "wall": Color("120a30"), "neon": true},
	"day": {"name": "Светлая", "bg": Color("e8d6bc"), "surface": "wood", "wood": Color("d8b080"), "rim": Color("a87444"), "felt": Color("d8b080"),
		"inlay": Color("8a5a2a"), "lamp": Color("fffaf0"), "lamp_e": 5.0, "amb": Color("f0e0c8"), "amb_e": 0.9, "body": Color("2a2420"), "rim_tint": 0.3,
		"bokeh": [Color("ffffff"), Color("fff0d0")], "exposure": 1.0, "floor": Color("b89a78"), "wall": Color("e8d8c0")},
}
const BACKS := {"blue": "Синяя", "red": "Красная", "black": "Чёрная", "gold": "Золотая", "green": "Зелёная"}

var theme: Dictionary = THEMES.cabinet
var shape := "round"
var face := "vt"
var back := "blue"
var speed := 1.0

var cam: Camera3D
var env: WorldEnvironment
var lamp: SpotLight3D
var table_root: Node3D
var room_root: Node3D
var people: Array = []          # by seat; null for me
var seats := 0
var me := 0
var deck_node: MeshInstance3D
var trump_node: Node3D
var discard_root: Node3D
var pairs: Array = []           # [{a: Node3D, d: Node3D}]
var discard_n := 0
var view_bottom := 0.0
var glows: Array = []
var _tex := {}
var _models: Array = []
var _sil_mat: StandardMaterial3D

# ------------------------------------------------------------------ setup
func _ready() -> void:
	cam = Camera3D.new(); cam.fov = 46.0; cam.near = 0.05; cam.far = 40.0
	add_child(cam)
	env = WorldEnvironment.new(); env.environment = Environment.new(); add_child(env)
	room_root = Node3D.new(); add_child(room_root)
	table_root = Node3D.new(); add_child(table_root)
	discard_root = Node3D.new(); add_child(discard_root)
	_models = [load("res://models/Xbot.glb"), load("res://models/Michelle.glb")]
	get_viewport().size_changed.connect(frame_camera)

func set_look(look: Dictionary) -> void:
	theme = THEMES.get(look.get("theme", "cabinet"), THEMES.cabinet)
	shape = look.get("shape", shape)
	face = look.get("face", face)
	back = look.get("back", back)
	RX = 0.85 if shape == "round" else 0.8
	RZ = 1.1 if shape == "round" else 1.02
	_build_env(); _build_room(); _build_table()
	for n in _all_cards(): _refresh_card(n)
	if seats > 0: _place_people(seats, me)
	if deck_node or trump_node: set_deck(_deck_n, trump_node.get_meta("card") if trump_node else -1)

func _all_cards() -> Array:
	var out := []
	for p in pairs:
		if p.a: out.append(p.a)
		if p.d: out.append(p.d)
	for c in discard_root.get_children(): out.append(c)
	if trump_node: out.append(trump_node)
	for p in people:
		if p: out.append_array(p.cards)
	return out

func _build_env() -> void:
	var e := env.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = theme.bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = theme.amb
	e.ambient_light_energy = theme.amb_e
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = theme.exposure
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_light_color = theme.bg
	e.fog_density = 0.06 if theme.name != "Светлая" else 0.03
	e.fog_sky_affect = 0.0
	if lamp: lamp.queue_free()
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 2.6, 0.15)
	lamp.light_color = theme.lamp
	lamp.light_energy = theme.lamp_e
	lamp.spot_range = 5.0
	lamp.spot_angle = 48.0
	lamp.spot_angle_attenuation = 1.6
	lamp.shadow_enabled = true
	lamp.shadow_blur = 2.0
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	add_child(lamp)

func _mat(color: Color, rough := 0.6, tex: String = "", emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if tex != "": m.albedo_texture = load(tex)
	if emit > 0.0:
		m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = emit
	return m

func _build_room() -> void:
	for c in room_root.get_children(): c.queue_free()
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(16, 16); floor.mesh = pm
	var fm := _mat(theme.floor, 0.9); fm.disable_receive_shadows = true
	floor.material_override = fm
	room_root.add_child(floor)
	# walls far behind, in the dark
	for a in [0.0, 90.0, -90.0, 180.0]:
		var w := MeshInstance3D.new(); var q := PlaneMesh.new(); q.size = Vector2(16, 6); q.orientation = PlaneMesh.FACE_Z
		w.mesh = q; w.material_override = _mat(theme.wall, 0.95)
		w.rotation_degrees.y = a; w.position = Vector3(0, 3, 0) + Vector3(0, 0, -6).rotated(Vector3.UP, deg_to_rad(a))
		room_root.add_child(w)
	# lamps in the room, out of focus: small bright spheres the glow turns into soft lights
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for i in 9:
		var s := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.06 + rng.randf() * 0.08; sm.height = sm.radius * 2
		s.mesh = sm
		var col: Color = theme.bokeh[i % theme.bokeh.size()]
		var mm := _mat(col, 1.0, "", 3.0 + rng.randf() * 3.0); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.material_override = mm
		var ang := rng.randf_range(-2.4, 2.4)
		s.position = Vector3(sin(ang) * 5.2, 1.3 + rng.randf() * 1.6, -absf(cos(ang)) * 5.2 - 0.4)
		room_root.add_child(s)
		var ol := OmniLight3D.new(); ol.light_color = col; ol.light_energy = 0.6; ol.omni_range = 2.5; ol.position = s.position
		room_root.add_child(ol)

func _surface_mat() -> StandardMaterial3D:
	if theme.surface == "felt":
		var m := _mat(theme.felt, 0.95, "res://art/felt.webp")
		m.uv1_scale = Vector3(3, 3, 3)
		return m
	var w := _mat(theme.wood, 0.35, "res://art/wood.webp")
	w.clearcoat_enabled = true; w.clearcoat = 0.6; w.clearcoat_roughness = 0.2
	return w
func _rim_mat() -> StandardMaterial3D:
	var m := _mat(theme.rim, 0.32, "res://art/wood.webp")
	if theme.get("neon", false):
		m = _mat(Color("0c0a1c"), 0.3)
		m.emission_enabled = true; m.emission = theme.inlay; m.emission_energy_multiplier = 0.8
	return m

func _build_table() -> void:
	for c in table_root.get_children(): c.queue_free()
	var top := MeshInstance3D.new()
	var surf := _surface_mat()
	if shape == "round":
		var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 0.97; cm.height = 0.06; cm.radial_segments = 96
		top.mesh = cm; top.scale = Vector3(RX, 1, RZ); top.position.y = TABLE_Y - 0.03
		var edge := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.96; tm.outer_radius = 1.04; tm.rings = 96
		edge.mesh = tm; edge.scale = Vector3(RX, 0.9, RZ); edge.position.y = TABLE_Y - 0.012; edge.material_override = _rim_mat()
		table_root.add_child(edge)
		var ring := MeshInstance3D.new(); var tr := TorusMesh.new(); tr.inner_radius = 0.795; tr.outer_radius = 0.805; tr.rings = 96
		ring.mesh = tr; ring.scale = Vector3(RX, 0.05, RZ); ring.position.y = TABLE_Y + 0.0005
		var im := _mat(theme.inlay.darkened(0.25), 0.4, "", 0.6 if theme.get("neon", false) else 0.0); ring.material_override = im
		table_root.add_child(ring)
	else:
		var bm := BoxMesh.new(); bm.size = Vector3(2 * RX, 0.06, 2 * RZ)
		top.mesh = bm; top.position.y = TABLE_Y - 0.03
		for k in 4:
			var bar := MeshInstance3D.new(); var cy := CapsuleMesh.new(); cy.radius = 0.045
			var along_x := k < 2
			cy.height = (2 * RX if along_x else 2 * RZ) + 0.09
			bar.mesh = cy; bar.material_override = _rim_mat()
			bar.rotation_degrees = Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)
			bar.position = Vector3(0 if along_x else (RX if k == 2 else -RX), TABLE_Y - 0.01, (RZ if k == 0 else -RZ) if along_x else 0.0)
			table_root.add_child(bar)
	top.material_override = surf
	table_root.add_child(top)
	var leg := MeshInstance3D.new(); var lm := CylinderMesh.new(); lm.top_radius = 0.12; lm.bottom_radius = 0.3; lm.height = TABLE_Y - 0.05
	leg.mesh = lm; leg.position.y = (TABLE_Y - 0.05) / 2; leg.material_override = _mat(theme.rim, 0.5)
	table_root.add_child(leg)

# ------------------------------------------------------------------ people
func _sil_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = theme.body
	m.roughness = 0.75
	m.rim_enabled = true; m.rim = theme.rim_tint; m.rim_tint = 0.6
	return m

func seat_point(k: int, out := 0.36) -> Vector3:
	var ang := PI / 2 + TAU * float((k - me + seats) % seats) / float(seats)   # me at the bottom, clockwise
	var x := cos(ang); var z := sin(ang)
	if shape == "square":
		var m := maxf(absf(x), absf(z))
		var sq := minf(1.0 / m, 1.18)
		x *= sq; z *= sq
	return Vector3(x * (RX + out), 0, z * (RZ + out))

func _place_people(n: int, my_seat: int) -> void:
	for p in people:
		if p: p.queue_free()
	people = []
	seats = n; me = my_seat
	_sil_mat = _sil_material()
	for k in n:
		if k == me: people.append(null); continue
		var p := Node3D.new()
		p.set_script(PersonScript)
		add_child(p)
		var at := seat_point(k)
		p.position = at
		p.look_at(Vector3(0, 0, 0), Vector3.UP)
		p.rotate_object_local(Vector3.UP, PI)               # the person's +Z points at the table
		p.look_at_point = Vector3(0, TABLE_Y, 0)
		p.setup(_models[k % 2], _sil_mat, 1.0 if k % 2 == 0 else 1.06)
		var rt: Array = p.rest_targets()
		p.left_target = rt[0]; p.right_target = rt[1]
		people.append(p)
		_set_fan(p, 0)
	frame_camera()

# ------------------------------------------------------------------ cards
func _texture(path: String) -> Texture2D:
	if not _tex.has(path): _tex[path] = load(path)
	return _tex[path]
func face_path(card: int) -> String: return "res://cards/%s/%d-%d.webp" % [face, Core.suit(card), Core.value(card)]
func back_path() -> String: return "res://cards/backs/%s.webp" % back

func _card_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## a card: front faces +Z of the node, back faces -Z
func make_card(card: int, small := false) -> Node3D:
	var n := Node3D.new()
	var q := QuadMesh.new(); q.size = Vector2(CW, CH) * (FAN_SCALE if small else 1.0)
	var f := MeshInstance3D.new(); f.mesh = q; f.name = "F"
	var b := MeshInstance3D.new(); b.mesh = q; b.name = "B"; b.rotation.y = PI
	n.add_child(f); n.add_child(b)
	n.set_meta("card", card)
	_refresh_card(n)
	return n
func _refresh_card(n: Node3D) -> void:
	var card: int = n.get_meta("card")
	(n.get_node("B") as MeshInstance3D).material_override = _card_mat(_texture(back_path()))
	var f := n.get_node("F") as MeshInstance3D
	if card >= 0: f.material_override = _card_mat(_texture(face_path(card))); f.visible = true
	else: f.visible = false
func set_face(n: Node3D, card: int) -> void:
	n.set_meta("card", card); _refresh_card(n)

func flat_basis(face_up: bool, yaw := 0.0) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2 if face_up else PI / 2)

func _set_fan(p, n: int) -> void:
	while p.cards.size() > n: p.cards.pop_back().queue_free()
	while p.cards.size() < n:
		var c := make_card(-1, true); p.fan.add_child(c); p.cards.append(c)
	_fan_layout(p, false)
func _fan_layout(p, animate: bool) -> void:
	var home: Transform3D = p.fan_home()
	p.fan.global_transform = home
	var n: int = p.cards.size()
	var spread := minf(1.3, 0.12 * maxf(n - 1, 0))
	for k in n:
		var c: Node3D = p.cards[k]
		var tt := 0.0 if n == 1 else float(k) / float(n - 1) - 0.5
		var ang := -tt * spread
		var hh := CH * FAN_SCALE
		var pos := Vector3(sin(-ang) * hh * 0.42, cos(ang) * hh * 0.42 - hh * 0.2, -k * 0.002)
		var bas := Basis(Vector3.UP, PI) * Basis(Vector3.BACK, ang)       # back faces the table
		if animate:
			var tw := create_tween().set_parallel()
			tw.tween_property(c, "position", pos, 0.2 / speed)
			tw.tween_property(c, "quaternion", bas.get_rotation_quaternion(), 0.2 / speed)
		else:
			c.position = pos; c.basis = bas

func set_counts(counts: Array) -> void:
	for k in counts.size():
		if k < people.size() and people[k]: _set_fan(people[k], counts[k])

var _deck_n := 0
func set_deck(n: int, trump_card: int) -> void:
	_deck_n = n
	if deck_node: deck_node.queue_free(); deck_node = null
	if trump_node and (trump_card < 0 or trump_node.get_meta("card") != trump_card): trump_node.queue_free(); trump_node = null
	var dp := deck_pos()
	if trump_card >= 0 and trump_node == null:
		trump_node = make_card(trump_card); add_child(trump_node)
		trump_node.position = dp + Vector3(0.05, 0.003, 0.0)
		trump_node.basis = flat_basis(true, PI / 2 - 0.05)
	var stack := n - (1 if trump_card >= 0 else 0)
	if stack > 0:
		deck_node = MeshInstance3D.new()
		var bm := BoxMesh.new(); var th := maxf(0.004, stack * 0.0016); bm.size = Vector3(CW, th, CH)
		deck_node.mesh = bm
		var edge := _mat(Color("e9e1cf"), 0.8)
		deck_node.material_override = edge
		var topq := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(CW, CH); topq.mesh = q
		topq.material_override = _card_mat(_texture(back_path()))
		topq.basis = flat_basis(false); topq.position.y = th / 2 + 0.0005
		topq.rotation = Vector3(-PI / 2, 0, PI)
		deck_node.add_child(topq)
		deck_node.position = dp + Vector3(0, 0.006 + th / 2, 0)
		deck_node.rotation.y = 0.08
		add_child(deck_node)

func deck_pos() -> Vector3: return Vector3(-RX * 0.62, TABLE_Y, -RZ * 0.6)
func disc_pos() -> Vector3: return Vector3(RX * 0.64, TABLE_Y, -RZ * 0.62)

func slot_pos(i: int, n: int) -> Vector3:
	var cols := n if n <= 3 else (3 if n <= 6 else 4)
	var rows := int(ceil(float(n) / cols))
	var r := i / cols; var c := i % cols
	var in_row := n - r * cols if r == rows - 1 else cols
	var dx := CW * 1.32; var dz := CH * 1.18
	return Vector3((c - (in_row - 1) / 2.0) * dx, TABLE_Y + 0.002, (r - (rows - 1) / 2.0) * dz + 0.1)
func _target(kind: String, idx: int, n: int) -> Transform3D:
	var p := slot_pos(idx, n)
	if kind == "b": return Transform3D(flat_basis(true, 0.2), p + Vector3(0.025, 0.004, 0.045))
	return Transform3D(flat_basis(true, -0.04), p)
func _relayout(animate: bool) -> void:
	var n := pairs.size()
	for i in n:
		var pr: Dictionary = pairs[i]
		for k in ["a", "d"]:
			var node: Node3D = pr[k]
			if node == null or node.get_meta("flying", false): continue
			var tg := _target("b" if k == "d" else "a", i, n)
			tg.basis = tg.basis * Basis(Vector3.BACK, node.get_meta("jit", 0.0))
			if animate:
				var tw := create_tween().set_parallel()
				tw.tween_property(node, "global_position", tg.origin, 0.22 / speed)
				tw.tween_property(node, "quaternion", tg.basis.get_rotation_quaternion(), 0.22 / speed)
			else:
				node.global_transform = tg

## move a node along an arc (with a lift) to a transform; scale too
func _fly(node: Node3D, to: Transform3D, secs: float, lift := 0.12, to_scale := Vector3.ONE) -> void:
	var from := node.global_transform
	var s0 := node.scale
	var qa := from.basis.orthonormalized().get_rotation_quaternion()
	var qb := to.basis.orthonormalized().get_rotation_quaternion()
	var tw := create_tween()
	tw.tween_method(func(e: float):
		var k := ease(e, -2.0)
		var p := from.origin.lerp(to.origin, k) + Vector3.UP * sin(PI * k) * lift
		node.global_transform = Transform3D(Basis(qa.slerp(qb, minf(1.0, k * 1.2))).scaled(s0.lerp(to_scale, k)), p), 0.0, 1.0, secs / speed)
	await tw.finished

func _place(node: Node3D, kind: String, idx: int) -> void:
	node.set_meta("jit", randf_range(-0.05, 0.05))
	if kind == "b": pairs[idx].d = node
	else: pairs[idx].a = node
	_relayout(true)

func opponent_plays(seat: int, card: int, kind: String, idx: int) -> void:
	if kind != "b": pairs.append({"a": null, "d": null}); _relayout(true)
	var tg := _target(kind, idx, pairs.size())
	var p = people[seat]
	var node: Node3D
	if p == null:
		node = make_card(card); add_child(node); node.global_position = cam.global_position
		await _fly(node, tg, 0.35)
	else:
		var pick: Node3D = p.cards[randi() % p.cards.size()] if p.cards.size() > 0 else null   # any card: all backs look alike
		p.right_busy = true
		var from: Vector3 = p.right_target
		var grip: Vector3 = pick.global_position if pick else from
		var tw := create_tween()
		tw.tween_method(func(e): p.right_target = from.lerp(grip, e), 0.0, 1.0, 0.18 / speed)
		await tw.finished
		if pick:
			p.cards.erase(pick)
			var gt := pick.global_transform
			pick.get_parent().remove_child(pick); add_child(pick); pick.global_transform = gt
			node = pick
		else:
			node = make_card(-1, true); add_child(node); node.global_position = grip
		_fan_layout(p, true)
		set_face(node, card)
		var q := QuadMesh.new(); q.size = Vector2(CW, CH)
		for m in [node.get_node("F"), node.get_node("B")]: (m as MeshInstance3D).mesh = q
		node.scale = Vector3.ONE * FAN_SCALE
		node.set_meta("flying", true)
		var hand_follow := func(_e): p.right_target = node.global_position + Vector3.UP * 0.03
		var lean0: float = p.lean
		var tw2 := create_tween().set_parallel()
		tw2.tween_method(func(e: float): p.lean = lean0 + sin(PI * minf(1.0, e * 1.2)) * 0.3; hand_follow.call(e), 0.0, 1.0, 0.45 / speed)
		_fly(node, tg, 0.45)
		await tw2.finished
		node.set_meta("flying", false)
		node.global_transform = tg
		var back_from: Vector3 = p.right_target
		var rest: Vector3 = p.rest_targets()[1]
		var tw3 := create_tween()
		tw3.tween_method(func(e): p.right_target = back_from.lerp(rest, e); p.lean = lean0 * e, 0.0, 1.0, 0.3 / speed)
		tw3.finished.connect(func(): p.right_busy = false)
	_place(node, kind, idx)

func i_play(card: int, kind: String, idx: int, screen: Vector2) -> void:
	if kind != "b": pairs.append({"a": null, "d": null}); _relayout(true)
	var tg := _target(kind, idx, pairs.size())
	var node := make_card(card); add_child(node)
	node.global_transform = Transform3D(cam.global_basis, cam.project_position(screen, 0.6))
	node.set_meta("flying", true)
	await _fly(node, tg, 0.34, 0.05)
	node.set_meta("flying", false)
	_place(node, kind, idx)

func _table_cards() -> Array:
	var out := []
	for p in pairs:
		if p.a: out.append(p.a)
		if p.d: out.append(p.d)
	return out

func discard() -> void:
	var cards := _table_cards(); pairs = []
	var dp := disc_pos()
	var k := 0
	for n in cards:
		var to := Transform3D(flat_basis(false, randf_range(-0.5, 0.5)), dp + Vector3(randf_range(-0.03, 0.03), 0.004 + (discard_n + k) * 0.0012, randf_range(-0.03, 0.03)))
		_fly(n, to, 0.36 + k * 0.03, 0.08)
		k += 1
	discard_n += cards.size()
	await get_tree().create_timer((0.4 + k * 0.03) / speed).timeout
	for n in cards:
		var gt: Transform3D = n.global_transform
		remove_child(n); discard_root.add_child(n); n.global_transform = gt
	while discard_root.get_child_count() > 14:
		var o := discard_root.get_child(0); discard_root.remove_child(o); o.queue_free()

func take(seat: int, screen: Vector2) -> void:
	var cards := _table_cards(); pairs = []
	var p = people[seat]
	var k := 0
	if p:
		p.right_busy = true
		var from: Vector3 = p.right_target
		var mid := Vector3(0, TABLE_Y + 0.05, 0.05)
		var tw := create_tween()
		tw.tween_method(func(e): p.right_target = from.lerp(mid, e); p.lean = 0.3 * e, 0.0, 1.0, 0.25 / speed)
		await tw.finished
		var home: Transform3D = p.fan_home()
		for n in cards:
			_fly(n, Transform3D(home.basis * Basis(Vector3.UP, PI), home.origin), 0.38 + k * 0.03, 0.1, Vector3.ONE * FAN_SCALE)
			k += 1
		var tw2 := create_tween()
		tw2.tween_method(func(e): p.right_target = mid.lerp(p.rest_targets()[1], e); p.lean = 0.3 * (1.0 - e), 0.0, 1.0, 0.42 / speed)
		tw2.finished.connect(func(): p.right_busy = false)
	else:
		var to := Transform3D(cam.global_basis, cam.project_position(screen, 0.6))
		for n in cards:
			_fly(n, to, 0.34 + k * 0.03, 0.05)
			k += 1
	await get_tree().create_timer((0.42 + k * 0.03) / speed).timeout
	for n in cards: n.queue_free()

func draw(seat: int, card: int, is_last: bool, deck_left: int, screen: Vector2) -> void:
	var dp := deck_pos()
	var node: Node3D
	if is_last and trump_node:
		node = trump_node; trump_node = null
	else:
		node = make_card(-1); add_child(node)
		node.global_transform = Transform3D(flat_basis(false, 0.08), dp + Vector3(0, 0.02, 0))
	set_deck(deck_left, trump_node.get_meta("card") if trump_node else -1)
	var p = people[seat]
	if p:
		var home: Transform3D = p.fan_home()
		await _fly(node, Transform3D(home.basis * Basis(Vector3.UP, PI), home.origin), 0.3, 0.1, Vector3.ONE * FAN_SCALE)
		node.queue_free()
		var c := make_card(-1, true); p.fan.add_child(c)
		p.cards.insert(randi() % (p.cards.size() + 1), c)          # into a random place
		_fan_layout(p, false)
	else:
		if card >= 0: set_face(node, card)
		await _fly(node, Transform3D(cam.global_basis, cam.project_position(screen, 0.6)), 0.28, 0.06)
		node.queue_free()

func nod(seat: int) -> void:
	var p = people[seat]
	if p == null: return
	var tw := create_tween()
	tw.tween_method(func(e): p.lean = sin(PI * e) * 0.15, 0.0, 1.0, 0.4 / speed)
	await tw.finished

func new_match(n: int, my_seat: int, deck_n: int, trump_card: int) -> void:
	for p in pairs:
		if p.a: p.a.queue_free()
		if p.d: p.d.queue_free()
	pairs = []
	for c in discard_root.get_children(): c.queue_free()
	discard_n = 0
	if trump_node: trump_node.queue_free(); trump_node = null
	_place_people(n, my_seat)
	set_deck(deck_n, trump_card)

func set_table(tbl: Array) -> void:
	for p in pairs:
		if p.a: p.a.queue_free()
		if p.d: p.d.queue_free()
	pairs = []
	for x in tbl:
		var a := make_card(x.a); add_child(a)
		var d: Node3D = null
		if x.d >= 0: d = make_card(x.d); add_child(d)
		pairs.append({"a": a, "d": d})
	_relayout(false)

func highlight(idxs: Array) -> void:
	for g in glows: g.queue_free()
	glows = []
	for i in idxs:
		if i >= pairs.size() or pairs[i].a == null: continue
		var g := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(CW * 1.16, CH * 1.1); g.mesh = q
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.35, 0.85); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.material_override = m
		add_child(g)
		g.global_transform = pairs[i].a.global_transform
		g.global_position.y -= 0.001
		glows.append(g)

func pick_slot(screen: Vector2) -> int:
	var from := cam.project_ray_origin(screen); var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 1e-4: return -1
	var t := (TABLE_Y - from.y) / dir.y
	var hit := from + dir * t
	var best := -1; var bd := 0.2
	for i in pairs.size():
		if pairs[i].a == null: continue
		var d: float = Vector2(hit.x, hit.z).distance_to(Vector2(pairs[i].a.global_position.x, pairs[i].a.global_position.z))
		if d < bd: bd = d; best = i
	return best

func label_pos(seat: int) -> Vector2:
	var p = people[seat] if seat < people.size() else null
	if p == null: return Vector2(-999, -999)
	return cam.unproject_position(p.global_position + Vector3.UP * 1.42)

# ------------------------------------------------------------------ camera
## the camera looks down at a fixed angle and comes as close as it can while every head and the table fit above
## the area of my cards (view_bottom pixels)
func set_view_bottom(px: float) -> void:
	view_bottom = px; frame_camera()
func frame_camera() -> void:
	if cam == null or seats == 0: return
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var pitch := deg_to_rad(36.0 if seats <= 2 else (40.0 if seats == 3 else 44.0))
	if aspect > 1.0: pitch = deg_to_rad(34.0)
	var look := Vector3(0, TABLE_Y, 0.0)
	var dir := Vector3(0, -sin(pitch), -cos(pitch))
	cam.fov = 46.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH if aspect < 1.0 else Camera3D.KEEP_HEIGHT
	cam.v_offset = 0.0
	var pts := []
	for k in seats:
		if k == me: continue
		var sp := seat_point(k)
		pts.append(sp + Vector3.UP * 1.5)
		pts.append(sp * 0.8 + Vector3.UP * (TABLE_Y + 0.3))
	pts.append_array([Vector3(-RX - 0.05, TABLE_Y, 0), Vector3(RX + 0.05, TABLE_Y, 0), Vector3(0, TABLE_Y, RZ * 0.6), Vector3(0, TABLE_Y, -RZ - 0.05)])
	var avail := vs.y - view_bottom - 16.0
	# try a few angles and keep the one that shows the table biggest
	var best := 99.0; var best_dir := dir; var best_tall := -1.0
	for deg in ([30.0, 36.0, 42.0, 48.0, 54.0] if aspect < 1.0 else [30.0, 36.0]):
		var pr := deg_to_rad(deg)
		var dd := Vector3(0, -sin(pr), -cos(pr))
		var lo := 1.2; var hi := 14.0; var found := 99.0
		for it in 20:
			var d := (lo + hi) / 2.0
			cam.global_transform = Transform3D(Basis.looking_at(dd), look - dd * d)
			var mnx := 1e9; var mxx := -1e9; var mny := 1e9; var mxy := -1e9
			for p in pts:
				var sp: Vector2 = cam.unproject_position(p)
				mnx = minf(mnx, sp.x); mxx = maxf(mxx, sp.x); mny = minf(mny, sp.y); mxy = maxf(mxy, sp.y)
			if mnx >= vs.x * 0.04 and mxx <= vs.x * 0.96 and (mxy - mny) <= avail: found = d; hi = d
			else: lo = d
		if found > 50.0: continue
		# score: how tall the table looks on the screen (a flat angle squeezes it)
		cam.global_transform = Transform3D(Basis.looking_at(dd), look - dd * found)
		var tall: float = cam.unproject_position(Vector3(0, TABLE_Y, RZ)).y - cam.unproject_position(Vector3(0, TABLE_Y, -RZ)).y
		if tall > best_tall: best_tall = tall; best = found; best_dir = dd
	dir = best_dir
	cam.global_transform = Transform3D(Basis.looking_at(dir), look - dir * best)
	# shift the picture so its top sits near the top of the screen (h/v offset are in world units at distance 1)
	var top := 1e9
	for p in pts: top = minf(top, cam.unproject_position(p).y)
	var want := 118.0
	var px_per_unit := vs.x / (2.0 * tan(deg_to_rad(cam.fov) / 2.0)) if cam.keep_aspect == Camera3D.KEEP_WIDTH else vs.y / (2.0 * tan(deg_to_rad(cam.fov) / 2.0))
	cam.v_offset = (top - want) / px_per_unit * best * 0.0 + 0.0
	cam.global_position -= cam.global_basis.y * ((top - want) / px_per_unit) * best
	for p in people:
		if p:
			var rt: Array = p.rest_targets()
			if not p.right_busy: p.right_target = rt[1]
			p.left_target = rt[0]
			_fan_layout(p, false)
