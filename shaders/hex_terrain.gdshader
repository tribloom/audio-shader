shader_type canvas_item;

/*** Audio (optional) ***/
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass : hint_range(0.0,1.0) = 0.18; // low bin
uniform float u_mid  : hint_range(0.0,1.0) = 0.38; // mid bin
uniform float u_hi   : hint_range(0.0,1.0) = 0.75; // high bin

/*** Look / feel ***/
uniform float aspect    : hint_range(0.1,4.0) = 1.7777;
uniform float scale     : hint_range(6.0,30.0) = 14.0; // hex density
uniform float steps     : hint_range(2.0,24.0) = 10.0; // height quantization
uniform float height_amp: hint_range(0.0,3.0)  = 1.6;  // bass -> height
uniform float wall_base : hint_range(0.01,0.25) = 0.06; // base wall thickness (normalized)
uniform float wall_gain : hint_range(0.0,0.35)  = 0.18; // extra thickness from height
uniform float edge_w    : hint_range(1.0,5.0)   = 2.4;  // outline sharpness

/*** Colors ***/
uniform vec3 bg_lo   = vec3(0.02, 0.04, 0.07);
uniform vec3 bg_hi   = vec3(0.08, 0.10, 0.13);
uniform vec3 tile_lo = vec3(0.18, 0.22, 0.28);
uniform vec3 tile_hi = vec3(0.35, 0.65, 1.00);
uniform vec3 glow_hi = vec3(0.55, 0.85, 1.25);

/*** utils ***/
float samp(float u){
    float du=0.008, a=0.0, w=0.0;
    for(int k=-2;k<=2;k++){
        float uk = clamp(u + du*float(k), 0.0, 1.0);
        a += texture(spectrum_tex, vec2(uk, 0.25)).r; w += 1.0;
    }
    return (w>0.0)? a/w : 0.0;
}
float n2(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
float vnoise(vec2 p){
    vec2 i=floor(p), f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    float a=n2(i), b=n2(i+vec2(1,0)), c=n2(i+vec2(0,1)), d=n2(i+vec2(1,1));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

/* Tile to hex cell (pointy-top), return local coords + id */
vec3 hex_cell(vec2 p){
    const vec2 k = vec2(1.0, 1.7320508);                    // (1, sqrt(3))
    vec2 a = mod(p, k) - 0.5*k;
    vec2 b = mod(p - 0.5*k, k) - 0.5*k;
    vec2 g = (length(a) < length(b)) ? a : b;               // local coords in hex
    float id = floor((p-g).x) + 13.0*floor((p-g).y);
    return vec3(g, id);
}

/* Signed distance to unit hex border (radius=0.5) */
float sdHex(vec2 g){
    g = abs(g);
    return max(dot(g, vec2(0.8660254, 0.5)), g.y) - 0.5;    // <0 inside, 0 at border
}

void fragment(){
    // screen → centered UV with aspect
    vec2 q = vec2(UV.x, 1.0-UV.y);
    vec2 p = -1.0 + 2.0*q; p.x *= aspect;

    // audio
    float bass = use_audio ? samp(u_bass) : 0.25 + 0.06*sin(TIME*0.6);
    float mid  = use_audio ? samp(u_mid ) : 0.25 + 0.05*sin(TIME*0.4+1.7);
    float hi   = use_audio ? samp(u_hi  ) : 0.25 + 0.08*sin(TIME*0.9+3.1);

    // hex tiling
    vec2 hp = p * scale;
    vec3 hc = hex_cell(hp);
    vec2 g  = hc.xy;

    // base “height” (0..1) with steps; bass lifts it clearly
    float base = vnoise(hp*0.12 + 0.15*TIME);
    float st_n = floor(mix(steps, steps+8.0, clamp(mid,0.0,1.0)) + 0.5);
    float h    = floor((base + height_amp*bass) * st_n) / max(1.0, st_n);

    // SDFs
    float s  = -sdHex(g);                 // inside distance to border: 0 at border → 0.5 at center
    float fw = fwidth(s) * edge_w;

    // ****** FAKE EXTRUSION ******
    // make a “top face” that shrinks as height increases => visible wall ring
    float wall = wall_base + wall_gain * h;            // normalized 0..~0.35
    wall = clamp(wall, 0.01, 0.35);
    float inside = smoothstep(0.0, fw, s);             // 1 inside, 0 outside
    float top    = smoothstep(wall + fw, wall - fw, s);// 1 on top, 0 on wall
    float side   = clamp(inside - top, 0.0, 1.0);      // the ring = “wall thickness”
    float border = smoothstep(fw*2.0, 0.0, abs(s));    // crisp outline

    // lighting from gradient for subtle “height shading”
    float hx = vnoise((hp+vec2(0.8,0.0))*0.12 + 0.15*TIME);
    float hy = vnoise((hp+vec2(0.0,0.8))*0.12 + 0.15*TIME);
    float ndl= clamp(0.5 + 0.9*dot(normalize(vec2(-0.7,0.6)), normalize(vec2(hx-base,hy-base)*8.0)), 0.0, 1.0);

    // colors
    vec3 bg   = mix(bg_hi, bg_lo, q.y);
    vec3 face = mix(tile_lo, tile_hi, h) * (0.55 + 0.75*ndl + 0.35*bass);
    vec3 wallc= face * 0.70;                             // darker sides
    vec3 glow = glow_hi * pow(hi, 0.9);

    vec3 col = bg * (1.0 - inside) + wallc * side + face * top;
    col = mix(col, glow, border*0.6);                    // bright edge responds to highs

    // vignette
    col *= smoothstep(1.7, 0.5, length(p));

    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
