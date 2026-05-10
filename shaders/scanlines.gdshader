shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.20;
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.025;
uniform float chromatic_aberration : hint_range(0.0, 4.0) = 1.0;
uniform vec2 viewport_size = vec2(640.0, 480.0);
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
    vec2 uv = SCREEN_UV;
    float px = 1.0 / viewport_size.x;

    // chromatic aberration sutil
    float r = texture(screen_tex, uv + vec2( px * chromatic_aberration, 0.0)).r;
    float g = texture(screen_tex, uv).g;
    float b = texture(screen_tex, uv - vec2( px * chromatic_aberration, 0.0)).b;
    vec3 col = vec3(r, g, b);

    // scanlines
    float scan = sin(uv.y * viewport_size.y * 3.14159) * 0.5 + 0.5;
    col *= mix(1.0, scan, scanline_intensity);

    // flicker temporal
    col *= 1.0 - (sin(TIME * 30.0) * flicker_intensity);

    // vinheta
    vec2 d = uv - vec2(0.5);
    float v = smoothstep(0.4, 0.95, length(d));
    col = mix(col, vignette_color.rgb, v * vignette_strength);

    COLOR = vec4(col, 1.0);
}