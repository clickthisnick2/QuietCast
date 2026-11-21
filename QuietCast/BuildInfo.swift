import Foundation

enum BuildInfo {
    /// Timestamp of when the app binary was last built, derived from the executable's modification date.
    static let timestamp: String = {
        guard let executableURL = Bundle.main.executableURL,
            let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
            let date = attributes[.modificationDate] as? Date
        else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }()
}
