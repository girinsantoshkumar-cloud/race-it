shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx, shadows_disabled, ambient_light_disabled;

uniform vec4 wave_a = vec4(1.0, 0.3, 0.25, 60.0);
uniform vec4 wave_b = vec4(0.6, 0.8, 0.20, 30.0);

uniform vec3 shallow_color : source_color = vec3(0.10, 0.62, 0.58);
uniform vec3 deep_color : source_color = vec3(0.01, 0.13, 0.26);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.82, 0.92);
uniform vec3 sky_zenith : source_color = vec3(0.25, 0.48, 0.80);
uniform float clarity = 0.09;
uniform float foam_width = 2.0;
uniform float foam_crest = 0.62;
uniform float reflection = 0.85;

uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float tiling = 0.05;
uniform float flow_speed = 0.015;

uniform sampler2D depth_mask : hint_default_white, filter_linear, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform float mask_size = 512.0;
uniform float mask_res = 256.0;
uniform float max_depth = 20.0;

varying vec2 ripple_uv;
varying vec2 mask_uv;
varying float crest;

vec3 gerstner(vec4 w, vec2 p, inout vec3 t, inout vec3 b) {
	vec2 d = normalize(w.xy);
	float k = 6.28318 / w.w;
	float c = sqrt(9.8 / k);
	float f = k * (dot(d, p) - c * TIME);
	float s = sin(f);
	float co = cos(f);
	float a = w.z / k;
	t += vec3(-d.x * d.x * w.z * s, d.x * w.z * co, -d.x * d.y * w.z * s);
	b += vec3(-d.x * d.y * w.z * s, d.y * w.z * co, -d.y * d.y * w.z * s);
	return vec3(d.x * a * co, a * s, d.y * a * co);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, 1.0);
	vec3 off = gerstner(wave_a, p, t, b);
	off += gerstner(wave_b, p, t, b);
	VERTEX += off;
	NORMAL = normalize(cross(b, t));
	crest = clamp(off.y * 0.16 + 0.5, 0.0, 1.0);
	ripple_uv = p * tiling;
	mask_uv = (p - mask_origin) / mask_size * ((mask_res - 1.0) / mask_res) + 0.5 / mask_res;
}

void fragment() {
	vec3 n = texture(normal_map, ripple_uv + vec2(TIME, TIME * 0.5) * flow_speed).rgb;
	float dist = clamp(dot(VERTEX, VERTEX) * 0.00004, 0.0, 1.0);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(0.8, 0.1, dist);

	float depth = texture(depth_mask, mask_uv).r * max_depth;
	float fade = clamp(depth * clarity, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, fade);
	col += shallow_color * smoothstep(0.45, 0.9, crest) * 0.25;

	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	fr = fr * fr * fr;
	vec3 rdir = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	vec3 sky = mix(sky_horizon, sky_zenith, clamp(rdir.y, 0.0, 1.0));
	col = mix(col, sky, clamp(fr * reflection + 0.06, 0.0, 1.0));

	float caps = smoothstep(foam_crest, 0.95, crest) * smoothstep(0.35, 0.65, n.g);
	float shore = 1.0 - smoothstep(0.0, foam_width, depth);
	float pulse = 0.7 + 0.3 * sin(TIME * 1.4 + n.g * 6.0 - depth * 2.0);
	float foam = clamp(max(caps * 0.85, shore * pulse * smoothstep(0.2, 0.55, n.g + 0.4)), 0.0, 1.0);

	ALBEDO = mix(col, foam_color, foam);
	ROUGHNESS = mix(0.04, 0.7, foam);
	SPECULAR = 0.6;
	EMISSION = mix(col * 0.22, foam_color * 0.45, foam);
	ALBEDO = mix(ALBEDO, sky_horizon, dist * 0.5);
}