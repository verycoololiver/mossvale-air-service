shader_type spatial;
uniform bool pavement = false;
uniform float wetness : hint_range(0,1) = 0.0;
varying vec3 world;
varying vec3 world_normal;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
	world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal=normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
}
void fragment(){
	float n=noise(world.xz*.14)*.55+noise(world.xz*.75)*.28+noise(world.xz*5.5)*.17;
	if(pavement){
		// Fade subpixel aggregate instead of letting it shimmer during camera movement.
		float detail=1.0-smoothstep(.2,1.1,length(fwidth(world.xz))*65.0);
		float grain=mix(.5,noise(world.xz*65.0),detail);
		vec3 dry=mix(vec3(.135,.152,.156),vec3(.225,.240,.235),grain*.30+n*.42);
		float puddle=smoothstep(.41,.74,noise(world.xz*.24))*wetness;
		ALBEDO=pow(dry,vec3(2.2))*mix(1.0,.48,wetness);
		ROUGHNESS=mix(.88,.28,puddle*.45+wetness*.52);
		METALLIC=.10;
		NORMAL_MAP=normalize(vec3((grain-.5)*.09,(noise(world.zx*65.0)-.5)*.09*detail,1.0))*.5+.5;
	}else{
		// Lush valley meadow with clover/wildflower patches, rocky cliff slopes, and highland ridges.
		vec3 lush_low=mix(vec3(.13,.255,.095),vec3(.33,.435,.155),n);
		float meadow_patch=smoothstep(.46,.76,noise(world.xz*.048));
		vec3 meadow=mix(lush_low,vec3(.38,.35,.165),meadow_patch*.30);
		float bloom=smoothstep(.68,.86,noise(world.xz*.38+vec2(17.3,9.1)))*(1.0-smoothstep(8.0,28.0,world.y));
		meadow=mix(meadow,vec3(.48,.43,.20),bloom*.22);

		// Highland heather & pine-needle tones at higher elevations
		float high_blend=smoothstep(18.0,58.0,world.y);
		vec3 highland=mix(vec3(.18,.26,.13),vec3(.31,.33,.21),n);
		vec3 base_ground=mix(meadow,highland,high_blend*.65);

		// Steep mountain slopes expose layered warm granite rock
		float slope=1.0-clamp(world_normal.y,0.0,1.0);
		float strata=noise(vec2(world.x*.08+world.z*.08,world.y*.55));
		vec3 rock=mix(vec3(.26,.25,.23),vec3(.41,.38,.33),strata*.65+n*.35);
		float rock_mask=smoothstep(.14,.34,slope+high_blend*.09+(n-.5)*.08);
		vec3 final_col=mix(base_ground,rock,rock_mask);

		// Subtle sunlit alpine crest tint on the highest peaks
		float peak_mask=smoothstep(54.0,78.0,world.y+n*8.0)*smoothstep(.15,.55,world_normal.y);
		final_col=mix(final_col,vec3(.52,.51,.47),peak_mask*.45);

		ALBEDO=pow(final_col,vec3(2.2))*(1.0-wetness*.22);
		ROUGHNESS=mix(.95,.78,rock_mask)*(1.0-wetness*.18);
	}
}
