shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* Look/feel */
uniform vec3 filament_color : source_color = vec3(0.82, 0.95, 1.0);
uniform vec3 glow_color     : source_color = vec3(0.35, 0.75, 1.0);
uniform float bg_dim = 0.03;

uniform float field_scale   = 3.0;   // 2.4..3.6
uniform float ridge_contrast= 1.55;  // crisper ridges
uniform float filament_width= 0.015; // 0.012..0.02
uniform float trails        = 7.0;   // 3..10 micro segments

uniform float slither_rate  = 0.45;  // how fast endpoints crawl
uniform float wiggle_amp    = 0.07;  // sideways waviness
uniform float spark_gain    = 1.7;

/* --- fast noise --- */
float h11(float x){ x=fract(x*0.1031); x*=x+33.33; return fract(1e4*x*(x+0.9)); }
float n2(vec2 p){
    vec2 i=floor(p), f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    float a=h11(dot(i,vec2(1.0,57.0)));
    float b=h11(dot(i+vec2(1,0),vec2(1.0,57.0)));
    float c=h11(dot(i+vec2(0,1),vec2(1.0,57.0)));
    float d=h11(dot(i+vec2(1,1),vec2(1.0,57.0)));
    return mix(mix(a,b,u.x),mix(c,d,u.x),u.y);
}
float fbm(vec2 p){
    float s=0.0,a=0.5;
    for(int i=0;i<4;i++){ s+=a*n2(p); p=p*2.02+17.0; a*=0.55; }
    return s;
}
vec2 flow(vec2 p){
    float n1=fbm(p);
    float n2v=fbm(p+vec2(11.5,7.3));
    float a=(n1-n2v)*6.28318;
    return normalize(vec2(cos(a),sin(a)));
}

/* spectrum */
float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float band(float a,float b){
    float n=max(1.0,b-a), s=0.0;
    for(int i=0;i<64;i++){ if(float(i)>=a && float(i)<b) s+=bin(i); }
    return s/n;
}

/* distance to short segment */
float seg(vec2 p, vec2 a, vec2 b){
    vec2 ap=p-a, ab=b-a;
    float d=dot(ab,ab);
    float h=d>1e-5?clamp(dot(ap,ab)/d,0.0,1.0):0.0;
    return length(ap-ab*h);
}

void fragment(){
    vec2 uv = UV*2.0-1.0; uv.x*=aspect;
    float t = TIME;

    float wf = texture(waveform_tex, vec2(fract(t*0.25),0.5)).r;
    wf = (wf*2.0-1.0)*0.02;

    float low  = enable_audio?band(0.0,10.0)*audio_gain:0.0;
    float mid  = enable_audio?band(10.0,28.0)*audio_gain:0.0;
    float high = enable_audio?band(28.0,56.0)*audio_gain:0.0;

    // Stationary sample position; persistent field
    float zoom = field_scale * (1.0 - 0.05*low);
    vec2  P = uv * zoom;

    // Ridged mask keeps a sparse network that won’t blob
    float rid = abs(0.5 - fbm(P + vec2(0.37*t, -0.29*t)));
    rid = pow(clamp(rid*2.0,0.0,1.0), ridge_contrast); // 0..1 lines

    float width = filament_width * mix(1.0,0.7, clamp(high,0.0,1.0));

    vec3 col = vec3(bg_dim);
    float f_acc=0.0, s_acc=0.0;

    int copies = int(clamp(trails,2.0,12.0));
    for(int i=0;i<12;i++){
        if(i>=copies) break;
        float k=float(i);

        // Anchor in field space with tiny jitter
        vec2 anchor = P + (vec2(h11(k*13.3),h11(k*7.7))-0.5) * (0.9);

        // Local flow
        vec2 d = flow(anchor + vec2(0.6*t,-0.5*t));

        // Endpoints crawl **along the flow** → organic slither
        float crawl = slither_rate * (1.0 + 0.6*mid + 0.6*low);
        //vec2 slide = d * (t*crawl + wf);
		float osc = sin(t*crawl + k*1.73 + wf*3.0);   // per-wire phase
vec2  slide = d * (osc * 0.22);               // ~22% of unit length

        // sideways wiggle so lines breathe
        vec2 nrm = vec2(-d.y, d.x);
        float wav = sin((dot(anchor,vec2(1.7,2.3))+t*1.5) + k)*wiggle_amp*(0.6+0.8*mid);

        vec2 C = (anchor + slide)/zoom;
        float half_len = mix(0.18,0.32, clamp(mid,0.0,1.0));
        vec2 A = C - d*half_len + nrm*wav;
        vec2 B = C + d*half_len - nrm*wav;

        float dist = seg(uv, A, B);
        float wire = exp(-pow(dist/max(1e-4,width), 2.0)) * rid;
        f_acc += wire;

        if(enable_audio){
            // Sparks travel along the wire direction (not screen space)
            float speed = 1.8 + 2.6*high + 3.5*kick;
            float proj  = dot(uv-C, d);
            float ph    = proj*7.0 + t*speed + k;
            float spark = max(0.0, sin(ph));
            spark = pow(spark, 14.0) * (0.7 + 0.9*high) * (1.0 + 1.4*kick);
            s_acc += spark * wire; // only where the wire exists
        }
    }

    vec3 fil = filament_color * f_acc * (1.0 + 0.8*low);
    vec3 glo = glow_color * (0.25*f_acc + spark_gain*s_acc);

    col += fil + glo;

    float vig = smoothstep(1.35, 0.45, length(uv));
    col *= vig;

    COLOR = vec4(clamp(col,0.0,3.0),1.0);
}
