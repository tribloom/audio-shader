shader_type canvas_item;

/* ---- Audio inputs (all optional) ---- */
uniform bool enable_audio = true;
uniform float kick_env = 0.0;
uniform float bass_env = 0.0;
uniform float mids_env = 0.0;
uniform float highs_env = 0.0;

/* Provide this if you have a global loudness; if not, shader will average spectrum_tex */
uniform float volume_env = -1.0;

/* Spectrum fallback */
uniform sampler2D spectrum_tex;
uniform int bar_count;

/* ---- Flow speed mapping (quiet -> slow, loud -> fast) ---- */
uniform float flow_speed = 1.0;     // base speed
uniform float flow_min = 0.6;       // speed factor at silence
uniform float flow_max = 2.0;       // speed factor at max loudness
uniform float flow_curve = 0.8;     // <1 = more responsive at low vols

/* ---- Color/contrast audio touches (from last version) ---- */
uniform float audio_hue_nm = 6.0;
uniform float audio_exposure = 0.06;
uniform float audio_zoom = 0.015;
uniform float audio_sat = 0.12;
uniform float sparkle_amount = 0.02;

/* ---- Look controls ---- */
uniform float gamma_correction = 2.2;

/* --------- Spectral color (WAHa.06x36) --------- */
vec3 spectral_colour(float l){
    float r = 0.0;
    float g = 0.0;
    float b = 0.0;
    if ((l >= 400.0) && (l < 410.0)) { float t = (l - 400.0) / (410.0 - 400.0); r = (0.33 * t) - (0.20 * t * t); }
    else if ((l >= 410.0) && (l < 475.0)) { float t = (l - 410.0) / (475.0 - 410.0); r = 0.14 - (0.13 * t * t); }
    else if ((l >= 545.0) && (l < 595.0)) { float t = (l - 545.0) / (595.0 - 545.0); r = (1.98 * t) - (t * t); }
    else if ((l >= 595.0) && (l < 650.0)) { float t = (l - 595.0) / (650.0 - 595.0); r = 0.98 + (0.06 * t) - (0.40 * t * t); }
    else if ((l >= 650.0) && (l < 700.0)) { float t = (l - 650.0) / (700.0 - 650.0); r = 0.65 - (0.84 * t) + (0.20 * t * t); }
    if ((l >= 415.0) && (l < 475.0)) { float t = (l - 415.0) / (475.0 - 415.0); g = (0.80 * t * t); }
    else if ((l >= 475.0) && (l < 590.0)) { float t = (l - 475.0) / (590.0 - 475.0); g = 0.8 + (0.76 * t) - (0.80 * t * t); }
    else if ((l >= 585.0) && (l < 639.0)) { float t = (l - 585.0) / (639.0 - 585.0); g = 0.82 - (0.80 * t); }
    if ((l >= 400.0) && (l < 475.0)) { float t = (l - 400.0) / (475.0 - 400.0); b = (2.20 * t) - (1.50 * t * t); }
    else if ((l >= 475.0) && (l < 560.0)) { float t = (l - 475.0) / (560.0 - 475.0); b = 0.7 - t + (0.30 * t * t); }
    return vec3(r, g, b);
}

vec3 spectral_palette(float x){
    return spectral_colour(x * 300.0 + 400.0);
}

/* --- helpers --- */
float luma(vec3 c){
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 p){
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

/* average the spectrum when volume_env < 0 */
float spectrum_mean(){
    int n = max(1, bar_count);
    float sum = 0.0;
    int taps = 64;
    for (int i = 0; i < 64; i++){
        float t = float(i) / float(taps - 1);
        float x = (t * float(n - 1) + 0.5) / float(n);
        sum += texture(spectrum_tex, vec2(x, 0.5)).r;
    }
    return clamp(sum / float(taps), 0.0, 1.0);
}

/* -------------- Fragment -------------- */
void fragment(){
    vec2 res = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord = UV * res;
    vec2 p = (2.0 * fragCoord - res) / max(res.x, res.y);

    /* overall loudness -> speed factor */
    float loud = volume_env;
    if (loud < 0.0){
        loud = spectrum_mean();
    }
    loud = clamp(loud, 0.0, 1.0);
    float loud_nl = pow(loud, flow_curve);
    float speed_factor = mix(1.0, mix(flow_min, flow_max, loud_nl), enable_audio ? 1.0 : 0.0);

    /* musical breathing (zoom/exposure) – optional, kept subtle */
    float zoom = 1.0;
    float exposure = 1.0;
    float nm_shift = 0.0;
    float sat_boost = 1.0;
    if (enable_audio){
        zoom = 1.0 - audio_zoom * clamp(kick_env, 0.0, 1.0);
        exposure = 1.0 + audio_exposure * clamp(kick_env, 0.0, 1.0);
        nm_shift = (audio_hue_nm / 300.0) * clamp(mids_env + 0.5 * bass_env, 0.0, 1.0);
        sat_boost = 1.0 + audio_sat * clamp(highs_env, 0.0, 1.0);
    }
    p *= zoom;

    /* time now speeds up or slows down with loudness */
    float t = TIME * flow_speed * speed_factor;

    /* Iterated sine warp */
    vec2 q = p;
    for (int i = 1; i < 50; i++){
        float fi = float(i);
        q = q + vec2(
            0.6 / fi * sin(fi * q.y + t + 0.3 * fi) + 1.0,
            0.6 / fi * sin(fi * q.x + t + 0.3 * (fi + 10.0)) - 1.4
        );
    }

    /* Rainbow with tiny wavelength drift */
    vec3 col = spectral_palette(q.x - 48.5 + nm_shift);

    /* Saturation and faint sparkle from highs */
    float Y = luma(col);
    col = mix(vec3(Y), col, sat_boost);
    if (enable_audio){
        float sparkle = sparkle_amount * clamp(highs_env, 0.0, 1.0);
        float s = hash21(floor(fragCoord * 1.25) + floor(vec2(TIME)));
        col += sparkle * step(0.98, s);
    }

    /* Gamma + exposure */
    col *= exposure;
    col = pow(col, vec3(1.0 / gamma_correction));

    COLOR = vec4(col, 1.0);
}
