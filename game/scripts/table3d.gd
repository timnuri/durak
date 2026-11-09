extends Node3D
## The 3D table: a dark room, a lamp over an oval or rectangular table, the opponents sitting evenly around it.
## The human player is the camera; his own cards are 2D at the bottom of the screen (main.gd).
## Every move is an async function; the game awaits them one after another.
## Nothing gives a hand away: an opponent takes a random card from his fan, new cards go into a random place,
## and the deck is dealt from without a hand.


const PersonScript := preload("res://scripts/person.gd")
const TABLE_Y := 0.74
const CW := 0.32
const CH := 0.48
const FAN_SCALE := 0.56
var RX := 0.8
var RZ := 1.0
## the room: walls at ±ROOM_X, back wall at -ROOM_ZB, the wall behind me at +ROOM_ZF
const ROOM_X := 3.2
const ROOM_ZB := 3.3
const ROOM_ZF := 3.0
const ROOM_H := 2.9

const THEMES := {
	"cabinet": {"name": "Кабинет", "bg": Color("1a0f08"), "surface": "wood", "wood": Color("6a3a1c"), "rim": Color("3a1c0d"), "felt": Color("3a1c0d"),
		"inlay": Color("c99a45"), "lamp": Color("ffcf96"), "lamp_e": 3.2, "amb": Color("6a5040"), "amb_e": 0.5, "rim_tint": 0.25,
		"exposure": 1.0, "floor": Color("8a5a36"), "wall": Color("3b2a1e"), "panel": Color("4a2e1c"), "rug": Color("7a2a22"), "warm": Color("ffb066"),
		"sofa": "GlamVelvetSofa", "env_e": 0.25},
	"casino": {"name": "Казино", "bg": Color("06140f"), "surface": "felt", "wood": Color("5a2c14"), "rim": Color("4a2210"), "felt": Color("0f6a38"),
		"inlay": Color("f0c75a"), "lamp": Color("fff0d8"), "lamp_e": 3.2, "amb": Color("3a5a4a"), "amb_e": 0.5, "rim_tint": 0.3,
		"exposure": 1.05, "floor": Color("4a2a1a"), "wall": Color("12382a"), "panel": Color("3a1a0a"), "rug": Color("6a1418"), "warm": Color("ffd28a"),
		"sofa": "GlamVelvetSofa", "env_e": 0.3},
	"neon": {"name": "Неон", "bg": Color("07031a"), "surface": "felt", "wood": Color("1a1430"), "rim": Color("120c26"), "felt": Color("1c1f5e"),
		"inlay": Color("3ff0ff"), "lamp": Color("d9c8ff"), "lamp_e": 3.6, "amb": Color("40308a"), "amb_e": 0.45, "rim_tint": 0.6,
		"exposure": 1.05, "floor": Color("2a2440"), "wall": Color("140c2e"), "panel": Color("0c0820"), "rug": Color("2a1460"), "warm": Color("ff3fd0"),
		"sofa": "GlamVelvetSofa", "env_e": 0.2, "neon": true},
	"day": {"name": "Светлая", "bg": Color("e8d6bc"), "surface": "wood", "wood": Color("d8b080"), "rim": Color("a87444"), "felt": Color("d8b080"),
		"inlay": Color("8a5a2a"), "lamp": Color("fffaf0"), "lamp_e": 2.6, "amb": Color("f0e0c8"), "amb_e": 0.9, "rim_tint": 0.2,
		"exposure": 1.0, "floor": Color("c8a070"), "wall": Color("e8dcc8"), "panel": Color("c09868"), "rug": Color("9a6a4a"), "warm": Color("fff0d0"),
		"sofa": "GlamVelvetSofa", "env_e": 0.8, "day": true},
}
const BACKS := {"blue": "Синяя", "red": "Красная", "black": "Чёрная", "gold": "Золотая", "green": "Зелёная"}
## clothes of the opponents (one set per seat): skin, hair, sweater, trousers, shoes, collar
const LOOKS := [
	{"skin": Color("c89c7c"), "hair": Color("2a1a10"), "top": Color("2c3e5c"), "pants": Color("2a2a2e"), "shoes": Color("1a1210"), "collar": Color("e8e4dc")},
	{"skin": Color("a87458"), "hair": Color("0e0a08"), "top": Color("7a2a2a"), "pants": Color("1e2430"), "shoes": Color("2a1a10"), "collar": Color("7a2a2a")},
	{"skin": Color("d4aa8a"), "hair": Color("8a5a2a"), "top": Color("3a5a3a"), "pants": Color("3a3028"), "shoes": Color("1a1a1a"), "collar": Color("d8d0c0")},
	{"skin": Color("8a5a40"), "hair": Color("1a1210"), "top": Color("c8b090"), "pants": Color("2a2a30"), "shoes": Color("3a2414"), "collar": Color("c8b090")},
	{"skin": Color("c8a080"), "hair": Color("5a3a20"), "top": Color("1e1e22"), "pants": Color("3a3a44"), "shoes": Color("101010"), "collar": Color("f0f0f0")},
]

var theme: Dictionary = THEMES.cabinet
var shape := "square"
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
var _person_model: PackedScene
var _chair_model: PackedScene
var probe: ReflectionProbe
var cam_attr: CameraAttributesPractical
## "forward_plus" / "mobile" (Android) / "gl_compatibility" (browser)
var renderer := "gl_compatibility"

# ------------------------------------------------------------------ setup
func _ready() -> void:
	renderer = RenderingServer.get_current_rendering_method()
	cam = Camera3D.new(); cam.fov = 46.0; cam.near = 0.05; cam.far = 40.0
	cam_attr = CameraAttributesPractical.new()
	cam.attributes = cam_attr
	add_child(cam)
	env = WorldEnvironment.new(); env.environment = Environment.new(); add_child(env)
	room_root = Node3D.new(); add_child(room_root)
	table_root = Node3D.new(); add_child(table_root)
	discard_root = Node3D.new(); add_child(discard_root)
	_person_model = load("res://models/Xbot.glb")
	_chair_model = load("res://models/room/ChairDamaskPurplegold.glb")
	get_viewport().size_changed.connect(frame_camera)

func hi_quality() -> bool: return renderer != "gl_compatibility"

func set_look(look: Dictionary) -> void:
	theme = THEMES.get(look.get("theme", "cabinet"), THEMES.cabinet)
	shape = look.get("shape", shape)
	face = look.get("face", face)
	back = look.get("back", back)
	RX = 0.8 if shape == "round" else 0.76
	RZ = 0.9 if shape == "round" else 0.86
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
	# reflections: an HDR photo of a lobby (for the lacquer and the glass), the room itself comes from the probe
	var sky := Sky.new(); var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://art/env/lobby.hdr"); psm.energy_multiplier = theme.env_e
	sky.sky_material = psm; sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = theme.amb
	e.ambient_light_energy = theme.amb_e
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = theme.exposure
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_strength = 1.0
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = false
	e.ssao_enabled = renderer == "forward_plus"
	e.ssao_radius = 0.6; e.ssao_intensity = 1.6
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06; e.adjustment_saturation = 1.08
	if lamp: lamp.queue_free()
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 2.45, 0.1)
	lamp.light_color = theme.lamp
	lamp.light_energy = theme.lamp_e
	lamp.spot_range = 5.0
	lamp.spot_angle = 46.0
	lamp.spot_angle_attenuation = 1.3
	lamp.shadow_enabled = true
	lamp.shadow_blur = 1.5
	lamp.light_size = 0.12
	lamp.light_specular = 0.35 if hi_quality() else 0.15          # soft shadows (PCSS) on Android and desktop
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
## real wood: grain texture, normal map, lacquer
func _wood(color: Color, rough := 0.35, scale := 1.0, coat := 0.0) -> StandardMaterial3D:
	var m := _mat(color, rough, "res://art/wood_pbr.jpg")
	m.normal_enabled = true; m.normal_texture = load("res://art/wood_pbr_n.jpg"); m.normal_scale = 0.6
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if coat > 0.0: m.clearcoat_enabled = true; m.clearcoat = coat; m.clearcoat_roughness = 0.22
	return m
func _box(size: Vector3, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = size; mi.mesh = b
	mi.position = pos; mi.material_override = m
	(parent if parent else room_root).add_child(mi)
	return mi
func _model(path: String, pos: Vector3, yaw_deg := 0.0, s := 1.0, parent: Node3D = null) -> Node3D:
	var m: Node3D = load(path).instantiate()
	for c in m.find_children("*", "Camera3D", true, false): c.free()
	for c in m.find_children("*", "Light3D", true, false): c.free()
	m.position = pos; m.rotation_degrees.y = yaw_deg; m.scale = Vector3.ONE * s
	(parent if parent else room_root).add_child(m)
	return m
func _omni(pos: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new(); l.position = pos; l.light_color = col; l.light_energy = energy; l.omni_range = rng
	l.omni_attenuation = 1.4; l.shadow_enabled = shadow and hi_quality()
	room_root.add_child(l)
	return l

## a real room around the table: wood floor and a rug, panelled walls, a sofa, plants, a floor lamp, sconces, pictures
func _build_room() -> void:
	for c in room_root.get_children(): c.queue_free()
	var t: Dictionary = theme
	# floor and rug
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(ROOM_X * 2, ROOM_ZB + ROOM_ZF)
	floor.mesh = pm; floor.position.z = (ROOM_ZF - ROOM_ZB) / 2.0
	floor.material_override = _wood(t.floor, 0.45, 5.0, 0.4)
	room_root.add_child(floor)
	var rug := MeshInstance3D.new(); var rp := PlaneMesh.new(); rp.size = Vector2(3.4, 3.0); rug.mesh = rp; rug.position.y = 0.006
	var rm := _mat(t.rug, 0.95, "res://art/wool.jpg"); rm.uv1_scale = Vector3(4, 4, 4)
	rm.normal_enabled = true; rm.normal_texture = load("res://art/wool_n.jpg"); rm.normal_scale = 0.7
	rug.material_override = rm; room_root.add_child(rug)
	var border := MeshInstance3D.new(); var bp := PlaneMesh.new(); bp.size = Vector2(3.6, 3.2); border.mesh = bp; border.position.y = 0.004
	border.material_override = _mat(t.rug.darkened(0.55), 0.95, "res://art/wool.jpg"); room_root.add_child(border)
	# ceiling
	_box(Vector3(ROOM_X * 2, 0.05, ROOM_ZB + ROOM_ZF), Vector3(0, ROOM_H + 0.025, (ROOM_ZF - ROOM_ZB) / 2.0), _mat(t.wall.darkened(0.5), 0.9))
	# walls: wallpaper above, wood panels below, a rail and a skirting board
	var paper := _mat(t.wall, 0.85, "res://art/wool.jpg"); paper.uv1_scale = Vector3(6, 3, 1)
	var panel := _wood(t.panel, 0.4, 2.0, 0.3)
	var trim := _wood(t.panel.darkened(0.25), 0.35, 3.0, 0.4)
	var walls := [[Vector3(0, 0, -ROOM_ZB), 0.0, ROOM_X * 2], [Vector3(-ROOM_X, 0, 0), 90.0, ROOM_ZB + ROOM_ZF], [Vector3(ROOM_X, 0, 0), -90.0, ROOM_ZB + ROOM_ZF], [Vector3(0, 0, ROOM_ZF), 180.0, ROOM_X * 2]]
	for w in walls:
		var root := Node3D.new(); root.position = w[0]; root.rotation_degrees.y = w[1]; room_root.add_child(root)
		if w[1] == 90.0 or w[1] == -90.0: root.position.z = (ROOM_ZF - ROOM_ZB) / 2.0
		var len: float = w[2]
		_box(Vector3(len, ROOM_H - 1.0, 0.04), Vector3(0, 1.0 + (ROOM_H - 1.0) / 2.0, 0), paper, root)
		_box(Vector3(len, 1.0, 0.04), Vector3(0, 0.5, 0.0), panel, root)
		_box(Vector3(len, 0.05, 0.07), Vector3(0, 1.0, 0.02), trim, root)
		_box(Vector3(len, 0.12, 0.06), Vector3(0, 0.06, 0.02), trim, root)
		_box(Vector3(len, 0.08, 0.08), Vector3(0, ROOM_H - 0.04, 0.02), trim, root)
		var k := -len / 2.0 + 0.55
		while k < len / 2.0 - 0.4:                            # raised panels on the wainscot
			_box(Vector3(0.62, 0.62, 0.025), Vector3(k, 0.52, 0.025), panel, root)
			k += 0.8
		if t.get("neon", false):
			_box(Vector3(len, 0.03, 0.03), Vector3(0, ROOM_H - 0.14, 0.05), _mat(t.inlay, 1.0, "", 4.0), root)
			_box(Vector3(len, 0.03, 0.03), Vector3(0, 1.05, 0.05), _mat(t.warm, 1.0, "", 3.0), root)
	# furniture along the back wall
	var bz := -ROOM_ZB
	_model("res://models/room/%s.glb" % t.sofa, Vector3(0, 0, bz + 0.7), 0.0, 1.0)
	_model("res://models/room/DiffuseTransmissionPlant.glb", Vector3(-ROOM_X + 0.55, 0, bz + 0.55), 30.0, 1.7)
	_model("res://models/room/DiffuseTransmissionPlant.glb", Vector3(ROOM_X - 0.5, 0, bz + 0.5), -60.0, 1.5)
	_model("res://models/room/SheenChair.glb", Vector3(-ROOM_X + 0.6, 0, -0.9), 70.0, 1.05)
	# a side table with flowers and a candle
	var side := Vector3(-1.75, 0, bz + 0.45)
	_box(Vector3(0.5, 0.04, 0.4), side + Vector3(0, 0.62, 0), _wood(t.panel, 0.3, 1.0, 0.8))
	for dx in [-0.21, 0.21]:
		for dz in [-0.16, 0.16]:
			_box(Vector3(0.035, 0.6, 0.035), side + Vector3(dx, 0.3, dz), _wood(t.panel.darkened(0.2), 0.4))
	_model("res://models/room/GlassVaseFlowers.glb", side + Vector3(-0.08, 0.64, 0.02), 20.0, 2.2)
	var candle := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 0.025; cy.bottom_radius = 0.025; cy.height = 0.14
	candle.mesh = cy; candle.position = side + Vector3(0.14, 0.64 + 0.07, 0.0); candle.material_override = _mat(Color("f0e6d0"), 0.6)
	room_root.add_child(candle)
	_flame(side + Vector3(0.14, 0.64 + 0.16, 0.0))
	# floor lamp on the right
	_floor_lamp(Vector3(1.75, 0, bz + 0.45))
	# sconces on the side walls and pictures (the old Russian deck's kings and queens) on the walls
	for sx in [-1.0, 1.0]:
		for zz in [-1.6, 0.6]:
			_sconce(Vector3(sx * (ROOM_X - 0.05), 1.75, zz), -sx)
	_picture(Vector3(-1.75, 1.75, bz + 0.03), 0.0, "res://cards/ru/1-13.webp")
	_picture(Vector3(1.75, 1.75, bz + 0.03), 0.0, "res://cards/ru/2-12.webp")
	_picture(Vector3(0, 1.85, bz + 0.03), 0.0, "res://cards/ru/3-11.webp", 1.25)
	_picture(Vector3(-ROOM_X + 0.03, 1.7, -2.6), 90.0, "res://cards/ru/3-13.webp")
	_picture(Vector3(ROOM_X - 0.03, 1.7, -2.6), -90.0, "res://cards/ru/0-12.webp")
	# reflections of the room in the lacquer and the glass
	if probe: probe.queue_free()
	probe = ReflectionProbe.new()
	probe.size = Vector3(ROOM_X * 2, ROOM_H, ROOM_ZB + ROOM_ZF)
	probe.position = Vector3(0, ROOM_H / 2.0, (ROOM_ZF - ROOM_ZB) / 2.0)
	probe.origin_offset = Vector3(0, 1.3 - ROOM_H / 2.0, -(ROOM_ZF - ROOM_ZB) / 2.0)
	probe.box_projection = true; probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.mesh_lod_threshold = 4.0
	add_child(probe)
	# soft light from behind me so that faces are not black
	var fill := _omni(Vector3(0, 1.9, ROOM_ZF - 0.6), t.warm.lerp(Color.WHITE, 0.6), 0.6, 5.0)
	fill.light_specular = 0.0

func _flame(pos: Vector3) -> void:
	var f := MeshInstance3D.new(); var s := SphereMesh.new(); s.radius = 0.012; s.height = 0.04; f.mesh = s
	var m := _mat(Color("ffb84a"), 1.0, "", 8.0); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.material_override = m; f.position = pos; f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room_root.add_child(f)
	_omni(pos + Vector3(0, 0.05, 0), Color("ff9a40"), 0.8, 1.6)

func _floor_lamp(at: Vector3) -> void:
	var metal := _mat(Color("b08a4a"), 0.3); metal.metallic = 0.9
	var base := MeshInstance3D.new(); var bc := CylinderMesh.new(); bc.top_radius = 0.16; bc.bottom_radius = 0.18; bc.height = 0.03
	base.mesh = bc; base.position = at + Vector3(0, 0.015, 0); base.material_override = metal; room_root.add_child(base)
	var pole := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.013; pc.bottom_radius = 0.016; pc.height = 1.5
	pole.mesh = pc; pole.position = at + Vector3(0, 0.78, 0); pole.material_override = metal; room_root.add_child(pole)
	var shade := MeshInstance3D.new(); var sc := CylinderMesh.new(); sc.top_radius = 0.17; sc.bottom_radius = 0.25; sc.height = 0.32; sc.cap_top = false; sc.cap_bottom = false
	var sm := _mat(theme.warm.lerp(Color("fff0d8"), 0.5), 0.9, "", 1.6)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.mesh = sc; shade.position = at + Vector3(0, 1.58, 0); shade.material_override = sm
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room_root.add_child(shade)
	_omni(at + Vector3(0, 1.5, 0.15), theme.warm, 2.4, 4.0, true)

func _sconce(pos: Vector3, facing: float) -> void:
	var metal := _mat(Color("b08a4a"), 0.3); metal.metallic = 0.9
	_box(Vector3(0.03, 0.18, 0.1), pos, metal)
	var glass := MeshInstance3D.new(); var s := SphereMesh.new(); s.radius = 0.07; s.height = 0.12; glass.mesh = s
	glass.material_override = _mat(theme.warm.lerp(Color.WHITE, 0.4), 0.5, "", 3.0)
	glass.position = pos + Vector3(facing * 0.1, 0.07, 0); glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room_root.add_child(glass)
	_omni(glass.position + Vector3(facing * 0.15, 0, 0), theme.warm, 1.6, 3.4)

func _picture(pos: Vector3, yaw: float, img: String, s := 1.0) -> void:
	var root := Node3D.new(); root.position = pos; root.rotation_degrees.y = yaw; room_root.add_child(root)
	var gold := _mat(Color("a07830"), 0.35); gold.metallic = 0.85
	var w := 0.42 * s; var h := 0.6 * s
	_box(Vector3(w + 0.08, h + 0.08, 0.03), Vector3(0, 0, 0.015), gold, root)
	var q := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(w, h); q.mesh = qm
	var m := _mat(Color(0.85, 0.82, 0.76), 0.6, img); q.material_override = m
	q.position = Vector3(0, 0, 0.032); root.add_child(q)

## things on the table: a card box and a tin
func _build_props() -> void:
	var box := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.2, 0.07, 0.28); box.mesh = bm
	var m := _mat(Color("1a0f0a"), 0.35); m.metallic = 0.2
	box.material_override = m
	var lid := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(0.17, 0.25); lid.mesh = q
	var lm := _card_mat(_texture("res://cards/backs/gold.webp")); lid.material_override = lm
	lid.rotation = Vector3(-PI / 2, 0, 0); lid.position.y = 0.0355; box.add_child(lid)
	box.position = Vector3(-RX * 0.78, TABLE_Y + 0.035, RZ * 0.42); box.rotation.y = 0.35
	table_root.add_child(box)
	var tin := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.09; cm.bottom_radius = 0.09; cm.height = 0.07; tin.mesh = cm
	var tm := _mat(Color("2a2420"), 0.25); tm.metallic = 0.85; tin.material_override = tm
	var rimm := MeshInstance3D.new(); var tr := TorusMesh.new(); tr.inner_radius = 0.085; tr.outer_radius = 0.095; rimm.mesh = tr
	var gm := _mat(Color("b88a3a"), 0.3); gm.metallic = 0.9; rimm.material_override = gm; rimm.position.y = 0.035; tin.add_child(rimm)
	tin.position = Vector3(RX * 0.8, TABLE_Y + 0.035, RZ * 0.38)
	table_root.add_child(tin)

func _surface_mat() -> StandardMaterial3D:
	if theme.surface == "felt":
		var m := _mat(theme.felt, 0.95, "res://art/felt.webp")
		m.uv1_scale = Vector3(3, 3, 3)
		m.normal_enabled = true; m.normal_texture = load("res://art/wool_n.jpg"); m.normal_scale = 0.4
		return m
	return _wood(theme.wood, 0.38, 1.0, 0.55)
func _rim_mat() -> StandardMaterial3D:
	var m := _wood(theme.rim, 0.45, 2.0, 0.25)
	if theme.get("neon", false):
		m = _mat(Color("0c0a1c"), 0.3)
		m.emission_enabled = true; m.emission = theme.inlay; m.emission_energy_multiplier = 0.35
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
		var im := _mat(theme.inlay.darkened(0.25), 0.3, "", 0.6 if theme.get("neon", false) else 0.0); im.metallic = 0.8
		ring.material_override = im
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
	# a turned pedestal on a wide foot
	var wood := _wood(theme.rim, 0.35, 1.0, 0.6)
	var leg := MeshInstance3D.new(); var lm := CylinderMesh.new(); lm.top_radius = 0.09; lm.bottom_radius = 0.13; lm.height = TABLE_Y - 0.16
	leg.mesh = lm; leg.position.y = 0.08 + (TABLE_Y - 0.16) / 2; leg.material_override = wood
	table_root.add_child(leg)
	var cap := MeshInstance3D.new(); var cc := CylinderMesh.new(); cc.top_radius = 0.3; cc.bottom_radius = 0.12; cc.height = 0.1
	cap.mesh = cc; cap.position.y = TABLE_Y - 0.11; cap.material_override = wood; table_root.add_child(cap)
	var foot := MeshInstance3D.new(); var fc := CylinderMesh.new(); fc.top_radius = 0.2; fc.bottom_radius = 0.42; fc.height = 0.1
	foot.mesh = fc; foot.position.y = 0.05; foot.material_override = wood; table_root.add_child(foot)
	_build_props()

# ------------------------------------------------------------------ people
func seat_point(k: int, out := 0.36) -> Vector3:
	# me at the bottom (+Z); the opponents sit in an arc across the table, clockwise, so that all of them are in view
	var i := (k - me + seats) % seats
	var n_opp := seats - 1
	var span := minf(124.0, 42.0 * (n_opp - 1))
	var deg := 90.0 if i == 0 else 270.0 - span / 2.0 + (span * float(i - 1) / float(n_opp - 1) if n_opp > 1 else span / 2.0)
	var ang := deg_to_rad(deg)
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
		var look: Dictionary = LOOKS[(k - 1 + LOOKS.size()) % LOOKS.size()]
		p.setup(_person_model, look, 1.0 if k % 2 == 0 else 1.05, theme.rim_tint)
		var chair := _model("res://models/room/ChairDamaskPurplegold.glb", Vector3(0, 0, -0.12), 0.0, 1.0, p)
		chair.name = "Chair"
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
	m.albedo_color = Color(0.92, 0.9, 0.86)
	# a little light of its own, so the cards read well even in the shadow of a hand
	m.emission_enabled = true; m.emission_texture = tex; m.emission = Color(1, 1, 1); m.emission_energy_multiplier = 0.22
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
		if not is_instance_valid(node): return
		var k := ease(e, -2.0)
		var p := from.origin.lerp(to.origin, k) + Vector3.UP * sin(PI * k) * lift
		node.global_transform = Transform3D(Basis(qa.slerp(qb, minf(1.0, k * 1.2))).scaled(s0.lerp(to_scale, k)), p), 0.0, 1.0, secs / speed)
	await tw.finished

func _place(node: Node3D, kind: String, idx: int) -> void:
	if not is_instance_valid(node): return
	if idx >= pairs.size(): node.queue_free(); return          # the table was cleared meanwhile (a new match)
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
		tw.tween_method(func(e): if is_instance_valid(p): p.right_target = from.lerp(grip, e), 0.0, 1.0, 0.18 / speed)
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
		var hand_follow := func(_e): if is_instance_valid(p) and is_instance_valid(node): p.right_target = node.global_position + Vector3.UP * 0.03
		var lean0: float = p.lean
		var tw2 := create_tween().set_parallel()
		tw2.tween_method(func(e: float): if is_instance_valid(p): p.lean = lean0 + sin(PI * minf(1.0, e * 1.2)) * 0.3; hand_follow.call(e), 0.0, 1.0, 0.45 / speed)
		_fly(node, tg, 0.45)
		await tw2.finished
		if not is_instance_valid(p) or not is_instance_valid(node): return
		node.set_meta("flying", false)
		node.global_transform = tg
		var back_from: Vector3 = p.right_target
		var rest: Vector3 = p.rest_targets()[1]
		var tw3 := create_tween()
		tw3.tween_method(func(e): if is_instance_valid(p): p.right_target = back_from.lerp(rest, e); p.lean = lean0 * e, 0.0, 1.0, 0.3 / speed)
		tw3.finished.connect(func(): if is_instance_valid(p): p.right_busy = false)
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
		tw.tween_method(func(e): if is_instance_valid(p): p.right_target = from.lerp(mid, e); p.lean = 0.3 * e, 0.0, 1.0, 0.25 / speed)
		await tw.finished
		var home: Transform3D = p.fan_home()
		for n in cards:
			_fly(n, Transform3D(home.basis * Basis(Vector3.UP, PI), home.origin), 0.38 + k * 0.03, 0.1, Vector3.ONE * FAN_SCALE)
			k += 1
		var tw2 := create_tween()
		tw2.tween_method(func(e): if is_instance_valid(p): p.right_target = mid.lerp(p.rest_targets()[1], e); p.lean = 0.3 * (1.0 - e), 0.0, 1.0, 0.42 / speed)
		tw2.finished.connect(func(): if is_instance_valid(p): p.right_busy = false)
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
	if seat >= people.size(): node.queue_free(); return          # a new match with fewer players started meanwhile
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
	tw.tween_method(func(e): if is_instance_valid(p): p.lean = sin(PI * e) * 0.15, 0.0, 1.0, 0.4 / speed)
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
## put the camera at `e` looking straight ahead (no yaw), tilted so that the world point `pt` lands at screen height `want`
func _aim(e: Vector3, pt: Vector3, want: float) -> float:
	var lo := -1.4; var hi := 0.3
	for it in 22:
		var pitch := (lo + hi) / 2.0
		cam.global_transform = Transform3D(Basis(Vector3.RIGHT, pitch), e)
		var y: float = cam.unproject_position(pt).y
		if cam.is_position_behind(pt) or y > want: hi = pitch
		else: lo = pitch
	return 0.0

func frame_camera() -> void:
	if cam == null or seats == 0: return
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var portrait := aspect < 1.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 62.0 if portrait else 48.0
	cam.v_offset = 0.0; cam.h_offset = 0.0
	# sitting at the table, looking across it: the camera finds the height and the distance at which the heads of the
	# opponents are near the top of the screen and the near edge of the table is just above my cards
	var top_y := vs.y * (0.2 if portrait else 0.16)
	var edge_y := vs.y - view_bottom + vs.y * 0.03
	var heads: Array = []
	for p in people:
		if p: heads.append(p.global_position + Vector3.UP * 1.25)
	if heads.is_empty(): heads.append(Vector3(0, 1.25, -RZ - 0.36))
	var best := INF; var eye := Vector3.ZERO
	for zi in 16:
		for yi in 23:
			var e := Vector3(0, 1.25 + yi * 0.05, RZ + 0.15 + zi * 0.08)
			var y_e := _aim(e, Vector3(0, TABLE_Y, RZ), edge_y)
			var hy := INF; var out := 0.0
			for h in heads:
				if cam.is_position_behind(h): hy = -INF; continue
				var sp := cam.unproject_position(h)
				hy = minf(hy, sp.y)
				out += maxf(0.0, vs.x * 0.06 - sp.x) + maxf(0.0, sp.x - vs.x * 0.94)
			var sc := absf(hy - top_y) + out * 3.0 + y_e * 0.0
			if sc < best: best = sc; eye = e
	_aim(eye, Vector3(0, TABLE_Y, RZ), edge_y)
	# depth of field: the table and the players sharp, the room behind them soft (Android and desktop)
	var far := 0.0
	for p in people:
		if p: far = maxf(far, eye.distance_to(p.global_position + Vector3.UP * 1.1))
	cam_attr.dof_blur_far_enabled = hi_quality() and far > 0.0
	cam_attr.dof_blur_far_distance = far + 0.6
	cam_attr.dof_blur_far_transition = 2.0
	cam_attr.dof_blur_amount = 0.05
	for p in people:
		if p:
			var rt: Array = p.rest_targets()
			if not p.right_busy: p.right_target = rt[1]
			p.left_target = rt[0]
			_fan_layout(p, false)
