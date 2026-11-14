"""(Mapping copied from the exercise-video worktree's bake_painting.py, Nov 14.)
Bakes the app's body painting onto the unisex average MetaHuman (headless):

    Blender -b --python bake_painting.py

The same anatomical mapping as build_human.py, on the MetaHuman's own body:
the torso and head are pinned to landmarks (collarbone, bottom of the pecs,
navel, groin; base of the neck, hip line, glute fold), the limbs are wrapped
like sleeves around their bones, and front and back use the front and back
paintings. The result is baked into the MetaHuman's own UV layout
(DiffuseUV), for the body and the head, as textures for Unreal:
  T_<part>_Paint   the painting (dark skin where it has no paint)
  T_<part>_Shade   the painting's light/dark, for the lit muscles
  T_<part>_Mask1..4  one muscle group per channel:
     1 = chest, back, shoulders   2 = biceps, triceps, forearms
     3 = core, obliques, glutes   4 = quads, hamstrings, calves
"""
import bpy, os, math
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(REPO, "GymTracker", "Assets.xcassets")
EXPORT = os.environ.get("MH_EXPORT", os.path.expanduser("~/Developer/GymTracker-exercise-videos/scripts/exercise-videos/ue/export"))
OUT = os.path.join(HERE, "..", "ue", "textures"); os.makedirs(OUT, exist_ok=True)
RES = int(os.environ.get("BAKE_RES", "2048"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for f in ("body", "face"):
    bpy.ops.import_scene.fbx(filepath=os.path.join(EXPORT, f + ".fbx"))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and not o.name.endswith("_LOD0"): bpy.data.objects.remove(o)
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
for o in arms:
    if o.parent:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
for o in arms:
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    for c in o.children: c.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
rig = [a for a in arms if any(c.type == 'MESH' and "Body" in c.name for c in a.children)][0]
body = [c for c in rig.children if c.type == 'MESH'][0]
face = [c for o in arms if o is not rig for c in o.children if c.type == 'MESH'][0]
B = rig.data.bones
def H(n): return np.array(rig.matrix_world @ B[n].head_local)

# --- Painting joints (app's 200×400 canvas, y down); "_l" = person's left = viewer's right on the FRONT painting.
PJ = {
    "pelvis": (100, 200), "neck": (100, 74), "crown": (100, 4),
    "shoulder_l": (144, 92), "elbow_l": (152.8, 141.8), "wrist_l": (161.8, 195.0), "handtip_l": (170, 240),
    "shoulder_r": (56, 92), "elbow_r": (48.2, 142.3), "wrist_r": (38.2, 195.9), "handtip_r": (30, 240),
    "hip_l": (118, 194), "knee_l": (117.5, 288.7), "ankle_l": (122.4, 359.6), "toe_l": (121, 397),
    "hip_r": (82, 194), "knee_r": (82.1, 288.3), "ankle_r": (77.8, 359.5), "toe_r": (79, 397),
}
# Mesh joints (world, metres): each joint is the next bone's head.
MJ = {}
for s in ("l", "r"):
    MJ["shoulder_" + s], MJ["elbow_" + s], MJ["wrist_" + s] = H("upperarm_" + s), H("lowerarm_" + s), H("hand_" + s)
    m3, m2 = H("middle_03_" + s), H("middle_02_" + s); MJ["handtip_" + s] = m3 + (m3 - m2) * 1.2
    MJ["hip_" + s], MJ["knee_" + s], MJ["ankle_" + s], MJ["toe_" + s] = H("thigh_" + s), H("calf_" + s), H("foot_" + s), H("ball_" + s)

# --- Vertices of both meshes, with their dominant bone.
def mesh_data(o):
    me = o.data
    co = np.array([o.matrix_world @ v.co for v in me.vertices])
    nrm = np.array([(o.matrix_world.to_3x3() @ v.normal).normalized() for v in me.vertices])
    gname = {g.index: g.name for g in o.vertex_groups}
    dom = []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(gname.get(best.group, "") if best else "")
    return co, nrm, dom
def segment(bone, x):
    b = bone.lower(); s = "l" if b.endswith("_l") else "r" if b.endswith("_r") else ("l" if x > 0 else "r")
    if b.startswith("upperarm") or b.startswith("clavicle_out"): return "upper_" + s
    if b.startswith("lowerarm") or b.startswith("wrist"): return "fore_" + s
    if b.startswith(("hand", "index", "middle", "ring", "pinky", "thumb")): return "hand_" + s
    if b.startswith("thigh"): return "thigh_" + s
    if b.startswith(("calf", "ankle")): return "calf_" + s
    if b.startswith(("foot", "ball")) or "toe" in b: return "foot_" + s
    if b.startswith(("neck", "head", "facial")) or b == "": return "head"
    return "torso"

# --- Painting images
def load_px(path):
    img = bpy.data.images.load(path, check_existing=True)
    w, h = img.size
    return np.array(img.pixels[:]).reshape(h, w, 4)[::-1]
PAINT = os.path.join(HERE, "..", "painting")  # the old painting, kept as the mapping source
def asset(side, kind):
    cap = side.capitalize(); return os.path.join(PAINT, f"Body{kind}{cap}.png")
anat = {"front": load_px(asset("front", "Anatomy")), "back": load_px(asset("back", "Anatomy"))}
PH, PW = anat["front"].shape[:2]; KP = PW / 200.0

def painted_halfwidth(a, b, t, sign, cap, img="front"):
    a, b = np.array(a, float), np.array(b, float)
    d = (b - a) / np.linalg.norm(b - a); n = np.array([-d[1], d[0]]) * sign
    c = a + (b - a) * t; w = 0.0
    while w < cap:
        p = c + n * w; x, y = int(p[0] * KP), int(p[1] * KP)
        if x < 0 or y < 0 or x >= PW or y >= PH or anat[img][y, x, 3] < 0.5: break
        w += 0.5
    return max(w, 2.0)
def painted_row_halfwidth(img, y, cap):
    w = 0.0; yy = int(min(max(y, 0), 399.9) * KP)
    while w < cap:
        x = int((100 + w) * KP)
        if x >= PW or anat[img][yy, x, 3] < 0.5: break
        w += 0.5
    return max(w, 4.0)
def pin_y(z, pins):
    zs = [p[0] for p in pins][::-1]; ys = [p[1] for p in pins][::-1]
    if z <= zs[0]: return ys[0] + (z - zs[0]) * (ys[1] - ys[0]) / (zs[1] - zs[0])
    if z >= zs[-1]: return ys[-1] + (z - zs[-1]) * (ys[-1] - ys[-2]) / (zs[-1] - zs[-2])
    return float(np.interp(z, zs, ys))

LIMBS = {}
for s in ("l", "r"):
    LIMBS["upper_" + s] = ("shoulder_" + s, "elbow_" + s, 17)
    LIMBS["fore_" + s] = ("elbow_" + s, "wrist_" + s, 13)
    LIMBS["hand_" + s] = ("wrist_" + s, "handtip_" + s, 16)
    LIMBS["thigh_" + s] = ("hip_" + s, "knee_" + s, 24)
    LIMBS["calf_" + s] = ("knee_" + s, "ankle_" + s, 16)
NB = 24

def map_mesh(co, nrm, dom, all_torso_co):
    n = len(co)
    seg = np.array([segment(dom[i], co[i, 0]) for i in range(n)], dtype=object)
    # The shoulder cap is the deltoid: it belongs to the arm.
    for s, sx in (("l", 1), ("r", -1)):
        sh = MJ["shoulder_" + s]
        sel = (seg == "torso") & (co[:, 0] * sx > abs(sh[0]) - 0.035) & (co[:, 2] > sh[2] - 0.12)
        seg[sel] = "upper_" + s
    front = np.zeros((n, 2)); back = np.zeros((n, 2)); facing = -nrm[:, 1].copy()
    # Limbs: sleeves around the bone (angle picks front / side / back).
    for key, (ja, jb, cap) in LIMBS.items():
        idx = np.where(seg == key)[0]
        if len(idx) == 0: continue
        out_x = 1.0 if key.endswith("_l") else -1.0
        A3, B3 = MJ[ja], MJ[jb]; Lb = np.linalg.norm(B3 - A3); dn = (B3 - A3) / Lb
        Fv = np.array([0.0, -1.0, 0.0]); Fv = Fv - dn * (Fv @ dn); Fv /= np.linalg.norm(Fv)
        Ov = np.cross(dn, Fv)
        if Ov[0] * out_x < 0: Ov = -Ov
        rel = co[idx] - A3; t = rel @ dn / Lb
        r = rel - np.outer(rel @ dn, dn); th = np.arctan2(r @ Ov, r @ Fv)
        pa, pb = np.array(PJ[ja], float), np.array(PJ[jb], float)
        pd = (pb - pa) / np.linalg.norm(pb - pa); pn = np.array([-pd[1], pd[0]])
        sgn = 1.0 if pn[0] * (pa[0] - 100.0) > 0 else -1.0
        wt = np.array([painted_halfwidth(pa, pb, (bi + 0.5) / NB, sgn, cap) for bi in range(NB)])
        bins = np.clip((np.clip(t, 0, 1) * NB).astype(int), 0, NB - 1)
        for k, i in enumerate(idx):
            front[i] = pa + (pb - pa) * t[k] + pn * sgn * np.sin(th[k]) * wt[bins[k]]
        back[idx, 0] = 200.0 - front[idx, 0]; back[idx, 1] = front[idx, 1]
        facing[idx] = np.cos(th)
    # Feet: point at the camera in the painting → front projection around the ankle.
    scale = (PJ["ankle_l"][1] - PJ["crown"][1]) / (TOP_Z - MJ["ankle_l"][2])
    for s in ("l", "r"):
        idx = np.where(seg == "foot_" + s)[0]
        for i in idx:
            d = co[i] - MJ["ankle_" + s]
            front[i] = np.array(PJ["ankle_" + s]) + np.array([d[0], -d[2]]) * scale
        back[idx, 0] = 200.0 - front[idx, 0]; back[idx, 1] = front[idx, 1]
    # Torso: landmark pins, widths matched per height.
    tidx = np.where(seg == "torso")[0]
    for which, pins, out in (("front", FRONT_PINS, front), ("back", BACK_PINS, back)):
        for i in tidx:
            x, z = co[i, 0], co[i, 2]; y = pin_y(z, pins)
            mw = float(np.interp(z, ZB, MESH_HW)); pw = painted_row_halfwidth(which, y, 44 if y < 125 else 48)
            sx = x if which == "front" else -x
            out[i] = (100 + sx / mw * pw, y)
    # Head and neck.
    hidx = np.where(seg == "head")[0]
    for which, pins, out in (("front", HEAD_FRONT, front), ("back", HEAD_BACK, back)):
        for i in hidx:
            x, z = co[i, 0], co[i, 2]; y = pin_y(z, pins)
            pw = painted_row_halfwidth(which, y, 24); mw = 0.075 if z > CHIN_Z else 0.06
            sx = x if which == "front" else -x
            out[i] = (100 + sx / mw * pw, y)
    f = np.clip((facing + 0.3) / 0.6, 0, 1); f = f * f * (3 - 2 * f)
    return front, back, f

bco, bnrm, bdom = mesh_data(body); fco, fnrm, fdom = mesh_data(face)
TOP_Z = float(fco[:, 2].max())
mid = np.abs(bco[:, 0]) < 0.006
CROTCH_Z = float(bco[mid & (bco[:, 2] > 0.5), 2].min())
CLAV_Z = float(H("clavicle_l")[2]); C7_Z = float(H("neck_01")[2]); CHIN_Z = TOP_Z - 0.235
FRONT_PINS = [(C7_Z, 64.6), (CLAV_Z, 78.2), (CLAV_Z - 0.225, 121.2), (CROTCH_Z + 0.255, 166.0), (CROTCH_Z + 0.095, 203.5), (CROTCH_Z, 227.0)]
BACK_PINS = [(C7_Z, 58.0), (float(MJ["shoulder_l"][2]), 90.0), (CROTCH_Z + 0.225, 173.0), (CROTCH_Z + 0.105, 200.0), (CROTCH_Z - 0.01, 227.0)]
HEAD_FRONT = [(TOP_Z, 4.0), (CHIN_Z, 51.0), (CLAV_Z, 78.2)]
HEAD_BACK = [(TOP_Z, 4.0), (float(H("head")[2]), 36.0), (C7_Z, 58.0)]
print("LANDMARKS top %.3f crotch %.3f clav %.3f c7 %.3f" % (TOP_Z, CROTCH_Z, CLAV_Z, C7_Z))
torso_sel = np.array([segment(bdom[i], bco[i, 0]) == "torso" for i in range(len(bco))])
tz = bco[torso_sel, 2]; tx = bco[torso_sel, 0]
ZB = np.linspace(tz.min(), tz.max(), 40)
MESH_HW = np.array([max(np.percentile(np.abs(tx[np.abs(tz - z) < 0.02]), 95) if (np.abs(tz - z) < 0.02).sum() > 5 else 0.1, 0.02) for z in ZB])

def add_layers(o, front, back, facing):
    me = o.data
    for name, cv in (("uv_front", front), ("uv_back", back)):
        uv = me.uv_layers.new(name=name)
        for loop in me.loops:
            c = cv[loop.vertex_index]; uv.data[loop.index].uv = (c[0] / 200.0, 1.0 - c[1] / 400.0)
    attr = me.color_attributes.new("facing", 'FLOAT_COLOR', 'POINT')
    for i in range(len(me.vertices)): attr.data[i].color = (facing[i], facing[i], facing[i], 1)
    me.uv_layers["DiffuseUV"].active = True

for o, (co, nrm, dom) in ((body, (bco, bnrm, bdom)), (face, (fco, fnrm, fdom))):
    add_layers(o, *map_mesh(co, nrm, dom, None))
print("MAPPED")

# ---------------------------------------------------------------------------
# The app's body figure (Nov 14): the MetaHuman itself, front and back, from
# one orthographic camera, plus a shading pass for the tinted muscles and a
# muscle-ID pass to cut the highlight shapes from (cut_regions.py).
import bmesh, json
for o in (body, face):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != 0], context='FACES')
    bm.to_mesh(o.data); bm.free()

def material(kind):
    m = bpy.data.materials.new(kind); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links; N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    fac = N.new("ShaderNodeAttribute"); fac.attribute_name = "facing"
    def uvn(name):
        n = N.new("ShaderNodeUVMap"); n.uv_map = name; return n
    uf, ub = uvn("uv_front"), uvn("uv_back")
    def tex(path, uv, noncolor, closest=False):
        n = N.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(path, check_existing=True); n.extension = 'CLIP'
        if noncolor: n.image.colorspace_settings.name = 'Non-Color'
        if closest: n.interpolation = 'Closest'
        L.new(uv.outputs[0], n.inputs[0]); return n
    if kind == "ids":
        f = tex(os.path.join(HERE, "ids_front.png"), uf, True, True)
        b = tex(os.path.join(HERE, "ids_back.png"), ub, True, True)
        step = N.new("ShaderNodeMath"); step.operation = 'GREATER_THAN'; step.inputs[1].default_value = 0.5
        L.new(fac.outputs["Fac"], step.inputs[0])
        mx = N.new("ShaderNodeMix"); mx.data_type = 'RGBA'; L.new(step.outputs[0], mx.inputs[0])
        L.new(b.outputs["Color"], mx.inputs[6]); L.new(f.outputs["Color"], mx.inputs[7])
        em = N.new("ShaderNodeEmission"); L.new(mx.outputs[2], em.inputs[0]); L.new(em.outputs[0], out.inputs[0])
        return m
    def fmix(a, b):
        mm = N.new("ShaderNodeMix"); mm.data_type = 'FLOAT'; L.new(fac.outputs["Fac"], mm.inputs[0]); L.new(a, mm.inputs[2]); L.new(b, mm.inputs[3]); return mm.outputs[0]
    def cmix(a, b, f):
        mm = N.new("ShaderNodeMix"); mm.data_type = 'RGBA'; L.new(f, mm.inputs[0]); L.new(a, mm.inputs[6]); L.new(b, mm.inputs[7]); return mm.outputs[2]
    bsdf = N.new("ShaderNodeBsdfPrincipled"); bsdf.inputs["Roughness"].default_value = 0.6
    L.new(bsdf.outputs[0], out.inputs[0])
    if kind == "anatomy":
        af, ab = tex(asset("front", "Anatomy"), uf, False), tex(asset("back", "Anatomy"), ub, False)
        skin = N.new("ShaderNodeRGB"); skin.outputs[0].default_value = (0.055, 0.055, 0.065, 1)
        col = cmix(skin.outputs[0], cmix(ab.outputs["Color"], af.outputs["Color"], fac.outputs["Fac"]), fmix(ab.outputs["Alpha"], af.outputs["Alpha"]))
    else:  # shade: the painting's light/dark, lit the same way
        sf, sb = tex(asset("front", "Shade"), uf, True), tex(asset("back", "Shade"), ub, True)
        col = fmix(sb.outputs["Color"], sf.outputs["Color"])
    L.new(col, bsdf.inputs["Base Color"])
    return m

def assign(m):
    for o in (body, face):
        o.data.materials.clear(); o.data.materials.append(m)
        for p in o.data.polygons: p.material_index = 0

# Camera: orthographic, framing the whole body (arms out) with a margin.
pts = np.vstack([bco, fco]); lo, hi = pts.min(0), pts.max(0)
span_x, span_z = hi[0] - lo[0], hi[2] - lo[2]
H = int(os.environ.get("FIG_H", "2240")); margin = 1.03
W = int(round(H * span_x / span_z / 2)) * 2
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = span_z * margin * max(1.0, W / H)
cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
for loc in ((3, -3, 4), (-3, 3, 3)):
    Lt = bpy.data.objects.new("L", bpy.data.lights.new("L", 'SUN')); Lt.data.energy = 3; Lt.location = loc
    Lt.rotation_euler = (Vector((0, 0, 1)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); sc.collection.objects.link(Lt)
sc.world = bpy.data.worlds.new("w")
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.film_transparent = True
OUTF = os.path.join(HERE, "render"); os.makedirs(OUTF, exist_ok=True)
json.dump({"width": W, "height": H}, open(os.path.join(OUTF, "size.json"), "w"))
print("FIGURE", W, H)

def shoot(kind, side):
    cam.location = (cx, -10, cz) if side == "front" else (cx, 10, cz)
    cam.rotation_euler = (math.radians(90), 0, 0 if side == "front" else math.radians(180))
    sc.render.filepath = os.path.join(OUTF, f"{kind}_{side}.png"); bpy.ops.render.render(write_still=True)

for kind in ("anatomy", "shade"):
    assign(material(kind)); sc.render.engine = 'BLENDER_EEVEE'
    sc.view_settings.view_transform = 'AgX' if 'AgX' in [i.identifier for i in sc.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Standard'
    for side in ("front", "back"): shoot(kind, side)
assign(material("ids")); sc.render.engine = 'CYCLES'; sc.cycles.samples = 1; sc.cycles.device = 'CPU'
sc.cycles.use_denoising = False; sc.render.filter_size = 0.01; sc.view_settings.view_transform = 'Raw'
sc.render.image_settings.color_depth = '8'; sc.render.dither_intensity = 0
for side in ("front", "back"): shoot("ids", side)
print("FIGURE DONE")
