shader_type canvas_item;

/* Audio (optional) */
uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid  = 0.45;
uniform float u_high = 0.78;

/* Look */
uniform float aspect = 1.7777;
uniform float cell_scale : hint_range(2.0, 20.0) = 9.0;
uniform float edge_soft  : hint_range(0.5, 4.0) = 1.8;
uniform float glow       : hint_range(0.0, 2.0) = 0.9;

float samp(float u){
    float du=0.01, a=0.0; for(int k=-2;k<=2;k++){ a+=texture(spectrum_tex, vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; }
    return a/5.0;
}
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453123); }

void fragment(){
    vec2 q = vec2(UV.x, 1.0-UV.y);
    vec2 p = -1.0 + 2.0*q; p.x *= aspect;

    float bass = use_audio ? samp(u_bass) : 0.25+0.06*sin(TIME*0.6);
    float mid  = use_audio ? samp(u_mid ) : 0.25+0.05*sin(TIME*0.4+1.1);
    float hi   = use_audio ? samp(u_high) : 0.25+0.08*sin(TIME*0.9+2.0);

    vec2 gp = p * cell_scale;
    vec2 g  = floor(gp), f = fract(gp);

    // Find nearest (and second) feature points (classic Voronoi)
    float d1 = 1e9, d2 = 1e9; vec2 id1 = vec2(0.0);
    for(int j=-1;j<=1;j++){
        for(int i=-1;i<=1;i++){
            vec2 o = vec2(float(i),float(j));
            vec2 h = g + o;
            // jittered seed that also "breathes" with bass
            vec2 seed = vec2(hash(h), hash(h+19.7));
            seed = 0.5 + 0.35*(seed-0.5)*(1.0+0.7*bass);
            vec2 r = o + seed - f;
            float d = dot(r,r);
            if(d < d1){ d2=d1; d1=d; id1=h; }
            else if(d < d2){ d2 = d; }
        }
    }

    // Cell id -> color
    float hue = hash(id1*3.17);
    vec3  base = mix(vec3(0.16,0.22,0.32), vec3(0.3,0.8,1.0), 0.55+0.35*sin(hue*TAU + 2.0*mid + TIME*0.3));

    // Edge factor from nearest & second nearest
    float edge = clamp((sqrt(d2)-sqrt(d1))*cell_scale, 0.0, 1.0);
    float e    = smoothstep(0.0, edge_soft*0.25, edge);

    // Audio accents on edges (highs)
    float ping = pow(hi, 1.2);
    vec3 col = mix(base*0.8, base, e) + glow*ping*(1.0-e)*vec3(0.5,0.8,1.2);

    // Gentle vignette
    col *= smoothstep(1.7,0.6,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
