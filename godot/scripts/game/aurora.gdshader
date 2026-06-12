shader_type canvas_item;
// Cheap animated aurora curtains for the upper sky. Compatibility-safe:
// only TIME, UV and basic math — no arrays, textures or derivatives.

uniform vec4 color_a : source_color = vec4(0.31, 0.80, 0.77, 1.0);
uniform vec4 color_b : source_color = vec4(0.49, 0.36, 1.00, 1.0);
uniform float speed = 0.12;
uniform float intensity = 0.55;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i.x + i.y * 57.0);
	float b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0);
	float d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	// Slowly waving vertical curtains.
	float wave = noise(vec2(UV.x * 3.0 + t, t * 0.5));
	float band = sin((UV.x * 7.0 + wave * 2.5) * 3.14159);
	band = smoothstep(0.25, 1.0, band);
	// Aurora lives only in the upper sky, fading out by mid-screen.
	float vfade = smoothstep(0.62, 0.02, UV.y);
	float a = band * vfade * intensity;
	vec3 col = mix(color_a.rgb, color_b.rgb, noise(vec2(UV.x * 2.0, t)));
	COLOR = vec4(col, a);
}
