extends SceneTree
## Bake mesh cây — bake-first, thay việc dựng TreeMeshBuilder lúc chạy.
##
## Chạy (sau khi sửa src/world/props/tree/tree_mesh_builder.gd):
##   <godot> --headless --path . --script res://tools/art/bake_trees.gd
## Ghi vào TreeMeshBuilder.BAKED_DIR, mỗi Variant × seed 0..BAKED_SEEDS-1:
##   <variant>_<seed>.res        mesh cây (thân + tán thẻ lá; material là tham chiếu ngoài .tres)
##   <variant>_<seed>_proxy.res  proxy bóng low-poly (SHADOWS_ONLY)
##   tree_proxy_material.tres    material chung của proxy (chỉ tạo khi chưa có)
## Deterministic (rng seed = hash(variant, seed)) → chạy lại ra file giống hệt.


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TreeMeshBuilder.BAKED_DIR)
	var t0 := Time.get_ticks_msec()
	var failed := false
	if not ResourceLoader.exists(TreeMeshBuilder.PROXY_MATERIAL_PATH):
		failed = not _save(TreeMeshBuilder.proxy_material(), TreeMeshBuilder.PROXY_MATERIAL_PATH)
	for variant: int in TreeMeshBuilder.Variant.values():
		for seed_value in TreeMeshBuilder.BAKED_SEEDS:
			var v := variant as TreeMeshBuilder.Variant
			failed = not _save(TreeMeshBuilder.build(v, seed_value),
					TreeMeshBuilder.baked_path(v, seed_value, false)) or failed
			failed = not _save(TreeMeshBuilder.build_shadow_proxy(v, seed_value),
					TreeMeshBuilder.baked_path(v, seed_value, true)) or failed
	print("[bake_trees] %d loài × %d seed, %d ms" % [TreeMeshBuilder.Variant.size(), TreeMeshBuilder.BAKED_SEEDS,
			Time.get_ticks_msec() - t0])
	quit(1 if failed else 0)


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("[bake_trees] lưu %s lỗi %s" % [path, error_string(err)])
		return false
	print("[bake_trees] %s" % path)
	return true
