shader_type canvas_item;

/*
 * Port of the "drop" raymarch audio sphere from Shadertoy.
 * Uses the project's spectrum_tex (1xN RG8 strip) for audio reactivity
 * and replaces the original sampler inputs with procedural lookups so the
 * effect can run inside the visualizer without external textures.
 */

// ---- Inputs provided by the visualizer ----
uniform sampler2D spectrum_tex : hint_default_black;
uniform float aspect = 1.7777;
uniform int bar_count = 64;

// Optional gain so users can tweak from the editor if needed
uniform float audio_gain = 1.0;

// Allow tweaking of previously hard-coded constants from the editor.
uniform float ray_march_tolerance = 0.01;
uniform int   ray_march_num_steps = 64;
uniform float camera_fov_adjust = 1.0;
uniform vec3  camera_pos = vec3(0.0, 0.0, -5.0);
uniform vec3  env_light = vec3(0.2, 0.2, 0.25);
uniform vec3  background_color = vec3(0.08, 0.10, 0.18);

// ---- Constants mirroring the original shader ----
//const float PI = 3.14159265;

// Simple light description (float because bool fields are awkward in Godot)
struct WorldLight {
    float enabled; // 0.0 or 1.0
    vec3  color;   // intensity encoded in magnitude
    vec3  position;
};

const int MAX_RAY_MARCH_STEPS = 256;

WorldLight make_light(float enabled, vec3 color, vec3 position){
    WorldLight l;
    l.enabled = enabled;
    l.color = color;
    l.position = position;
    return l;
}

WorldLight get_light(int index){
    if (index == 0){
        return make_light(1.0, vec3(1.0, 1.0, 1.0), vec3(1.0, 0.7, -3.0));
    }
    if (index == 1){
        return make_light(1.0,
                          vec3(0.7, 0.4, 0.3),
                          vec3(-3.0, 3.0 * cos(TIME / 1.5), 0.2 + 2.0 * sin(TIME) + 0.8));
    }
    return make_light(0.0, vec3(0.0), vec3(0.0));
}

// ---- Audio helpers -------------------------------------------------------
const int MAX_AUDIO_BINS = 128; // guard for loops

float spectrum_sample(int i){
    int bc = max(bar_count, 1);
    i = clamp(i, 0, bc - 1);
    float x = (float(i) + 0.5) / float(bc);
    return texture(spectrum_tex, vec2(x, 0.5)).r * audio_gain;
}

float spectrum_average(int start_idx, int count){
    int bc = max(bar_count, 1);
    if (count <= 0){
        return 0.0;
    }
    int end_idx = clamp(start_idx + count, 0, bc);
    float accum = 0.0;
    int n = max(1, end_idx - start_idx);
    for (int i = 0; i < MAX_AUDIO_BINS; i++){
        if (i >= n){ break; }
        accum += spectrum_sample(start_idx + i);
    }
    return accum / float(n);
}

float bass_intensity(int range_bins){
    int bc = max(bar_count, 1);
    int n = clamp(range_bins, 1, bc);
    return spectrum_average(0, n);
}

float audio_volume(){
    int bc = max(bar_count, 1);
    float sum = 0.0;
    for (int i = 0; i < MAX_AUDIO_BINS; i++){
        if (i >= bc){ break; }
        sum += spectrum_sample(i);
    }
    float avg = sum / float(max(1, bc));
    return abs(pow(avg, 4.2));
}

bool is_dropped(){
    float gate = bass_intensity(40) - 0.1;
    return gate >= 0.5;
}

// ---- Scene distance + helpers -------------------------------------------
float sdf_dist_point2sphere(vec3 point, vec3 center, float radius){
    return length(point - center) - radius;
}

float sdf_compute_scene(vec3 point){
    float drop_gate = is_dropped() ? 1.0 : 0.0;
    float displacement = sin(cos(TIME * 2.0) * point.x * 0.5) * tan(drop_gate * point.y) *
                         sin(5.0 * sin(TIME + 3.2) * point.z);

    float sphere_x;
    float sphere_y;
    float sphere_z;
    if (drop_gate > 0.5){
        sphere_z = 0.2 + 2.0 * sin(TIME * 1.5);
        sphere_y = 3.0 * cos(TIME);
        sphere_x = cos(TIME) * 6.0;
    } else {
        sphere_z = 0.2 + 2.0 * sin(TIME / 4.0);
        sphere_y = 3.0 * cos(TIME / 8.0);
        sphere_x = 0.0; // mouse-free version
    }

    float sphere = sdf_dist_point2sphere(point, vec3(sphere_x, sphere_y, sphere_z), 1.0);
    return sphere + displacement;
}

vec3 sdf_compute_scene_normal(vec3 point){
    const float NORMAL_STEP = 0.001;
    vec3 step = vec3(NORMAL_STEP, 0.0, 0.0);
    float dx = sdf_compute_scene(point + step) - sdf_compute_scene(point - step);
    float dy = sdf_compute_scene(point + step.yxz) - sdf_compute_scene(point - step.yxz);
    float dz = sdf_compute_scene(point + step.yzx) - sdf_compute_scene(point - step.yzx);
    return normalize(vec3(dx, dy, dz));
}

bool ray_march(vec3 ray_origin, vec3 ray_dir, out vec3 hit_pos){
    hit_pos = ray_origin;
    float march_step = sdf_compute_scene(ray_origin);
    int max_steps = clamp(ray_march_num_steps, 1, MAX_RAY_MARCH_STEPS);
    for (int i = 0; i < MAX_RAY_MARCH_STEPS; i++){
        if (i >= max_steps){
            break;
        }
        hit_pos += ray_dir * march_step;
        march_step = sdf_compute_scene(hit_pos);
        if (march_step <= ray_march_tolerance){
            return true;
        }
    }
    return false;
}

// ---- Look + shading ------------------------------------------------------
vec3 bg_gradient(vec2 uv){
    float vol = clamp(audio_volume() * 2.0, 0.0, 1.0);
    vec3 base = vec3(vol, (1.0 - vol * 2.0) * (1.0 - bass_intensity(20)), (1.0 - vol * 2.0) * (1.0 - bass_intensity(20)));
    vec3 sky = background_color + vec3(0.35, 0.25, 0.45) * uv.y;
    vec3 drop_col = vec3(1.0, 0.1, 0.05);
    return mix(base, is_dropped() ? drop_col : sky, vol);
}

vec3 procedural_albedo(vec3 normal, float drop_gate){
    vec3 wave = 0.5 + 0.5 * sin(normal.xyx * 3.5 + vec3(0.0, 2.0, 4.0) + TIME * vec3(0.4, 0.6, 0.8));
    if (drop_gate > 0.5){
        return wave * 0.3;
    }
    return mix(wave, vec3(0.5), 0.8);
}

float procedural_spec_mask(vec3 normal){
    float m = pow(clamp(1.0 - abs(normal.y), 0.0, 1.0), 2.5);
    return clamp(m, 0.0, 1.0);
}

vec3 ray_march_shade(vec3 ray_origin, vec3 ray_dir, vec2 uv){
    vec3 hit_pos;
    if (!ray_march(ray_origin, ray_dir, hit_pos)){
        return bg_gradient(uv);
    }

    vec3 normal = sdf_compute_scene_normal(hit_pos);
    vec3 view_dir = normalize(camera_pos - hit_pos);

    float drop_gate = is_dropped() ? 1.0 : 0.0;
    vec3 albedo = procedural_albedo(normal, drop_gate);
    vec3 spec_color = drop_gate > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(1.0);
    float spec_mask = procedural_spec_mask(normal);

    vec3 lighting = vec3(0.0);
    for (int i = 0; i < 8; i++){
        WorldLight light = get_light(i);
        if (light.enabled < 0.5){
            continue;
        }
        vec3 light_dir = normalize(light.position - hit_pos);
        vec3 half_dir = normalize(view_dir + light_dir);
        vec3 diff = light.color * clamp(dot(light_dir, normal), 0.0, 1.0);
        float spec_term = pow(clamp(dot(normal, half_dir), 0.0, 1.0), 8.0);
        vec3 spec = spec_color * spec_term * spec_mask;
        lighting += diff + spec;
    }

    vec3 fresnel = spec_color * pow(clamp(1.0 - dot(normal, view_dir), 0.0, 1.0), 2.3);
    return albedo * (lighting + env_light) + fresnel;
}

void fragment(){
    vec2 uv = UV * 2.0 - 1.0;
    if (aspect >= 1.0){
        uv.x *= aspect;
    } else {
        uv.y /= max(aspect, 0.0001);
    }

    vec3 ray_dir = normalize(vec3(uv.x, uv.y, camera_fov_adjust));
    vec3 color = ray_march_shade(camera_pos, ray_dir, uv);
    COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}