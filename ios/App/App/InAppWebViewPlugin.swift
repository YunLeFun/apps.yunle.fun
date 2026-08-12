import Capacitor
import Foundation
import ImageIO
import UIKit
import WebKit

private struct AuthorizationSheetContent {
    let applicationName: String
    let applicationOrigin: String
    let applicationIconURL: String?
    let accountName: String
    let accountAvatarURL: String?
    let permissionDescription: String
    let authorizationNotice: String?
}

private enum AuthorizationSheetChoice: String {
    case current
    case other
    case cancel
}

/// Reads image metadata without decoding the source at full resolution, then
/// creates only the small thumbnail needed by the authorization surface.
enum AuthorizationImageDecoder {
    private static let maximumSourceDimension: Int64 = 8_192
    private static let maximumSourcePixels: Int64 = 16_777_216
    private static let thumbnailPixelSize = 256

    static func decode(_ data: Data) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }

        let width = widthNumber.int64Value
        let height = heightNumber.int64Value
        guard width > 0,
              height > 0,
              width <= Self.maximumSourceDimension,
              height <= Self.maximumSourceDimension,
              width <= Self.maximumSourcePixels / height
        else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailPixelSize,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions)
        else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}

/// Streams an HTTPS image with a hard byte ceiling and no redirects. The
/// response is never buffered past the consent surface's 2 MB policy.
final class BoundedHTTPSImageLoader: NSObject, URLSessionDataDelegate,
    URLSessionTaskDelegate {
    private static let allowedMIMETypes: Set<String> = [
        "image/gif",
        "image/heic",
        "image/heif",
        "image/jpeg",
        "image/png",
        "image/webp",
    ]

    private let maximumBytes: Int
    private let completion: (Data?) -> Void
    private var received = Data()
    private var session: URLSession?
    private var completed = false

    init(maximumBytes: Int, completion: @escaping (Data?) -> Void) {
        self.maximumBytes = maximumBytes
        self.completion = completion
        super.init()
    }

    func start(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: url).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme?.lowercased() == "https",
              (200..<300).contains(http.statusCode),
              http.mimeType.map({ Self.allowedMIMETypes.contains($0.lowercased()) }) == true,
              response.expectedContentLength == NSURLSessionTransferSizeUnknown
                || response.expectedContentLength <= Int64(maximumBytes)
        else {
            completionHandler(.cancel)
            finish(nil)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard received.count <= maximumBytes - data.count else {
            dataTask.cancel()
            finish(nil)
            return
        }
        received.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        finish(error == nil ? received : nil)
    }

    private func finish(_ data: Data?) {
        guard !completed else { return }
        completed = true
        completion(data)
        session?.invalidateAndCancel()
        session = nil
    }
}

/// 云乐坊第一方应用的可信原生授权 Sheet。所有展示字段均由宿主注册表或宿主会话提供。
private final class AuthorizationConsentViewController: UIViewController,
    UIAdaptivePresentationControllerDelegate {
    private static let brandColor = UIColor(red: 179 / 255, green: 38 / 255, blue: 30 / 255, alpha: 1)
    private static let accentColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 180 / 255, blue: 171 / 255, alpha: 1)
            : UIColor(red: 179 / 255, green: 38 / 255, blue: 30 / 255, alpha: 1)
    }
    private static let noticeTintColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 185 / 255, blue: 92 / 255, alpha: 1)
            : UIColor(red: 168 / 255, green: 92 / 255, blue: 0, alpha: 1)
    }
    private static let noticeBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 58 / 255, green: 42 / 255, blue: 22 / 255, alpha: 1)
            : UIColor(red: 1, green: 243 / 255, blue: 214 / 255, alpha: 1)
    }
    private static let maximumImageBytes = 2_000_000

    private let content: AuthorizationSheetContent
    private let onChoice: (AuthorizationSheetChoice) -> Void
    private var didComplete = false

    init(
        content: AuthorizationSheetContent,
        onChoice: @escaping (AuthorizationSheetChoice) -> Void
    ) {
        self.content = content
        self.onChoice = onChoice
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityViewIsModal = true
        buildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        complete(.cancel, dismiss: false)
    }

    private func buildLayout() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 24, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(makeIdentityConnection())

        let titleLabel = makeLabel(
            text: "登录到 \(content.applicationName)",
            style: .title2,
            weight: .bold,
            color: .label,
            alignment: .center)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.setCustomSpacing(6, after: titleLabel)
        contentStack.addArrangedSubview(makeOriginRow())

        contentStack.addArrangedSubview(makeInformationPanel(
            symbol: "person.text.rectangle",
            title: "将向 \(content.applicationName) 提供",
            body: content.permissionDescription,
            tint: Self.accentColor,
            background: Self.accentColor.withAlphaComponent(0.08)))

        if let notice = content.authorizationNotice {
            contentStack.addArrangedSubview(makeInformationPanel(
                symbol: "creditcard.fill",
                title: "费用说明",
                body: notice,
                tint: Self.noticeTintColor,
                background: Self.noticeBackgroundColor))
        }

        contentStack.addArrangedSubview(makeSecurityRow())
        scrollView.addSubview(contentStack)

        let actions = makeActionContainer()
        view.addSubview(scrollView)
        view.addSubview(actions)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actions.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func makeIdentityConnection() -> UIView {
        let app = makeIdentityEndpoint(
            imageURL: content.applicationIconURL,
            fallbackText: String(content.applicationName.prefix(1)),
            title: content.applicationName,
            subtitle: "申请登录",
            circular: false)
        let account = makeIdentityEndpoint(
            imageURL: content.accountAvatarURL,
            fallbackText: String(content.accountName.prefix(1)),
            title: content.accountName,
            subtitle: "当前账号",
            circular: true)

        let verifiedIcon = UIImageView(image: UIImage(systemName: "checkmark.shield.fill"))
        verifiedIcon.tintColor = Self.accentColor
        verifiedIcon.contentMode = .scaleAspectFit
        verifiedIcon.translatesAutoresizingMaskIntoConstraints = false
        verifiedIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        verifiedIcon.accessibilityLabel = "云乐坊认证连接"

        let verifiedLabel = makeLabel(
            text: "云乐坊认证",
            style: .caption1,
            weight: .semibold,
            color: Self.accentColor,
            alignment: .center)
        let verified = UIStackView(arrangedSubviews: [verifiedIcon, verifiedLabel])
        verified.axis = .vertical
        verified.spacing = 5
        verified.alignment = .fill

        let row = UIStackView(arrangedSubviews: [app, verified, account])
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 10
        return row
    }

    private func makeIdentityEndpoint(
        imageURL: String?,
        fallbackText: String,
        title: String,
        subtitle: String,
        circular: Bool
    ) -> UIView {
        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.backgroundColor = Self.accentColor.withAlphaComponent(0.10)
        imageContainer.layer.cornerRadius = circular ? 28 : 14
        imageContainer.clipsToBounds = true
        NSLayoutConstraint.activate([
            imageContainer.widthAnchor.constraint(equalToConstant: 56),
            imageContainer.heightAnchor.constraint(equalToConstant: 56),
        ])

        let fallback = makeLabel(
            text: fallbackText,
            style: .title2,
            weight: .bold,
            color: Self.accentColor,
            alignment: .center)
        fallback.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(fallback)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            fallback.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            fallback.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
        ])
        loadHTTPSImage(imageURL, into: imageView, hiding: fallback)

        let titleLabel = makeLabel(
            text: title,
            style: .footnote,
            weight: .semibold,
            color: .label,
            alignment: .center)
        titleLabel.numberOfLines = 2
        let subtitleLabel = makeLabel(
            text: subtitle,
            style: .caption1,
            weight: .regular,
            color: .secondaryLabel,
            alignment: .center)

        let endpoint = UIStackView(arrangedSubviews: [imageContainer, titleLabel, subtitleLabel])
        endpoint.axis = .vertical
        endpoint.spacing = 4
        endpoint.alignment = .center
        endpoint.isAccessibilityElement = true
        endpoint.accessibilityLabel = "\(subtitle)，\(title)"
        return endpoint
    }

    private func makeOriginRow() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = makeLabel(
            text: content.applicationOrigin,
            style: .footnote,
            weight: .regular,
            color: .secondaryLabel,
            alignment: .left)
        label.lineBreakMode = .byTruncatingMiddle
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.distribution = .fill
        return row
    }

    private func makeInformationPanel(
        symbol: String,
        title: String,
        body: String,
        tint: UIColor,
        background: UIColor
    ) -> UIView {
        let panel = UIView()
        panel.backgroundColor = background
        panel.layer.cornerRadius = 16

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        let titleLabel = makeLabel(
            text: title,
            style: .subheadline,
            weight: .semibold,
            color: .label,
            alignment: .left)
        let bodyLabel = makeLabel(
            text: body,
            style: .body,
            weight: .regular,
            color: .label,
            alignment: .left)
        bodyLabel.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
        ])
        return panel
    }

    private func makeSecurityRow() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = makeLabel(
            text: "不会共享你的密码或云乐坊长期登录凭证。",
            style: .footnote,
            weight: .regular,
            color: .secondaryLabel,
            alignment: .left)
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10
        return row
    }

    private func makeActionContainer() -> UIView {
        let primary = makeButton(
            title: "以「\(shortAccountName())」登录",
            configuration: .filled(),
            selector: #selector(allowTapped))
        primary.configuration?.baseBackgroundColor = Self.brandColor
        primary.configuration?.baseForegroundColor = .white
        primary.accessibilityLabel = "以 \(content.accountName) 登录"
        primary.accessibilityIdentifier = "authorization-current-account"

        let other = makeButton(
            title: "使用其他账号",
            configuration: .tinted(),
            selector: #selector(otherTapped))
        other.configuration?.baseBackgroundColor = Self.accentColor.withAlphaComponent(0.12)
        other.configuration?.baseForegroundColor = Self.accentColor
        other.accessibilityIdentifier = "authorization-other-account"

        let cancel = makeButton(
            title: "取消",
            configuration: .plain(),
            selector: #selector(cancelTapped))
        cancel.configuration?.baseForegroundColor = .secondaryLabel
        cancel.accessibilityIdentifier = "authorization-cancel"

        let stack = UIStackView(arrangedSubviews: [primary, other, cancel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            stack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeButton(
        title: String,
        configuration: UIButton.Configuration,
        selector: Selector
    ) -> UIButton {
        var configuration = configuration
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    private func makeLabel(
        text: String,
        style: UIFont.TextStyle,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment
    ) -> UILabel {
        let baseSize = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style).pointSize
        let label = UILabel()
        label.text = text
        label.font = UIFontMetrics(forTextStyle: style)
            .scaledFont(for: UIFont.systemFont(ofSize: baseSize, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = alignment
        return label
    }

    private func shortAccountName() -> String {
        content.accountName.count > 20
            ? String(content.accountName.prefix(19)) + "…"
            : content.accountName
    }

    private func loadHTTPSImage(
        _ source: String?,
        into imageView: UIImageView,
        hiding fallback: UIView
    ) {
        guard let source = source,
              let url = URL(string: source),
              url.scheme?.lowercased() == "https"
        else {
            return
        }
        BoundedHTTPSImageLoader(maximumBytes: Self.maximumImageBytes) { data in
            guard let data = data,
                  let image = AuthorizationImageDecoder.decode(data)
            else {
                return
            }
            DispatchQueue.main.async {
                imageView.image = image
                imageView.isHidden = false
                fallback.isHidden = true
            }
        }.start(url: url)
    }

    @objc private func allowTapped() {
        complete(.current)
    }

    @objc private func otherTapped() {
        complete(.other)
    }

    @objc private func cancelTapped() {
        complete(.cancel)
    }

    private func complete(_ choice: AuthorizationSheetChoice, dismiss: Bool = true) {
        guard !didComplete else { return }
        didComplete = true
        onChoice(choice)
        if dismiss {
            self.dismiss(animated: true)
        }
    }

    func expire() {
        complete(.cancel)
    }
}

@objc(HostRuntimePlugin)
public class HostRuntimePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HostRuntimePlugin"
    public let jsName = "HostRuntime"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateAppInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listSessions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "confirmAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestHostLogin", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resumeAuthorizationAfterLogin", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelAuthorizationLogin", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authorizeWithOtherAccount", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resolveAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearIdentitySessions", returnType: CAPPluginReturnPromise),
    ]

    /// 后台会话池（强持有，保活已最小化/暂停的 WebView）。
    /// LRU 顺序：index 0 = 最近交互；超过上限淘汰最旧的暂停会话。
    /// 「最小化」「跳详情页」只暂停（dismiss 保留状态），「结束」才真正移除释放。
    private var sessions: [WebViewController] = []
    private let maxSessions = 3
    private var authorizationPromptActive = false
    private static let authorizationConsentTimeoutSeconds: TimeInterval = 5 * 60

    /// 会话去重 / 定位键：优先 appId，无则用 URL（与 WebViewController.sessionKey 一致）
    private func indexOfSession(key: String) -> Int? {
        sessions.firstIndex { $0.sessionKey == key }
    }

    /// 移到 LRU 最前（最近交互）
    private func moveToFront(_ vc: WebViewController) {
        if let i = sessions.firstIndex(where: { $0 === vc }) {
            sessions.remove(at: i)
        }
        sessions.insert(vc, at: 0)
    }

    private func removeSession(_ vc: WebViewController) {
        vc.cancelPendingAuthorizations()
        if let i = sessions.firstIndex(where: { $0 === vc }) {
            sessions.remove(at: i)
        }
    }

    /// 超出上限时从最旧端淘汰一个未在前台的会话（其 WKWebView 随之释放）
    private func evictIfNeeded() {
        while sessions.count > maxSessions {
            guard let idx = sessions.lastIndex(where: { $0.presentingViewController == nil }) else { break }
            removeSession(sessions[idx])
        }
    }

    /// 把当前后台会话列表推给 JS（悬浮球 / 托盘 / 主屏「正在运行」区据此渲染）
    private func notifySessionsChanged() {
        notifyListeners("sessionsChanged", data: ["sessions": sessions.map { $0.sessionInfo() }])
    }

    @objc func open(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"),
              let url = URL(string: urlString),
              Self.isSupportedWebURL(url)
        else {
            call.reject("Missing or invalid url")
            return
        }

        let title = call.getString("title") ?? ""
        let toolbarColor = call.getString("toolbarColor")
        let appInfo = parseAppInfo(call.getObject("app"))
        // 展示形态：titlebar（默认）= 顶部固定标题栏 + 单菜单按钮；immersive = 全屏平铺 + 悬浮胶囊（官方应用声明专属）
        let displayMode = WebViewDisplayMode(rawValue: call.getString("displayMode") ?? "") ?? .titlebar
        // 跨站外链打开方式：safari-view（默认）= App 内系统浏览器视图；default-browser = 跳出到手机默认浏览器
        let externalLinkBehavior = ExternalLinkBehavior(rawValue: call.getString("externalLinkMode") ?? "") ?? .safariView
        // 本次会话追加的 JSAPI 授信域（敏感能力鉴权用，详见 WebViewController.isTrustedOrigin）
        let trustedHosts = call.getArray("trustedHosts", String.self) ?? []

        // 会话键：优先 appId，无则用 URL（与 WebViewController.sessionKey 一致）
        let sessionKey = (appInfo?.id).flatMap { $0.isEmpty ? nil : $0 } ?? urlString

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 命中暂停中的同会话（且展示形态一致）：直接恢复，保留页面状态、刷新可变上下文
            if let idx = self.indexOfSession(key: sessionKey),
               self.sessions[idx].presentingViewController == nil,
               self.sessions[idx].displayMode == displayMode {
                let paused = self.sessions[idx]
                paused.externalLinkBehavior = externalLinkBehavior
                paused.extraTrustedHosts = trustedHosts
                self.moveToFront(paused)
                self.bridge?.viewController?.present(paused, animated: true) {
                    call.resolve()
                }
                self.notifySessionsChanged()
                return
            }

            // 同键但形态不一致（无法复用）：释放旧的，走新建
            if let idx = self.indexOfSession(key: sessionKey) {
                self.removeSession(self.sessions[idx])
            }

            let vc = WebViewController()
            vc.url = url
            vc.customTitle = title
            vc.toolbarColorHex = toolbarColor
            vc.appInfo = appInfo
            vc.displayMode = displayMode
            vc.externalLinkBehavior = externalLinkBehavior
            vc.extraTrustedHosts = trustedHosts
            vc.onClose = { [weak self, weak vc] in
                guard let self = self, let vc = vc else { return }
                self.removeSession(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifySessionsChanged()
            }
            vc.onMinimize = { [weak self, weak vc] in
                // 压后台：保活会话、移到最前；通知前台收起 + 最小化事件（区分于「结束」）+ 刷新后台列表
                guard let self = self, let vc = vc else { return }
                self.moveToFront(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifyListeners("browserMinimized", data: ["name": vc.appInfo?.name ?? ""])
                self.notifySessionsChanged()
            }
            vc.onDetail = { [weak self] appId in
                self?.notifyListeners("detailRequested", data: ["appId": appId])
            }
            vc.onAuthorizationRequest = { [weak self, weak vc] requestId, sourceOrigin, request in
                guard let self = self, let vc = vc else { return }
                _ = vc.pauseAuthorizationTimeout(requestId: requestId)
                self.notifyListeners("authorizationRequested", data: [
                    "requestId": requestId,
                    "sourceOrigin": sourceOrigin,
                    "appId": vc.appInfo?.id ?? "",
                    "request": request,
                ], retainUntilConsumed: true)
            }

            vc.modalPresentationStyle = .fullScreen
            self.sessions.insert(vc, at: 0)
            self.evictIfNeeded()

            self.bridge?.viewController?.present(vc, animated: true) {
                call.resolve()
            }
            self.notifySessionsChanged()
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { call.resolve(); return }
            // 关闭当前前台会话（无前台则取最近一个）
            guard let vc = self.sessions.first(where: { $0.presentingViewController != nil }) ?? self.sessions.first else {
                call.resolve()
                return
            }
            if vc.presentingViewController != nil {
                vc.dismiss(animated: true) {
                    self.removeSession(vc)
                    self.notifyListeners("browserFinished", data: [:])
                    self.notifySessionsChanged()
                    call.resolve()
                }
            }
            else {
                self.removeSession(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifySessionsChanged()
                call.resolve()
            }
        }
    }

    /// 打开后由 JS 异步补充应用元信息（如评价数），下次打开详情面板时生效
    @objc func updateAppInfo(_ call: CAPPluginCall) {
        guard let obj = call.getObject("app") else {
            call.resolve()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let vc = self.sessions.first(where: { $0.presentingViewController != nil }) ?? self.sessions.first
            else {
                call.resolve()
                return
            }
            var info = vc.appInfo ?? WebAppInfo()
            Self.apply(obj, to: &info)
            vc.appInfo = info
            call.resolve()
        }
    }

    /// 返回当前后台会话列表（供悬浮球 / 托盘 / 主屏「正在运行」区渲染）
    @objc func listSessions(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            call.resolve(["sessions": self?.sessions.map { $0.sessionInfo() } ?? []])
        }
    }

    /// 彻底结束并释放指定会话（按 sessionKey）；前台会话则先收起
    @objc func endSession(_ call: CAPPluginCall) {
        let key = call.getString("id") ?? call.getString("key") ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let idx = self.indexOfSession(key: key) else {
                call.resolve()
                return
            }
            let vc = self.sessions[idx]
            if vc.presentingViewController != nil {
                vc.dismiss(animated: true) {
                    self.removeSession(vc)
                    self.notifySessionsChanged()
                    call.resolve()
                }
                return
            }
            self.removeSession(vc)
            self.notifySessionsChanged()
            call.resolve()
        }
    }

    /// 在原生可信界面中确认是否允许当前 Apps 账号登录目标应用。
    @objc func confirmAuthorization(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty,
            let applicationName = normalizedPromptLabel(
            call.getString("applicationName"),
            maxLength: 80),
            let applicationOrigin = normalizedHTTPSOrigin(
                call.getString("applicationOrigin")),
            let accountName = normalizedPromptLabel(
                call.getString("accountName"),
                maxLength: 120),
            let permissionDescription = normalizedPromptLabel(
                call.getString("permissionDescription"),
                maxLength: 160)
        else {
            call.reject("Missing authorization prompt context")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Browser unavailable")
                return
            }
            guard !self.authorizationPromptActive else {
                call.reject("Authorization prompt already active")
                return
            }
            guard let presenter = self.authorizationPromptPresenter() else {
                call.reject("No active browser session")
                return
            }
            guard let authorizationSession = self.sessions.first(where: {
                $0.pauseAuthorizationTimeout(requestId: requestId)
            }) else {
                call.reject("Unknown or expired authorization request")
                return
            }

            self.authorizationPromptActive = true
            var decisionFinished = false
            var promptTimeout: DispatchWorkItem?
            let authorizationNotice = normalizedPromptLabel(
                call.getString("authorizationNotice"),
                maxLength: 160)
            let sheet = AuthorizationConsentViewController(
                content: AuthorizationSheetContent(
                    applicationName: applicationName,
                    applicationOrigin: applicationOrigin,
                    applicationIconURL: normalizedHTTPSURL(call.getString("applicationIconUrl")),
                    accountName: accountName,
                    accountAvatarURL: normalizedHTTPSURL(call.getString("accountAvatarUrl")),
                    permissionDescription: permissionDescription,
                    authorizationNotice: authorizationNotice),
                onChoice: { [weak self] choice in
                    guard !decisionFinished else { return }
                    decisionFinished = true
                    promptTimeout?.cancel()
                    self?.authorizationPromptActive = false
                    guard authorizationSession.resumeAuthorizationTimeout(requestId: requestId) else {
                        call.reject("Unknown or expired authorization request")
                        return
                    }
                    call.resolve([
                        "allowed": choice == .current,
                        "choice": choice.rawValue,
                    ])
                })
            if let presentation = sheet.sheetPresentationController {
                presentation.detents = [.medium(), .large()]
                presentation.prefersGrabberVisible = true
                presentation.preferredCornerRadius = 28
            }
            presenter.present(sheet, animated: true)
            let timeout = DispatchWorkItem { [weak self, weak sheet] in
                guard let self = self,
                      self.authorizationPromptActive,
                      !decisionFinished
                else { return }
                _ = authorizationSession.resolveAuthorization(
                    requestId: requestId,
                    result: nil,
                    error: "authorization timed out")
                sheet?.expire()
            }
            promptTimeout = timeout
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.authorizationConsentTimeoutSeconds,
                execute: timeout)
        }
    }

    /// Keep the originating WebView alive while the Apps login route is shown.
    @objc func requestHostLogin(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let session = self.sessions.first(where: {
                      $0.authorizationEvent(requestId: requestId) != nil
                  }),
                  session.pauseAuthorizationTimeout(requestId: requestId)
            else {
                call.reject("Unknown or expired authorization request")
                return
            }

            self.moveToFront(session)
            guard session.presentingViewController != nil else {
                call.resolve()
                return
            }
            session.dismiss(animated: true) {
                self.notifyListeners("browserFinished", data: [:])
                self.notifySessionsChanged()
                call.resolve()
            }
        }
    }

    /// Restore the kept-alive WebView and deliver the same validated request
    /// again. The page Promise is still the original pending authorization.
    @objc func resumeAuthorizationAfterLogin(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let session = self.sessions.first(where: {
                      $0.authorizationEvent(requestId: requestId) != nil
                  }),
                  let event = session.authorizationEvent(requestId: requestId),
                  let presenter = self.bridge?.viewController
            else {
                call.reject("Unknown or expired authorization request")
                return
            }

            let deliver = {
                self.moveToFront(session)
                self.notifyListeners(
                    "authorizationRequested",
                    data: event,
                    retainUntilConsumed: true)
                self.notifySessionsChanged()
                call.resolve()
            }
            if session.presentingViewController != nil {
                deliver()
                return
            }
            guard presenter.presentedViewController == nil else {
                call.reject("Host login surface is busy")
                return
            }
            presenter.present(session, animated: true, completion: deliver)
        }
    }

    /// Cancel the pending page Promise and restore the originating WebView so
    /// the application can render its ordinary signed-out state.
    @objc func cancelAuthorizationLogin(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let session = self.sessions.first(where: {
                      $0.authorizationEvent(requestId: requestId) != nil
                  }),
                  session.resolveAuthorization(
                      requestId: requestId,
                      result: nil,
                      error: "HOST_AUTH_DENIED"),
                  let presenter = self.bridge?.viewController
            else {
                call.reject("Unknown or expired authorization request")
                return
            }

            let finish = {
                self.moveToFront(session)
                self.notifySessionsChanged()
                call.resolve()
            }
            if session.presentingViewController != nil {
                finish()
                return
            }
            guard presenter.presentedViewController == nil else {
                call.reject("Host login surface is busy")
                return
            }
            presenter.present(session, animated: true, completion: finish)
        }
    }

    /// 在 AuthenticationServices 的可信系统界面中完成其他账号登录。
    @objc func authorizeWithOtherAccount(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Browser unavailable")
                return
            }
            let started = self.sessions.contains {
                $0.beginOtherAccountAuthorization(requestId: requestId)
            }
            if started {
                call.resolve()
            }
            else {
                call.reject("Unknown or invalid authorization request")
            }
        }
    }

    /// 把宿主 JS 签发的一次性授权码回传给发起请求的 WebView Promise。
    @objc func resolveAuthorization(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        let result = call.getObject("result")
        let error = call.getString("error")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Browser unavailable")
                return
            }
            let resolved = self.sessions.contains {
                $0.resolveAuthorization(
                    requestId: requestId,
                    result: result,
                    error: error)
            }
            if resolved {
                call.resolve()
            }
            else {
                call.reject("Unknown or expired authorization request")
            }
        }
    }

    /// Native allowlist for sessions derived from Apps identity.
    ///
    /// Keep this independent from web input: JavaScript cannot choose arbitrary
    /// cookie names or domains for native deletion.
    private static let identitySessionCookies: [(host: String, name: String)] = [
        ("play.yunle.fun", "__Host-ylf_play_session"),
        ("cms.yunle.fun", "__Host-ylf-cms-session"),
        // nuxt-auth-utils stores the CMS user projection separately. It is
        // never authoritative without the opaque CMS session, but clearing it
        // ensures SSR renders LoginGate immediately after an Apps account change.
        ("cms.yunle.fun", "h3"),
    ]

    /// Apps 退出或切换账号后清除第一方 HttpOnly BFF cookie，并通知保活页面刷新身份。
    @objc func clearIdentitySessions(_ call: CAPPluginCall) {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            let identityCookies = cookies.filter { cookie in
                let host = cookie.domain
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased()
                return Self.identitySessionCookies.contains {
                    $0.host == host && $0.name == cookie.name
                }
            }
            let group = DispatchGroup()
            identityCookies.forEach { cookie in
                group.enter()
                cookieStore.delete(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self?.sessions
                    .forEach { $0.notifyHostIdentityChanged() }
                call.resolve()
            }
        }
    }

    private func parseAppInfo(_ obj: JSObject?) -> WebAppInfo? {
        guard let obj = obj else { return nil }
        var info = WebAppInfo()
        Self.apply(obj, to: &info)
        return info
    }

    private func normalizedPromptLabel(_ value: String?, maxLength: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(normalized.prefix(maxLength))
    }

    private func normalizedHTTPSOrigin(_ value: String?) -> String? {
        guard let value = value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil,
              url.fragment == nil
        else {
            return nil
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return "https://\(host)\(port)"
    }

    private func normalizedHTTPSURL(_ value: String?) -> String? {
        guard let value = value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil
        else {
            return nil
        }
        return url.absoluteString
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil
        else {
            return false
        }
        if scheme == "https" { return true }
#if DEBUG
        return scheme == "http"
            && (host == "localhost" || host == "127.0.0.1" || host == "::1")
#else
        return false
#endif
    }

    private func authorizationPromptPresenter() -> UIViewController? {
        guard var presenter = bridge?.viewController else {
            return nil
        }

        // Follow UIKit's actual presentation chain instead of the session LRU.
        // Multiple kept-alive sessions may still have a presenting controller;
        // choosing the first one can place the sheet behind the visible WebView.
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        var owner: UIViewController? = presenter
        while let current = owner {
            if sessions.contains(where: { $0 === current }) {
                return presenter
            }
            owner = current.presentingViewController
        }
        return nil
    }

    /// 仅覆盖 JS 侧传入的字段（部分更新）
    private static func apply(_ obj: JSObject, to info: inout WebAppInfo) {
        if let v = obj["id"] as? String { info.id = v }
        if let v = obj["slug"] as? String { info.slug = v }
        if let v = obj["name"] as? String { info.name = v }
        if let v = obj["emoji"] as? String { info.emoji = v }
        if let v = obj["logo"] as? String { info.logo = v }
        if let v = obj["themeColor"] as? String { info.themeColor = v }
        if let v = obj["description"] as? String { info.description = v }
        if let v = obj["category"] as? String { info.category = v }
        if let v = obj["downloads"] as? String { info.downloads = v }
        if let v = obj["rating"] as? Double { info.rating = v }
        else if let v = obj["rating"] as? Int { info.rating = Double(v) }
        if let v = obj["ratingCount"] as? Int { info.ratingCount = v }
        else if let v = obj["ratingCount"] as? Double { info.ratingCount = Int(v) }
    }
}
