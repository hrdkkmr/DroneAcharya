// Simulated sensor-camera look: monochrome, contrast, grain and vignette. Daylight
// uses a green-tinted "TV" look; night uses a neutral "thermal" look (actors are
// switched to bright heat-signature materials separately). Visual only.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float thermal = 0.0;
uniform float grain = 0.05;
uniform float contrast = 1.6;
uniform float seed = 0.0;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	// Daylight: darken the bright sky to mid-grey so small dark objects stand out.
	luma = mix(pow(luma, 1.5) * 0.8, luma, thermal);
	luma = clamp((luma - 0.5) * contrast + 0.5, 0.0, 1.0);
	float noise = fract(sin(dot(SCREEN_UV * 1000.0 + seed, vec2(12.9898, 78.233))) * 43758.5453);
	luma = clamp(luma + (noise - 0.5) * grain, 0.0, 1.0);
	vec3 tint = mix(vec3(0.82, 1.0, 0.84), vec3(1.0), thermal);
	float vignette = smoothstep(0.9, 0.35, distance(SCREEN_UV, vec2(0.5)));
	COLOR = vec4(vec3(luma) * tint * mix(0.55, 1.0, vignette), 1.0);
}
