import SwiftUI

// MARK: - Иконки

struct DroneGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2
            let oy = (size.height - s) / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            var arms = Path()
            arms.move(to: p(0.26, 0.26))
            arms.addLine(to: p(0.74, 0.74))
            arms.move(to: p(0.74, 0.26))
            arms.addLine(to: p(0.26, 0.74))
            context.stroke(
                arms,
                with: .color(.white),
                style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round)
            )

            let rotors: [(CGFloat, CGFloat)] = [
                (0.22, 0.22), (0.78, 0.22), (0.22, 0.78), (0.78, 0.78),
            ]
            for (x, y) in rotors {
                let center = p(x, y)
                let radius = s * 0.135
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white),
                    lineWidth: s * 0.05
                )
            }

            let center = p(0.5, 0.5)
            let bodyRect = CGRect(
                x: center.x - s * 0.095,
                y: center.y - s * 0.065,
                width: s * 0.19,
                height: s * 0.13
            )
            context.fill(
                Path(roundedRect: bodyRect, cornerRadius: s * 0.035),
                with: .color(.white)
            )

            let cameraRect = CGRect(
                x: center.x - s * 0.028,
                y: center.y + s * 0.075,
                width: s * 0.056,
                height: s * 0.056
            )
            context.fill(Path(ellipseIn: cameraRect), with: .color(.white))
        }
    }
}

struct MissileGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2
            let oy = (size.height - s) / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            var bodyPath = Path()
            bodyPath.move(to: p(0.5, 0.03))
            bodyPath.addLine(to: p(0.635, 0.30))
            bodyPath.addLine(to: p(0.635, 0.70))
            bodyPath.addLine(to: p(0.365, 0.70))
            bodyPath.addLine(to: p(0.365, 0.30))
            bodyPath.closeSubpath()
            context.fill(bodyPath, with: .color(.white))

            var leftFin = Path()
            leftFin.move(to: p(0.365, 0.50))
            leftFin.addLine(to: p(0.215, 0.76))
            leftFin.addLine(to: p(0.365, 0.735))
            leftFin.closeSubpath()
            context.fill(leftFin, with: .color(.white))

            var rightFin = Path()
            rightFin.move(to: p(0.635, 0.50))
            rightFin.addLine(to: p(0.785, 0.76))
            rightFin.addLine(to: p(0.635, 0.735))
            rightFin.closeSubpath()
            context.fill(rightFin, with: .color(.white))

            let windowCenter = p(0.5, 0.24)
            let windowRect = CGRect(
                x: windowCenter.x - s * 0.045,
                y: windowCenter.y - s * 0.03,
                width: s * 0.09,
                height: s * 0.06
            )
            context.fill(
                Path(roundedRect: windowRect, cornerRadius: s * 0.02),
                with: .color(Color(red: 0.10, green: 0.15, blue: 0.22))
            )

            var flame = Path()
            flame.move(to: p(0.43, 0.70))
            flame.addLine(to: p(0.5, 0.95))
            flame.addLine(to: p(0.57, 0.70))
            flame.closeSubpath()
            context.fill(
                flame,
                with: .color(Color(red: 1.0, green: 0.45, blue: 0.05))
            )
        }
    }
}

struct AlertGlyph: View {
    let kind: AlertKind
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.accent.opacity(0.16))
            Circle()
                .stroke(kind.accent.opacity(0.45), lineWidth: 1)
            symbol
                .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var symbol: some View {
        switch kind {
        case .uavThreat:
            DroneGlyph()
        case .missileThreat:
            MissileGlyph()
        case .sirensOn:
            Image(systemName: "speaker.wave.3.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(kind.accent)
        case .uavAllClear, .missileAllClear:
            Image(systemName: "checkmark.shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(kind.accent)
        case .sirensOff:
            Image(systemName: "speaker.slash.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(kind.accent)
        }
    }
}

// MARK: - Картинка для уведомления

struct NotificationArtwork: View {
    let kind: AlertKind

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.12),
                    kind.accent.opacity(0.45),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 28) {
                AlertGlyph(kind: kind, size: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Text(kind.title.uppercased())
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text("Оренбургская область")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)
            }
            .padding(36)
        }
    }
}

// MARK: - Строка истории

struct AlertRow: View {
    let event: AlertEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AlertGlyph(kind: event.kind, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    if event.isTest {
                        Text("ТЕСТ")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer(minLength: 0)

                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(event.kind.notificationBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(event.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

// MARK: - Кнопки

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.orange.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .foregroundStyle(.black)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0.07))
            )
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
