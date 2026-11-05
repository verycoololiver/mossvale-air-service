"""Original first-person outdoor clothing and hands. Metres, Z up, facing +Y.

Separate from the rejected third-person pilot. Run with Blender --background
--python this_file. Creates its own scene; exports one skinned mesh and rig.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
scene = bpy.data.scenes.new('Mossvale first-person body')
bpy.context.window.scene = scene


def material(name, color, roughness=.85):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    return mat


canvas = material('Weathered olive canvas', (.125, .155, .102))
rib = material('Dark olive cuffs and hem', (.055, .072, .045))
trousers = material('Charcoal work trousers', (.09, .105, .108))
leather = material('Brown boot leather', (.13, .076, .040), .65)
rubber = material('Dark boot rubber', (.023, .027, .025))
laces = material('Muted boot laces', (.24, .21, .15))
skin = material('Hands', (.48, .265, .155), .72)
hair_mat = material('Warm dark hair', (.055, .038, .026), .88)
cap_mat = material('Field cap wool', (.165, .142, .098), .86)


def bind(obj, weights):
    for vertex in obj.data.vertices:
        if isinstance(weights, str):
            influences = {weights: 1.0}
        else:
            low, high, z0, z1 = weights
            t = min(1, max(0, (vertex.co.z - z0) / (z1 - z0)))
            t = t*t*(3-2*t)
            influences = {low: 1-t, high: t}
        for name, weight in influences.items():
            if weight > 0:
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([vertex.index], weight, 'REPLACE')
    return obj


def mesh(name, vertices, faces, mat, weights):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    data.materials.append(mat)
    for face in data.polygons:
        face.use_smooth = True
    return bind(obj, weights)


def loft(name, rings, mat, weights, count=24, cloth=False):
    vertices, faces = [], []
    for i, (x, y, z, rx, ry) in enumerate(rings):
        for j in range(count):
            angle = j*math.tau/count
            # Restrained irregular folds, avoiding a perfectly tubular silhouette.
            fold = 1 + (.018*math.sin(angle*5+i*1.7) if cloth else 0)
            vertices.append((x+rx*math.cos(angle)*fold, y+ry*math.sin(angle)*fold, z))
    faces.append(tuple(reversed(range(count))))
    for i in range(len(rings)-1):
        for j in range(count):
            faces.append((i*count+j, i*count+(j+1)%count,
                          (i+1)*count+(j+1)%count, (i+1)*count+j))
    faces.append(tuple((len(rings)-1)*count+j for j in range(count)))
    return mesh(name, vertices, faces, mat, weights)


def ellipsoid(name, center, scale, mat, bone, segments=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=10, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    return bind(obj, bone)


def piping(name, points, radius, mat, bone):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for point, value in zip(spline.points, points):
        point.co = (*value, 1)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    curve.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return bind(bpy.context.object, bone)


# Clean, fitted silhouette. No epaulettes, badges, contrasting shoulder blocks,
# floating collar, head or face to intersect the first-person camera.
loft('Canvas jacket', [
    (0,0,.91,.164,.110), (0,0,.99,.176,.118), (0,0,1.09,.174,.119),
    (0,0,1.20,.182,.122), (0,0,1.32,.192,.116), (0,0,1.39,.186,.102),
    (0,0,1.44,.152,.082)], canvas, ('hips','chest',1.03,1.24), cloth=True)
loft('Knitted jacket hem', [(0,0,.895,.162,.108),(0,0,.945,.168,.113)], rib, 'hips')
piping('Jacket front seam', [(0,.121,.96),(0,.123,1.12),(0,.124,1.24),(0,.108,1.37)], .003, rib, 'chest')
# Natural collar, neck, head, hair and outdoor field cap for third-person camera.
loft('Jacket collar', [
    (0,-.004,1.405,.138,.084), (0,-.006,1.455,.098,.075), (0,-.005,1.482,.078,.068)],
    rib, 'chest', cloth=True)
loft('Neck', [
    (0,.004,1.445,.058,.056), (0,.008,1.505,.052,.052), (0,.010,1.555,.054,.054)],
    skin, 'chest')
loft('Head', [
    (0,.016,1.535,.048,.058), (0,.018,1.568,.072,.084), (0,.014,1.618,.082,.096),
    (0,.008,1.668,.084,.100), (0,.004,1.715,.076,.092), (0,.002,1.746,.048,.060)],
    skin, 'chest')
for side, suffix in [(-1, 'L'), (1, 'R')]:
    ellipsoid('Ear '+suffix, (side*.083, .004, 1.625), (.013, .020, .027), skin, 'chest')
    ellipsoid('Eye '+suffix, (side*.031, .096, 1.636), (.009, .007, .008), hair_mat, 'chest')
    piping('Brow '+suffix, [(side*.018, .099, 1.650), (side*.044, .096, 1.648)], .0028, hair_mat, 'chest')
ellipsoid('Nose', (0, .105, 1.622), (.012, .018, .022), skin, 'chest')
loft('Hair back', [
    (0,-.022,1.562,.074,.076), (0,-.018,1.608,.086,.092),
    (0,-.010,1.658,.089,.098), (0,-.002,1.702,.082,.092)],
    hair_mat, 'chest', cloth=True)
loft('Field cap crown', [
    (0,.004,1.662,.088,.104), (0,.006,1.695,.091,.107),
    (0,.004,1.735,.084,.098), (0,.002,1.760,.056,.068)],
    cap_mat, 'chest', cloth=True)
loft('Field cap visor', [
    (0,.075,1.668,.076,.035), (0,.112,1.662,.068,.028), (0,.142,1.654,.052,.018)],
    rib, 'chest')
loft('Trouser waist', [
    (0,0,.78,.148,.098),(0,0,.85,.156,.104),(0,0,.92,.158,.106),(0,0,.98,.156,.104)],
    trousers, 'hips')

for side, suffix in [(-1, 'L'), (1, 'R')]:
    thigh, shin, foot = 'thigh_'+suffix, 'shin_'+suffix, 'foot_'+suffix
    upper, forearm, hand = 'upper_'+suffix, 'forearm_'+suffix, 'hand_'+suffix
    x = side*.096
    loft('Trouser leg '+suffix, [
        (x,0,.175,.062,.067),(x,.003,.23,.070,.074),(x,0,.31,.067,.075),
        (x,.008,.43,.074,.082),(x,.018,.50,.080,.083),(x,.011,.56,.083,.087),
        (x,0,.68,.089,.091),(x,0,.80,.098,.098),(x*.88,0,.94,.106,.102)],
        trousers, (shin,thigh,.43,.60), cloth=True)
    # Rounded sole and leather upper. Toe +Y; narrow heel, broader toe box.
    def boot_ring(z, extent, width):
        verts = []
        for j in range(28):
            angle = math.tau*j/28
            y = .068 + math.sin(angle)*extent
            taper = 1-.13*max(0,-math.sin(angle))
            verts.append((x+math.cos(angle)*width*taper, y, z))
        return verts
    for label, rings, mat in [
        ('Sole',[(.011,.143,.067),(.020,.15,.070),(.046,.15,.070),(.053,.140,.065)],rubber),
        ('Leather upper',[(.047,.139,.066),(.083,.141,.065),(.113,.126,.060),(.135,.095,.055)],leather)]:
        vertices = sum([boot_ring(*ring) for ring in rings], [])
        faces = [tuple(reversed(range(28)))]
        for i in range(len(rings)-1):
            for j in range(28):
                faces.append((i*28+j,i*28+(j+1)%28,(i+1)*28+(j+1)%28,(i+1)*28+j))
        faces.append(tuple((len(rings)-1)*28+j for j in range(28)))
        mesh(label+' '+suffix, vertices, faces, mat, foot)
    loft('Boot ankle '+suffix,[(x,0,.09,.061,.060),(x,-.006,.17,.060,.061),(x,-.007,.235,.057,.058)],leather,foot)
    for i in range(4):
        y = .044+i*.028
        z = .148-i*.008
        piping('Crossed lace '+suffix,[(x-.035,y-.009,z),(x+.035,y+.009,z)],.0023,laces,foot)
        piping('Crossed lace '+suffix,[(x+.035,y-.009,z+.001),(x-.035,y+.009,z+.001)],.0023,laces,foot)
    piping('Toe stitching '+suffix,[(x-.054,.123,.112),(x-.031,.176,.123),(x,.187,.124),(x+.031,.176,.123),(x+.054,.123,.112)],.0016,laces,foot)
    # Slightly bent sleeves terminate in a narrow cuff and an actual hand.
    loft('Canvas sleeve '+suffix,[
        (side*.236,.042,.948,.040,.043),(side*.238,.036,1.01,.048,.050),
        (side*.235,.016,1.10,.054,.054),(side*.226,.004,1.18,.058,.058),
        (side*.208,0,1.29,.062,.062),(side*.178,0,1.385,.060,.064)],
        canvas,(forearm,upper,1.08,1.23),cloth=True)
    loft('Wrist cuff '+suffix,[(side*.236,.042,.925,.040,.042),(side*.236,.042,.969,.043,.044)],rib,forearm)
    hx = side*.237
    loft('Palm '+suffix,[(hx,.05,.842,.030,.021),(hx,.045,.878,.035,.024),
                        (hx,.044,.917,.030,.023),(hx,.045,.936,.023,.022)],skin,hand,20)
    # Four individually tapered fingers with a relaxed curl, and an opposed thumb.
    for j, length in enumerate([.064,.075,.069,.052]):
        fx = hx + side*(-.023+j*.0155)
        loft('Finger %d %s'%(j,suffix),[
            (fx,.062,.842-length,.0055,.0065),
            (fx,.067,.849-length*.77,.008,.009),
            (fx,.054,.843-length*.36,.0085,.010),
            (fx,.047,.853,.009,.011)],skin,hand,12)
    ellipsoid('Thumb base '+suffix,(hx-side*.032,.064,.881),(.016,.019,.029),skin,hand)
    ellipsoid('Relaxed thumb '+suffix,(hx-side*.041,.073,.854),(.012,.014,.027),skin,hand)

# Only deform bones needed by the pilot view. Animations are driven by
# actual locomotion and ground contacts in Godot instead of baked root motion.
armature = bpy.data.armatures.new('Outdoor body rig')
rig = bpy.data.objects.new('OutdoorBodyRig', armature)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')


def bone(name, head, tail, parent=None):
    item = armature.edit_bones.new(name)
    item.head = head
    item.tail = tail
    if parent:
        item.parent = armature.edit_bones[parent]
    return item


bone('hips',(0,0,.95),(0,0,1.10))
bone('chest',(0,0,1.10),(0,0,1.42),'hips')
for side, suffix in [(-1,'L'),(1,'R')]:
    bone('thigh_'+suffix,(side*.096,0,.95),(side*.096,.016,.52),'hips')
    bone('shin_'+suffix,(side*.096,.016,.52),(side*.096,0,.135),'thigh_'+suffix)
    bone('foot_'+suffix,(side*.096,0,.135),(side*.096,.18,.08),'shin_'+suffix)
    bone('upper_'+suffix,(side*.178,0,1.385),(side*.226,.008,1.155),'chest')
    bone('forearm_'+suffix,(side*.226,.008,1.155),(side*.236,.042,.939),'upper_'+suffix)
    bone('hand_'+suffix,(side*.236,.042,.939),(side*.237,.048,.84),'forearm_'+suffix)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
meshes = [obj for obj in scene.objects if obj.type == 'MESH']
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.object
body.name = 'Outdoor clothing and hands'
body.parent = rig
modifier = body.modifiers.new('Natural joint deformation', 'ARMATURE')
modifier.object = rig
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
scene.render.fps = 30
source = ROOT/'art'/'source'/'first_person_body.blend'
output = ROOT/'game'/'assets'/'first_person_body.glb'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB',
    use_selection=True, use_active_scene=True, export_yup=True, export_skins=True, export_animations=False)
print('FIRST_PERSON_BODY_READY', len(body.data.vertices), 'vertices', output)
