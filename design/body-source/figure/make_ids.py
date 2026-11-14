"""Muscle ID maps from the old painted outlines (old_specs.txt, 200x400 canvas).

Each area is filled with its own index (red channel) at the painting's
1120x2240 resolution; the gaps between areas stay 0. render_figure.py
wraps these onto the MetaHuman exactly like the painting, so every muscle
lands where the painting put it.

    python3 make_ids.py
"""
import json, os
import numpy as np, cv2

HERE = os.path.dirname(os.path.abspath(__file__))
S = 5.6  # px per canvas unit (1120 / 200)
rows = [l.split("\t") for l in open(os.path.join(HERE, "old_specs.txt")).read().splitlines()]
names = sorted({r[0] for r in rows})
index = {n: i + 1 for i, n in enumerate(names)}
for side in ("front", "back"):
    img = np.zeros((2240, 1120), np.uint8)
    for name, sd, data in rows:
        if sd != side: continue
        for outline in data.split(";"):
            pts = [tuple(map(float, p.split(","))) for p in outline.split() if "," in p]
            if len(pts) < 3: continue
            cv2.fillPoly(img, [np.round(np.array(pts) * S).astype(np.int32)], index[name] * 4)
    # Stored as index x 4 so 8-bit rounding can never change an area.
    # Same-colour RGB so Blender reads the index back from any channel.
    cv2.imwrite(os.path.join(HERE, f"ids_{side}.png"), cv2.merge([img, img, img]))
json.dump(index, open(os.path.join(HERE, "ids.json"), "w"), indent=1)
print(len(index), "areas")
