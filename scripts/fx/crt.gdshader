shader_type canvas_item;
// Full-screen CRT / arcade pass: barrel warp, scanlines, aperture grille,
// chromatic aberration and a vignette. `fever` is driven by the combo level so
// the whole screen visibly heats up during a streak.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float enabled : hint_range(0.0, 1.0) = 1.0;
uniform float fever : hint_range(0.0, 1.0) = 0.0;
// Curvature defaults to 0: the pass is drawn over the live UI, so warping the
// image would move pixels out from under the cursor and the player's finger.
// Raise it only for a non-interactive showcase build.
uniform float warp_amount : hint_range(0.0, 0.4) = 0.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.10;
uniform float aberration : hint_range(0.0, 6.0) = 0.35;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;
uniform float grille_strength : hint_range(0.0, 1.0) = 0.05;
uniform float scanline_count = 620.0;
uniform float time_scale = 1.0;

vec2 barrel(vec2 uv, float amount) {
	vec2 cc = uv - 0.5;
	float dist = dot(cc, cc);
	return uv + cc * dist * amount;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float warp = warp_amount * enabled;
	vec2 wuv = barrel(uv, warp);

	// Outside the tube: black bezel.
	if (wuv.x < 0.0 || wuv.x > 1.0 || wuv.y < 0.0 || wuv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		float ab = (aberration + fever * 0.9) * enabled / max(SCREEN_PIXEL_SIZE.x, 0.0001) * SCREEN_PIXEL_SIZE.x;
		vec2 dir = normalize(wuv - vec2(0.5)) * SCREEN_PIXEL_SIZE * ab;
		vec3 col;
		col.r = texture(screen_tex, wuv + dir).r;
		col.g = texture(screen_tex, wuv).g;
		col.b = texture(screen_tex, wuv - dir).b;

		// Horizontal scanlines with a slow roll.
		float roll = TIME * time_scale * 0.35;
		float scan = sin((wuv.y + roll) * scanline_count * 3.14159);
		col *= 1.0 - scanline_strength * enabled * (0.5 + 0.5 * scan);

		// Vertical aperture grille.
		float grille = sin(wuv.x / max(SCREEN_PIXEL_SIZE.x, 0.0001) * 3.14159 * 0.5);
		col *= 1.0 - grille_strength * enabled * (0.5 + 0.5 * grille);

		// Fever pushes saturation and a red-hot bias.
		if (fever > 0.001) {
			float lum = dot(col, vec3(0.299, 0.587, 0.114));
			col = mix(col, mix(vec3(lum), col, 1.0 + fever * 0.7), 1.0);
			col.r += fever * 0.03 * (0.5 + 0.5 * sin(TIME * 9.0));
		}

		// Vignette.
		vec2 vc = wuv - 0.5;
		float vig = 1.0 - dot(vc, vc) * (vignette_strength + fever * 0.35) * enabled;
		col *= clamp(vig, 0.0, 1.0);

		COLOR = vec4(col, 1.0);
	}
}
