shader_type spatial;

// Dein Texture-Atlas
uniform sampler2D texture_atlas;


// Wie viele Tiles dein Atlas in X- und Y-Richtung hat (z.B. 4x4 für 16 Tiles)
uniform vec2 atlas_size = vec2(4.0, 4.0);

void vertex() {
	// INSTANCE_CUSTOM ist ein vec4, das du pro Instanz setzen kannst.
	// Wir nutzen hier nur die x-Komponente für den Tile-Index.
	float tile_index = INSTANCE_CUSTOM.x;

	// Berechne die Spalte (x) und Zeile (y) des Tiles im Atlas
	float tile_y = floor(tile_index / atlas_size.x);
	float tile_x = mod(tile_index, atlas_size.x);

	// Berechne die Grösse eines einzelnen Tiles in UV-Koordinaten (0.0 bis 1.0)
	vec2 uv_scale = 1.0 / atlas_size;

	// Verschiebe die UV-Koordinaten des Meshes (UV), skaliere sie passend
	// und verschiebe sie dann an die richtige Stelle im Atlas.
	UV = (UV * uv_scale) + vec2(tile_x, tile_y) * uv_scale;
}

void fragment() {
	// Lese die Farbe aus dem Atlas an den neu berechneten UV-Koordinaten
	ALBEDO = texture(texture_atlas, UV).rgb;
	ALPHA = texture(texture_atlas, UV).a;
}