shader_type sky;

// Clouds are baked only when a time/weather uniform changes. Looking around
// reads the cached cubemap; there is deliberately no TIME or camera POSITION.
uniform vec3 zenith_color : source_color = vec3(0.22, 0.43, 0.64);
uniform vec3 horizon_color : source_color = vec3(0.80, 0.77, 0.68);
uniform vec3 ground_color : source_color = vec3(0.20, 0.28, 0.23);
uniform vec3 cloud_light : source_color = vec3(0.98, 0.87, 0.71);
uniform vec3 cloud_shadow : source_color = vec3(0.46, 0.53, 0.59);
uniform vec3 light_color : source_color = vec3(1.0, 0.82, 0.60);
uniform vec3 light_direction = vec3(-0.7, 0.3, 0.6);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float moonlight : hint_range(0.0, 1.0) = 0.0;
uniform bool direct_sky = false;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.52;
	mat2 turn = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise2(p);
		p = turn * p * 2.07 + vec2(13.7, 9.2);
		amplitude *= 0.48;
	}
	return value;
}

float cloud_field(vec2 p) {
	vec2 warp = vec2(noise2(p * 0.55 + 19.2), noise2(p * 0.55 - 7.6));
	return fbm(p + warp * 1.5);
}

void sky() {
	if (AT_CUBEMAP_PASS || direct_sky) {
		vec3 dir = normalize(EYEDIR);
		vec3 light_dir = normalize(light_direction);
		float altitude = max(dir.y, 0.0);
		float elevation = pow(altitude, 0.38);
		vec3 atmosphere = mix(horizon_color, zenith_color, elevation);
		float toward_light = max(dot(dir, light_dir), 0.0);
		float horizon_band = exp(-altitude * 9.5) * pow(toward_light, 2.2) * 0.24;
		float glow = pow(toward_light, 7.0) * 0.20 + pow(toward_light, 72.0) * 0.26 + horizon_band;
		atmosphere += light_color * glow * daylight * (1.0 - overcast * 0.82);

		// Subtle stars at night in clear sky above the horizon
		if (moonlight > 0.3 && overcast < 0.5 && altitude > 0.08) {
			vec2 star_uv = dir.xz / (altitude + 0.35) * 95.0;
			float star = pow(hash21(floor(star_uv)), 26.0) * smoothstep(0.08, 0.35, altitude);
			atmosphere += vec3(0.85, 0.92, 1.0) * star * moonlight * (1.0 - overcast) * 0.85;
		}

		// Projected cloud deck
		vec2 cloud_uv = dir.xz / (altitude + 0.14) * 2.0 + vec2(7.4, -3.2);
		float field = cloud_field(cloud_uv);
		float threshold = mix(0.60, 0.32, cloud_cover);
		float body = smoothstep(threshold + 0.025, threshold + 0.14, field);
		float horizon_fade = smoothstep(0.015, 0.16, altitude);
		float opacity = body * horizon_fade;
		float lit_field = cloud_field(cloud_uv + light_dir.xz * 0.32);
		float edge_light = clamp((field - lit_field) * 5.2 + 0.32, 0.0, 1.0);
		float silver = pow(toward_light, 12.0) * (1.0 - body * 0.65) * 0.82;
		vec3 clouds = mix(cloud_shadow, cloud_light,
			clamp(edge_light + (1.0 - body) * 0.32 + silver, 0.0, 1.0));
		clouds += light_color * pow(toward_light, 5.0) * edge_light * daylight * 0.16 * (1.0 - overcast);
		clouds = mix(horizon_color, clouds, smoothstep(0.02, 0.35, altitude) * 0.86 + 0.14);
		vec3 result = mix(atmosphere, clouds, opacity * 0.96);

		// Thin high cirrus wisps
		float wisps = smoothstep(0.56, 0.78, fbm(cloud_uv * vec2(0.42, 1.9) + 41.0));
		result = mix(result, cloud_light, wisps * 0.24 * horizon_fade * (1.0 - opacity) * (1.0 - overcast));
		float disc = smoothstep(cos(0.013), cos(0.005), toward_light);
		result += light_color * disc * (daylight * 2.4 + moonlight * 0.65) * (1.0 - opacity) * (1.0 - overcast * 0.95);
		result = mix(result, ground_color, smoothstep(0.0, 0.32, -dir.y));
		COLOR = result;
	} else {
		COLOR = texture(RADIANCE, EYEDIR).rgb;
	}
}
