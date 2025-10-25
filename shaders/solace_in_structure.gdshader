shader_type canvas_item;

/* === your exact uniforms === */
uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;   // 64 bins across X, sample at y=0.5
uniform sampler2D waveform_tex;   // optional (unused here)
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* ======== Shadertoy “common” pieces ======== */
const float ZUCCONI_OFFSET = 1.05;

float saturate_f(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate_v(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

vec3 bump3y(vec3 x, vec3 yoffset) {
    vec3 y = vec3(1.0) - x * x;
    y = saturate_v(y - yoffset);
    return y;
}
vec3 spectral_zucconi6(float x){
    const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);

    const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);

    return bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2);
}

mat2 rotate2d(float a){
    float c = cos(a), s = sin(a);
    return mat2(vec2(c,-s), vec2(s,c));
}

/* Simplex noise (makio64 3D) */
lowp vec4 permute(in lowp vec4 x){ return mod(x*x*34. + x, 289.); }
lowp float snoise(in mediump vec3 v){
  const lowp vec2 C = vec2(0.16666666666,0.33333333333);
  const lowp vec4 D = vec4(0.,.5,1.,2.);
  lowp vec3 i  = floor(C.y*(v.x+v.y+v.z) + v);
  lowp vec3 x0 = C.x*(i.x+i.y+i.z) + (v - i);
  lowp vec3 g = step(x0.yzx, x0);
  lowp vec3 l = (1. - g).zxy;
  lowp vec3 i1 = min(g, l);
  lowp vec3 i2 = max(g, l);
  lowp vec3 x1 = x0 - i1 + C.x;
  lowp vec3 x2 = x0 - i2 + C.y;
  lowp vec3 x3 = x0 - D.yyy;
  i = mod(i,289.);
  lowp vec4 p = permute(permute(permute(
	  i.z + vec4(0., i1.z, i2.z, 1.))
	+ i.y + vec4(0., i1.y, i2.y, 1.))
	+ i.x + vec4(0., i1.x, i2.x, 1.));
  lowp vec3 ns = .142857142857 * D.wyz - D.xzx;
  lowp vec4 j = -49. * floor(p * ns.z * ns.z) + p;
  lowp vec4 x_ = floor(j * ns.z);
  lowp vec4 X = x_ * ns.x + ns.yyyy;
  lowp vec4 Y = floor(j - 7. * x_ ) * ns.x + ns.yyyy;
  lowp vec4 h = 1. - abs(X) - abs(Y);
  lowp vec4 b0 = vec4(X.xy, Y.xy);
  lowp vec4 b1 = vec4(X.zw, Y.zw);
  lowp vec4 sh = -step(h, vec4(0));
  lowp vec4 a0 = b0.xzyw + (floor(b0)*2. + 1.).xzyw*sh.xxyy;
  lowp vec4 a1 = b1.xzyw + (floor(b1)*2. + 1.).xzyw*sh.zzww;
  lowp vec3 p0 = vec3(a0.xy,h.x);
  lowp vec3 p1 = vec3(a0.zw,h.y);
  lowp vec3 p2 = vec3(a1.xy,h.z);
  lowp vec3 p3 = vec3(a1.zw,h.w);
  lowp vec4 norm = inversesqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
  p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
  lowp vec4 m = max(.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.);
  return .5 + 12. * dot(m*m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

/* ======== Audio mapping (Shadertoy → your spectrum) ======== */
float sample_spectrum(float x01){
    return texture(spectrum_tex, vec2(clamp(x01,0.0,1.0), 0.5)).r * audio_gain;
}
float spatializeAudio(float dist) {             // ST buffer A
    float fftDomain = pow(dist, 2.0);
    float fft = sample_spectrum(fftDomain * 0.09);
    return pow(fft, 4.0);
}

/* ======== “image” helpers ======== */
const float SHAPE_SIZE   = 0.618;
const float CHROM_ABB    = 0.02;
const float ITERATIONS   = 7.0;
const float INITIAL_LUMA = 0.6;

float getColorComponent(vec2 st, float modScale, float blur) {
    vec2 modSt = mod(st, 1.0 / modScale) * modScale * 2.0 - 1.0;
    float dist = length(modSt);
    float shapeMap = smoothstep(SHAPE_SIZE + blur, SHAPE_SIZE - blur,
                                sin(dist * 3.0) * 0.5 + 0.5);
    return shapeMap;
}

void fragment(){
    float t = TIME;

    // ---- Coords using only UV + aspect (no screen size) ----
    // uv01 in [0,1], center to [-1,1], fix x by aspect like Shadertoy’s min-dim mapping
    vec2 uv01 = UV;
    vec2 st = uv01 * 2.0 - 1.0;
    st.x *= aspect;
    vec2 origSt = st;
    float dist = length(st);

    // === “buffer a” chunk ===
    float audioSignal = enable_audio ? spatializeAudio(dist) : 0.0;
    float zucconiDomain = ZUCCONI_OFFSET - dist;
    vec3  colorA = spectral_zucconi6(zucconiDomain) * audioSignal * 0.2;

    // === “image” chunk (feedback-free approximation) ===
    // Pseudo-feedback texture from animated noise (keeps the vibe)
    vec3 feedback = vec3(
        snoise(vec3(uv01 * 2.3, t * 0.27)),
        snoise(vec3(uv01 * 2.3 + vec2(37.0,11.0), t * 0.27)),
        snoise(vec3(uv01 * 2.3 + vec2(13.0,71.0), t * 0.27))
    ) * 0.5 + 0.5;

    float blur = 0.4 + sin(t * 0.52) * 0.2;

    float fb_luma = (feedback.r + feedback.g + feedback.b) / 3.0;
    st -= fb_luma * st * 0.3;

    st *= rotate2d(sin(t * 0.14) * 0.3);
    st *= (sin(t * 0.15) + 2.0) * 0.3;

    float st_len = max(1e-4, length(st * 0.428));
    st *= log(st_len) * 1.3;

    float modScale = 1.0;

    vec3 acc = vec3(0.0);
    float luma = INITIAL_LUMA;

    for (float i = 0.0; i < ITERATIONS; i += 1.0) {
        vec2 center = st + vec2(sin(t * 0.12), cos(t * 0.13)) * 1.5;

        // Shadertoy sampled feedback at vec2(length(center), .25); instead use your spectrum
        float fft = enable_audio ? sample_spectrum(clamp(length(center), 0.0, 1.0)) : 0.0;
        float blur_i = blur * (1.0 + 0.2 * fft);

        vec3 shapeColor = vec3(
            getColorComponent(center - st * CHROM_ABB, modScale, blur_i),
            getColorComponent(center,                    modScale, blur_i),
            getColorComponent(center + st * CHROM_ABB,   modScale, blur_i)
        ) * luma;

        st *= 1.1 + getColorComponent(center, modScale, 0.04) * 1.2;
        st *= rotate2d(sin(t * 0.05) * 1.33);

        acc += shapeColor;
        acc = clamp(acc, 0.0, 1.0);

        luma *= 0.6;
        blur *= 0.63;
    }

    float zuc2 = ZUCCONI_OFFSET - length(origSt);
    vec3 audioColor = spectral_zucconi6(zuc2) * (enable_audio ? audioSignal : 0.0) * 0.4;

    vec3 col = colorA;
    col += acc * 0.95;     // like prevColor * 0.95
    col *= feedback;       // color *= feedback.rgb
    col += audioColor;

    // keep it reactive to your global level
    col *= 0.9 + 0.6 * level * audio_gain;

    // mild tone balance
    col = col / (1.0 + col * 0.7);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
