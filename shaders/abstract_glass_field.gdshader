shader_type canvas_item;

// Ported from "Abstract Glassy Field" by Shane: https://www.shadertoy.com/view/4ttGDH
// Adapted for the audio-shader visualizer.

/* ---- Audio controls ---- */
uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform vec3 bass_glow_color = vec3(1.0, 0.25, 0.15);
uniform vec3 mid_glow_color = vec3(0.2, 0.6, 1.0);
uniform vec3 treble_glow_color = vec3(0.9, 0.2, 1.0);

/* ---- Visual controls ---- */
uniform float aspect         : hint_range(0.25, 4.0) = 1.7777;
uniform float cam_speed      : hint_range(0.25, 6.0) = 3.0;
uniform float fov_scale      : hint_range(0.1, 2.0) = 1.0;
uniform float lens_k         : hint_range(0.0, 0.4) = 0.125;
uniform float fog_mix        : hint_range(0.0, 1.0) = 0.95;
uniform float glow_gain      : hint_range(0.0, 24.0) = 12.0;
uniform float refraction_eta : hint_range(1.0, 2.0) = 1.31;
uniform float reflection_mix : hint_range(0.0, 1.0) = 0.5;

/* ---- Texture inputs ---- */
uniform sampler2D env_tex : hint_default_black; // Noise or environment texture (set to repeat).

const float FAR = 50.0;

/* ---- Audio helpers ---- */
float bar_at_index(int idx){
    if (bar_count <= 0) return 0.0;
    int i = clamp(idx, 0, bar_count - 1);
    float u = (float(i) + 0.5) / float(bar_count);
    return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}

float low_band(){
    int n = max(1, min(8, bar_count));
    float sum = 0.0;
    for (int i = 0; i < n; i++){
        sum += bar_at_index(i);
    }
    return sum / float(n);
}

float mid_band(){
    if (bar_count <= 0) return 0.0;
    int lo = int(float(bar_count) * 0.3);
    int hi = int(float(bar_count) * 0.7);
    int n = max(1, hi - lo);
    float sum = 0.0;
    for (int i = lo; i < hi; i++){
        sum += bar_at_index(i);
    }
    return sum / float(n);
}

float hi_band(){
    if (bar_count <= 0) return 0.0;
    int start = int(float(bar_count) * 0.75);
    int n = max(1, bar_count - start);
    float sum = 0.0;
    for (int i = start; i < bar_count; i++){
        sum += bar_at_index(i);
    }
    return sum / float(n);
}

vec3 tri_planar(sampler2D tex, vec3 p, vec3 n){
    n = max(abs(n) - 0.2, 0.001);
    n /= dot(n, vec3(1.0));
    vec3 tx = texture(tex, p.zy).xyz;
    vec3 ty = texture(tex, p.xz).xyz;
    vec3 tz = texture(tex, p.xy).xyz;
    return tx*tx*n.x + ty*ty*n.y + tz*tz*n.z;
}

vec3 cam_path(float t){
    float a = sin(t * 0.11);
    float b = cos(t * 0.14);
    return vec3(a * 4.0 - b * 1.5, b * 1.7 + a * 1.5, t);
}

float scene_sdf(vec3 p){
    p.xy -= cam_path(p.z).xy;
    p = cos(p * 0.1490 + sin(p.zxy * 0.4375));
    float n = dot(p, p);
    p = sin(p * 3.0 + cos(p.yzx * 12.0));
    return (n - p.x * p.y * p.z * 0.35 - 0.9) * 1.33 + 0.001 * texture(env_tex, p.xy).x;
}

float calc_ao(vec3 p, vec3 n){
    float sca = 1.0;
    float occ = 0.0;
    for (int i = 0; i < 5; i++){
        float hr = 0.01 + float(i) * 0.35 / 4.0;
        float dd = scene_sdf(n * hr + p);
        occ += (hr - dd) * sca;
        sca *= 0.7;
    }
    return clamp(1.0 - occ, 0.3, 1.0);
}

vec3 calc_normal(vec3 p){
    const vec2 e = vec2(0.002, 0.0);
    return normalize(vec3(
        scene_sdf(p + e.xyy) - scene_sdf(p - e.xyy),
        scene_sdf(p + e.yxy) - scene_sdf(p - e.yxy),
        scene_sdf(p + e.yyx) - scene_sdf(p - e.yyx)
    ));
}

vec2 raymarch(vec3 ro, vec3 rd){
    float glow_accum = 0.0;
    float t = 0.0;
    for (int i = 0; i < 128; i++){
        float h = scene_sdf(ro + rd * t);
        if (abs(h) < 0.001 * (t * 0.25 + 1.0) || t > FAR) break;
        t += h;
        if (abs(h) < 0.35){
            glow_accum += (0.35 - abs(h)) / 24.0;
        }
    }
    return vec2(min(t, FAR), glow_accum);
}

float soft_shadow(vec3 ro, vec3 rd, float start_d, float end_d, float k){
    float shade = 1.0;
    const int max_iter = 24;
    float dist = start_d;
    for (int i = 0; i < max_iter; i++){
        float h = scene_sdf(ro + rd * dist);
        shade = min(shade, smoothstep(0.0, 1.0, k * h / dist));
        dist += clamp(h, 0.01, 0.2);
        if (abs(h) < 0.001 || dist > end_d) break;
    }
    return min(max(shade, 0.0) + 0.4, 1.0);
}

vec3 tri_planar_bump(sampler2D tex, vec3 p, vec3 n, float bf){
    const vec2 e = vec2(0.001, 0.0);
    mat3 m = mat3(
        tri_planar(tex, p - e.xyy, n),
        tri_planar(tex, p - e.yxy, n),
        tri_planar(tex, p - e.yyx, n)
    );
    vec3 g = vec3(0.299, 0.587, 0.114) * m;
    g = (g - dot(tri_planar(tex, p, n), vec3(0.299, 0.587, 0.114))) / e.x;
    g -= n * dot(n, g);
    return normalize(n + g * bf);
}

float noise3(vec3 p){
    const vec3 s = vec3(7.0, 157.0, 113.0);
    vec3 ip = floor(p);
    p -= ip;
    vec4 h = vec4(0.0, s.yz, s.y + s.z) + dot(ip, s);
    p = p * p * (3.0 - 2.0 * p);
    h = mix(fract(sin(h) * 43758.5453), fract(sin(h + s.x) * 43758.5453), p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z);
}

void fragment(){
    vec2 uv = vec2(UV.x, 1.0 - UV.y);
    vec2 res = vec2(aspect, 1.0);
    vec2 frag_coord = vec2(uv.x * res.x, uv.y * res.y);
    vec2 u = (frag_coord - res * 0.5) / res.y;

    float speed = cam_speed;
    vec3 cam_o = cam_path(TIME * speed);
    vec3 cam_lk = cam_path(TIME * speed + 0.25);
    vec3 light_pos = cam_path(TIME * speed + 2.0) + vec3(0.0, 1.0, 0.0);

    float FOV = 1.570796 * fov_scale;
    vec3 fwd = normalize(cam_lk - cam_o);
    vec3 rgt = normalize(vec3(fwd.z, 0.0, -fwd.x));
    vec3 up = cross(fwd, rgt);

    vec3 ray_dir = fwd + FOV * (u.x * rgt + u.y * up);
    ray_dir = normalize(vec3(ray_dir.xy, ray_dir.z - length(ray_dir.xy) * lens_k));

    vec2 march = raymarch(cam_o, ray_dir);
    float t = march.x;
    float accum_glow = march.y;
    vec3 col = vec3(0.0);

    if (t < FAR){
        vec3 pos = cam_o + ray_dir * t;
        vec3 normal = calc_normal(pos);
        vec3 smooth_normal = normal;

        float sz = 1.0 / 3.0;
        normal = tri_planar_bump(env_tex, pos * sz, normal, 0.1 / (1.0 + t * 0.25 / FAR));

        vec3 light_dir = light_pos - pos;
        float light_dist = max(length(light_dir), 0.001);
        light_dir /= light_dist;

        float attenuation = 1.0 / (1.0 + light_dist * 0.05 + light_dist * light_dist * 0.0125);
        float ao = calc_ao(pos, normal);
        float shadow = soft_shadow(pos, light_dir, 0.04, light_dist, 16.0);
        float diffuse = max(dot(light_dir, normal), 0.0);
        float specular = pow(max(dot(reflect(ray_dir, normal), light_dir), 0.0), 64.0);
        float fresnel = clamp(1.0 + dot(ray_dir, normal), 0.0, 1.0);

        vec3 base = vec3(0.05);
        col = base * (diffuse * 0.1 + ao * 0.25) + vec3(0.5, 0.7, 1.0) * specular * 2.0 + vec3(1.0, 0.7, 0.4) * pow(fresnel, 8.0) * 0.25;

        vec3 refl = texture(env_tex, 0.2 * normalize(reflect(ray_dir, smooth_normal * 0.5 + normal * 0.5)).xy).xyz;
        vec3 refr = texture(env_tex, 0.2 * normalize(refract(ray_dir, smooth_normal * 0.5 + normal * 0.5, 1.0 / refraction_eta)).xy).xyz;
        refl *= refl * 0.3;
        refr *= refr * 0.4;
        vec3 ref_col = mix(refr, refl, pow(fresnel, 5.0));
        col += ref_col * ((diffuse * diffuse * 0.25 + 0.75) + ao * 0.25) * mix(0.0, 1.5, reflection_mix);

        col = mix(col.xzy, col, diffuse * 0.85 + 0.15);

        float bass = 0.0;
        float mid = 0.0;
        float tre = 0.0;
        if (audio_enabled){
            bass = low_band();
            mid = mid_band();
            tre = hi_band();
        }
        float band_energy = bass + mid + tre;
        float audio_mix = audio_enabled ? 1.0 : 0.0;
        float inv_energy = 1.0 / max(band_energy, 0.0001);
        vec3 band_color = (bass_glow_color * bass + mid_glow_color * mid + treble_glow_color * tre) * inv_energy;
        vec3 glow_tint = mix(vec3(1.0, 0.3, 0.1), band_color, audio_mix);
        float glow_boost = mix(1.0, clamp(band_energy, 0.0, 3.0), audio_mix);

        vec3 acc_col = vec3(1.0, 0.3, 0.1) * accum_glow;
        vec3 glow = pow(min(vec3(1.5, 1.0, 1.0) * accum_glow, 1.0), vec3(1.0, 2.5, 12.0)) * 0.5 + acc_col * 0.5;
        vec3 glow_base = mix(col, glow_tint, audio_mix);
        col += glow_base * glow * glow_gain * glow_boost;

        float hi = abs(mod(t + 0.02 * texture(env_tex, pos.xy).x, 8.0) - 4.0) * 2.0;
        vec3 charge = vec3(0.01, 0.05, 1.0) * col / (0.001 + hi * hi * 0.2);
        col += mix(charge.yxz, charge, noise3(pos * 3.0));

        col *= ao * shadow * attenuation;
    }

    vec3 fog = vec3(0.125, 0.04, 0.05) * (ray_dir.y * 0.5 + 0.5);
    col = mix(col, fog, smoothstep(0.0, fog_mix, t / FAR));

    vec2 vignette_uv = uv;
    col = mix(vec3(0.0), col, pow(16.0 * vignette_uv.x * vignette_uv.y * (1.0 - vignette_uv.x) * (1.0 - vignette_uv.y), 0.125) * 0.5 + 0.5);

    COLOR = vec4(sqrt(clamp(col, 0.0, 1.0)), 1.0);
}