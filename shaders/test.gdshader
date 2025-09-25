shader_type canvas_item;
render_mode unshaded, blend_mix;

/* Driven by Visualizer.gd */
uniform float bass   = 0.0;       // 0..1
uniform float treble = 0.0;       // 0..1
uniform float tone   = 0.5;       // 0..1
uniform float aspect = 1.7777778;

/* Base ring */
uniform float ring_radius   = 0.45;
uniform float band_width    = 0.015;     // half-width
uniform float ring_scroll   = 0.08;      // slow spin

/* Rainbow timing */
uniform float hue_period_s  = 10.0;
uniform float sat           = 0.95;
uniform float val           = 1.00;

/* Continuous ripple trains */
uniform int   pulses_per_side = 10;   // echoes per side (0..10)
uniform float emit_dt         = 0.08; // seconds between pulses
uniform float speed_out       = 0.55; // outward speed
uniform float speed_in        = 0.55; // inward speed
uniform float pulse_falloff   = 0.20; // per-echo brightness falloff
uniform float width_spread    = 1.90; // older pulses wider

/* Drive mapping */
uniform float drive_thresh    = 0.06; // min drive to see rings
uniform float drive_strength  = 1.2;  // overall gain
uniform float base_push_amt   = 0.04; // tiny live dilation of base ring

/* Helpers */
#define TAU 6.28318530718
#define S(a,b,c) smoothstep(a,b,c)

vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0/6.0, 4.0/6.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

/* Soft ring profile */
float ring_profile(float r, float radius, float width){
    float d = abs(r - radius);
    return S(width, 0.0, d) * 0.8 + S(width * 6.0, 0.0, d) * 0.2;
}

void fragment(){
    // aspect-correct circle
    vec2 p = (SCREEN_UV - 0.5) * 2.0; p.x *= aspect;
    float r   = length(p);
    float ang = atan(p.y, p.x) + TIME * ring_scroll;
    float u   = fract(ang / TAU);

    // rainbow along circumference + slow drift
    float hue = fract(u + tone + (hue_period_s > 0.0 ? TIME / hue_period_s : 0.0));
    vec3 base_rgb = hsv2rgb(vec3(hue, sat, val));

    // base ring (slightly “breathes” with audio so it feels alive)
    float base_push = (bass + treble) * 0.5 * base_push_amt;
    float base_r = ring_radius + base_push;
    vec3 col = base_rgb * ring_profile(r, base_r, band_width);

    // drives (gate and scale)
    float drive_out = max(0.0, bass   - drive_thresh) * drive_strength; // outward
    float drive_in  = max(0.0, treble - drive_thresh) * drive_strength; // inward

    int   N   = clamp(pulses_per_side, 0, 10);
    float T   = TIME;
    float ph  = fract(T / emit_dt) * emit_dt; // <-- modulo phase (0..emit_dt)

    // OUTWARD pulses: newest age in [0, emit_dt), older = + i*emit_dt
    for (int i = 0; i < 10; i++){
        if (i >= N) break;
        float age     = ph + float(i) * emit_dt;      // continuous emission
        float radius  = base_r + speed_out * age;
        float width   = band_width * mix(1.0, width_spread, float(i)/max(1.0,float(N)));
        float weight  = pow(pulse_falloff, float(i)) * drive_out;

        if (weight <= 0.0) continue;                  // silent = invisible
        if (radius > 1.6) continue;                   // offscreen safety

        col += base_rgb * (ring_profile(r, radius, width) * weight);
    }

    // INWARD pulses
    for (int j = 0; j < 10; j++){
        if (j >= N) break;
        float age     = ph + float(j) * emit_dt;
        float radius  = base_r - speed_in * age;
        float width   = band_width * mix(1.0, width_spread, float(j)/max(1.0,float(N)));
        float weight  = pow(pulse_falloff, float(j)) * drive_in;

        if (weight <= 0.0) continue;
        if (radius < 0.02) continue;

        col += base_rgb * (ring_profile(r, radius, width) * weight);
    }

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
