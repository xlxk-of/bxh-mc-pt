class_name CardIcon
extends Control
## Renders a card/item as its actual 3D model on a slowly turning turntable,
## inside a transparent SubViewport, with a rarity-tinted glow behind it.
##
## Falls back to the pre-rendered 240px turntable PNG strip when a model is
## missing or when `prefer_frames` is set (cheap mode for long shop lists on
## low-end phones).

signal pressed(icon: CardIcon)
signal long_pressed(icon: CardIcon)

@export var entry_name := ""
@export var rarity := "Common"
@export var prefer_frames := false
@export var spin_speed := 0.55
@export var interactive := true

var index := -1
var payload: Variant = null
var dimmed := false:
	set(value):
		dimmed = value
		modulate.a = 0.45 if value else 1.0

var _glow: TextureRect
var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _spin_radius := 1.0
var _half_height := 1.0
var _sprite: AnimatedSprite2D
var _empty_label: Label
var _press_time := 0.0
var _pressing := false
var _long_fired := false
var _hover := 0.0
var _mouse_in := false
var _built := false
var _tilt := Vector2.ZERO
var _base_spin := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	mouse_entered.connect(func(): _mouse_in = true)
	mouse_exited.connect(func(): _mouse_in = false)
	_build()
	set_process(true)


func _build() -> void:
	_glow = TextureRect.new()
	_glow.texture = _radial_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.offset_left = -12
	_glow.offset_top = -12
	_glow.offset_right = 12
	_glow.offset_bottom = 12
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	_empty_label = UIKit.make_label("", "tiny", Cfg.GRAY)
	_empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_empty_label)

	_built = true
	set_entry(entry_name, rarity)


func _radial_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	return tex


# ------------------------------------------------------------------- content
func set_entry(new_name: String, new_rarity := "") -> void:
	entry_name = new_name
	if not new_rarity.is_empty():
		rarity = new_rarity
	# Callers often configure the icon before it enters the tree; _build()
	# replays the latest values once the children exist.
	if not _built:
		return
	_clear_visual()

	if entry_name.is_empty():
		_glow.visible = false
		_empty_label.visible = true
		_empty_label.text = ""
		return

	_glow.visible = true
	_empty_label.visible = false
	var key := Cards.asset_key(entry_name)
	var scene: PackedScene = null if prefer_frames else Cards.model_scene(key)
	if scene != null:
		_build_model_view(scene)
	else:
		_build_frame_view(key)
	_update_glow()


func _clear_visual() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.get_parent().queue_free()
		_viewport = null
		_pivot = null
		_camera = null
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.get_parent().queue_free()
		_sprite = null


func _build_model_view(scene: PackedScene) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Every icon is a separate render target, and 4x MSAA quadruples what each
	# one costs. A phone browser has a hard ceiling on that and drops the whole
	# tab when it is hit, which is not a trade worth making for smoother edges
	# on a 90px turntable.
	_viewport.msaa_3d = Viewport.MSAA_2X if Layout.touch_primary else Viewport.MSAA_4X
	container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.78)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 2.1
	key_light.rotation_degrees = Vector3(-38, -35, 0)
	_viewport.add_child(key_light)

	var rim := OmniLight3D.new()
	rim.light_color = Cfg.rarity_color(rarity).lightened(0.3)
	rim.light_energy = 3.2
	rim.omni_range = 8.0
	rim.position = Vector3(-1.6, 0.6, -2.0)
	rim.name = "RimLight"
	_viewport.add_child(rim)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var model := scene.instantiate()
	_pivot.add_child(model)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_fit_model(model)
	# The ortho box depends on the viewport's aspect, which is not known until
	# the container has been laid out.
	container.resized.connect(_frame_camera)


const PIVOT_TILT_DEG := -8.0
## How far the hover parallax may tip the model past its resting pose. Only a
## mouse can trigger it, so only a mouse pays for the headroom.
const HOVER_TILT_MAX := 0.45
const FRAME_MARGIN := 1.06


## Centre the model on the pivot and record the silhouette it sweeps out, so the
## camera can be framed now and re-framed whenever the icon is resized.
func _fit_model(model: Node) -> void:
	var aabb := _merged_aabb(model)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	model.position = -aabb.get_center()
	# The model spins on Y, so the widest it ever gets is the XZ diagonal --
	# framing to the X extent alone clips every model as it turns side-on.
	_spin_radius = maxf(Vector2(aabb.size.x, aabb.size.z).length() * 0.5, 0.001)
	_half_height = maxf(aabb.size.y * 0.5, 0.001)
	_pivot.rotation.x = deg_to_rad(PIVOT_TILT_DEG)
	_frame_camera()


## Sizes the ortho box to the model's worst-case projected silhouette. The old
## code used 0.81 * the bounding-sphere radius, which is smaller than the model
## itself whenever a shape is tall and thin, so those models were cropped.
func _frame_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var dist: float = maxf(_spin_radius, _half_height) * 4.0
	# Camera elevation plus the pivot's own tilt: both push the model's height
	# into the frame at an angle, so both count toward how tall it reads.
	var pitch := atan2(dist * 0.14, dist) + absf(deg_to_rad(PIVOT_TILT_DEG))
	if interactive and not Layout.touch_primary:
		pitch += HOVER_TILT_MAX
	var half_h: float = _half_height * cos(pitch) + _spin_radius * sin(pitch)
	var half_w := _spin_radius

	var vp: Vector2 = _viewport.size if _viewport != null and is_instance_valid(_viewport) else Vector2.ZERO
	var aspect: float = vp.x / vp.y if vp.x > 0.0 and vp.y > 0.0 else 1.0
	# Camera3D.size is the *vertical* extent (KEEP_HEIGHT), so a viewport
	# narrower than it is tall needs the box grown to fit the width.
	var half: float = maxf(half_h, half_w / maxf(aspect, 0.01))

	_camera.size = half * 2.0 * FRAME_MARGIN
	_camera.position = Vector3(0, dist * 0.14, dist)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.near = 0.01
	_camera.far = dist * 4.0


## Bounding box of every mesh under `node`, in `node`'s own local space.
##
## Each child's box is transformed by that child's transform exactly once. The
## previous version applied a MeshInstance3D's transform twice -- once when
## building its own box and again on the way out -- so any glb whose meshes are
## not at the origin was framed against a box in the wrong place.
func _merged_aabb(node: Node) -> AABB:
	var out := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out = (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var sub := _merged_aabb(child)
		if sub.size == Vector3.ZERO:
			continue
		if child is Node3D:
			sub = (child as Node3D).transform * sub
		out = sub if not found else out.merge(sub)
		found = true
	return out


func _build_frame_view(key: String) -> void:
	var frames := Cards.frames(key)
	if frames == null:
		_empty_label.visible = true
		_empty_label.text = entry_name.substr(0, 2).to_upper()
		return
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.centered = true
	_sprite.play("default")
	holder.add_child(_sprite)
	holder.resized.connect(_layout_sprite)
	_layout_sprite()


func _layout_sprite() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var tex := _sprite.sprite_frames.get_frame_texture("default", 0)
	if tex == null:
		return
	var target: float = minf(size.x, size.y)
	_sprite.scale = Vector2.ONE * (target / maxf(tex.get_width(), 1.0))
	_sprite.position = size * 0.5


func _update_glow() -> void:
	if _glow == null:
		return
	var col := Cfg.rarity_color(rarity)
	var strength := 0.35
	match rarity:
		"Ultra": strength = 0.5
		"Exotic": strength = 0.75
		"Cosmic": strength = 0.95
	_glow.modulate = Color(col.r, col.g, col.b, strength)


# ------------------------------------------------------------------- process
func _process(delta: float) -> void:
	if entry_name.is_empty():
		return
	if rarity == "Cosmic":
		_update_glow()

	var target_hover := 1.0 if (interactive and _mouse_in) else 0.0
	_hover = lerpf(_hover, target_hover, 1.0 - pow(0.001, delta))

	if _glow and _glow.visible:
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.003)
		_glow.scale = Vector2.ONE * (pulse + _hover * 0.12)
		_glow.position = (size - size * _glow.scale) * 0.5

	if _pivot != null and is_instance_valid(_pivot):
		_base_spin += delta * spin_speed * (1.0 + _hover * 1.8)
		# Hovering tilts the model toward the pointer for a tactile parallax.
		var want := Vector2.ZERO
		if interactive and _mouse_in:
			var local := get_local_mouse_position() / maxf(size.x, 1.0) - Vector2(0.5, 0.5)
			want = local.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
		_tilt = _tilt.lerp(want, 1.0 - pow(0.002, delta))
		_pivot.rotation.y = _base_spin + _tilt.x * 0.9
		# Bounded by HOVER_TILT_MAX, which is the headroom _frame_camera left.
		_pivot.rotation.x = deg_to_rad(PIVOT_TILT_DEG) - _tilt.y * (HOVER_TILT_MAX * 2.0)

	if _pressing:
		_press_time += delta
		if not _long_fired and _press_time >= Cfg.LONG_PRESS_TIME:
			_long_fired = true
			long_pressed.emit(self)
			if SaveGame.haptics and Layout.touch_primary:
				Input.vibrate_handheld(18)


func _gui_input(event: InputEvent) -> void:
	if not interactive or entry_name.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_time = 0.0
				_long_fired = false
			else:
				if _pressing and not _long_fired:
					pressed.emit(self)
				_pressing = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Desktop parity for the touch long-press.
			long_pressed.emit(self)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_pressing = false
		_mouse_in = false
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		# A hidden icon keeps its render target either way, but there is no
		# reason to keep drawing into it behind a full-screen menu.
		set_render_active(is_visible_in_tree())
	elif what == NOTIFICATION_SCROLL_BEGIN:
		# A finger drag on top of this icon is scrolling the list it sits in, not
		# tapping it. Let go without firing the tap or the hold-to-sell.
		_pressing = false
		_long_fired = false


## Visible-only rendering keeps a shop full of models off the GPU budget.
func set_render_active(active: bool) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _sprite != null and is_instance_valid(_sprite):
		if active:
			_sprite.play("default")
		else:
			_sprite.pause()


## Celebratory kick used when a card's effect fires.
func celebrate() -> void:
	UIKit.pop(self, 1.28, 0.3)
	if _glow:
		var t := create_tween()
		var col := Cfg.rarity_color(rarity)
		t.tween_property(_glow, "modulate", Color(1, 1, 1, 1.0), 0.08)
		t.tween_property(_glow, "modulate", Color(col.r, col.g, col.b, 0.35), 0.4)
