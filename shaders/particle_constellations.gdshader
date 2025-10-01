shader_type canvas_item;
render_mode unshaded;

/* ===== Audio input ===== */
uniform bool       audio_enabled = false;
uniform sampler2D  spectrum_tex;          // 1 x bar_count row, R = magnitude
uniform int        bar_count     = 64;
uniform float      audio_gain    = 1.2;
uniform float      hit_threshold = 0.02;  // ignore tiny noise
uniform float      gamma_shape   = 0.65;  // magnitude → intensity curve
uniform float      pulse_speed   = 6.0;   // flutter speed
uniform float      pulse_amount  = 0.25;  // flutter depth

/* ===== Voronoi / look ===== */
uniform float scale        = 9.5;         // bigger = more cells
uniform float jitter       = 0.65;        // 0..1 — how irregular the cells are
uniform float edge_width   = 0.11;        // Voronoi border thickness
uniform vec3  edge_color   = vec3(0.18, 0.45, 0.95);  // blue-ish lines
uniform float edge_emiss   = 0.8;         // edge brightness
uniform vec3  bg_color     = vec3(0.02);  // background inside cells

/* Center dot / glow (this is what we color with spectrum) */
uniform float center_size  = 0.19;        // base radius of the white dot
uniform float center_glow  = 2.4;         // glow falloff (bigger = softer)

/* Debug overlay (bottom bars) */
uniform bool  debug_view   = false;

/* ---------- helpers ---------- */
float hash21(vec2 p){
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
vec2 hash22(vec2 p){
    float n = sin(dot(p, vec2(127.1, 311.7)));
    return fract(vec2(262144.0, 32768.0) * n);
}
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.);
    return c.z * mix(vec3(1.), clamp(p - 1., 0., 1.), c.y);
}
vec3 rainbow(float t){ // 0=red … ~0.85=violet (avoid wrap)
    return hsv2rgb(vec3(mix(0.0, 0.85, clamp(t,0.0,1.0)), 0.95, 1.0));
}
float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    i = clamp(i, 0, bar_count - 1);
    float u = (float(i) + 0.5) / float(bar_count);
    return texture(spectrum_tex, vec2(u, 0.5)).r;
}

/* ---------- fragment ---------- */
void fragment(){
    vec2 RES = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 uv  = FRAGCOORD.xy / RES;
    // Center/fit
    uv = (uv - 0.5) * vec2(RES.x/RES.y, 1.0);

    // Voronoi in p-space
    vec2 p = uv * scale;

    vec2 ip = floor(p);
    vec2 fp = fract(p);

    float d1 = 1e9;         // nearest distance
    float d2 = 1e9;         // second nearest (for edge)
    vec2  best_cell = vec2(0.0);
    vec2  best_site = vec2(0.0);

    // search 3x3 neighbors
    for (int j = -1; j <= 1; j++){
        for (int i = -1; i <= 1; i++){
            vec2 cell = ip + vec2(float(i), float(j));
            vec2 rnd  = hash22(cell) * 2.0 - 1.0;        // [-1,1]
            vec2 site = vec2(float(i), float(j)) + vec2(0.5) + rnd * jitter; // jittered site in each cell
            vec2 r    = site - fp;
            float d   = dot(r, r);
            // track nearest and second nearest
            if (d < d1){
                d2 = d1;
                d1 = d;
                best_cell = cell;
                best_site = site;
            } else if (d < d2){
                d2 = d;
            }
        }
    }

    // Edge factor from F2-F1
    float edge = clamp((sqrt(d2) - sqrt(d1)) / edge_width, 0.0, 1.0);
    float edge_i = 1.0 - smoothstep(0.0, 1.0, edge);

    // Base canvas: bg + blue edges (keep the original look)
    vec3 col = bg_color;
    col = mix(col, edge_color, edge_i * edge_emiss);

    // Center dot for the chosen cell (use radial distance from the best site)
    vec2 rp = best_site - fp;                 // vector to site
    float r  = length(rp);                    // radius inside cell
    float dot_mask = exp(-pow(max(r, 0.0) / max(center_size, 1e-4), center_glow)); // soft round dot

    // Map THIS CELL ONLY to a stable spectrum band
    // Use the integer cell id to pick a bar (stable across frames)
    float h = hash21(best_cell);
    int band_ix = (bar_count > 0) ? int(floor(h * float(bar_count))) : 0;
    float denom = max(1.0, float(bar_count - 1));
    vec3 band_rgb = rainbow(float(band_ix) / denom);

    // Band magnitude → pulse (white → color)
    float mag = audio_enabled ? bar_at_index(band_ix) : 0.0;
    mag = max(0.0, mag * audio_gain - hit_threshold);
    float hit = pow(mag, gamma_shape);

    float flutter = 0.5 + 0.5 * sin(TIME * pulse_speed + h * 40.0); // per-cell phase
    float pulse = clamp(hit * (1.0 + pulse_amount * (flutter - 0.5) * 2.0), 0.0, 1.0);

    vec3 center_col = mix(vec3(1.0), band_rgb, pulse);

    // Composite: keep edges as-is, color ONLY the dot region
    col = mix(col, center_col, dot_mask);

    // Debug overlay: rainbow spectrum bars at bottom (no returns)
    if (debug_view && bar_count > 0){
        vec2 suv = FRAGCOORD.xy / RES;   // 0..1 screen uv
        float bar_h = 0.12;
        float in_bar = step(suv.y, bar_h);
        int i = int(floor(suv.x * float(bar_count)));
        i = clamp(i, 0, max(bar_count - 1, 0));
        float v = clamp(bar_at_index(i) * audio_gain, 0.0, 1.0);
        float hgt = mix(0.0, bar_h, v);
        float filled = step(suv.y, hgt);
        vec3 dbg = mix(vec3(0.05), rainbow(float(i)/denom), filled);
        col = mix(col, dbg, in_bar);
    }

    // Tone map a touch (soften highlights)
    col = sqrt(col);
    COLOR = vec4(col, 1.0);
}
