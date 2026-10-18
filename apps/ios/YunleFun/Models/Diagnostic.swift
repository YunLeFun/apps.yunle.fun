import Foundation

enum DiagnosticLogLevel: String, Codable, CaseIterable, Sendable {
    case log, info, warn, error, debug
}

struct DiagnosticLogEntry: Codable, Equatable, Sendable {
    let level: DiagnosticLogLevel
    let message: String
    let timestamp: Double
}

struct DiagnosticClientContext: Codable, Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let platform: String
    let route: String
    let timezone: String
    let userAgent: String
}

struct DiagnosticUploadPayload: Codable, Equatable, Sendable {
    let startTime: Double
    let endTime: Double
    let issueDescription: String
    let logs: [DiagnosticLogEntry]
    let client: DiagnosticClientContext
}

struct DiagnosticUploadReceipt: Codable, Equatable, Sendable {
    let uploadId: String
    let supportCode: String
    let logCount: Int
    let expiresAt: Double
}

enum DiagnosticLimits {
    static let retentionMilliseconds: Double = 7 * 24 * 60 * 60 * 1000
    static let futureClockSkewMilliseconds: Double = 5 * 60 * 1000
    static let maximumEntries = 500
    static let maximumMessageUTF16Length = 1500
}

/// A second line of protection for explicitly selected host events. Callers
/// must still exclude account data, request bodies and cloud-application text.
enum DiagnosticText {
    static func redact(_ value: String, limit: Int = DiagnosticLimits.maximumMessageUTF16Length) -> String {
        var result = replace(authorizationBearer, in: value, with: "$1Bearer [redacted]")
        result = replace(bearer, in: result, with: "Bearer [redacted]")
        result = replace(quotedSensitiveValue, in: result, with: "$1$2[redacted]$2")
        result = replace(bareSensitiveValue, in: result, with: "$1[redacted]")
        result = replace(jwt, in: result, with: "[redacted-token]")
        let source = result as NSString
        for match in httpURL.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
            let raw = source.substring(with: match.range)
            var candidate = raw
            var trailing = ""
            while let last = candidate.last, "),.;".contains(last) {
                trailing.insert(candidate.removeLast(), at: trailing.startIndex)
            }
            let redacted: String
            if let url = URL(string: candidate), let host = url.host, !host.isEmpty {
                redacted = "[redacted-url:\(host.lowercased())]" + trailing
            } else { redacted = "[redacted-url]" + trailing }
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: redacted) }
        }
        result = replace(email, in: result, with: "[redacted-email]")
        result = replace(longIdentifier, in: result, with: "[redacted-id]")
        result = replace(phone, in: result, with: "[redacted-phone]")
        return utf16Prefix(result, limit: limit)
    }

    /// JavaScript counts UTF-16 units. Preserve complete Swift Characters at
    /// that boundary, including surrogate pairs and joined emoji sequences.
    static func utf16Prefix(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        var count = 0
        var end = value.startIndex
        while end < value.endIndex {
            let next = value.index(after: end)
            let length = value[end..<next].utf16.count
            guard count + length <= limit else { break }
            count += length; end = next
        }
        return String(value[..<end])
    }

    private static func replace(_ expression: NSRegularExpression, in value: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: template)
    }

    private static let sensitiveKey = #"access[_-]?token|refresh[_-]?token|password|passwd|secret|cookie|session|q-signature|signature|token"#
    private static let authorizationBearer = try! NSRegularExpression(pattern: #"(Authorization\s*[:=]\s*)Bearer\s+[\w.~+/=-]+"#, options: .caseInsensitive)
    private static let bearer = try! NSRegularExpression(pattern: #"Bearer\s+[\w.~+/=-]+"#, options: .caseInsensitive)
    private static let quotedSensitiveValue = try! NSRegularExpression(
        pattern: #"(["']?(?:"# + sensitiveKey + #")["']?\s*[:=]\s*)(["'])([\s\S]*?)\2"#, options: .caseInsensitive)
    // Match an existing placeholder as a whole so load/select redaction is
    // idempotent, rather than appending another closing bracket on each pass.
    private static let bareSensitiveValue = try! NSRegularExpression(
        pattern: #"((?:"# + sensitiveKey + #")\s*[:=]\s*)(?:\[redacted\]|[^\s,;&}\]"']+)"#, options: .caseInsensitive)
    private static let jwt = try! NSRegularExpression(pattern: #"\beyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}\b"#)
    private static let httpURL = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#, options: .caseInsensitive)
    private static let email = try! NSRegularExpression(pattern: #"\b[\w.%+-]+@[\w.-]+\.[A-Z]{2,}\b"#, options: .caseInsensitive)
    private static let longIdentifier = try! NSRegularExpression(pattern: #"\b\d{16,20}\b"#)
    private static let phone = try! NSRegularExpression(pattern: #"(?:\+?86[\s-]?)?1[3-9]\d{9}"#)
}
