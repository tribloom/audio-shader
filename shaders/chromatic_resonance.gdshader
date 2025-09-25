shader_type canvas_item;

// Driven by your Visualizer.gd
uniform float level : hint_range(0.0, 1.0) = 0.0;
uniform float kick  : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7777778; // 16:9 as a literal

uniform float music_reaction = 0.8;  // overall sensitivity

float S(float a, float b, float c) { return smoothstep(a, b, c); }
float sat(float a) { return clamp(a, 0.0, 1.0); }

float N2(vec2 p) {
	p = mod(p, vec2(1456.2346));
	vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

float cosine_interpolate(float y1, float y2, float t) {
	float mu = (1.0 - cos(t * PI)) * 0.5;
	return mix(y1, y2, mu);
}

float noise2(vec2 uv) {
	vec2 corner = floor(uv);
	float c00 = N2(corner + vec2(0.0, 0.0));
	float c01 = N2(corner + vec2(0.0, 1.0));
	float c11 = N2(corner + vec2(1.0, 1.0));
	float c10 = N2(corner + vec2(1.0, 0.0));
	vec2 diff = fract(uv);
	float a = cosine_interpolate(c00, c10, diff.x);
	float b = cosine_interpolate(c01, c11, diff.x);
	return cosine_interpolate(a, b, diff.y);
}

float line_noise(float x, float t) {
	float n = noise2(vec2(x * 0.6, t * 0.2));
	return n - 0.5;
}

float line_fn(vec2 uv, float t, float scroll) {
	float ax = abs(uv.x);
	uv.y *= (0.5 + ax * ax * 0.3);
	uv.x += TIME * scroll;

	float n1 = line_noise(uv.x, t);
	float n2 = line_noise(uv.x + 0.5, t + 10.0) * 2.0;

	float ay = abs(uv.y - n1);
	float lum = S(0.02, 0.00, ay) * 1.5;
	lum += S(1.5, 0.00, ay) * 0.1;

	float r = (uv.y - n1) / (n2 - n1);
	float h = sat(1.0 - r);
	if (r > 0.0) {
		lum = max(lum, h * h * 0.7);
	}
	return lum;
}

void fragment() {
	// UV is 0..1 across the ColorRect. Center it and apply aspect.
	vec2 uv = UV * 2.0 - 1.0;   // now ~[-1,1]
	uv.x *= aspect;

	// Audio reactivity
	float amp_main = music_reaction * (0.25 + level * 1.25);
	float amp_kick = music_reaction * (0.25 + kick  * 1.75);

	float t0 = TIME * (0.30 + level * 0.80);
	float t1 = TIME * (0.50 + level * 1.00) + 45.0;
	float t2 = TIME * (0.40 + level * 0.90) + 67.3;
	float t3 = TIME * (0.77 + level * 1.25) + 1235.45;
	float t4 = TIME * (0.77 + level * 1.15) + 456.45;

	float w0 = (sin(TIME * 0.6) + kick * 2.0) * 0.35 * amp_kick;
	float w1 = (sin(TIME * 0.7 + 0.5) + level * 2.0) * 0.25 * amp_main;
	float w2 = (sin(TIME * 0.8 + 1.0) + level * 2.0) * 0.22 * amp_main;
	float w3 = (sin(TIME * 1.0 + 1.5) + kick  * 2.2) * 0.30 * amp_kick;
	float w4 = (sin(TIME * 1.2 + 2.0) + level * 2.2) * 0.24 * amp_main;

	float lum = 0.0;
	lum += line_fn(uv * vec2(2.0, 1.0)   + vec2(0.00, w0), t0, 0.10) * 0.60;
	lum += line_fn(uv * vec2(1.5, 0.9)   + vec2(0.33, w1), t1, 0.15) * 0.50;
	lum += line_fn(uv * vec2(1.3, 1.2)   + vec2(0.66, w2), t2, 0.20) * 0.30;
	lum += line_fn(uv * vec2(1.5, 1.15)  + vec2(0.80, w3), t3, 0.23) * 0.43;
	lum += line_fn(uv * vec2(1.5, 1.15)  + vec2(0.80, w4), t4, 0.30) * 0.25;

	float ax = abs(uv.x);
	lum += ax * ax * 0.05;

	// Hue sweep (use TAU instead of redefining 2*PI)
	float xh = uv.x * 1.2 + TIME * (0.2 + level * 0.6);
	vec3 hue = (sin(vec3(xh, xh + TAU * 0.33, xh + TAU * 0.66)) + vec3(1.0)) * 0.7;

	vec3 col;
	float thres = 0.7;
	if (lum < thres) {
		col = hue * lum / thres;
	} else {
		col = vec3(1.0) - (vec3(1.0 - (lum - thres)) * (vec3(1.0) - hue));
	}

	COLOR = vec4(col, 1.0);
}
