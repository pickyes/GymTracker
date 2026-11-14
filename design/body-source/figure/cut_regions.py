"""Muscle outlines for the MetaHuman figure, cut from the ID renders.

render/ids_<side>.png holds each area's index x 4 (see make_ids.py). Every
area is cleaned (slivers dropped, holes filled, pulled in a hair so
neighbours keep a gap) and traced into outlines on the app's canvas:
400 units tall, as wide as the render (render/size.json).

Writes:
  regions.swift            MuscleSpec lines for BodyDiagramView.swift
  BodyFigure<Side>.png     the grey figure (base image)
  BodyFigureShade<Side>.png  its light/dark, normalised, for the tint

    python3 cut_regions.py
"""
import json, os
import numpy as np, cv2

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(HERE, "render")
size = json.load(open(os.path.join(R, "size.json")))
W, H = size["width"], size["height"]
K = 400.0 / H                      # canvas units per pixel
names = {v: k for k, v in json.load(open(os.path.join(HERE, "ids.json"))).items()}
old_order = []
for line in open(os.path.join(HERE, "old_specs.txt")).read().splitlines():
    n, sd, _ = line.split("\t")
    if (n, sd) not in old_order: old_order.append((n, sd))

MIN_AREA = 120                     # px; smaller specks are mapping noise
out = []
for side in ("front", "back"):
    ids = cv2.imread(os.path.join(R, f"ids_{side}.png"), cv2.IMREAD_UNCHANGED)
    idx = np.round(ids[..., 0].astype(float) / 4).astype(int)
    idx[ids[..., 3] < 128] = 0
    regions = {}
    for i in sorted(set(np.unique(idx)) - {0}):
        if i not in names: continue
        m = (idx == i).astype(np.uint8)
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
        keep = np.zeros_like(m)
        for c in range(1, n):
            if st[c, 4] >= MIN_AREA: keep[lab == c] = 1
        keep = cv2.erode(keep, np.ones((3, 3), np.uint8))   # an even gap to neighbours
        cs, _ = cv2.findContours(keep, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        polys = []
        for c in cs:
            if cv2.contourArea(c) < MIN_AREA * 0.6: continue
            c = cv2.approxPolyDP(c, 1.2, True).reshape(-1, 2)
            if len(c) < 3: continue
            polys.append(" ".join(f"{x * K:.2f},{y * K:.2f}" for x, y in c))
        if polys: regions[names[i]] = ";".join(polys)
    for n, sd in old_order:
        if sd == side and n in regions:
            out.append(f'    MuscleSpec(.{n}, .{side}, "{regions[n]}"),')
    missing = sorted({n for n, sd in old_order if sd == side} - set(regions))
    print(side, len(regions), "areas", "missing:", missing)

    cap = side.capitalize()
    base = cv2.imread(os.path.join(R, f"anatomy_{side}.png"), cv2.IMREAD_UNCHANGED)
    cv2.imwrite(os.path.join(HERE, f"BodyFigure{cap}.png"), base)
    shade = cv2.imread(os.path.join(R, f"shade_{side}.png"), cv2.IMREAD_UNCHANGED)
    rgb = shade[..., :3].astype(float); a = shade[..., 3] > 0
    top = np.percentile(rgb[a].mean(1), 97) if a.any() else 255
    rgb = np.clip(rgb * (255.0 / max(top, 1)), 0, 255)
    shade[..., :3] = rgb.astype(np.uint8)
    cv2.imwrite(os.path.join(HERE, f"BodyFigureShade{cap}.png"), shade)

open(os.path.join(HERE, "regions.swift"), "w").write("\n".join(out) + "\n")
print("canvas", round(W * K, 2), "x 400")
