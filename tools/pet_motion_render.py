# Renders PetPose frames (tools/pet_pose_dump.luau JSON) on real pet FBX rigs as image strips, to check the pet motion
# without Studio. Bone maths = carter's pets\pet_clips.py apply_pose (same as PetMotion).
#   /tmp/bpyenv/bin/python tools/pet_motion_render.py pose.json <fbx dir> <out dir>
import json, math, os, sys
import bpy
import numpy as np
from mathutils import Matrix, Vector

pose_json, fbx_dir, out_dir = sys.argv[1:4]
POSES = json.load(open(pose_json))
JOBS_ALL = [  # (scene, pet, frames to show)
    ('walk_quad', 'DireWolf', 6), ('walk_heavy', 'Bear', 6), ('walk_hopper', 'Bunny', 6), ('walk_hopper', 'Frog', 6),
    ('walk_waddle', 'Penguin', 6), ('walk_biped', 'StormEagle', 6), ('walk_quad', 'Griffin', 6),
    ('attack', 'Griffin', 6), ('hit', 'DireWolf', 5), ('win', 'Bunny', 7), ('hatch', 'Penguin', 6), ('run', 'DireWolf', 6),
]
SIZE = 300
ONLY = os.environ.get('ONLY')
JOBS = [j for j in JOBS_ALL if not ONLY or j[1] in ONLY.split(',')]


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


def setup(fbx):
    clear()
    bpy.ops.import_scene.fbx(filepath=fbx, automatic_bone_orientation=False)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    vs = np.array([o.matrix_world @ v.co for o in meshes for v in o.data.vertices])
    return arm, meshes, float(vs[:, 2].max() - vs[:, 2].min()), Vector(((vs[:, 0].max() + vs[:, 0].min()) / 2, (vs[:, 1].max() + vs[:, 1].min()) / 2, (vs[:, 2].max() + vs[:, 2].min()) / 2))


def apply_pose(arm, v, h, base):
    bn = {b.name.split('_')[-1]: arm.matrix_world @ b.head_local for b in arm.data.bones}
    back = bn.get('Tail', bn.get('Body', Vector()))
    fy = 1.0 if bn.get('Head', Vector((0, 1, 0))).y > back.y else -1.0
    sx = 1.0 if bn.get('WingL', Vector((1, 0, 0))).x >= bn.get('Body', Vector()).x else -1.0
    inv = arm.matrix_world.inverted().to_3x3()
    ax = {'X': (inv @ Vector((-fy, 0, 0))).normalized(), 'Z': (inv @ Vector((0, 0, 1))).normalized(),
          'R': (inv @ Vector((0, -sx, 0))).normalized()}

    def rot(pb, p=0.0, y=0.0, r=0.0):
        R = Matrix.Rotation(y, 3, ax['Z']) @ Matrix.Rotation(p, 3, ax['X']) @ Matrix.Rotation(r, 3, ax['R'])
        rest = pb.bone.matrix_local.to_3x3()
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (rest.inverted() @ R @ rest).to_quaternion()

    pbs = {pb.name.split('_')[-1]: pb for pb in arm.pose.bones}
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (1, 0, 0, 0)
    for n, ch in (('LegL', 'legFL'), ('LegR', 'legFR'), ('LegBL', 'legBL'), ('LegBR', 'legBR')):
        if n in pbs: rot(pbs[n], p=v[ch])
    if 'Tail' in pbs: rot(pbs['Tail'], p=v['tailP'], y=v['tailY'])
    if 'Head' in pbs: rot(pbs['Head'], p=v['headP'], y=v['headY'], r=v['headR'])
    if 'Arms' in pbs: rot(pbs['Arms'], p=v['arms'])
    if 'WingL' in pbs: rot(pbs['WingL'], r=v['wing'])
    if 'WingR' in pbs: rot(pbs['WingR'], r=-v['wing'])
    s = h / 5.0
    piv = base.translation.copy()
    off = (Matrix.Translation(piv + Vector((0, v['rootZ'] * s * fy, v['rootY'] * s))) @ Matrix.Rotation(v['rootYaw'], 4, 'Z')
           @ Matrix.Rotation(v['rootR'], 4, (0, fy, 0)) @ Matrix.Rotation(v['rootP'], 4, (-fy, 0, 0)) @ Matrix.Translation(-piv))
    arm.matrix_world = off @ base
    bpy.context.view_layer.update()


def scene_setup(h, mid):
    sc = bpy.context.scene
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); sc.collection.objects.link(cam)
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 3.0; sun.rotation_euler = (0.9, 0.2, 0.7)
    tgt = mid.copy()
    cam.location = mid + Vector((h * 2.6, -h * 1.6, h * 0.5)); cam.data.lens = 40
    cam.data.clip_start = h * 0.01; cam.data.clip_end = h * 100
    cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler(); sc.camera = cam
    w = bpy.data.worlds.get('W') or bpy.data.worlds.new('W'); w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.75, 0.88, 1.0, 1); bg.inputs[1].default_value = 0.9; sc.world = w
    for eng in ('CYCLES',):  # EEVEE needs a GPU (EGL); Cycles runs on the CPU
        try:
            sc.render.engine = eng; break
        except TypeError:
            pass
    if sc.render.engine == 'CYCLES':
        sc.cycles.samples = 16
    sc.view_settings.view_transform = 'Standard'
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = 'PNG'


os.makedirs(out_dir, exist_ok=True)
for scene, pet, n in JOBS:
    fbx = os.path.join(fbx_dir, 'Pet_%s.fbx' % pet)
    if not os.path.exists(fbx):
        print('skip', pet); continue
    arm, meshes, h, mid = setup(fbx)
    base = arm.matrix_world.copy()
    print('height', h, 'mid', mid)
    scene_setup(h, mid)
    frames = POSES[scene]
    picks = [frames[min(len(frames) - 1, round(i * (len(frames) - 1) / max(n - 1, 1)))] for i in range(n)]
    if scene.startswith('walk_'):  # one step cycle at the end of the clip (after the start-up blend)
        picks = frames[-18:][::3][:n]
    tiles = []
    tmp = os.path.join(out_dir, '_f.png')
    for v in picks:
        apply_pose(arm, v, h, base)
        bpy.context.scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp, check_existing=False)
        tiles.append(np.array(im.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)[::-1])
        bpy.data.images.remove(im)
    strip = np.concatenate(tiles, axis=1)
    from PIL import Image
    Image.fromarray((np.clip(strip, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out_dir, '%s_%s.png' % (scene, pet)))
    os.remove(tmp)
    print('wrote', scene, pet)
