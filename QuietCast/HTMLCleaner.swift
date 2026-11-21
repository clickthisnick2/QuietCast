import Foundation

enum HTMLCleaner {
    static func clean(_ html: String) -> String {
        var text = html

        // Strip HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Remove URLs (http://, https://, www.)
        text = text.replacingOccurrences(
            of: "https?://\\S+",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "www\\.\\S+",
            with: "",
            options: .regularExpression
        )

        // Named entities, in a fixed order. `&amp;` is last so `&amp;lt;` becomes
        // `&lt;` and is not decoded a second time.
        let entities: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&#8217;", "\u{2019}"),
            ("&#8216;", "\u{2018}"),
            ("&#8220;", "\u{201C}"),
            ("&#8221;", "\u{201D}"),
            ("&#8211;", "\u{2013}"),
            ("&#8212;", "\u{2014}"),
            ("&#8230;", "\u{2026}"),
            ("&amp;", "&"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric HTML entities (&#NNN;)
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let numRange = match.range(at: 1)
                let numStr = nsText.substring(with: numRange)
                if let code = UInt32(numStr), let scalar = Unicode.Scalar(code) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(scalar))
                }
            }
        }

        // Collapse whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
