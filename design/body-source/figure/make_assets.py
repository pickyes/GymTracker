"""Packs model/ into the app's asset catalog as data assets (no image
processing by Xcode, so the ID values survive exactly).

    python3 make_assets.py
"""
import json, os, struct, zlib
import numpy as np, cv2
HERE = os.path.dirname(os.path.abspath(__file__))
CAT = os.path.join(HERE, "..", "..", "..", "GymTracker", "Assets.xcassets")
M = os.path.join(HERE, "model")
def dataset(name, filename, data):
    d = os.path.join(CAT, name + ".dataset"); os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        if f != "Contents.json": os.remove(os.path.join(d, f))
    open(os.path.join(d, filename), "wb").write(data)
    json.dump({"data": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)
dataset("BodyModel", "BodyModel.bin", open(os.path.join(M, "BodyModel.bin"), "rb").read())
dataset("BodyColor", "BodyColor.png", open(os.path.join(M, "BodyColor.png"), "rb").read())
dataset("BodyShade", "BodyShade.png", open(os.path.join(M, "BodyShade.png"), "rb").read())
ids = cv2.imread(os.path.join(M, "BodyIDs.png"))[..., 2].astype(int)
# Texels blended at a border (not a multiple of 4) take the nearest clean
# area, so lit muscles have clean edges instead of dark specks.
bad = (ids % 4) != 0
_, lab = cv2.distanceTransformWithLabels(bad.astype(np.uint8), cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
good = ids[~bad]; ids[bad] = good[np.clip(lab[bad] - 1, 0, len(good) - 1)]
ids = (ids // 4).astype(np.uint8)
h, w = ids.shape
c = zlib.compressobj(9, zlib.DEFLATED, -15); raw = c.compress(ids.tobytes()) + c.flush()
dataset("BodyIDs", "BodyIDs.bin", struct.pack("<II", w, h) + raw)
names = {v: k for k, v in json.load(open(os.path.join(HERE, "ids.json"))).items()}
print("let bodyModelAreas: [MuscleID?] = [nil, " + ", ".join("." + names[i] for i in range(1, max(names) + 1)) + "]")
print("ids", w, h, len(raw), "bytes")
