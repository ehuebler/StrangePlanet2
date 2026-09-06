"""Retarget m2m_player.glb clips onto the character-3 humanoid.

The two rigs disagree about names, facing, rest pose and bone roll, so the clips
cannot be copied. Each Mixamo pose is read as a world-space rotation away from
that bone's own rest, then written onto the matching character-3 bone from its
rest. Existing character-3 clips are never rewritten: this script only exports
the new library.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --factory-startup --python assets/source/blender/merge_m2m_animations.py

    # one clip, for checking the retarget:
    ... --python assets/source/blender/merge_m2m_animations.py -- --only=Idle_A

`build_character_3.py` calls [func merge_into_open_file] after the locomotion
bake so a body rebuild still ships the Mixamo library.
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
C3_GLB = os.path.join(ROOT, "assets", "runtime", "characters", "player_character_3.glb")
M2M_GLB = os.path.join(ROOT, "assets", "runtime", "characters", "m2m_player.glb")
OUT_GLB = os.path.join(ROOT, "assets", "runtime", "characters", "player_character_3_m2m.glb")

# Mixamo / UE5 names -> character-3 humanoid. Sides are taken after the source
# armature has been yawed to face the same way as the destination.
BONE_MAP = {
    "pelvis": "Hips",
    "spine_01": "Spine",
    "spine_02": "Chest",
    "spine_03": "UpperChest",
    "neck_01": "Neck",
    "head": "Head",
    "clavicle_l": "LeftShoulder",
    "upperarm_l": "LeftUpperArm",
    "lowerarm_l": "LeftLowerArm",
    "hand_l": "LeftHand",
    "thumb_01_l": "LeftThumb1",
    "thumb_02_l": "LeftThumb2",
    "middle_01_l": "LeftMiddle1",
    "middle_02_l": "LeftMiddle2",
    "middle_03_l": "LeftMiddle3",
    "clavicle_r": "RightShoulder",
    "upperarm_r": "RightUpperArm",
    "lowerarm_r": "RightLowerArm",
    "hand_r": "RightHand",
    "thumb_01_r": "RightThumb1",
    "thumb_02_r": "RightThumb2",
    "middle_01_r": "RightMiddle1",
    "middle_02_r": "RightMiddle2",
    "middle_03_r": "RightMiddle3",
    "thigh_l": "LeftUpperLeg",
    "calf_l": "LeftLowerLeg",
    "foot_l": "LeftFoot",
    "ball_l": "LeftToes",
    "thigh_r": "RightUpperLeg",
    "calf_r": "RightLowerLeg",
    "foot_r": "RightFoot",
    "ball_r": "RightToes",
}

SRC_FOOT, SRC_TOES = "foot_l", "ball_l"
DST_FOOT, DST_TOES = "LeftFoot", "LeftToes"
COLLISION_PREFIX = "m2m_"
# Names already authored on player_character_3.glb. Mixamo clips that share one
# of these keep the Mixamo motion under a prefixed name instead of replacing it.
C3_CLIPS = {
    "Idle", "Walk", "Run", "CrouchIdle", "CrouchWalk", "JumpRise", "Fall",
    "AirRun", "Land", "HeroLand", "Slide", "Float", "Fly", "MeteorFly",
    "StarfireRight", "StarfireLeft", "StarfireFloatRight", "StarfireFloatLeft",
    "NukeThrow", "NukeFloatThrow", "LassoThrow", "LassoFloatThrow",
    "LassoHold", "LassoFloatHold", "WallPlace", "WallFloatPlace",
    "NausicaMark", "NausicaFloatMark", "GrappleGrab", "GrappleCarry",
    "Tread", "Swim",
}


def parse_only() -> list[str]:
    args = sys.argv
    if "--" in args:
        args = args[args.index("--") + 1:]
    else:
        args = []
    wanted: list[str] = []
    for argument in args:
        if argument.startswith("--only="):
            wanted.extend(part for part in argument.split("=", 1)[1].split(",") if part)
    return wanted


def world_matrix(arm: bpy.types.Object, pose_bone: bpy.types.PoseBone) -> Matrix:
    return arm.matrix_world @ pose_bone.matrix


def world_pos(arm: bpy.types.Object, name: str) -> Vector:
    return world_matrix(arm, arm.pose.bones[name]).to_translation()


def facing_delta(arm: bpy.types.Object, foot: str, toes: str) -> Vector:
    return world_pos(arm, toes) - world_pos(arm, foot)


def align_facing(src: bpy.types.Object, dest: bpy.types.Object) -> None:
    """Yaw the Mixamo armature so its toes point the same way as character 3."""
    clear_pose(src)
    clear_pose(dest)
    bpy.context.view_layer.update()
    src_delta = facing_delta(src, SRC_FOOT, SRC_TOES)
    dest_delta = facing_delta(dest, DST_FOOT, DST_TOES)
    src_flat = Vector((src_delta.x, src_delta.y, 0.0))
    dest_flat = Vector((dest_delta.x, dest_delta.y, 0.0))
    if src_flat.length < 1e-6 or dest_flat.length < 1e-6:
        print("facing: could not read toe direction")
        return
    src_flat.normalize()
    dest_flat.normalize()
    # A half-turn when they oppose keeps Mixamo left on character-3 left. A
    # measured yaw from splayed feet is a few degrees off and swaps the sides.
    if src_flat.dot(dest_flat) < 0.0:
        turn = math.pi
    else:
        turn = dest_flat.xy.angle_signed(src_flat.xy)
    if abs(turn) < math.radians(5.0):
        print("facing: already aligned")
        return
    src.rotation_mode = "XYZ"
    src.matrix_world = Matrix.Rotation(turn, 4, "Z") @ src.matrix_world
    bpy.context.view_layer.update()
    print("facing: yawed source {0:.1f} deg so toes match destination".format(
        math.degrees(turn)))


def assign_action(rig: bpy.types.Object, action: bpy.types.Action | None) -> None:
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action
    if action is not None and hasattr(rig.animation_data, "action_slot") and action.slots:
        rig.animation_data.action_slot = action.slots[0]


def mute_nla(rig: bpy.types.Object, mute: bool) -> None:
    if rig.animation_data is None:
        return
    for track in rig.animation_data.nla_tracks:
        track.mute = mute


def clear_pose(rig: bpy.types.Object) -> None:
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        pose_bone.scale = Vector((1.0, 1.0, 1.0))


def hierarchy_order(rig: bpy.types.Object) -> list[str]:
    order: list[str] = []

    def walk(name: str) -> None:
        order.append(name)
        for bone in rig.pose.bones:
            if bone.parent is not None and bone.parent.name == name:
                walk(bone.name)

    for bone in rig.pose.bones:
        if bone.parent is None:
            walk(bone.name)
    return order


def bone_direction(arm: bpy.types.Object, name: str) -> Vector:
    pose_bone = arm.pose.bones[name]
    head = arm.matrix_world @ pose_bone.head
    tail = arm.matrix_world @ pose_bone.tail
    vector = tail - head
    if vector.length < 1e-6:
        return Vector((0.0, 0.0, 1.0))
    return vector.normalized()


def make_basis(along: Vector, side: Vector) -> Matrix:
    """Right-handed world basis with +Y along the bone."""
    y_axis = along.normalized()
    x_axis = side - y_axis * side.dot(y_axis)
    if x_axis.length_squared < 1e-10:
        x_axis = y_axis.orthogonal()
    x_axis.normalize()
    z_axis = x_axis.cross(y_axis).normalized()
    x_axis = y_axis.cross(z_axis).normalized()
    return Matrix((
        (x_axis.x, y_axis.x, z_axis.x),
        (x_axis.y, y_axis.y, z_axis.y),
        (x_axis.z, y_axis.z, z_axis.z),
    ))


def rest_side(along: Vector, up: Vector, forward: Vector) -> Vector:
    """World-space roll axis shared by both rigs, so left and right swing the same way."""
    side = along.cross(up)
    if side.length_squared < 0.05:
        side = along.cross(forward)
    if side.length_squared < 1e-10:
        side = along.orthogonal()
    return side.normalized()


def capture_rest(arm: bpy.types.Object, names: list[str],
                 up: Vector, forward: Vector) -> dict[str, dict]:
    clear_pose(arm)
    bpy.context.view_layer.update()
    rest: dict[str, dict] = {}
    for name in names:
        if name not in arm.pose.bones:
            continue
        matrix = world_matrix(arm, arm.pose.bones[name]).copy()
        along = bone_direction(arm, name)
        side = rest_side(along, up, forward)
        rest[name] = {
            "matrix": matrix,
            "along": along,
            "side": side,
            "basis": make_basis(along, side),
        }
    return rest


def posed_armature(parent_posed: Matrix | None, parent_rest: Matrix | None,
                   rest: Matrix, pose_basis: Matrix) -> Matrix:
    """Armature-space matrix of a bone from its rest-relative pose."""
    if parent_posed is None or parent_rest is None:
        return rest @ pose_basis
    return parent_posed @ parent_rest.inverted() @ rest @ pose_basis


def apply_world_pose(arm: bpy.types.Object, pose_bone: bpy.types.PoseBone,
                     world_rot: Quaternion | None, world_loc: Vector | None,
                     posed: dict[str, Matrix]) -> None:
    """Write a world rotation as loc/quat channels. Parent poses come from `posed`."""
    rest = pose_bone.bone.matrix_local.copy()
    parent = pose_bone.parent
    parent_posed = posed.get(parent.name) if parent is not None else None
    parent_rest = parent.bone.matrix_local.copy() if parent is not None else None
    pose_bone.rotation_mode = "QUATERNION"
    if world_rot is None:
        pose_bone.rotation_quaternion = Quaternion()
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        posed[pose_bone.name] = posed_armature(parent_posed, parent_rest, rest, Matrix.Identity(4))
        return

    arm_r = arm.matrix_world.to_3x3().inverted() @ world_rot.to_matrix()
    if parent_posed is not None and parent_rest is not None:
        pose_r = (rest.to_3x3().inverted() @ parent_rest.to_3x3()
                  @ parent_posed.to_3x3().inverted() @ arm_r)
    else:
        pose_r = rest.to_3x3().inverted() @ arm_r
    quat = pose_r.to_quaternion()
    pose_bone.rotation_quaternion = quat
    if world_loc is not None:
        desired = world_rot.to_matrix().to_4x4()
        desired.translation = world_loc
        arm_space = arm.matrix_world.inverted() @ desired
        if parent_posed is not None and parent_rest is not None:
            pose_basis = rest.inverted() @ parent_rest @ parent_posed.inverted() @ arm_space
        else:
            pose_basis = rest.inverted() @ arm_space
        pose_bone.location = pose_basis.to_translation()
        posed[pose_bone.name] = posed_armature(parent_posed, parent_rest, rest, pose_basis)
    else:
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        pose_basis = quat.to_matrix().to_4x4()
        posed[pose_bone.name] = posed_armature(parent_posed, parent_rest, rest, pose_basis)


def find_armature(has_bone: str) -> bpy.types.Object:
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and has_bone in obj.pose.bones:
            return obj
    raise SystemExit("no armature with bone {0}".format(has_bone))


def find_mesh(arm: bpy.types.Object) -> bpy.types.Object | None:
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.find_armature() == arm:
            return obj
    return None


def _print_pose_sanity(src: bpy.types.Object, dest: bpy.types.Object, label: str) -> None:
    pairs = (
        ("pelvis", "Hips"),
        ("hand_l", "LeftHand"),
        ("hand_r", "RightHand"),
        ("upperarm_l", "LeftUpperArm"),
        ("upperarm_r", "RightUpperArm"),
    )
    print("sanity {0}:".format(label))
    for src_name, dest_name in pairs:
        if src_name not in src.pose.bones or dest_name not in dest.pose.bones:
            continue
        src_p = world_pos(src, src_name)
        dest_p = world_pos(dest, dest_name)
        print("  {0:<14} src={1}  {2:<14} dest={3}".format(
            src_name, tuple(round(v, 3) for v in src_p),
            dest_name, tuple(round(v, 3) for v in dest_p)))


def clip_name_for(track_name: str, occupied: set[str]) -> str:
    if track_name not in occupied:
        return track_name
    prefixed = COLLISION_PREFIX + track_name
    if prefixed not in occupied:
        return prefixed
    index = 2
    while "{0}{1}_{2}".format(COLLISION_PREFIX, track_name, index) in occupied:
        index += 1
    return "{0}{1}_{2}".format(COLLISION_PREFIX, track_name, index)


def source_clips(src: bpy.types.Object) -> list[tuple[str, bpy.types.Action]]:
    if src.animation_data is None:
        return []
    clips: list[tuple[str, bpy.types.Action]] = []
    seen: set[str] = set()
    for track in src.animation_data.nla_tracks:
        if not track.strips or track.strips[0].action is None:
            continue
        name = track.name
        if name in seen:
            continue
        seen.add(name)
        clips.append((name, track.strips[0].action))
    return clips


def retarget_rotation(src_now: Matrix, src_bind: dict, dest_bind: dict) -> Quaternion:
    """Copy the source bone's rotation-from-rest through a rest anatomical frame.

    Mixamo bones run along local +X and character-3 along +Y, so a raw world-axis
    copy hangs one arm. Rebuilding that frame from head-to-tail every tick also
    lets the roll axis flip when two local axes are equally perpendicular.
    The anatomical bases are captured once at rest; each frame only applies
    `src_now` as a change from that rest.
    """
    src_now_r = src_now.to_3x3()
    src_rest_r = src_bind["matrix"].to_3x3()
    src_anat = src_bind["basis"]
    dest_anat = dest_bind["basis"]
    dest_rest_r = dest_bind["matrix"].to_3x3()
    src_pose_anat = src_now_r @ src_rest_r.inverted() @ src_anat
    src_delta = src_anat.inverted() @ src_pose_anat
    dest_pose_anat = dest_anat @ src_delta
    dest_world = dest_pose_anat @ dest_anat.inverted() @ dest_rest_r
    return dest_world.to_quaternion()


def retarget_clip(src: bpy.types.Object, dest: bpy.types.Object, action: bpy.types.Action,
                  name: str, mapping: dict[str, str], src_rest: dict[str, dict],
                  dest_rest: dict[str, dict], dest_order: list[str],
                  height_scale: float) -> None:
    start, end = (int(round(action.frame_range[0])),
                  int(round(action.frame_range[1])))
    if end < start:
        start, end = 1, 1
    mute_nla(src, True)
    mute_nla(dest, True)
    assign_action(src, action)
    assign_action(dest, None)
    clear_pose(dest)

    hips_origin: Vector | None = None
    prev_quats: dict[str, Quaternion] = {}
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()

        dest_rotation: dict[str, Quaternion] = {}
        hips_location: Vector | None = None
        for src_name, dest_name in mapping.items():
            src_now = world_matrix(src, src.pose.bones[src_name])
            src_bind = src_rest[src_name]
            dest_bind = dest_rest[dest_name]
            dest_rotation[dest_name] = retarget_rotation(src_now, src_bind, dest_bind)
            if dest_name == "Hips":
                travel = ((src_now.to_translation() - src_bind["matrix"].to_translation())
                          * height_scale)
                if hips_origin is None:
                    hips_origin = Vector((travel.x, travel.y, 0.0))
                hips_location = dest_bind["matrix"].to_translation() + Vector((
                    travel.x - hips_origin.x,
                    travel.y - hips_origin.y,
                    travel.z,
                ))

        posed: dict[str, Matrix] = {}
        for dest_name in dest_order:
            pose_bone = dest.pose.bones[dest_name]
            apply_world_pose(
                dest, pose_bone,
                dest_rotation.get(dest_name),
                hips_location if dest_name == "Hips" else None,
                posed)
            quat = pose_bone.rotation_quaternion.copy()
            previous = prev_quats.get(dest_name)
            if previous is not None and previous.dot(quat) < 0.0:
                quat.negate()
                pose_bone.rotation_quaternion = quat
            prev_quats[dest_name] = quat
            pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            pose_bone.keyframe_insert(data_path="location", frame=frame)
        if name in {"Idle_A", "Sprint"} and frame in {start, (start + end) // 2}:
            bpy.context.view_layer.update()
            _print_pose_sanity(src, dest, "{0} frame {1}".format(name, frame))

    baked = dest.animation_data.action
    if baked is None:
        raise SystemExit("retarget produced no action for {0}".format(name))
    baked.name = name
    baked.use_fake_user = True
    assign_action(dest, None)
    track = dest.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, start, baked)
    strip.name = name
    strip.blend_type = "REPLACE"
    print("  {0:<28} {1:>4} frames".format(name, end - start + 1))


def export_sidecar(dest: bpy.types.Object, mesh: bpy.types.Object | None,
                   keep_tracks: set[str]) -> None:
    """Write only the retargeted tracks. Original character-3 clips stay muted."""
    if dest.animation_data is not None:
        for track in dest.animation_data.nla_tracks:
            track.mute = track.name not in keep_tracks
    assign_action(dest, None)
    clear_pose(dest)
    bpy.context.view_layer.update()

    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        obj.select_set(False)
    dest.hide_viewport = False
    dest.select_set(True)
    if mesh is not None:
        mesh.hide_viewport = False
        mesh.select_set(True)
    view_layer.objects.active = dest

    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_materials="NONE",
        export_yup=True,
    )
    print("wrote {0} ({1:.1f} KB)".format(OUT_GLB, os.path.getsize(OUT_GLB) / 1024.0))


def merge_into_open_file(dest: bpy.types.Object, mesh: bpy.types.Object | None,
                         only: list[str] | None = None) -> int:
    """Retarget Mixamo clips onto the character-3 rig already in this scene."""
    if not os.path.isfile(M2M_GLB):
        print("skip m2m merge: missing {0}".format(M2M_GLB))
        return 0

    before_objects = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=M2M_GLB)
    src = find_armature("pelvis")
    imported = [obj for obj in bpy.data.objects if obj not in before_objects]

    bpy.context.scene.render.fps = 30
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"

    align_facing(src, dest)
    mapping = {src_name: dest_name for src_name, dest_name in BONE_MAP.items()
               if src_name in src.pose.bones and dest_name in dest.pose.bones}
    missing_src = sorted(name for name in BONE_MAP if name not in src.pose.bones)
    missing_dest = sorted(name for name in BONE_MAP.values() if name not in dest.pose.bones)
    if missing_src:
        print("source bones skipped:", ", ".join(missing_src))
    if missing_dest:
        print("dest bones skipped:", ", ".join(missing_dest))
    print("mapped {0} bones".format(len(mapping)))

    dest_forward = facing_delta(dest, DST_FOOT, DST_TOES)
    dest_forward = Vector((dest_forward.x, dest_forward.y, 0.0))
    if dest_forward.length < 1e-6:
        dest_forward = Vector((0.0, -1.0, 0.0))
    dest_forward.normalize()
    world_up = Vector((0.0, 0.0, 1.0))
    src_rest = capture_rest(src, list(mapping.keys()), world_up, dest_forward)
    dest_rest = capture_rest(dest, list(mapping.values()), world_up, dest_forward)
    dest_order = hierarchy_order(dest)
    src_hip = src_rest["pelvis"]["matrix"].to_translation().z
    dest_hip = dest_rest["Hips"]["matrix"].to_translation().z
    height_scale = dest_hip / src_hip if src_hip > 1e-4 else 1.0
    print("height scale {0:.3f} (hips {1:.3f} -> {2:.3f})".format(
        height_scale, src_hip, dest_hip))
    _print_pose_sanity(src, dest, "rest after align")

    occupied = set(C3_CLIPS)
    if dest.animation_data is not None:
        occupied.update(track.name for track in dest.animation_data.nla_tracks)
    clips = source_clips(src)
    if only:
        wanted = set(only)
        clips = [entry for entry in clips if entry[0] in wanted]
        missing = wanted - {entry[0] for entry in clips}
        if missing:
            raise SystemExit("unknown m2m clips: {0}".format(", ".join(sorted(missing))))

    print("retargeting {0} clips:".format(len(clips)))
    added: set[str] = set()
    for track_name, action in clips:
        dest_name = clip_name_for(track_name, occupied)
        occupied.add(dest_name)
        retarget_clip(src, dest, action, dest_name, mapping, src_rest, dest_rest,
                      dest_order, height_scale)
        added.add(dest_name)

    if added:
        _print_pose_sanity(src, dest, "after last clip")

    export_sidecar(dest, mesh, added)

    if dest.animation_data is not None:
        for track in dest.animation_data.nla_tracks:
            track.mute = False
    assign_action(src, None)
    assign_action(dest, None)
    clear_pose(dest)
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    return len(added)


def main() -> None:
    if not os.path.isfile(C3_GLB):
        raise SystemExit("missing {0}".format(C3_GLB))
    if not os.path.isfile(M2M_GLB):
        raise SystemExit("missing {0}".format(M2M_GLB))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=C3_GLB)
    dest = find_armature("Hips")
    mesh = find_mesh(dest)
    added = merge_into_open_file(dest, mesh, parse_only())
    print("merged {0} m2m clips onto character 3".format(added))


if __name__ == "__main__":
    main()
