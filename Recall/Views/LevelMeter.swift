import SwiftUI

/// Rolling bar meter fed by the recorder's level window. Purely decorative — the bars
/// are padded to a fixed count so the layout does not jump as samples arrive.
struct LevelMeter: View {
    var levels: [Float]
    var isActive: Bool

    private var padded: [Float] {
        let capacity = AudioRecorder.levelWindow
        guard levels.count < capacity else { return Array(levels.suffix(capacity)) }
        return Array(repeating: 0, count: capacity - levels.count) + levels
    }

    var body: some View {
        GeometryReader { proxy in
            let bars = padded
            let spacing: CGFloat = 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(bars.count - 1)) / CGFloat(bars.count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: width, height: max(3, proxy.size.height * CGFloat(level)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.08), value: bars)
        }
        .accessibilityHidden(true)
    }
}
