extends SceneTree
func _init():
	var t = load("res://scripts/table3d.gd").new()
	get_root().add_child(t)
	await process_frame
	t.set_look({"theme": "day"})
	t.new_match(2, 0, 20, 19)
	for i in 5: await process_frame
	var p = t.people[1]
	print("person pos ", p.global_position, " basis.z ", p.global_basis.z)
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftHand"]:
		print(n, " ", p.world_of(n))
	print("targets ", p.left_target, p.right_target)
	quit()
