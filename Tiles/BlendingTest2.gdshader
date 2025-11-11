shader_type canvas_item;

// Noise and decal tileset shader by Big Boy Games (Jesse)

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform sampler2D decal : repeat_enable, filter_nearest;
uniform bool displayDecal = false;
varying vec2 worldUV;
uniform float noise_scale = 0.01;
uniform float decal_scale = 0.4;

void vertex() {
	worldUV = (MODEL_MATRIX*vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 noiseCorrect = vec2(1.0,1.0)/vec2(textureSize(noise, 0));
	vec2 decalCorrect = vec2(1.0,1.0)/vec2(textureSize(decal, 0));

	COLOR.rgb = mix(COLOR.rgb, texture(noise, worldUV*noiseCorrect*noise_scale).rgb, texture(noise, worldUV*noiseCorrect*noise_scale).rgb);

	if (displayDecal) {
		COLOR.rgb = mix(COLOR.rgb, texture(decal, worldUV*decalCorrect*decal_scale).rgb, texture(decal, worldUV*decalCorrect*decal_scale).a * texture(noise, worldUV*noiseCorrect*noise_scale).a);
	}
}