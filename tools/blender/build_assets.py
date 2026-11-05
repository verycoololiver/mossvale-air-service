"""Original Mossvale benchmark assets. Run in Blender; metres, Z up, nose -Y.
Each build creates its own scene and leaves unrelated scenes untouched.
"""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'game' / 'assets'
SOURCE = ROOT / 'art' / 'source'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)

def scene_new(name):
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    return scene

def mat(name, color, metallic=0, rough=.5, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = rough
    if emission:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emission
    return m

def mesh(name, verts, faces, material, smooth=False):
    me=bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces); me.update()
    ob=bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material: me.materials.append(material)
    for p in me.polygons: p.use_smooth=smooth
    return ob

def cube(name, loc, scale, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob=bpy.context.object; ob.name=name; ob.dimensions=scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(material)
    if bevel:
        mod=ob.modifiers.new('Soft manufactured edges', 'BEVEL'); mod.width=bevel; mod.segments=3
        mod=ob.modifiers.new('Weighted surface normals', 'WEIGHTED_NORMAL')
    return ob

def uvball(name, loc, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc)
    ob=bpy.context.object; ob.name=name; ob.scale=scale; ob.data.materials.append(material)
    for p in ob.data.polygons: p.use_smooth=True
    return ob

def rod(name, a,b, radius, material, radius2=None, vertices=12):
    d=Vector(b)-Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius if radius2 is None else radius2, depth=d.length, location=(Vector(a)+Vector(b))/2)
    ob=bpy.context.object; ob.name=name; ob.rotation_euler=d.to_track_quat('Z','Y').to_euler(); ob.data.materials.append(material)
    for p in ob.data.polygons: p.use_smooth=True
    return ob

def line(name, points, radius, material, closed=False):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.bevel_depth=radius; cu.bevel_resolution=2
    s=cu.splines.new('POLY'); s.points.add(len(points)-1)
    for p,v in zip(s.points,points): p.co=(*v,1)
    s.use_cyclic_u=closed
    ob=bpy.data.objects.new(name,cu); bpy.context.scene.collection.objects.link(ob); cu.materials.append(material)
    return ob

def text3d(name, txt, loc, size, material, rot=(math.pi/2,0,0)):
    cu=bpy.data.curves.new(name,'FONT'); cu.body=txt; cu.size=size; cu.align_x='CENTER'; cu.extrude=.001
    ob=bpy.data.objects.new(name,cu); bpy.context.scene.collection.objects.link(ob)
    ob.location=loc; ob.rotation_euler=rot; cu.materials.append(material)
    return ob

def export(name):
    # Convert bevels/curves/fonts explicitly so the GLB matches the editable source.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.context.scene.objects:
        if ob.type in {'MESH','CURVE','FONT'}: ob.select_set(True)
    active=next(o for o in bpy.context.selected_objects)
    bpy.context.view_layer.objects.active=active
    bpy.ops.object.convert(target='MESH')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')), export_format='GLB', use_selection=True, use_active_scene=True, export_apply=True, export_yup=True)
    triangles=sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
    print('ASSET_READY', name, triangles)

def build_plane():
    scene_new('MV-4 Heron — aircraft source')
    ivory=mat('Heron | warm enamel',(.73,.71,.60),.22,.29)
    teal=mat('Heron | deep petrol enamel',(.012,.075,.078),.45,.27)
    gold=mat('Heron | ochre trim',(.9,.39,.065),.28,.34)
    dark=mat('Heron | charcoal',(.018,.023,.025),.3,.42)
    rubber=mat('Heron | tyres',(.022,.028,.026),0,.88)
    alu=mat('Heron | brushed aluminium',(.48,.54,.54),.8,.28)
    glass=mat('Heron | blue smoked glazing',(.028,.1,.15),.58,.14)
    red=mat('Heron | port light',(.9,.025,.015),0,.2,2)
    green=mat('Heron | starboard light',(.05,.8,.23),0,.2,2)
    # Loft: cowl, front windscreen, four-seat cabin, tapering tail.
    rings=[(-2.65,1.47,.28,.3),(-2.42,1.48,.49,.44),(-1.95,1.48,.57,.5),(-1.35,1.48,.6,.51),(-.83,1.65,.64,.79),(.1,1.67,.64,.81),(.92,1.6,.56,.69),(1.38,1.48,.43,.5),(2.35,1.36,.24,.27),(3.2,1.34,.11,.14),(3.48,1.33,.035,.06)]
    n=48; v=[]; f=[]
    for y,z,rx,rz in rings:
        for j in range(n):
            a=2*math.pi*j/n; v.append((rx*math.cos(a),y,z+rz*math.sin(a)))
    for i in range(len(rings)-1):
        for j in range(n): f.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    f.extend([tuple(reversed(range(n))),tuple((len(rings)-1)*n+j for j in range(n))])
    fus=mesh('Sculpted monocoque fuselage',v,f,ivory,True)
    fus.data.materials.append(teal)
    for poly in fus.data.polygons:
        if poly.center.z < 1.35: poly.material_index=1
    # Long coloured stripe follows the cross-section, lifted just off the skin.
    for side in [-1,1]:
        vv=[]
        for y,z,rx,rz in rings[1:-1]:
            for a in [-.08,.085]: vv.append((side*(rx*math.cos(a)+.009),y,z+rz*math.sin(a)))
        mesh('Swept ochre fuselage stripe',vv,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(rings)-3)],gold)
    # Glazing conforms to the cabin cross-section; narrow cream mullions remain.
    def cabin_surface(y, angle, side):
        for i in range(len(rings)-1):
            a,b=rings[i],rings[i+1]
            if a[0]<=y<=b[0]:
                t=(y-a[0])/(b[0]-a[0]); z=a[1]*(1-t)+b[1]*t; rx=a[2]*(1-t)+b[2]*t; rz=a[3]*(1-t)+b[3]*t
                return (side*(rx*math.cos(angle)+.014),y,z+rz*math.sin(angle)+.008)
    for side in [-1,1]:
        for start,end in [(-1.25,-.87),(-.78,.02),(.13,.85)]:
            ys=[start+(end-start)*i/6 for i in range(7)]; aa=[.25,.46,.66, .85]
            vv=[cabin_surface(y,a,side) for y in ys for a in aa]
            ff=[]
            for i in range(6):
                for j in range(3):
                    q=(i*4+j,i*4+j+1,(i+1)*4+j+1,(i+1)*4+j)
                    ff.append(q if side==1 else tuple(reversed(q)))
            ob=mesh('Flush cabin glass',vv,ff,glass,True)
            outline=[cabin_surface(y,.25,side) for y in ys]+[cabin_surface(end,a,side) for a in aa]+[cabin_surface(y,.85,side) for y in reversed(ys)]+[cabin_surface(start,a,side) for a in reversed(aa)]
            line('Window rubber seal',outline,.018,dark,True)
        line('Door seam',[cabin_surface(-.8,.18,side),(side*.608,-.8,1.25),(side*.61,.09,1.24),cabin_surface(.09,.19,side)],.007,dark)
        rod('Door handle',(side*.653,-.03,1.68),(side*.653,-.22,1.68),.022,alu)
    # Front windscreen follows the sloped fuselage shoulder across its crown.
    angles=[.88+(math.pi-1.76)*j/12 for j in range(13)]
    ys=[-1.31+i*.069 for i in range(7)]
    vv=[cabin_surface(y,a,1) for y in ys for a in angles]
    ff=[(i*13+j,i*13+j+1,(i+1)*13+j+1,(i+1)*13+j) for i in range(6) for j in range(12)]
    mesh('Curved front windscreen',vv,ff,glass,True)
    outline=[cabin_surface(ys[0],a,1) for a in angles]+[cabin_surface(y,angles[-1],1) for y in ys]+[cabin_surface(ys[-1],a,1) for a in reversed(angles)]+[cabin_surface(y,angles[0],1) for y in reversed(ys)]
    line('Windscreen seal',outline,.017,dark,True)
    line('Windscreen central mullion',[cabin_surface(y,math.pi/2,1) for y in ys],.013,ivory)
    # Airfoil-shaped main wing; straight root, swept and rounded tip.
    def wing(name, span, chord, y,z, material):
        vv=[]; ff=[]; sections=[(-span,.18),(-span+.18,.83),(-span+.55,.94),(0,1),(span-.55,.94),(span-.18,.83),(span,.18)]
        profile=[]
        for j in range(19):
            t=(1-math.cos(math.pi*j/18))/2
            h=.12*(.2969*math.sqrt(t)-.126*t-.3516*t*t+.2843*t**3-.1015*t**4)*5
            profile.append((t,h))
        profile+= [(t,-h*.55) for t,h in reversed(profile[1:-1])]
        N=len(profile)
        for x,fac in sections:
            for t,h in profile: vv.append((x,y+(t-.42)*chord*fac+(1-fac)*.22,z+h*chord*fac+abs(x)*.017))
        for i in range(len(sections)-1):
            for j in range(N): ff.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
        ff.extend([tuple(reversed(range(N))),tuple((len(sections)-1)*N+j for j in range(N))])
        ob=mesh(name,vv,ff,material,True)
        return ob
    wing('High wing | cambered airfoil',5.05,1.6,-.23,2.45,ivory)
    for side in [-1,1]:
        rod('Lift strut',(side*.48,.08,1.15),(side*3.35,-.52,2.48),.043,alu)
        rod('Rear lift strut',(side*.5,.28,1.15),(side*3.35,.38,2.49),.032,alu)
        line('Aileron hinge',[(side*2.65,.59,2.52),(side*4.53,.59,2.55)],.009,dark)
        # Coloured wingtip band, below the nav light.
        uvball('Wingtip accent',(side*4.94,-.05,2.55),(.11,.37,.068),teal)
        uvball('Navigation lens',(side*5.01,-.24,2.57),(.06,.12,.045),red if side<0 else green)
    wing('Horizontal tail',1.61,.88,2.75,1.49,teal)
    fin_outline=[(2.15,1.43),(2.58,2.55),(2.91,2.64),(3.42,1.41)]
    vv=[(s*.066,y,z) for s in [-1,1] for y,z in fin_outline]
    mesh('Swept vertical stabilizer',vv,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],teal)
    line('Rudder separation',[(.069,3.05,1.5),(.069,2.9,2.55)],.009,gold)
    for side in [-1,1]:
        text3d('Tail registration','MV', (side*.071,2.81,1.83),.23,ivory,(math.pi/2,0,side*math.pi/2))
    # Fixed bush landing gear, tyres and metal hubs.
    for side in [-1,1]:
        rod('Main gear leg',(side*.35,-.54,1.1),(side*1.13,-.86,.42),.059,alu)
        rod('Trailing gear brace',(side*.43,.25,1.13),(side*1.13,-.86,.42),.036,dark)
        bpy.ops.mesh.primitive_torus_add(major_radius=.29,minor_radius=.12,major_segments=40,minor_segments=12,location=(side*1.15,-.86,.41),rotation=(0,math.pi/2,0))
        ob=bpy.context.object; ob.name='Tundra tyre'; ob.data.materials.append(rubber)
        for p in ob.data.polygons:p.use_smooth=True
        rod('Wheel hub',(side*1.01,-.86,.41),(side*1.3,-.86,.41),.19,alu,vertices=32)
        rod('Hub cap',(side*1.295,-.86,.41),(side*1.316,-.86,.41),.1,teal,vertices=24)
    rod('Tailwheel spring',(0,2.86,1.17),(0,3.16,.24),.033,dark)
    rod('Tailwheel',(-.075,3.16,.2),(.075,3.16,.2),.19,rubber,vertices=24)
    # Spinner and separate propeller blades.
    uvball('Spinner',(0,-2.75,1.47),(.27,.42,.27),alu)
    for sign in [-1,1]:
        vv=[(-.08,-2.83,1.47+sign*.15),(.13,-2.83,1.47+sign*.29),(.2,-2.82,1.47+sign*.91),(.1,-2.8,1.47+sign*1.03),(-.07,-2.82,1.47+sign*.95),(-.09,-2.85,1.47+sign*.3)]
        ob=mesh('Propeller blade',vv,[tuple(range(6))],dark)
        sol=ob.modifiers.new('Blade thickness','SOLIDIFY');sol.thickness=.025
        cube('Propeller safety tip',(.065,-2.826,1.47+sign*.92),(.14,.028,.09),gold,.012)
    for side in [-1,1]:
        uvball('Cooling intake',(side*.3,-2.431,1.53),(.12,.035,.09),dark)
        rod('Exhaust',(side*.43,-1.78,1.12),(side*.5,-1.64,.92),.044,dark)
    line('Cowl panel join',[(.58*math.cos(a),-1.95,1.48+.51*math.sin(a)) for a in [i*2*math.pi/48 for i in range(48)]],.006,dark,True)
    # Rivets only around the visible cowling and wing roots, not everywhere.
    for side in [-1,1]:
        for j in range(9): uvball('Flush fastener',(side*.565,-1.92+j*.065,1.61),(.009,.009,.009),alu)
    rod('Radio antenna',(0,.3,2.48),(0,.35,2.98),.012,dark)
    export('heron_mv4')

def build_hangar():
    scene_new('Mossvale hangar — modular source')
    metal=mat('Hangar | charcoal zinc',(.075,.12,.125),.65,.4)
    frame=mat('Hangar | painted frame',(.12,.2,.19),.25,.5)
    wood=[mat('Hangar | cedar '+str(i),(.24+i*.025,.12+i*.013,.058+i*.009),0,.8) for i in range(5)]
    concrete=mat('Hangar | foundation',(.32,.34,.31),0,.92)
    cream=mat('Hangar | lettering',(.85,.78,.6),.1,.55)
    window=mat('Hangar | glazing',(.055,.12,.15),.45,.2)
    glow=mat('Hangar | warm lamp', (1,.61,.22),0,.3,3)
    cube('Concrete sill',(0,0,.08),(14.4,11.6,.16),concrete,.035)
    cube('Back wall',(0,5.5,2.8),(14,.18,5.6),frame,.02)
    for s in [-1,1]: cube('Side wall',(s*7,0,2.8),(.15,11,5.6),frame,.02)
    # Standing seam roof, intentionally modeled to catch grazing sunlight.
    for s in [-1,1]:
        roof=mesh('Zinc roof',[(0,-5.85,7.15),(0,5.85,7.15),(s*7.4,5.85,5.55),(s*7.4,-5.85,5.55)],[(0,1,2,3)],metal)
        roof.modifiers.new('Roof thickness','SOLIDIFY').thickness=.1
        for i in range(25):
            y=-5.75+i*.48; rod('Standing roof seam',(0,y,7.18),(s*7.4,y,5.58),.027,metal,vertices=6)
    for s in [-1,1]:
        for i in range(38): cube('Cedar side plank',(s*7.105,-5.35+i*.286,2.8),(.075,.255,5.45),wood[i%5],.008)
        for y in [-5.5,0,5.5]: cube('Structural post',(s*6.8,y,2.77),(.22,.22,5.5),frame,.02)
        rod('Gable beam',(0,-5.69,7.02),(s*7,-5.69,5.52),.095,frame,vertices=4)
    # Front header and gable with vertical cedar slats.
    for i in range(48):
        x=-6.86+i*.292; top=7.05-abs(x)/7*1.5
        cube('Gable cedar',(x,-5.56,(top+4.8)/2),(.265,.16,top-4.8),wood[i%5],.01)
    cube('Door track',(0,-5.79,4.77),(14.4,.18,.16),metal,.02)
    # Half-open sliding doors leave a deep, useful interior.
    for x0 in [-5.55,5.55]:
        cube('Sliding door',(x0,-5.68,2.37),(3,.2,4.7),frame,.02)
        for i in range(13): cube('Door corrugation',(x0-1.4+i*.23,-5.815,2.37),(.04,.055,4.6),metal,.01)
        cube('Door window',(x0,-5.825,3.25),(1.9,.02,.6),window,.03)
        cube('Door handle',(x0-.8,-5.9,1.4),(.045,.055,.33),cream,.02)
    cube('Airfield nameboard',(0,-5.75,5.7),(7.9,.15,.85),metal,.035)
    text3d('Nameboard','M O S S V A L E',(0,-5.84,5.48),.48,cream)
    text3d('Small sign','AIR SERVICE  /  01',(0,-5.86,4.98),.18,cream)
    for x in [-5,5]:
        rod('Lamp arm',(x,-5.8,4.5),(x,-6.25,4.5),.035,metal)
        cube('Lamp housing',(x,-6.25,4.43),(.4,.3,.12),metal,.05)
        cube('Lamp diffuser',(x,-6.25,4.362),(.31,.23,.012),glow,.01)
    # Interior roof beams, cabinet and workbench give the open door depth.
    for y in [-4,0,4]:
        rod('Roof tie',(-6.85,y,5.35),(6.85,y,5.35),.075,frame,vertices=4)
        for s in [-1,1]: rod('Roof truss',(0,y,6.95),(s*6.8,y,5.35),.075,frame,vertices=4)
    cube('Workbench',(-5,2,1.05),(2.7,1,.12),wood[2],.03)
    for x in [-6.1,-3.9]:
        for y in [1.65,2.35]: cube('Bench leg',(x,y,.52),(.1,.1,1.04),metal)
    cube('Tool cabinet',(-5,4,1),(2,.8,2),metal,.06)
    export('mossvale_hangar')

def build_nature():
    scene_new('Silver birch — source')
    rng=random.Random(22)
    bark=mat('Birch | pale bark',(.58,.55,.43),0,.95)
    barkdark=mat('Birch | bark marks',(.1,.12,.09),0,1)
    greens=[mat('Birch | foliage '+str(i),(.022+i*.007,.063+i*.013,.008+i*.005),0,.93) for i in range(5)]
    rod('Birch trunk',(0,0,0),(.18,0,6.2),.18,bark,.06,10)
    for i in range(14):
        z=.4+i*.34; rod('Bark band',(.025*z,0,z),(.025*z+.002,0,z+.045),.181-z*.015,barkdark,vertices=10)
    # Branches and many irregular small leaf clusters, not giant spheres.
    for i in range(14):
        a=i*2.399; z=2.5+i*.24; reach=1.4+math.sin(i*.65)*.5
        end=Vector((math.cos(a)*reach,math.sin(a)*reach,z+1.15))
        rod('Branch',(.025*z,0,z),end,.057,bark,.012,7)
        for j in range(6):
            c=end+Vector((rng.uniform(-.65,.65),rng.uniform(-.65,.65),rng.uniform(-.4,.55)))
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=c)
            ob=bpy.context.object; ob.name='Birch leaf cluster'; ob.scale=(rng.uniform(.45,.78),rng.uniform(.5,.83),rng.uniform(.35,.6)); ob.data.materials.append(greens[(i+j)%5])
            for v in ob.data.vertices: v.co*=rng.uniform(.8,1.2)
            for p in ob.data.polygons:p.use_smooth=True
    export('birch')
    scene_new('Meadow rock — source')
    rock=mat('Rock | weathered granite',(.28,.31,.26),0,.95)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(0,0,.38))
    ob=bpy.context.object;ob.name='Weathered boulder';ob.scale=(1.3,.85,.7);ob.data.materials.append(rock)
    for v in ob.data.vertices:v.co*=rng.uniform(.8,1.15)
    bevel=ob.modifiers.new('Worn edges','BEVEL');bevel.width=.06;bevel.segments=2
    ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    export('boulder')

def build_service():
    scene_new('Airfield fuel point — source')
    teal=mat('Fuel | petrol paint',(.035,.16,.15),.35,.4)
    white=mat('Fuel | ivory',(.78,.73,.58),.15,.45)
    black=mat('Fuel | rubber',(.018,.022,.022),0,.82)
    steel=mat('Fuel | steel',(.4,.45,.43),.7,.3)
    cube('Pump plinth',(0,0,.1),(1.4,1.1,.2),steel,.04)
    cube('Fuel dispenser',(0,0,1.15),(.85,.64,2.1),teal,.1)
    cube('Pump fascia',(0,-.331,1.66),(.65,.035,.48),white,.025)
    cube('Counter display',(0,-.353,1.7),(.48,.01,.19),black,.01)
    text3d('Fuel readout','AVGAS',(0,-.37,1.23),.16,white)
    text3d('Pump litres','042.8',(0,-.37,1.66),.12,white)
    pts=[(.42,0,1.8),(.7,-.04,1.6),(.8,-.12,.6),(.65,-.2,.25),(.38,-.3,.2),(.22,-.45,.36),(.25,-.42,1.05)]
    line('Coiled fuel hose',pts,.033,black)
    rod('Nozzle',(.25,-.42,1.05),(.25,-.42,1.4),.043,steel)
    export('fuel_pump')

if __name__=='__main__':
    build_plane(); build_hangar(); build_nature(); build_service()
