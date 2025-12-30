shader_type canvas_item;
render_mode unshaded;

// Colors
uniform vec4 bg_color       : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 line_color_a   : source_color = vec4(0.75, 0.90, 1.00, 1.0);
uniform vec4 line_color_b   : source_color = vec4(0.50, 0.20, 0.90, 1.0);

// Overall audio “strength”
uniform float audio_reactivity       : hint_range(0.0, 2.0) = 1.0;

// How audio affects different aspects (0 = off, 1 = full)
uniform float amp_reactivity         : hint_range(0.0, 1.0) = 1.0;
uniform float thickness_reactivity   : hint_range(0.0, 1.0) = 1.0;
uniform float brightness_reactivity  : hint_range(0.0, 1.0) = 1.0;
uniform float color_shift_reactivity : hint_range(0.0, 1.0) = 0.5;

// Base shape
uniform float base_amplitude         = 0.20;
uniform float base_line_width        = 0.015;
uniform float reactive_line_width    = 0.03;

// Brightness boost from audio
uniform float max_extra_brightness   = 0.5;

// Glow
uniform float glow_strength          : hint_range(0.0, 1.0) = 0.4;
uniform float glow_width_mult        : hint_range(1.0, 5.0) = 2.5;

// Color animation
uniform float gradient_scale         = 1.5;
uniform float gradient_scroll_speed  = 0.03;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float decay = 0.85;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float full_band(){ if(bar_count<=0) return 0.0; float s=0.0; for(int i=0;i<bar_count;i++) s+=bar_at_index(i); return s/max(1.0,float(bar_count)); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float line_y(vec2 p, float y, float w){ return smoothstep(w, 0.0, abs(p.y - y)); }


void fragment() {
    vec2 p = norm_uv(UV);

    // raw audio and scaled version
    float e_raw = audio_enabled ? full_band() : 0.0;
    float e     = clamp(e_raw * audio_reactivity, 0.0, 1.0);

    // amplitude reacts to audio
    float amp = base_amplitude + base_amplitude * amp_reactivity * e;

    // waveform
    float phase = TIME * 1.5;
    float y     = sin(p.x * 8.0 + phase) * amp;

    // line thickness reacts to audio
    float width = base_line_width + reactive_line_width * thickness_reactivity * e;

    // main line and two echoes
    float base  = line_y(p, y, width);
    float echo1 = line_y(p, y * 0.8, width * 0.7) * decay;
    float echo2 = line_y(p, y * 0.6, width * 0.5) * decay * decay;
    float v     = clamp(base + echo1 + echo2, 0.0, 1.0);

    // subtle glow as a wider version of the line
    float glow = line_y(p, y, width * glow_width_mult) * glow_strength;

    // gradient position, with subtle audio-driven color shift
    float color_shift = color_shift_reactivity * e * 0.25;
    float t = fract(p.x * gradient_scale + TIME * gradient_scroll_speed + color_shift);

    vec3 grad = mix(line_color_a.rgb, line_color_b.rgb, t);

    // brightness reacts to audio
    float brightness = 1.0 + max_extra_brightness * brightness_reactivity * e;

    // base line color
    vec3 line_col = grad * v * brightness;

    // glow uses the same gradient, softer
    vec3 glow_col = grad * glow;

    // composite over background
    vec3 col = bg_color.rgb;
    col += line_col;
    col += glow_col;

    // prevent blowout
    col = clamp(col, 0.0, 1.0);

    COLOR = vec4(col, 1.0);
}

 