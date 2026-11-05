shader_type spatial;
render_mode cull_disabled;
uniform vec3 low_color : source_color = vec3(.09,.19,.04);
uniform vec3 high_color : source_color = vec3(.38,.49,.14);
uniform vec3 flower_color : source_color = vec3(.78,.66,.24);
varying float shade;
varying float height;
void vertex(){
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	height=UV.y;
	shade=INSTANCE_CUSTOM.x;
	float wind=sin(world.x*.25+world.z*.17+TIME*1.55)+sin(world.x*.72-world.z*.31+TIME*2.25)*.34;
	VERTEX.x+=wind*UV.y*UV.y*.135;
	VERTEX.z+=cos(world.x*.19+TIME)*UV.y*UV.y*.055;
	float fade=1.0-smoothstep(68.0,96.0,distance(world.xz,CAMERA_POSITION_WORLD.xz));
	VERTEX.y*=fade;
}
void fragment(){
	vec3 blade=mix(low_color,high_color,height*.78+shade*.22);
	float blossom=step(.84,shade)*smoothstep(.62,.92,height);
	ALBEDO=mix(blade,flower_color,blossom*.72);
	ROUGHNESS=.86;
	BACKLIGHT=vec3(.26,.32,.08)*height;
}
