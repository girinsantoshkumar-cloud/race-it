shader_type spatial;

// This is the reference shader of the plugin, and has the most features.
// it should be preferred for high-end graphics cards.
// For less features but lower-end targets, see the lite version.

// TODO Figure out why sampling colormap or splatmap in vertex shader leads to artifacts.
// At extremely shallow angles (such as horizon), some pixels start to flash.
// It appears to be caused by interpolation between the vertex and fragment shaders, leading to
// color values going largely outside of 0..1.
// See https://github.com/Zylann/godot_heightmap_plugin/issues/469
//#define COLORMAP_PER_VERTEX
//#define SPLATMAP_PER_VERTEX

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
// I had to remove `hint_albedo` from colormap in Godot 3 because it makes sRGB conversion kick in,
// which snowballs to black when doing GPU painting on that texture...
uniform sampler2D u_terrain_colormap;
uniform sampler2D u_terrain_splatmap;
uniform sampler2D u_terrain_globalmap : source_color;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

// the reason bump is preferred with albedo is, roughness looks better with normal maps.
// If we want no normal mapping, roughness would only give flat mirror surfaces,
// while bump still allows to do depth-blending for free.
uniform sampler2D u_ground_albedo_bump_0 : source_color;
uniform sampler2D u_ground_albedo_bump_1 : source_color;
uniform sampler2D u_ground_albedo_bump_2 : source_color;
uniform sampler2D u_ground_albedo_bump_3 : source_color;

uniform sampler2D u_ground_normal_roughness_0;
uniform sampler2D u_ground_normal_roughness_1;
uniform sampler2D u_ground_normal_roughness_2;
uniform sampler2D u_ground_normal_roughness_3;

// Had to give this uniform a suffix, because it's declared as a simple float
// in other shaders, and its type cannot be inferred by the plugin.
// See https://github.com/godotengine/godot/issues/24488
uniform vec4 u_ground_uv_scale_per_texture = vec4(20.0, 20.0, 20.0, 20.0);

uniform bool u_depth_blending = true;
uniform bool u_triplanar = false;
// Each component corresponds to a ground texture. Set greater than zero to enable.
uniform vec4 u_tile_reduction = vec4(0.0, 0.0, 0.0, 0.0);

uniform float u_globalmap_blend_start;
uniform float u_globalmap_blend_distance;

uniform vec4 u_colormap_opacity_per_texture = vec4(1.0, 1.0, 1.0, 1.0);

uniform float u_specular = 0.5;

#ifdef COLORMAP_PER_VERTEX
varying float v_hole;
varying vec3 v_tint0;
varying vec3 v_tint1;
varying vec3 v_tint2;
varying vec3 v_tint3;
#endif
#ifdef SPLATMAP_PER_VERTEX
varying vec4 v_splat;
#endif
varying vec2 v_ground_uv0;
varying vec2 v_ground_uv1;
varying vec2 v_ground_uv2;
varying vec3 v_ground_uv3;
varying float v_distance_to_camera;


vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

vec4 pack_normal(vec3 n, float a) {
	n.z *= -1.0;
	return vec4((n.xzy + vec3(1.0)) * 0.5, a);
}

// Blends weights according to the bump of detail textures,
// so for example it allows to have sand fill the gaps between pebbles
vec4 get_depth_blended_weights(vec4 splat, vec4 bumps) {
	float dh = 0.2;

	vec4 h = bumps + splat;

	// TODO Keep improving multilayer blending, there are still some edge cases...
	// Mitigation: nullify layers with near-zero splat
	h *= smoothstep(0, 0.05, splat);

	vec4 d = h + dh;
	d.r -= max(h.g, max(h.b, h.a));
	d.g -= max(h.r, max(h.b, h.a));
	d.b -= max(h.g, max(h.r, h.a));
	d.a -= max(h.g, max(h.b, h.r));

	return clamp(d, 0, 1);
}

vec3 get_triplanar_blend(vec3 world_normal) {
	vec3 blending = abs(world_normal);
	blending = normalize(max(blending, vec3(0.00001))); // Force weights to sum to 1.0
	float b = blending.x + blending.y + blending.z;
	return blending / vec3(b, b, b);
}

vec4 texture_triplanar(sampler2D tex, vec3 world_pos, vec3 blend) {
	vec4 xaxis = texture(tex, world_pos.yz);
	vec4 yaxis = texture(tex, world_pos.xz);
	vec4 zaxis = texture(tex, world_pos.xy);
	// blend the results of the 3 planar projections.
	return xaxis * blend.x + yaxis * blend.y + zaxis * blend.z;
}

vec4 depth_blend2(vec4 a_value, float a_bump, vec4 b_value, float b_bump, float t) {
	// https://www.gamasutra.com
	// /blogs/AndreyMishkinis/20130716/196339/Advanced_Terrain_Texture_Splatting.php
	float d = 0.1;
	float ma = max(a_bump + (1.0 - t), b_bump + t) - d;
	float ba = max(a_bump + (1.0 - t) - ma, 0.0);
	float bb = max(b_bump + t - ma, 0.0);
	return (a_value * ba + b_value * bb) / (ba + bb);
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(cosa * v.x - sina * v.y, sina * v.x + cosa * v.y);
}

vec4 texture_antitile(
	sampler2D albedo_tex,
	sampler2D normal_tex,
	vec2 uv,
	out vec4 out_normal
) {
	// ------------------------------------------------------------
	// Deterministic stochastic anti-tiling.
	//
	// Every 1x1 UV cell receives one of 16 transformations:
	//   4 rotations x 2 horizontal flips x 2 vertical flips.
	//
	// The transformation is based on the integer tile coordinate,
	// so it stays stable while the camera moves.
	//
	// IMPORTANT:
	// The same transformation is applied to the normal map.
	// ------------------------------------------------------------

	vec2 tile = floor(uv);
	vec2 local_uv = fract(uv);

	// Small deterministic hash function.
	vec3 p3 = fract(vec3(tile.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);

	float r0 = fract((p3.x + p3.y) * p3.z);

	p3 = fract(vec3((tile + vec2(17.13, 91.71)).xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float r1 = fract((p3.x + p3.y) * p3.z);

	p3 = fract(vec3((tile + vec2(43.71, 11.27)).xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float r2 = fract((p3.x + p3.y) * p3.z);

	// Four possible rotations.
	int rotation = int(floor(r0 * 4.0));

	// Random mirrors.
	bool flip_x = r1 > 0.5;
	bool flip_y = r2 > 0.5;

	// ------------------------------------------------------------
	// Transform the UV.
	// ------------------------------------------------------------

	// Mirror first.
	if (flip_x) {
		local_uv.x = 1.0 - local_uv.x;
	}

	if (flip_y) {
		local_uv.y = 1.0 - local_uv.y;
	}

	// Rotate around the tile center.
	vec2 centered = local_uv - vec2(0.5);

	if (rotation == 1) {
		// 90 degrees
		centered = vec2(-centered.y, centered.x);
	} else if (rotation == 2) {
		// 180 degrees
		centered = -centered;
	} else if (rotation == 3) {
		// 270 degrees
		centered = vec2(centered.y, -centered.x);
	}

	local_uv = centered + vec2(0.5);

	// ------------------------------------------------------------
	// Sample albedo and normal using the exact same UV.
	// ------------------------------------------------------------

	vec4 col = texture(albedo_tex, local_uv);
	vec4 nrm = texture(normal_tex, local_uv);

	// ------------------------------------------------------------
	// Transform the sampled tangent-space normal back to match
	// the UV transformation.
	//
	// HTerrain's normal convention uses X/Z as the tangent plane.
	// The inverse rotation is therefore applied here.
	// ------------------------------------------------------------

	vec3 n = unpack_normal(nrm);

	// Inverse of the 90/180/270 degree rotation.
	if (rotation == 1) {
		n.xz = vec2(n.z, -n.x);
	} else if (rotation == 2) {
		n.xz = -n.xz;
	} else if (rotation == 3) {
		n.xz = vec2(-n.z, n.x);
	}

	// Mirror transformations are their own inverse.
	if (flip_x) {
		n.x = -n.x;
	}

	if (flip_y) {
		n.z = -n.z;
	}

	n = normalize(n);
	out_normal = pack_normal(n, nrm.a);

	return col;
}

void vertex() {
	vec4 wpos = MODEL_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = (u_terrain_inverse_transform * wpos).xz;
	// Must add a half-offset so that we sample the center of pixels,
	// otherwise bilinear filtering of the textures will give us mixed results (#183)
	cell_coords += vec2(0.5);

	// Normalized UV
	UV = cell_coords / vec2(textureSize(u_terrain_heightmap, 0));

	// Height displacement
	float h = sample_heightmap(u_terrain_heightmap, UV);
	VERTEX.y = h;
	wpos.y = h;

	vec3 base_ground_uv = vec3(cell_coords.x, h * MODEL_MATRIX[1][1], cell_coords.y);
	v_ground_uv0 = base_ground_uv.xz / u_ground_uv_scale_per_texture.x;
	v_ground_uv1 = base_ground_uv.xz / u_ground_uv_scale_per_texture.y;
	v_ground_uv2 = base_ground_uv.xz / u_ground_uv_scale_per_texture.z;
	v_ground_uv3 = base_ground_uv / u_ground_uv_scale_per_texture.w;

#ifdef COLORMAP_PER_VERTEX
	// Putting this in vertex saves 2 fetches from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate tint and splat, but it's not bad overall)
	vec4 tint = texture(u_terrain_colormap, UV);
	v_hole = tint.a;
	v_tint0 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.x);
	v_tint1 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.y);
	v_tint2 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.z);
	v_tint3 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.w);
#endif
#ifdef SPLATMAP_PER_VERTEX
	v_splat = texture(u_terrain_splatmap, UV);
#endif

	// Need to use u_terrain_normal_basis to handle scaling.
	NORMAL = u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));

	v_distance_to_camera = distance(wpos.xyz, CAMERA_POSITION_WORLD);
}

void fragment() {
#ifndef COLORMAP_PER_VERTEX
	vec4 tint = texture(u_terrain_colormap, UV);
	float v_hole = tint.a;
	vec3 v_tint0 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.x);
	vec3 v_tint1 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.y);
	vec3 v_tint2 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.z);
	vec3 v_tint3 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.w);
#endif

	if (v_hole < 0.5) {
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	}

#ifndef SPLATMAP_PER_VERTEX
	vec4 v_splat = texture(u_terrain_splatmap, UV);
#endif

	vec3 terrain_normal_world =
		u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));
	terrain_normal_world = normalize(terrain_normal_world);
	vec3 normal = terrain_normal_world;

	float globalmap_factor = clamp((v_distance_to_camera - u_globalmap_blend_start)
		* u_globalmap_blend_distance, 0.0, 1.0);
	globalmap_factor *= globalmap_factor; // slower start, faster transition but far away
	vec3 global_albedo = texture(u_terrain_globalmap, UV).rgb;
	ALBEDO = global_albedo;

	// Doing this branch allows to spare a bunch of texture fetches for distant pixels.
	// Eventually, there could be a split between near and far shaders in the future,
	// if relevant on high-end GPUs
	if (globalmap_factor < 1.0) {
		vec4 ab0, ab1, ab2, ab3;
		vec4 nr0, nr1, nr2, nr3;

		if (u_triplanar) {
			// Only do triplanar on one texture slot,
			// because otherwise it would be very expensive and cost many more ifs.
			// I chose the last slot because first slot is the default on new splatmaps,
			// and that's a feature used for cliffs, which are usually designed later.

			vec3 blending = get_triplanar_blend(terrain_normal_world);

			ab3 = texture_triplanar(u_ground_albedo_bump_3, v_ground_uv3, blending);
			nr3 = texture_triplanar(u_ground_normal_roughness_3, v_ground_uv3, blending);

		} else {
			if (u_tile_reduction[3] > 0.0) {
				ab3 = texture_antitile(
					u_ground_albedo_bump_3, u_ground_normal_roughness_3, v_ground_uv3.xz, nr3);
			} else {
				ab3 = texture(u_ground_albedo_bump_3, v_ground_uv3.xz);
				nr3 = texture(u_ground_normal_roughness_3, v_ground_uv3.xz);
			}
		}

		if (u_tile_reduction[0] > 0.0) {
			ab0 = texture_antitile(
				u_ground_albedo_bump_0, u_ground_normal_roughness_0, v_ground_uv0, nr0);
		} else {
			ab0 = texture(u_ground_albedo_bump_0, v_ground_uv0);
			nr0 = texture(u_ground_normal_roughness_0, v_ground_uv0);
		}
		if (u_tile_reduction[1] > 0.0) {
			ab1 = texture_antitile(
				u_ground_albedo_bump_1, u_ground_normal_roughness_1, v_ground_uv1, nr1);
		} else {
			ab1 = texture(u_ground_albedo_bump_1, v_ground_uv1);
			nr1 = texture(u_ground_normal_roughness_1, v_ground_uv1);
		}
		if (u_tile_reduction[2] > 0.0) {
			ab2 = texture_antitile(
				u_ground_albedo_bump_2, u_ground_normal_roughness_2, v_ground_uv2, nr2);
		} else {
			ab2 = texture(u_ground_albedo_bump_2, v_ground_uv2);
			nr2 = texture(u_ground_normal_roughness_2, v_ground_uv2);
		}

		vec3 col0 = ab0.rgb * v_tint0;
		vec3 col1 = ab1.rgb * v_tint1;
		vec3 col2 = ab2.rgb * v_tint2;
		vec3 col3 = ab3.rgb * v_tint3;

		vec4 rough = vec4(nr0.a, nr1.a, nr2.a, nr3.a);

		vec3 normal0 = unpack_normal(nr0);
		vec3 normal1 = unpack_normal(nr1);
		vec3 normal2 = unpack_normal(nr2);
		vec3 normal3 = unpack_normal(nr3);

		vec4 w;
		// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
		if (u_depth_blending) {
			w = get_depth_blended_weights(v_splat, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
		} else {
			w = v_splat.rgba;
		}

		float w_sum = (w.r + w.g + w.b + w.a);

		ALBEDO = (
			w.r * col0.rgb +
			w.g * col1.rgb +
			w.b * col2.rgb +
			w.a * col3.rgb) / w_sum;

		ROUGHNESS = (
			w.r * rough.r +
			w.g * rough.g +
			w.b * rough.b +
			w.a * rough.a) / w_sum;

		vec3 ground_normal = /*u_terrain_normal_basis **/ (
			w.r * normal0 +
			w.g * normal1 +
			w.b * normal2 +
			w.a * normal3) / w_sum;
		// If no splat textures are defined, normal vectors will default to (1,1,1),
		// which is incorrect, and causes the terrain to be shaded wrongly in some directions.
		// However, this should not be a problem to fix in the shader,
		// because there MUST be at least one splat texture set.
		//ground_normal = normalize(ground_normal);
		// TODO Make the plugin insert a default normalmap if it's empty

		// Combine terrain normals with detail normals (not sure if correct but looks ok)
		normal = normalize(vec3(
			terrain_normal_world.x + ground_normal.x,
			terrain_normal_world.y,
			terrain_normal_world.z + ground_normal.z));

		normal = mix(normal, terrain_normal_world, globalmap_factor);

		ALBEDO = mix(ALBEDO, global_albedo, globalmap_factor);
		ROUGHNESS = mix(ROUGHNESS, 1.0, globalmap_factor);

		// Show splatmap weights
		//ALBEDO = w.rgb;
	}
	// Highlight all pixels undergoing no splatmap at all
//	else {
//		ALBEDO = vec3(1.0, 0.0, 0.0);
//	}

	NORMAL = (VIEW_MATRIX * (vec4(normal, 0.0))).xyz;
	SPECULAR = u_specular;
}