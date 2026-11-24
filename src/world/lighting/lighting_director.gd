class_name LightingDirector
extends Node
## Áp LightingPreset lên mặt trời, bầu trời, môi trường, đèn và VFX của level; chuyển cảnh mượt.
## Dev: phím F2 (action "cycle_lighting") để xoay vòng preset khi tinh chỉnh.
## Gameplay có thể gọi set_preset_by_name("Night") từ cutscene/trigger.

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var presets: Array[LightingPreset] = []
@export var start_index: int = 0
@export var transition_time: float = 2.0
## Material hoa để chỉnh petal_glow theo preset (tùy chọn).
@export var flower_material: ShaderMaterial
## Material nước để chỉnh water_tint / sky_sheen theo preset (tùy chọn).
@export var water_material: ShaderMaterial

var current_index: int = 0
var _values: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	if presets.is_empty():
		push_warning("LightingDirector: chưa có preset nào.")
		return
	# Environment/Sky là resource dùng chung → nhân bản để chỉnh runtime không ảnh hưởng file gốc.
	if world_environment and world_environment.environment:
		world_environment.environment = world_environment.environment.duplicate(true)
	current_index = clampi(start_index, 0, presets.size() - 1)
	# Dev/CI: "-- --lighting=Night" để khởi động thẳng với preset đó
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lighting="):
			var wanted := arg.trim_prefix("--lighting=")
			for i in presets.size():
				if presets[i].display_name.to_lower() == wanted.to_lower():
					current_index = i
	_values = presets[current_index].to_values()
	_apply(_values)
	get_tree().node_added.connect(_on_node_added)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cycle_lighting") and not presets.is_empty():
		set_preset((current_index + 1) % presets.size())
		get_viewport().set_input_as_handled()


func set_preset(index: int, duration: float = transition_time) -> void:
	if index < 0 or index >= presets.size():
		return
	current_index = index
	var from := _values.duplicate()
	var to := presets[index].to_values()
	EventBus.toast_requested.emit("Lighting: %s" % presets[index].display_name)
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		_values = to
		_apply(_values)
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(t: float) -> void: _blend_and_apply(from, to, t), 0.0, 1.0, duration)


func set_preset_by_name(preset_name: String, duration: float = transition_time) -> void:
	for i in presets.size():
		if presets[i].display_name == preset_name:
			set_preset(i, duration)
			return
	push_warning("LightingDirector: không có preset '%s'" % preset_name)


func _blend_and_apply(from: Dictionary, to: Dictionary, t: float) -> void:
	for key: String in to:
		_values[key] = lerp(from[key], to[key], t)
	_apply(_values)


func _apply(v: Dictionary) -> void:
	if sun:
		sun.light_color = v["sun_color"]
		sun.light_energy = v["sun_energy"]
		sun.rotation_degrees = v["sun_rotation"]

	var env := world_environment.environment if world_environment else null
	if env:
		env.ambient_light_color = v["ambient_color"]
		env.ambient_light_energy = v["ambient_energy"]
		env.fog_light_color = v["fog_color"]
		env.fog_density = v["fog_density"]
		env.volumetric_fog_density = v["volumetric_fog_density"]
		env.volumetric_fog_albedo = v["volumetric_fog_albedo"]
		env.tonemap_exposure = v["exposure"]
		env.glow_intensity = v["glow_intensity"]
		env.glow_bloom = v["glow_bloom"]
		env.adjustment_saturation = v["saturation"]
		env.adjustment_contrast = v["contrast"]
		var sky_material := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
		if sky_material:
			sky_material.sky_top_color = v["sky_top_color"]
			sky_material.sky_horizon_color = v["sky_horizon_color"]
			sky_material.ground_horizon_color = v["sky_horizon_color"]
			sky_material.ground_bottom_color = v["ground_bottom_color"]
			sky_material.sky_energy_multiplier = v["sky_energy"]

	for node in get_tree().get_nodes_in_group(&"lamps"):
		var lamp := node as Light3D
		if lamp:
			if not lamp.has_meta(&"base_energy"):
				lamp.set_meta(&"base_energy", lamp.light_energy)
			lamp.light_energy = float(lamp.get_meta(&"base_energy")) * float(v["lamp_energy"])

	for node in get_tree().get_nodes_in_group(&"ambient_motes"):
		if node.has_method(&"set_intensity"):
			node.call(&"set_intensity", v["motes_intensity"])

	if flower_material:
		flower_material.set_shader_parameter(&"petal_glow", v["flower_glow"])
	if water_material:
		water_material.set_shader_parameter(&"water_tint", v["water_tint"])
		water_material.set_shader_parameter(&"sky_sheen", v["water_sheen"])

	for node in get_tree().get_nodes_in_group(&"tinted_sprites"):
		_tint_sprite(node)


## Sprite nhân vật sinh ra sau (spawn / đổi màn) cũng nhận màu preset hiện tại.
func _on_node_added(node: Node) -> void:
	if node.is_in_group(&"tinted_sprites"):
		_tint_sprite(node)


func _tint_sprite(node: Node) -> void:
	var sprite := node as SpriteBase3D
	if sprite and _values.has("sprite_tint"):
		sprite.modulate = _values["sprite_tint"]
