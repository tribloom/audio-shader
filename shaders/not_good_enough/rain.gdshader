shader_type canvas_item;

/*** Audio (optional) ***/
uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_beat_low : hint_range(0.0,1.0) = 0.14;
uniform float u_beat_mid : hint_range(0.0,1.0) = 0.32;

/*** Background / vignette ***/
uniform vec3 bg_top = vec3(0.07, 0.09, 0.13);
uniform vec3 bg_bot = vec3(0.02, 0.03, 0.05);
uniform float vignette = 0.25;       // 0 = none, 1 = heavy
uniform float aspect = 1.7777;

/*** Droplet population (three scales) ***/
uniform float cols_big   : hint_range(6.0, 64.0)   = 22.0;
uniform float rad_big    : hint_range(0.008,0.08)  = 0.035;

uniform float cols_med   : hint_range(12.0, 120.0) = 48.0;
uniform float rad_med    : hint_range(0.006,0.05)  = 0.020;

uniform float cols_small : hint_range(20.0, 200.0) = 96.0;
uniform float rad_small  : hint_range(0.004,0.04)  = 0.012;

/*** Motion & density ***/
uniform float base_speed   : hint_range(0.0, 3.0) = 0.50; // downward (UV units / sec)
uniform float speed_audio  : hint_range(0.0, 2.0) = 0.70; // beat -> extra speed
uniform float base_density : hint_range(0.0, 1.0) = 0.35; // chance a cell has a drop
uniform float dens_audio   : hint_range(0.0, 1.0) = 0.45; // beat -> more active cells
uniform float wind         : hint_range(-0.25,0.25) = -0.03; // sideways drift

/*** Shading ***/
uniform vec2  light_dir = vec2(-0.6, 0.7); // top-left
uniform float refract_amt : hint_range(0.0, 0.03) = 0.010;
uniform float fresnel_pow : hint_range(1.0, 6.0)  = 3.0;   // rim strength
uniform float spec_gain   : hint_range(0.0, 2.0)  = 1.0;   // highlight
uniform float body_gain   : hint_range(0.5, 2.0)  = 1.0;   // inner brightness

// ---------------- utils ----------------
float h21(vec2 p){
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float band_sample(float a, float b){
    const int N = 12;
    float s = 0.0;
    for (int i=0;i<N;i++){
        float t = float(i)/float(N-1);
        float u = clamp(mix(a,b,t), 0.0, 1.0);
        s += texture(spectrum_tex, vec2(u, 0.25)).r;
    }
    return s/float(N);
}

vec3 bg(vec2 uv){ return mix(bg_bot, bg_top, uv.y); }

// Sphere lighting (2D circle -> 3D normal)
vec3 shade_droplet(vec2 uv, vec2 c, float r){
    vec2 rel = (uv - c)/max(r, 1e-4);     // normalized to radius
    float d2 = dot(rel, rel);
    if (d2 >= 1.0) return vec3(0.0);      // outside

    float z  = sqrt(max(0.0, 1.0 - d2));  // sphere cap height
    vec3 n   = normalize(vec3(rel, z));   // surface normal
    vec3 L   = normalize(vec3(light_dir, 0.9));

    float ndl = max(dot(n, L), 0.0);
    float fres = pow(1.0 - max(n.z, 0.0), fresnel_pow);

    // fake refraction: offset bg by surface slope (more at edge)
    vec2 refr_uv = uv + rel * refract_amt * (0.4 + 0.6*(1.0 - z));
    vec3 refr = bg(refr_uv);

    // body + rim + spec
    float spec = pow(ndl, 24.0) * spec_gain;
    vec3  body = refr * (0.8 + 0.6 * z) * body_gain;
    vec3  rim  = vec3(0.95, 0.98, 1.0) * fres;

    return body + rim + spec;
}

// One procedural layer of droplets, returned as additive contribution
vec3 layer(vec2 uv, float cols, float base_r, float density, float speed, float seed_shift){
    vec2 cell_count = vec2(cols, cols);   // roughly square cells
    vec2 gp = uv * cell_count;
    vec2 gi = floor(gp);

    vec3 acc = vec3(0.0);

    // Search nearest 3×3 cells
    for (int j=-1;j<=1;j++){
        for (int i=-1;i<=1;i++){
            vec2 id = gi + vec2(float(i), float(j));

            // Per-cell randoms
            float s0 = h21(id + seed_shift);
            float s1 = h21(id + 11.7 + seed_shift);
            float s2 = h21(id + 27.3 + seed_shift);

            // Decide if this cell *has* a droplet
            if (s0 > density) continue;

            // Base cell center (x jitter), y scrolls down continuously
            vec2 c = (id + vec2(0.5, 0.5)) / cell_count;
            c.x += (s1 - 0.5) * (1.0/cols) * 0.9;    // tiny x jitter
            float y0 = fract(s2 - TIME * speed);     // 1..0 wrap
            c.y = y0;
            c.x += wind * (TIME * 0.2 + (uv.y - c.y)); // light drift

            float r = base_r * mix(0.85, 1.25, s1);
            acc += shade_droplet(uv, c, r) - bg(uv);  // add only droplet delta
        }
    }
    return acc;
}

void fragment(){
    // UV (0..1), flip Y so top is 1 (like window glass)
    vec2 uv = vec2(UV.x, 1.0 - UV.y);

    // Background first
    vec3 col = bg(uv);

    // Beat (low + mid)
    float beat_lo  = use_audio ? band_sample(u_beat_low, u_beat_low+0.06) : 0.25 + 0.06*sin(TIME*0.6);
    float beat_mid = use_audio ? band_sample(u_beat_mid, u_beat_mid+0.10) : 0.20 + 0.05*sin(TIME*0.4+1.2);
    float beat = clamp(0.6*beat_lo + 0.4*beat_mid, 0.0, 1.0);

    float density = clamp(base_density + dens_audio*beat, 0.0, 1.0);
    float speed   = base_speed + speed_audio*beat;

    // Three scales of droplets
    col += layer(uv, cols_big,   rad_big,   density, speed*0.55,  3.0);
    col += layer(uv, cols_med,   rad_med,   density, speed*0.90, 17.0);
    col += layer(uv, cols_small, rad_small, density, speed*1.25, 41.0);

    // Vignette
    vec2 p = -1.0 + 2.0 * uv; p.x *= aspect;
    float vig = mix(1.0, smoothstep(1.7, 0.6, length(p)), vignette);
    col *= vig;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
