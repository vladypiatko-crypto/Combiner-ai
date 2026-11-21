"""
Ragdoll Rumble - procedural Blender models.

Run:  blender --background --factory-startup --python blender/build_models.py
Outputs:
  src/shared/MeshData.luau   vertex-colored triangle data the game turns into MeshParts at runtime
  blender/exports/*.obj      the same models as OBJ (import into Blender / Roblox 3D Importer)
  blender/renders/*.png      preview renders

Conventions (Blender, Z up): weapons point down +X with the grip at the origin and +Z up.
Export converts to Roblox (Y up): (x, y, z) -> (x, z, -y).
Faces whose material is marked glow are exported as a separate "glow" mesh (rendered Neon).
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_LUAU = os.path.join(ROOT, "src", "shared", "MeshData.luau")
OUT_OBJ = os.path.join(ROOT, "blender", "exports")
OUT_PNG = os.path.join(ROOT, "blender", "renders")
os.makedirs(OUT_OBJ, exist_ok=True)
os.makedirs(OUT_PNG, exist_ok=True)

random.seed(7)

# ---------------------------------------------------------------------------- palette
P = {
    "metal": 0x2B2F3A, "dark": 0x16181F, "steel": 0x8A93A6, "chrome": 0xC9D1E0,
    "wood": 0x9A6233, "woodl": 0xC07A3F, "gold": 0xFFC93C, "goldd": 0xC8901E,
    "red": 0xFF4D5E, "redd": 0xB0283A, "green": 0x2F9E44, "greenl": 0x6BD66B,
    "olive": 0x4C6B3A, "orange": 0xFF8F3C, "cyan": 0x3CF2E0, "blue": 0x3FA9FF,
    "blued": 0x1E4E8C, "purple": 0x8B5CF6, "pink": 0xFF6AD5, "white": 0xF2F4FA,
    "black": 0x0E0F14, "tape": 0xE8E2CF, "blade": 0xDFE8FF, "rock": 0x5A4A42,
    "lava": 0xFF6A1F, "cream": 0xFFF1D6,
}
GLOW = {"g_yellow": 0xFFD34D, "g_cyan": 0x3CF2E0, "g_red": 0xFF3355, "g_blade": 0xE6F6FF,
        "g_orange": 0xFF9A3C, "g_pink": 0xFF5DCF, "g_blue": 0x5BC0FF, "g_white": 0xFFFFFF,
        "g_purple": 0xA56BFF, "g_green": 0x7CFF6B, "g_gold": 0xFFD86B}


def col(name):
    if name in P:
        return P[name], False
    return GLOW[name], True


# ---------------------------------------------------------------------------- builder
class Model:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []  # list of (hex, glow)

    def mat(self, cname):
        c = col(cname)
        if c not in self.mats:
            self.mats.append(c)
        return self.mats.index(c)

    def _new(self, before):
        return [f for f in self.bm.faces if f not in before]

    def _finish(self, before, cname, matrix, bevel=0.0, segments=1):
        bm = self.bm
        faces = self._new(before)
        verts = list({v for f in faces for v in f.verts})
        bmesh.ops.transform(bm, matrix=matrix, verts=verts)
        if bevel > 0:
            edges = list({e for f in faces for e in f.edges})
            bmesh.ops.bevel(bm, geom=edges + verts, offset=bevel, offset_type="OFFSET",
                            segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
        faces = self._new(before)
        mi = self.mat(cname)
        for f in faces:
            f.material_index = mi
        return faces

    # --- primitives (all take a final placement matrix)
    def box(self, size, cname, m=Matrix(), bevel=0.0):
        before = set(self.bm.faces)
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        bmesh.ops.scale(self.bm, vec=Vector(size), verts=r["verts"])
        return self._finish(before, cname, m, bevel)

    def cyl(self, r1, r2, depth, cname, m=Matrix(), seg=12, bevel=0.0):
        """cylinder / cone along +Z centered at origin"""
        before = set(self.bm.faces)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r1, radius2=r2, depth=depth)
        return self._finish(before, cname, m, bevel)

    def sphere(self, r, cname, m=Matrix(), u=12, v=8):
        before = set(self.bm.faces)
        bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=r)
        return self._finish(before, cname, m)

    def ico(self, r, cname, m=Matrix(), sub=1, jitter=0.0):
        before = set(self.bm.faces)
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=r)
        if jitter > 0:
            for v in res["verts"]:
                v.co *= 1 + random.uniform(-jitter, jitter)
        return self._finish(before, cname, m)

    def torus(self, R, r, cname, m=Matrix(), major=16, minor=6, arc=2 * math.pi):
        """ring in the XY plane"""
        bm = self.bm
        before = set(bm.faces)
        full = abs(arc - 2 * math.pi) < 1e-6
        rings = major if full else major + 1
        grid = []
        for i in range(rings):
            a = arc * i / major
            ring = []
            for j in range(minor):
                b = 2 * math.pi * j / minor
                d = R + r * math.cos(b)
                ring.append(bm.verts.new((d * math.cos(a), d * math.sin(a), r * math.sin(b))))
            grid.append(ring)
        for i in range(major):
            a, b = grid[i], grid[(i + 1) % rings]
            for j in range(minor):
                bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor]))
        if not full:
            bm.faces.new(list(reversed(grid[0])))
            bm.faces.new(grid[-1])
        return self._finish(before, cname, m)

    def prism(self, pts, depth, cname, m=Matrix(), bevel=0.0):
        """2D outline in the XZ plane (x, z) extruded along Y"""
        bm = self.bm
        before = set(bm.faces)
        vs = [bm.verts.new((x, -depth / 2, z)) for (x, z) in pts]
        f = bm.faces.new(vs)
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        nv = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
        return self._finish(before, cname, m, bevel)

    def lathe(self, prof, cname, m=Matrix(), seg=16):
        """profile [(radius, z), ...] bottom to top, revolved around Z (closed with caps)"""
        bm = self.bm
        before = set(bm.faces)
        rings = []
        for (r, z) in prof:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), z)) for i in range(seg)])
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for i in range(seg):
                bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        return self._finish(before, cname, m)

    def text(self, body, size, depth, cname, m=Matrix(), bevel=0.02):
        cu = bpy.data.curves.new(self.name + "_txt", "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = depth / 2
        cu.bevel_depth = bevel
        cu.bevel_resolution = 0
        cu.resolution_u = 2
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        ob = bpy.data.objects.new(self.name + "_txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = ob.evaluated_get(dg).to_mesh()
        before = set(self.bm.faces)
        tmp = bmesh.new()
        tmp.from_mesh(me)
        # text lies in XY, extruded along Z -> stand it up facing -Y
        bmesh.ops.rotate(tmp, verts=tmp.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
        tmesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(tmesh)
        tmp.free()
        self.bm.from_mesh(tmesh)
        ob.evaluated_get(dg).to_mesh_clear()
        bpy.data.objects.remove(ob)
        return self._finish(before, cname, m)


def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(x, y, z):
    return Matrix.Diagonal((x, y, z, 1))


AX = R("Y", 90)  # turn a +Z primitive to point down +X

MODELS = {}


def model(fn):
    MODELS[fn.__name__] = fn
    return fn


# ---------------------------------------------------------------------------- weapons
@model
def popper(m):
    m.box((1.55, 0.36, 0.42), "metal", T(0.62, 0, 0.2), bevel=0.05)
    m.box((1.2, 0.34, 0.22), "dark", T(0.5, 0, -0.06), bevel=0.03)
    m.box((0.38, 0.32, 0.85), "dark", T(0.0, 0, -0.38) @ R("Y", -14), bevel=0.06)
    m.torus(0.17, 0.035, "dark", T(0.35, 0, -0.25) @ R("X", 90), major=10, minor=4, arc=math.pi)
    m.cyl(0.09, 0.09, 0.25, "black", T(1.45, 0, 0.22) @ AX, seg=10)
    m.box((0.1, 0.12, 0.12), "dark", T(0.02, 0, 0.45))
    m.box((1.05, 0.02, 0.07), "g_yellow", T(0.62, 0.185, 0.24))
    m.box((1.05, 0.02, 0.07), "g_yellow", T(0.62, -0.185, 0.24))


@model
def scatter(m):
    m.cyl(0.15, 0.15, 2.6, "metal", T(1.35, 0, 0.18) @ AX, seg=12)
    m.cyl(0.1, 0.1, 2.0, "dark", T(1.1, 0, -0.06) @ AX, seg=10)
    m.box((0.95, 0.36, 0.32), "wood", T(1.25, 0, -0.08), bevel=0.06)
    for i in range(5):
        m.box((0.06, 0.38, 0.33), "woodl", T(0.9 + i * 0.17, 0, -0.08))
    m.box((0.8, 0.34, 0.5), "dark", T(0.05, 0, 0.08), bevel=0.05)
    m.prism([(-0.3, 0.25), (-1.55, 0.15), (-1.6, -0.45), (-1.3, -0.5), (-0.35, -0.15)], 0.32, "wood", bevel=0.04)
    m.box((0.12, 0.3, 0.5), "dark", T(-1.58, 0, -0.15))
    for i in range(3):
        m.cyl(0.07, 0.07, 0.3, "g_orange", T(-0.75 + i * 0.22, 0.2, 0.0) @ R("X", 90), seg=8)


@model
def buzzer(m):
    m.box((1.5, 0.4, 0.5), "dark", T(0.55, 0, 0.12), bevel=0.05)
    m.box((1.2, 0.18, 0.08), "metal", T(0.6, 0, 0.42))
    for i in range(6):
        m.box((0.08, 0.2, 0.06), "dark", T(0.15 + i * 0.18, 0, 0.48))
    m.cyl(0.11, 0.11, 0.7, "metal", T(1.55, 0, 0.15) @ AX, seg=10)
    m.cyl(0.15, 0.15, 0.28, "black", T(1.95, 0, 0.15) @ AX, seg=8)
    m.box((0.28, 0.3, 0.95), "metal", T(0.45, 0, -0.5) @ R("Y", 12), bevel=0.04)
    m.box((0.34, 0.32, 0.7), "dark", T(-0.05, 0, -0.35) @ R("Y", -10), bevel=0.05)
    m.box((0.7, 0.08, 0.08), "steel", T(-0.55, 0.12, 0.2))
    m.box((0.7, 0.08, 0.08), "steel", T(-0.55, -0.12, 0.2))
    m.box((0.1, 0.34, 0.5), "dark", T(-0.9, 0, 0.05))
    m.box((1.2, 0.02, 0.06), "g_cyan", T(0.55, 0.21, 0.2))
    m.box((1.2, 0.02, 0.06), "g_cyan", T(0.55, -0.21, 0.2))


@model
def longshot(m):
    m.cyl(0.09, 0.09, 3.0, "dark", T(1.9, 0, 0.12) @ AX, seg=10)
    m.cyl(0.14, 0.14, 0.4, "metal", T(3.35, 0, 0.12) @ AX, seg=10)
    m.box((1.3, 0.36, 0.42), "metal", T(0.45, 0, 0.1), bevel=0.05)
    m.cyl(0.17, 0.17, 1.2, "dark", T(0.55, 0, 0.58) @ AX, seg=12)
    m.cyl(0.22, 0.22, 0.12, "metal", T(1.15, 0, 0.58) @ AX, seg=12)
    m.cyl(0.22, 0.22, 0.12, "metal", T(-0.05, 0, 0.58) @ AX, seg=12)
    m.cyl(0.15, 0.15, 0.03, "g_red", T(1.22, 0, 0.58) @ AX, seg=12)
    m.box((0.1, 0.12, 0.25), "dark", T(0.55, 0, 0.36))
    m.prism([(-0.15, 0.3), (-1.45, 0.22), (-1.6, -0.42), (-1.25, -0.48), (-0.3, -0.2)], 0.34, "olive", bevel=0.04)
    m.box((0.35, 0.3, 0.7), "dark", T(0.0, 0, -0.35) @ R("Y", -12), bevel=0.05)
    for s in (-1, 1):
        m.box((0.05, 0.05, 0.9), "steel", T(2.3, 0.15 * s, -0.25) @ R("X", 18 * s))


@model
def edge(m):
    m.prism([(0.45, 0.1), (3.15, 0.13), (3.6, 0.0), (3.15, -0.13), (0.45, -0.1)], 0.07, "g_blade")
    m.prism([(0.5, 0.13), (3.1, 0.15), (3.1, 0.12), (0.5, 0.1)], 0.09, "steel")
    m.prism([(0.25, 0.0), (0.38, 0.42), (0.5, 0.0), (0.38, -0.42)], 0.3, "gold", bevel=0.02)
    for i in range(4):
        m.cyl(0.1, 0.1, 0.12, "black" if i % 2 == 0 else "red", T(0.1 - i * 0.12, 0, 0) @ AX, seg=8)
    m.sphere(0.11, "gold", T(-0.45, 0, 0), u=8, v=6)


@model
def bonker(m):
    m.lathe([(0.0, -0.45), (0.17, -0.45), (0.2, -0.38), (0.11, -0.3), (0.13, 0.6), (0.2, 1.4),
             (0.33, 2.3), (0.35, 2.75), (0.3, 2.95), (0.0, 3.0)], "woodl", AX, seg=14)
    for z in (-0.1, 0.1, 0.3):
        m.cyl(0.14, 0.14, 0.12, "tape", T(z, 0, 0) @ AX, seg=12)
    m.prism([(1.9, 0.0), (2.0, 0.22), (2.1, 0.0), (2.0, -0.22)], 0.72, "red")
    m.cyl(0.36, 0.36, 0.06, "g_gold", T(2.55, 0, 0) @ AX, seg=14)


@model
def fizz(m):
    m.sphere(0.45, "green", T(0.15, 0, 0), u=12, v=10)
    for z in (-0.18, 0.12):
        m.torus(0.43, 0.04, "dark", T(0.15, 0, z) @ S(1, 1, 1), major=14, minor=4)
    m.cyl(0.18, 0.15, 0.25, "metal", T(0.15, 0, 0.5), seg=10)
    m.torus(0.13, 0.03, "steel", T(0.4, 0, 0.6) @ R("Y", 70), major=10, minor=4)
    m.box((0.08, 0.12, 0.6), "steel", T(-0.05, 0, 0.25) @ R("Y", -20))
    m.sphere(0.1, "g_yellow", T(0.15, 0, 0.67), u=8, v=6)


@model
def boomtube(m):
    m.cyl(0.38, 0.38, 3.2, "olive", T(0.9, 0, 0.2) @ AX, seg=16)
    m.cyl(0.45, 0.5, 0.35, "dark", T(2.6, 0, 0.2) @ AX, seg=16)
    m.cyl(0.32, 0.32, 0.05, "black", T(2.79, 0, 0.2) @ AX, seg=16)
    m.cyl(0.2, 0.01, 0.4, "g_red", T(2.75, 0, 0.2) @ AX, seg=10)
    m.cyl(0.42, 0.42, 0.25, "dark", T(-0.6, 0, 0.2) @ AX, seg=16)
    for x in (0.2, 1.4):
        m.cyl(0.4, 0.4, 0.12, "orange", T(x, 0, 0.2) @ AX, seg=16)
    m.box((0.3, 0.3, 0.6), "dark", T(0.3, 0, -0.35), bevel=0.04)
    m.box((0.5, 0.18, 0.3), "metal", T(1.2, 0, 0.72), bevel=0.03)
    m.cyl(0.08, 0.08, 0.05, "g_red", T(1.46, 0, 0.75) @ AX, seg=8)


# ---------------------------------------------------------------------------- props
def crate(m, main, trim, glow):
    m.box((3.0, 3.0, 3.0), main, T(0, 0, 0), bevel=0.12)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((0.34, 0.34, 3.08), trim, T(1.38 * sx, 1.38 * sy, 0), bevel=0.04)
            m.box((3.08, 0.34, 0.34), trim, T(0, 1.38 * sx, 1.38 * sy), bevel=0.04)
            m.box((0.34, 3.08, 0.34), trim, T(1.38 * sx, 0, 1.38 * sy), bevel=0.04)
    star = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = 0.85 if i % 2 == 0 else 0.36
        star.append((r * math.cos(a), r * math.sin(a)))
    for side in (-1, 1):
        m.prism(star, 0.1, glow, T(0, 1.52 * side, 0))
    m.box((3.1, 0.12, 0.12), glow, T(0, -1.52, -1.0))
    m.box((3.1, 0.12, 0.12), glow, T(0, -1.52, 1.0))


@model
def crate_finisher(m):
    crate(m, "redd", "gold", "g_gold")


@model
def crate_spawn(m):
    crate(m, "blued", "chrome", "g_cyan")


@model
def machine(m):
    m.box((6.0, 4.0, 1.2), "dark", T(0, 0, 0.6), bevel=0.1)
    m.box((5.4, 3.6, 6.4), "purple", T(0, 0, 4.4), bevel=0.2)
    m.box((4.0, 0.3, 2.6), "black", T(0, -1.75, 5.3), bevel=0.05)
    m.box((3.6, 0.1, 2.2), "g_pink", T(0, -1.92, 5.3))
    m.box((2.2, 0.4, 0.6), "dark", T(0, -1.75, 2.4), bevel=0.05)
    m.box((1.6, 0.1, 0.15), "g_cyan", T(0, -1.97, 2.4))
    for i, c in enumerate(("red", "gold", "blue")):
        m.cyl(0.32, 0.32, 0.3, c, T(-1.2 + i * 1.2, -1.9, 3.55) @ R("X", 90), seg=12)
    m.box((5.9, 3.9, 1.2), "dark", T(0, 0, 8.2), bevel=0.15)
    m.box((5.0, 0.1, 0.8), "g_yellow", T(0, -1.97, 8.2))
    m.sphere(1.0, "g_purple", T(0, 0, 9.4), u=14, v=8)
    m.cyl(0.2, 0.2, 1.4, "steel", T(-2.9, 0, 5.4), seg=8)
    m.sphere(0.35, "red", T(-2.9, 0, 6.2), u=10, v=6)


@model
def locker(m):
    m.box((3.2, 2.0, 6.0), "blued", T(0, 0, 3.0), bevel=0.12)
    m.box((1.45, 0.1, 5.5), "blue", T(-0.78, -1.02, 3.0), bevel=0.03)
    m.box((1.45, 0.1, 5.5), "blue", T(0.78, -1.02, 3.0), bevel=0.03)
    for s in (-1, 1):
        for k in range(4):
            m.box((1.0, 0.12, 0.1), "blued", T(0.78 * s, -1.08, 5.2 - k * 0.25))
        m.box((0.12, 0.15, 0.7), "chrome", T(0.18 * s, -1.12, 3.0))
    m.box((2.2, 0.12, 0.5), "g_cyan", T(0, -1.1, 6.35))
    m.box((3.3, 2.1, 0.3), "dark", T(0, 0, 0.15))


@model
def trophy(m):
    m.lathe([(0.0, 0.0), (1.1, 0.0), (1.1, 0.35), (0.8, 0.4), (0.8, 0.7), (0.25, 0.8), (0.2, 1.6),
             (0.45, 1.75), (1.0, 2.2), (1.2, 3.3), (1.1, 3.35), (0.0, 3.0)], "gold", seg=18)
    for s in (-1, 1):
        m.torus(0.45, 0.09, "goldd", T(1.15 * s, 0, 2.7) @ R("X", 90), major=12, minor=5)
    m.box((2.4, 2.4, 0.4), "dark", T(0, 0, -0.2), bevel=0.05)
    star = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = 0.42 if i % 2 == 0 else 0.18
        star.append((r * math.cos(a), r * math.sin(a) + 2.55))
    m.prism(star, 0.08, "g_white", T(0, -1.12, 0))


@model
def coin(m):
    m.cyl(1.0, 1.0, 0.22, "gold", R("X", 90), seg=20)
    m.torus(0.92, 0.08, "goldd", R("X", 90), major=20, minor=4)
    star = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = 0.55 if i % 2 == 0 else 0.23
        star.append((r * math.cos(a), r * math.sin(a)))
    m.prism(star, 0.3, "g_gold")


@model
def saw(m):
    teeth = []
    n = 16
    for i in range(n * 2):
        a = i * math.pi / n
        r = 1.0 if i % 2 == 0 else 0.84
        a2 = a + (0.12 if i % 2 == 0 else 0)
        teeth.append((r * math.cos(a2), r * math.sin(a2)))
    m.prism(teeth, 0.12, "chrome")
    m.cyl(0.62, 0.62, 0.16, "steel", R("X", 90), seg=18)
    m.cyl(0.22, 0.22, 0.3, "g_red", R("X", 90), seg=10)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        m.cyl(0.1, 0.1, 0.2, "dark", T(0.42 * math.cos(a), 0, 0.42 * math.sin(a)) @ R("X", 90), seg=8)


@model
def spike(m):
    m.cyl(0.5, 0.0, 1.0, "chrome", T(0, 0, 0.5), seg=4)
    m.cyl(0.55, 0.55, 0.12, "dark", T(0, 0, 0.06), seg=4)


@model
def lamp(m):
    m.cyl(0.35, 0.45, 0.4, "dark", T(0, 0, 0.2), seg=10)
    m.cyl(0.14, 0.14, 7.0, "metal", T(0, 0, 3.7), seg=8)
    m.box((1.6, 0.2, 0.2), "metal", T(0.7, 0, 7.1))
    m.cyl(0.55, 0.25, 0.5, "dark", T(1.4, 0, 6.85), seg=10)
    m.sphere(0.32, "g_yellow", T(1.4, 0, 6.55), u=10, v=6)


@model
def portal(m):
    m.torus(3.2, 0.35, "dark", R("X", 90), major=28, minor=6)
    m.torus(2.85, 0.12, "g_cyan", R("X", 90), major=28, minor=4)
    for i in range(8):
        a = i * math.pi / 4
        m.box((0.5, 0.8, 0.5), "g_pink", T(3.3 * math.cos(a), 0, 3.3 * math.sin(a)) @ R("Y", -math.degrees(a)))
    m.box((7.6, 2.4, 0.6), "dark", T(0, 0, -3.5), bevel=0.1)


@model
def logo(m):
    m.text("RAGDOLL", 3.2, 0.9, "white", T(0, 0, 1.6))
    m.text("RUMBLE", 3.2, 0.9, "g_pink", T(0, 0, -1.4))
    m.box((15.0, 0.6, 6.8), "dark", T(0, 0.75, 0.1), bevel=0.3)


@model
def bench(m):
    m.box((4.0, 1.2, 0.3), "wood", T(0, 0, 1.1), bevel=0.05)
    for s in (-1, 1):
        m.box((0.3, 1.0, 1.0), "metal", T(1.6 * s, 0, 0.5))


@model
def target(m):
    m.cyl(1.6, 1.6, 0.25, "white", R("X", 90), seg=20)
    m.cyl(1.2, 1.2, 0.3, "red", R("X", 90), seg=20)
    m.cyl(0.8, 0.8, 0.35, "white", R("X", 90), seg=18)
    m.cyl(0.4, 0.4, 0.4, "g_red", R("X", 90), seg=14)
    m.cyl(0.12, 0.12, 4.0, "wood", T(0, 0.3, -2.0), seg=8)


# ---------------------------------------------------------------------------- vfx meshes
@model
def fx_star(m):
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = 1.0 if i % 2 == 0 else 0.42
        pts.append((r * math.cos(a), r * math.sin(a)))
    m.prism(pts, 0.25, "g_white")


@model
def fx_slash(m):
    pts = []
    n = 14
    for i in range(n + 1):
        a = math.radians(-70 + 140 * i / n)
        pts.append((2.0 * math.cos(a), 2.0 * math.sin(a)))
    for i in range(n, -1, -1):
        a = math.radians(-70 + 140 * i / n)
        w = 0.55 * math.sin(math.pi * i / n) + 0.02
        pts.append(((2.0 - w) * math.cos(a) - 0.25, (2.0 - w) * math.sin(a)))
    m.prism(pts, 0.05, "g_white")


@model
def fx_shard(m):
    m.ico(0.5, "g_white", S(1.0, 0.5, 1.6), sub=0, jitter=0.25)


@model
def fx_ring(m):
    m.torus(1.0, 0.08, "g_white", R("X", 90), major=32, minor=4)


@model
def fx_rock(m):
    m.ico(1.0, "rock", S(1.1, 1.0, 0.9), sub=1, jitter=0.18)
    m.ico(0.7, "lava", T(0.25, -0.2, 0.2), sub=0, jitter=0.2)


@model
def fx_halo(m):
    m.torus(1.0, 0.12, "g_gold", major=24, minor=5)


@model
def fx_skull(m):
    m.sphere(1.0, "white", S(1, 1, 0.95), u=12, v=8)
    m.box((1.1, 0.9, 0.6), "white", T(0, 0, -0.75), bevel=0.15)
    for s in (-1, 1):
        m.sphere(0.28, "black", T(0.38 * s, -0.82, 0.05), u=8, v=6)
    m.prism([(-0.12, -0.25), (0.12, -0.25), (0.0, -0.05)], 0.3, "black", T(0, -0.85, 0))


@model
def fx_bolt(m):
    pts = [(0.0, 2.0), (0.55, 2.0), (0.15, 0.4), (0.6, 0.4), (-0.35, -2.0), (0.0, -0.2), (-0.45, -0.2)]
    m.prism(pts, 0.2, "g_yellow")


# ---------------------------------------------------------------------------- export
def to_roblox(v):
    return (v.x, v.z, -v.y)


def fmt(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def export_model(name, m):
    bm = m.bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.verts.index_update()
    subs = {}
    for f in bm.faces:
        hexc, glow = m.mats[f.material_index]
        key = "glow" if glow else "solid"
        subs.setdefault(key, []).append((f, hexc))
    out = {}
    for key, faces in subs.items():
        vmap, verts, tris, cols, pal = {}, [], [], [], []
        for f, hexc in faces:
            if hexc not in pal:
                pal.append(hexc)
            idx = []
            for v in f.verts:
                if v.index not in vmap:
                    vmap[v.index] = len(verts)
                    verts.append(to_roblox(v.co))
                idx.append(vmap[v.index] + 1)
            tris.append(idx)
            cols.append(pal.index(hexc) + 1)
        out[key] = (verts, tris, cols, pal)
    # bounds (roblox space)
    allv = [to_roblox(v.co) for v in bm.verts]
    mn = [min(p[i] for p in allv) for i in range(3)]
    mx = [max(p[i] for p in allv) for i in range(3)]
    ntri = len(bm.faces)
    # OBJ + preview object
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    for hexc, glow in m.mats:
        mat = bpy.data.materials.new(f"{name}_{hexc:06x}")
        r, g, b = ((hexc >> 16) & 255) / 255, ((hexc >> 8) & 255) / 255, (hexc & 255) / 255
        mat.diffuse_color = (r ** 2.2, g ** 2.2, b ** 2.2, 1)
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    with open(os.path.join(OUT_OBJ, name + ".obj"), "w") as fh:
        fh.write(f"# Ragdoll Rumble - {name} (Y up)\n")
        for v in me.vertices:
            x, y, z = to_roblox(v.co)
            fh.write(f"v {x:.4f} {y:.4f} {z:.4f}\n")
        for p in me.polygons:
            fh.write("f " + " ".join(str(i + 1) for i in p.vertices) + "\n")
    return out, (mn, mx), ntri, ob


def luau_table(name, subs, bounds):
    lines = [f'\t["{name}"] = {{']
    mn, mx = bounds
    lines.append(f"\t\tmin = {{ {', '.join(fmt(x) for x in mn)} }}, max = {{ {', '.join(fmt(x) for x in mx)} }},")
    for key in ("solid", "glow"):
        if key not in subs:
            continue
        verts, tris, cols, pal = subs[key]
        lines.append(f"\t\t{key} = {{")
        lines.append("\t\t\tpal = { " + ", ".join(f"0x{c:06x}" for c in pal) + " },")
        lines.append("\t\t\tv = { " + ", ".join(fmt(c) for p in verts for c in p) + " },")
        lines.append("\t\t\tt = { " + ", ".join(str(i) for t in tris for i in t) + " },")
        lines.append("\t\t\tc = { " + ", ".join(str(c) for c in cols) + " },")
        lines.append("\t\t},")
    lines.append("\t},")
    return "\n".join(lines)


def render(ob, path):
    scene = bpy.context.scene
    for o in scene.collection.objects:
        o.hide_render = o is not ob
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = False
    scene.render.resolution_x = 360
    scene.render.resolution_y = 300
    scene.render.film_transparent = False
    scene.world = scene.world or bpy.data.worlds.new("w")
    scene.world.color = (0.05, 0.05, 0.08)
    cam = scene.camera
    if not cam:
        cd = bpy.data.cameras.new("cam")
        cd.type = "ORTHO"
        cam = bpy.data.objects.new("cam", cd)
        scene.collection.objects.link(cam)
        scene.camera = cam
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    center = sum(bb, Vector()) / 8
    size = max((max(c[i] for c in bb) - min(c[i] for c in bb)) for i in range(3))
    d = Vector((1.0, -2.2, 1.0)).normalized()
    cam.location = center + d * (size * 3 + 5)
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = size * 1.35 + 0.3
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    chunks = []
    stats = []
    objects = []
    for name, fn in MODELS.items():
        m = Model(name)
        fn(m)
        subs, bounds, ntri, ob = export_model(name, m)
        chunks.append(luau_table(name, subs, bounds))
        stats.append((name, ntri))
        objects.append((name, ob))
    header = ("--!nocheck\n-- AUTO-GENERATED by blender/build_models.py (Blender " + bpy.app.version_string + "). Do not edit by hand.\n"
              "-- Triangles in Roblox space; c = palette index per triangle; glow meshes render as Neon.\n"
              "return {\n")
    with open(OUT_LUAU, "w") as fh:
        fh.write(header + "\n".join(chunks) + "\n}\n")
    for name, ob in objects:
        render(ob, os.path.join(OUT_PNG, name + ".png"))
    for name, n in stats:
        print(f"MODEL {name}: {n} tris")
    print("WROTE", OUT_LUAU, os.path.getsize(OUT_LUAU), "bytes")


main()
