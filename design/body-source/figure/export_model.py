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
# The app's 3D body (Nov 14): one light mesh, one texture layout, three
# baked textures, written as raw arrays the app turns into SceneKit geometry.
#   BodyModel.bin     header + positions, normals, uvs (float32) + indices (uint32)
#   BodyColor.png     the grey anatomy
#   BodyShade.png     its light/dark (multiplied by a highlight colour)
#   BodyIDs.png       muscle index x 4 per texel (ids.json), 0 = no muscle
import bmesh, json, struct
TARGET = int(os.environ.get("TARGET_TRIS", "60000"))
RES = int(os.environ.get("TEX_RES", "2048"))
OUTD = os.path.join(HERE, "model"); os.makedirs(OUTD, exist_ok=True)
for o in (body, face):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != 0], context='FACES')
    bm.to_mesh(o.data); bm.free()
    for u in [u.name for u in o.data.uv_layers if u.name not in ("uv_front", "uv_back")]:
        o.data.uv_layers.remove(o.data.uv_layers[u])
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); face.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
o = body; me = o.data
tris = sum(len(p.vertices) - 2 for p in me.polygons)
mod = o.modifiers.new("dec", 'DECIMATE'); mod.ratio = min(1.0, TARGET / tris)
bpy.ops.object.modifier_apply(modifier="dec")
print("TRIS", tris, "->", sum(len(p.vertices) - 2 for p in me.polygons))
me.uv_layers.new(name="AppUV"); me.uv_layers["AppUV"].active = True
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')

# --- Muscle areas on the mesh itself (Nov 14). The paintings only face the
# camera front and back; on the flanks, the sides of limbs and the head they
# smear. So the painted area is trusted only where it faces you squarely
# (FRONT_OK / BACK_OK), and everywhere else each vertex takes the nearest
# trusted area across the mesh surface (Dijkstra on edge lengths), never
# crossing into another body part. Faces then carry one flat area each, so
# the side boundaries follow the mesh, cleanly.
import heapq, json
TRUST = 0.5   # |normal toward the camera| above this: the painting faces you squarely
def load_ids(side):
    img = bpy.data.images.load(os.path.join(HERE, f"ids_{side}.png"), check_existing=True)
    w, h = img.size
    a = np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, 0]
    return np.round(a * 255 / 4).astype(int)
IDF, IDB = load_ids("front"), load_ids("back")
IH, IW = IDF.shape; KI = IW / 200.0
nv = len(me.vertices)
fac_attr = me.color_attributes["facing"]
facing_v = np.array([fac_attr.data[i].color[0] for i in range(nv)])
# How squarely each vertex faces front or back (0 = side, 1 = straight on),
# from the surface itself: the painting's own facing saturates early.
square_v = np.array([abs(v.normal[1]) for v in me.vertices])
sq_attr = me.color_attributes.new("square", 'FLOAT_COLOR', 'POINT')
for i in range(nv): sq_attr.data[i].color = (square_v[i],) * 3 + (1,)
ufront, uback = me.uv_layers["uv_front"].data, me.uv_layers["uv_back"].data
def sample(img, uv):
    x = int(min(max(uv[0] * 200 * KI, 0), IW - 1)); y = int(min(max((1 - uv[1]) * 400 * KI, 0), IH - 1))
    return int(img[y, x])
votes = [dict() for _ in range(nv)]
for loop in me.loops:
    vi = loop.vertex_index
    if square_v[vi] < TRUST: continue
    lab = sample(IDF, ufront[loop.index].uv) if facing_v[vi] > 0.5 else sample(IDB, uback[loop.index].uv)
    # A gap between muscles is only believed where it faces you squarely;
    # off to the side it's the painting's edge, and the fill covers it.
    if lab == 0 and square_v[vi] < 0.8: continue
    votes[vi][lab] = votes[vi].get(lab, 0) + 1
label = np.full(nv, -1, int)
for i, v in enumerate(votes):
    if v: label[i] = max(v, key=v.get)
# Body part per vertex (same split as the painting map), so a fill never
# crosses from the arm into the torso or from the neck into the head.
gname = {g.index: g.name for g in o.vertex_groups}
part = []
for v in me.vertices:
    best = max(v.groups, key=lambda g: g.weight, default=None)
    part.append(segment(gname.get(best.group, "") if best else "", v.co[0]))
adj = [[] for _ in range(nv)]
for e in me.edges:
    a, b = e.vertices; L = (me.vertices[a].co - me.vertices[b].co).length
    adj[a].append((b, L)); adj[b].append((a, L))
# Areas that never light for training (joints, serratus, fascia, groin) keep
# their painted shape where trusted but don't spread: on the 3D flanks they
# became large grey blotches. The muscles round them fill the sides instead.
# (Head, hands and feet are their own body parts, so they still fill there.)
NAMES = {v: k for k, v in json.load(open(os.path.join(HERE, "ids.json"))).items()}
NO_SPREAD = {i for i, n in NAMES.items() if n.startswith(("serratus", "elbow", "wrist", "knee", "ankle", "hipFlexor"))
             or n in ("midBack", "lowerBack", "groin")}
dist = np.full(nv, np.inf); heap = []
for i in range(nv):
    if label[i] > 0 and label[i] not in NO_SPREAD: dist[i] = 0; heapq.heappush(heap, (0.0, i))
filled = label.copy()
while heap:
    d, i = heapq.heappop(heap)
    if d > dist[i]: continue
    for j, L in adj[i]:
        if label[j] >= 0 or part[j] != part[i]: continue
        nd = d + L
        if nd < dist[j]:
            dist[j] = nd; filled[j] = filled[i]; heapq.heappush(heap, (nd, j))
filled[filled < 0] = 0
# Hands and feet are only ever hand and foot (a shin or forearm area painted
# down over them lit the top of the foot).
INDEX = {n: i for i, n in NAMES.items()}
for i in range(nv):
    pt = part[i]
    if pt.startswith(("hand_", "foot_")):
        side = "Left" if pt.endswith("_l") else "Right"
        filled[i] = INDEX[("hand" if pt.startswith("hand") else "foot") + side]
print("FLOOD trusted", int((label >= 0).sum()), "filled", int(((label < 0) & (filled > 0)).sum()), "of", nv)
flood = me.color_attributes.new("flood", 'FLOAT_COLOR', 'CORNER')
for poly in me.polygons:
    labs = [int(filled[me.loops[li].vertex_index]) for li in poly.loop_indices]
    lab = max(set(labs), key=labs.count)
    c = lab * 4 / 255.0
    for li in poly.loop_indices: flood.data[li].color = (c, c, c, 1)

def material(kind):
    m = bpy.data.materials.new(kind); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links; N.clear()
    out = N.new("ShaderNodeOutputMaterial"); em = N.new("ShaderNodeEmission"); L.new(em.outputs[0], out.inputs[0])
    fac = N.new("ShaderNodeAttribute"); fac.attribute_name = "facing"
    def uvn(name):
        n = N.new("ShaderNodeUVMap"); n.uv_map = name; return n
    uf, ub = uvn("uv_front"), uvn("uv_back")
    def tex(path, uv, noncolor, closest=False):
        n = N.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(path, check_existing=True); n.extension = 'CLIP'
        if noncolor: n.image.colorspace_settings.name = 'Non-Color'
        if closest: n.interpolation = 'Closest'
        L.new(uv.outputs[0], n.inputs[0]); return n
    def detail_weight(sq):
        r = N.new("ShaderNodeMapRange"); r.interpolation_type = 'SMOOTHSTEP'
        L.new(sq, r.inputs["Value"]); r.inputs["From Min"].default_value = 0.3; r.inputs["From Max"].default_value = 0.6
        return r.outputs["Result"]
    def fmix(a, b):
        mm = N.new("ShaderNodeMix"); mm.data_type = 'FLOAT'; L.new(fac.outputs["Fac"], mm.inputs[0]); L.new(a, mm.inputs[2]); L.new(b, mm.inputs[3]); return mm.outputs[0]
    def cmix(a, b, f):
        mm = N.new("ShaderNodeMix"); mm.data_type = 'RGBA'; L.new(f, mm.inputs[0]); L.new(a, mm.inputs[6]); L.new(b, mm.inputs[7]); return mm.outputs[2]
    def math(op, a, b=None, v=None):
        n = N.new("ShaderNodeMath"); n.operation = op
        L.new(a, n.inputs[0])
        if b is not None: L.new(b, n.inputs[1])
        elif v is not None: n.inputs[1].default_value = v
        return n.outputs[0]
    # How squarely a painting faces you: 0 at the side, 1 straight on.
    sqn = N.new("ShaderNodeAttribute"); sqn.attribute_name = "square"; sq = sqn.outputs["Fac"]
    if kind == "ids":
        f = tex(os.path.join(HERE, "ids_front.png"), uf, True, True)
        b = tex(os.path.join(HERE, "ids_back.png"), ub, True, True)
        step = math('GREATER_THAN', fac.outputs["Fac"], v=0.5)
        painted = cmix(b.outputs["Color"], f.outputs["Color"], step)
        fl = N.new("ShaderNodeAttribute"); fl.attribute_name = "flood"
        trusted = math('GREATER_THAN', sq, v=TRUST)
        col = cmix(fl.outputs["Color"], painted, trusted)
    elif kind == "color":
        af, ab = tex(asset("front", "Anatomy"), uf, False), tex(asset("back", "Anatomy"), ub, False)
        skin = N.new("ShaderNodeRGB"); skin.outputs[0].default_value = (0.055, 0.055, 0.065, 1)
        col = cmix(skin.outputs[0], cmix(ab.outputs["Color"], af.outputs["Color"], fac.outputs["Fac"]), fmix(ab.outputs["Alpha"], af.outputs["Alpha"]))
        # Toward the side the painted detail fades to plain body grey
        # instead of smearing into stripes.
        plain = N.new("ShaderNodeRGB"); plain.outputs[0].default_value = (0.20, 0.20, 0.215, 1)
        col = cmix(plain.outputs[0], col, detail_weight(sq))
    else:
        sf, sb = tex(asset("front", "Shade"), uf, True), tex(asset("back", "Shade"), ub, True)
        col = fmix(sb.outputs["Color"], sf.outputs["Color"])
        mm = N.new("ShaderNodeMix"); mm.data_type = 'FLOAT'
        L.new(detail_weight(sq), mm.inputs[0]); mm.inputs[2].default_value = 0.8; L.new(col, mm.inputs[3])
        col = mm.outputs[0]
    L.new(col, em.inputs[0])
    target = N.new("ShaderNodeTexImage"); N.active = target
    return m, target

sc.render.engine = 'CYCLES'; sc.cycles.samples = 1; sc.cycles.device = 'CPU'
sc.render.bake.use_clear = True
bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
for kind, name, margin in (("color", "BodyColor", 8), ("shade", "BodyShade", 8), ("ids", "BodyIDs", 4)):
    m, target = material(kind)
    me.materials.clear(); me.materials.append(m)
    for p in me.polygons: p.material_index = 0
    img = bpy.data.images.new(name, RES, RES, alpha=False)
    if kind != "color": img.colorspace_settings.name = 'Non-Color'
    target.image = img
    sc.render.bake.margin = margin
    sc.render.filter_size = 0.01 if kind == "ids" else 1.5
    bpy.ops.object.bake(type='EMIT', uv_layer="AppUV")
    img.filepath_raw = os.path.join(OUTD, name + ".png"); img.file_format = 'PNG'; img.save()
    print("BAKED", name)

# Geometry: triangulate, one vertex per (position, normal, uv) corner.
bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.triangulate(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
me.calc_loop_triangles() if hasattr(me, "calc_loop_triangles") else None
uv = me.uv_layers["AppUV"].data
co = np.array([v.co[:] for v in me.vertices])
# Z-up metres -> Y-up, centred, 2 units tall, facing +Z.
co = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)
lo, hi = co.min(0), co.max(0); c = (lo + hi) / 2; s = 2.0 / (hi[1] - lo[1])
co = (co - c) * s
nrm_loop = np.zeros((len(me.loops), 3)); me.loops.foreach_get("normal", nrm_loop.ravel()) if False else None
keys = {}; P = []; Nn = []; U = []; I = []
cn = me.corner_normals if hasattr(me, "corner_normals") else None
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        n = cn[li].vector if cn is not None else me.loops[li].normal
        n = (n[0], n[2], -n[1])
        u = uv[li].uv
        k = (vi, round(u[0], 5), round(u[1], 5), round(n[0], 2), round(n[1], 2), round(n[2], 2))
        if k not in keys:
            keys[k] = len(P); P.append(co[vi]); Nn.append(n); U.append((u[0], 1.0 - u[1]))
        I.append(keys[k])
P = np.array(P, np.float32); Nn = np.array(Nn, np.float32)
Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-6)
U = np.array(U, np.float32); I = np.array(I, np.uint32)
with open(os.path.join(OUTD, "BodyModel.bin"), "wb") as f:
    f.write(struct.pack("<4sII", b"BDY1", len(P), len(I)))
    f.write(P.tobytes()); f.write(Nn.tobytes()); f.write(U.tobytes()); f.write(I.tobytes())
print("MODEL", len(P), "verts", len(I) // 3, "tris")


# --- The area map, texel by texel (Nov 14). Each vertex's area is blended
# with its neighbours' (a few smoothing passes), then every texel of every
# triangle takes the strongest blended area: curved, even boundaries
# instead of triangle-edge steps. Where the body faces you squarely the
# painting's own outline is used (it's exact there).
SMOOTH = 3
weights = [{int(filled[i]): 1.0} for i in range(nv)]
nbr = [[j for j, _ in adj[i]] for i in range(nv)]
for _ in range(SMOOTH):
    new = []
    for i in range(nv):
        acc = dict(weights[i]); n = 1
        for j in nbr[i]:
            if part[j] != part[i]: continue
            for k, w in weights[j].items(): acc[k] = acc.get(k, 0.0) + w
            n += 1
        new.append({k: w / n for k, w in acc.items() if w / n > 0.02})
    weights = new
uvA = me.uv_layers["AppUV"].data
# Fresh: triangulating rebuilt the mesh, so earlier layer handles are stale.
ufront, uback = me.uv_layers["uv_front"].data, me.uv_layers["uv_back"].data
R = RES
raster = np.zeros((R, R), np.uint8)
for poly in me.polygons:
    lis = list(poly.loop_indices)
    if len(lis) != 3: continue
    vs = [me.loops[li].vertex_index for li in lis]
    P = np.array([[uvA[li].uv[0] * R, (1 - uvA[li].uv[1]) * R] for li in lis])
    x0, y0 = np.floor(P.min(0)).astype(int); x1, y1 = np.ceil(P.max(0)).astype(int)
    x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, R - 1), min(y1, R - 1)
    if x1 < x0 or y1 < y0: continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = P
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-12: continue
    l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
    l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
    l3 = 1 - l1 - l2
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    if not inside.any(): continue
    bary = (l1[inside], l2[inside], l3[inside])
    cands = set(weights[vs[0]]) | set(weights[vs[1]]) | set(weights[vs[2]])
    best = None; bestv = None
    for k in cands:
        v = sum(bary[t] * weights[vs[t]].get(k, 0.0) for t in range(3))
        if best is None: best, bestv = np.full(v.shape, k), v
        else:
            m = v > bestv; best[m] = k; bestv = np.where(m, v, bestv)
    # Squarely facing: the painting's exact outline.
    sqt = sum(bary[t] * square_v[vs[t]] for t in range(3))
    sq_mask = sqt > 0.75
    if sq_mask.any():
        fac = sum(bary[t] * facing_v[vs[t]] for t in range(3))
        uf = [np.array(ufront[li].uv) for li in lis]; ub = [np.array(uback[li].uv) for li in lis]
        ufx = sum(bary[t] * uf[t][0] for t in range(3)); ufy = sum(bary[t] * uf[t][1] for t in range(3))
        ubx = sum(bary[t] * ub[t][0] for t in range(3)); uby = sum(bary[t] * ub[t][1] for t in range(3))
        def samp(img, u, v):
            x = np.clip((u * 200 * KI).astype(int), 0, IW - 1); y = np.clip(((1 - v) * 400 * KI).astype(int), 0, IH - 1)
            return img[y, x]
        painted = np.where(fac > 0.5, samp(IDF, ufx, ufy), samp(IDB, ubx, uby))
        best = np.where(sq_mask, painted, best)
    yy = (ys[inside] - 0.5).astype(int); xx = (xs[inside] - 0.5).astype(int)
    raster[yy, xx] = best.astype(np.uint8)
np.save(os.path.join(OUTD, "BodyIDs_raster.npy"), raster)
print("RASTER areas", len(np.unique(raster)))
