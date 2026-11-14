"""Extends the paintings and muscle areas out past the figure's outline.

The 3D body wraps the front painting round the front and the back one
round the back; at the flanks both are sampled near or past their painted
edge, which left a dark stripe down the sides. Here each painting is
grown outward (inpainted, made opaque), and each muscle area is grown into
the empty band along the outline, so the seam lands on paint and muscle.

    python3 extend_edges.py      (then export_model.py, make_assets.py)
"""
import os, numpy as np, cv2
HERE = os.path.dirname(os.path.abspath(__file__)); P = os.path.join(HERE, "..", "painting")
BAND = 70  # px at 1120x2240
for side in ("Front", "Back"):
    a = cv2.imread(os.path.join(P, f"BodyAnatomy{side}.png"), cv2.IMREAD_UNCHANGED)
    if not os.path.exists(os.path.join(P, f"orig_BodyAnatomy{side}.png")):
        for k in ("Anatomy", "Shade"):
            os.rename(os.path.join(P, f"Body{k}{side}.png"), os.path.join(P, f"orig_Body{k}{side}.png"))
    inside = cv2.imread(os.path.join(P, f"orig_BodyAnatomy{side}.png"), cv2.IMREAD_UNCHANGED)[..., 3] > 128
    out_dist = cv2.distanceTransform((~inside).astype(np.uint8), cv2.DIST_L2, 5)
    grow = (~inside) & (out_dist < BAND)
    for k in ("Anatomy", "Shade"):
        im = cv2.imread(os.path.join(P, f"orig_Body{k}{side}.png"), cv2.IMREAD_UNCHANGED)
        if im.ndim == 2: im = cv2.cvtColor(im, cv2.COLOR_GRAY2BGRA)
        if im.shape[2] == 3: im = cv2.cvtColor(im, cv2.COLOR_BGR2BGRA)
        # Nearest painted pixel, so the edge colour carries straight out.
        _, lab = cv2.distanceTransformWithLabels((~inside).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
        src = im[inside]
        fill = src[np.clip(lab[grow] - 1, 0, len(src) - 1)]
        im[grow] = fill; im[grow, 3] = 255
        # Smoothed: nearest-pixel growth drew streaks that showed on the
        # 3D body's flanks.
        soft = cv2.GaussianBlur(im, (0, 0), 14)
        im[grow] = soft[grow]; im[grow, 3] = 255
        if side == "Back":
            # The back of the head: the painting's two dark ovals read as
            # eyes on the 3D head. Painted out to the skull's own grey.
            head = np.zeros(im.shape[:2], np.uint8); head[: int(50 * 5.6)] = 1
            lum = im[..., :3].mean(2)
            ref = np.median(lum[(head > 0) & inside])
            dark = ((head > 0) & inside & (lum < ref * 0.8)).astype(np.uint8)
            dark = cv2.dilate(dark, np.ones((9, 9), np.uint8))
            im[..., :3] = cv2.inpaint(np.ascontiguousarray(im[..., :3]), dark, 12, cv2.INPAINT_TELEA)
        cv2.imwrite(os.path.join(P, f"Body{k}{side}.png"), im)
    # Muscle areas: empty pixels in the outer band (inside or just outside
    # the outline) take the nearest area; inner gaps between muscles stay.
    ids = cv2.imread(os.path.join(HERE, f"ids_{side.lower()}.png"))[..., 0]
    in_dist = cv2.distanceTransform(inside.astype(np.uint8), cv2.DIST_L2, 5)
    band = (ids == 0) & ((~inside & (out_dist < BAND)) | (inside & (in_dist < 26)))
    _, lab = cv2.distanceTransformWithLabels((ids == 0).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    vals = ids[ids != 0]
    ids[band] = vals[np.clip(lab[band] - 1, 0, len(vals) - 1)]
    cv2.imwrite(os.path.join(HERE, f"ids_{side.lower()}.png"), cv2.merge([ids, ids, ids]))
    print(side, "grown", int(grow.sum()), "px; areas grown", int(band.sum()), "px")
