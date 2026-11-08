shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Optional: Only needed if your mesh is flat squares instead of 3D blades
uniform sampler2D grass_tex : source_color, filter_linear_mipmap;
uniform bool use_texture_alpha = false;

uniform vec3 root_shadow_color : source_color = vec3(0.03, 0.04, 0.02); // Deep Last of Us undergrowth shadow
uniform vec3 lush_green : source_color = vec3(0.11, 0.23, 0.06);        // Rich forest green
uniform vec3 overgrown_olive : source_color = vec3(0.24, 0.31, 0.09);   // Sunlit overgrown tips

varying float v_height;
varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Calculate height from the actual 3D vertex Y position (0 at ground, 1 at tip)
	// This never fails even if your UV map is upside down!
	v_height = clamp(VERTEX.y / 1.2, 0.0, 1.0);
	
	// Gentle wind sway on the upper part of the blades
	float wind = sin(TIME * 1.8 + v_world_pos.x * 0.5 + v_world_pos.z * 0.5) * 0.12 * v_height;
	VERTEX.x += wind;
	
	// Point normals up so the thick grass carpet blends together smoothly like a real field
	NORMAL = normalize(vec3(0.0, 1.0, 0.2));
}

void fragment() {
	if (use_texture_alpha) {
		vec4 tex = texture(grass_tex, UV);
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	
	// Create natural color patches across the world (Lush Green vs Olive Green)
	float world_patch = sin(v_world_pos.x * 0.15) * cos(v_world_pos.z * 0.15) * 0.5 + 0.5;
	vec3 tip_color = mix(lush_green, overgrown_olive, world_patch);
	
	// Micro-stripes along the blade so it looks fibrous
	float blade_fiber = sin(UV.x * 60.0) * 0.08 + 0.92;
	
	// Darken the bottom 35% of the grass for thick "Last of Us" ambient occlusion shadow
	float ao_gradient = smoothstep(0.0, 0.65, v_height);
	
	ALBEDO = mix(root_shadow_color, tip_color * blade_fiber, ao_gradient);
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.15, 0.22, 0.05) * v_height; // Makes tips glow slightly in sunlight
}