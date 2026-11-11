import SwiftUI

/// The body figure, shown as a REAL anatomical muscle image — front and
/// back — with overlays that tint or glow the muscle regions. The body
/// is never drawn in code. The images are the matched pair in the asset
/// catalog (`BodyFront` / `BodyBack`, 1120×2240, red anatomical muscle
/// figure on a white background, no labels, correct human proportions).
///
/// The figure is shown on a white card (the images have white
/// backgrounds, so the card blends with them and reads on both dark and
/// light screens). Every muscle is a tappable overlay region: in the
/// injury diagram it marks a body part; on the workout screen it lights
/// up live for the current exercise's muscles; on the Body screen it is
/// coloured by recovery state from logged history (fresh muscles bright
/// pink, recently trained muscles purple, the rest the image's own red).
///
/// The overlay geometry is on a 200×400 canvas. The images are 1:2
/// (1120×2240), the same aspect as the canvas, so the overlay
/// coordinates map 1:1 onto the image. The coordinates were re-measured
/// off the real images on 2026-11-09 with a grid overlay and verified by
/// rendering the shapes over the images and by a pixel-overlap check:
/// each muscle is a polygon tracing its true outline, so a lit muscle is
/// FILLED solid with the highlight colour, edge to edge, and no two
/// fills touch — a lit chest shows four separate filled muscles (two
/// pecs, two delts), never one merged blob. A tapped / marked muscle
/// LIGHTS UP: bright orange-red fill, a white edge, a tight glow, and a
/// quick spring pop. Lit muscles always match the exercise: the live
/// body lights exactly the muscles the current exercise trains
/// (see MuscleGroup.litGroups), and shows the primary muscle's side
/// first (see LiveBodyView.bestSide).

enum MuscleID: String, CaseIterable, Hashable {
    case head, neck
    case trapLeft, trapRight
    case deltLeft, deltRight
    case pecLeft, pecRight
    case bicepsLeft, bicepsRight
    case tricepsLeft, tricepsRight
    case forearmLeft, forearmRight
    case wristLeft, wristRight
    case abs, obliqueLeft, obliqueRight
    case latLeft, latRight, lowerBack
    case gluteLeft, gluteRight
    case hipLeft, hipRight
    case quadLeft, quadRight
    case hamstringLeft, hamstringRight
    case kneeLeft, kneeRight
    case calfLeft, calfRight
    case ankleLeft, ankleRight
    case footLeft, footRight

    /// Which body part this muscle marks in the injury diagram.
    var bodyPart: BodyPart? {
        switch self {
        case .head, .neck: return .neck
        case .trapLeft, .trapRight, .latLeft, .latRight: return .upperBack
        case .deltLeft: return .shoulderLeft
        case .deltRight: return .shoulderRight
        case .pecLeft, .pecRight: return .chest
        case .bicepsLeft, .tricepsLeft: return .elbowLeft
        case .bicepsRight, .tricepsRight: return .elbowRight
        case .forearmLeft: return .wristLeft
        case .forearmRight: return .wristRight
        case .wristLeft: return .wristLeft
        case .wristRight: return .wristRight
        case .abs, .obliqueLeft, .obliqueRight: return .core
        case .lowerBack: return .lowerBack
        case .gluteLeft, .hipLeft: return .hipLeft
        case .gluteRight, .hipRight: return .hipRight
        case .quadLeft, .hamstringLeft, .kneeLeft: return .kneeLeft
        case .quadRight, .hamstringRight, .kneeRight: return .kneeRight
        case .calfLeft, .ankleLeft, .footLeft: return .ankleLeft
        case .calfRight, .ankleRight, .footRight: return .ankleRight
        }
    }

    /// Which muscle group this shape belongs to (live workout diagram and
    /// the recovery-coloured Body screen).
    var muscleGroup: MuscleGroup? {
        switch self {
        case .pecLeft, .pecRight: return .chest
        case .latLeft, .latRight, .trapLeft, .trapRight, .lowerBack: return .back
        case .deltLeft, .deltRight: return .shoulders
        case .bicepsLeft, .bicepsRight: return .biceps
        case .tricepsLeft, .tricepsRight: return .triceps
        case .forearmLeft, .forearmRight: return .forearms
        case .wristLeft, .wristRight: return .wrists
        case .quadLeft, .quadRight: return .quads
        case .hamstringLeft, .hamstringRight: return .hamstrings
        case .gluteLeft, .gluteRight, .hipLeft, .hipRight: return .glutes
        case .calfLeft, .calfRight: return .calves
        case .abs: return .core
        case .obliqueLeft, .obliqueRight: return .obliques
        case .neck: return .neck
        case .ankleLeft, .ankleRight: return .ankles
        case .footLeft, .footRight: return .feet
        case .head, .kneeLeft, .kneeRight:
            return nil
        }
    }
}

/// Recovery state of one muscle, from the user's own logged history
/// (on-device). Fresh = not trained for 3+ days (or never). Recovering =
/// trained in the last 24–48 hours.
enum MuscleRecovery {
    case fresh
    case recovering
}

/// The muscle groups lit up for one exercise, primary + the muscles that
/// work with it. Only real synergists: a lateral raise lights the delts
/// alone (no chest, no triceps), a pushdown lights the triceps alone —
/// an exercise never lights a muscle it does not train. Compounds keep
/// their synergists (bench press lights chest, shoulders, and triceps;
/// a row lights back, biceps, and forearms; a squat lights quads,
/// glutes, and hamstrings).
extension MuscleGroup {
    var litGroups: [MuscleGroup] {
        switch self {
        case .chest: return [.chest, .shoulders, .triceps]
        case .back: return [.back, .biceps, .forearms]
        case .shoulders: return [.shoulders, .triceps]
        case .biceps: return [.biceps, .forearms]
        case .triceps: return [.triceps]
        case .forearms: return [.forearms, .biceps]
        case .neck: return [.neck]
        case .wrists: return [.wrists]
        case .feet: return [.feet]
        case .ankles: return [.ankles]
        case .quads: return [.quads, .glutes, .hamstrings]
        case .hamstrings: return [.hamstrings, .glutes]
        case .glutes: return [.glutes, .hamstrings, .quads]
        case .calves: return [.calves]
        case .core: return [.core, .obliques]
        case .obliques: return [.obliques, .core]
        case .fullBody: return [.chest, .back, .shoulders, .quads, .glutes, .core]
        }
    }

    /// True when this group is mainly on the back of the body.
    var isBackSide: Bool {
        switch self {
        case .back, .glutes, .hamstrings, .triceps: return true
        default: return false
        }
    }
}

enum BodyDiagramSide: String, CaseIterable {
    case front, back
    var label: String { rawValue.capitalized }
}

/// One muscle's overlay region on the 200×400 canvas.
/// Ellipse center, radii, rotation in degrees.
/// Rounded-rect instead of an ellipse (abs).
/// Polygon instead of an ellipse: a list of canvas points tracing the
/// muscle's true outline in the image, so the highlight FILLS the whole
/// muscle edge to edge instead of sitting as a small oval inside it.
private struct MuscleSpec {
    let id: MuscleID
    let side: BodyDiagramSide
    let cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: CGFloat
    let rect: CGRect?
    let polygon: [CGPoint]?

    init(_ id: MuscleID, _ side: BodyDiagramSide, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: CGFloat = 0) {
        self.id = id; self.side = side
        self.cx = cx; self.cy = cy; self.rx = rx; self.ry = ry; self.rot = rot
        self.rect = nil
        self.polygon = nil
    }

    init(_ id: MuscleID, _ side: BodyDiagramSide, rect: CGRect) {
        self.id = id; self.side = side
        self.cx = rect.midX; self.cy = rect.midY; self.rx = rect.width / 2; self.ry = rect.height / 2; self.rot = 0
        self.rect = rect
        self.polygon = nil
    }

    init(_ id: MuscleID, _ side: BodyDiagramSide, polygon: [CGPoint]) {
        self.id = id; self.side = side
        self.cx = 0; self.cy = 0; self.rx = 0; self.ry = 0; self.rot = 0
        self.rect = nil
        self.polygon = polygon
    }
}

/// Every muscle's overlay region, front and back, traced off the
/// real images on 2026-11-09 (grid-overlay measurement on the 1120×2240
/// images, then verified by rendering the shapes over the images and by
/// a pixel-overlap check over every pair on both sides = NONE).
/// Each muscle is a POLYGON tracing that muscle's true outline in the
/// image, inset ~1.5 canvas units from the edge — so a lit muscle is
/// FILLED solid with the highlight colour, edge to edge, following the
/// muscle's exact shape (DaRon, 2026-11-09: "it needs to highlight and
/// fill the muscle"), while neighbouring fills stay separated by a thin
/// unlit sliver plus their white outlines: never overlapping, never one
/// merged blob. Right side = mirror of left (x -> 200 - x).
/// Small parts (head, neck, hips, knees, wrists, ankles, feet) stay
/// ellipses; abs stays a rounded rect.
/// Coordinates are on a 200×400 canvas, center x = 100 — the same
/// aspect as the images, so the regions land on the muscles in the
/// pictures.
private func mirrorPts(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: 200 - $0.x, y: $0.y) } }

// Traced polygons, left side only (right side = mirrorPts).
private let trapFrontL: [CGPoint] = [CGPoint(x: 90, y: 58), CGPoint(x: 76, y: 64), CGPoint(x: 62, y: 72), CGPoint(x: 59, y: 75), CGPoint(x: 68, y: 78), CGPoint(x: 80, y: 74), CGPoint(x: 90, y: 67)]
private let deltL: [CGPoint] = [CGPoint(x: 63, y: 80), CGPoint(x: 54, y: 78), CGPoint(x: 47, y: 81), CGPoint(x: 44, y: 90), CGPoint(x: 46, y: 100), CGPoint(x: 54, y: 103), CGPoint(x: 60, y: 100), CGPoint(x: 65, y: 92), CGPoint(x: 66, y: 84)]
private let pecL: [CGPoint] = [CGPoint(x: 93, y: 86), CGPoint(x: 84, y: 84), CGPoint(x: 72, y: 86), CGPoint(x: 68, y: 92), CGPoint(x: 67, y: 99), CGPoint(x: 69, y: 106), CGPoint(x: 78, y: 112), CGPoint(x: 88, y: 115), CGPoint(x: 93, y: 112), CGPoint(x: 94, y: 98)]
private let bicL: [CGPoint] = [CGPoint(x: 52, y: 106), CGPoint(x: 46, y: 110), CGPoint(x: 45, y: 124), CGPoint(x: 46, y: 138), CGPoint(x: 50, y: 146), CGPoint(x: 56, y: 144), CGPoint(x: 58, y: 132), CGPoint(x: 57, y: 118), CGPoint(x: 55, y: 108)]
private let foreL: [CGPoint] = [CGPoint(x: 48, y: 154), CGPoint(x: 41, y: 158), CGPoint(x: 40, y: 172), CGPoint(x: 42, y: 186), CGPoint(x: 47, y: 194), CGPoint(x: 52, y: 190), CGPoint(x: 53, y: 174), CGPoint(x: 52, y: 160)]
private let oblL: [CGPoint] = [CGPoint(x: 79, y: 125), CGPoint(x: 71, y: 128), CGPoint(x: 67, y: 142), CGPoint(x: 67, y: 158), CGPoint(x: 71, y: 172), CGPoint(x: 79, y: 177), CGPoint(x: 81, y: 160), CGPoint(x: 81, y: 138)]
private let quadL: [CGPoint] = [CGPoint(x: 81, y: 201), CGPoint(x: 71, y: 204), CGPoint(x: 67, y: 222), CGPoint(x: 67, y: 246), CGPoint(x: 71, y: 265), CGPoint(x: 78, y: 274), CGPoint(x: 90, y: 274), CGPoint(x: 93, y: 260), CGPoint(x: 94, y: 236), CGPoint(x: 93, y: 214), CGPoint(x: 89, y: 202)]
private let calfFrontL: [CGPoint] = [CGPoint(x: 81, y: 297), CGPoint(x: 72, y: 302), CGPoint(x: 70, y: 320), CGPoint(x: 72, y: 338), CGPoint(x: 78, y: 350), CGPoint(x: 88, y: 350), CGPoint(x: 91, y: 336), CGPoint(x: 91, y: 318), CGPoint(x: 88, y: 302)]
private let trapBackL: [CGPoint] = [CGPoint(x: 88, y: 62), CGPoint(x: 76, y: 66), CGPoint(x: 66, y: 75), CGPoint(x: 68, y: 90), CGPoint(x: 78, y: 108), CGPoint(x: 88, y: 126), CGPoint(x: 93, y: 135), CGPoint(x: 94, y: 100), CGPoint(x: 94, y: 72)]
private let triL: [CGPoint] = [CGPoint(x: 51, y: 104), CGPoint(x: 45, y: 108), CGPoint(x: 44, y: 122), CGPoint(x: 45, y: 136), CGPoint(x: 49, y: 146), CGPoint(x: 55, y: 144), CGPoint(x: 57, y: 130), CGPoint(x: 56, y: 116), CGPoint(x: 54, y: 106)]
private let latL: [CGPoint] = [CGPoint(x: 67, y: 106), CGPoint(x: 70, y: 103), CGPoint(x: 80, y: 115), CGPoint(x: 89, y: 130), CGPoint(x: 93, y: 137), CGPoint(x: 93, y: 148), CGPoint(x: 90, y: 160), CGPoint(x: 80, y: 163), CGPoint(x: 72, y: 156), CGPoint(x: 68, y: 132)]
private let lowBackPoly: [CGPoint] = [CGPoint(x: 100, y: 166), CGPoint(x: 109, y: 170), CGPoint(x: 107, y: 178), CGPoint(x: 93, y: 178), CGPoint(x: 91, y: 170)]
private let gluteL: [CGPoint] = [CGPoint(x: 82, y: 184), CGPoint(x: 70, y: 188), CGPoint(x: 65, y: 200), CGPoint(x: 65, y: 214), CGPoint(x: 70, y: 224), CGPoint(x: 82, y: 227), CGPoint(x: 92, y: 226), CGPoint(x: 94, y: 214), CGPoint(x: 94, y: 196), CGPoint(x: 90, y: 186)]
private let hamL: [CGPoint] = [CGPoint(x: 82, y: 230), CGPoint(x: 71, y: 234), CGPoint(x: 68, y: 250), CGPoint(x: 69, y: 266), CGPoint(x: 74, y: 279), CGPoint(x: 88, y: 279), CGPoint(x: 92, y: 266), CGPoint(x: 93, y: 248), CGPoint(x: 92, y: 234)]
private let calfBackL: [CGPoint] = [CGPoint(x: 81, y: 297), CGPoint(x: 70, y: 300), CGPoint(x: 68, y: 312), CGPoint(x: 70, y: 326), CGPoint(x: 78, y: 333), CGPoint(x: 88, y: 333), CGPoint(x: 93, y: 324), CGPoint(x: 93, y: 308), CGPoint(x: 89, y: 299)]
private let muscleSpecs: [MuscleSpec] = [
    // Head + neck (both sides).
    MuscleSpec(.head, .front, cx: 100, cy: 30, rx: 20, ry: 24),
    MuscleSpec(.head, .back, cx: 100, cy: 28, rx: 20, ry: 22),
    MuscleSpec(.neck, .front, cx: 100, cy: 63, rx: 9, ry: 7),
    MuscleSpec(.neck, .back, cx: 100, cy: 59, rx: 11, ry: 8),
    // Traps (both sides — the upper trapezius shows from the front too).
    MuscleSpec(.trapLeft, .front, polygon: trapFrontL),
    MuscleSpec(.trapRight, .front, polygon: mirrorPts(trapFrontL)),
    MuscleSpec(.trapLeft, .back, polygon: trapBackL),
    MuscleSpec(.trapRight, .back, polygon: mirrorPts(trapBackL)),
    // Delts (both sides).
    MuscleSpec(.deltLeft, .front, polygon: deltL),
    MuscleSpec(.deltRight, .front, polygon: mirrorPts(deltL)),
    MuscleSpec(.deltLeft, .back, polygon: deltL),
    MuscleSpec(.deltRight, .back, polygon: mirrorPts(deltL)),
    // Chest (front only).
    MuscleSpec(.pecLeft, .front, polygon: pecL),
    MuscleSpec(.pecRight, .front, polygon: mirrorPts(pecL)),
    // Arms: biceps front, triceps back, forearms both. The arms hang
    // away from the body on the real figure, so the regions sit wide.
    MuscleSpec(.bicepsLeft, .front, polygon: bicL),
    MuscleSpec(.bicepsRight, .front, polygon: mirrorPts(bicL)),
    MuscleSpec(.tricepsLeft, .back, polygon: triL),
    MuscleSpec(.tricepsRight, .back, polygon: mirrorPts(triL)),
    MuscleSpec(.forearmLeft, .front, polygon: foreL),
    MuscleSpec(.forearmRight, .front, polygon: mirrorPts(foreL)),
    MuscleSpec(.forearmLeft, .back, polygon: foreL),
    MuscleSpec(.forearmRight, .back, polygon: mirrorPts(foreL)),
    // Wrists (both sides): a small ellipse on the wrist joint, just below
    // the forearm — the forearm polygon ends at y 194, the ellipse tops
    // at y 195, so the two never touch. Same spot front and back: the
    // arms hang the same way in both images.
    MuscleSpec(.wristLeft, .front, cx: 46, cy: 200, rx: 6, ry: 5),
    MuscleSpec(.wristRight, .front, cx: 154, cy: 200, rx: 6, ry: 5),
    MuscleSpec(.wristLeft, .back, cx: 46, cy: 200, rx: 6, ry: 5),
    MuscleSpec(.wristRight, .back, cx: 154, cy: 200, rx: 6, ry: 5),
    // Core (front only): abs as one rounded rect + obliques.
    MuscleSpec(.abs, .front, rect: CGRect(x: 83, y: 121, width: 34, height: 52)),
    MuscleSpec(.obliqueLeft, .front, polygon: oblL),
    MuscleSpec(.obliqueRight, .front, polygon: mirrorPts(oblL)),
    // Back (back only): lats + lower back + glutes.
    MuscleSpec(.latLeft, .back, polygon: latL),
    MuscleSpec(.latRight, .back, polygon: mirrorPts(latL)),
    MuscleSpec(.lowerBack, .back, polygon: lowBackPoly),
    MuscleSpec(.gluteLeft, .back, polygon: gluteL),
    MuscleSpec(.gluteRight, .back, polygon: mirrorPts(gluteL)),
    // Hips (front only, small — the hip joint).
    MuscleSpec(.hipLeft, .front, cx: 85, cy: 190, rx: 9, ry: 8),
    MuscleSpec(.hipRight, .front, cx: 115, cy: 190, rx: 9, ry: 8),
    // Legs: quads front, hamstrings back, knees/calves/ankles/feet both.
    MuscleSpec(.quadLeft, .front, polygon: quadL),
    MuscleSpec(.quadRight, .front, polygon: mirrorPts(quadL)),
    MuscleSpec(.hamstringLeft, .back, polygon: hamL),
    MuscleSpec(.hamstringRight, .back, polygon: mirrorPts(hamL)),
    MuscleSpec(.kneeLeft, .front, cx: 82, cy: 285, rx: 9, ry: 10),
    MuscleSpec(.kneeRight, .front, cx: 118, cy: 285, rx: 9, ry: 10),
    MuscleSpec(.kneeLeft, .back, cx: 82, cy: 288, rx: 9, ry: 8),
    MuscleSpec(.kneeRight, .back, cx: 118, cy: 288, rx: 9, ry: 8),
    MuscleSpec(.calfLeft, .front, polygon: calfFrontL),
    MuscleSpec(.calfRight, .front, polygon: mirrorPts(calfFrontL)),
    MuscleSpec(.calfLeft, .back, polygon: calfBackL),
    MuscleSpec(.calfRight, .back, polygon: mirrorPts(calfBackL)),
    MuscleSpec(.ankleLeft, .front, cx: 82, cy: 360, rx: 8, ry: 9),
    MuscleSpec(.ankleRight, .front, cx: 118, cy: 360, rx: 8, ry: 9),
    MuscleSpec(.ankleLeft, .back, cx: 82, cy: 360, rx: 8, ry: 9),
    MuscleSpec(.ankleRight, .back, cx: 118, cy: 360, rx: 8, ry: 9),
    MuscleSpec(.footLeft, .front, cx: 82, cy: 381, rx: 10, ry: 11),
    MuscleSpec(.footRight, .front, cx: 118, cy: 381, rx: 10, ry: 11),
    MuscleSpec(.footLeft, .back, cx: 82, cy: 381, rx: 10, ry: 11),
    MuscleSpec(.footRight, .back, cx: 118, cy: 381, rx: 10, ry: 11),
]

/// The anatomical figure itself: the real image on a white card, with a
/// tappable tint/glow overlay over each muscle region. `highlighted` is
/// the set of muscles lit up right now (bright + glow — injury marks, or
/// the live workout muscles). `recovery` colours each muscle by its
/// recovery state from logged history (fresh = bright pink, recovering =
/// purple); the highlight wins over the recovery colour. A muscle with
/// no state shows the image's own red — that is the resting state.
/// `onTap` fires with the muscle tapped (nil = display only). The figure
/// scales to fit its frame; the canvas is 200×400, the same aspect as
/// the images, so the overlays land on the muscles in the pictures.
struct BodyFigureView: View {
    let side: BodyDiagramSide
    var highlighted: Set<MuscleID> = []
    var recovery: [MuscleID: MuscleRecovery] = [:]
    var onTap: ((MuscleID) -> Void)? = nil

    private var imageName: String { side == .front ? "BodyFront" : "BodyBack" }

    /// Overlay palette. The image's own red is the resting state, so
    /// resting muscles get no overlay at all. Fresh = bright pink with a
    /// glow, recovering = purple, lit = bright orange-red with a white
    /// edge, a glow, and a pop.
    private static let freshFill = Color(red: 1.0, green: 0.18, blue: 0.33).opacity(0.55)
    private static let recoveringFill = Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.55)
    private static let litFill = Color(red: 1.0, green: 0.38, blue: 0.08).opacity(0.85)
    private static let litGlow = Color(red: 1.0, green: 0.45, blue: 0.1)
    private static let litStroke = Color.white.opacity(0.9)
    private static let stateStroke = Color.white.opacity(0.35)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 200, proxy.size.height / 400)
            let w = 200 * scale, h = 400 * scale
            ZStack {
                // No card behind the figure: the images are transparent
                // now (white baked into the PNGs was converted to alpha),
                // so the red figure sits directly on the app's own
                // background — true black in dark mode, system background
                // in light mode — with no white box anywhere (DaRon,
                // 21:36: "background of body needs to match").
                ZStack {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    ForEach(muscleSpecs.filter { $0.side == side }, id: \.id) { spec in
                        muscleOverlay(spec, scale: scale)
                    }
                }
                .frame(width: w, height: h)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }

    private func muscleOverlay(_ spec: MuscleSpec, scale: CGFloat) -> some View {
        let lit = highlighted.contains(spec.id)
        let fill: Color?
        if lit {
            fill = Self.litFill
        } else if let state = recovery[spec.id] {
            fill = state == .fresh ? Self.freshFill : Self.recoveringFill
        } else {
            fill = nil
        }
        let shape = overlayPath(spec, scale: scale)
        // A muscle with no state is invisible but still tappable — the
        // tap target is the muscle region itself.
        return Button {
            onTap?(spec.id)
        } label: {
            ZStack {
                if let fill {
                    shape.fill(fill)
                } else {
                    shape.fill(Color.clear)
                }
                if lit {
                    shape.stroke(Self.litStroke, lineWidth: 2)
                } else if fill != nil {
                    shape.stroke(Self.stateStroke, lineWidth: 1)
                }
            }
            // The glow is tight and scales with the figure: a fixed
            // 12pt shadow bled ~10 canvas units past each shape and
            // merged neighbouring glows into one blob. At 3 canvas
            // units the glow still reads as a glow, but two lit
            // muscles stay visibly separate.
            .shadow(color: lit ? Self.litGlow : (fill != nil && recovery[spec.id] == .fresh ? Self.freshFill : .clear),
                    radius: lit ? 3 * scale : (fill != nil ? 2 * scale : 0))
            .scaleEffect(lit ? 1.02 : 1.0)
            .animation(AppAnimation.snappy, value: lit)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(spec.id.accessibilityLabel)
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
    }

    /// The overlay shape for one muscle: a polygon tracing the muscle's
    /// true outline (most muscles), a rounded rect for abs, an ellipse
    /// for the small parts, rotated around its center when needed.
    private func overlayPath(_ spec: MuscleSpec, scale: CGFloat) -> Path {
        let cx = spec.cx * scale, cy = spec.cy * scale
        let rx = spec.rx * scale, ry = spec.ry * scale
        var path: Path
        if let polygon = spec.polygon, polygon.count >= 3 {
            path = Path()
            path.move(to: CGPoint(x: polygon[0].x * scale, y: polygon[0].y * scale))
            for pt in polygon.dropFirst() {
                path.addLine(to: CGPoint(x: pt.x * scale, y: pt.y * scale))
            }
            path.closeSubpath()
            return path
        }
        if let rect = spec.rect {
            path = Path(roundedRect: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                            width: rect.width * scale, height: rect.height * scale),
                        cornerRadius: 8 * scale)
        } else {
            path = Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        if spec.rot != 0 {
            var t = CGAffineTransform(translationX: cx, y: cy)
            t = t.rotated(by: spec.rot * .pi / 180)
            t = t.translatedBy(x: -cx, y: -cy)
            path = path.applying(t)
        }
        return path
    }
}

extension MuscleID {
    var accessibilityLabel: String {
        switch self {
        case .head: return "Head"
        case .neck: return "Neck"
        case .trapLeft: return "Left trapezius"
        case .trapRight: return "Right trapezius"
        case .deltLeft: return "Left shoulder"
        case .deltRight: return "Right shoulder"
        case .pecLeft: return "Left chest"
        case .pecRight: return "Right chest"
        case .bicepsLeft: return "Left biceps"
        case .bicepsRight: return "Right biceps"
        case .tricepsLeft: return "Left triceps"
        case .tricepsRight: return "Right triceps"
        case .forearmLeft: return "Left forearm"
        case .forearmRight: return "Right forearm"
        case .wristLeft: return "Left wrist"
        case .wristRight: return "Right wrist"
        case .abs: return "Abs"
        case .obliqueLeft: return "Left obliques"
        case .obliqueRight: return "Right obliques"
        case .latLeft: return "Left lat"
        case .latRight: return "Right lat"
        case .lowerBack: return "Lower back"
        case .gluteLeft: return "Left glute"
        case .gluteRight: return "Right glute"
        case .hipLeft: return "Left hip"
        case .hipRight: return "Right hip"
        case .quadLeft: return "Left quadriceps"
        case .quadRight: return "Right quadriceps"
        case .hamstringLeft: return "Left hamstring"
        case .hamstringRight: return "Right hamstring"
        case .kneeLeft: return "Left knee"
        case .kneeRight: return "Right knee"
        case .calfLeft: return "Left calf"
        case .calfRight: return "Right calf"
        case .ankleLeft: return "Left ankle"
        case .ankleRight: return "Right ankle"
        case .footLeft: return "Left foot"
        case .footRight: return "Right foot"
        }
    }
}

// MARK: - Injury diagram (setup quiz + Profile)

/// The tappable body for listing injuries. Front/back toggle, tap a
/// muscle to mark its body part (tap again to unmark) — the muscle
/// LIGHTS UP bright and stays lit until tapped again. Marked parts are
/// listed underneath as chips (full names, never cut off); no labels sit
/// on the figure itself.
struct BodyDiagramView: View {
    @Binding var selected: Set<BodyPart>
    @State private var side: BodyDiagramSide = .front

    /// Muscles lit up = every muscle whose body part is marked.
    private var litMuscles: Set<MuscleID> {
        Set(muscleSpecs.filter { spec in
            spec.side == side && spec.id.bodyPart.map { selected.contains($0) } == true
        }.map { $0.id })
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $side) {
                ForEach(BodyDiagramSide.allCases, id: \.self) { side in
                    Text(side.label).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            BodyFigureView(side: side, highlighted: litMuscles) { muscle in
                guard let part = muscle.bodyPart else { return }
                withAnimation(AppAnimation.snappy) {
                    if selected.contains(part) { selected.remove(part) }
                    else { selected.insert(part) }
                }
            }
            .frame(height: 360)
            .animation(AppAnimation.snappy, value: side)

            if !selected.isEmpty {
                markedChips
            } else {
                Text("Tap a muscle to mark it — tap again to unmark.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Marked parts as chips, two per row, full names, tap the × to unmark.
    private var markedChips: some View {
        let parts = selected.sorted { $0.label < $1.label }
        return FlexibleChips(parts) { part in
            HStack(spacing: 6) {
                Text(part.label)
                Button {
                    withAnimation(AppAnimation.snappy) { selected.remove(part) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unmark \(part.label)")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
        }
    }
}

/// Wraps chips into rows (two per row, flexible).
private struct FlexibleChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        // Two columns, wrapping rows.
        let rows = stride(from: 0, to: items.count, by: 2).map { i in
            Array(items[i..<min(i + 2, items.count)])
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }
}

// MARK: - Live workout body (real-time, on the workout screen)

/// The real-time body on the workout screen: it lights up the muscle
/// groups of the CURRENT exercise and flips front/back to show them.
/// `muscle` is the current exercise's muscle; `nextMuscle` is the next
/// exercise's. Display only — not tappable.
/// `figureHeight`: the figure's height. Nil = fill the available height
/// (propped/open layout, where the body should be BIG); a number = a
/// fixed height (compact layout, and the regular detail pane, which
/// scrolls).
struct LiveBodyView: View {
    let muscle: MuscleGroup?
    let nextMuscle: MuscleGroup?
    var figureHeight: CGFloat? = 300
    @State private var side: BodyDiagramSide = .front
    @State private var userFlipped = false

    private var litGroups: [MuscleGroup] {
        muscle?.litGroups ?? []
    }

    private var litMuscles: Set<MuscleID> {
        Set(muscleSpecs.filter { spec in
            spec.side == side && spec.id.muscleGroup.map { litGroups.contains($0) } == true
        }.map { $0.id })
    }

    /// The side that shows the primary muscle first: a row shows the
    /// back, a squat shows the front (quads), a pushdown shows the back
    /// (triceps). Counting synergist groups hid the prime mover — a row
    /// used to open on the front (biceps + forearms outnumber the back
    /// group 2-to-1) and a pushdown opened on the front too, where the
    /// triceps do not even appear. The primary muscle's side wins; the
    /// group count only breaks a tie when the primary straddles sides.
    private var bestSide: BodyDiagramSide {
        if let muscle {
            return muscle.isBackSide ? .back : .front
        }
        let backCount = litGroups.filter { $0.isBackSide }.count
        let frontCount = litGroups.count - backCount
        return backCount > frontCount ? .back : .front
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Working now")
                    .font(.headline)
                Spacer()
                Picker("View", selection: $side) {
                    ForEach(BodyDiagramSide.allCases, id: \.self) { side in
                        Text(side.label).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: side) { _, _ in userFlipped = true }
            }
            BodyFigureView(side: side, highlighted: litMuscles)
                .modifier(LiveBodyFigureHeight(height: figureHeight))
                .animation(AppAnimation.snappy, value: side)
                .animation(AppAnimation.snappy, value: litMuscles)
            if !litGroups.isEmpty {
                Text(litGroups.map { $0.label }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if let nextMuscle, nextMuscle != muscle {
                Text("Next up: \(nextMuscle.label)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear {
            if !userFlipped { side = bestSide }
        }
        .onChange(of: muscle) { _, _ in
            if !userFlipped {
                withAnimation(AppAnimation.snappy) { side = bestSide }
            }
        }
    }
}

/// The live body's figure height: a fixed height, or fill the available
/// height (when `height` is nil, e.g. the propped/open layout where the
/// body should be BIG and use the full pane).
private struct LiveBodyFigureHeight: ViewModifier {
    let height: CGFloat?
    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Body screen (recovery state, Fitbod pattern)

/// The Body screen (History → Body): the real figure, coloured by
/// recovery state from the user's own logged history — fresh muscles
/// (not trained for 3+ days) bright pink, recently trained muscles
/// (last 24–48h) purple, the rest the image's own red. Stats at the top,
/// a rotate button to flip front/back, and tapping a muscle shows which
/// one it is (and lights it up).
struct BodyView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var side: BodyDiagramSide = .front
    @State private var tappedMuscle: MuscleID?

    /// Recovery colour per muscle, from the store's logged history.
    /// The dates are computed once, not per muscle.
    private var recovery: [MuscleID: MuscleRecovery] {
        let dates = store.lastTrainedDates()
        var map: [MuscleID: MuscleRecovery] = [:]
        for spec in muscleSpecs {
            guard let group = spec.id.muscleGroup else { continue }
            map[spec.id] = store.recoveryState(for: group, dates: dates)
        }
        return map
    }

    private var highlighted: Set<MuscleID> {
        tappedMuscle.map { [$0] } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsRow
                legendRow
                BodyFigureView(side: side, highlighted: highlighted, recovery: recovery) { muscle in
                    withAnimation(AppAnimation.snappy) {
                        tappedMuscle = (tappedMuscle == muscle) ? nil : muscle
                    }
                }
                .frame(height: 360)
                .animation(AppAnimation.snappy, value: side)
                if let tappedMuscle {
                    Text(tappedMuscle.accessibilityLabel)
                        .font(.headline)
                    if let group = tappedMuscle.muscleGroup {
                        Text(store.recoveryCaption(for: group))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                rotateButton
            }
            .padding()
        }
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statCard(value: store.daysSinceLastWorkout.map { "\($0)" } ?? "—",
                     label: "DAYS SINCE YOUR LAST WORKOUT")
            statCard(value: "\(store.freshMuscleGroups.count)",
                     label: "FRESH MUSCLE GROUPS")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .bold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .themeCard()
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendDot(color: Color(red: 1.0, green: 0.18, blue: 0.33), label: "Fresh")
            legendDot(color: Color(red: 0.55, green: 0.36, blue: 0.96), label: "Recovering")
            legendDot(color: Color(red: 0.84, green: 0.25, blue: 0.17), label: "Resting")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    private var rotateButton: some View {
        Button {
            withAnimation(AppAnimation.snappy) {
                side = side == .front ? .back : .front
            }
        } label: {
            Label("Rotate — \(side == .front ? "Back" : "Front")", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }
}
