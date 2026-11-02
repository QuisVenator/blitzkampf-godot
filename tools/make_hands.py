"""Generates assets/models/viewmodel/hands.glb: two low-poly first-person hands.

Run: blender -b --factory-startup --python tools/make_hands.py -- assets/models/viewmodel/hands.glb

Every finger joint is its own object, parented in a chain (index_01 > index_02 > index_03),
with its origin at the joint, so a joint can be rotated in the Godot editor like any node.
Rest pose: palm down, fingers straight, pointing forward. In Godot a finger curls by
rotating its joints around local X (positive = towards the palm).
Units are metres. The hand is about human size; scale it in the viewmodel scene if needed.
"""
import math
import sys

import bpy
from mathutils import Matrix

SKIN = (0.97, 0.69, 0.20, 1.0)
JOINT = (0.74, 0.40, 0.95, 1.0)

# (name, knuckle x offset from the palm centre towards the pinky side, segment lengths)
FINGERS = [
    ("index", -0.0375, (0.040, 0.025, 0.021)),
    ("middle", -0.0125, (0.045, 0.028, 0.022)),
    ("ring", 0.0125, (0.041, 0.026, 0.020)),
    ("pinky", 0.0375, (0.032, 0.021, 0.018)),
]
THUMB = (0.034, 0.028, 0.024)
PALM = (0.09, 0.094, 0.026)  # x width, y length, z thickness
FOREARM_LENGTH = 0.42


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


skin_mat = None
joint_mat = None


def finish(obj, mat, bevel=0.0):
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def box(name, size, center, parent):
    """A box whose own origin sits at the parent's joint; `center` is the box middle."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(scale=True)
    obj.location = center
    obj.parent = parent
    bpy.context.view_layer.update()
    # Move the geometry, not the origin: the origin stays at the joint (parent space 0).
    obj.data.transform(Matrix.Translation(center))
    obj.location = (0, 0, 0)
    return obj


def joint_ball(name, radius, parent):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = parent
    obj.location = (0, 0, 0)
    return finish(obj, joint_mat)


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.01
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


def segment(name, length, width, parent, location, rotation_z=0.0):
    """One finger bone: an empty at the joint with a box along +Y and a joint ball."""
    joint = empty(name, location, parent)
    joint.rotation_euler = (0.0, 0.0, rotation_z)
    body = box(name + "_mesh", (width, length, width * 0.9), (0.0, length / 2.0, 0.0), joint)
    finish(body, skin_mat, bevel=width * 0.18)
    joint_ball(name + "_joint", width * 0.58, joint)
    return joint


def build_hand(side):
    """`side` is "R" or "L". The left hand is the right hand mirrored across x."""
    sign = 1.0 if side == "R" else -1.0
    wrist = empty("hand_" + side, (0.0, 0.0, 0.0))

    arm = box("forearm_" + side, (0.062, FOREARM_LENGTH, 0.058), (0.0, -FOREARM_LENGTH / 2.0 - 0.012, 0.0), wrist)
    finish(arm, skin_mat, bevel=0.012)
    cuff = box("cuff_" + side, (0.07, 0.03, 0.066), (0.0, -0.022, 0.0), wrist)
    finish(cuff, joint_mat, bevel=0.008)

    palm = box("palm_" + side, (PALM[0], PALM[1], PALM[2]), (0.0, PALM[1] / 2.0, 0.0), wrist)
    finish(palm, skin_mat, bevel=0.01)

    for finger, knuckle_x, lengths in FINGERS:
        width = 0.018 if finger != "pinky" else 0.016
        parent = wrist
        location = (sign * knuckle_x, PALM[1], 0.0)
        for index, length in enumerate(lengths, start=1):
            parent = segment(f"{finger}_{index:02d}_{side}", length, width, parent, location)
            location = (0.0, length, 0.0)

    parent = wrist
    location = (-sign * 0.036, 0.02, 0.0)
    rotation = sign * math.radians(38.0)
    for index, length in enumerate(THUMB, start=1):
        parent = segment(f"thumb_{index:02d}_{side}", length, 0.021, parent, location, rotation)
        location = (0.0, length, 0.0)
        rotation = 0.0
    return wrist


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    global skin_mat, joint_mat
    bpy.ops.wm.read_factory_settings(use_empty=True)
    skin_mat = material("Skin", SKIN)
    joint_mat = material("Joint", JOINT)
    right = build_hand("R")
    left = build_hand("L")
    # Place them side by side for a preview; the game positions them itself.
    right.location = (0.0, 0.0, 0.0)
    left.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("wrote", out)


main()
