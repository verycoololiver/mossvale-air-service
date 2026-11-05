"""Run after build_assets.py helper definitions in Blender."""

def build_airfield_props():
    scene_new('Airfield workshop props')
    wood=mat('Props | weathered oak',(.27,.15,.068),0,.86)
    steel=mat('Props | dark metal',(.028,.07,.065),.4,.48)
    enamel=mat('Props | fuel drum enamel',(.1,.21,.2),.45,.4)
    cream=mat('Props | warm lettering',(.85,.76,.54),0,.6)
    # Waiting bench: five seat slats, three back slats, brackets and legs.
    for i in range(5):cube('Bench seat slat',(-4.4,-7+i*.11,.48),(2,.09,.06),wood,.015)
    for i in range(3):cube('Bench back slat',(-4.4,-6.47,.72+i*.15),(2,.06,.12),wood,.013)
    for x in [-5.12,-3.68]:
        for y in [-6.9,-6.51]:cube('Bench steel leg',(x,y,.245),(.07,.07,.45),steel,.015)
        cube('Bench back support',(x,-6.43,.71),(.06,.06,.77),steel,.012)
    # A framed flight noticeboard beside the hangar door.
    for x in [4.1,5.3]:cube('Noticeboard upright',(x,-6.9,.94),(.11,.11,1.88),wood,.02)
    cube('Noticeboard backing',(4.7,-6.94,1.46),(1.32,.12,1),wood,.025)
    cube('Noticeboard face',(4.7,-7.008,1.46),(1.18,.012,.85),steel,.015)
    text3d('Welcome','WELCOME TO',(4.7,-7.027,1.65),.105,cream)
    text3d('Field name','MOSSVALE',(4.7,-7.027,1.47),.15,cream)
    text3d('Field elevation','AIRSTRIP  /  420 M',(4.7,-7.027,1.27),.072,cream)
    # Two fuel drums with rolled rims and labels.
    for x,y in [(6.2,-3.8),(6.25,-2.9)]:
        rod('Service drum',(x,y,.04),(x,y,.87),.3,enamel,vertices=24)
        for z in [.07,.31,.63,.85]:
            bpy.ops.mesh.primitive_torus_add(major_radius=.301,minor_radius=.014,major_segments=24,minor_segments=8,location=(x,y,z))
            bpy.context.object.name='Rolled drum rim';bpy.context.object.data.materials.append(steel)
        cube('Drum label',(x,y-.302,.5),(.25,.01,.21),cream,.012)
        text3d('Drum marking','100',(x,y-.315,.47),.085,steel)
    # Cargo crate: separate weathered planks and steel corner strips.
    for i in range(6):cube('Cargo box plank',(5.8,-1.6,.09+i*.12),(1.05,.86,.108),wood,.008)
    for x in [5.33,6.27]:cube('Crate band',(x,-1.6,.41),(.045,.89,.82),steel,.008)
    export('airfield_props')
