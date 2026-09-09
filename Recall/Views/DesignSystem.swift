import SwiftUI

// MARK: - Palette

/// Warm paper and ink instead of the system's clinical grey-on-white. Every colour is
/// declared for both appearances so nothing falls back to a system default.
extension Color {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Page background.
    static let paper = dynamic(light: 0xFBF9F6, dark: 0x121110)
    /// Slightly recessed paper, for the few places that need separation.
    static let paperSunken = dynamic(light: 0xF2EEE8, dark: 0x1B1917)
    /// Primary text.
    static let ink = dynamic(light: 0x1C1917, dark: 0xF5F1EA)
    /// Secondary text.
    static let inkSoft = dynamic(light: 0x78716C, dark: 0xA8A29E)
    /// Tertiary text and placeholders.
    static let inkFaint = dynamic(light: 0xA8A29E, dark: 0x6B6560)
    /// Hairline rules — the only structural device besides whitespace.
    static let rule = dynamic(light: 0xE4DED4, dark: 0x2C2926)
    /// The single accent. Warm, and it doubles as the record colour.
    static let ember = dynamic(light: 0xB4491F, dark: 0xE8845C)
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Type

/// Serif for anything editorial — titles and transcripts. The competitors that read as
/// designed rather than assembled all lead with type, and New York ships with the system.
extension Font {
    static let displayLarge = Font.system(size: 34, weight: .semibold, design: .serif)
    static let displayMedium = Font.system(size: 27, weight: .semibold, design: .serif)
    static let displaySmall = Font.system(size: 20, weight: .semibold, design: .serif)
    /// Transcript and summary body. Relative, so Dynamic Type still scales it.
    static let reading = Font.system(.title3, design: .serif)
    static let readingSmall = Font.system(.callout, design: .serif)

    /// Sans for the interface itself: labels, metadata, numbers.
    static let uiLabel = Font.system(.subheadline, weight: .medium)
    static let uiMeta = Font.system(.footnote)
    /// Small caps-ish section markers.
    static let uiMarker = Font.system(.caption, weight: .semibold)

    static func numeric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }
}

// MARK: - Structure

enum Metrics {
    static let gutter: CGFloat = 24
}

extension View {
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.paper)
    }
}

/// Hairline rule. Replaces the card edges — separation without boxes.
struct Rule: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// Uppercase section marker, letterspaced. Quiet, and it carries the rhythm.
struct Marker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.uiMarker)
            .tracking(1.1)
            .foregroundStyle(Color.inkFaint)
    }
}

/// Editorial screen title: serif, large, with an optional quiet line under it.
struct PageTitle<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.displayLarge)
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.uiMeta)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Ghost tag. Outlined rather than filled — filled pills read as system chips.
struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(Color.inkSoft)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(Color.rule, lineWidth: 1))
    }
}

/// Label + value on one hairline-separated line. No card, no chevron.
struct PlainRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.body))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 12)
            trailing
                .font(.system(.body))
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.vertical, 14)
    }
}

/// Underlined selector. A segmented control is unmistakably system chrome.
struct UnderlinePicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 26) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option.value }
                } label: {
                    VStack(spacing: 6) {
                        Text(option.title)
                            .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)
                        Group {
                            if isSelected {
                                Capsule()
                                    .fill(Color.ember)
                                    .matchedGeometryEffect(id: "underline", in: namespace)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Wraps chips onto as many lines as they need.
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

/// Live waveform. One `Canvas` draw per update rather than a stack of animated views.
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

            for index in 0..<count {
                let offset = count - levels.count
                let level = index >= offset ? CGFloat(levels[index - offset]) : 0
                let height = max(barWidth, level * size.height)
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                let fade = 0.3 + 0.7 * (CGFloat(index) / CGFloat(count))

                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(isActive ? Color.ember.opacity(fade) : Color.rule)
                )
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: levels)
        .accessibilityHidden(true)
    }
}
