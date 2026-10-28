import Foundation

enum FeedbackChannel: String, Codable, Sendable {
    case standard, testFlight

    static func forLaunch(receiptURL: URL?, isDevelopment: Bool, isSimulator: Bool) -> Self {
        !isDevelopment && !isSimulator && receiptURL?.lastPathComponent == "sandboxReceipt" ? .testFlight : .standard
    }

    static var current: Self {
        #if DEBUG
        let development = true
        #else
        let development = false
        #endif
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return forLaunch(receiptURL: Bundle.main.appStoreReceiptURL, isDevelopment: development, isSimulator: simulator)
    }

    static func forShareExtension(receiptURL: URL?, remembered: Self?, isDevelopment: Bool, isSimulator: Bool) -> Self {
        if isDevelopment || isSimulator { return .standard }
        guard receiptURL != nil else { return remembered ?? .standard }
        return forLaunch(receiptURL: receiptURL, isDevelopment: false, isSimulator: false)
    }
}
