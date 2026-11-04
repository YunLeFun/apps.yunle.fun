import Foundation
import ImageIO
import UIKit
import WebKit

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

private let authorizationComfortableDetentIdentifier
    = UISheetPresentationController.Detent.Identifier("authorization-comfortable")

@MainActor
func configureAuthorizationConsentPresentation(
    _ presentation: UISheetPresentationController,
    contentSizeCategory: UIContentSizeCategory
) {
    if contentSizeCategory.isAccessibilityCategory {
        presentation.detents = [.large()]
        presentation.selectedDetentIdentifier = .large
    } else {
        let comfortable = UISheetPresentationController.Detent.custom(
            identifier: authorizationComfortableDetentIdentifier
        ) { context in
            guard context.containerTraitCollection.verticalSizeClass != .compact else {
                return nil
            }
            let proportionalHeight = context.maximumDetentValue * 0.76
            return min(
                context.maximumDetentValue,
                max(540, min(640, proportionalHeight)))
        }
        presentation.detents = [comfortable, .large()]
        presentation.selectedDetentIdentifier = authorizationComfortableDetentIdentifier
    }
    presentation.prefersGrabberVisible = true
    presentation.prefersScrollingExpandsWhenScrolledToEdge = true
    presentation.preferredCornerRadius = 28
}

/// 云乐坊第一方应用的可信原生授权 Sheet。所有展示字段均由宿主注册表或宿主会话提供。
final class AuthorizationConsentViewController: UIViewController,
    UIAdaptivePresentationControllerDelegate {
    private static let accentColor = UIColor.systemBlue
    private static let noticeTintColor = UIColor.systemOrange
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
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 24, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(makeHeader())
        contentStack.setCustomSpacing(4, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeApplicationHero())
        contentStack.setCustomSpacing(8, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeOriginRow())
        contentStack.addArrangedSubview(makeAccountPanel())

        contentStack.addArrangedSubview(makeInformationPanel(
            symbol: "person.text.rectangle",
            title: "将向 \(content.applicationName) 提供",
            body: content.permissionDescription,
            tint: Self.accentColor,
            background: .secondarySystemBackground))

        if let notice = content.authorizationNotice {
            contentStack.addArrangedSubview(makeInformationPanel(
                symbol: "creditcard.fill",
                title: "费用说明",
                body: notice,
                tint: Self.noticeTintColor,
                background: Self.noticeTintColor.withAlphaComponent(0.10)))
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

    private func makeHeader() -> UIView {
        let spacer = UIView()
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .secondaryLabel
        close.backgroundColor = .tertiarySystemFill
        close.layer.cornerRadius = 22
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        close.accessibilityLabel = "关闭授权"
        close.accessibilityIdentifier = "authorization-cancel"
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
        ])

        let row = UIStackView(arrangedSubviews: [spacer, close])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func makeApplicationHero() -> UIView {
        let icon = makeIdentityImage(
            imageURL: content.applicationIconURL,
            fallbackText: String(content.applicationName.prefix(1)),
            size: 64,
            cornerRadius: 16)
        icon.isAccessibilityElement = true
        icon.accessibilityLabel = "\(content.applicationName) 应用图标"

        let title = makeLabel(
            text: "允许“\(content.applicationName)”登录？",
            style: .title2,
            weight: .bold,
            color: .label,
            alignment: .center)
        title.numberOfLines = 0

        let subtitle = makeLabel(
            text: "云乐坊将使用你的当前账号完成安全授权",
            style: .subheadline,
            weight: .regular,
            color: .secondaryLabel,
            alignment: .center)
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.setCustomSpacing(14, after: icon)
        return stack
    }

    private func makeIdentityImage(
        imageURL: String?,
        fallbackText: String,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> UIView {
        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.backgroundColor = Self.accentColor.withAlphaComponent(0.10)
        imageContainer.layer.cornerRadius = cornerRadius
        imageContainer.clipsToBounds = true
        NSLayoutConstraint.activate([
            imageContainer.widthAnchor.constraint(equalToConstant: size),
            imageContainer.heightAnchor.constraint(equalToConstant: size),
        ])

        let fallback = makeLabel(
            text: fallbackText,
            style: size >= 60 ? .title1 : .headline,
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
        return imageContainer
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
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let container = UIView()
        container.backgroundColor = .tertiarySystemFill
        container.layer.cornerRadius = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return container
    }

    private func makeAccountPanel() -> UIView {
        let avatar = makeIdentityImage(
            imageURL: content.accountAvatarURL,
            fallbackText: String(content.accountName.prefix(1)),
            size: 48,
            cornerRadius: 24)

        let context = makeLabel(
            text: "使用此云乐坊账号",
            style: .footnote,
            weight: .regular,
            color: .secondaryLabel,
            alignment: .left)
        let account = makeLabel(
            text: content.accountName,
            style: .headline,
            weight: .semibold,
            color: .label,
            alignment: .left)
        account.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [context, account])
        labels.axis = .vertical
        labels.spacing = 2

        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = Self.accentColor
        check.contentMode = .scaleAspectFit
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            check.widthAnchor.constraint(equalToConstant: 24),
            check.heightAnchor.constraint(equalToConstant: 24),
        ])

        let row = UIStackView(arrangedSubviews: [avatar, labels, check])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let panel = UIView()
        panel.backgroundColor = .secondarySystemBackground
        panel.layer.cornerRadius = 16
        panel.isAccessibilityElement = true
        panel.accessibilityLabel = "当前云乐坊账号，\(content.accountName)，已选择"
        panel.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
        return panel
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
            color: .secondaryLabel,
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
            title: "使用此账号继续",
            configuration: .filled(),
            selector: #selector(allowTapped))
        primary.tintColor = Self.accentColor
        primary.accessibilityLabel = "以 \(content.accountName) 登录"
        primary.accessibilityIdentifier = "authorization-current-account"

        let other = makeButton(
            title: "使用其他账号",
            configuration: .tinted(),
            selector: #selector(otherTapped))
        other.configuration?.baseForegroundColor = Self.accentColor
        other.accessibilityIdentifier = "authorization-other-account"

        let stack = UIStackView(arrangedSubviews: [primary, other])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
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
        button.titleLabel?.numberOfLines = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
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
        if dismiss, presentingViewController != nil {
            self.dismiss(animated: true) { self.onChoice(choice) }
        } else { onChoice(choice) }
    }

    func expire() {
        complete(.cancel)
    }
}

/// 根据设备物理内存选择保守的 WebView 自动上限；会员可手动提高到 7 个。
enum WebViewSessionPolicy {
    private static let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
    private static let memberLimitRange = 2...7

    static func automaticLimit(physicalMemory: UInt64) -> Int {
        if physicalMemory < 5 * gibibyte { return 2 }
        if physicalMemory < 7 * gibibyte { return 3 }
        if physicalMemory < 10 * gibibyte { return 4 }
        return 5
    }

    static func memberLimit(_ preferredLimit: Int?) -> Int? {
        guard let preferredLimit, memberLimitRange.contains(preferredLimit) else { return nil }
        return preferredLimit
    }
}

/// Shared by native SwiftUI runtime surfaces.
/// Web input cannot choose the identity cookies this method deletes.
@MainActor
enum HostIdentitySessions {
    private static let identitySessionCookies: [(host: String, name: String)] = [
        ("play.yunle.fun", "__Host-ylf_play_session"),
        ("cms.yunle.fun", "__Host-ylf-cms-session"),
        ("cms.yunle.fun", "h3"),
    ]

    static func clear(completion: @escaping () -> Void) {
        clear(in: .default(), completion: completion)
    }

    static func clear(in dataStore: WKWebsiteDataStore,
                      completion: @escaping () -> Void) {
        // Identity resets also run before any browser exists. Keep a WebKit
        // context for this store alive through both enumeration and deletion;
        // a detached cookie store can stall across iOS process suspension.
        // The context never loads a page or joins the visible session pool.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let context = WKWebView(frame: .zero, configuration: configuration)
        let cookieStore = dataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let identityCookies = cookies.filter { cookie in
                let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                return identitySessionCookies.contains { $0.host == host && $0.name == cookie.name }
            }
            let group = DispatchGroup()
            identityCookies.forEach { cookie in
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                withExtendedLifetime(context) { completion() }
            }
        }
    }
}
