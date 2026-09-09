import Foundation

enum DurationFormat {
    /// `m:ss`, or `h:mm:ss` past an hour.
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatStyle(style: .file).format(bytes)
    }
}
