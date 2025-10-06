
shader_type canvas_item;

// ---- Inputs ----
uniform sampler2D spectrum_tex : hint_default_black;
uniform sampler2D waveform_tex : hint_default_black;

uniform float wave_gain = 4.0;   // try 3–6

// Toggle between original (spectrum-as-line) and real waveform
uniform bool use_true_waveform = false;

// Spectrum sampling row (your spectrum is 1xN; center of row 0 is ~0.125)
uniform float spec_row_v = 0.125;

// Log mapping to bias highs for the "up-and-right" feel
uniform bool use_log_freq_map = true;
uniform float log_k = 0.75;

// Waveform ring buffer head normalized [0..1], set from GDScript
uniform float wave_head_norm = 0.0;
// How much history to show across the screen (1.0 = full buffer)
uniform float wave_history_span = 1.0;

// Visual parameters
uniform float wave_amp = 1.0;
uniform float wave_thickness = 0.03; // thicker avoids raymarch gaps
uniform float grad_val = 0.8; // GRADVAL
uniform float aspect = 1.77777;

uniform vec3 color1 : source_color = vec3(0.25,0.625,0.625);
uniform vec3 color2 : source_color = vec3(0.25,0.25,1.0);
uniform vec3 color3 : source_color = vec3(1.00,0.25,0.25);

float udBox(vec3 p, vec3 b){
    return length(max(abs(p)-b, 0.0));
}

mat2 rot2d(float a){ float c=cos(a), s=sin(a); return mat2(vec2(c,-s), vec2(s,c)); }
vec3 rotate_xyz(vec3 p, vec3 a){ p.yz=rot2d(a.x)*p.yz; p.xz=rot2d(a.y)*p.xz; p.xy=rot2d(a.z)*p.xy; return p; }

vec3 get_col(float v, vec3 c1, vec3 c2){
    return mix(c1, c2, clamp(v, 0.0, 1.0));
}

vec4 map_sdf(vec3 rp, float waveF){
    vec3 bg = vec3(0.125);
    vec4 d = vec4(bg, udBox(rp-vec3(0.0,0.0,0.75), vec3(1.8,1.1,0.5)));
    vec4 eL = vec4(bg, udBox(rp-vec3( 1.9,0.0,0.3725), vec3(0.1,1.1,1.0)));
    vec4 eR = vec4(bg, udBox(rp-vec3(-1.9,0.0,0.3725), vec3(0.1,1.1,1.0)));
    vec4 eT = vec4(bg, udBox(rp-vec3(0.0, 1.2,0.3725), vec3(2.0,0.1,1.0)));
    vec4 eB = vec4(bg, udBox(rp-vec3(0.0,-1.2,0.3725), vec3(2.0,0.1,1.0)));

    d = (eL.a > d.a) ? d : eL;
    d = (eR.a > d.a) ? d : eR;
    d = (eT.a > d.a) ? d : eT;
    d = (eB.a > d.a) ? d : eB;

    // Wave bar
    float y_base = -waveF * wave_amp + wave_amp * 0.5;
    float waveDist = udBox(rp - vec3(0.0, y_base, 0.25), vec3(1.8, wave_thickness, 0.001));
    vec4 wave = vec4(vec3(0.3), waveDist);
    d = (wave.a > d.a) ? d : wave;
    return d;
}

vec3 calc_normal(vec3 rp, float waveF){
    vec3 e = vec3(0.002,0.0,0.0);
    return normalize(vec3(
        map_sdf(rp + e.xyy, waveF).a - map_sdf(rp - e.xyy, waveF).a,
        map_sdf(rp + e.yxy, waveF).a - map_sdf(rp - e.yxy, waveF).a,
        map_sdf(rp + e.yyx, waveF).a - map_sdf(rp - e.yyx, waveF).a
    ));
}

float point_light(vec3 lp, vec3 rp, vec3 n, float pulse){
    return (1.5*(pulse+0.05)/pow(distance(lp,rp),2.0)) * max(dot(normalize(lp-rp),n),0.0) * 0.25;
}
float draw_light(vec3 lp, vec3 rd, vec3 ro, float td, float pulse){
    float res = 0.0;
    if (td > distance(lp,ro)){
        float dlp = length(cross(lp-ro, lp-(ro+rd))) / length((ro+rd)-ro);
        res = max(exp(-dlp*64.0*((1.0-pulse)+0.5)), 0.0);
    }
    return res;
}

void fragment(){
    vec2 uv = vec2(UV.x, 1.0-UV.y);
    vec2 p = 2.0*uv - 1.0;
    p.x *= aspect;

    // Build 16 spectrum bands like original
    float hArr[16];
    for (int i=0;i<16;i++){
        float u = 1.0 / pow(2.0, float(i)*0.5) - 0.001;
        hArr[i] = texture(spectrum_tex, vec2(u, spec_row_v)).r;
    }

    // Ray setup
    float z = -0.5;
    vec3 ro = vec3(0.0, 0.0, z-2.0);
    vec3 rd = normalize(vec3(p, z) - ro);

    // Choose the signal used for the horizontal bar
    float ux = clamp((p.x/aspect + 1.0) * 0.5, 0.0, 1.0);
    if (use_log_freq_map){
        ux = pow(ux, log_k);
    }

    // Spectrum-as-line (classic) or true waveform (ring buffer)
    float waveF = 0.0;
    if (!use_true_waveform){
        float texel = 1.0 / float(textureSize(spectrum_tex, 0).x);
        float v0 = texture(spectrum_tex, vec2(clamp(ux - texel, 0.0, 1.0), spec_row_v)).r;
        float v1 = texture(spectrum_tex, vec2(ux,                         spec_row_v)).r;
        float v2 = texture(spectrum_tex, vec2(clamp(ux + texel, 0.0, 1.0), spec_row_v)).r;
        waveF = (v0 + 2.0*v1 + v2) * 0.25;
    } else {
        float x = fract(wave_head_norm + ux * wave_history_span);
        float texel = 1.0 / float(textureSize(waveform_tex, 0).x);
        float w0 = texture(waveform_tex, vec2(fract(x - texel), 0.5)).r;
        float w1 = texture(waveform_tex, vec2(x,                0.5)).r;
        float w2 = texture(waveform_tex, vec2(fract(x + texel), 0.5)).r;
        waveF = (w0 + 2.0*w1 + w2) / 4.0;
    }

    // March
    vec3 rp = vec3(0.0);
    vec4 d = vec4(0.0);
    float td = 0.5;
    float dMax = 25.0;
    for (int i=0;i<64;i++){
        if (td >= dMax) { break; }
        rp = ro + rd * td;
        d = map_sdf(rp, waveF);
        if (d.a < 0.001){ break; }
        td += d.a * 0.60; // smaller step gives more stable thin lines
    }

    // Lights
    float g = 1.0/(1.0 - grad_val);
    float r = 1.0/grad_val;
    vec3 lp[16];
    vec3 lc[16];
    for (int i=0;i<16;i++){
        lp[i] = vec3((7.5 - float(i))*0.2125, hArr[i]*2.0 - 1.0, 0.0);
        vec3 mid = get_col(hArr[i]*r, color1, color2);
        lc[i] = get_col((hArr[i]-grad_val)*g, mid, color3);
    }

    vec3 col = vec3(0.0);
    if (d.a < 0.001){
        vec3 n = calc_normal(rp, waveF);
        vec3 illum = vec3(0.01);
        for (int i=0;i<16;i++){ illum += lc[i]*point_light(lp[i], rp, n, hArr[i]); }
        col = d.rgb * illum;
    }
    for (int i=0;i<16;i++){ col += lc[i]*draw_light(lp[i], rd, ro, td, hArr[i]); }

    // Post
    col = clamp(col, 0.0, 1.0);
    col = pow(col, vec3(0.45));

    // vignette/contrast similar to original
    float f = 8.0;
    col = (1.0/(1.0+exp(4.0 - f*col)) - 0.0003) / (0.982 - 0.018);
    vec2 pp = p; pp.x /= aspect;
    col *= smoothstep(1.325, 0.825, abs(pp.x));
    col *= smoothstep(1.325, 0.825, abs(pp.y));

    COLOR = vec4(col, 1.0);
}
