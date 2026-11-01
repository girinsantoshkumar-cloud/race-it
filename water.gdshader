shader_type spatial;
render_mode cull_disabled;

uniform vec4 water_color: source_color=vec4(0.05,0.25,0.35,0.75);
uniform sampler2D normal_map: hint_normal,repeat_enable;
uniform float tiling=0.05;
uniform float speed=0.02;

varying vec3 world_pos;

void vertex() {
	// Called for every vertex the material is visible on.
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	// Called for every pixel the material is visible on.
	vec2 uv=world_pos.xz*tiling;
	vec3 n1=texture(normal_map,uv*TIME*speed).rgb;
	vec3 n2=texture(normal_map,uv*1.7-TIME*speed*0.7).rgb;
	NORMAL_MAP=mix(n1,n2,0.5);
	ALBEDO=water_color.rgb;
	ALPHA=water_color.a;
	ROUGHNESS=0.05;
	SPECULAR=0.02;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
