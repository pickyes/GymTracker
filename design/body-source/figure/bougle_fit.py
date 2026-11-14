"""Fits Bouglé's anatomical plates (../bougle) onto the body's painting canvas.

The app's 3D body is mapped through a 200x400 painting canvas (1120x2240 px;
see export_model.py). This replaces that canvas's anatomy with Bouglé's
engraved superficial muscles, fitted to the canvas outline with a thin-plate
spline through matched landmarks, and re-cuts every muscle area along the
real gaps the plates draw between muscles.

Each plate is dissected deeper on one side, so the superficial side is
mirrored across the midline:
  front: the person's left (viewer right); the abs from the other side,
         where the rectus sheath is opened.
  back:  upper body from the viewer's right, hips and legs from the left.
Head, hands and feet keep the old painting (not muscle the app lights).

Writes ../painting/orig_Body{Anatomy,Shade}{Front,Back}.png (the old ones
are kept as old_*), ids_{front,back}.png, and previews in fit_preview/.

    python3 bougle_fit.py      (then extend_edges.py, export_model.py, make_assets.py)
"""
import json, os
import numpy as np, cv2
from skimage.segmentation import watershed

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "bougle")
PAINT = os.path.join(HERE, "..", "painting")
PREV = os.path.join(HERE, "fit_preview"); os.makedirs(PREV, exist_ok=True)
S = 5.6                       # px per canvas unit
CW, CH = 1120, 2240

# --- Which drawing the anatomy comes from: "openstax" (modern, CC BY 4.0,
# default) or "bougle" (1899 engravings, public domain).
PLATES = os.environ.get("PLATES", "openstax")
OS_SRC = os.path.join(HERE, "..", "openstax", "openstax_1105.jpg")

def remove_lines(img):
    """OpenStax prints black label leader lines across the figure."""
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    m = ((hsv[..., 2] < 95) & (hsv[..., 1] < 90)).astype(np.uint8)
    m = cv2.dilate(m, np.ones((5, 5), np.uint8))
    return cv2.inpaint(img, m, 4, cv2.INPAINT_TELEA)

# OpenStax joints (px in each cropped plate). Front: the person's right is
# superficial (viewer's left), so the plate is flipped first; numbers below
# are after the flip (x' = 1303 - x). Back: viewer's right for the upper
# body and thighs, viewer's left (mirrored) for the calves.
OS_FRONT_CROP, OS_BACK_CROP = (0, 1300), (1560, 2900)
OS_FRONT_MID = 691
OS_FRONT_J = {"crown": (691, 30), "chin": (691, 185), "notch": (691, 228), "crotch": (691, 648),
              "shoulder": (823, 280), "elbow": (878, 500), "wrist": (938, 645),
              "hip": (758, 635), "knee": (748, 905), "ankle": (733, 1140)}
OS_FRONT_TORSO = [(0.49, 848), (0.57, 843), (0.65, 838), (0.72, 813), (0.80, 808)]
OS_FRONT_INNER = [((560, 715), (691, 535)), ((585, 522), (728, 350)),
                  ((690, 505), (803, 340)), ((560, 940), (691, 625))]
OS_BACK_MID = 612
OS_BACK_J = {"crown": (612, 30), "chin": (612, 180), "notch": (612, 220), "crotch": (612, 700),
             "shoulder": (770, 325), "elbow": (800, 515), "wrist": (845, 655),
             "hip": (690, 660), "knee": (675, 910), "ankle": (665, 1130)}
OS_BACK_INNER = [((560, 840), (612, 640))]

# --- Joints, read off the plates (px) and the canvas (units, person's left
# = canvas right half). The outline is matched automatically between them
# (edge_pairs): at the same proportion along each limb and down the torso,
# the plate's outline point goes to the canvas's. Plates are used one half
# at a time, with the used half on the right (mirrored where needed).
# The canvas is the 3D body's own straight-on render (render_relief.py):
# joints projected from the skeleton, in canvas units (px / S).
FRAME = json.load(open(os.path.join(HERE, "relief", "frame.json")))
CANVAS = {side: {k: (x / S, y / S) for k, (x, y) in FRAME["joints"][side].items()} for side in ("front", "back")}
# The old painting's joints (units), for carrying the old muscle areas over.
OLD_J = {
    "crown": (100, 4), "chin": (100, 51), "notch": (100, 78), "crotch": (100, 205),
    "shoulder": (144, 92), "elbow": (152.8, 141.8), "wrist": (161.8, 195),
    "hip": (118, 194), "knee": (117.5, 288.7), "ankle": (122.4, 359.6),
}
OLD_J_BACK = dict(OLD_J, notch=(100, 64.6))
# Interior anatomy matched by eye between the body's clay render (canvas px)
# and the plates (px): where the sculpted muscles are.
FRONT_INNER = [((560, 715), (497, 1120)),   # navel
               ((585, 522), (535, 835)),    # pec underline, by the sternum
               ((690, 505), (740, 850)),    # pec underline, outer
               ((560, 940), (497, 1590))]   # top of the pubis
BACK_UPPER_INNER = [((560, 840), (506, 1440))]  # top of the natal cleft
BACK_LEGS_INNER = [((640, 1005), (642, 1720))]  # gluteal fold
FRONT_MID = 495
FRONT_J = {"crown": (495, 31), "chin": (495, 387), "notch": (495, 540), "crotch": (497, 1710),
           "shoulder": (817, 622), "elbow": (833, 1090), "wrist": (890, 1493),
           "hip": (640, 1610), "knee": (630, 2110), "ankle": (630, 2780)}
# The front plate draws the external oblique's tendon sheet nearly paper
# coloured, so its torso edge is given, not cut: (canvas y, plate x) on the
# viewer's right, where the arm hangs clear of the torso.
FRONT_TORSO = [(0.49, 757), (0.57, 757), (0.65, 753), (0.72, 755), (0.80, 762)]  # (notch->crotch t, plate x)
BACK_MID = 506
BACK_UPPER_J = {"crown": (506, 27), "chin": (506, 385), "notch": (506, 440), "crotch": (506, 1560),
                "shoulder": (833, 624), "elbow": (857, 1084), "wrist": (890, 1511),
                "hip": (672, 1520), "knee": (672, 2130), "ankle": (642, 2830)}
# The legs come from the viewer's left of the back plate (mirrored: x' = 2*mid - x).
BACK_LEGS_J = dict(BACK_UPPER_J, hip=(672, 1520), knee=(672, 2130), ankle=(642, 2830))

def plate_mask(img, joints):
    """The figure, cut from the paper: GrabCut seeded with the skeleton."""
    sc = 0.5; sm = cv2.resize(img, None, fx=sc, fy=sc)
    m = np.full(sm.shape[:2], cv2.GC_PR_BGD, np.uint8)
    J = {k: (int(x * sc), int(y * sc)) for k, (x, y) in joints.items()}
    mid = J["crown"][0]
    def mir(p): return (2 * mid - p[0], p[1])
    bones = [("crown", "chin"), ("chin", "notch"), ("notch", "crotch"), ("notch", "shoulder"),
             ("shoulder", "elbow"), ("elbow", "wrist"), ("crotch", "hip"), ("hip", "knee"), ("knee", "ankle")]
    fg = np.zeros_like(m)
    for a, b in bones:
        for f in (lambda p: p, mir):
            cv2.line(fg, f(J[a]), f(J[b]), 1, 9)
    far = cv2.distanceTransform((1 - cv2.dilate(fg, np.ones((3, 3), np.uint8))).astype(np.uint8), cv2.DIST_L2, 5)
    m[far > 70] = cv2.GC_BGD
    m[fg > 0] = cv2.GC_FGD
    bg = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(sm, m, None, bg, fgm, 5, cv2.GC_INIT_WITH_MASK)
    out = ((m == cv2.GC_FGD) | (m == cv2.GC_PR_FGD)).astype(np.uint8)
    out = cv2.morphologyEx(out, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, l, st, _ = cv2.connectedComponentsWithStats(out); out = (l == 1 + np.argmax(st[1:, 4])).astype(np.uint8)
    return cv2.resize(out, (img.shape[1], img.shape[0]), interpolation=cv2.INTER_NEAREST)

def march(mask, p, d, limit):
    """Distance from p along d to where the mask ends (None past limit)."""
    h, w = mask.shape
    for k in range(1, int(limit)):
        x, y = int(p[0] + d[0] * k), int(p[1] + d[1] * k)
        if x < 0 or y < 0 or x >= w or y >= h or not mask[y, x]: return k
    return None

def edge_pairs(cmask, cj, pmask, pj, side_x=1):
    """Matching outline points, canvas px <-> plate px."""
    out = []
    def seg(a, b, ts, lim_c, lim_p, both=True):
        A, B = np.array(cj[a], float) * S, np.array(cj[b], float) * S
        a2, b2 = np.array(pj[a], float), np.array(pj[b], float)
        for t in ts:
            pc, pp = A + (B - A) * t, a2 + (b2 - a2) * t
            dc = (B - A) / np.linalg.norm(B - A); dp = (b2 - a2) / np.linalg.norm(b2 - a2)
            nc, np_ = np.array([-dc[1], dc[0]]), np.array([-dp[1], dp[0]])
            if nc[0] < 0: nc = -nc
            if np_[0] < 0: np_ = -np_
            for sgn in ((1, -1) if both else (1,)):
                kc = march(cmask, pc, nc * sgn, lim_c); kp = march(pmask, pp, np_ * sgn, lim_p)
                if kc and kp: out.append((tuple(pc + nc * sgn * kc), tuple(pp + np_ * sgn * kp)))
    sc = np.linalg.norm(np.array(pj["notch"]) - np.array(pj["crotch"])) / (np.linalg.norm(np.array(cj["notch"]) - np.array(cj["crotch"])) * S)
    seg("shoulder", "elbow", (0.3, 0.55, 0.8), 20 * S, 20 * S * sc)
    seg("elbow", "wrist", (0.25, 0.5, 0.75), 14 * S, 14 * S * sc)
    seg("hip", "knee", (0.2, 0.45, 0.7, 0.9), 26 * S, 26 * S * sc)
    seg("knee", "ankle", (0.15, 0.35, 0.55, 0.75, 0.92), 18 * S, 18 * S * sc)
    # Torso and head: straight out from the midline, only where no arm is
    # alongside (the march would run on into it: rejected by the limit).
    for a, b, ts, lim in (("crown", "chin", (0.25, 0.5, 0.75), 24), ("chin", "notch", (0.5,), 20),
                          ("notch", "crotch", (0.15, 0.3, 0.45, 0.55, 0.65, 0.75, 0.85), 60)):
        A, B = np.array(cj[a], float) * S, np.array(cj[b], float) * S
        a2, b2 = np.array(pj[a], float), np.array(pj[b], float)
        for t in ts:
            pc, pp = A + (B - A) * t, a2 + (b2 - a2) * t
            kc = march(cmask, pc, (1, 0), lim * S); kp = march(pmask, pp, (1, 0), lim * S * sc)
            if kc and kp: out.append(((pc[0] + kc, pc[1]), (pp[0] + kp, pp[1])))
    # Top and outer edge of the shoulder.
    for d in ((0, -1),):  # straight up only: the body's arms are raised
        kc = march(cmask, np.array(cj["shoulder"]) * S, d, 30 * S); kp = march(pmask, np.array(pj["shoulder"], float), d, 30 * S * sc)
        if kc and kp:
            out.append(((cj["shoulder"][0] * S + d[0] * kc, cj["shoulder"][1] * S + d[1] * kc),
                        (pj["shoulder"][0] + d[0] * kp, pj["shoulder"][1] + d[1] * kp)))
    return out

def fit_pairs(cmask, cj, plate, pj, torso=None, inner=()):
    """All matched points for one half: joints, outline, mirrored copies."""
    pmask = plate_mask(plate, pj)
    pairs = [((x * S, y * S), pj[k]) for k, (x, y) in cj.items()]
    if torso:
        # Given torso edge: at proportion t between notch and crotch, the
        # canvas edge <-> plate x. The figure outline includes it.
        n0, c0 = cj["notch"][1], cj["crotch"][1]; pn, pc = pj["notch"][1], pj["crotch"][1]
        poly = [(pj["notch"][0], pn + torso[0][0] * (pc - pn))]
        for t, px in torso:
            py = pn + t * (pc - pn); cy = n0 + t * (c0 - n0)
            kc = march(cmask, np.array([100 * S, cy * S]), (1, 0), 60 * S)
            if kc: pairs.append(((100 * S + kc, cy * S), (px, py)))
            poly.append((px, py))
        poly.append((pj["notch"][0], poly[-1][1]))
        cv2.fillPoly(pmask, [np.array(poly, np.int32)], 1)
        cv2.fillPoly(pmask, [np.array([(2 * pj["notch"][0] - x, y) for x, y in poly], np.int32)], 1)
        lo_y = (n0 + torso[0][0] * (c0 - n0) - 4) * S; hi_y = (n0 + torso[-1][0] * (c0 - n0) + 4) * S
        pairs += [e for e in edge_pairs(cmask, cj, pmask, pj) if not (lo_y < e[0][1] < hi_y and abs(e[0][0] - 100 * S) < 60 * S)]
    else:
        pairs += edge_pairs(cmask, cj, pmask, pj)
    pairs += list(inner)
    mid_c, mid_p = 100 * S, pj["crown"][0]
    mirror = [((2 * mid_c - c[0], c[1]), (2 * mid_p - p[0], p[1])) for c, p in pairs if c[0] > mid_c + 3]
    return pairs + mirror, pmask

def mirrored(pairs, mid):
    out = list(pairs)
    for (cx, cy), (px, py) in pairs:
        if cx > 100.5: out.append(((200 - cx, cy), (2 * mid - px, py)))
    return out

def tps_fit(dst, src):
    """Thin-plate spline taking canvas px (dst) to plate px (src)."""
    d = np.asarray(dst, float); s = np.asarray(src, float)
    keep = []
    for i in range(len(d)):  # one point per spot (duplicates make it singular)
        if all(np.linalg.norm(d[i] - d[j]) > 4 for j in keep): keep.append(i)
    d, s = d[keep], s[keep]; n = len(d)
    r = np.linalg.norm(d[:, None] - d[None], axis=2)
    K = np.where(r > 0, r * r * np.log(r + 1e-12), 0)
    P = np.hstack([np.ones((n, 1)), d])
    # Smoothing: hand-read joints are a few px off.
    A = np.zeros((n + 3, n + 3)); A[:n, :n] = K + np.eye(n) * 2e4; A[:n, n:] = P; A[n:, :n] = P.T
    W = np.linalg.solve(A, np.vstack([s, np.zeros((3, 2))]))
    return d, W

def tps_map(model):
    d, W = model; n = len(d)
    ys, xs = np.mgrid[0:CH, 0:CW].astype(np.float32)
    pts = np.stack([xs.ravel(), ys.ravel()], 1)
    out = W[n] + pts @ W[n + 1:]
    for k in range(0, len(pts), 400000):
        q = pts[k:k + 400000]
        r = np.linalg.norm(q[:, None] - d[None], axis=2)
        U = np.where(r > 0, r * r * np.log(r + 1e-12), 0)
        out[k:k + 400000] += U @ W[:n]
    return out[:, 0].reshape(CH, CW).astype(np.float32), out[:, 1].reshape(CH, CW).astype(np.float32)

def half_widths(mask, A, B, ts, limit):
    """The limb's half-width each side of bone A->B at proportions ts."""
    d = (B - A) / np.linalg.norm(B - A); n = np.array([-d[1], d[0]])
    w = []
    for t in ts:
        p = A + (B - A) * t
        w.append([march(mask, p, n * sg, limit) or limit for sg in (1, -1)])
    w = np.array(w, float)
    med = np.median(w, 0)
    return np.minimum(w, med * 1.5)   # a march that ran into the torso

def bone_map(cmask, cj, pmask, pj, region, seg):
    """Plate coordinates for canvas pixels of a posed limb segment: the same
    proportion along the bone and the same fraction of the limb's width
    across it, so a limb raised on the body takes the plate's hanging limb."""
    a_, b_ = seg
    A, B = np.array(cj[a_], float) * S, np.array(cj[b_], float) * S
    a2, b2 = np.array(pj[a_], float), np.array(pj[b_], float)
    ts = np.linspace(0.05, 0.95, 10)
    sc = np.linalg.norm(b2 - a2) / np.linalg.norm(B - A)
    wc = half_widths(cmask, A, B, ts, 40 * S); wp = half_widths(pmask, a2, b2, ts, 40 * S * sc)
    ys_, xs_ = np.nonzero(region)
    q = np.stack([xs_, ys_], 1).astype(float)
    d = (B - A) / np.linalg.norm(B - A); n = np.array([-d[1], d[0]])
    t = ((q - A) @ d) / np.linalg.norm(B - A); off = (q - A) @ n
    dp = (b2 - a2) / np.linalg.norm(b2 - a2); np_ = np.array([-dp[1], dp[0]])
    tc = np.clip(t, ts[0], ts[-1])
    side = np.where(off >= 0, 0, 1)
    wci = np.where(side == 0, np.interp(tc, ts, wc[:, 0]), np.interp(tc, ts, wc[:, 1]))
    wpi = np.where(side == 0, np.interp(tc, ts, wp[:, 0]), np.interp(tc, ts, wp[:, 1]))
    src = a2 + np.outer(t, b2 - a2) + np.outer(off * wpi / np.maximum(wci, 1), np_)
    return ys_, xs_, src

def warp(plate, pairs, mask=None, arms=None, interp=cv2.INTER_CUBIC):
    """The plate on the canvas. Where the canvas outline reaches past the
    plate's figure (paper would show), a smooth fill is used. `arms`
    (cmask, cj, pmask, pj, side) maps the arms bone by bone instead."""
    dst = [c for c, _ in pairs]; src = [p for _, p in pairs]
    mx, my = tps_map(tps_fit(dst, src))
    if arms is not None:
        cmask, cj, pmask, pj, side = arms
        right = np.zeros(cmask.shape, bool); right[:, CW // 2:] = True
        bm_x, bm_y = mx.copy(), my.copy(); weight = np.zeros(cmask.shape, np.float32)
        for nm, seg in (("upper", ("shoulder", "elbow")), ("fore", ("elbow", "wrist")), ("hand", ("elbow", "wrist"))):
            reg = part_is(side, nm) & right & (cmask > 0)
            reg = cv2.dilate(reg.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool) & right
            if not reg.any(): continue
            yy, xx, sp = bone_map(cmask, cj, pmask, pj, reg, seg)
            bm_x[yy, xx] = sp[:, 0]; bm_y[yy, xx] = sp[:, 1]; weight[yy, xx] = 1
        weight = cv2.GaussianBlur(weight, (0, 0), 5)
        mx = mx * (1 - weight) + bm_x * weight; my = my * (1 - weight) + bm_y * weight
    out = cv2.remap(plate, mx, my, interp, borderMode=cv2.BORDER_REFLECT)
    if mask is not None:
        wm = cv2.remap(mask, mx, my, cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        wm = cv2.erode(wm, np.ones((5, 5), np.uint8))
        if wm.any() and (wm == 0).any():
            _, lab = cv2.distanceTransformWithLabels((wm == 0).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
            src_px = out[wm > 0]; out[wm == 0] = src_px[np.clip(lab[wm == 0] - 1, 0, len(src_px) - 1)]
            # Smoothed, so the fill carries colour, not streaks of the edge.
            soft = cv2.GaussianBlur(out, (0, 0), 14)
            out[wm == 0] = soft[wm == 0]
    return out

def mirror_half(img, right=True):
    """Copies one half of the canvas over the other (about x = 100)."""
    out = img.copy(); h = CW // 2
    if right: out[:, :h] = img[:, h:][:, ::-1]
    else: out[:, h:] = img[:, :h][:, ::-1]
    return out

def remove_fold_bar(img):
    """The front plate has a dark strap across it where its sheets join
    (rows ~1494-1530, sloping slightly). Bridged column by column from the
    rows just above and below it: the thigh fibres there run vertically,
    so they carry straight through (smudge-style inpainting smeared them)."""
    out = img.astype(np.float32).copy(); w = img.shape[1]
    for x in range(w):
        c = int(1510 + 14 * x / w); a, b = c - 19, c + 20
        top = out[a - 3:a, x].mean(0); bot = out[b:b + 3, x].mean(0)
        t = np.linspace(0, 1, b - a)[:, None]
        out[a:b, x] = top * (1 - t) + bot * t
    out = out.astype(np.uint8)
    # A light blur across the bridge only, so columns don't show as stripes.
    band = np.zeros(img.shape[:2], np.uint8)
    for x in range(w):
        c = int(1510 + 14 * x / w); band[c - 21:c + 22, x] = 1
    blur = cv2.GaussianBlur(out, (7, 1), 0)
    out[band > 0] = blur[band > 0]
    return out

def remove_labels(img):
    """The plates print reference numbers on the muscles: small dark
    specks with no fibre direction. Painted out."""
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    bh = cv2.morphologyEx(g, cv2.MORPH_BLACKHAT, np.ones((15, 15), np.uint8))
    m = (bh > 55).astype(np.uint8)
    n, l, st, _ = cv2.connectedComponentsWithStats(m)
    keep = np.zeros_like(m)
    for i in range(1, n):
        w, h, a = st[i, 2], st[i, 3], st[i, 4]
        if a < 220 and max(w, h) < 26 and min(w, h) > 2: keep[l == i] = 1  # compact blobs, not long fibre lines
    keep = cv2.dilate(keep, np.ones((5, 5), np.uint8))
    return cv2.inpaint(img, keep, 5, cv2.INPAINT_TELEA)

# --- Build both sides.
old = {s: cv2.imread(os.path.join(PAINT, f"old_BodyAnatomy{s}.png") if os.path.exists(os.path.join(PAINT, f"old_BodyAnatomy{s}.png"))
                     else os.path.join(PAINT, f"orig_BodyAnatomy{s}.png"), cv2.IMREAD_UNCHANGED) for s in ("Front", "Back")}
for s in ("Front", "Back"):
    for k in ("Anatomy", "Shade"):
        o, keep = os.path.join(PAINT, f"orig_Body{k}{s}.png"), os.path.join(PAINT, f"old_Body{k}{s}.png")
        if not os.path.exists(keep): os.rename(o, keep)
oldshade = {s: cv2.imread(os.path.join(PAINT, f"old_BodyShade{s}.png"), cv2.IMREAD_UNCHANGED) for s in ("Front", "Back")}
names = json.load(open(os.path.join(HERE, "ids.json")))
oldids_src = {}
rows = [l.split("\t") for l in open(os.path.join(HERE, "old_specs.txt")).read().splitlines()]
for side in ("front", "back"):
    img = np.zeros((CH, CW), np.int32)
    for name, sd, data in rows:
        if sd != side: continue
        for outline in data.split(";"):
            pts = [tuple(map(float, p.split(","))) for p in outline.split() if "," in p]
            if len(pts) >= 3: cv2.fillPoly(img, [np.round(np.array(pts) * S).astype(np.int32)], names[name])
    oldids_src[side] = img

ys = np.arange(CH)[:, None] / S
RELIEF = os.path.join(HERE, "relief")
clay = {s: cv2.imread(os.path.join(RELIEF, f"clay_{s}.png"), cv2.IMREAD_UNCHANGED) for s in ("front", "back")}
part = {s: cv2.imread(os.path.join(RELIEF, f"part_{s}.png"))[..., 2].astype(np.float32) / 255 for s in ("front", "back")}
def canvas_mask(side): return (clay[side.lower()][..., 3] > 128).astype(np.uint8)
# Body parts from the render: 1 head, .8 upper arm, .6 forearm, .4 hand, .2 foot.
def part_is(side, *names_):
    v = part[side]; out = np.zeros(v.shape, bool)
    for n in names_:
        c = {"head": 1.0, "upper": 0.8, "fore": 0.6, "hand": 0.4, "foot": 0.2}[n]
        out |= np.abs(v - c) < 0.09
    return out

def warp_ids(src_ids, side):
    """The old muscle areas, carried from the old painting onto the body's
    render by joints and outline (only seeds for the re-cut below)."""
    oj = OLD_J if side == "front" else OLD_J_BACK
    om = (old[side.capitalize()][..., 3] > 128).astype(np.uint8)
    pairs = [((x * S, y * S), (oj[k][0] * S, oj[k][1] * S)) for k, (x, y) in CANVAS[side].items()]
    pairs += edge_pairs(canvas_mask(side), CANVAS[side], om, {k: (x * S, y * S) for k, (x, y) in oj.items()})
    pairs += [((2 * 560 - c[0], c[1]), (2 * 560 - p[0], p[1])) for c, p in pairs if c[0] > 563]
    ojp = {k: (x * S, y * S) for k, (x, y) in oj.items()}
    out = warp(src_ids.astype(np.float32), pairs, None, arms=(canvas_mask(side), CANVAS[side], om, ojp, side), interp=cv2.INTER_NEAREST)
    return np.round(out).astype(np.int32)
for side in ("front", "back"):
    w_ = warp_ids(oldids_src[side], side)
    # Arms were mapped on the right half; the left half mirrors it with each
    # area's left/right swapped.
    swap = {names[k]: names[k.replace('Left', '#').replace('Right', 'Left').replace('#', 'Right')] for k in names}
    lut = np.arange(256); [lut.__setitem__(a_, b_) for a_, b_ in swap.items()]
    mir = lut[np.clip(w_[:, ::-1], 0, 255)]
    w_[:, :CW // 2] = mir[:, :CW // 2]
    oldids_src[side] = w_ * canvas_mask(side)

if PLATES == "openstax":
    whole = remove_lines(cv2.imread(OS_SRC))
    front_plate = whole[OS_FRONT_CROP[0]:OS_FRONT_CROP[1], ::-1].copy()
    back_plate = whole[OS_BACK_CROP[0]:OS_BACK_CROP[1]].copy()
    fp, fmask = fit_pairs(canvas_mask("Front"), CANVAS["front"], front_plate, OS_FRONT_J, OS_FRONT_TORSO, OS_FRONT_INNER)
    front = mirror_half(warp(front_plate, fp, fmask, arms=(canvas_mask('front'), CANVAS['front'], fmask, OS_FRONT_J, 'front')), right=True)
    bp, bmask = fit_pairs(canvas_mask("Back"), CANVAS["back"], back_plate, OS_BACK_J, None, OS_BACK_INNER)
    bu = mirror_half(warp(back_plate, bp, bmask, arms=(canvas_mask('back'), CANVAS['back'], bmask, OS_BACK_J, 'back')), right=True)
    back_mirror_plate = back_plate[:, ::-1].copy()
    BL = {k: (back_plate.shape[1] - 1 - (2 * OS_BACK_MID - x), y) for k, (x, y) in OS_BACK_J.items()}
    BLI = [(c, (back_plate.shape[1] - 1 - (2 * OS_BACK_MID - p[0]), p[1])) for c, p in OS_BACK_INNER]
    blp, blm = fit_pairs(canvas_mask("Back"), CANVAS["back"], back_mirror_plate, BL, None, BLI)
    bl = mirror_half(warp(back_mirror_plate, blp, blm), right=True)
    # Calves from the side where the gastrocnemius is whole.
    ky = CANVAS["back"]["knee"][1] + 4
    t = np.clip((ys - ky) / 10, 0, 1)[..., None]
    back = (bu * (1 - t) + bl * t).astype(np.uint8)
else:
    front_plate = remove_labels(remove_fold_bar(cv2.imread(os.path.join(SRC, "Bougle_whole2.jpg"))))
    back_plate = remove_labels(cv2.imread(os.path.join(SRC, "Bougle_whole5.jpg")))
    fp, fmask = fit_pairs(canvas_mask("Front"), CANVAS["front"], front_plate, FRONT_J, FRONT_TORSO, FRONT_INNER)
    fw = warp(front_plate, fp, fmask, arms=(canvas_mask('front'), CANVAS['front'], fmask, FRONT_J, 'front'))
    front_mirror_plate = front_plate[:, ::-1].copy()
    FJ_M = {k: (front_plate.shape[1] - 1 - (2 * FRONT_MID - x), y) for k, (x, y) in FRONT_J.items()}
    # (the viewer-left half, mirrored onto the right: same joints, x flipped twice)
    FJ_M = {k: (2 * FRONT_MID - x, y) for k, (x, y) in FRONT_J.items()}
    FJ_M = {k: (front_plate.shape[1] - 1 - x, y) for k, (x, y) in FJ_M.items()}
    FT_M = [(t, front_plate.shape[1] - 1 - (2 * FRONT_MID - px)) for t, px in FRONT_TORSO]  # assumed symmetric
    FI_M = [(c, (front_plate.shape[1] - 1 - (2 * FRONT_MID - p[0]), p[1])) for c, p in FRONT_INNER]
    fpm, fmm = fit_pairs(canvas_mask("Front"), CANVAS["front"], front_mirror_plate, FJ_M, FT_M, FI_M)
    fwm = warp(front_mirror_plate, fpm, fmm)
    front = mirror_half(fw, right=True)
    abs_zone = (oldids_src["front"] == names["abs"]).astype(np.uint8)
    abs_zone = cv2.dilate(abs_zone, np.ones((25, 25), np.uint8))
    z = cv2.GaussianBlur(abs_zone.astype(np.float32), (31, 31), 0)[..., None]
    front = mirror_half((front * (1 - z) + mirror_half(fwm, right=True) * z).astype(np.uint8), right=True)

    bp, bmask = fit_pairs(canvas_mask("Back"), CANVAS["back"], back_plate, BACK_UPPER_J, None, BACK_UPPER_INNER)
    bu = mirror_half(warp(back_plate, bp, bmask, arms=(canvas_mask('back'), CANVAS['back'], bmask, BACK_UPPER_J, 'back')), right=True)
    back_mirror_plate = back_plate[:, ::-1].copy()
    BL = {k: (back_plate.shape[1] - 1 - (2 * BACK_MID - x), y) for k, (x, y) in BACK_LEGS_J.items()}
    BLI = [(c, (back_plate.shape[1] - 1 - (2 * BACK_MID - p[0]), p[1])) for c, p in BACK_LEGS_INNER]
    blp, blm = fit_pairs(canvas_mask("Back"), CANVAS["back"], back_mirror_plate, BL, None, BLI)
    bl = mirror_half(warp(back_mirror_plate, blp, blm), right=True)
    wy = (CANVAS['back']['notch'][1] + 0.78 * (CANVAS['back']['crotch'][1] - CANVAS['back']['notch'][1]))
    t = np.clip((ys - wy) / 14, 0, 1)[..., None]
    back = (bu * (1 - t) + bl * t).astype(np.uint8)
for nm, pairs, plate, pm in (("front", fp, front_plate, fmask), ("back", bp, back_plate, bmask)):
    v = plate.copy(); v[pm == 0] = (v[pm == 0] * 0.35).astype(np.uint8)
    for c, p in pairs: cv2.circle(v, (int(p[0]), int(p[1])), 9, (0, 255, 0), -1)
    cv2.imwrite(os.path.join(PREV, f"pairs_{nm}.jpg"), cv2.resize(v, None, fx=0.3, fy=0.3))

def finish(col, side):
    """Grey anatomy + shade on the body's render, inside its outline. Head,
    hands and feet are plain body grey: not muscle the app lights."""
    S_ = side.capitalize(); alpha = clay[side][..., 3]
    lab = cv2.cvtColor(col, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[..., 0] / 255.0
    # Muscle tissue: red (a* well above the plate's tendons and paper),
    # read over a few px so fibre lines don't count as gaps.
    red = cv2.GaussianBlur(np.clip((lab[..., 1] - 132) / 12, 0, 1), (0, 0), 3)
    # Graphite figure: muscle a mid grey with its fibres, tendons and fascia
    # a quieter grey (bright white tendons fought every highlight).
    g = np.clip(red * (0.18 + 0.48 * L ** 1.4) + (1 - red) * (0.30 + 0.14 * L), 0, 1)
    grey = g * 255
    pl = part_is(side, 'head', 'hand', 'foot').astype(np.uint8)
    if side == "front":
        # The plate draws genitals; the body is smooth there. Plain grey.
        cj = CANVAS[side]
        cy = int((cj["crotch"][1] * S + (cj["notch"][1] + 0.83 * (cj["crotch"][1] - cj["notch"][1])) * S) / 2)
        cv2.ellipse(pl, (CW // 2, cy), (62, 70), 0, 0, 360, 1, -1)
    plain = cv2.GaussianBlur(pl.astype(np.float32), (0, 0), 4)
    an = plain * 96 + (1 - plain) * grey
    anat = np.dstack([an, an, an * 1.04, alpha]).clip(0, 255).astype(np.uint8)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(24, 48))
    sh = clahe.apply((L * 255).astype(np.uint8)).astype(np.float32) / 255.0
    m = (alpha > 128) & (red > 0.3)
    lo, hi = np.percentile(sh[m], 3), np.percentile(sh[m], 98)
    sh = np.clip((sh - lo) / (hi - lo), 0, 1) * 255
    sh = plain * 200 + (1 - plain) * sh
    shade = np.dstack([sh, sh, sh, alpha]).clip(0, 255).astype(np.uint8)
    cv2.imwrite(os.path.join(PAINT, f"orig_BodyAnatomy{S_}.png"), anat)
    cv2.imwrite(os.path.join(PAINT, f"orig_BodyShade{S_}.png"), shade)
    return red, L, plain, alpha

for side, col in (("front", front), ("back", back)):
    cv2.imwrite(os.path.join(PREV, f"plate_{side}.jpg"), col)
    red, L, keep_old, alpha = finish(col, side)
    # --- Muscle areas re-cut on the plate: each old area, shrunk to its
    # core, grows over the plate's muscle tissue and stops at the gaps the
    # plate draws between muscles (light fascia, tendons) — watershed.
    ids = oldids_src[side]
    markers = np.zeros_like(ids)
    for i in np.unique(ids):
        if i == 0: continue
        m = (ids == i).astype(np.uint8)
        core = cv2.erode(m, np.ones((13, 13), np.uint8))
        if core.sum() < 30: core = cv2.erode(m, np.ones((5, 5), np.uint8))
        markers[core > 0] = i
    fascia = cv2.GaussianBlur((1 - red) * (0.4 + 0.6 * L), (7, 7), 0)
    inside = alpha > 128
    grown = watershed(fascia, markers, mask=inside)
    # Areas may only grow a little past their old outline (the plate and the
    # old painting differ in proportion, not in which muscle is where).
    near = np.zeros_like(ids)
    for i in np.unique(ids):
        if i == 0: continue
        reach = cv2.dilate((ids == i).astype(np.uint8), np.ones((71, 71), np.uint8))
        near[(reach > 0) & (grown == i)] = i
    new = near.copy()
    # Tendon and fascia (the plate's pale areas) are gaps: not lit. Only
    # real ones: smoothed, and specks too small to be anatomy are dropped.
    gap = ((cv2.GaussianBlur(red, (0, 0), 4) < 0.3) & (keep_old < 0.5)).astype(np.uint8)
    gap = cv2.morphologyEx(gap, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, l, st, _ = cv2.connectedComponentsWithStats(gap)
    for k in range(1, n):
        if st[k, 4] < 900: gap[l == k] = 0
    new[gap > 0] = 0
    # Holes left inside an area take that area.
    for k in np.unique(new):
        if k == 0: continue
        m = (new == k).astype(np.uint8)
        filled = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
        new[(filled > 0) & (new == 0) & (gap == 0)] = k
    # Joints/head/hands/feet keep their old shapes.
    for n in ("head", "handLeft", "handRight", "footLeft", "footRight", "wristLeft", "wristRight",
              "elbowLeft", "elbowRight", "kneeLeft", "kneeRight", "ankleLeft", "ankleRight"):
        new[new == names[n]] = 0; new[ids == names[n]] = names[n]
    # Head, hands and feet exactly as the body's own parts.
    pv_ = part[side]; right = np.zeros_like(new, bool); right[:, CW // 2:] = True
    near_side = "Left" if side == "front" else "Right"     # the viewer's right half
    far_side = "Right" if side == "front" else "Left"
    new[part_is(side, "head")] = names["head"]
    new[(keep_old > 0.5) & ~part_is(side, "head", "hand", "foot")] = names["groin"]
    hand = part_is(side, "hand"); foot = part_is(side, "foot")
    new[hand & right] = names["hand" + near_side]; new[hand & ~right] = names["hand" + far_side]
    new[foot & right] = names["foot" + near_side]; new[foot & ~right] = names["foot" + far_side]
    new = cv2.medianBlur(new.astype(np.uint8), 5)
    out = (new * 4).astype(np.uint8)
    cv2.imwrite(os.path.join(HERE, f"ids_{side}.png"), cv2.merge([out, out, out]))
    # Previews: fitted plate with the old outline, and the new areas.
    edge = cv2.Canny(canvas_mask(side) * 255, 50, 150)
    pv = col.copy(); pv[edge > 0] = (0, 255, 0)
    rng = np.random.RandomState(4); pal = rng.randint(50, 255, (256, 3)).astype(np.uint8); pal[0] = 0
    sh = cv2.imread(os.path.join(PAINT, f"orig_BodyShade{side.capitalize()}.png"))
    area = (pal[new].astype(np.float32) * (0.35 + 0.65 * sh / 255.0)).astype(np.uint8)
    cv2.imwrite(os.path.join(PREV, f"fit_{side}.jpg"), cv2.resize(np.hstack([pv, area]), None, fx=0.4, fy=0.4))
print("done")
