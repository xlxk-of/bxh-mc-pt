class_name LevelBackground
extends Control
## A real 3D environment behind the board instead of a flat fill. Each round
## tier gets its own biome, and the whole scene reacts to combo fever: fog
## thickens, emissives brighten, embers pick up.
##
## Rendered into a SubViewport at a reduced scale so it stays cheap on mobile.

const THEMES := {
	"limbo": {
		"sky_top": Color(0.06, 0.06, 0.16), "sky_horizon": Color(0.16, 0.13, 0.32),
		"fog": Color(0.13, 0.12, 0.28), "emissive": Color(0.45, 0.55, 1.0),
		"mote": Color(0.65, 0.75, 1.0), "gravity": 0.6, "title": "Limbo",
	},
	"abyss": {
		"sky_top": Color(0.02, 0.07, 0.09), "sky_horizon": Color(0.05, 0.22, 0.24),
		"fog": Color(0.05, 0.17, 0.19), "emissive": Color(0.2, 0.95, 0.85),
		"mote": Color(0.4, 1.0, 0.9), "gravity": 0.35, "title": "The Abyss",
	},
	"furnace": {
		"sky_top": Color(0.14, 0.02, 0.02), "sky_horizon": Color(0.45, 0.10, 0.02),
		"fog": Color(0.28, 0.06, 0.03), "emissive": Color(1.0, 0.42, 0.10),
		"mote": Color(1.0, 0.6, 0.2), "gravity": -1.4, "title": "The Furnace",
	},
	"cosmic": {
		"sky_top": Color(0.07, 0.02, 0.14), "sky_horizon": Color(0.34, 0.06, 0.35),
		"fog": Color(0.18, 0.05, 0.26), "emissive": Color(0.95, 0.35, 0.95),
		"mote": Color(1.0, 0.6, 1.0), "gravity": 0.15, "title": "Cosmic Static",
	},
}

var current_theme := "limbo"

var _viewport: SubViewport
var _container: SubViewportContainer
var _camera: Camera3D
var _env: Environment
var _sky_material: ProceduralSkyMaterial
var _pillars: Array[MeshInstance3D] = []
var _pillar_material: StandardMaterial3D
var _motes: GPUParticles3D
var _mote_material: ParticleProcessMaterial
var _time := 0.0
var _fever := 0.0


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Layout.layout_changed.connect(func():
		UIKit.fill_viewport(self)
		_resize_viewport())
	Juice.fever_changed.connect(func(level: int, _s: int): _fever = level / 4.0)
	set_process(true)


func _build() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	_container = container
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)

	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_energy_multiplier = 0.85
	_sky_material.ground_energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = _sky_material

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.55
	_env.fog_enabled = true
	_env.fog_density = 0.02
	_env.fog_sky_affect = 0.4
	_env.glow_enabled = true
	_env.glow_intensity = 1.3
	_env.glow_bloom = 0.22
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.55
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.shadow_enabled = false
	_viewport.add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.position = Vector3(0, 2.4, 12.0)
	_camera.rotation_degrees = Vector3(-6, 0, 0)
	_camera.far = 220.0
	_viewport.add_child(_camera)

	_build_pillars()
	_build_motes()
	apply_theme("limbo", true)
	_resize_viewport()


## Two receding rows of monoliths frame the board and sell the depth.
func _build_pillars() -> void:
	_pillar_material = StandardMaterial3D.new()
	_pillar_material.albedo_color = Color(0.05, 0.05, 0.08)
	_pillar_material.roughness = 0.85
	_pillar_material.emission_enabled = true
	_pillar_material.emission_energy_multiplier = 0.55

	var rng := RandomNumberGenerator.new()
	rng.seed = 20250811
	for i in 26:
		var mesh := BoxMesh.new()
		var w := rng.randf_range(1.1, 2.6)
		var h := rng.randf_range(5.0, 22.0)
		mesh.size = Vector3(w, h, w)
		mesh.material = _pillar_material

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var side: float = -1.0 if i % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var depth: float = -6.0 - float(i / 2) * 7.0
		mi.position = Vector3(
			side * rng.randf_range(6.5, 15.0),
			-h * 0.5 + rng.randf_range(-2.0, 2.5),
			depth + rng.randf_range(-2.0, 2.0))
		mi.rotation.y = rng.randf_range(-0.5, 0.5)
		mi.set_meta("bob", rng.randf_range(0.0, TAU))
		mi.set_meta("bob_speed", rng.randf_range(0.15, 0.45))
		mi.set_meta("base_y", mi.position.y)
		_viewport.add_child(mi)
		_pillars.append(mi)


func _build_motes() -> void:
	_motes = GPUParticles3D.new()
	_motes.amount = 260
	_motes.lifetime = 9.0
	_motes.preprocess = 6.0
	_motes.visibility_aabb = AABB(Vector3(-30, -25, -110), Vector3(60, 60, 130))

	_mote_material = ParticleProcessMaterial.new()
	_mote_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mote_material.emission_box_extents = Vector3(22, 14, 55)
	_mote_material.direction = Vector3(0, 1, 0)
	_mote_material.spread = 35.0
	_mote_material.gravity = Vector3(0, 0.6, 0)
	_mote_material.initial_velocity_min = 0.15
	_mote_material.initial_velocity_max = 0.8
	_mote_material.scale_min = 0.03
	_mote_material.scale_max = 0.12
	_motes.process_material = _mote_material

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.75)
	quad.material = mat
	_motes.draw_pass_1 = quad
	_motes.position = Vector3(0, -4, -30)
	_viewport.add_child(_motes)


## The container drives the viewport size; `stretch_shrink` renders the scene
## at a fraction of screen resolution and upscales, which is where the mobile
## savings come from.
func _resize_viewport() -> void:
	if _container == null:
		return
	_container.stretch_shrink = 2 if Layout.is_phone() else 1


# ------------------------------------------------------------------- themes
## Pick the biome from the round number: boss rounds burn, later rounds go cosmic.
func theme_for_round(round_count: int) -> String:
	if round_count % 5 == 0:
		return "furnace"
	if round_count >= 15:
		return "cosmic"
	if round_count >= 6:
		return "abyss"
	return "limbo"


func apply_theme(theme_name: String, instant := false) -> void:
	if not THEMES.has(theme_name):
		return
	if theme_name == current_theme and not instant:
		return
	current_theme = theme_name
	var t: Dictionary = THEMES[theme_name]

	if instant:
		_set_theme_colors(t, 1.0)
		return
	# Cross-fade the palette over ~0.9s so round transitions feel like travel.
	var from := {
		"sky_top": _sky_material.sky_top_color,
		"sky_horizon": _sky_material.sky_horizon_color,
		"fog": _env.fog_light_color,
		"emissive": _pillar_material.emission,
		"mote": _mote_material.color,
	}
	var tween := create_tween()
	tween.tween_method(func(w: float):
		_sky_material.sky_top_color = (from["sky_top"] as Color).lerp(t["sky_top"], w)
		_sky_material.sky_horizon_color = (from["sky_horizon"] as Color).lerp(t["sky_horizon"], w)
		_env.fog_light_color = (from["fog"] as Color).lerp(t["fog"], w)
		_pillar_material.emission = (from["emissive"] as Color).lerp(t["emissive"], w)
		_mote_material.color = (from["mote"] as Color).lerp(t["mote"], w)
		_mote_material.gravity = Vector3(0, lerpf(_mote_material.gravity.y, t["gravity"], w), 0)
	, 0.0, 1.0, 0.9)


func _set_theme_colors(t: Dictionary, _w: float) -> void:
	_sky_material.sky_top_color = t["sky_top"]
	_sky_material.sky_horizon_color = t["sky_horizon"]
	_sky_material.ground_bottom_color = (t["sky_top"] as Color).darkened(0.4)
	_sky_material.ground_horizon_color = t["sky_horizon"]
	_env.fog_light_color = t["fog"]
	_pillar_material.emission = t["emissive"]
	_mote_material.color = t["mote"]
	_mote_material.gravity = Vector3(0, t["gravity"], 0)


func theme_title() -> String:
	return THEMES[current_theme].get("title", "")


# ------------------------------------------------------------------ process
func _process(delta: float) -> void:
	_time += delta
	if _camera:
		# Slow drift so the scene never feels like a static wallpaper.
		_camera.position.x = sin(_time * 0.12) * 1.3
		_camera.position.y = 2.4 + sin(_time * 0.19) * 0.5
		_camera.rotation.y = sin(_time * 0.08) * 0.05
	for mi in _pillars:
		var base: float = mi.get_meta("base_y")
		mi.position.y = base + sin(_time * float(mi.get_meta("bob_speed")) + float(mi.get_meta("bob"))) * 0.5

	# Fever pushes bloom, fog and ember count.
	if _env:
		_env.glow_intensity = lerpf(1.3, 2.6, _fever)
		_env.fog_density = lerpf(0.02, 0.055, _fever)
	if _pillar_material:
		_pillar_material.emission_energy_multiplier = lerpf(0.55, 2.4, _fever)
	if _motes:
		_motes.amount_ratio = lerpf(0.6, 1.0, _fever)
