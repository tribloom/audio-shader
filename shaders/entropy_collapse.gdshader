shader_type canvas_item;

/* === Required uniforms === */
uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* === Aesthetic controls === */
uniform vec3 shard_color : source_color = vec3(0.90, 0.98, 1.0);
uniform vec3 core_color  : source_color = vec3(0.35, 0.65, 1.0);
uniform float bg_dim = 0.04;
uniform float star_density = 1.0;       // 0.6..1.6
uniform float swirl_amount = 1.3;       // baseline twist
uniform float collapse_bias = 0.55;     // >0 pulls inward
uniform float shard_sharpness = 18.0;   // higher = thinner shards
uniform float ray_layers = 6.0;         // 3..8 recommended

/* Hash & noise */
float hash11(float x){
    x = fract(x * 0.1031);
    x *= x + 33.33;
    return fract(1e4 * x * (x + 0.9));
}
float noise2(vec2 p){
    vec2 i = floor(p), f = fract(p);
    vec2 u = f*f*(3.0 - 2.0*f);
    float a = hash11(dot(i, vec2(1.0, 57.0)));
    float b = hash11(dot(i + vec2(1.0,0.0), vec2(1.0, 57.0)));
    float c = hash11(dot(i + vec2(0.0,1.0), vec2(1.0, 57.0)));
    float d = hash11(dot(i + vec2(1.0,1.0), vec2(1.0, 57.0)));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){
    float s=0.0, a=0.5;
    for (int i=0;i<4;i++){
        s += a * noise2(p);
        p = p*2.02 + 23.0;
        a *= 0.55;
    }
    return s;
}

/* Spectrum */
float bin(int i){
    float x = (float(i) + 0.5) / 64.0;
    return texture(spectrum_tex, vec2(x, 0.5)).r;
}
float band(float a, float b){
    float n = max(1.0, b - a), s = 0.0;
    for (int i=0; i<64; i++){
        if (float(i) >= a && float(i) < b) s += bin(i);
    }
    return s / n;
}

void fragment(){
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    float t = TIME;

    // Optional subtle wobble from waveform
    float wf = texture(waveform_tex, vec2(fract(t * 0.2), 0.5)).r;
    wf = (wf * 2.0 - 1.0) * 0.04;

    // Audio features
    float low  = enable_audio ? band(0.0, 10.0)  * audio_gain : 0.0;
    float mid  = enable_audio ? band(10.0, 28.0) * audio_gain : 0.0;
    float high = enable_audio ? band(28.0, 56.0) * audio_gain : 0.0;

    // Polar space
    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Gravity core parameters
    float gravity   = collapse_bias + 0.9 * low;       // stronger with bass
    float twist     = swirl_amount + 1.1 * mid;        // spiral energy with mids
    float shardness = shard_sharpness * (1.0 + 0.6 * high);

    // Supernova flash envelope on kick (fast rise, fast decay)
    float K = enable_audio ? smoothstep(0.0, 1.0, kick) : 0.0;
    float flash = K;

    // Radial velocity: inward (negative) with small outward when flashing
    float v_collapse = - (0.25 + 0.85 * gravity);
    float v_flash    =  0.75 * flash;
    float v = v_collapse + v_flash;

    // Time-advanced radius for dust pattern sampling (creates motion blur feel)
    float r_adv = clamp(r + v * 0.25, 0.0, 2.0);

    // Spiral warp — folds space toward the singularity
    float ang = a + twist * r_adv + 0.15 * sin(6.0 * r_adv + 2.5 * t + 2.0 * mid) + wf;

    // Multi-layer radial shards (star-like spokes that shear under warp)
    float layers = clamp(ray_layers, 2.0, 10.0);
    float shard = 0.0;
    float glow  = 0.0;

    for (int i=0; i<10; i++){
        if (float(i) >= layers) break;
        float ph = float(i) * 1.2566371; // 2π/5-ish stagger regardless of count
        float s = abs(sin(ang + ph));
        //float ray = pow(1.0 - smoothstep(0.0, 0.8, s), shardness);
		float ray = pow(max(1e-6, 1.0 - smoothstep(0.0, 0.8, s)), shard_sharpness);

        // Depth fade — brighter near core during collapse
        float df = exp(-3.0 * r_adv) * (1.0 + 0.8 * gravity);
        shard += ray * df;

        // Sparkly debris modulated by treble
        float nb = fbm(vec2(ang * 2.0, r_adv * 5.0) * (1.0 + 0.5 * high) + float(i) * 7.0);
        glow  += ray * df * nb;
    }

    // Core glow reacts to level; shards to highs; overall to flash
    vec3 col = vec3(bg_dim);
    col += core_color  * (0.45 + 0.75 * level * audio_gain) * exp(-6.0 * r);
    col += shard_color * (0.6 + 0.6 * high) * shard;
    col += shard_color * 0.8 * glow;

    // Supernova moment: brief wide additive lift
    col += (core_color * 0.6 + shard_color * 0.6) * flash;

    // Vignette to frame
    float vig = smoothstep(1.25, 0.35, length(uv));
    col *= vig;

    COLOR = vec4(col, 1.0);
}
