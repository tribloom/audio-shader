shader_type canvas_item;
render_mode unshaded;

// Optional audio drive
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int bar_count = 64;
uniform float audio_gain = 2.0;
uniform float bass_band = 0.12; // normalized band end for bass averaging
uniform float treble_band = 0.65; // start of the treble averaging band

// Display controls
uniform float aspect = 1.7777;
uniform float contrast = 1.0;
uniform vec2 mouse = vec2(0.0); // pixels from viewport origin

float bar_at_index(int i){
    if (bar_count <= 0) {
        return 0.0;
    }
    i = clamp(i, 0, bar_count - 1);
    float u = (float(i) + 0.5) / float(bar_count);
    return texture(spectrum_tex, vec2(u, 0.5)).r;
}

float band_average(float a, float b){
    if (bar_count <= 0) {
        return 0.0;
    }
    a = clamp(a, 0.0, 1.0);
    b = clamp(b, 0.0, 1.0);
    if (b < a) {
        float tmp = a;
        a = b;
        b = tmp;
    }
    int ia = int(floor(a * float(bar_count)));
    int ib = int(ceil (b * float(bar_count))) - 1;
    ia = clamp(ia, 0, max(0, bar_count - 1));
    ib = clamp(ib, 0, max(0, bar_count - 1));
    float sum = 0.0;
    int count = 0;
    for (int k = 0; k < 512; k++) {
        if (k > ib) {
            break;
        }
        if (k >= ia) {
            sum += bar_at_index(k);
            count++;
        }
    }
    return (count > 0) ? sum / float(count) : 0.0;
}

void rot(inout vec2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    p = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

float hash(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 58.233))) * 13758.5453);
}

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 18.5453);
}

float psin(float a) {
    return 0.5 + 0.5 * sin(a);
}

float onoise(vec2 x) {
    x *= 0.5;
    float a = sin(x.x);
    float b = sin(x.y);
    float c = mix(a, b, psin(6.283185307 * tanh(a * b + a + b)));
    return c;
}

float vnoise(vec2 x) {
    vec2 i = floor(x);
    vec2 w = fract(x);
    vec2 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);

    float a = hash(i + vec2(0.0, 0.0));
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    float k0 = a;
    float k1 = b - a;
    float k2 = c - a;
    float k3 = d - c + a - b;

    float aa = mix(a, b, u.x);
    float bb = mix(c, d, u.x);
    float cc = mix(aa, bb, u.y);

    return k0 + k1 * u.x + k2 * u.y + k3 * u.x * u.y;
}

float fbm1(vec2 p) {
    vec2 op = p;
    const float aa = 0.45;
    const float pp = 2.03;
    const vec2 oo = -vec2(1.23, 1.5);
    const float rr = 1.2;

    float h = 0.0;
    float d = 0.0;
    float a = 1.0;

    for (int i = 0; i < 5; ++i) {
        h += a * onoise(p);
        d += a;
        a *= aa;
        p += oo;
        p *= pp;
        rot(p, rr);
    }

    return mix((h / d), -0.5 * (h / d), pow(vnoise(0.9 * op), 0.25));
}

float fbm2(vec2 p) {
    vec2 op = p;
    const float aa = 0.45;
    const float pp = 2.03;
    const vec2 oo = -vec2(1.23, 1.5);
    const float rr = 1.2;

    float h = 0.0;
    float d = 0.0;
    float a = 1.0;

    for (int i = 0; i < 7; ++i) {
        h += a * onoise(p);
        d += a;
        a *= aa;
        p += oo;
        p *= pp;
        rot(p, rr);
    }

    return mix((h / d), -0.5 * (h / d), pow(vnoise(0.9 * op), 0.25));
}

float fbm3(vec2 p) {
    vec2 op = p;
    const float aa = 0.45;
    const float pp = 2.03;
    const vec2 oo = -vec2(1.23, 1.5);
    const float rr = 1.2;

    float h = 0.0;
    float d = 0.0;
    float a = 1.0;

    for (int i = 0; i < 3; ++i) {
        h += a * onoise(p);
        d += a;
        a *= aa;
        p += oo;
        p *= pp;
        rot(p, rr);
    }

    return mix((h / d), -0.5 * (h / d), pow(vnoise(0.9 * op), 0.25));
}

float warp(vec2 p, float bump, float t, vec2 mxy) {
    vec2 v = vec2(fbm1(p), fbm1(p + 0.5 * vec2(1.0, 1.0)));
    rot(v, 1.0 + t * 1.1 + mxy.x);

    vec2 vv = vec2(fbm2(p + 3.7 * v), fbm2(p - 2.7 * v.yx + 0.7 * vec2(1.0, 1.0)));
    rot(vv, -1.0 + t * 1.21315 + mxy.y);

    return fbm3(p + bump * vv);
}

float height(vec2 p, float bump, float t, vec2 mxy) {
    float a = 0.005 * t;
    p += 5.0 * vec2(cos(a), sin(a));
    p *= 2.0;
    p += 13.0;
    float h = warp(p, bump, t, mxy);
    float rs = 3.0;
    return 0.35 * tanh(rs * h) / rs;
}

vec3 normal(vec2 p, vec2 resolution, float bump, float t, vec2 mxy) {
    vec2 eps = -vec2(2.0 / resolution.y, 0.0);

    vec3 n;
    n.x = height(p + eps.xy, bump, t, mxy) - height(p - eps.xy, bump, t, mxy);
    n.y = 2.0 * eps.x;
    n.z = height(p + eps.yx, bump, t, mxy) - height(p - eps.yx, bump, t, mxy);

    return normalize(n);
}

vec3 postProcess(vec3 col, vec2 q) {
    col = pow(clamp(col, 0.0, 1.0), vec3(0.85));
    col = col * 0.6 + 0.4 * col * col * (3.0 - 2.0 * col);
    col = mix(col, vec3(dot(col, vec3(0.1))), -1.0);
    col *= 0.5 + 0.5 * pow(100.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.7);
    return col;
}

void fragment() {
    vec2 resolution = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord = UV * resolution;
    vec2 q = fragCoord / resolution;
    vec2 p = -1.0 + 2.0 * q;
    p.x *= aspect;

    float t = TIME;

    float bass = use_audio ? band_average(0.0, bass_band) : 0.4 + 0.3 * sin(t * 0.45);
    float treble = use_audio ? band_average(treble_band, 1.0) : 0.4 + 0.3 * sin(t * 0.9 + 1.3);
    float audio_drive = clamp((bass * 0.8 + treble * 0.2) * audio_gain, 0.0, 2.5);

    float bump = mix(5.4, 7.6, clamp(audio_drive, 0.0, 1.0));
    vec2 mxy = mouse * 0.005;

    float h = height(p, bump, t, mxy);
    vec3 pp = vec3(p.x, h, p.y);

    const vec3 lp1 = vec3(0.9, -0.5, 0.8);
    const vec3 lp2 = vec3(-0.9, -1.5, 0.9);

    float ll1 = length(lp1.xz - pp.xz);
    vec3 ld1 = normalize(lp1 - pp);
    vec3 ld2 = normalize(lp2 - pp);

    vec3 n = normal(p, resolution, bump, t, mxy);
    float diff1 = max(dot(ld1, n), -0.1);
    float diff2 = max(dot(ld2, n), 0.0);

    vec3 baseCol = vec3(0.6, 0.6, 0.8) + 0.2 + audio_drive * 0.25 * vec3(0.5, 0.4, 0.9);

    float oh = height(p + ll1 * 0.05 * normalize(ld1.xz), bump, t, mxy);
    const float level0 = 0.0;
    const float level1 = 0.125;
    vec3 scol = baseCol * (smoothstep(level0, level1, h) - smoothstep(level0, level1, oh));

    vec3 col = vec3(0.0);
    col += baseCol * pow(max(diff1, 0.0), 9.0);
    col += 0.1 * baseCol * pow(max(diff1, 0.0), 0.1) * (1.0 + audio_drive * 0.4);
    col += 0.15 * baseCol.zyx * pow(diff2, 2.0);
    col += 0.015 * baseCol.zyx * pow(diff2, 2.0);
    col += scol * 0.5;

    col = mix(col, col * (1.0 + audio_drive * 0.5), clamp(audio_drive, 0.0, 1.0));
    col = pow(col, vec3(contrast));
    col = postProcess(col, q);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}