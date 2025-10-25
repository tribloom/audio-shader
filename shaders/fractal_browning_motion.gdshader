shader_type canvas_item;

/* === your exact uniforms === */
uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;   // 64 bins across X, sample at y=0.5
uniform sampler2D waveform_tex;   // optional (unused here)
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* ================== Simplex 2D noise (as in your code) ================== */
vec3 permute_vec3(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

float snoise2(vec2 v){
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                      -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute_vec3( permute_vec3( i.y + vec3(0.0, i1.y, 1.0 ))
                       + i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy),
                          dot(x12.zw,x12.zw)), 0.0);
  m *= m; m *= m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
  vec3 g;
  g.x  = a0.x  * x0.x      + h.x  * x0.y;
  g.yz = a0.yz * x12.xz    + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

/* ================== FBM (as in your code) ================== */
const mat2 FBM_M = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
float fbm(vec2 p){
    float f = 0.0;
    f += 0.5000 * snoise2(p);  p = FBM_M*p*2.02;
    f += 0.2500 * snoise2(p);  p = FBM_M*p*2.03;
    f += 0.1250 * snoise2(p);  p = FBM_M*p*2.01;
    f += 0.0625 * snoise2(p);
    return f / 0.9375;
}

/* ================== Audio helpers (map iChannel0 → spectrum_tex) ================== */
float spectrum_bin(int i){
    // 64 bins in your pipeline; sample at y=0.5
    float x = (float(i) + 0.5) / 64.0;
    return texture(spectrum_tex, vec2(x, 0.5)).r * audio_gain;
}
float spectrum_band_avg(float start_x01, float end_x01){
    // Convert Shadertoy’s [0..1] domain to 64-bin index range
    start_x01 = clamp(start_x01, 0.0, 1.0);
    end_x01   = clamp(end_x01,   0.0, 1.0);
    if (end_x01 < start_x01){ float tmp = start_x01; start_x01 = end_x01; end_x01 = tmp; }

    int i0 = int(floor(start_x01 * 64.0));
    int i1 = int(ceil (end_x01   * 64.0)) - 1;
    i0 = clamp(i0, 0, 63);
    i1 = clamp(i1, 0, 63);
    int count = max(1, i1 - i0 + 1);

    float sum = 0.0;
    for (int i = 0; i < 64; i++){
        if (i >= i0 && i <= i1){
            sum += spectrum_bin(i);
        }
    }
    return sum / float(count);
}

/* ================== Your “liquid” logic (ported) ================== */
vec2 liquid(vec2 uv){
    float t0   = TIME / 2.0;                         // iTime → TIME
    float bass = enable_audio ? spectrum_band_avg(0.001, 0.04) : 0.0;
    float mids = enable_audio ? spectrum_band_avg(0.3,   0.6 ) : 0.0;
    float highs= enable_audio ? spectrum_band_avg(0.8,   1.0 ) : 0.0;

    float t = t0 + mids / 4.0;

    float s1 = fbm(uv + t/2.0 + fbm(uv + fbm(uv + (t + highs)/4.0)/10.0));
    float s2 = fbm(uv + s1 + bass * 1.5);

    float f  = sin(t0);
    float f2 = sin(t0 * 2.3);
    return vec2(mix(s1, s2, f), mix(s2, s1, f2));
}

/* ================== Fragment ================== */
void fragment(){
    // Shadertoy uv = fragCoord / iResolution.xy
    // Use your full-screen UV, aspect-corrected to preserve shapes.
    vec2 uv = UV;                 // 0..1
    vec2 st = uv * 2.0 - 1.0;     // center
    st.x *= aspect;
    vec2 uv_fixed = st * 0.5 + 0.5; // back to 0..1 after aspect fix

    vec2 liq = liquid(uv_fixed);

    // Shadertoy wrote (0, liq, 1): G=B channels carry the liquid field
    vec3 col = vec3(0.0, liq.x, liq.y);

    // Optional: make overall energy lift slightly (comment out if not desired)
    col *= 0.9 + 0.5 * level * audio_gain;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
