shader_type spatial;

uniform sampler2D logic_map : filter_nearest;
uniform float blend_radius : hint_range(1.0, 20.0, 1.0) = 1.0; // Pixel-Radius für Blending
uniform float texture_scale : hint_range(0.1, 10.0, 0.1) = 1.0;

// Texturen
uniform sampler2D farmland_texture;
uniform sampler2D forest_texture;
uniform sampler2D grass_texture;
uniform sampler2D grassland_texture;
uniform sampler2D residential_texture;
uniform sampler2D vineyard_texture;
uniform sampler2D water_texture;

int get_type_id(vec2 uv) {
    // Clamp UV to avoid sampling outside bounds
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    float type_id_float = texture(logic_map, uv).r * 255.0;
    return int(round(type_id_float));
}

vec3 sample_texture_for_type(int type_id, vec2 uv) {
    switch (type_id) {
        case 1: return texture(water_texture, uv * texture_scale).rgb;
        case 2: return texture(grass_texture, uv * texture_scale).rgb;
        case 3: return texture(grassland_texture, uv * texture_scale).rgb;
        case 4: return texture(farmland_texture, uv * texture_scale).rgb;
        case 5: return texture(residential_texture, uv * texture_scale).rgb;
        case 6: return texture(vineyard_texture, uv * texture_scale).rgb;
        case 7: return texture(forest_texture, uv * texture_scale).rgb;
        default: return texture(grass_texture, uv * texture_scale).rgb;
    }
}

void fragment() {
    vec2 texel_size = 1.0 / vec2(textureSize(logic_map, 0));
    int center_type = get_type_id(UV);

    // Basis-Farbe
    vec3 final_color = sample_texture_for_type(center_type, UV);

    // Sammle alle Typen in der Umgebung
    float type_weights[8] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}; // Index = type_id - 1
    float total_weight = 0.0;

    // Sample in einem Kreis um den aktuellen Pixel
    int radius = int(blend_radius);
    for (int x = -radius; x <= radius; x++) {
        for (int y = -radius; y <= radius; y++) {
            vec2 offset = vec2(float(x), float(y));
            float distance = length(offset);

            // Nur innerhalb des Radius sampeln
            if (distance <= blend_radius) {
                vec2 sample_uv = UV + offset * texel_size;
                int sample_type = get_type_id(sample_uv);

                if (sample_type >= 1 && sample_type <= 7) {
                    // Gewicht basierend auf Distanz (näher = mehr Gewicht)
                    float weight = 1.0 - (distance / blend_radius);
                    weight = weight * weight; // Quadratischer Falloff

                    type_weights[sample_type - 1] += weight;
                    total_weight += weight;
                }
            }
        }
    }

    // Normalisiere Gewichte
    if (total_weight > 0.0) {
        for (int i = 0; i < 7; i++) {
            type_weights[i] /= total_weight;
        }

        // Mische alle Texturen basierend auf ihren Gewichten
        final_color = vec3(0.0);
        for (int type_id = 1; type_id <= 7; type_id++) {
            float weight = type_weights[type_id - 1];
            if (weight > 0.001) {
                final_color += sample_texture_for_type(type_id, UV) * weight;
            }
        }
    }

    ALBEDO = final_color;
    SPECULAR = 0.1;
    METALLIC = 0.0;
    ROUGHNESS = 0.8;
}