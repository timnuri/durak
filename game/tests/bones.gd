extends SceneTree
func _init():
	var m = load("res://models/Xbot.glb").instantiate()
	get_root().add_child(m)
	await process_frame
	var sk: Skeleton3D = m.find_child("Skeleton3D", true, false)
	if sk == null:
		for c in m.get_children(): print(c.name, c.get_class())
	print("sk global ", sk.global_transform)
	for n in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftHand", "mixamorig_LeftToeBase", "mixamorig_LeftEye"]:
		var i := sk.find_bone(n)
		if i >= 0: print(n, " ", sk.global_transform * sk.get_bone_global_rest(i).origin)
	quit()
