class_name UIKit
extends RefCounted
## Shared visual language for every screen: fonts, styleboxes, buttons, panels.
## Built in code so the whole UI can re-flow for phone / tablet / desktop
## without maintaining parallel scene layouts.

## Font roles:
##   display - Warpixes, the chunky arcade face used for titles and buttons.
##   numeric - Sixtyfour Convergence, used for score / money / combo readouts.
##   ui      - the engine default sans, used for body copy and card text.
##
## PixelGamer is deliberately absent: the bundled file was a demo-licensed build
## that substitutes a watermark glyph for every digit and punctuation mark.
const FONT_DISPLAY := "res://assets/fonts/Warpixes.ttf"
const FONT_NUMERIC := "res://assets/fonts/SixtyfourConvergence.ttf"

static var _fonts := {}
static var _theme: Theme = null


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := ""
	match kind:
		"display", "title": path = FONT_DISPLAY
		"numeric": path = FONT_NUMERIC
	var f: Font = ThemeDB.fallback_font
	if not path.is_empty() and ResourceLoader.exists(path):
		f = load(path)
	_fonts[kind] = f
	return f


## Full-rect anchors do not resolve for a Control parented to a CanvasLayer --
## its parent area reads as zero, so the anchor pass stomps the size back to
## (0, 0) right after _ready(). Pinning the anchors to the top-left corner makes
## the opposite anchors equal, which leaves an explicit size alone; Layout then
## re-applies this on every viewport resize.
static func fill_viewport(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	# Layout.logical_size() is authoritative: get_viewport_rect() still reports
	# the previous frame's canvas size right after content_scale_factor changes.
	var vp := Layout.logical_size()
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = vp


# ------------------------------------------------------------------ styles
static func panel_style(fill := Cfg.PANEL_FILL, border := Cfg.PANEL_BORDER,
		radius := 14, border_width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(fill.r, fill.g, fill.b, 0.92)
	sb.border_color = Color(border.r, border.g, border.b, 0.7)
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func button_style(fill: Color, accent: Color, radius := 10,
		accent_bar := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_border_width_all(1)
	if accent_bar:
		sb.border_width_left = 4
		sb.border_color = accent
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## A styled Button that grows and glows on hover/focus, echoing the pygame UI.
static func make_button(text: String, accent := Cfg.PANEL_ACCENT, size_kind := "body") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = Layout.touch_size()
	b.add_theme_font_override("font", font("display"))
	# Buttons never use the body-copy tiers: a label can be 16px, a tap target
	# label should not be.
	var label_size := font_size(size_kind)
	if Layout.touch_primary:
		label_size = maxi(label_size, font_size("body"))
	b.add_theme_font_size_override("font_size", label_size)
	b.add_theme_color_override("font_color", Cfg.WHITE)
	b.add_theme_color_override("font_hover_color", Cfg.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_focus_color", Cfg.WHITE)
	b.add_theme_stylebox_override("normal", button_style(Cfg.BUTTON_FILL, accent))
	var hover := button_style(Cfg.BUTTON_HOVER, accent)
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
	hover.shadow_size = 12
	b.add_theme_stylebox_override("hover", hover)
	var pressed := button_style(Cfg.BUTTON_HOVER.darkened(0.25), accent)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	var disabled := button_style(Cfg.BUTTON_FILL.darkened(0.4), Cfg.GRAY)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_disabled_color", Cfg.GRAY)
	b.pressed.connect(func(): Audio.play(Cfg.SFX_UI_CLICK, 0.8))
	return b


static func make_panel(fill := Cfg.PANEL_FILL, accent := Cfg.PANEL_ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(fill, accent))
	return p


## Godot's stock HSlider is a 4px hairline with a handle a few pixels across --
## fine with a mouse, unhittable with a thumb, and the single biggest reason the
## settings screen read as a desktop panel on a phone. This one is sized off the
## same tap-target metric as buttons.
static func make_slider(value: float, accent := Cfg.ACCENT_PRIMARY,
		low := 0.0, high := 1.0, step := 0.01) -> HSlider:
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track: float = maxf(12.0, Layout.touch_size() * 0.28)
	var knob: float = maxf(26.0, Layout.touch_size() * 0.62)
	s.custom_minimum_size.y = maxf(Layout.touch_size(), knob + 8.0)
	s.add_theme_stylebox_override("slider", bar_style(Color(1, 1, 1, 0.13), track))
	var filled := bar_style(accent, track)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", bar_style(accent.lightened(0.2), track))
	var tex := circle_texture(int(knob), Cfg.WHITE, accent)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", circle_texture(int(knob), accent.lightened(0.45), Cfg.WHITE))
	s.add_theme_icon_override("grabber_disabled", circle_texture(int(knob), Cfg.GRAY, Cfg.GRAY))
	return s


## A rounded bar of a given thickness. Sliders derive their track height from the
## stylebox's own minimum size, which is what the content margins set here.
static func bar_style(color: Color, thickness: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(thickness * 0.5))
	sb.content_margin_top = thickness * 0.5
	sb.content_margin_bottom = thickness * 0.5
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	return sb


static var _circles := {}


## Slider knobs are theme *icons*, so they need a texture rather than a stylebox.
## Generated once per size/colour and cached; a phone only ever needs two.
static func circle_texture(diameter: int, fill: Color, ring: Color) -> Texture2D:
	diameter = maxi(10, diameter)
	var key := "%d|%s|%s" % [diameter, fill.to_html(), ring.to_html()]
	if _circles.has(key):
		return _circles[key]
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var radius := diameter * 0.5
	var edge: float = maxf(2.0, diameter * 0.18)
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			if d > radius:
				continue
			var col: Color = fill if d < radius - edge else ring
			# Feather the outermost pixel so the knob is a disc, not a cog.
			col.a *= clampf(radius - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_circles[key] = tex
	return tex


## Every tier scales by the same factor on touch, body copy included: the phone
## is handed more logical pixels than it has points, so an unscaled 13px caption
## renders at about 8pt. Scaling the whole ramp keeps the type hierarchy intact
## instead of squashing it from the bottom.
static func font_size(kind: String) -> int:
	var base := 19
	match kind:
		"tiny": base = 13
		"small": base = 16
		"body": base = 19
		"medium": base = 24
		"large": base = 34
		"huge": base = 52
		"title": base = 46
	return int(round(base * Layout.text_scale()))


static func make_label(text: String, kind := "body", color := Cfg.WHITE,
		font_kind := "ui") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_kind))
	l.add_theme_font_size_override("font_size", font_size(kind))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func make_number(text: String, kind := "medium", color := Cfg.WHITE) -> Label:
	var l := make_label(text, kind, color, "numeric")
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


static func make_title(text: String, kind := "title", color := Cfg.ACCENT_PRIMARY) -> Label:
	var l := make_label(text, kind, color, "display")
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


## Small caps section header with an accent rule underneath.
static func make_section(text: String, accent := Cfg.PANEL_ACCENT) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(make_label(text.to_upper(), "small", Cfg.TEXT_DIM, "display"))
	var rule := ColorRect.new()
	rule.color = accent
	rule.custom_minimum_size = Vector2(38, 2)
	v.add_child(rule)
	return v


static func spacer(height := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


## Full-rect dimmer used behind every modal / full-screen menu.
static func make_scrim(alpha := 0.82) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Rarity chip: coloured pill with the rarity name, cosmic animates via _process
## on the owning screen (call refresh_rarity_chip each frame for Cosmic).
static func make_rarity_chip(rarity: String) -> PanelContainer:
	var p := PanelContainer.new()
	var col := Cfg.rarity_color(rarity)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.28)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := make_label(rarity.to_upper(), "tiny", col.lightened(0.35))
	l.name = "RarityLabel"
	p.add_child(l)
	p.set_meta("rarity", rarity)
	return p


## Type chip: what the entry *is*, worn next to how rare it is. A card and an
## item at the same rarity cost the same and read the same in a shop row, but
## they compete for different slots, so the pair "(Exotic) (Card)" answers the
## only two questions a player has before reading the description.
static func make_type_chip(kind: String) -> PanelContainer:
	var col := type_color(kind)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(make_label(kind.to_upper(), "tiny", col.lightened(0.25)))
	return p


## Deliberately not rarity-tinted: the two chips sit side by side, and giving
## them the same colour would make the pair read as one long badge.
static func type_color(kind: String) -> Color:
	match kind.to_lower():
		"card": return Cfg.PANEL_ACCENT
		"item": return Cfg.CYAN
		"perk": return Cfg.MAGENTA
		"contract": return Cfg.ACCENT_DANGER
	return Cfg.GRAY


## Rarity and type as one row, in that order.
static func make_tag_row(rarity: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(make_rarity_chip(rarity))
	row.add_child(make_type_chip(kind))
	return row


static func refresh_rarity_chip(chip: PanelContainer) -> void:
	if chip == null or String(chip.get_meta("rarity", "")) != "Cosmic":
		return
	var col := Cfg.cosmic_color
	var sb: StyleBoxFlat = chip.get_theme_stylebox("panel")
	if sb:
		sb.bg_color = Color(col.r, col.g, col.b, 0.28)
		sb.border_color = col
	var l := chip.get_node_or_null("RarityLabel") as Label
	if l:
		l.add_theme_color_override("font_color", col.lightened(0.35))


## Applies the project-wide base theme to the tree root once.
static func install_theme(root: Window) -> void:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = font("ui")
		_theme.default_font_size = font_size("body")
		var scroll := StyleBoxFlat.new()
		scroll.bg_color = Color(1, 1, 1, 0.14)
		scroll.set_corner_radius_all(6)
		_theme.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
		_theme.set_stylebox("grabber", "VScrollBar", scroll)
		_theme.set_stylebox("grabber_highlight", "VScrollBar", scroll)
		_theme.set_stylebox("grabber_pressed", "VScrollBar", scroll)
	root.theme = _theme


## Pop a control briefly -- the standard "something happened here" tell.
static func pop(node: Control, strength := 1.12, time := 0.18) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2.ONE * strength, time * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, time * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
