shader_type spatial;

uniform sampler2D logic_map; // Unsere Karte mit den Typ-IDs im R-Kanal

// Die Texturen für die verschiedenen Bodentypen
uniform sampler2D farmland_texture;
uniform sampler2D forest_texture;
uniform sampler2D grass_texture;
uniform sampler2D grassland_texture;
uniform sampler2D residential_texture;
uniform sampler2D vineyard_texture;
uniform sampler2D water_texture;

void fragment() {
    // Lies die Typ-ID aus der Logic-Map für die aktuelle Position
    float type_id_float = texture(logic_map, UV).r * 255.0;
    int type_id = int(type_id_float);
	float scale = 1.0;
    vec3 final_color = vec3(0.0); // Standard-Farbe (lila, für Debugging)

    // Wähle die richtige Textur basierend auf der ID
    if (type_id == 1) { // Gras
        final_color = texture(water_texture, UV * scale).rgb; // *10.0 für Tiling
    } else if (type_id == 2) { // Farmland / Erde
        final_color = texture(grass_texture, UV * scale).rgb;
    } else if (type_id == 3) { // Residential
        final_color = texture(grassland_texture, UV * scale).rgb;
	} else if (type_id == 4) { // Residential
        final_color = texture(farmland_texture, UV * scale).rgb;
	} else if (type_id == 5) { // Residential
        final_color = texture(residential_texture, UV * scale).rgb;
	} else if (type_id == 6) { // Residential
        final_color = texture(vineyard_texture, UV * scale).rgb;
	} else if (type_id == 7) { // Residential
        final_color = texture(forest_texture, UV * scale).rgb;
    }else{
		final_color = texture(grass_texture, UV * scale).rgb;
	}
    ALBEDO = final_color;
	SPECULAR = final_color.r;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}