shader_type spatial;
uniform vec4 base_color : source_color = vec4(.5,.4,.25,1.0);
uniform float wood = 0.0;
uniform float base_roughness = .8;
uniform float metalness = 0.0;
varying vec3 local;
float hash(vec3 p){p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
void vertex(){local=VERTEX;}
void fragment(){
 float fleck=hash(floor(local*90.0));
 float grain=sin(local.x*155.0+local.z*137.0+sin(local.y*.9)*2.0)*.5+.5;
 float variation=mix(fleck,grain,wood);
 ALBEDO=base_color.rgb*(.88+variation*.21);
 ROUGHNESS=clamp(base_roughness+(variation-.5)*.12,.05,1.0);
 METALLIC=metalness;
}
