shader_type canvas_item;
uniform float level;
uniform float kick;
void fragment(){ COLOR = vec4(level, kick, 0.0, 1.0); }