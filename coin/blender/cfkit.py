"""Small Blender helpers for COIN FLICK models: chunky low-poly, flat shaded, one mesh object per colour piece.

Run with the bpy venv:  /tmp/bpyenv/bin/python blender/build.py [--only Name] [--no-render]
Units are studs (1 Blender unit = 1 stud), +Z up in Blender (exported as +Y up for Roblox), origin = floor centre.
"""

import math

import bpy  # noqa: F401  (must come first: it registers bmesh and mathutils)
import bmesh
from mathutils import Matrix, Vector


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


class Model:
    def __init__(self, name):
        self.name = name
        self.pieces = {}  # slot -> (bmesh, colour)
        self.materials = {}  # slot -> Roblox Enum.Material name

    def manifest(self, faces):
        """What the game needs to repaint the imported MeshParts (the FBX itself carries no colours)."""
        return {
            "file": f"{self.name}.fbx",
            "faces": faces,
            "pieces": {
                slot: {"color": "#%02x%02x%02x" % tuple(round(c * 255) for c in colour), "material": self.materials[slot]}
                for slot, (_, colour) in self.pieces.items()
            },
        }
    def slot(self, slot, colour, material="SmoothPlastic"):
        if slot not in self.pieces:
            self.pieces[slot] = (bmesh.new(), hexc(colour))
            self.materials[slot] = material
        return Piece(self, self.pieces[slot][0])

    def objects(self):
        out = []
        for slot, (bm, colour) in self.pieces.items():
            mesh = bpy.data.meshes.new(f"{self.name}_{slot}")
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(mesh)
            for poly in mesh.polygons:
                poly.use_smooth = False
            obj = bpy.data.objects.new(f"{self.name}_{slot}", mesh)
            material = bpy.data.materials.new(f"{self.name}_{slot}")
            material.diffuse_color = (*colour, 1)
            material.use_nodes = True
            bsdf = material.node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Base Color"].default_value = (*colour, 1)
            bsdf.inputs["Roughness"].default_value = 0.55
            mesh.materials.append(material)
            bpy.context.scene.collection.objects.link(obj)
            out.append(obj)
        return out


class Piece:
    def __init__(self, model, bm):
        self.model = model
        self.bm = bm

    def _add(self, tmp, mat):
        bmesh.ops.transform(tmp, matrix=mat, verts=tmp.verts)
        mesh = bpy.data.meshes.new("t")
        tmp.to_mesh(mesh)
        tmp.free()
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    @staticmethod
    def _mat(loc, rot, scale=(1, 1, 1)):
        return (
            Matrix.Translation(loc)
            @ Matrix.Rotation(rot[2], 4, "Z")
            @ Matrix.Rotation(rot[1], 4, "Y")
            @ Matrix.Rotation(rot[0], 4, "X")
            @ Matrix.Diagonal((*scale, 1))
        )

    def box(self, size, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        if bevel > 0:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, segments=1, affect="EDGES")
        self._add(tmp, self._mat(loc, rot, size))

    def cyl(self, r_bottom, r_top, h, seg=10, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=seg, radius1=r_bottom, radius2=r_top, depth=h)
        if bevel > 0:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, segments=1, affect="EDGES")
        self._add(tmp, self._mat(loc, rot))

    def ball(self, r, loc=(0, 0, 0), scale=(1, 1, 1), seg=7, rings=5, rot=(0, 0, 0)):
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=seg, v_segments=rings, radius=r)
        self._add(tmp, self._mat(loc, rot, scale))

    def cone(self, r, h, seg=7, loc=(0, 0, 0), rot=(0, 0, 0)):
        self.cyl(r, 0.0, h, seg=seg, loc=loc, rot=rot)

    def star(self, r_out, r_in, depth, points=5, loc=(0, 0, 0), rot=(0, 0, 0)):
        """Flat extruded star lying in the XY plane, thickness `depth` along Z."""
        tmp = bmesh.new()
        verts = []
        for i in range(points * 2):
            ang = math.pi / 2 + i * math.pi / points
            r = r_out if i % 2 == 0 else r_in
            verts.append(tmp.verts.new((math.cos(ang) * r, math.sin(ang) * r, -depth / 2)))
        face = tmp.faces.new(verts)
        res = bmesh.ops.extrude_face_region(tmp, geom=[face])
        top = [v for v in res["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(tmp, vec=(0, 0, depth), verts=top)
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        self._add(tmp, self._mat(loc, rot))


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export_fbx(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        axis_forward="-Z",
        axis_up="Y",
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )


def render(objs, path, size=(640, 480), cam_dir=(1.0, -1.25, 0.8), samples=12, target=None, dist=None):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.84, 1.0, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    scene.world = world
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = target or (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    d = Vector(cam_dir).normalized()
    cam.location = centre + d * (dist or radius * 3.2)
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 1.7
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
