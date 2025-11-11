shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_test_disabled, shadows_disabled, unshaded;

uniform sampler2D albedo_texture;
uniform float multiply_strength : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_offset : hint_range(-1.0, 1.0) = 0.0;
uniform float alpha_strength : hint_range(0.0, 1.0, 0.1) = 1.0;

void fragment() {
    vec4 tex_color = texture(albedo_texture, UV);

    // Angepasste Multiply-Formel für weniger Dunkelheit
    vec3 result = mix(vec3(1.0), tex_color.rgb, multiply_strength);

    // Optional: Helligkeit anpassen
    result += brightness_offset;

    ALBEDO = result;
    ALPHA = 1.0; // Kein Alpha-Channel
}