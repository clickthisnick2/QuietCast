import Foundation

/// Labels shared by the library list and the Now Playing bar.
enum PlaybackText {
    /// "1h 23m" or "5m". Truncates seconds. Under a minute is "0m".
    static func hoursMinutes(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0m" }
        let bounded = min(max(seconds, 0.0), Double(Int.max / 4))
        let total = Int(bounded)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Downloaded-row progress. Under a minute is "<1m"; otherwise the same hours-and-minutes text.
    static func progressSpan(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "<1m" }
        let bounded = min(max(seconds, 0.0), Double(Int.max / 4))
        if bounded < 60 {
            return "<1m"
        }
        return hoursMinutes(bounded)
    }

    /// Elapsed or remaining clock on the transport bar. Hours appear only past 59:59.
    static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Sleep-timer countdown. Stays in minutes even past an hour.
    static func countdown(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Speed menu label, such as "1x" or "1.5x".
    static func rate(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }

    /// Exact hours, minutes, and seconds for spoken sleep-timer announcements.
    static func spokenRemaining(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        var parts: [String] = []
        if h > 0 {
            parts.append("\(h) hour\(h == 1 ? "" : "s")")
        }
        if m > 0 {
            parts.append("\(m) minute\(m == 1 ? "" : "s")")
        }
        if s > 0 || parts.isEmpty {
            parts.append("\(s) second\(s == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    /// `itunes:duration` is seconds, minutes:seconds, or hours:minutes:seconds.
    static func durationSeconds(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ":")
        if pieces.count == 1 {
            guard let seconds = Double(trimmed), seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        }
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        var total = 0.0
        for piece in pieces {
            let part = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            total = total * 60 + value
        }
        guard total.isFinite, total > 0 else { return nil }
        return total
    }
}
