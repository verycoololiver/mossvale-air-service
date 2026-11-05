import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art" / "source"
GAME_ASSETS = ROOT / "game" / "assets"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, color, roughness=0.75, metallic=0.0, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_box(name, loc, scale, mat, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_pavilion():
    clear_scene()
    m_concrete = make_mat("PavilionConcrete", (0.52, 0.54, 0.50), roughness=0.9)
    m_cedar = make_mat("PavilionCedar", (0.42, 0.28, 0.17), roughness=0.78)
    m_zinc = make_mat("PavilionZinc", (0.23, 0.30, 0.29), roughness=0.45, metallic=0.55)
    m_luggage_brown = make_mat("LuggageLeather", (0.36, 0.20, 0.11), roughness=0.62)
    m_luggage_tan = make_mat("LuggageCanvas", (0.64, 0.52, 0.34), roughness=0.72)
    m_brass = make_mat("PavilionBrass", (0.82, 0.66, 0.32), roughness=0.35, metallic=0.8)
    m_beacon = make_mat("BeaconGlass", (0.98, 0.84, 0.45), roughness=0.2, emission=(0.98, 0.80, 0.35), emission_strength=2.5)

    # Raised timber/stone platform
    add_box("Platform_Base", (0.0, 0.0, 0.08), (4.2, 2.8, 0.16), m_concrete)
    add_box("Platform_Deck", (0.0, 0.0, 0.18), (4.0, 2.6, 0.05), m_cedar)

    # 4 corner cedar posts
    for sx in (-1.65, 1.65):
        for sy in (-1.0, 1.0):
            add_box(f"Post_{sx}_{sy}", (sx, sy, 1.35), (0.14, 0.14, 2.35), m_cedar)

    # Roof tie beams
    add_box("Beam_Front", (0.0, -1.0, 2.45), (3.6, 0.16, 0.16), m_cedar)
    add_box("Beam_Back", (0.0, 1.0, 2.45), (3.6, 0.16, 0.16), m_cedar)

    # Pitched gable roof slopes
    add_box("Roof_Slope_Front", (0.0, -0.68, 2.78), (4.5, 1.65, 0.08), m_zinc, rot=(math.radians(22), 0.0, 0.0))
    add_box("Roof_Slope_Back", (0.0, 0.68, 2.78), (4.5, 1.65, 0.08), m_zinc, rot=(math.radians(-22), 0.0, 0.0))
    add_box("Roof_Ridge", (0.0, 0.0, 3.08), (4.55, 0.22, 0.10), m_brass)

    # Rooftop aviation beacon mini-mast
    add_box("Beacon_Mast", (0.0, 0.0, 3.38), (0.14, 0.14, 0.52), m_zinc)
    add_box("Beacon_Lamp", (0.0, 0.0, 3.72), (0.28, 0.28, 0.24), m_beacon)
    add_box("Beacon_Cap", (0.0, 0.0, 3.88), (0.34, 0.34, 0.06), m_zinc)

    # Passenger waiting bench
    add_box("Bench_Seat", (-0.55, 0.35, 0.52), (2.1, 0.48, 0.07), m_cedar)
    add_box("Bench_Back", (-0.55, 0.56, 0.82), (2.1, 0.06, 0.42), m_cedar, rot=(math.radians(-10), 0.0, 0.0))
    for bx in (-1.35, 0.25):
        add_box(f"Bench_Leg_{bx}", (bx, 0.35, 0.35), (0.10, 0.44, 0.32), m_zinc)

    # Vintage passenger suitcases waiting on the right side
    add_box("Suitcase_Large", (1.05, 0.25, 0.42), (0.62, 0.38, 0.44), m_luggage_brown, rot=(0.0, 0.0, math.radians(14)))
    add_box("Suitcase_Strap1", (0.90, 0.25, 0.42), (0.05, 0.40, 0.45), m_brass, rot=(0.0, 0.0, math.radians(14)))
    add_box("Suitcase_Strap2", (1.20, 0.25, 0.42), (0.05, 0.40, 0.45), m_brass, rot=(0.0, 0.0, math.radians(14)))
    add_box("Suitcase_Small", (1.02, 0.24, 0.76), (0.46, 0.30, 0.24), m_luggage_tan, rot=(0.0, 0.0, math.radians(-8)))

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    GAME_ASSETS.mkdir(parents=True, exist_ok=True)
    blend_path = SOURCE_DIR / "passenger_pavilion.blend"
    glb_path = GAME_ASSETS / "passenger_pavilion.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        export_apply=True,
    )
    print("EXPORTED_PAVILION", glb_path)


if __name__ == "__main__":
    build_pavilion()
