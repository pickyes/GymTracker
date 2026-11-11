import SwiftUI

/// One consistent icon for every piece of equipment. Same size (28pt),
/// same line-icon style, same stroke — SF Symbols where they exist, and
/// a custom line drawing in the same style for the rest. No photos, no
/// mixed styles, no different sizes.
struct EquipmentIcon: View {
    let equipment: Equipment

    var body: some View {
        Group {
            if let symbol = equipment.sfSymbolName {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
            } else {
                EquipmentLineIcon(equipment: equipment)
            }
        }
        .frame(width: 28, height: 28)
        .foregroundStyle(.primary)
    }
}

extension Equipment {
    /// SF Symbol name where one exists for this equipment, nil otherwise.
    /// Only dumbbell and bodyweight have a real SF Symbol; everything
    /// else is drawn by `EquipmentLineIcon` in the same line style.
    var sfSymbolName: String? {
        switch self {
        case .dumbbell: return "dumbbell"
        case .bodyweight: return "person.fill"
        default: return nil
        }
    }
}

/// Custom line icons, drawn in code to match the SF Symbol look:
/// stroke-based, 2pt line, rounded caps and joins, one color, 28×28.
private struct EquipmentLineIcon: View {
    let equipment: Equipment

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 28.0
            Path { path in
                draw(&path)
            }
            .stroke(Color.primary, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
            .frame(width: 28 * s, height: 28 * s)
        }
        .frame(width: 28, height: 28)
    }

    private func draw(_ p: inout Path) {
        switch equipment {
        case .barbell:
            // Horizontal bar, plates at both ends.
            p.move(to: CGPoint(x: 3, y: 14)); p.addLine(to: CGPoint(x: 25, y: 14))
            p.addRoundedRect(in: CGRect(x: 5, y: 8, width: 3, height: 12), cornerSize: CGSize(width: 1, height: 1))
            p.addRoundedRect(in: CGRect(x: 20, y: 8, width: 3, height: 12), cornerSize: CGSize(width: 1, height: 1))
        case .squatRack:
            // Two uprights, a top bar, feet.
            p.move(to: CGPoint(x: 7, y: 4)); p.addLine(to: CGPoint(x: 7, y: 24))
            p.move(to: CGPoint(x: 21, y: 4)); p.addLine(to: CGPoint(x: 21, y: 24))
            p.move(to: CGPoint(x: 4, y: 7)); p.addLine(to: CGPoint(x: 24, y: 7))
            p.move(to: CGPoint(x: 7, y: 18)); p.addLine(to: CGPoint(x: 21, y: 18))
            p.move(to: CGPoint(x: 4, y: 24)); p.addLine(to: CGPoint(x: 10, y: 24))
            p.move(to: CGPoint(x: 18, y: 24)); p.addLine(to: CGPoint(x: 24, y: 24))
        case .bench:
            // Flat bench: top pad + two legs.
            p.move(to: CGPoint(x: 3, y: 11)); p.addLine(to: CGPoint(x: 25, y: 11))
            p.move(to: CGPoint(x: 8, y: 11)); p.addLine(to: CGPoint(x: 8, y: 23))
            p.move(to: CGPoint(x: 20, y: 11)); p.addLine(to: CGPoint(x: 20, y: 23))
            p.move(to: CGPoint(x: 5, y: 23)); p.addLine(to: CGPoint(x: 11, y: 23))
            p.move(to: CGPoint(x: 17, y: 23)); p.addLine(to: CGPoint(x: 23, y: 23))
        case .cable:
            // Cable tower: upright, pulley, cable down to a handle.
            p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 5, height: 20), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addEllipse(in: CGRect(x: 17, y: 5, width: 6, height: 6))
            p.move(to: CGPoint(x: 20, y: 11)); p.addLine(to: CGPoint(x: 20, y: 19))
            p.move(to: CGPoint(x: 17, y: 19)); p.addLine(to: CGPoint(x: 23, y: 19))
        case .bands:
            // A looped resistance band.
            p.addEllipse(in: CGRect(x: 8, y: 4, width: 12, height: 20))
            p.move(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 14, y: 10))
        case .kettlebell:
            // Bell + handle.
            p.addEllipse(in: CGRect(x: 8, y: 13, width: 12, height: 11))
            p.move(to: CGPoint(x: 9, y: 14))
            p.addCurve(to: CGPoint(x: 19, y: 14), control1: CGPoint(x: 9, y: 4), control2: CGPoint(x: 19, y: 4))
        case .pullUpBar:
            // Overhead bar on two supports.
            p.move(to: CGPoint(x: 3, y: 7)); p.addLine(to: CGPoint(x: 25, y: 7))
            p.move(to: CGPoint(x: 6, y: 7)); p.addLine(to: CGPoint(x: 6, y: 24))
            p.move(to: CGPoint(x: 22, y: 7)); p.addLine(to: CGPoint(x: 22, y: 24))
        case .machine:
            // Weight-stack machine: frame, seat, stack.
            p.addRoundedRect(in: CGRect(x: 5, y: 4, width: 18, height: 20), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 5, y: 16)); p.addLine(to: CGPoint(x: 14, y: 16))
            p.move(to: CGPoint(x: 17, y: 8)); p.addLine(to: CGPoint(x: 20, y: 8))
            p.move(to: CGPoint(x: 17, y: 11)); p.addLine(to: CGPoint(x: 20, y: 11))
            p.move(to: CGPoint(x: 17, y: 14)); p.addLine(to: CGPoint(x: 20, y: 14))
        case .smithMachine:
            // Rails + a bar on the rails.
            p.move(to: CGPoint(x: 7, y: 4)); p.addLine(to: CGPoint(x: 7, y: 24))
            p.move(to: CGPoint(x: 21, y: 4)); p.addLine(to: CGPoint(x: 21, y: 24))
            p.move(to: CGPoint(x: 4, y: 13)); p.addLine(to: CGPoint(x: 24, y: 13))
            p.addRoundedRect(in: CGRect(x: 5, y: 10, width: 3, height: 6), cornerSize: CGSize(width: 1, height: 1))
            p.addRoundedRect(in: CGRect(x: 20, y: 10, width: 3, height: 6), cornerSize: CGSize(width: 1, height: 1))
        case .ezBar:
            // Zig-zag EZ curl bar with end plates.
            p.move(to: CGPoint(x: 3, y: 14)); p.addLine(to: CGPoint(x: 9, y: 14))
            p.addLine(to: CGPoint(x: 12, y: 10)); p.addLine(to: CGPoint(x: 16, y: 18)); p.addLine(to: CGPoint(x: 19, y: 14))
            p.addLine(to: CGPoint(x: 25, y: 14))
            p.addRoundedRect(in: CGRect(x: 4, y: 10, width: 2.5, height: 8), cornerSize: CGSize(width: 1, height: 1))
            p.addRoundedRect(in: CGRect(x: 21.5, y: 10, width: 2.5, height: 8), cornerSize: CGSize(width: 1, height: 1))
        case .trapBar:
            // Hexagonal trap bar.
            p.move(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 22, y: 9))
            p.addLine(to: CGPoint(x: 22, y: 19)); p.addLine(to: CGPoint(x: 14, y: 24))
            p.addLine(to: CGPoint(x: 6, y: 19)); p.addLine(to: CGPoint(x: 6, y: 9))
            p.closeSubpath()
            p.move(to: CGPoint(x: 6, y: 14)); p.addLine(to: CGPoint(x: 2, y: 14))
            p.move(to: CGPoint(x: 22, y: 14)); p.addLine(to: CGPoint(x: 26, y: 14))
        case .landmine:
            // Bar angled into a pivot base.
            p.move(to: CGPoint(x: 6, y: 23)); p.addLine(to: CGPoint(x: 22, y: 7))
            p.addEllipse(in: CGRect(x: 3, y: 20, width: 7, height: 5))
        case .suspension:
            // Two straps from one anchor, handles at the ends.
            p.move(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 9, y: 18))
            p.move(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 19, y: 18))
            p.addEllipse(in: CGRect(x: 6.5, y: 18, width: 5, height: 5))
            p.addEllipse(in: CGRect(x: 16.5, y: 18, width: 5, height: 5))
        case .medicineBall:
            // Ball with a seam.
            p.addEllipse(in: CGRect(x: 6, y: 6, width: 16, height: 16))
            p.move(to: CGPoint(x: 6, y: 14))
            p.addCurve(to: CGPoint(x: 22, y: 14), control1: CGPoint(x: 11, y: 10), control2: CGPoint(x: 17, y: 18))
        case .weightPlates:
            // A plate: disc with a center hole.
            p.addEllipse(in: CGRect(x: 6, y: 6, width: 16, height: 16))
            p.addEllipse(in: CGRect(x: 11.5, y: 11.5, width: 5, height: 5))
        case .dumbbell, .bodyweight:
            break // SF Symbol path — never drawn here.
        }
    }
}
