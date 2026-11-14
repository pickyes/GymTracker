# 3D body figure (Nov 14)

The app's body is the unisex MetaHuman (from the exercise-video work),
wrapped in the same anatomy painting the flat figure used, so every muscle
area matches the old outlines (and the injury/recovery logic built on them).

Run in order (Python: opencv-python-headless, pillow, numpy; Blender 5.3):

1. `python3 make_ids.py` — muscle area maps from the old outlines (old_specs.txt)
2. `python3 extend_edges.py` — grow paintings and areas past the outline (no flank seam)
3. `Blender -b --python export_model.py` — decimate to 60k tris, bake colour/shade/IDs, write model/
4. `python3 make_assets.py` — pack model/ into Assets.xcassets (BodyModel/Color/Shade/IDs data sets)

`MH_EXPORT` points at the MetaHuman FBX export (default: the exercise-videos
worktree). If ids.json order changes, update `BodyModel.areas` in
BodyDiagramView.swift (make_assets.py prints the line).

render_figure.py / cut_regions.py made a flat front/back version of the same
body; kept for reference, not used by the app.
