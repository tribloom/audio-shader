shader_type canvas_item;
render_mode unshaded;

const float R3 = 1.732051;

// ===== Controls (material-owned) =====
uniform float speed : hint_range(0.0, 3.0) = 0.20;    // base animation rate
uniform float base_spin : hint_range(0.0, 3.0) = 0.40; // pattern spin not audio-driven
uniform float zoom  : hint_range(0.2, 3.0) = 1.00;
uniform float hex_scale = 0.10;
uniform float layer_scale = 5.0;
uniform float brightness = 1.6;  // slightly lower default
uniform float vignette  = 2.0;
uniform float bob_amp   = 20.0;  // camera vertical bob amplitude (constant)

// Audio uniforms (Visualizer feeds the values; toggle here)
uniform bool  use_audio = true;
uniform float audio_drive : hint_range(0.0, 4.0) = 1.0;
uniform float audio_level = 0.0;
uniform float audio_bass  = 0.0;
uniform float audio_treble= 0.0;

// Mapping strength
uniform float bass_to_speed  : hint_range(0.0, 2.0) = 0.35; // bass -> time speed
uniform float treble_to_hue  : hint_range(0.0, 3.0) = 0.75; // treble -> hue offset

// Optional mouse (unchanged)
uniform bool  mouse_enabled = false;
uniform vec2  mouse = vec2(0.0);

// ===== Helpers =====
mat2 Rot(float a){
    float s = sin(a), c = cos(a);
    return mat2(vec2(c, -s), vec2(s, c)); // Godot expects column vectors
}

vec4 HexCoords(vec2 uv){
    vec2 s = vec2(1.0, R3);
    vec2 h = 0.5 * s;
    vec2 gv = s * uv;
    vec2 a = mod(gv, s) - h;
    vec2 b = mod(gv + h, s) - h;
    vec2 ab = dot(a,a) < dot(b,b) ? a : b;
    vec2 st = ab;
    vec2 id = gv - ab;
    return vec4(st, id);
}

float GetSize(vec2 id, float seed, float t){
    float d = length(id);
    float a = sin(d * seed + t) + sin(d * seed * seed * 10.0 + t * 2.0);
    return a * 0.5 + 0.5;
}

float Hexagon(vec2 uv, float r, vec2 offs, float t){
    uv *= Rot(mix(0.0, 3.1415, r));
    r /= (1.0 / sqrt(2.0));
    uv = vec2(-uv.y, uv.x);
    uv.x *= R3;
    uv = abs(uv);

    vec2 n = normalize(vec2(1.0, 1.0));
    float d = dot(uv, n) - r;
    d = max(d, uv.y - r * 0.707);

    d = smoothstep(0.06, 0.02, abs(d));
    d += smoothstep(0.10, 0.09, abs(r - 0.5)) * sin(t);
    return d;
}

float Xor(float a, float b){ return a + b; }

float N(float p){ return fract(sin(p * 123.34) * 345.456); }

// Hue shift by treble: we offset the phase used in Col()
vec3 Col(float p, float offs, float hue_shift){
    float n = N(p) * 1234.34;
    return sin(n * vec3(12.23, 45.23, 56.2) + (offs + hue_shift) * 3.0) * 0.5 + 0.5;
}

float Layer(vec2 uv, float s, float t){
    vec4 hu = HexCoords(uv * 2.0);

    float d = Hexagon(hu.xy, GetSize(hu.zw, s, t), vec2(0.0), t);
    vec2 offs = vec2(1.0, 0.0);
    d = Xor(d, Hexagon(hu.xy - offs, GetSize(hu.zw + offs, s, t),  offs, t));
    d = Xor(d, Hexagon(hu.xy + offs, GetSize(hu.zw - offs, s, t), -offs, t));
    offs = vec2(0.5, 0.8725);
    d = Xor(d, Hexagon(hu.xy - offs, GetSize(hu.zw + offs, s, t),  offs, t));
    d = Xor(d, Hexagon(hu.xy + offs, GetSize(hu.zw - offs, s, t), -offs, t));
    offs = vec2(-0.5, 0.8725);
    d = Xor(d, Hexagon(hu.xy - offs, GetSize(hu.zw + offs, s, t),  offs, t));
    d = Xor(d, Hexagon(hu.xy + offs, GetSize(hu.zw - offs, s, t), -offs, t));

    return d;
}

vec3 GetRayDir(vec2 uv, vec3 p, vec3 lookat, float z){
    vec3 f = normalize(lookat - p);
    vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
    vec3 u = cross(f, r);
    vec3 c = p + f * z;
    vec3 i = c + uv.x * r + uv.y * u;
    return normalize(i - p);
}

void fragment(){
    // Screen resolution
    vec2 iResolution = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord   = SCREEN_UV * iResolution;

    // Shadertoy-like coords
    vec2 uv  = (fragCoord - 0.5 * iResolution) / iResolution.y;
    //vec2 UV  = SCREEN_UV - 0.5;
    float duv = dot(UV, UV);

    vec2 m = mouse_enabled ? (mouse - 0.5) : vec2(0.0);

    // ----- Audio mapping (gentle & separated) -----
    float bass_v   = clamp(audio_bass,   0.0, 1.0);
    float treble_v = clamp(audio_treble, 0.0, 1.0);
    float drive    = max(0.0, audio_drive);

    // Bass changes time speed only (no camera shake)
    float speed_mult = 1.0;
    if (use_audio) {
        // mild non-linear to ignore micro flutter
        speed_mult += drive * bass_to_speed * pow(bass_v, 1.25);
    }

    // Treble shifts hue only
    float hue_shift = (use_audio ? drive * treble_to_hue * treble_v : 0.0);

    // Times: separate spin from content time
    float t_base = TIME * speed;
    float t      = t_base * speed_mult + m.x * 0.0 + 5.0; // mouse no longer speeds it
    float spin_t = TIME * base_spin;                       // constant spin

    // Camera (y-bob amplitude is constant)
    float y = sin(t * 0.5);
    vec3 ro = vec3(0.0, bob_amp * y, -5.0);
    vec3 lookat = vec3(0.0, 0.0, -10.0);
    vec3 rd = GetRayDir(uv, ro, lookat, zoom);

    vec3 col = vec3(0.0);

    // Intersect y=0 plane
    float k = ro.y / rd.y;
    vec3 p = ro + rd * k;
    float dp = length(p.xz);

    if (k <= 0.0){
        vec2 luv = p.xz * hex_scale;

        // layer breathing at base speed only
        float scale_mix = sin(t * 0.5) * 0.5 + 0.5;
        luv *= mix(1.0, layer_scale, scale_mix);

        // spin independent from bass
        luv *= Rot(spin_t);

        luv.x *= R3;

        // 3 scrolling layers
        for (float i = 0.0; i < 1.0; i += 1.0/3.0){
            float id   = floor(i + t);
            float tf   = fract(i + t);
            float z    = mix(5.0, 0.1, tf);
            float fade = smoothstep(0.0, 0.3, tf) * smoothstep(1.0, 0.7, tf);

            float d = Layer(luv * z, N(i + id), t);
            col += fade * tf * d * Col(id, duv, hue_shift);
        }
    }

    col *= brightness;

    if (ro.y < 0.0) col = 1.0 - col;

    // Distance + vignette falloff (gentle)
    col *= smoothstep(18.0, 5.0, dp);
    col *= 1.0 - duv * vignette;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
