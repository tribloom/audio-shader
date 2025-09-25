shader_type canvas_item;

uniform int   pulses_per_side = 50;   // echoes per side (0..10)
uniform float echo_falloff = 0.0;

// === Audio-driven uniforms (0..1) ===
uniform float bass   : hint_range(0.0, 1.0) = 0.0;
uniform float treble : hint_range(0.0, 1.0) = 0.0;
uniform float tone   : hint_range(0.0, 1.0) = 0.0;

// === Screen ===
uniform float aspect = 1.7777778;

// === Look controls ===
uniform float base_thickness = 0.010;
uniform float ring_thickness = 0.008;
uniform float bass_speed     = 0.55;
uniform float treble_speed   = 0.75;
uniform float ring_gain      = 2.0;

// Exposure & response
uniform float exposure  = 1.9;   // overall brightness (bloom loves >1.0 if 2D HDR+Glow on)
uniform float gamma_inv = 0.85;  // <1.0 lifts mids

// Hue motion
uniform float hue_speed         = 1.6;
uniform float hue_treble_boost  = 1.8;

// === Chromatic "bleed" controls ===
uniform float bleed_amount = 0.012; // base radial blur strength (screen-space)
uniform float dispersion   = 0.010; // per-channel radial offset (adds colored fringes)
uniform float overlay_thres = 0.70; // overlay threshold like the chromatic shader
uniform int   blur_taps = 3;        // 0..5 small taps (cost ↑ a bit with taps)

// ---------------- helpers ----------------
float sstep(float a, float b, float x){ return smoothstep(a,b,x); }
float ring(vec2 p, float r, float t){ float d = abs(length(p) - r); return 1.0 - sstep(t, t*1.8, d); }

vec3 hsv2rgb(vec3 c){
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float rings_luminance(vec2 p, float R){
	int   N   = clamp(pulses_per_side, 0, 50);
	// base edge
	float base_edge = ring(p, R, base_thickness) * 1.05;
	float rate = 0.22 * mix(0.6, 2.5, bass);
	float stride = 0.85;

	float lum = base_edge;
	// outward rings (bass)
	for (int i = 0; i < N; i++){
		if (i >= N) break;
		float out_phase  = TIME * (bass_speed   * (float(i)*rate + (float(i)*stride) * bass));
		float out_r  = R + fract(out_phase)  * 0.85;
		float out_ring  = ring(p, out_r,  ring_thickness)     * (bass * ring_gain * (0.85 * float(i)));
		float w     = pow(echo_falloff, float(i)) * bass * ring_gain;
		//lum += ring(p, out_r, ring_thickness) * w;
		lum += out_ring;
		}

	// inward ring (treble)
	for (int i = 0; i < N; i++){
		float in_phase = TIME * (treble_speed * (float(i)*0.7 + (2.2 - float(i)*.05) * treble));
		float in_r     = R * (1.0 - fract(in_phase));
		float in_ring  = ring(p, max(in_r, 0.0), ring_thickness) * (treble * ring_gain * 0.95);
		lum += in_ring;
	}
	//float lum = base_edge + out_ring + out_ring2 + out_ring3+ out_ring4+ out_ring5 + in_ring;

	// mild radial vignette so bleed feels “glowy”
	lum *= 1.0 - smoothstep(1.05, 1.35, length(p));
	return lum;
}

// small radial blur using a few taps along the center→pixel direction
float radial_blur(vec2 p, float R){
	if (blur_taps <= 0) return rings_luminance(p, R);
	vec2 dir = normalize(p + 1e-6);
	float sum = 0.0;
	float wsum = 0.0;
	float step_ = bleed_amount / float(max(1, blur_taps));
	for (int i=0; i<6; i++){
		if (i >= blur_taps) break;
		float w = 1.0 - float(i) / float(max(1, blur_taps)); // heavier near center sample
		sum += rings_luminance(p + dir * step_ * float(i), R) * w;
		wsum += w;
	}
	return sum / max(wsum, 1e-6);
}

void fragment(){
	// normalized, centered coords with aspect correction
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= aspect;

	// circle radius ~ distance to edge
	float R = 0.5;

	// ---- Chromatic bleed via per-channel dispersion + radial blur ----
	// Slightly offset samples for R/G/B along radial direction
	vec2 dir = normalize(uv + 1e-6);
	float dispR =  dispersion;
	float dispG =  0.0;
	float dispB = -dispersion;

	float lumR = radial_blur(uv + dir * dispR, R);
	float lumG = radial_blur(uv + dir * dispG, R);
	float lumB = radial_blur(uv + dir * dispB, R);

	// ---- Color base: fast hue spin like chromatic shader ----
	float hue = fract(tone + TIME * (hue_speed + treble * hue_treble_boost));
	float sat = 0.98;
	float val = clamp(0.35 + 0.55 * treble + 0.25 * (1.0 - bass), 0.0, 1.0);
	vec3 hue_rgb = hsv2rgb(vec3(hue, sat, val));

	// Overlay-style mix (like Chromatic Resonance):
	// if lum < thres => linear scale; else overlay brighten with hue
	vec3 colR;
	vec3 colG;
	vec3 colB;

	float th = overlay_thres;

	vec3 hueR = hue_rgb;
	vec3 hueG = hue_rgb;
	vec3 hueB = hue_rgb;

	vec3 cR = (lumR < th) ? (hueR * lumR / th) : (vec3(1.0) - (vec3(1.0 - (lumR - th)) * (vec3(1.0) - hueR)));
	vec3 cG = (lumG < th) ? (hueG * lumG / th) : (vec3(1.0) - (vec3(1.0 - (lumG - th)) * (vec3(1.0) - hueG)));
	vec3 cB = (lumB < th) ? (hueB * lumB / th) : (vec3(1.0) - (vec3(1.0 - (lumB - th)) * (vec3(1.0) - hueB)));

	// Recombine channels with their dispersed intensities
	vec3 col = vec3(cR.r, cG.g, cB.b);

	// Exposure + gentle gamma lift
	col *= exposure;
	col = pow(max(col, 0.0), vec3(gamma_inv));

	COLOR = vec4(col, 1.0);
}
