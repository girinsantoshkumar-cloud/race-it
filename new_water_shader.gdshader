shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, shadows_disabled;

#define SCENE_DEPTH
//wave design _last_consistent_
uniform vec4 wave_a = vec4(1.0, 0.25, 0.14, 62.0);
uniform vec4 wave_b = vec4(-0.45, 0.9, 0.10, 34.0);
uniform vec4 wave_c = vec4(-0.9, -0.35, 0.07, 19.0);
uniform float wave_speed = 0.22;

//color defined _clear_water_color_
uniform vec3 shallow_color : source_color = vec3(0.10, 0.45, 0.50);
uniform vec3 deep_color : source_color = vec3(0.01, 0.08, 0.18);
uniform vec3 seabed_color : source_color = vec3(0.30, 0.26, 0.18);
uniform vec3 foam_color : source_color = vec3(1.0);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.72, 0.90);
uniform float absorption = 0.20;
uniform float foam_width = 2.0;
uniform float foam_amount = 1.0;

uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float tiling = 0.08;
uniform float flow_speed = 0.006;

#ifdef SCENE_DEPTH
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
#else
uniform sampler2D depth_mask : hint_default_white, filter_linear, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform float mask_size = 512.0;
uniform float mask_res = 512.0;
uniform float max_depth = 20.0;
varying vec2 mask_uv;
#endif

varying vec4 ripple_uv;   // xy = layer 1, zw = layer 2 _already_animated_
varying float crest;
varying float dist;

void gerstner(vec4 w, vec2 p, float tt, inout vec3 off, inout vec3 t, inout vec3 b) {
	vec2 d = normalize(w.xy);
	float k = 6.28318 / w.w;
	float f = k * (dot(d, p) - sqrt(9.8 / k) * tt);
	float s = sin(f);
	float co = cos(f);
	float a = w.z / k;
	t += vec3(-d.x * d.x * w.z * s, d.x * w.z * co, -d.x * d.y * w.z * s);
	b += vec3(-d.x * d.y * w.z * s, d.y * w.z * co, -d.y * d.y * w.z * s);
	off += vec3(d.x * a * co, a * s, d.y * a * co);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float tt = TIME * wave_speed;
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, 1.0);
	vec3 off = vec3(0.0);
	gerstner(wave_a, p, tt, off, t, b);
	gerstner(wave_b, p, tt, off, t, b);
	gerstner(wave_c, p, tt, off, t, b);
	VERTEX += off;
	crest = clamp(off.y * 0.3 + 0.5, 0.0, 1.0);
	NORMAL = normalize(cross(b, t));

	vec2 base = p * tiling;
	float fs = TIME * flow_speed;
	ripple_uv = vec4(base + vec2(0.8, 0.35) * fs, base * 1.9 + vec2(-0.4, -0.9) * fs);

	vec3 vv = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dist = clamp(dot(vv, vv) * 0.00004, 0.0, 1.0);
#ifndef SCENE_DEPTH
	mask_uv = (p - mask_origin) / mask_size * ((mask_res - 1.0) / mask_res) + 0.5 / mask_res;
#endif
}

void fragment() {
#ifdef SCENE_DEPTH
	float dz = texture(depth_tex, SCREEN_UV).r;
#ifdef COMPAT_DEPTH
	dz = dz * 2.0 - 1.0;
#endif
	float vz = (INV_PROJECTION_MATRIX[2][2] * dz + INV_PROJECTION_MATRIX[3][2]) / (INV_PROJECTION_MATRIX[2][3] * dz + INV_PROJECTION_MATRIX[3][3]);
	float depth = max(-vz + VERTEX.z, 0.0);
#else
	float depth = texture(depth_mask, mask_uv).r * max_depth;
#endif

	// Ripples (second layer skipped far away, where it is invisible)
	vec3 n1 = texture(normal_map, ripple_uv.xy).rgb;
	vec3 nm = n1;
	if (dist < 0.6) {
		nm = mix(n1, texture(normal_map, ripple_uv.zw).rgb, 0.5);
	}
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(0.65, 0.15, dist);

	// Colour
	float fade = 1.0 - exp(-depth * absorption);
	vec3 col = mix(mix(seabed_color * 0.7 + shallow_color * 0.3, shallow_color, smoothstep(0.0, 0.35, fade)), deep_color, fade);
	col += shallow_color * smoothstep(0.55, 0.95, crest) * 0.22;

	// Fresnel sky sheen
	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, sky_tint, fr * fr * fr * 0.55);

	// Foam, only computed where it can be visible
	float foam = 0.0;
	if (depth < foam_width || crest > 0.78) {
		float lap = 0.6 + 0.4 * sin(TIME * 1.1 + n1.g * 7.0 - depth * 1.5);
		float band = 1.0 - smoothstep(0.0, foam_width * lap, depth);
		float edge = 1.0 - smoothstep(0.0, 0.4, depth);
		float caps = smoothstep(0.78, 0.98, crest) * smoothstep(0.4, 0.7, n1.g) * 0.5;
		foam = clamp((band * (0.55 + 0.45 * smoothstep(0.3, 0.7, n1.r)) + edge * 0.6 + caps) * foam_amount, 0.0, 1.0);
	}

	ALBEDO = mix(mix(col, foam_color, foam), sky_tint, dist * 0.35);
	EMISSION = mix(col * 0.22, foam_color * 0.4, foam);
	ROUGHNESS = mix(0.05, 0.75, foam);
	SPECULAR = 0.7;
}