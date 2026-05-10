shader_type canvas_item;

uniform float speed : hint_range(0.1, 5.0) = 1.5;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D noise_tex : repeat_enable, filter_linear;

vec3 hue2rgb(float h){
    return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0, 0.0, 1.0);
}

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    float t = TIME * speed;
    float h = fract(UV.x * 0.5 + UV.y * 0.5 + t * 0.2);
    vec3 rainbow = hue2rgb(h);
    // shimmer perlin se houver noise_tex
    float shimmer = texture(noise_tex, UV * 4.0 + vec2(t * 0.1, t * 0.05)).r;
    vec3 finalcol = mix(base.rgb, base.rgb * rainbow + rainbow * 0.4 * shimmer, intensity);
    COLOR = vec4(finalcol, base.a);
}