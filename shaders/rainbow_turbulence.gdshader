shader_type canvas_item;
render_mode unshaded;

// -----------------------------
// Inputs you already pass
// -----------------------------
uniform float aspect = 1.7778;          // width / height

uniform float scale = 1.0;
uniform float bass_scale = 0.6;
uniform float mid_scale = 0.35;
uniform float high_scale = 0.05;
// Audio (existing)
uniform bool  audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int   bar_count = 64;
uniform float audio_gain = 1.0;
uniform float color_mix = 0.25; // unused here; kept for compatibility

// Raymarch controls
uniform int   rm_iterations = 82;
uniform float rm_fudge = 0.8;
uniform float rm_intersection_precision = 0.001;
uniform float rm_max_dist = 20.0;
uniform float focal_length = 5.0;

// Camera as scalars
uniform float cam_pos_x = 0.0;
uniform float cam_pos_y = -10.0;
uniform float cam_pos_z = -10.0;

uniform float cam_tar_x = 0.0;
uniform float cam_tar_y = 0.0;
uniform float cam_tar_z = 0.0;

uniform float cam_up_x = 0.0;
uniform float cam_up_y = 0.0;
uniform float cam_up_z = -1.0;

// -----------------------------
// Helpers
// -----------------------------
float iTime() { return TIME; }

float bar_at_index(int i){
	if (bar_count <= 0) return 0.0;
	i = clamp(i, 0, bar_count - 1);
	float u = (float(i) + 0.5) / float(bar_count);
	return texture(spectrum_tex, vec2(u, 0.5)).r;
}
float band_avg(float a, float b){
	if (bar_count <= 1) return 0.0;
	int ia = int(floor(a * float(bar_count)));
	int ib = int(ceil (b * float(bar_count))) - 1;
	ia = clamp(ia, 0, max(0, bar_count - 1));
	ib = clamp(ib, 0, max(0, bar_count - 1));
	float s = 0.0;
	int c = 0;
	for (int k = 0; k < 4096; k++) {
		if (k > ib) break;
		if (k >= ia) {
			s += bar_at_index(k);
			c++;
		}
	}
	return (c > 0) ? s / float(c) : 0.0;
}

// -----------------------------
// Noise (IQ) – mat3 via vec3 columns
// -----------------------------
const mat3 m = mat3(
    vec3( 0.00, -0.80, -0.60),
    vec3( 0.80,  0.36, -0.48),
    vec3( 0.60, -0.48,  0.64)
);

float hashf(float n) { return fract(sin(n) * 43758.5453); }

float noise(vec3 x) { // in [0,1]
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f*f*(3.0 - 2.0*f);
    float n = p.x + p.y*57.0 + 113.0*p.z;

    float res = mix(mix(mix( hashf(n+  0.0), hashf(n+  1.0), f.x),
                        mix( hashf(n+ 57.0), hashf(n+ 58.0), f.x), f.y),
                    mix(mix( hashf(n+113.0), hashf(n+114.0), f.x),
                        mix( hashf(n+170.0), hashf(n+171.0), f.x), f.y), f.z);
    return res;
}
float snoise(vec3 x) { return noise(x) * 2.0 - 1.0; }

float sfbm(vec3 p) { // in [-1,1]
    float f = 0.0;
    f  = 0.5000 * snoise( p ); p = m * p * 2.02;
    f += 0.2500 * snoise( p ); p = m * p * 2.03;
    f += 0.1250 * snoise( p ); p = m * p * 2.01;
    f += 0.0625 * snoise( p );
    return f;
}

// -----------------------------
// SDF ops
// -----------------------------
float sdSphere(vec3 p, float s) { return length(p) - s; }

float opSmoothSubtraction(float d1, float d2, float k) {
    float h = clamp( 0.5 - 0.5*(d2 + d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0 - h);
}

// -----------------------------
// Palette
// -----------------------------
vec3 pal(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b * cos( 6.28318 * (c * t + d) );
}
vec3 spectrum_col(float n) {
    return pal(n,
        vec3(0.5), vec3(0.5),
        vec3(1.0), vec3(0.0, 0.33, 0.67));
}

// -----------------------------
// Scene map (audio ONLY changes sphere radius)
// -----------------------------
float map_sdf(vec3 p, float a_amp) {
    float t = iTime();

    // Slight radius pulse on hits; color untouched elsewhere
    float base_radius = 2.0;
    float pulse = scale * a_amp; // tweak for stronger/weaker breathing
    float radius = base_radius + pulse;

    vec3 p2 = p;
    p2.x += 0.1 * sin(t + 2.0 * p.y);
    p2.y += 0.1 * sin(t + 2.0 * p.x);
    p2.z += 0.1 * sin(t + 2.0 * p.y);

    float d1 = sdSphere(p, radius);
    float d2 = sfbm( p2 * 1.5 + sin(0.1 * t) );
    float d  = opSmoothSubtraction(d2, d1, 0.0);
    return d;
}

// -----------------------------
// Camera
// -----------------------------
mat3 calcLookAtMatrix(vec3 ro, vec3 ta, vec3 up) {
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, up));
    vec3 vv = normalize(cross(uu, ww));
    return mat3(uu, vv, ww);
}

// -----------------------------
// Fragment
// -----------------------------
void fragment() {
    // Build vectors from scalar uniforms
    vec3 cam_pos = vec3(cam_pos_x, cam_pos_y, cam_pos_z);
    vec3 cam_tar = vec3(cam_tar_x, cam_tar_y, cam_tar_z);
    vec3 cam_up  = vec3(cam_up_x,  cam_up_y,  cam_up_z);

    // Fullscreen quad coords in [-1,1], corrected by aspect on X
    vec2 u = SCREEN_UV * 2.0 - 1.0;
    u.x *= aspect;

    // Audio level (single scalar)
    float a_lvl = 0.0;
    if (audio_enabled && bar_count > 0) {
        float low  = band_avg(0.00, 0.15);
        float mid  = band_avg(0.15, 0.50);
        float high = band_avg(0.50, 1.00);
        a_lvl = (bass_scale * low + mid_scale * mid + high_scale * high) * audio_gain;
        a_lvl = a_lvl / (1.0 + abs(a_lvl)); // soft clip
    }
    float a_amp = clamp(a_lvl * float(audio_enabled), 0.0, 1.0);

    // Ray setup
    mat3 camMat = calcLookAtMatrix(cam_pos, cam_tar, cam_up);
    vec3 ray_dir = normalize(camMat * vec3(u, focal_length));
    vec3 ray_pos = cam_pos;
    float ray_len = 0.0;

    float distv = 0.0;
    vec3 color = vec3(0.0);
    vec3 c;

    int ITER = rm_iterations;
    for (int i = 0; i < 512; i++) {
        if (i >= ITER) break;

        ray_len += max(rm_intersection_precision, abs(distv) * rm_fudge);
        ray_pos = cam_pos + ray_dir * ray_len;
        distv = map_sdf(ray_pos, a_amp);

        // Near-surface glow (blue-green tint)
        c = vec3(max(0.0, 0.01 - abs(distv)) * 0.5);
        c *= vec3(1.4, 2.1, 1.7);

        // Ambient purple haze
        c += vec3(0.6, 0.25, 0.7) * rm_fudge / 160.0;
        c *= smoothstep(20.0, 7.0, length(ray_pos));

        // Distance fade
        float rl = smoothstep(rm_max_dist, 0.1, ray_len);
        c *= rl;

        // Palette sweep (unchanged by audio)
        c *= spectrum_col(rl * 6.0 - 0.6);

        color += c;

        if (ray_len > rm_max_dist) break;
    }

    // Tonemap-ish (no audio coupling)
    color = pow(color, vec3(1.0 / 1.8)) * 2.0;
    color = pow(color, vec3(2.0)) * 3.0;

    COLOR = vec4(color, 1.0);
}
