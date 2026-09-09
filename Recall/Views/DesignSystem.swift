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

/// Big screen title, used instead of a stock navigation large title so every screen
/// controls its own header.
struct ScreenHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.screenTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A titled group of rows on one card surface.
struct CardGroup<Content: View>: View {
    var title: LocalizedStringKey?
    var footnote: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) { content }
                .surfaceCard(padding: 0)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// One line inside a `CardGroup`: label on the left, anything on the right.
struct CardRow<Trailing: View>: View {
    let label: LocalizedStringKey
    var showsDivider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(.body, design: .rounded))
                Spacer(minLength: 12)
                trailing
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if showsDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

/// Pill selector. The stock segmented control is the single most "system settings"
/// looking element there is.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
    }
}
