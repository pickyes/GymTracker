# Body diagram source

`BodyFront.png` / `BodyBack.png` are the anatomical paintings the app's
body-diagram shapes are cut from. They are **not** shipped in the app.

`gen.py` segments the red muscle pixels along the white lines painted
between muscles and writes `regions.json` (every named area's exact
outlines on the 200×400 canvas). Those outlines are pasted into
`muscleSpecs` in `GymTracker/BodyDiagramView.swift`.

Run (needs pillow, numpy, opencv-python-headless):

    python3 gen.py <output-dir>

Left/right are the person's sides: on the front view the person's right
is on the viewer's left.
