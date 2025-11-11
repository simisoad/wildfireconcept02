shader_type spatial;

uniform sampler2D logic_map; // Unsere Karte mit den Typ-IDs im R-Kanal
uniform float blend_distance : hint_range(0.0, 0.1, 0.001) = 0.02; // Wie weit der Übergang reicht
uniform float texture_scale : hint_range(0.1, 10.0, 0.1) = 1.0; // Skalierung der Texturen

// Die Texturen für die verschiedenen Bodentypen
uniform sampler2D farmland_texture;
uniform sampler2D forest_texture;
uniform sampler2D grass_texture;
uniform sampler2D grassland_texture;
uniform sampler2D residential_texture;
uniform sampler2D vineyard_texture;
uniform sampler2D water_texture;

// Hilfsfunktion um Typ-ID aus der Logic-Map zu lesen
int get_type_id(vec2 uv) {
    float type_id_float = texture(logic_map, uv).r * 255.0;
    return int(type_id_float + 0.5); // +0.5 für bessere Rundung
}

// Hilfsfunktion um die Textur für einen bestimmten Typ zu sampeln
vec3 sample_texture_for_type(int type_id, vec2 uv) {
    if (type_id == 1) {
        return texture(water_texture, uv * texture_scale).rgb;
    } else if (type_id == 2) {
        return texture(grass_texture, uv * texture_scale).rgb;
    } else if (type_id == 3) {
        return texture(grassland_texture, uv * texture_scale).rgb;
    } else if (type_id == 4) {
        return texture(farmland_texture, uv * texture_scale).rgb;
    } else if (type_id == 5) {
        return texture(residential_texture, uv * texture_scale).rgb;
    } else if (type_id == 6) {
        return texture(vineyard_texture, uv * texture_scale).rgb;
    } else if (type_id == 7) {
        return texture(forest_texture, uv * texture_scale).rgb;
    } else {
        return texture(grass_texture, uv * texture_scale).rgb;
    }
}

void fragment() {
    // Aktuelle Typ-ID
    int center_type = get_type_id(UV);

    // Basis-Textur für den aktuellen Typ
    vec3 final_color = sample_texture_for_type(center_type, UV);

    // Texel-Größe der Logic-Map berechnen
    vec2 texel_size = 1.0 / vec2(textureSize(logic_map, 0));

    // Nachbar-Pixel überprüfen und weiche Übergänge erstellen
    float total_weight = 1.0;

    // 8-er Nachbarschaft überprüfen
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue; // Zentrum überspringen

            vec2 neighbor_uv = UV + vec2(float(x), float(y)) * texel_size;

            // Rand-Überprüfung
            if (neighbor_uv.x < 0.0 || neighbor_uv.x > 1.0 ||
                neighbor_uv.y < 0.0 || neighbor_uv.y > 1.0) continue;

            int neighbor_type = get_type_id(neighbor_uv);

            // Wenn der Nachbar einen anderen Typ hat, Übergang erstellen
            if (neighbor_type != center_type) {
                // Distanz zum Rand berechnen
                float distance = length(vec2(float(x), float(y)) * texel_size);

                // Blend-Gewicht basierend auf Distanz
                float blend_weight = smoothstep(0.0, blend_distance, distance);
                blend_weight = 1.0 - blend_weight;
                blend_weight = max(0.0, blend_weight);

                if (blend_weight > 0.0) {
                    // Nachbar-Textur sampeln
                    vec3 neighbor_color = sample_texture_for_type(neighbor_type, UV);

                    // Farben mischen
                    final_color = mix(final_color, neighbor_color, blend_weight * 0.3);
                    total_weight += blend_weight * 0.3;
                }
            }
        }
    }

    // Normalisierung
    final_color /= total_weight;

    ALBEDO = final_color;
    SPECULAR = 0.1;
    METALLIC = 0.0;
    ROUGHNESS = 0.8;
    ALPHA = 1.0;
}