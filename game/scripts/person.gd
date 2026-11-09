extends Node3D
## One opponent at the table: a real human model (Mixamo rig) posed sitting, dark like a silhouette in the lamp
## light, holding a fan of cards in both hands. The arms follow targets (two-bone IK), so the right hand can
## reach anywhere on the table; the spine leans with it.

const P := "mixamorig_"
var sk: Skeleton3D
var MODEL_YAW := 0.0
var bones := {}
var fan := Node3D.new()           # the cards in the hands (children: card nodes)
var cards: Array = []
var left_target := Vector3.ZERO    # world space
var right_target := Vector3.ZERO
var right_busy := false
var lean := 0.0                    # extra forward lean (radians) while reaching
var look_at_point := Vector3.ZERO
var t := 0.0
var phase := randf() * 6.28
var seat_height := 0.47
var _rest_dir := {}
var _len := {}

func setup(model: PackedScene, mat: Material, height_scale: float) -> void:
	var m := model.instantiate()
	add_child(m)
	m.scale = Vector3.ONE * height_scale
	m.rotation.y = MODEL_YAW
	sk = _find_skeleton(m)
	for mi in _meshes(m):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ap := m.find_child("AnimationPlayer", true, false)
	if ap: ap.stop()
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.begins_with(P): bones[n.substr(P.length())] = i
	sk.reset_bone_poses()
	for pair in [["Spine", "Spine1"], ["Spine1", "Spine2"], ["Spine2", "Neck"], ["Neck", "Head"], ["Head", "HeadTop_End"],
			["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"], ["LeftHand", "LeftHandMiddle1"],
			["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"], ["RightHand", "RightHandMiddle1"],
			["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"],
			["LeftShoulder", "LeftArm"], ["RightShoulder", "RightArm"]]:
		var a: int = bones[pair[0]]; var b: int = bones[pair[1]]
		var d := sk.get_bone_global_rest(b).origin - sk.get_bone_global_rest(a).origin
		_rest_dir[pair[0]] = d.normalized()
		_len[pair[0]] = d.length()
	# every model gets the same torso: shoulders 0.52 m above the hips (the models come in different sizes)
	var torso := (sk.global_transform * sk.get_bone_global_rest(bones["LeftArm"]).origin).y - (sk.global_transform * sk.get_bone_global_rest(bones["Hips"]).origin).y
	m.scale = Vector3.ONE * height_scale * 0.52 / maxf(torso, 0.05)
	# sit: the hips go down to the chair
	var hips_y := (sk.global_transform * sk.get_bone_global_rest(bones["Hips"]).origin).y - global_position.y
	m.position.y = seat_height - hips_y
	add_child(fan)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r: return r
	return null
func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out

## skeleton-space helpers
func _to_sk(world: Vector3) -> Vector3: return sk.global_transform.affine_inverse() * world
func _dir_to_sk(world_dir: Vector3) -> Vector3: return (sk.global_transform.basis.inverse() * world_dir).normalized()
## global poses computed here (the skeleton's own cache is a frame late while we change bones)
var _gc := {}
func _g(b: int) -> Transform3D:
	if _gc.has(b): return _gc[b]
	var par := sk.get_bone_parent(b)
	var pg := _g(par) if par >= 0 else Transform3D()
	var local := Transform3D(Basis(sk.get_bone_pose_rotation(b)).scaled(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b))
	var g := pg * local
	_gc[b] = g
	return g
func _gpos(name: String) -> Vector3: return _g(bones[name]).origin
func world_of(name: String) -> Vector3: return sk.global_transform * _gpos(name)

## turn bone `name` so that it points along `dir` (skeleton space); twist about `up_hint` kept natural
func _point(name: String, dir: Vector3) -> void:
	var b: int = bones[name]
	var rest_g := sk.get_bone_global_rest(b)
	var q := Quaternion(_rest_dir[name], dir.normalized())
	var new_basis := Basis(q) * rest_g.basis
	var parent := sk.get_bone_parent(b)
	var pb := _g(parent).basis.orthonormalized()
	sk.set_bone_pose_rotation(b, (pb.inverse() * new_basis.orthonormalized()).get_rotation_quaternion())
	_gc.clear()

func _arm(side: String, target_world: Vector3) -> void:
	var S := _gpos(side + "Arm")
	var T := _to_sk(target_world)
	var L1: float = _len[side + "Arm"]; var L2: float = _len[side + "ForeArm"]
	var d := T - S
	var dist := clampf(d.length(), absf(L1 - L2) + 0.001, L1 + L2 - 0.001)
	var dir := d.normalized()
	var x := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, L1 * L1 - x * x))
	var out := _dir_to_sk(global_basis.x * (1.0 if side == "Left" else -1.0))
	var pole := (_dir_to_sk(Vector3.DOWN) * 1.0 + out * 0.35 + _dir_to_sk(-global_basis.z) * 0.5).normalized()
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var E := S + dir * x + perp * h
	_point(side + "Arm", E - S)
	_point(side + "ForeArm", (S + dir * dist) - E)
	# the hand continues the forearm, bent a little down
	var fdir := ((S + dir * dist) - E).normalized()
	_point(side + "Hand", (fdir + _dir_to_sk(Vector3.DOWN) * 0.35).normalized())

func _process(delta: float) -> void:
	if sk == null: return
	t += delta
	var fwd := _dir_to_sk(global_basis.z)          # the model faces +Z, towards the table
	var up := _dir_to_sk(Vector3.UP)
	sk.reset_bone_poses()
	_gc.clear()
	# legs: thighs forward under the table, shins down
	for side in ["Left", "Right"]:
		_point(side + "UpLeg", (fwd + up * -0.15).normalized())
		_point(side + "Leg", (-up + fwd * 0.1).normalized())
	# spine: sitting up, leaning over the table a little (and more while reaching)
	var breathe := sin(t * 1.3 + phase) * 0.01
	var l := 0.12 + lean + breathe
	_point("Spine", (up * cos(l) + fwd * sin(l)).normalized())
	_point("Spine1", (up * cos(l * 1.2) + fwd * sin(l * 1.2)).normalized())
	_point("Spine2", (up * cos(l * 1.3) + fwd * sin(l * 1.3)).normalized())
	# head: looks at the table, turns slowly
	var to_look := _dir_to_sk(look_at_point - world_of("Neck"))
	var turn := sin(t * 0.37 + phase) * 0.12
	var head_dir := (up * 0.75 + (to_look + _dir_to_sk(global_basis.x) * turn).normalized() * 0.45).normalized()
	_point("Neck", (up * 0.9 + fwd * 0.25).normalized())
	_point("Head", head_dir)
	_point("LeftShoulder", _rest_dir["LeftShoulder"])
	_point("RightShoulder", _rest_dir["RightShoulder"])
	_arm("Left", left_target)
	_arm("Right", right_target)

## where the fan is held, in world space (in front of the chest, above the table)
func fan_home() -> Transform3D:
	var chest := global_position + global_basis.z * 0.36 + Vector3.UP * (seat_height + 0.42)
	var b := global_basis.rotated(global_basis.x, -0.55)    # tilted back towards the player
	return Transform3D(b, chest)
func rest_targets() -> Array:
	var f := fan_home()
	return [f.origin + global_basis.x * 0.06 + Vector3.DOWN * 0.07, f.origin - global_basis.x * 0.07 + Vector3.DOWN * 0.06]
