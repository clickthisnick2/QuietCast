import Foundation

enum TimeGate {
    static let searchOpensLabel = "8 AM"
    static let searchClosesLabel = "8 PM"
    /// Shown wherever the search window is described, for example "8 AM – 8 PM".
    static let searchHoursText = "\(searchOpensLabel) – \(searchClosesLabel)"
    /// Nighttime window, the inverse of search hours.
    static let nightHoursText = "\(searchClosesLabel) – \(searchOpensLabel)"
    /// Search window written with "and", for the library caption.
    static let searchHoursSentence = "\(searchOpensLabel) and \(searchClosesLabel)"

    /// Search is allowed between 8:00 AM and 7:59 PM local time.
    /// Returns false when hour >= 20 or hour < 8.
    static func searchAllowed(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 8 && hour < 20
    }

    /// Nighttime is 8:00 PM – 7:59 AM (the inverse of search hours).
    static func isNighttime(at date: Date = Date()) -> Bool {
        !searchAllowed(at: date)
    }
}
