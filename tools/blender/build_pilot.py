"""Original Mossvale pilot: metres, Blender Z up, facing -Y. No paid assets.
Run in Blender's Python context. Creates a separate scene, a skinned character,
and baked in-place idle/walk/run/air animations; keeps unrelated scenes intact.
"""
import bpy
import math
from mathutils import Vector


def pilot_material(name, color, roughness=.7, metal=0):
    material = bpy.data.materials.new('Pilot | ' + name)
    material.diffuse_color = (*color, 1)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metal
    return material


def pilot_bind(obj, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    return obj


def pilot_ball(name, center, size, material, bone, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = True
    return pilot_bind(obj, bone)


def pilot_box(name, center, size, material, bone, bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new('Soft edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for face in obj.data.polygons:
        face.use_smooth = True
    return pilot_bind(obj, bone)


def pilot_vertex_weights(vertex, weights):
    if 'blend' in weights:
        first, second, start, span = weights['blend']
        weight = max(0,min(1,(vertex.z-start)/span))
        return {first:weight, second:1-weight}
    return weights


def pilot_loft(name, rings, material, weights, count=20):
    # Each ring stores x/y/z centre and elliptical half-width/depth.
    verts = []
    for x, y, z, rx, ry in rings:
        for j in range(count):
            a = j * math.tau / count
            verts.append((x + rx*math.cos(a), y + ry*math.sin(a), z))
    faces = [tuple(reversed(range(count)))]
    for i in range(len(rings)-1):
        for j in range(count):
            faces.append((i*count+j, i*count+(j+1)%count,
                          (i+1)*count+(j+1)%count, (i+1)*count+j))
    faces.append(tuple((len(rings)-1)*count+j for j in range(count)))
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    data.materials.append(material)
    for face in data.polygons:
        face.use_smooth = True
    for vertex in data.vertices:
        for bone, weight in pilot_vertex_weights(vertex.co,weights).items():
            group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add([vertex.index], weight, 'REPLACE')
    return obj


def pilot_build_geometry():
    scene = bpy.data.scenes.new('Mossvale pilot — rigged source')
    bpy.context.window.scene = scene
    jacket = pilot_material('petrol canvas', (.035,.16,.16), .82)
    rib = pilot_material('knitted cuffs', (.018,.075,.074), .95)
    cream = pilot_material('shoulder canvas', (.58,.51,.36), .85)
    trousers = pilot_material('slate trousers', (.055,.074,.071), .9)
    leather = pilot_material('boot leather', (.095,.06,.035), .76)
    sole = pilot_material('rubber soles', (.018,.024,.022), .94)
    skin = pilot_material('warm skin', (.53,.29,.16), .72)
    hair = pilot_material('dark hair', (.036,.021,.014), .85)
    gold = pilot_material('brass and insignia', (.7,.42,.12), .45, .35)
    eye = pilot_material('eyes', (.012,.021,.019), .35)
    # Tailored jacket, softly tapered through waist and shoulders.
    pilot_loft('Canvas flight jacket', [
        (0,0,.9,.155,.105), (0,0,.94,.174,.117), (0,0,1.06,.18,.118),
        (0,0,1.21,.208,.127), (0,0,1.35,.235,.12),
        (0,0,1.41,.237,.105), (0,0,1.46,.14,.088)], jacket,
        {'blend':['pelvis','chest',1.18,-.22]})
    pilot_loft('Jacket hem', [(0,0,.90,.16,.11),(0,0,.947,.175,.12)],rib,{'pelvis':1})
    pilot_loft('Raised collar', [(0,0,1.42,.112,.09),(0,0,1.495,.096,.075)],cream,{'chest':1})
    pilot_ball('Neck',(0,0,1.49),(.074,.069,.095),skin,'head')
    pilot_box('Front zipper',(0,-.129,1.202),(.012,.008,.40),gold,'chest',.003)
    pilot_box('Zipper pull',(.012,-.143,1.34),(.014,.008,.035),gold,'chest',.004)
    for side in [-1,1]:
        pilot_box('Chest pocket',(side*.123,-.121,1.267),(.115,.022,.12),jacket,'chest',.014)
        pilot_box('Pocket flap',(side*.123,-.136,1.316),(.12,.014,.027),cream,'chest',.006)
        pilot_box('Shoulder reinforcement',(side*.165,0,1.413),(.147,.20,.025),cream,'chest',.012)
        pilot_box('Hip pocket',(side*.13,-.117,1.025),(.11,.014,.06),rib,'pelvis',.008)
    pilot_box('Pilot name patch',(-.121,-.15,1.272),(.078,.005,.026),gold,'chest',.003)
    # A simple wing emblem on the back, readable from the normal camera.
    for side in [-1,1]:
        emblem = pilot_box('Back wing insignia',(side*.065,.13,1.29),(.116,.008,.023),cream,'chest',.007)
        emblem.rotation_euler.y = side*.16
    pilot_ball('Emblem centre',(0,.132,1.29),(.025,.008,.031),gold,'chest',12,8)
    pilot_loft('Trouser seat',[(0,0,.862,.075,.075),(0,0,.915,.156,.101),(0,0,.99,.156,.10)],trousers,{'pelvis':1})
    for side, suffix in [(-1,'L'),(1,'R')]:
        thigh, shin, foot = 'thigh.'+suffix, 'shin.'+suffix, 'foot.'+suffix
        upper, forearm, hand = 'upperarm.'+suffix, 'forearm.'+suffix, 'hand.'+suffix
        pilot_loft('Trouser leg '+suffix,[
            (side*.116,0,.16,.065,.069), (side*.12,0,.27,.074,.077),
            (side*.12,-.009,.46,.08,.082), (side*.12,-.015,.54,.088,.088),
            (side*.115,0,.72,.099,.101), (side*.108,0,.91,.111,.106)],trousers,{'blend':[thigh,shin,.46,.15]})
        pilot_box('Boot sole '+suffix,(side*.12,-.052,.036),(.16,.295,.072),sole,foot,.025)
        pilot_box('Laced boot '+suffix,(side*.12,-.06,.099),(.153,.264,.135),leather,foot,.043)
        pilot_loft('Boot ankle '+suffix,[(side*.12,.008,.08,.074,.074),(side*.12,.006,.224,.068,.07)],leather,{shin:1})
        for i in range(4):
            pilot_box('Boot lace '+suffix,(side*.12,-.084+i*.029,.169),(.076,.006,.005),cream,foot,.002)
        pilot_loft('Jacket sleeve '+suffix,[
            (side*.326,-.025,.91,.055,.056), (side*.32,-.025,1.02,.068,.066),
            (side*.31,-.02,1.115,.077,.074), (side*.3,-.01,1.17,.08,.077),
            (side*.274,0,1.31,.09,.091), (side*.236,0,1.4,.096,.097)],jacket,{'blend':[upper,forearm,1.08,.12]})
        pilot_loft('Wrist cuff '+suffix,[(side*.326,-.025,.889,.055,.054),(side*.326,-.025,.931,.059,.057)],rib,{forearm:1})
        pilot_ball('Hand '+suffix,(side*.327,-.025,.847),(.046,.03,.073),skin,hand)
        pilot_ball('Thumb '+suffix,(side*.297,-.049,.85),(.022,.023,.043),skin,hand,12,8)
    # Human face with a defined jaw, ears, nose and brows; no featureless capsule.
    pilot_loft('Head',[(0,-.018,1.502,.062,.058),(0,-.012,1.535,.092,.081),
                      (0,0,1.6,.12,.104),(0,.004,1.675,.116,.101),
                      (0,.008,1.725,.084,.078),(0,.01,1.747,.036,.036)],skin,{'head':1},24)
    pilot_ball('Nose',(0,-.108,1.597),(.024,.036,.041),skin,'head',16,10)
    for side in [-1,1]:
        pilot_ball('Ear',(side*.12,.004,1.613),(.025,.022,.044),skin,'head',16,10)
        pilot_ball('Eye',(side*.047,-.098,1.643),(.012,.007,.010),eye,'head',12,8)
        brow = pilot_box('Brow',(side*.048,-.099,1.661),(.038,.009,.009),hair,'head',.004)
        brow.rotation_euler.y = side*.1
    pilot_box('Mouth',(0,-.097,1.552),(.047,.007,.006),leather,'head',.003)
    # Cropped hair shell; front hairline follows the brow, back covers the nape.
    verts, faces = [], []
    for ring in range(7):
        for j in range(32):
            angle = j*math.tau/32
            bottom = 1.635 + .066*max(0,-math.sin(angle))
            theta = (1-ring/7)*math.acos(max(-1,min(1,(bottom-1.648)/.115)))
            verts.append((.122*math.sin(theta)*math.cos(angle),.012+.109*math.sin(theta)*math.sin(angle),1.648+.115*math.cos(theta)))
    for ring in range(6):
        for j in range(32):
            faces.append((ring*32+j,ring*32+(j+1)%32,(ring+1)*32+(j+1)%32,(ring+1)*32+j))
    faces.append(tuple(6*32+j for j in range(32)))
    data = bpy.data.meshes.new('Hair shell')
    data.from_pydata(verts,[],faces)
    data.materials.append(hair)
    obj = bpy.data.objects.new('Cropped dark hair',data)
    scene.collection.objects.link(obj)
    for face in data.polygons: face.use_smooth=True
    pilot_bind(obj,'head')
    print('PILOT_GEOMETRY',len(scene.objects),'parts')


def pilot_rig_and_export():
    scene = bpy.context.scene
    parts = [obj for obj in scene.objects if obj.type=='MESH']
    armature = bpy.data.armatures.new('Pilot skeleton')
    rig = bpy.data.objects.new('PilotRig',armature)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name, head, tail, parent=None):
        b = armature.edit_bones.new(name)
        b.head, b.tail = head, tail
        if parent: b.parent=armature.edit_bones[parent]
    bone('root',(0,0,0),(0,0,.2))
    bone('pelvis',(0,0,.94),(0,0,1.12),'root')
    bone('chest',(0,0,1.12),(0,0,1.46),'pelvis')
    bone('head',(0,0,1.46),(0,0,1.73),'chest')
    for side,suffix in [(-1,'L'),(1,'R')]:
        bone('thigh.'+suffix,(side*.108,0,.94),(side*.12,-.015,.54),'pelvis')
        bone('shin.'+suffix,(side*.12,-.015,.54),(side*.12,0,.13),'thigh.'+suffix)
        bone('foot.'+suffix,(side*.12,0,.13),(side*.12,-.19,.07),'shin.'+suffix)
        bone('upperarm.'+suffix,(side*.236,0,1.4),(side*.31,-.02,1.13),'chest')
        bone('forearm.'+suffix,(side*.31,-.02,1.13),(side*.326,-.025,.9),'upperarm.'+suffix)
        bone('hand.'+suffix,(side*.326,-.025,.9),(side*.327,-.025,.8),'forearm.'+suffix)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts: obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    character = bpy.context.object
    character.name = 'Pilot skinned mesh'
    character.parent = rig
    modifier = character.modifiers.new('Pilot deformation','ARMATURE')
    modifier.object = rig
    scene.render.fps = 30
    for b in rig.pose.bones: b.rotation_mode='XYZ'
    for name, length in [('idle',90),('walk',32),('run',22),('air',30)]:
        rig.animation_data_create()
        rig.animation_data.action = None
        # Let Blender create the action slot on first insertion (Blender 5.x).
        for frame in range(1,length+2):
            phase = (frame-1)/length*math.tau
            for b in rig.pose.bones:
                b.rotation_euler=(0,0,0)
                b.location=(0,0,0)
            if name=='idle':
                rig.pose.bones['chest'].rotation_euler.x=.012*math.sin(phase)
                rig.pose.bones['head'].rotation_euler.z=.025*math.sin(phase)
            elif name in ('walk','run'):
                running = name=='run'
                amplitude = .72 if running else .50
                rig.pose.bones['root'].location.y=.025*abs(math.cos(phase)) if running else .012*math.cos(phase*2)
                rig.pose.bones['chest'].rotation_euler.x=.12 if running else .025
                rig.pose.bones['pelvis'].rotation_euler.y=.04*math.sin(phase)
                for suffix, offset in [('L',0),('R',math.pi)]:
                    swing = math.sin(phase+offset)
                    thigh = amplitude*swing
                    knee = .10+max(0,swing)*(1.12 if running else .65)
                    rig.pose.bones['thigh.'+suffix].rotation_euler.x=thigh
                    rig.pose.bones['shin.'+suffix].rotation_euler.x=knee
                    rig.pose.bones['foot.'+suffix].rotation_euler.x=-thigh*.6-knee*.55
                    rig.pose.bones['upperarm.'+suffix].rotation_euler.x=-swing*(.6 if running else .29)
                    rig.pose.bones['forearm.'+suffix].rotation_euler.x=-.8 if running else -.16
            else:
                rig.pose.bones['thigh.L'].rotation_euler.x=-.25
                rig.pose.bones['thigh.R'].rotation_euler.x=.15
                for suffix in ['L','R']:
                    rig.pose.bones['shin.'+suffix].rotation_euler.x=.42
                    rig.pose.bones['forearm.'+suffix].rotation_euler.x=-.4
            for b in rig.pose.bones:
                b.keyframe_insert(data_path='rotation_euler',frame=frame,group=b.name)
                b.keyframe_insert(data_path='location',frame=frame,group=b.name)
        action=rig.animation_data.action
        action.name=name
        action.use_fake_user=True
        track=rig.animation_data.nla_tracks.new()
        track.name=name
        track.strips.new(name,1,action)
        track.mute=True
    rig.animation_data.action=None
    scene.frame_set(1)
    for b in rig.pose.bones:
        b.rotation_euler=(0,0,0)
        b.location=(0,0,0)
    bpy.ops.object.select_all(action='DESELECT')
    character.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.save_as_mainfile(filepath='C:/Users/user/Desktop/antigriavity/AviationGame/art/experiments/mossvale_pilot.blend',copy=True)
    bpy.ops.export_scene.gltf(filepath='C:/Users/user/Desktop/antigriavity/AviationGame/art/experiments/mossvale_pilot.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=True,export_animation_mode='ACTIONS',export_skins=True)
    print('PILOT_EXPORTED',len(character.data.vertices),'vertices',len(armature.bones),'bones')
