shader_type canvas_item;
render_mode unshaded, blend_mix;

//const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

/* ---- Original defines as tweakable uniforms ---- */
uniform float size        = 0.544726;
uniform float lineSize    = 0.174972;
uniform float blur        = 0.227794;
uniform float grid        = 4.3651814;
uniform float grid2       = 4.1270218;
uniform float morph       = 2.30923;
uniform float delayAmount = 0.044175148;
uniform float speed       = 0.466905;

/* ---- Framing like the Shadertoy version (optional) ---- */
uniform float stretch_x = 1.7777778; // 16/9 stretch that Shadertoy used (set 1.0 to disable)
uniform float x_offset  = 0.35;      // left shift used there (set 0.0 to disable)

/* ---- NEW: global size/position controls ---- */
uniform vec2  center = vec2(0.5, 0.5); // scale/zoom pivot in UV space
uniform float scale  = 1.0;            // 1.0 = original size; 1.5 = bigger; 0.75 = smaller
uniform float rotate = 0.0;            // optional rotation (radians); 0 = none

/* ---- NEW: audio + bpm drive (feed from your Visualizer.gd) ---- */
uniform float audio_level = 0.0; // 0..1 wide-band level (use your level_sm)
uniform float bass        = 0.0; // 0..1 low band
uniform float treble      = 0.0; // 0..1 high band
uniform float tone        = 0.5; // 0..1 spectral centroid if you have it
uniform float bpm         = 128.0;

/* Amount of drive */
uniform float bpm_drive     = 0.5;  // how much BPM alters speed (0=off)
uniform float level_drive   = 0.35; // how much audio level alters speed
uniform float morph_drive   = 0.30; // how much bass/treble widens patterns
uniform float hue_audio     = 0.18; // hue shift from tone/bands
uniform float sat_audio     = 0.30; // saturation boost from level

/* Hue scroll timing (base, before audio) */
uniform float hue_period_s  = 10.0; // original was TIME/10
/* Clamp guards */
uniform float min_speed     = 0.05;
uniform float max_speed     = 4.0;

/* ---------------- helpers ---------------- */
float impulse(float k, float x) {
    float h = k * x;
    return h * exp(1.0 - h);
}

float plot(float dis) {
    float pct = smoothstep(dis, dis + blur, 0.5)
              - smoothstep(lineSize + dis, lineSize + dis + blur, 0.5);
    return pct;
}

vec3 rgb2hsb(vec3 c){
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0*d + e)),
                d / (q.x + e),
                q.x);
}

vec3 hsb2rgb(vec3 c){
    vec3 rgb = clamp(abs(mod(c.x*6.0 + vec3(0.0,4.0,2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    rgb = rgb*rgb*(3.0 - 2.0*rgb);
    return c.z * mix(vec3(1.0), rgb, c.y);
}

/* ---------------- core pattern ---------------- */
vec3 wooper(vec2 st, float timeCheck){
    vec3 color = vec3(0.0);
    vec2 pos = vec2(0.5) - abs(st);

    float r = length(pos) * 2.0;
    float a = atan(pos.y, pos.x);

    float gridSine = 5.0 + (grid2 * sin(timeCheck/5.0 * PI));
    r = fract(impulse(r, gridSine) * grid);

    float morphSine  = 0.2 + (1.0 + sin(timeCheck/3.0 * PI) / 2.0) * morph;
    float morphSine2 = 0.2 + (1.0 + sin(timeCheck/5.0 * PI) / 2.0) * morph;
    float morphSine3 = 0.2 + (1.0 + sin(timeCheck/9.0 * PI) / 2.0) * morph;

    // Subtle audio widening (bass expands, treble tightens slightly)
    float widen = 1.0 + morph_drive * (bass * 0.75 - treble * 0.25);
    morphSine  *= widen;
    morphSine2 *= widen;
    morphSine3 *= widen;

    float f  = ( size * cos(a*6.0 + timeCheck/3.0) + size * cos(a*2.0 + timeCheck/2.0) ) * 0.5;
    float p  = plot(1.0 - smoothstep(f,  f + 0.9, r * morphSine));

    float f2 = ( size * cos(a*4.0 + timeCheck/3.0) + size * cos(a*3.0 + timeCheck*7.0) ) * 0.5;
    float p2 = plot(1.0 - smoothstep(f2, f2 + 0.9, r * morphSine2));

    float f3 = ( size * cos(a*7.0 + timeCheck/30.0) + size * cos(a*3.0 + timeCheck*7.0) ) * 0.5;
    float p3 = plot(1.0 - smoothstep(f3, f3 + 0.9, r * morphSine3));

    color.r = p;
    color.g = p2 * st.x;
    color.b = p3;
    return color;
}

vec3 powerParticle(vec2 st, float t, float speed_eff){
    // same displacement, time uses speed_eff
    st.y += ((st.x*0.05)*sin(t/10.0*PI) + (st.x*0.1)*sin(t/12.0*PI)) * 0.5;
    st.x += ((st.y*0.05)*sin(t/10.0*PI) + (st.y*0.1)*sin(t/12.0*PI)) * 0.5;

    vec3 colorNew = vec3(0.0);
    float timerChecker = t * speed_eff;

    for (int i = 0; i < 10; i++) {
        vec3 c = wooper(st, timerChecker + float(i) * delayAmount) * (1.0 - float(i) / 10.0);
        colorNew += c;
    }
    return colorNew;
}

/* ---------------- fragment ---------------- */
void fragment(){
    float t = TIME;

    // Base uv like the Shadertoy version
    vec2 st = UV;
    st.x = st.x * stretch_x - x_offset;

    // Apply scale around 'center' (scale > 1 => larger)
    st = (st - center) / max(scale, 1e-4) + center;

    // Optional rotation around center
    if (abs(rotate) > 1e-5) {
        vec2 q = st - center;
        float c = cos(rotate), s = sin(rotate);
        q = vec2(c*q.x - s*q.y, s*q.x + c*q.y);
        st = q + center;
    }

    // Compute a speed that reacts to BPM and level
    float bpm_factor   = 1.0 + bpm_drive * (bpm / 128.0 - 1.0);     // 128 as neutral
    float level_factor = 1.0 + level_drive * (audio_level - 0.3);   // gentle start
    float speed_eff = clamp(speed * bpm_factor * level_factor, min_speed, max_speed);

    vec3 powerColor = powerParticle(st, t, speed_eff);

    // Hue & saturation respond to audio tone/level
    vec3 hue = rgb2hsb(powerColor);
    float hue_base = fract(t / max(hue_period_s, 0.001));
    float hue_from_audio = hue_audio * ( (tone - 0.5) + 0.5 * (bass - treble) );
    hue.x = fract(hue_base + hue_from_audio);
    hue.y = clamp(0.5 + sat_audio * (audio_level - 0.4), 0.0, 1.0);

    float d = clamp(1.0 - distance(vec2(0.5), st) * 2.0, 0.0, 1.0);

    vec3 out_rgb = (hsb2rgb(hue) * d) + (powerColor * d * 0.5);
    COLOR = vec4(out_rgb, 1.0);
}
