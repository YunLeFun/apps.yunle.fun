import SwiftUI
import UIKit

final class FeedbackShareViewController: UIViewController {
    private var composer: ShareFeedbackComposer?

    override func viewDidLoad() {
        super.viewDidLoad()
        let content: AnyView
        do {
            let history = SharedFeedbackHistory()
            let remembered = try history.rememberedContext()?.channel
            let channel = Self.channel(remembered: remembered)
            let context = try history.prepareForShare(channel: channel)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
            let model = ShareFeedbackComposer(context: context, history: history, version: "\(version) (\(build))")
            composer = model
            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            content = AnyView(ShareFeedbackView(model: model, providers: providers,
                onCancel: { [weak self] in self?.cancelShare() }, onFinish: { [weak self] in self?.finishShare() }))
        } catch {
            content = AnyView(ShareFeedbackUnavailableView(message: (error as? SharedFeedbackHistoryError)?.message
                ?? "暂时无法打开反馈，请先打开一次云乐坊，再重新分享。", onClose: { [weak self] in self?.cancelShare() }))
        }
        let hosting = UIHostingController(rootView: content)
        addChild(hosting); hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor), hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        preferredContentSize = CGSize(width: 540, height: 680)
    }

    private func cancelShare() {
        composer?.discardDraft()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func finishShare() {
        composer?.discardDraft()
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func channel(remembered: FeedbackChannel?) -> FeedbackChannel {
        #if DEBUG && YUNLE_FEEDBACK_LOCAL_VALIDATION && targetEnvironment(simulator)
        // Lets the isolated acceptance fixture exercise the Beta guidance UI without a fake receipt.
        return remembered ?? .standard
        #else
        // The extension's Bundle.main has no App Store receipt of its own.
        let containingURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let containingBundle = containingURL.pathExtension == "app" ? Bundle(url: containingURL) : nil
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
        return FeedbackChannel.forShareExtension(receiptURL: containingBundle?.appStoreReceiptURL, remembered: remembered,
                                                isDevelopment: development, isSimulator: simulator)
        #endif
    }
}
