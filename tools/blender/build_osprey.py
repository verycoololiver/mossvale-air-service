"""Original six-seat Osprey commuter: longer cabin, three-blade prop, tricycle gear.
Run with Blender --background --python this_file. Uses our existing mesh helpers.
"""
import sys
import math
from pathlib import Path
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_assets import scene_new, mat, mesh, rod, uvball, line, text3d, export

scene_new('MV-6 Osprey — six seat commuter')
ivory = mat('Osprey | pearl enamel', (.72,.74,.68),.25,.3)
blue = mat('Osprey | deep blue enamel', (.022,.070,.12),.4,.29)
copper = mat('Osprey | burnt orange stripe', (.72,.25,.085),.3,.34)
dark = mat('Osprey | rubber and seals', (.017,.025,.03),0,.83)
glass = mat('Osprey | blue glazing', (.025,.09,.14),.6,.16)
metal = mat('Osprey | brushed aluminium', (.44,.49,.52),.75,.33)
red = mat('Osprey | port light',(.9,.025,.015),0,.2,2)
green = mat('Osprey | starboard light',(.05,.8,.23),0,.2,2)
rings = [(-3.35,1.7,.24,.26),(-3.10,1.70,.48,.43),(-2.7,1.70,.56,.50),
    (-2.1,1.76,.66,.60),(-1.65,1.88,.73,.79),(-.95,1.89,.75,.80),
    (.05,1.89,.75,.80),(1.15,1.86,.72,.76),(1.68,1.78,.61,.65),
    (2.4,1.62,.38,.43),(3.4,1.51,.17,.23),(4.0,1.50,.07,.13),(4.2,1.5,.025,.04)]
count = 48
vertices = [(rx*math.cos(j*math.tau/count), y, z+rz*math.sin(j*math.tau/count))
    for y,z,rx,rz in rings for j in range(count)]
faces = []
for i in range(len(rings)-1):
    for j in range(count):
        faces.append((i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j))
faces += [tuple(reversed(range(count))),tuple((len(rings)-1)*count+j for j in range(count))]
body = mesh('Long six-seat cabin',vertices,faces,ivory,True)
body.data.materials.append(blue)
for face in body.data.polygons:
    if face.center.z<1.45:face.material_index=1

def surface(y,a,side):
    for first,second in zip(rings,rings[1:]):
        if first[0]<=y<=second[0]:
            t=(y-first[0])/(second[0]-first[0])
            z,rx,rz=[first[k]*(1-t)+second[k]*t for k in [1,2,3]]
            return (side*(rx*math.cos(a)+.012),y,z+rz*math.sin(a)+.009)

for side in [-1,1]:
    stripe = [(side*(rx*math.cos(a)+.013),y,z+rz*math.sin(a))
        for y,z,rx,rz in rings[1:-1] for a in [-.1,.055]]
    mesh('Fine copper cheatline',stripe,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(rings)-3)],copper)
    for start,end in [(-1.98,-1.2),(-1.07,-.35),(-.20,.51),(.66,1.28)]:
        ys=[start+(end-start)*i/5 for i in range(6)]
        aa=[.20,.40,.60,.80]
        vv=[surface(y,a,side) for y in ys for a in aa]
        ff=[]
        for i in range(5):
            for j in range(3):
                q=(i*4+j,i*4+j+1,(i+1)*4+j+1,(i+1)*4+j)
                ff.append(q if side==1 else tuple(reversed(q)))
        mesh('Flush commuter window',vv,ff,glass,True)
        outline=[surface(y,.20,side) for y in ys]+[surface(end,a,side) for a in aa]+[surface(y,.80,side) for y in reversed(ys)]+[surface(start,a,side) for a in reversed(aa)]
        line('Window seal',outline,.014,dark,True)
    line('Passenger door seam',[surface(.58,.17,side),(side*.75,.58,1.25),(side*.72,1.38,1.25),surface(1.38,.16,side)],.009,dark)
    rod('Cabin door handle',(side*.76,1.0,1.78),(side*.76,1.2,1.78),.022,metal)
    rod('Boarding step',(side*.86,.7,.89),(side*.86,1.3,.89),.045,metal)
ys=[-2.12+i*.082 for i in range(7)]
angles=[.83+(math.pi-1.66)*j/16 for j in range(17)]
vv=[surface(y,a,1) for y in ys for a in angles]
mesh('Panoramic windscreen',vv,[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j) for i in range(6) for j in range(16)],glass,True)
line('Windscreen central frame',[surface(y,math.pi/2,1) for y in ys],.024,ivory)

def wing(name,span,chord,y,z,material):
    profile=[]
    for j in range(21):
        t=(1-math.cos(math.pi*j/20))*.5
        h=.12*(.2969*math.sqrt(t)-.126*t-.3516*t*t+.2843*t**3-.1015*t**4)*5
        profile.append((t,h))
    profile += [(t,-h*.55) for t,h in reversed(profile[1:-1])]
    sections=[(-span,.2),(-span+.20,.8),(-span+.65,.94),(0,1),(span-.65,.94),(span-.20,.8),(span,.2)]
    vv=[(x,y+(t-.42)*chord*f+(1-f)*.24,z+h*chord*f+abs(x)*.017) for x,f in sections for t,h in profile]
    n=len(profile)
    ff=[(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j) for i in range(len(sections)-1) for j in range(n)]
    ff += [tuple(reversed(range(n))),tuple((len(sections)-1)*n+j for j in range(n))]
    return mesh(name,vv,ff,material,True)

wing('Long commuter high wing',5.9,1.82,-.35,2.69,ivory)
wing('Horizontal stabilizer',1.9,1.02,3.32,1.75,blue)
fin=[(2.64,1.53),(3.12,2.92),(3.50,3.04),(4.15,1.51)]
vv=[(side*.075,y,z) for side in [-1,1] for y,z in fin]
mesh('Tall swept tail',vv,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],blue)
for side in [-1,1]:
    rod('Wing strut',(side*.6,.1,1.22),(side*3.7,-.23,2.72),.045,metal)
    line('Flap and aileron hinge',[(side*.92,.47,2.74),(side*5.23,.47,2.78)],.009,dark)
    uvball('Copper wing tip',(side*5.77,-.06,2.79),(.12,.42,.062),copper)
    uvball('Navigation light',(side*5.85,-.28,2.82),(.055,.1,.04),red if side<0 else green)
    text3d('Tail identifier','MV6',(side*.08,3.46,2.13),.24,ivory,(math.pi/2,0,side*math.pi/2))
    rod('Main landing leg',(side*.47,.18,1.15),(side*1.23,.32,.38),.065,metal)
    bpy.ops.mesh.primitive_torus_add(major_radius=.26,minor_radius=.115,major_segments=32,minor_segments=12,location=(side*1.24,.32,.375),rotation=(0,math.pi/2,0))
    tire=bpy.context.object;tire.name='Commuter main tyre';tire.data.materials.append(dark)
    for face in tire.data.polygons:face.use_smooth=True
    rod('Main wheel hub',(side*1.1,.32,.375),(side*1.38,.32,.375),.15,metal,vertices=24)
rod('Nose oleo',(0,-2.65,1.27),(0,-2.65,.29),.06,metal)
rod('Nose wheel',(-.075,-2.65,.27),(.075,-2.65,.27),.27,dark,vertices=32)
rod('Nose wheel hub',(-.08,-2.65,.27),(.08,-2.65,.27),.115,metal,vertices=24)
uvball('Polished spinner',(0,-3.45,1.70),(.255,.40,.255),metal)
for i in range(3):
    angle=i*math.tau/3
    def blade_point(x,z):
        return (x*math.cos(angle)+z*math.sin(angle),-3.62,1.7-x*math.sin(angle)+z*math.cos(angle))
    vv=[blade_point(x,z) for x,z in [(-.065,.18),(.10,.23),(.17,.87),(.075,1.15),(-.065,1.1),(-.095,.35)]]
    blade=mesh('Propeller blade',vv,[tuple(range(6))],dark)
    blade.modifiers.new('Blade thickness','SOLIDIFY').thickness=.026
    mesh('Propeller safety tip',[blade_point(x,z) for x,z in [(-.066,1.02),(.11,1.02),(.075,1.14),(-.06,1.1)]],[(0,1,2,3)],copper)
for side in [-1,1]:
    uvball('Engine intake',(side*.30,-3.1,1.7),(.12,.032,.08),dark)
    rod('Exhaust',(side*.47,-2.65,1.35),(side*.51,-2.39,1.13),.048,dark)
rod('Radio antenna',(0,.54,2.7),(0,.60,3.18),.012,dark)
export('osprey_mv6')
