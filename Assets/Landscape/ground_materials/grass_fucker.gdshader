shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color: source_color=vec3(0.08, 0.25, 0.05);
uniform vec3 tip_color:source_color=vec3(0.45, 0.7, 0.2);
uniform float blade_height=0.41;
uniform float wind_strength=0.15;
uniform float wind_speed=0.6;
uniform sampler2D wind_noise:repeat_enable;

varying float h;

void vertex() {
	// Called for every vertex the material is visible on.
	h=clamp(VERTEX.y/blade_height,0.0,1.0);
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float n=texture(wind_noise,world.xz*0.03+TIME*wind_speed*0.05).r;
	float sway=(n-0.5)*2.0*wind_strength*h*h;
	VERTEX.x+=sway;
	VERTEX.z+=sway;
	NORMAL+=vec3(0.0,1.0,0.0);
}

void fragment() {
	// Called for every pixel the material is visible on.
	ALBEDO=mix(base_color,tip_color,h);
	ROUGHNESS=0.9;
	BACKLIGHT=vec3(0.15,0.25,0.07);
	
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
