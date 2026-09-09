import SwiftUI

enum Metrics {
    static let card: CGFloat = 24
    static let control: CGFloat = 18
    static let gutter: CGFloat = 20
}

extension Font {
    /// Screen titles. Rounded reads warmer than the system default at large sizes.
    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    /// Metadata under a title: small, medium weight, never shouting.
    static let meta = Font.system(.footnote, design: .rounded, weight: .medium)
    /// Transcript body — deliberately larger than .body, and Dynamic Type still scales it.
    static let transcript = Font.system(.title3, design: .default, weight: .regular)

    /// Fixed-size numeric display, for the recording timer only.
    static func timer(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded)
    }
}

extension View {
    /// Grouped-background page. Without it the cards below are white on white.
    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
    }

    /// The one card surface used across the app.
    func surfaceCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

/// Small capsule used for tags and status.
struct Chip: View {
    let text: String
    var tint: Color = .accentColor
    var prominent = false

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? .white : tint)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
            )
    }
}

/// Live waveform. One `Canvas` draw per update instead of a stack of animated views —
/// the old version re-diffed sixty `Capsule`s on every audio buffer and stuttered.
struct Waveform: View {
    let recorder: AudioRecorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let levels = recorder.levels
        let isActive = recorder.isRecording

        Canvas(opaque: false) { context, size in
            let count = AudioRecorder.levelWindow
            let spacing: CGFloat = 3
            let barWidth = max(1.5, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let midY = size.height / 2
            let maxHeight = size.height

            for index in 0..<count {
                // Newest sample sits at the right edge; older ones drift left and fade.
                let offset = count - levels.count
                let level = index >= offset ? CGFloat(levels[index - offset]) : 0
                let height = max(barWidth, level * maxHeight)
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                let fade = 0.25 + 0.75 * (CGFloat(index) / CGFloat(count))

                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(isActive ? Color.accentColor.opacity(fade) : Color.secondary.opacity(0.22))
                )
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: levels)
        .accessibilityHidden(true)
    }
}

/// Wraps chips onto as many lines as they need. `HStack` would clip them and
/// `ViewThatFits` could only drop them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
