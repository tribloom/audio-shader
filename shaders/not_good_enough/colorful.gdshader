shader_type canvas_item;

/* ---- Controls ---- */
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float aspect = 1.7777778;            // you already drive this
uniform float view_scale = 30.0;             // Shadertoy "* 30."
uniform int   ds_factor : hint_range(1, 4) = 2; // 1=off, 2=half, 3=third (internal)

/* ---- Constants ---- */
const int L_ITERS = 120;

/* ---- Original eval (ltBcRc core) ---- */
vec3 eval_color_from_v(vec2 v, float iTime) {
    vec2 vv = v;

    float ft = iTime + 360.1;
    float tm = ft * 0.1;
    float tm2 = ft * 0.3;

    vec2 mspt_part = vec2(0.0, 0.0);
    mspt_part.x = sin(tm) + cos(tm * 0.2) + sin(tm * 0.5) + cos(tm * -0.4) + sin(tm * 1.3);
    mspt_part.y = cos(tm) + sin(tm * 0.1) + cos(tm * 0.8) + sin(tm * -1.1) + cos(tm * 1.5);
    vec2 mspt = (mspt_part + vec2(1.0, 1.0)) * 0.35;

    float R = 0.0;
    float RR = 0.0;
    float RRR = 0.0;

    float a = (1.0 - mspt.x) * 0.5;

    float C  = cos(tm2 * 0.03 + a * 0.01) * 1.1;
    float S  = sin(tm2 * 0.033 + a * 0.23) * 1.1;
    float C2 = cos(tm2 * 0.024 + a * 0.23) * 3.1;
    float S2 = sin(tm2 * 0.03  + a * 0.01) * 3.3;

    vec2 xa  = vec2(C,  -S);
    vec2 ya  = vec2(S,   C);
    vec2 xa2 = vec2(C2, -S2);
    vec2 ya2 = vec2(S2,  C2);

    vec2 shift  = vec2( 0.033,  0.14);
    vec2 shift2 = vec2(-0.023, -0.22);

    float Z = 0.4 + mspt.y * 0.3;
    float m = 0.99 + sin(iTime * 0.03) * 0.003;

    for (int i = 0; i < L_ITERS; i++) {
        float r  = dot(v,  v);
        float r2 = dot(vv, vv);

        if (r > 1.0) {
            float invr = 1.0 / r;
            v.x = v.x * invr;
            v.y = v.y * invr;
        }
        if (r2 > 1.0) {
            float invr2 = 1.0 / r2;
            vv.x = vv.x * invr2;
            vv.y = vv.y * invr2;
        }

        R  = R  * m;
        R  = R  + r;
        R  = R  * m;
        R  = R  + r2;

        if (i < L_ITERS - 1) {
            RR = RR * m;
            RR = RR + r;
            RR = RR * m;
            RR = RR + r2;

            if (i < L_ITERS - 2) {
                RRR = RRR * m;
                RRR = RRR + r;
                RRR = RRR * m;
                RRR = RRR + r2;
            }
        }

        float vx = dot(v,  xa);
        float vy = dot(v,  ya);
        v  = vec2(vx,  vy)  * Z + shift;

        float vvx = dot(vv, xa2);
        float vvy = dot(vv, ya2);
        vv = vec2(vvx, vvy) * Z + shift2;
    }

    float c = fract(R);
    if (mod(R, 2.0) > 1.0) {
        c = 1.0 - c;
    }

    float cc = fract(RR);
    if (mod(RR, 2.0) > 1.0) {
        cc = 1.0 - cc;
    }

    float ccc = fract(RRR);
    if (mod(RRR, 2.0) > 1.0) {
        ccc = 1.0 - ccc;
    }

    vec3 col = vec3(ccc, cc, c);
    return col;
}

/* ---- Map UV -> v, same as Shadertoy path ---- */
vec2 uv_to_v(vec2 uv_local) {
    vec2 uvc = uv_local - 0.5;
    uvc.y = -uvc.y;

    vec2 res_over_min = vec2(1.0, 1.0);
    if (aspect >= 1.0) {
        res_over_min = vec2(aspect, 1.0);
    } else {
        res_over_min = vec2(1.0, 1.0 / aspect);
    }

    vec2 v = uvc * res_over_min * view_scale;
    return v;
}

/* ---- Internal downsample + bilinear upsample (no scene changes) ---- */
vec3 downsampled_color(vec2 uv_local, float iTime) {
    if (ds_factor <= 1) {
        vec2 v_direct = uv_to_v(uv_local);
        return eval_color_from_v(v_direct, iTime);
    }

    // Per-axis pixel size in UV, from derivatives
    float px = abs(dFdx(uv_local.x)) + abs(dFdy(uv_local.x));
    float py = abs(dFdx(uv_local.y)) + abs(dFdy(uv_local.y));
    vec2 uv_px = vec2(px, py);

    // Size of one low-res texel in UV
    float fds = float(ds_factor);
    vec2 step_uv = uv_px * fds;

    // Low-res grid index and fractional position inside the cell
    vec2 pos = uv_local / step_uv;
    vec2 ipos = floor(pos);
    vec2 frac = pos - ipos;

    // Centers of the four neighboring low-res texels
    vec2 uv00 = (ipos + vec2(0.5, 0.5)) * step_uv;
    vec2 uv10 = (ipos + vec2(1.5, 0.5)) * step_uv;
    vec2 uv01 = (ipos + vec2(0.5, 1.5)) * step_uv;
    vec2 uv11 = (ipos + vec2(1.5, 1.5)) * step_uv;

    // Clamp to the valid range to avoid sampling outside
    uv00 = clamp(uv00, vec2(0.0, 0.0), vec2(1.0, 1.0));
    uv10 = clamp(uv10, vec2(0.0, 0.0), vec2(1.0, 1.0));
    uv01 = clamp(uv01, vec2(0.0, 0.0), vec2(1.0, 1.0));
    uv11 = clamp(uv11, vec2(0.0, 0.0), vec2(1.0, 1.0));

    // Evaluate the fractal at the four low-res centers
    vec3 c00 = eval_color_from_v(uv_to_v(uv00), iTime);
    vec3 c10 = eval_color_from_v(uv_to_v(uv10), iTime);
    vec3 c01 = eval_color_from_v(uv_to_v(uv01), iTime);
    vec3 c11 = eval_color_from_v(uv_to_v(uv11), iTime);

    // Bilinear upsample back to the current pixel
    float fx = frac.x;
    float fy = frac.y;

    vec3 cx0 = mix(c00, c10, fx);
    vec3 cx1 = mix(c01, c11, fx);
    vec3 col = mix(cx0, cx1, fy);

    return col;
}

/* ---- Fragment ---- */
void fragment() {
    float iTime = TIME * time_scale;
    vec3 col = downsampled_color(UV, iTime);
    COLOR = vec4(col, 1.0);
}
