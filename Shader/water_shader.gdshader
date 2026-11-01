
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color =
    vec4(0.005, 0.045, 0.075, 1.0);

uniform vec4 shallow_color : source_color =
    vec4(0.025, 0.25, 0.28, 1.0);

uniform float wave_height : hint_range(0.0, 0.3) = 0.08;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.6;
uniform float wave_scale : hint_range(0.1, 3.0) = 0.7;
uniform float detail_scale : hint_range(1.0, 20.0) = 7.0;
uniform float roughness_value : hint_range(0.05, 1.0) = 0.22;

varying vec3 world_position;

void vertex() {
    float t = TIME * wave_speed;

    float w1 = sin(VERTEX.x * wave_scale + t);
    float w2 = sin(VERTEX.z * wave_scale * 1.3 - t * 0.8);
    float w3 = sin((VERTEX.x + VERTEX.z) *
        wave_scale * 0.65 + t * 0.55);

    VERTEX.y += wave_height *
        (w1 * 0.45 + w2 * 0.35 + w3 * 0.20);

    world_position = (MODEL_MATRIX *
        vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;

    float a = sin(p.x * detail_scale + TIME * 0.8);
    float b = sin(p.y * detail_scale * 0.75 - TIME * 0.6);
    float detail = (a + b) * 0.5;

    float color_mix = clamp(0.40 + detail * 0.12, 0.0, 1.0);

    ALBEDO = mix(deep_color.rgb, shallow_color.rgb, color_mix);
    ROUGHNESS = roughness_value;
    METALLIC = 0.05;
    SPECULAR = 0.8;
}
