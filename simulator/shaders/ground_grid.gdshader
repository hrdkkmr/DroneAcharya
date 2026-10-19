// Grass-coloured ground with a faint 5 m grid and stronger 25 m lines, so the pilot
// can judge speed and distance. Lines are anti-aliased with fwidth().
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.32, 0.45, 0.26);
uniform vec3 line_color : source_color = vec3(0.22, 0.31, 0.18);
uniform float minor_spacing = 5.0;
uniform float major_spacing = 25.0;

varying vec3 world_position;

float grid_line(vec2 coordinate, float spacing, float width) {
	vec2 cell = abs(fract(coordinate / spacing - 0.5) - 0.5) * spacing;
	vec2 aa = fwidth(coordinate) * width;
	vec2 line = 1.0 - smoothstep(vec2(0.0), aa, cell);
	return max(line.x, line.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float minor = grid_line(world_position.xz, minor_spacing, 1.0) * 0.5;
	float major = grid_line(world_position.xz, major_spacing, 2.0);
	ALBEDO = mix(base_color, line_color, max(minor, major));
	ROUGHNESS = 0.95;
}
