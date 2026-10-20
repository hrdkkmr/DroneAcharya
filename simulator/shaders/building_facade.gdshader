shader_type spatial;
// Procedural facade for box buildings drawn with a MultiMesh (instance colour = wall
// colour). Windows are laid out in world space, so buildings of any size get evenly
// spaced floors without textures. Roofs (upward faces) use a flat roof colour.

uniform float floor_height = 3.2;
uniform float window_spacing = 3.0;
uniform float window_width = 0.62; // fraction of the spacing
uniform float shopfront = 1.0; // 1 = darker ground-floor band
uniform vec3 roof_color : source_color = vec3(0.3, 0.3, 0.31);
uniform vec3 glass_color : source_color = vec3(0.13, 0.17, 0.21);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (world_normal.y > 0.5) {
		ALBEDO = roof_color * (0.85 + 0.3 * base.g);
		ROUGHNESS = 0.95;
	} else {
		float u = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 cell = vec2(u / window_spacing, world_pos.y / floor_height);
		vec2 f = fract(cell);
		float half_gap = (1.0 - window_width) * 0.5;
		float win = step(half_gap, f.x) * step(f.x, 1.0 - half_gap) * step(0.28, f.y) * step(f.y, 0.82);
		float ground = step(world_pos.y, floor_height) * shopfront;
		float lit = hash(floor(cell) + floor(world_pos.xz * 0.01));
		vec3 glass = mix(glass_color, glass_color * 2.2 + vec3(0.05), step(0.85, lit));
		vec3 col = mix(base, glass, win * (1.0 - ground));
		col = mix(col, base * 0.45, ground * 0.7);
		// Slight darkening towards the ground so tall walls do not look flat.
		col *= 0.88 + 0.12 * clamp(world_pos.y / 12.0, 0.0, 1.0);
		ALBEDO = col;
		ROUGHNESS = mix(0.9, 0.3, win);
		METALLIC = win * 0.15;
	}
}
