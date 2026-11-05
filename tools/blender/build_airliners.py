"""Build MV-10 Albatross (10-seat / 9-passenger commuter) and MV-16 Skywhale (16-seat / 15-passenger regional airliner).
Run with Blender --background --python this_file.
"""
import sys
import math
from pathlib import Path
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_assets import scene_new, mat, mesh, rod, uvball, line, text3d, export


def build_wing(name, span, chord, y, z, material, dihedral=0.018):
    profile = []
    for j in range(21):
        t = (1 - math.cos(math.pi * j / 20)) * 0.5
        h = 0.13 * (0.2969 * math.sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t**3 - 0.1015 * t**4) * 5
        profile.append((t, h))
    profile += [(t, -h * 0.55) for t, h in reversed(profile[1:-1])]
    sections = [
        (-span, 0.22),
        (-span + 0.30, 0.78),
        (-span + 0.95, 0.94),
        (0, 1.0),
        (span - 0.95, 0.94),
        (span - 0.30, 0.78),
        (span, 0.22),
    ]
    vv = [
        (x, y + (t - 0.42) * chord * f + (1 - f) * 0.28, z + h * chord * f + abs(x) * dihedral)
        for x, f in sections
        for t, h in profile
    ]
    n = len(profile)
    ff = [
        (i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j)
        for i in range(len(sections) - 1)
        for j in range(n)
    ]
    ff += [tuple(reversed(range(n))), tuple((len(sections) - 1) * n + j for j in range(n))]
    return mesh(name, vv, ff, material, True)


def build_albatross():
    scene_new('MV-10 Albatross — ten seat regional commuter')
    ivory = mat('Albatross | pearl cream', (0.78, 0.79, 0.74), 0.25, 0.28)
    emerald = mat('Albatross | forest emerald', (0.025, 0.14, 0.095), 0.38, 0.28)
    gold = mat('Albatross | brass gold stripe', (0.76, 0.56, 0.16), 0.55, 0.26)
    dark = mat('Albatross | rubber and seals', (0.018, 0.025, 0.03), 0.0, 0.82)
    glass = mat('Albatross | cockpit glazing', (0.025, 0.095, 0.13), 0.62, 0.15)
    metal = mat('Albatross | brushed alloy', (0.48, 0.52, 0.55), 0.78, 0.30)
    red = mat('Albatross | port light', (0.9, 0.025, 0.015), 0.0, 0.2, 2.0)
    green = mat('Albatross | starboard light', (0.05, 0.85, 0.23), 0.0, 0.2, 2.0)

    rings = [
        (-4.65, 1.85, 0.26, 0.28),
        (-4.30, 1.85, 0.54, 0.48),
        (-3.75, 1.86, 0.68, 0.60),
        (-3.00, 1.94, 0.82, 0.76),
        (-2.35, 2.08, 0.92, 0.96),
        (-1.30, 2.10, 0.95, 0.98),
        (0.20, 2.10, 0.95, 0.98),
        (1.75, 2.08, 0.92, 0.94),
        (2.60, 1.98, 0.76, 0.80),
        (3.55, 1.82, 0.48, 0.54),
        (4.65, 1.70, 0.22, 0.28),
        (5.35, 1.68, 0.09, 0.15),
        (5.60, 1.68, 0.03, 0.05),
    ]
    count = 48
    vertices = [
        (rx * math.cos(j * math.tau / count), y, z + rz * math.sin(j * math.tau / count))
        for y, z, rx, rz in rings
        for j in range(count)
    ]
    faces = []
    for i in range(len(rings) - 1):
        for j in range(count):
            faces.append((i * count + j, i * count + (j + 1) % count, (i + 1) * count + (j + 1) % count, (i + 1) * count + j))
    faces += [tuple(reversed(range(count))), tuple((len(rings) - 1) * count + j for j in range(count))]
    body = mesh('Ten-seat commuter fuselage', vertices, faces, ivory, True)
    body.data.materials.append(emerald)
    for face in body.data.polygons:
        if face.center.z < 1.62:
            face.material_index = 1

    def surface(y, a, side):
        for first, second in zip(rings, rings[1:]):
            if first[0] <= y <= second[0]:
                t = (y - first[0]) / (second[0] - first[0])
                z, rx, rz = [first[k] * (1 - t) + second[k] * t for k in [1, 2, 3]]
                return (side * (rx * math.cos(a) + 0.013), y, z + rz * math.sin(a) + 0.009)
        return (0.0, y, 2.0)

    win_spans = [(-2.30, -1.72), (-1.52, -0.94), (-0.74, -0.16), (0.04, 0.62), (0.82, 1.40), (1.58, 2.12)]
    for side in [-1, 1]:
        stripe = [
            (side * (rx * math.cos(a) + 0.014), y, z + rz * math.sin(a))
            for y, z, rx, rz in rings[1:-1]
            for a in [-0.11, 0.06]
        ]
        mesh('Gold cheatline', stripe, [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(rings) - 3)], gold)
        for start, end in win_spans:
            ys = [start + (end - start) * i / 5 for i in range(6)]
            aa = [0.20, 0.40, 0.60, 0.78]
            vv = [surface(y, a, side) for y in ys for a in aa]
            ff = []
            for i in range(5):
                for j in range(3):
                    q = (i * 4 + j, i * 4 + j + 1, (i + 1) * 4 + j + 1, (i + 1) * 4 + j)
                    ff.append(q if side == 1 else tuple(reversed(q)))
            mesh('Cabin window', vv, ff, glass, True)
            outline = (
                [surface(y, 0.20, side) for y in ys]
                + [surface(end, a, side) for a in aa]
                + [surface(y, 0.78, side) for y in reversed(ys)]
                + [surface(start, a, side) for a in reversed(aa)]
            )
            line('Window seal', outline, 0.014, dark, True)
        line('Airstair door seam', [surface(1.50, 0.15, side), (side * 0.92, 1.50, 1.35), (side * 0.88, 2.25, 1.35), surface(2.25, 0.15, side)], 0.011, dark)
        rod('Cabin grab handle', (side * 0.94, 1.75, 1.92), (side * 0.94, 2.05, 1.92), 0.025, metal)
        rod('Boarding step', (side * 1.04, 1.55, 0.96), (side * 1.04, 2.18, 0.96), 0.05, metal)
        # Wing-mounted auxiliary turboprop nacelle for twin-commuter look
        uvball('Wing turbine nacelle', (side * 2.65, -0.85, 2.86), (0.34, 1.25, 0.32), emerald)
        uvball('Nacelle intake spinner', (side * 2.65, -2.08, 2.86), (0.18, 0.28, 0.18), metal)

    ys = [-3.02 + i * 0.105 for i in range(7)]
    angles = [0.80 + (math.pi - 1.60) * j / 16 for j in range(17)]
    vv = [surface(y, a, 1) for y in ys for a in angles]
    mesh('Flight deck windscreen', vv, [(i * 17 + j, i * 17 + j + 1, (i + 1) * 17 + j + 1, (i + 1) * 17 + j) for i in range(6) for j in range(16)], glass, True)
    line('Windscreen center post', [surface(y, math.pi / 2, 1) for y in ys], 0.026, ivory)

    build_wing('Albatross high wing', 7.6, 2.15, -0.40, 3.02, ivory, 0.016)
    build_wing('T-tail horizontal stabilizer', 2.45, 1.18, 4.72, 3.45, emerald, 0.008)
    fin = [(3.55, 1.72), (4.35, 3.48), (4.95, 3.56), (5.50, 1.68)]
    vv = [(side * 0.09, y, z) for side in [-1, 1] for y, z in fin]
    mesh('Swept T-tail fin', vv, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], emerald)

    for side in [-1, 1]:
        rod('Heavy wing strut', (side * 0.78, 0.12, 1.32), (side * 4.45, -0.25, 3.04), 0.055, metal)
        uvball('Gold winglet tip', (side * 7.48, -0.08, 3.16), (0.15, 0.52, 0.18), gold)
        uvball('Navigation light', (side * 7.58, -0.34, 3.20), (0.065, 0.12, 0.05), red if side < 0 else green)
        text3d('Tail identifier', 'MV10', (side * 0.095, 4.55, 2.55), 0.28, gold, (math.pi / 2, 0, side * math.pi / 2))
        rod('Main landing gear leg', (side * 0.62, 0.25, 1.25), (side * 1.52, 0.42, 0.40), 0.078, metal)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.30, minor_radius=0.13, major_segments=32, minor_segments=12, location=(side * 1.54, 0.42, 0.40), rotation=(0, math.pi / 2, 0))
        tire = bpy.context.object
        tire.name = 'Albatross main tyre'
        tire.data.materials.append(dark)
        for face in tire.data.polygons:
            face.use_smooth = True
        rod('Main wheel hub', (side * 1.38, 0.42, 0.40), (side * 1.70, 0.42, 0.40), 0.17, metal, vertices=24)

    rod('Nose oleo strut', (0, -3.72, 1.38), (0, -3.72, 0.30), 0.07, metal)
    rod('Nose wheel', (-0.09, -3.72, 0.29), (0.09, -3.72, 0.29), 0.29, dark, vertices=32)
    rod('Nose wheel hub', (-0.095, -3.72, 0.29), (0.095, -3.72, 0.29), 0.13, metal, vertices=24)

    uvball('Polished nose spinner', (0, -4.78, 1.85), (0.29, 0.46, 0.29), metal)
    for i in range(4):
        angle = i * math.tau / 4
        def blade_point(x, z):
            return (x * math.cos(angle) + z * math.sin(angle), -4.96, 1.85 - x * math.sin(angle) + z * math.cos(angle))
        vv = [blade_point(x, z) for x, z in [(-0.07, 0.20), (0.11, 0.25), (0.19, 0.96), (0.085, 1.28), (-0.07, 1.22), (-0.10, 0.38)]]
        blade = mesh('Propeller blade', vv, [tuple(range(6))], dark)
        blade.modifiers.new('Blade thickness', 'SOLIDIFY').thickness = 0.028
        mesh('Propeller safety tip', [blade_point(x, z) for x, z in [(-0.07, 1.12), (0.12, 1.12), (0.085, 1.27), (-0.065, 1.22)]], [(0, 1, 2, 3)], gold)

    rod('VHF dorsal antenna', (0, 0.65, 3.08), (0, 0.75, 3.62), 0.015, dark)
    export('albatross_mv10')


def build_skywhale():
    scene_new('MV-16 Skywhale — sixteen seat regional airliner')
    pearl = mat('Skywhale | glacier pearl', (0.83, 0.85, 0.88), 0.22, 0.24)
    navy = mat('Skywhale | royal navy', (0.018, 0.048, 0.14), 0.42, 0.26)
    crimson_gold = mat('Skywhale | imperial gold', (0.82, 0.58, 0.14), 0.58, 0.24)
    dark = mat('Skywhale | carbon and rubber', (0.016, 0.022, 0.028), 0.0, 0.82)
    glass = mat('Skywhale | tinted cockpit glass', (0.022, 0.085, 0.14), 0.65, 0.14)
    metal = mat('Skywhale | titanium alloy', (0.52, 0.56, 0.60), 0.80, 0.28)
    red = mat('Skywhale | port beacon', (0.92, 0.025, 0.015), 0.0, 0.2, 2.2)
    green = mat('Skywhale | starboard beacon', (0.05, 0.88, 0.25), 0.0, 0.2, 2.2)

    rings = [
        (-5.85, 2.02, 0.30, 0.32),
        (-5.40, 2.02, 0.64, 0.58),
        (-4.70, 2.05, 0.84, 0.76),
        (-3.80, 2.15, 1.04, 0.98),
        (-2.95, 2.32, 1.16, 1.20),
        (-1.60, 2.35, 1.20, 1.24),
        (0.40, 2.35, 1.20, 1.24),
        (2.35, 2.32, 1.16, 1.20),
        (3.45, 2.18, 0.94, 0.98),
        (4.65, 1.98, 0.58, 0.64),
        (5.90, 1.85, 0.26, 0.34),
        (6.75, 1.82, 0.10, 0.18),
        (7.05, 1.82, 0.035, 0.06),
    ]
    count = 48
    vertices = [
        (rx * math.cos(j * math.tau / count), y, z + rz * math.sin(j * math.tau / count))
        for y, z, rx, rz in rings
        for j in range(count)
    ]
    faces = []
    for i in range(len(rings) - 1):
        for j in range(count):
            faces.append((i * count + j, i * count + (j + 1) % count, (i + 1) * count + (j + 1) % count, (i + 1) * count + j))
    faces += [tuple(reversed(range(count))), tuple((len(rings) - 1) * count + j for j in range(count))]
    body = mesh('Wide-body regional fuselage', vertices, faces, pearl, True)
    body.data.materials.append(navy)
    for face in body.data.polygons:
        if face.center.z < 1.78:
            face.material_index = 1

    def surface(y, a, side):
        for first, second in zip(rings, rings[1:]):
            if first[0] <= y <= second[0]:
                t = (y - first[0]) / (second[0] - first[0])
                z, rx, rz = [first[k] * (1 - t) + second[k] * t for k in [1, 2, 3]]
                return (side * (rx * math.cos(a) + 0.015), y, z + rz * math.sin(a) + 0.010)
        return (0.0, y, 2.2)

    win_spans = [
        (-2.85, -2.32),
        (-2.12, -1.59),
        (-1.39, -0.86),
        (-0.66, -0.13),
        (0.07, 0.60),
        (0.80, 1.33),
        (1.53, 2.06),
        (2.26, 2.79),
    ]
    for side in [-1, 1]:
        stripe = [
            (side * (rx * math.cos(a) + 0.016), y, z + rz * math.sin(a))
            for y, z, rx, rz in rings[1:-1]
            for a in [-0.12, 0.065]
        ]
        mesh('Imperial gold cheatline', stripe, [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(rings) - 3)], crimson_gold)
        for start, end in win_spans:
            ys = [start + (end - start) * i / 5 for i in range(6)]
            aa = [0.18, 0.36, 0.54, 0.72]
            vv = [surface(y, a, side) for y in ys for a in aa]
            ff = []
            for i in range(5):
                for j in range(3):
                    q = (i * 4 + j, i * 4 + j + 1, (i + 1) * 4 + j + 1, (i + 1) * 4 + j)
                    ff.append(q if side == 1 else tuple(reversed(q)))
            mesh('Airliner oval window', vv, ff, glass, True)
            outline = (
                [surface(y, 0.18, side) for y in ys]
                + [surface(end, a, side) for a in aa]
                + [surface(y, 0.72, side) for y in reversed(ys)]
                + [surface(start, a, side) for a in reversed(aa)]
            )
            line('Window frame', outline, 0.015, dark, True)
        line('Main cabin door', [surface(2.15, 0.14, side), (side * 1.15, 2.15, 1.45), (side * 1.10, 3.05, 1.45), surface(3.05, 0.14, side)], 0.013, dark)
        rod('Airliner door handle', (side * 1.18, 2.45, 2.10), (side * 1.18, 2.80, 2.10), 0.028, metal)
        rod('Wide boarding step', (side * 1.28, 2.15, 1.02), (side * 1.28, 2.95, 1.02), 0.06, metal)
        # Dual wing-mounted high-bypass turbofan/turboprop pods
        uvball('Inboard engine pod', (side * 3.15, -1.05, 3.18), (0.44, 1.55, 0.42), navy)
        uvball('Inboard spinner cone', (side * 3.15, -2.58, 3.18), (0.24, 0.35, 0.24), metal)
        uvball('Outboard engine pod', (side * 5.65, -0.75, 3.28), (0.36, 1.28, 0.34), navy)
        uvball('Outboard spinner cone', (side * 5.65, -2.02, 3.28), (0.20, 0.28, 0.20), metal)

    ys = [-3.82 + i * 0.13 for i in range(7)]
    angles = [0.78 + (math.pi - 1.56) * j / 16 for j in range(17)]
    vv = [surface(y, a, 1) for y in ys for a in angles]
    mesh('Airliner wrap-around windscreen', vv, [(i * 17 + j, i * 17 + j + 1, (i + 1) * 17 + j + 1, (i + 1) * 17 + j) for i in range(6) for j in range(16)], glass, True)
    line('Cockpit center pillar', [surface(y, math.pi / 2, 1) for y in ys], 0.030, pearl)

    build_wing('Skywhale regional wing', 9.4, 2.55, -0.45, 3.42, pearl, 0.018)
    build_wing('High T-tail stabilizer', 3.10, 1.38, 6.05, 4.18, navy, 0.010)
    fin = [(4.45, 1.88), (5.55, 4.22), (6.30, 4.30), (6.95, 1.82)]
    vv = [(side * 0.11, y, z) for side in [-1, 1] for y, z in fin]
    mesh('Tall airliner vertical fin', vv, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], navy)

    for side in [-1, 1]:
        rod('Reinforced wing strut', (side * 0.98, 0.15, 1.45), (side * 5.25, -0.28, 3.45), 0.068, metal)
        # Tall blended winglet
        winglet = [(side * 9.25, -0.65, 3.55), (side * 9.55, -0.15, 4.35), (side * 9.55, 0.35, 4.38), (side * 9.25, 0.45, 3.55)]
        rod('Blended winglet leading edge', winglet[0], winglet[1], 0.09, crimson_gold)
        rod('Blended winglet trailing edge', winglet[3], winglet[2], 0.07, navy)
        uvball('Wingtip strobe', (side * 9.45, -0.35, 3.65), (0.08, 0.15, 0.06), red if side < 0 else green)
        text3d('Tail identifier', 'MV16', (side * 0.115, 5.75, 3.05), 0.34, crimson_gold, (math.pi / 2, 0, side * math.pi / 2))
        rod('Heavy main gear leg', (side * 0.82, 0.30, 1.35), (side * 1.88, 0.48, 0.44), 0.095, metal)
        for wheel_offset in [-0.24, 0.24]:
            bpy.ops.mesh.primitive_torus_add(
                major_radius=0.33,
                minor_radius=0.14,
                major_segments=32,
                minor_segments=12,
                location=(side * (1.88 + wheel_offset), 0.48, 0.44),
                rotation=(0, math.pi / 2, 0),
            )
            tire = bpy.context.object
            tire.name = 'Skywhale bogie tyre'
            tire.data.materials.append(dark)
            for face in tire.data.polygons:
                face.use_smooth = True
        rod('Dual wheel axle', (side * 1.52, 0.48, 0.44), (side * 2.24, 0.48, 0.44), 0.18, metal, vertices=24)

    rod('Heavy nose oleo', (0, -4.68, 1.48), (0, -4.68, 0.32), 0.085, metal)
    rod('Twin nose wheels', (-0.16, -4.68, 0.31), (0.16, -4.68, 0.31), 0.31, dark, vertices=32)
    rod('Nose axle hub', (-0.18, -4.68, 0.31), (0.18, -4.68, 0.31), 0.14, metal, vertices=24)

    uvball('Titanium nose spinner', (0, -5.98, 2.02), (0.34, 0.54, 0.34), metal)
    for i in range(5):
        angle = i * math.tau / 5
        def blade_point(x, z):
            return (x * math.cos(angle) + z * math.sin(angle), -6.18, 2.02 - x * math.sin(angle) + z * math.cos(angle))
        vv = [blade_point(x, z) for x, z in [(-0.08, 0.22), (0.13, 0.28), (0.22, 1.08), (0.095, 1.44), (-0.08, 1.38), (-0.11, 0.42)]]
        blade = mesh('Propeller blade', vv, [tuple(range(6))], dark)
        blade.modifiers.new('Blade thickness', 'SOLIDIFY').thickness = 0.032
        mesh('Propeller safety tip', [blade_point(x, z) for x, z in [(-0.08, 1.26), (0.14, 1.26), (0.095, 1.43), (-0.075, 1.38)]], [(0, 1, 2, 3)], crimson_gold)

    rod('Satcom dorsal fin', (0, 0.40, 3.55), (0, 1.20, 3.85), 0.045, crimson_gold)
    export('skywhale_mv16')


if __name__ == '__main__':
    build_albatross()
    build_skywhale()
