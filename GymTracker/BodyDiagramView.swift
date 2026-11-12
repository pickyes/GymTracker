import SwiftUI

/// The body figure, shown as a REAL anatomical muscle image — front and
/// back — with overlays that tint or glow the muscle regions. The body
/// is never drawn in code. The images are the matched pair in the asset
/// catalog (`BodyFront` / `BodyBack`, 1120×2240, red anatomical muscle
/// figure on a TRANSPARENT background — the white baked into the
/// generated PNGs was converted to alpha by body-images/
/// make_transparent.py, and the converted RGBA files are what the
/// catalog holds. MUST STAY RGBA: putting the RGB white-background
/// originals back in the catalog re-opens DaRon's 2026-11-10 defect
/// ("background of the body needs to match") — a white box exactly the
/// figure's frame on the true-black theme (seen in rerun-shot 212).
/// No card sits behind the figure anywhere: the transparent image lets
/// the app's own background show through — true black #000000 in dark
/// mode (Theme.background), system background in light mode — on every
/// surface that shows the body (Today open-pose pane, Body screen,
/// rest-day recovery view, injury diagram). Every muscle is a tappable
/// overlay region: in the injury diagram it marks a body part; on the
/// workout screen it lights up live for the current exercise's muscles; on the Body screen it is
/// coloured by recovery state from logged history (fresh muscles bright
/// pink, recently trained muscles purple, the rest the image's own red).
///
/// The overlay geometry is on a 200×400 canvas. The images are 1:2
/// (1120×2240), the same aspect as the canvas, so the overlay
/// coordinates map 1:1 onto the image. The polygons were re-derived
/// off the real images on 2026-11-10 (interior-red segmentation of the
/// 1120×2240 images, row-wise envelope trace, Douglas–Peucker
/// simplification, then hand-checked seam lines where two muscles meet
/// with no drawn boundary — deltopectoral groove, posterior-delt /
/// triceps border, gluteal fold). The 2026-11-09 polygons were wrong:
/// they painted white background and fascia and were replaced, not
/// nudged. Measured on the new set: 0% of any polygon's area falls on
/// pure-white background (old set: up to 14%), and pairwise overlap
/// between neighbouring polygons on the same side is ≤0.6% (shared
/// borders only). Each muscle is a polygon tracing its true outline, so
/// a lit muscle is FILLED solid with the highlight colour, edge to
/// edge. A tapped / marked muscle LIGHTS UP: bright orange-red fill, a
/// white edge, a tight glow, and a quick spring pop. Lit muscles always
/// match the exercise: the live body lights exactly the muscles the
/// current exercise trains (see LibraryExercise.trainedMuscles, the
/// single source of truth shared with exercise detail, program,
/// recovery, and stretches), and shows the primary muscle's side first
/// (see LiveBodyView.bestSide).

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
/// (on-device). Fresh = not trained for longer than the muscle's
/// recovery window (large muscles ~72 h, small muscles ~48 h — the
/// shared `MuscleGroup.recoveryHours` rule). Recovering = trained
/// within that window.
enum MuscleRecovery {
    case fresh
    case recovering
}

/// Which muscles an exercise trains is NOT decided here — it lives in
/// `LibraryExercise.trainedMuscles` (ExerciseLibrary.swift), the single
/// source of truth shared by exercise detail, program, recovery, and
/// stretches. The diagram reads it through `LiveBodyView` (which takes
/// the exercise id). The old per-group table that used to live here
/// (`litGroups`) was deleted on 2026-11-10: it duplicated that model
/// and was wrong for isolation moves (a lateral raise lit triceps, a
/// cable fly lit shoulders + triceps).
extension MuscleGroup {
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

/// Every muscle's overlay region, front and back, re-derived off the
/// real images on 2026-11-10 (see the file header for the method and
/// the measured results: 0% white-background spill, ≤0.6% pairwise
/// overlap). Each muscle is a POLYGON tracing that muscle's true
/// outline in the image, EDGE TO EDGE — so a lit muscle is FILLED
/// solid with the highlight colour, following the muscle's exact shape
/// (DaRon, 2026-11-09: "it needs to highlight and fill the muscle" and
/// "highlighted parts needs to go edge to egde"). Neighbouring fills
/// meet at their shared border — the white outlines drawn in the image
/// itself keep two lit muscles visibly separate, never one merged blob.
/// Right side = mirror of left (x -> 200 - x).
/// Small parts (head, neck, hips, knees, wrists, ankles, feet) stay
/// ellipses; abs is an oval polygon following the white lines.
/// Coordinates are on a 200×400 canvas, center x = 100 — the same
/// aspect as the images, so the regions land on the muscles in the
/// pictures.
/// There is NO lower-back polygon: the lumbar diamond in the back
/// image is fascia, not muscle — no red muscle exists there — so the
/// old hexagon (which painted fascia orange) was deleted. The lats
/// flank the spine down to the diamond and the glutes start at the
/// fold below it, so back exercises still cover the area.
/// `MuscleID.lowerBack` keeps its body-part mapping so a tap target
/// can be added later if wanted.
private func mirrorPts(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: 200 - $0.x, y: $0.y) } }

// Traced polygons, left side only (right side = mirrorPts).
private let trapFrontL: [CGPoint] = [CGPoint(x: 85.7, y: 50.7), CGPoint(x: 86.2, y: 61.4), CGPoint(x: 85, y: 63.6), CGPoint(x: 75, y: 69.3), CGPoint(x: 64.3, y: 73.6), CGPoint(x: 73.2, y: 76.4), CGPoint(x: 90.7, y: 76.4), CGPoint(x: 89.5, y: 68.6), CGPoint(x: 92.7, y: 65.7), CGPoint(x: 92.7, y: 64.3), CGPoint(x: 86.6, y: 50.7)]
private let deltL: [CGPoint] = [CGPoint(x: 60.9, y: 75.4), CGPoint(x: 55.5, y: 76.1), CGPoint(x: 50, y: 79.6), CGPoint(x: 44.3, y: 90.4), CGPoint(x: 43.4, y: 94.6), CGPoint(x: 47, y: 95.4), CGPoint(x: 48.4, y: 96.8), CGPoint(x: 50, y: 106.8), CGPoint(x: 50.9, y: 106.8), CGPoint(x: 56.1, y: 98.2), CGPoint(x: 59.9, y: 94.6), CGPoint(x: 59.3, y: 93.2), CGPoint(x: 59.6, y: 91.8), CGPoint(x: 71.8, y: 79.6), CGPoint(x: 71.8, y: 77.5), CGPoint(x: 67.1, y: 75.4)]
private let deltBackL: [CGPoint] = [CGPoint(x: 54.1, y: 75.2), CGPoint(x: 50.2, y: 78), CGPoint(x: 45.5, y: 85.9), CGPoint(x: 43.2, y: 94.5), CGPoint(x: 43.4, y: 101.6), CGPoint(x: 44.5, y: 105.9), CGPoint(x: 60.2, y: 101.8), CGPoint(x: 61.1, y: 101.6), CGPoint(x: 66.6, y: 99.9), CGPoint(x: 61.3, y: 95.2), CGPoint(x: 61.3, y: 93.8), CGPoint(x: 65.4, y: 90.9), CGPoint(x: 64.1, y: 87.3), CGPoint(x: 65.5, y: 83), CGPoint(x: 64.3, y: 81.6), CGPoint(x: 54.8, y: 78.8), CGPoint(x: 54.1, y: 75.2)]
private let pecL: [CGPoint] = [CGPoint(x: 91.4, y: 71.2), CGPoint(x: 93.8, y: 77.7), CGPoint(x: 75, y: 78.4), CGPoint(x: 65.5, y: 87.7), CGPoint(x: 56.8, y: 99.1), CGPoint(x: 60.5, y: 100.5), CGPoint(x: 70.7, y: 113.4), CGPoint(x: 78.4, y: 119.8), CGPoint(x: 80.2, y: 122.7), CGPoint(x: 86.4, y: 122.7), CGPoint(x: 82.7, y: 120.5), CGPoint(x: 92.5, y: 116.3), CGPoint(x: 96.1, y: 112), CGPoint(x: 97.1, y: 104.8), CGPoint(x: 97, y: 93.4), CGPoint(x: 93.9, y: 79.8), CGPoint(x: 84.8, y: 78.4), CGPoint(x: 97, y: 77.7), CGPoint(x: 95.2, y: 71.2)]
private let bicL: [CGPoint] = [CGPoint(x: 43.6, y: 105.4), CGPoint(x: 45, y: 111.1), CGPoint(x: 42.5, y: 118.9), CGPoint(x: 42.1, y: 125.4), CGPoint(x: 43.2, y: 128.9), CGPoint(x: 44.5, y: 129.6), CGPoint(x: 44.3, y: 137.5), CGPoint(x: 45.7, y: 143.9), CGPoint(x: 49.1, y: 149.6), CGPoint(x: 50.4, y: 149.6), CGPoint(x: 50.2, y: 147.5), CGPoint(x: 53.8, y: 145.4), CGPoint(x: 56.6, y: 139.6), CGPoint(x: 59.3, y: 130.4), CGPoint(x: 63, y: 129.6), CGPoint(x: 65.9, y: 126.8), CGPoint(x: 63.8, y: 105.4)]
private let foreL: [CGPoint] = [CGPoint(x: 39.6, y: 146.1), CGPoint(x: 38.6, y: 150.4), CGPoint(x: 38.8, y: 178.9), CGPoint(x: 45.5, y: 181.1), CGPoint(x: 45.4, y: 183.9), CGPoint(x: 41.4, y: 188.9), CGPoint(x: 39.8, y: 193.9), CGPoint(x: 40.5, y: 193.9), CGPoint(x: 41.6, y: 188.9), CGPoint(x: 50.7, y: 183.9), CGPoint(x: 54.8, y: 173.9), CGPoint(x: 57.1, y: 162.5), CGPoint(x: 56.8, y: 160.4), CGPoint(x: 53.4, y: 159.6), CGPoint(x: 52.7, y: 156.1), CGPoint(x: 46.8, y: 155.4), CGPoint(x: 44.8, y: 146.1)]
private let foreBackL: [CGPoint] = [CGPoint(x: 41.1, y: 154.3), CGPoint(x: 37.1, y: 162.1), CGPoint(x: 35.9, y: 169.3), CGPoint(x: 35.9, y: 175.7), CGPoint(x: 37.7, y: 177.1), CGPoint(x: 38.4, y: 193.6), CGPoint(x: 47, y: 193.6), CGPoint(x: 47, y: 185.7), CGPoint(x: 48.8, y: 185), CGPoint(x: 54.1, y: 175), CGPoint(x: 57.3, y: 158.6), CGPoint(x: 40.9, y: 156.4), CGPoint(x: 41.1, y: 154.3)]
private let oblL: [CGPoint] = [CGPoint(x: 66.6, y: 120), CGPoint(x: 68, y: 150.7), CGPoint(x: 67, y: 170), CGPoint(x: 68.4, y: 174.3), CGPoint(x: 73, y: 180), CGPoint(x: 79.5, y: 180), CGPoint(x: 82.5, y: 175.7), CGPoint(x: 83.2, y: 170.7), CGPoint(x: 81.6, y: 155), CGPoint(x: 82.5, y: 137.1), CGPoint(x: 81.4, y: 134.3), CGPoint(x: 85.9, y: 123.6), CGPoint(x: 68.4, y: 120)]
private let quadL: [CGPoint] = [CGPoint(x: 66.8, y: 180.2), CGPoint(x: 62, y: 196.6), CGPoint(x: 61.3, y: 203), CGPoint(x: 61.1, y: 221.6), CGPoint(x: 63.2, y: 223), CGPoint(x: 62.5, y: 244.5), CGPoint(x: 64.6, y: 260.2), CGPoint(x: 68.4, y: 273), CGPoint(x: 70.5, y: 274.5), CGPoint(x: 82, y: 275.2), CGPoint(x: 83.8, y: 280.2), CGPoint(x: 90.5, y: 281.6), CGPoint(x: 90.7, y: 288.8), CGPoint(x: 91.1, y: 288.8), CGPoint(x: 93.4, y: 276.6), CGPoint(x: 93.4, y: 260.2), CGPoint(x: 94.8, y: 255.9), CGPoint(x: 97.1, y: 237.3), CGPoint(x: 97.7, y: 210.2), CGPoint(x: 92.9, y: 208.8), CGPoint(x: 92.7, y: 203), CGPoint(x: 82.1, y: 193.8), CGPoint(x: 75.4, y: 193), CGPoint(x: 70.4, y: 180.2)]
private let calfFrontL: [CGPoint] = [CGPoint(x: 74.3, y: 296.1), CGPoint(x: 72.5, y: 296.8), CGPoint(x: 72, y: 299.6), CGPoint(x: 69.6, y: 301.8), CGPoint(x: 69.1, y: 313.2), CGPoint(x: 69.6, y: 326.1), CGPoint(x: 73.9, y: 349.6), CGPoint(x: 85.9, y: 349.6), CGPoint(x: 88.6, y: 329.6), CGPoint(x: 90, y: 327.5), CGPoint(x: 91.2, y: 321.1), CGPoint(x: 89.5, y: 303.2), CGPoint(x: 88.9, y: 301.1), CGPoint(x: 76.4, y: 300.4), CGPoint(x: 75.2, y: 296.1)]
private let trapBackL: [CGPoint] = [CGPoint(x: 85.5, y: 47.9), CGPoint(x: 85.7, y: 60), CGPoint(x: 77.5, y: 66.4), CGPoint(x: 64.3, y: 72.1), CGPoint(x: 67, y: 75), CGPoint(x: 80, y: 81.4), CGPoint(x: 80, y: 82.9), CGPoint(x: 65.4, y: 84.3), CGPoint(x: 64.3, y: 87.9), CGPoint(x: 66.2, y: 91.4), CGPoint(x: 62.5, y: 95), CGPoint(x: 76.6, y: 110), CGPoint(x: 79.1, y: 110.7), CGPoint(x: 79.1, y: 112.1), CGPoint(x: 81.6, y: 115), CGPoint(x: 81.8, y: 120), CGPoint(x: 86.1, y: 124.3), CGPoint(x: 92.9, y: 125), CGPoint(x: 96.6, y: 131.4), CGPoint(x: 96.8, y: 131.4), CGPoint(x: 97.3, y: 95), CGPoint(x: 95.9, y: 84.3), CGPoint(x: 94.3, y: 82.1), CGPoint(x: 91.1, y: 81.4), CGPoint(x: 91.2, y: 78.6), CGPoint(x: 92.5, y: 77.1), CGPoint(x: 91.2, y: 75.7), CGPoint(x: 91.4, y: 72.9), CGPoint(x: 94.8, y: 62.9), CGPoint(x: 86.8, y: 56.4), CGPoint(x: 87, y: 54.3), CGPoint(x: 89.8, y: 52.9), CGPoint(x: 88, y: 50), CGPoint(x: 88, y: 47.9)]
private let triL: [CGPoint] = [CGPoint(x: 57.3, y: 102.7), CGPoint(x: 51.4, y: 104.5), CGPoint(x: 46.4, y: 107.1), CGPoint(x: 44.1, y: 112.1), CGPoint(x: 42.5, y: 120.7), CGPoint(x: 42.9, y: 136.4), CGPoint(x: 44.8, y: 145.7), CGPoint(x: 47.3, y: 150), CGPoint(x: 53, y: 151.4), CGPoint(x: 53.9, y: 151.4), CGPoint(x: 60.4, y: 135), CGPoint(x: 61.8, y: 127.1), CGPoint(x: 57.3, y: 102.7)]
private let latL: [CGPoint] = [CGPoint(x: 66.8, y: 100.2), CGPoint(x: 59.6, y: 108), CGPoint(x: 59.6, y: 109.5), CGPoint(x: 63.4, y: 129.5), CGPoint(x: 68.2, y: 143), CGPoint(x: 68.6, y: 152.3), CGPoint(x: 67, y: 170.2), CGPoint(x: 77.9, y: 173), CGPoint(x: 78.4, y: 173), CGPoint(x: 82.9, y: 166.6), CGPoint(x: 83.6, y: 157.3), CGPoint(x: 93.4, y: 140.2), CGPoint(x: 95.2, y: 132.3), CGPoint(x: 92, y: 125.2), CGPoint(x: 86.1, y: 124.5), CGPoint(x: 81.8, y: 120.2), CGPoint(x: 81.1, y: 114.5), CGPoint(x: 78.9, y: 111.6), CGPoint(x: 75.5, y: 110.9), CGPoint(x: 67.5, y: 100.2)]
// Abs: an oval polygon following the white linea semilunaris on each
// side, from the sternum (y 123) to the pubis (y 182).
private let absPoly: [CGPoint] = [CGPoint(x: 89.5, y: 122.7), CGPoint(x: 86.1, y: 128.4), CGPoint(x: 84.6, y: 134.1), CGPoint(x: 84.6, y: 135.5), CGPoint(x: 86.2, y: 136.2), CGPoint(x: 84.8, y: 143.4), CGPoint(x: 86.6, y: 147.7), CGPoint(x: 85.7, y: 150.5), CGPoint(x: 85.9, y: 158.4), CGPoint(x: 87.3, y: 163.4), CGPoint(x: 86.4, y: 170.5), CGPoint(x: 88.4, y: 182), CGPoint(x: 111.6, y: 182), CGPoint(x: 113.6, y: 172.7), CGPoint(x: 112.7, y: 163.4), CGPoint(x: 113.9, y: 159.1), CGPoint(x: 114.1, y: 149.8), CGPoint(x: 113.2, y: 147.7), CGPoint(x: 115, y: 144.1), CGPoint(x: 113.6, y: 136.2), CGPoint(x: 115.4, y: 134.8), CGPoint(x: 114.1, y: 129.1), CGPoint(x: 111.1, y: 122.7)]
private let gluteL: [CGPoint] = [CGPoint(x: 68.2, y: 174.3), CGPoint(x: 65.9, y: 175), CGPoint(x: 65, y: 182.1), CGPoint(x: 65.2, y: 197.1), CGPoint(x: 67.7, y: 197.9), CGPoint(x: 66.1, y: 204.3), CGPoint(x: 67.1, y: 222.1), CGPoint(x: 68.2, y: 225.7), CGPoint(x: 69.5, y: 226.4), CGPoint(x: 80.7, y: 227.9), CGPoint(x: 94.6, y: 227.9), CGPoint(x: 93.4, y: 215.7), CGPoint(x: 98, y: 210), CGPoint(x: 97.3, y: 192.9), CGPoint(x: 94.3, y: 187.1), CGPoint(x: 76.2, y: 174.3)]
private let hamL: [CGPoint] = [CGPoint(x: 72.3, y: 228), CGPoint(x: 68.8, y: 243.8), CGPoint(x: 70.9, y: 274.5), CGPoint(x: 77.3, y: 277.3), CGPoint(x: 79.8, y: 281.6), CGPoint(x: 82.5, y: 281.6), CGPoint(x: 81.8, y: 278), CGPoint(x: 88, y: 277.3), CGPoint(x: 89.8, y: 275.2), CGPoint(x: 91.1, y: 269.5), CGPoint(x: 93.8, y: 268.8), CGPoint(x: 95, y: 250.2), CGPoint(x: 94.8, y: 230.9), CGPoint(x: 90.2, y: 230.2), CGPoint(x: 88.8, y: 228)]
private let calfBackL: [CGPoint] = [CGPoint(x: 72.9, y: 290), CGPoint(x: 70.5, y: 290.7), CGPoint(x: 67.9, y: 302.9), CGPoint(x: 66.4, y: 314.3), CGPoint(x: 66.8, y: 321.4), CGPoint(x: 70.5, y: 330.7), CGPoint(x: 72.1, y: 332.1), CGPoint(x: 82.5, y: 332.9), CGPoint(x: 83.4, y: 338.6), CGPoint(x: 87.3, y: 338.6), CGPoint(x: 87.3, y: 333.6), CGPoint(x: 90.9, y: 323.6), CGPoint(x: 91.1, y: 315.7), CGPoint(x: 88.6, y: 300), CGPoint(x: 87, y: 297.1), CGPoint(x: 83.4, y: 296.4), CGPoint(x: 83.2, y: 290)]
private let muscleSpecs: [MuscleSpec] = [
    // Head + neck (both sides).
    MuscleSpec(.head, .front, cx: 100, cy: 29, rx: 21, ry: 25),
    MuscleSpec(.head, .back, cx: 100, cy: 28, rx: 21, ry: 23),
    MuscleSpec(.neck, .front, cx: 100, cy: 62, rx: 9, ry: 8),
    MuscleSpec(.neck, .back, cx: 100, cy: 59, rx: 11, ry: 8),
    // Traps (both sides — the upper trapezius shows from the front too).
    MuscleSpec(.trapLeft, .front, polygon: trapFrontL),
    MuscleSpec(.trapRight, .front, polygon: mirrorPts(trapFrontL)),
    MuscleSpec(.trapLeft, .back, polygon: trapBackL),
    MuscleSpec(.trapRight, .back, polygon: mirrorPts(trapBackL)),
    // Delts (both sides).
    MuscleSpec(.deltLeft, .front, polygon: deltL),
    MuscleSpec(.deltRight, .front, polygon: mirrorPts(deltL)),
    MuscleSpec(.deltLeft, .back, polygon: deltBackL),
    MuscleSpec(.deltRight, .back, polygon: mirrorPts(deltBackL)),
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
    MuscleSpec(.forearmLeft, .back, polygon: foreBackL),
    MuscleSpec(.forearmRight, .back, polygon: mirrorPts(foreBackL)),
    // Wrists (both sides): a small ellipse on the wrist joint, just below
    // the forearm — the forearm polygon ends at y 194 and the ellipse
    // tops at y 194, so the two meet at the wrist joint without ever
    // overlapping. Same spot front and back: the arms hang the same way
    // in both images.
    MuscleSpec(.wristLeft, .front, cx: 46, cy: 200, rx: 7, ry: 6),
    MuscleSpec(.wristRight, .front, cx: 154, cy: 200, rx: 7, ry: 6),
    MuscleSpec(.wristLeft, .back, cx: 46, cy: 200, rx: 7, ry: 6),
    MuscleSpec(.wristRight, .back, cx: 154, cy: 200, rx: 7, ry: 6),
    // Core (front only): abs as a trapezoid following the white lines +
    // obliques.
    MuscleSpec(.abs, .front, polygon: absPoly),
    MuscleSpec(.obliqueLeft, .front, polygon: oblL),
    MuscleSpec(.obliqueRight, .front, polygon: mirrorPts(oblL)),
    // Back (back only): lats + glutes.
    MuscleSpec(.latLeft, .back, polygon: latL),
    MuscleSpec(.latRight, .back, polygon: mirrorPts(latL)),
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
    MuscleSpec(.kneeLeft, .front, cx: 82, cy: 285, rx: 10, ry: 10),
    MuscleSpec(.kneeRight, .front, cx: 118, cy: 285, rx: 10, ry: 10),
    MuscleSpec(.kneeLeft, .back, cx: 82, cy: 288, rx: 10, ry: 9),
    MuscleSpec(.kneeRight, .back, cx: 118, cy: 288, rx: 10, ry: 9),
    MuscleSpec(.calfLeft, .front, polygon: calfFrontL),
    MuscleSpec(.calfRight, .front, polygon: mirrorPts(calfFrontL)),
    MuscleSpec(.calfLeft, .back, polygon: calfBackL),
    MuscleSpec(.calfRight, .back, polygon: mirrorPts(calfBackL)),
    MuscleSpec(.ankleLeft, .front, cx: 82, cy: 360, rx: 9, ry: 10),
    MuscleSpec(.ankleRight, .front, cx: 118, cy: 360, rx: 9, ry: 10),
    MuscleSpec(.ankleLeft, .back, cx: 82, cy: 360, rx: 9, ry: 10),
    MuscleSpec(.ankleRight, .back, cx: 118, cy: 360, rx: 9, ry: 10),
    MuscleSpec(.footLeft, .front, cx: 82, cy: 381, rx: 11, ry: 11),
    MuscleSpec(.footRight, .front, cx: 118, cy: 381, rx: 11, ry: 11),
    MuscleSpec(.footLeft, .back, cx: 82, cy: 381, rx: 11, ry: 11),
    MuscleSpec(.footRight, .back, cx: 118, cy: 381, rx: 11, ry: 11),
]

/// The anatomical figure itself: the real image (transparent
/// background — it sits directly on Theme.background, true black in
/// dark mode, system background in light mode, with no card or panel
/// behind it), with a tappable tint/glow overlay over each muscle region. `highlighted` is
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
    /// glow AND a dashed white outline, so fresh is never color-only
    /// (colorblind-safe); recovering = purple, lit = bright orange-red
    /// with a white edge, a glow, and a pop.
    private static let freshFill = Color(red: 1.0, green: 0.18, blue: 0.33).opacity(0.90)
    private static let recoveringFill = Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.55)
    private static let litFill = Color(red: 1.0, green: 0.38, blue: 0.08).opacity(0.85)
    private static let litGlow = Color(red: 1.0, green: 0.45, blue: 0.1)
    private static let litStroke = Color.white.opacity(0.9)
    private static let stateStroke = Color.white.opacity(0.35)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 200, proxy.size.height / 400)
            let w = 200 * scale, h = 400 * scale
            // The outer ZStack is given the full proxy size so its
            // bounds contain the positioned figure (a positioned child
            // contributes no size to its parent, so without this frame
            // the outer ZStack would be 0x0 — harmless for rendering
            // but it would put the figure outside the parent's bounds
            // for hit-testing). NOTE: this frame alone did NOT fix the
            // taps (build #6 still failed) — the actual defect was the
            // tap-location coordinate space, fixed in the gesture
            // below. Kept because the sizing is still correct.
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
                // Tap handling (2026-11-10): a SINGLE tap-location
                // handler on the figure, NOT one Button per muscle.
                // Per-muscle Buttons never received taps on screen
                // (verified: shoulder x2 + abs x1 on build #4 marked
                // nothing, while the highlight renders in the right
                // place and the Front/Back picker in the same view
                // works). The container converts the tap to canvas
                // coordinates and hit-tests the muscle polygons in
                // code, topmost first. Gated on onTap so display-only
                // figures (workout, Body screen) get no gesture at all.
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // The tap location arrives in the GEOMETRYREADER's
                    // (proxy) coordinate space, NOT the figure's local
                    // space — verified from the console on build #7:
                    // a dead-centre abs tap reported location
                    // (458.7, 136.3) in a 919x360 proxy, i.e. the
                    // figure's centre, while the figure itself is only
                    // 180x360. Dividing by scale alone gave canvas
                    // (509.6, 151.5) — off the 200x400 canvas entirely —
                    // so every tap reported "no polygon hit". Subtract
                    // the figure's origin in proxy space first: the
                    // figure is centred, so origin = (proxy - size)/2.
                    let origin = CGPoint(x: (proxy.size.width - w) / 2,
                                         y: (proxy.size.height - h) / 2)
                    let canvas = CGPoint(x: (location.x - origin.x) / scale,
                                         y: (location.y - origin.y) / scale)
                    guard let onTap else { return }
                    for spec in muscleSpecs.filter({ $0.side == side }).reversed() {
                        if overlayPath(spec, scale: 1.0).contains(canvas) {
                            onTap(spec.id)
                            return
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        // The overlay is a PLAIN view, not a Button: touch goes to
        // the figure's single tap-location handler (see BodyFigureView
        // body). Per-muscle Buttons never received taps on screen.
        // VoiceOver still gets a per-muscle button via the
        // accessibilityAction below, which is independent of touch
        // hit-testing.
        return ZStack {
            // Each shape view carries the FULL-canvas frame: a bare
            // Path sizes to its own bounding rect, and the ZStack
            // would center that rect on the canvas center (see the
            // note on the Button above). With the full frame the Path
            // draws at its true canvas coordinates.
            ZStack {
                shape
                    .fill(fill ?? Color.clear)
                    .frame(width: 200 * scale, height: 400 * scale)
                if lit {
                    shape.stroke(Self.litStroke, lineWidth: 2)
                        .frame(width: 200 * scale, height: 400 * scale)
                } else if recovery[spec.id] == .fresh {
                    // Fresh is never color-only: a dashed white outline
                    // marks it as well as the pink fill (colorblind-safe).
                    shape.stroke(Color.white.opacity(0.9),
                                 style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 200 * scale, height: 400 * scale)
                } else if fill != nil {
                    shape.stroke(Self.stateStroke, lineWidth: 1)
                        .frame(width: 200 * scale, height: 400 * scale)
                }
            }
            // The glow is tight and scales with the figure: a fixed
            // 12pt shadow bled ~10 canvas units past each shape and
            // merged neighbouring glows into one blob. At 3 canvas
            // units the glow still reads as a glow, but two lit
            // muscles stay visibly separate. Fresh gets the full glow
            // too, matching the lit glow.
            .shadow(color: lit ? Self.litGlow : (recovery[spec.id] == .fresh ? Self.freshFill : .clear),
                    radius: (lit || recovery[spec.id] == .fresh) ? 3 * scale : 0)
            .scaleEffect(lit ? 1.02 : 1.0)
            .animation(AppAnimation.snappy, value: lit)
        }
        .accessibilityLabel(spec.id.accessibilityLabel)
        .accessibilityValue(freshnessValue(for: spec))
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onTap?(spec.id) }
    }

    /// VoiceOver freshness state for one muscle. Empty when the figure
    /// carries no recovery data (injury diagram, live workout), so
    /// nothing misleading is announced there.
    private func freshnessValue(for spec: MuscleSpec) -> String {
        switch recovery[spec.id] {
        case .fresh: return "Fresh"
        case .recovering: return "Recovering"
        case .none: return ""
        }
    }

    /// The overlay shape for one muscle: a polygon tracing the muscle's
    /// true outline (most muscles, abs included), an ellipse for the
    /// small parts, rotated around its center when needed.
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
/// `exerciseID` is the current exercise's library id; `nextExerciseID`
/// is the next exercise's. The muscles lit are the exercise's
/// `trainedMuscles` from `ExerciseLibrary` — the single source of truth
/// shared with exercise detail, program, recovery, and stretches —
/// never a diagram-local table. `muscle` / `nextMuscle` are fallbacks
/// for callers that only know a muscle group (primary only). Display
/// only — not tappable.
/// `figureHeight`: the figure's height. Nil = fill the available height
/// (propped/open layout, where the body should be BIG); a number = a
/// fixed height (compact layout, and the regular detail pane, which
/// scrolls).
struct LiveBodyView: View {
    // `var`, not `let`: a `let` with a default value is left OUT of the
    // synthesized memberwise initializer, so call sites could not pass
    // `exerciseID:` / `nextExerciseID:` at all (Xcode 27.2 build failure
    // 2026-11-10: "Extra arguments at positions #1, #2 in call"). These
    // are still inputs only — the view never writes them.
    var exerciseID: String? = nil
    var nextExerciseID: String? = nil
    var muscle: MuscleGroup? = nil
    var nextMuscle: MuscleGroup? = nil
    var figureHeight: CGFloat? = 300
    /// Optional hoisted side/flip (TodayView passes its own — Debug Pass
    /// 2, fold glitch): LiveBodyView is rebuilt per Today layout, so
    /// @State here alone would snap the figure back to the auto side on
    /// every fold. When the bindings are supplied, Today owns the values
    /// and this view restores them on appear and writes changes back;
    /// when nil (standalone uses) the local @State owns them as before.
    var sideBinding: Binding<BodyDiagramSide>? = nil
    var userFlippedBinding: Binding<Bool>? = nil
    @EnvironmentObject var store: WorkoutStore
    @State private var side: BodyDiagramSide = .front
    @State private var userFlipped = false

    /// The exercise (library or custom) for the current id, if it resolves.
    private var resolvedExercise: LibraryExercise? {
        exerciseID.flatMap { ExerciseLibrary.byId($0, plus: store.customExercises) }
    }

    /// The next exercise, if it resolves.
    private var resolvedNextExercise: LibraryExercise? {
        nextExerciseID.flatMap { ExerciseLibrary.byId($0, plus: store.customExercises) }
    }

    /// The primary muscle of the current exercise (resolved, else fallback).
    private var primaryMuscle: MuscleGroup? {
        resolvedExercise?.muscle ?? muscle
    }

    /// The primary muscle of the next exercise (resolved, else fallback).
    private var nextPrimaryMuscle: MuscleGroup? {
        resolvedNextExercise?.muscle ?? nextMuscle
    }

    /// The muscle groups lit for the current exercise: its
    /// `trainedMuscles` (primary + secondaries) when it resolves, else
    /// the fallback primary alone.
    private var litGroups: [MuscleGroup] {
        resolvedExercise?.trainedMuscles ?? (muscle.map { [$0] } ?? [])
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
        if let primaryMuscle {
            return primaryMuscle.isBackSide ? .back : .front
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
            if let nextPrimaryMuscle, nextPrimaryMuscle != primaryMuscle {
                Text("Next up: \(nextPrimaryMuscle.label)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear {
            // Restore a user-chosen flip from the hoisted state BEFORE
            // the auto-side logic below runs, so a fold never snaps the
            // figure back to the auto side. Runs first: onAppear
            // modifiers fire in attachment order, and this one is
            // attached before the auto-side one.
            if userFlippedBinding?.wrappedValue == true, let sideBinding {
                side = sideBinding.wrappedValue
                userFlipped = true
            }
        }
        .onAppear {
            if !userFlipped { side = bestSide }
        }
        .onChange(of: exerciseID) { _, _ in
            if !userFlipped {
                withAnimation(AppAnimation.snappy) { side = bestSide }
            }
        }
        .onChange(of: muscle) { _, _ in
            if !userFlipped {
                withAnimation(AppAnimation.snappy) { side = bestSide }
            }
        }
        // Write-through: a side/flip change here updates the hoisted
        // state, so the next layout instance restores it instead of
        // re-deriving it. (No loop: writing the binding re-renders with
        // the same values, which fires no further change.)
        .onChange(of: side) { _, newValue in
            sideBinding?.wrappedValue = newValue
        }
        .onChange(of: userFlipped) { _, newValue in
            userFlippedBinding?.wrappedValue = newValue
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
/// (not trained within the muscle's recovery window: ~72 h large,
/// ~48 h small) bright pink, recently trained muscles purple, the
/// rest the image's own red. Stats at the top,
/// a rotate button to flip front/back, and tapping a muscle shows which
/// one it is (and lights it up).
struct BodyView: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                // D15 (2026-11-10): 360pt capped the figure at 180 wide
                // in the wide open-pose pane. Regular width gets 520pt
                // (figure 260 wide, +44%) while still fitting with the
                // stats/legend/Rotate button; compact stays 360pt.
                .frame(height: horizontalSizeClass == .regular ? 520 : 360)
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
            // Same 16pt sides/top as before; the bottom is the shared
            // LayoutClearance rule (Debug Pass 2) so the Rotate button
            // scrolls clear of the floating menu button — and of the
            // rest-timer panel while a rest runs. The old uniform 16pt
            // padding left it under the button at scroll-bottom.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive))
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
            legendDot(color: Color(red: 1.0, green: 0.18, blue: 0.33), label: "Fresh", dashedRing: true)
            legendDot(color: Color(red: 0.55, green: 0.36, blue: 0.96), label: "Recovering")
            legendDot(color: Color(red: 0.84, green: 0.25, blue: 0.17), label: "Resting")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
    }

    private func legendDot(color: Color, label: String, dashedRing: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay {
                    // Fresh is never color-only: the legend swatch
                    // carries the same dashed ring as the figure.
                    if dashedRing {
                        Circle().stroke(Color.white, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
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
