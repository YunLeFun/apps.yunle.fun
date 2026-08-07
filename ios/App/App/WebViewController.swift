import AuthenticationServices
import SafariServices
import Security
import UIKit
import WebKit

/// 打开网页时随附的应用元信息（用于详情面板展示）
struct WebAppInfo {
    var id: String = ""
    /// URL slug（评价 key 优先用 slug；详情页站内路由用它）
    var slug: String = ""
    var name: String = ""
    var emoji: String = ""
    var logo: String = ""
    var themeColor: String = "#007AFF"
    var description: String = ""
    var category: String = ""
    var rating: Double = 0
    /// 评价条数（-1 = 未知，打开后由 JS 异步补充）
    var ratingCount: Int = -1
    var downloads: String = ""
}

/// 跨站外链的打开方式
enum ExternalLinkBehavior: String {
    /// App 内系统浏览器视图（SFSafariViewController，不跳出 App）
    case safariView = "safari-view"
    /// 跳出到手机默认浏览器
    case defaultBrowser = "default-browser"
}

/// 内嵌浏览器展示形态
enum WebViewDisplayMode: String {
    /// 沉浸式：网页全屏平铺，右上角悬浮胶囊（可拖动、随滚动隐藏）。官方应用声明专属
    case immersive
    /// 标题栏（默认）：顶部固定导航栏（返回 / 应用标题 / 「更多」菜单按钮，套用应用主题色），
    /// 网页从栏下开始，底部仍铺满到屏幕底
    case titlebar
}

/// 自定义网页容器，按 displayMode 分两种形态：
/// 沉浸式 = 无导航栏，网页全屏平铺，右上角悬浮小程序风格胶囊（更多 | 关闭），
/// 可后退时左上角出现悬浮返回键（官方应用声明专属）；
/// 标题栏（默认）= 顶部固定导航栏（返回 / 标题 / 单个「更多」菜单按钮，套用应用主题色），
/// 网页底部仍铺满。关闭收口在「更多」展开面板。
class WebViewController: UIViewController {
    var url: URL?
    var customTitle: String = ""
    var toolbarColorHex: String?
    var appInfo: WebAppInfo?
    /// 展示形态（present 之前设置，viewDidLoad 后不可变更；默认标题栏，沉浸为官方应用声明专属）
    var displayMode: WebViewDisplayMode = .titlebar
    /// 跨站外链的打开方式
    var externalLinkBehavior: ExternalLinkBehavior = .safariView
    /// 宿主打开时按应用追加的 JSAPI 授信 host（与内置第一方域合并）；
    /// 条目为可注册域（如 example.com），子域自动匹配
    var extraTrustedHosts: [String] = []
    /// 详情模态标志：true = 本容器是「查看详情与评价」弹出的站内详情页 sheet
    /// （pageSheet 可下滑 dismiss 回到下层应用；不进会话池，关闭即释放）
    var isDetailSheet = false
    var onClose: (() -> Void)?
    /// 最小化（压后台）：dismiss 但插件层保活本容器，重开同应用秒恢复
    var onMinimize: (() -> Void)?
    /// 用户点击「查看详情与评价」，由插件层通知 JS 跳转站内详情页
    var onDetail: ((String) -> Void)?
    /// 可信页面请求宿主代为签发一次性 SSO code；宿主不会向页面暴露自身 token。
    var onAuthorizationRequest: ((String, String, [String: Any]) -> Void)?

    /// 会话去重 / 定位键：优先 appId，无则用 URL（与插件层 sessionKey 一致）
    var sessionKey: String {
        if let id = appInfo?.id, !id.isEmpty { return id }
        return url?.absoluteString ?? ""
    }

    /// 导出给 JS 的会话摘要（后台「正在运行」列表渲染用）
    func sessionInfo() -> [String: Any] {
        let name = appInfo?.name ?? ""
        let resolvedName = !name.isEmpty
            ? name
            : (!customTitle.isEmpty ? customTitle : (webView?.url?.host ?? url?.host ?? ""))
        return [
            "id": appInfo?.id ?? "",
            "key": sessionKey,
            "name": resolvedName,
            "emoji": appInfo?.emoji ?? "",
            "logo": appInfo?.logo ?? "",
            "themeColor": appInfo?.themeColor ?? "",
            "url": (webView?.url ?? url)?.absoluteString ?? "",
            "title": webView?.title ?? customTitle,
            "displayMode": displayMode.rawValue,
        ]
    }

    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var backButton: UIButton!
    /// 沉浸模式的悬浮胶囊（更多 | 关闭）；标题栏模式为 nil
    private var capsule: UIView?
    /// 标题栏模式的单个「更多」菜单按钮（点开展开面板，「结束」移入其中）；沉浸模式为 nil
    private var menuButton: UIButton?
    /// 标题栏模式左上角「最小化（压后台）」按钮；沉浸模式为 nil（由胶囊关闭键处理）
    private var minimizeButton: UIButton?
    /// 当前右上角控件（capsule 或 menuButton 之一），共享约束 / 避让矩形计算
    private var rightControl: UIView!
    private var rightControlTopConstraint: NSLayoutConstraint!
    /// webView / 进度条顶部锚点（标题栏隐藏时在「贴栏底」与「贴屏顶」之间切换）
    private var webViewTopConstraint: NSLayoutConstraint!
    private var progressTopConstraint: NSLayoutConstraint!
    private var capsuleDragStartConstant: CGFloat = 6
    private var lastOffsetY: CGFloat = 0
    private var overlayHidden = false
    /// 标题栏模式下的顶部导航栏（沉浸模式为 nil）
    private var titleBar: UIView?
    private var titleLabel: UILabel?
    /// 标题栏是否可见（仅标题栏模式有意义；页面经 JSAPI 切换，会话内持久，不随导航重置）
    private var titleBarVisible = true
    /// 页面通过 JSAPI 主动隐藏了胶囊（每次主文档导航重置；仅沉浸模式可触发）
    private var capsuleHiddenByPage = false
    /// 标题栏配色：套用应用主题色时为 true（前景转白/黑、状态栏与发丝线适配）
    private var barIsThemed = false
    private var barBackgroundColor: UIColor = .systemBackground
    private var barForegroundColor: UIColor = .label
    private var statusBarStyle: UIStatusBarStyle = .default
    private var progressObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private struct PendingAuthorization {
        let reply: (Any?, String?) -> Void
        let timeout: DispatchWorkItem
        let request: [String: Any]
    }
    private var pendingAuthorizations: [String: PendingAuthorization] = [:]
    private var systemAuthenticationSession: ASWebAuthenticationSession?
    private var systemAuthorization: NativeSsoSystemAuthorization?

    /// 标题栏内容区高度（safe-area 顶部以下）
    private static let titleBarContentHeight: CGFloat = 44

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        modalPresentationCapturesStatusBarAppearance = true
        configureBarColors() // 解析主题色，定下标题栏前/背景色与状态栏样式
        if displayMode == .titlebar {
            setupTitleBar() // 先建栏，webView 顶部锚点依赖它
        }
        setupWebView()
        setupOverlay()
        setNeedsStatusBarAppearanceUpdate()
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }

    /// 解析应用主题色，定下标题栏前/背景色与状态栏样式。
    /// 有合法 themeColor 时套用为顶栏底色并按亮度选黑/白前景；否则回退系统背景。
    /// 状态栏适配仅标题栏模式生效（沉浸模式无顶栏，状态栏交给页面）。
    private func configureBarColors() {
        guard let themed = UIColor(hex: appInfo?.themeColor ?? "") else {
            barIsThemed = false
            barBackgroundColor = .systemBackground
            barForegroundColor = .label
            statusBarStyle = .default
            return
        }
        barIsThemed = true
        barBackgroundColor = themed
        barForegroundColor = themed.isLight ? UIColor(white: 0.12, alpha: 1) : .white
        statusBarStyle = displayMode == .titlebar
            ? (themed.isLight ? .darkContent : .lightContent)
            : .default
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        setupJSBridge(config.userContentController)

        webView = WKWebView(frame: .zero, configuration: config)
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        // WKWebView 默认 isOpaque，在首帧内容绘制前会先铺一层不透明白底，
        // 暗色模式 / 深色页面下表现为打开瞬间白闪；改为透明并以系统背景色兜底
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        view.addSubview(webView)

        // 沉浸：顶部到屏幕最顶；标题栏：顶部从导航栏底下开始。底部都铺到屏幕最底
        webViewTopConstraint = titleBar.map { webView.topAnchor.constraint(equalTo: $0.bottomAnchor) }
            ?? webView.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            webViewTopConstraint,
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                let p = Float(webView.estimatedProgress)
                self?.progressView.progress = p
                self?.progressView.isHidden = p >= 1.0
            }
        }

        canGoBackObservation = webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.backButton.isHidden = !webView.canGoBack
            }
        }

        if displayMode == .immersive {
            // 滚动方向感知：下滑浏览内容时胶囊滑出屏幕，上滑或回到顶部时恢复（标题栏模式顶栏固定不隐藏）
            contentOffsetObservation = webView.scrollView.observe(\.contentOffset, options: .new) { [weak self] scrollView, _ in
                DispatchQueue.main.async {
                    self?.handleScroll(scrollView)
                }
            }
        }

        if displayMode == .titlebar, customTitle.isEmpty {
            // 未传应用名时回退页面 <title>，随导航更新
            titleObservation = webView.observe(\.title, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.titleLabel?.text = webView.title
                }
            }
        }
    }

    /// 标题栏模式的顶部导航栏：占满 safe-area 顶部 + 44pt 内容区，
    /// 系统背景色 + 发丝线分隔，标题居中（返回键 / 胶囊仍由 setupOverlay 摆放）
    private func setupTitleBar() {
        let bar = UIView()
        bar.backgroundColor = barBackgroundColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let hairline = UIView()
        // 套用主题色时用前景色淡描边分隔，否则系统分隔线
        hairline.backgroundColor = barIsThemed ? barForegroundColor.withAlphaComponent(0.18) : .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)

        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = barForegroundColor
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.text = customTitle
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)

        // 标题尽量居中，两侧给返回键（左 52pt）与胶囊（右 12+88+8pt）让位
        let centerX = label.centerXAnchor.constraint(equalTo: bar.centerXAnchor)
        centerX.priority = .defaultHigh

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.titleBarContentHeight),

            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),

            centerX,
            label.centerYAnchor.constraint(
                equalTo: bar.bottomAnchor, constant: -Self.titleBarContentHeight / 2),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: bar.leadingAnchor, constant: 52),
            label.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -108),
        ])

        // 应用容器（非详情 sheet）：点标题进站内详情页
        if !isDetailSheet, appInfo != nil {
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
        }

        titleBar = bar
        titleLabel = label
    }

    /// 注入给页面的宿主 JSAPI（window.ylf）。
    /// 传输层只有一条 invoke(method, params) -> Promise 通道（基于 WKScriptMessageHandlerWithReply，
    /// 原生 replyHandler 直接驱动 Promise resolve/reject），具名方法都是其上的薄糖衣；
    /// 后续新增能力只需在 handleJSAPI 加 case，无需改传输层。
    private func setupJSBridge(_ controller: WKUserContentController) {
        controller.addScriptMessageHandler(
            WeakScriptMessageHandler(delegate: self), contentWorld: .page, name: "ylf")
        let script = """
        (function () {
          if (window.ylf) { return }
          function invoke(method, params) {
            return window.webkit.messageHandlers.ylf.postMessage({ method: method, params: params || {} })
          }
          window.ylf = {
            version: 5,
            inYunleApp: true,
            invoke: invoke,
            canIUse: function (method) { return invoke('canIUse', { method: method }) },
            authorize: function (params) { return invoke('authorize', params) },
            getEnv: function () { return invoke('getEnv') },
            hideCapsule: function () { return invoke('setCapsuleVisible', { visible: false }) },
            showCapsule: function () { return invoke('setCapsuleVisible', { visible: true }) },
            hideTitleBar: function () { return invoke('setTitleBarVisible', { visible: false }) },
            showTitleBar: function () { return invoke('setTitleBarVisible', { visible: true }) },
            closeBrowser: function () { return invoke('close') },
            setClipboard: function (text) { return invoke('setClipboard', { text: text }) },
          }
        })()
        """
        controller.addUserScript(WKUserScript(
            source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func handleScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        defer { lastOffsetY = y }
        let delta = y - lastOffsetY

        if y <= 60 {
            // 接近页面顶部：始终显示
            setOverlayHidden(false)
        }
        else if delta > 4 {
            // 向下浏览内容：隐藏，减少遮挡
            setOverlayHidden(true)
        }
        else if delta < -4 {
            // 回滑：恢复显示
            setOverlayHidden(false)
        }
    }

    private func setOverlayHidden(_ hidden: Bool) {
        guard hidden != overlayHidden else { return }
        overlayHidden = hidden
        applyOverlayVisibility()
    }

    /// 页面通过 JSAPI 隐藏/恢复胶囊；主文档导航时自动恢复（见 didCommit）。
    /// 标题栏模式下顶栏（含胶囊）不允许页面隐藏，静默忽略
    private func setCapsuleHiddenByPage(_ hidden: Bool) {
        guard displayMode == .immersive else { return }
        guard hidden != capsuleHiddenByPage else { return }
        capsuleHiddenByPage = hidden
        applyOverlayVisibility()
    }

    private func applyOverlayVisibility() {
        let capsuleVisible = !overlayHidden && !capsuleHiddenByPage
        let backVisible = !overlayHidden

        rightControl.isUserInteractionEnabled = capsuleVisible
        backButton.isUserInteractionEnabled = backVisible

        UIView.animate(withDuration: 0.25) {
            let transform = self.overlayHidden ? CGAffineTransform(translationX: 0, y: -70) : .identity
            self.rightControl.transform = transform
            self.rightControl.alpha = capsuleVisible ? 1 : 0
            self.backButton.transform = transform
            self.backButton.alpha = backVisible ? 1 : 0
        }
    }

    private func setupOverlay() {
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .clear
        progressView.tintColor = UIColor(hex: appInfo?.themeColor ?? "") ?? .systemBlue
        progressView.isHidden = true
        view.addSubview(progressView)

        // 右上角控件：沉浸 = 胶囊（更多 | 关闭）；标题栏 = 单个「更多」菜单按钮（「结束」移入展开面板）
        if displayMode == .immersive {
            let c = makeCapsule()
            capsule = c
            rightControl = c
        }
        else {
            let m = makeMenuButton()
            menuButton = m
            rightControl = m
        }
        view.addSubview(rightControl)

        backButton = makeFloatingButton(icon: "chevron.left", pointSize: 14)
        backButton.isHidden = true
        backButton.addTarget(self, action: #selector(goBackTapped), for: .touchUpInside)
        view.addSubview(backButton)

        // 标题栏左上角常驻「最小化（压后台）」按钮；沉浸模式由胶囊关闭键兜底，不建
        if displayMode == .titlebar {
            let mb = makeFloatingButton(icon: "chevron.down", pointSize: 15)
            mb.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)
            minimizeButton = mb
            view.addSubview(mb)
        }
        applyBarButtonStyles()

        // 标题栏模式下各浮层按钮恰好落在栏的 44pt 内容区内（6 + 32 + 6）
        rightControlTopConstraint = rightControl.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6)

        // 沉浸：进度条贴 safe-area 顶；标题栏：贴导航栏底（页面内容顶部）
        progressTopConstraint = titleBar.map { progressView.topAnchor.constraint(equalTo: $0.bottomAnchor) }
            ?? progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)

        NSLayoutConstraint.activate([
            progressTopConstraint,
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            rightControlTopConstraint,
            rightControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            backButton.centerYAnchor.constraint(equalTo: rightControl.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        // 左侧布局：标题栏 = [最小化][返回]（返回随历史出现，紧跟最小化键右侧）；沉浸 = [返回] 贴最左
        if let minimizeButton = minimizeButton {
            NSLayoutConstraint.activate([
                minimizeButton.centerYAnchor.constraint(equalTo: rightControl.centerYAnchor),
                minimizeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                minimizeButton.widthAnchor.constraint(equalToConstant: 32),
                minimizeButton.heightAnchor.constraint(equalToConstant: 32),
                backButton.leadingAnchor.constraint(equalTo: minimizeButton.trailingAnchor, constant: 6),
            ])
        }
        else {
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12).isActive = true
        }

        // 单菜单按钮无固有尺寸，显式给 32×32（胶囊自带 88×32）
        if let menuButton = menuButton {
            NSLayoutConstraint.activate([
                menuButton.widthAnchor.constraint(equalToConstant: 32),
                menuButton.heightAnchor.constraint(equalToConstant: 32),
            ])
        }

        if displayMode == .immersive, let capsule = capsule {
            // 胶囊可上下拖动，避免挡住网页右上角的操作按钮（标题栏模式固定在栏内）
            let pan = UIPanGestureRecognizer(target: self, action: #selector(capsulePanned(_:)))
            capsule.addGestureRecognizer(pan)
        }
    }

    /// 顶栏浮层按钮材质（返回 / 最小化 / 更多）：嵌在实体标题栏内时素色（前景色着色、无背景），
    /// 悬浮态（沉浸模式，或标题栏 hideTitleBar 收起后）转暗色半透明圆钮，保证任意网页配色上可读
    private func applyBarButtonStyles() {
        [backButton, minimizeButton, menuButton].compactMap { $0 }.forEach(styleBarButton)
    }

    private func styleBarButton(_ button: UIButton) {
        let floating = displayMode == .immersive || !titleBarVisible
        if floating {
            button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            button.layer.borderWidth = 0.5
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            button.tintColor = .white
        }
        else {
            button.backgroundColor = .clear
            button.layer.borderWidth = 0
            button.tintColor = barForegroundColor
        }
    }

    /// 标题栏显隐（仅标题栏模式生效，沉浸模式静默 no-op）。
    /// 隐藏后退化为沉浸姿态：网页铺满到屏顶、返回键与「更多」菜单按钮转悬浮材质，
    /// 菜单按钮固定悬浮于右上角作为退出锚点（关闭在其展开面板内，故不重置每文档、
    /// 会话内持久）。先同步定版面再动画，确保 getEnv() 立即读到最终的
    /// capsuleRect / safeAreaInsets。
    private func setTitleBarVisible(_ visible: Bool) {
        guard displayMode == .titlebar, let bar = titleBar, visible != titleBarVisible else { return }
        titleBarVisible = visible

        webViewTopConstraint.isActive = false
        webViewTopConstraint = webView.topAnchor.constraint(
            equalTo: visible ? bar.bottomAnchor : view.topAnchor)
        webViewTopConstraint.isActive = true

        progressTopConstraint.isActive = false
        progressTopConstraint = progressView.topAnchor.constraint(
            equalTo: visible ? bar.bottomAnchor : view.safeAreaLayoutGuide.topAnchor)
        progressTopConstraint.isActive = true

        applyBarButtonStyles()
        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.25) {
            bar.alpha = visible ? 1 : 0
            bar.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: -bar.bounds.height)
        }
    }

    @objc private func capsulePanned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            capsuleDragStartConstant = rightControlTopConstraint.constant
        case .changed:
            let translation = gesture.translation(in: view).y
            let maxConstant = view.bounds.height
                - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 80
            rightControlTopConstraint.constant = min(max(capsuleDragStartConstant + translation, 6), maxConstant)
        default:
            break
        }
    }

    /// 悬浮圆形按钮（与胶囊同材质：暗色半透明，不随浅色/深色模式变化）
    private func makeFloatingButton(icon: String, pointSize: CGFloat) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: icon, withConfiguration:
            UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// 标题栏右上角单个「更多」菜单按钮（点开展开面板；材质由 styleBarButton 决定）
    private func makeMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        return button
    }

    /// 仿微信小程序右上角胶囊按钮（悬浮于网页之上，暗色半透明）
    private func makeCapsule() -> UIView {
        let capsule = UIView()
        capsule.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        capsule.layer.cornerRadius = 16
        capsule.layer.borderWidth = 0.5
        capsule.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        capsule.translatesAutoresizingMaskIntoConstraints = false

        let moreButton = UIButton(type: .system)
        moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
        moreButton.tintColor = .white
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        divider.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        capsule.addSubview(moreButton)
        capsule.addSubview(divider)
        capsule.addSubview(closeButton)

        NSLayoutConstraint.activate([
            capsule.widthAnchor.constraint(equalToConstant: 88),
            capsule.heightAnchor.constraint(equalToConstant: 32),

            moreButton.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            moreButton.topAnchor.constraint(equalTo: capsule.topAnchor),
            moreButton.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            moreButton.trailingAnchor.constraint(equalTo: divider.leadingAnchor),

            divider.centerXAnchor.constraint(equalTo: capsule.centerXAnchor),
            divider.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 0.5),
            divider.heightAnchor.constraint(equalToConstant: 18),

            closeButton.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: capsule.topAnchor),
            closeButton.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            closeButton.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
        ])

        return capsule
    }

    // MARK: - Actions

    @objc private func goBackTapped() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    /// 结束（彻底释放）：收起容器并通知插件层释放本会话，下次打开全新开始
    @objc private func closeTapped() {
        dismiss(animated: true)
        onClose?()
    }

    /// 最小化（压后台）：收起容器但插件层保活，重开同应用秒恢复（彻底释放走「结束」）
    @objc private func minimizeTapped() {
        dismiss(animated: true)
        onMinimize?()
    }

    /// 点击标题栏应用名 → 打开站内详情页 sheet（不滚到评价区）
    @objc private func titleTapped() {
        presentAppDetail(scrollToReviews: false)
    }

    /// 打开站内应用详情页（含评分评价）为模态 sheet，盖在当前应用之上；
    /// 下滑 dismiss 即回到应用。详情页为远程第一方页面（apps.yunle.fun），JSAPI 自举登录。
    /// 自身 present、不进插件层会话池，dismiss 即释放。
    private func presentAppDetail(scrollToReviews: Bool) {
        guard let info = appInfo else { return }
        let key = info.slug.isEmpty ? info.id : info.slug
        guard !key.isEmpty else { return }
        var urlString = "https://apps.yunle.fun/app/\(key)"
        if scrollToReviews { urlString += "#reviews" }
        guard let url = URL(string: urlString) else { return }

        let detailVC = WebViewController()
        detailVC.url = url
        detailVC.appInfo = info
        detailVC.customTitle = info.name
        detailVC.displayMode = .titlebar
        detailVC.isDetailSheet = true
        detailVC.extraTrustedHosts = extraTrustedHosts
        // 默认 pageSheet：圆角卡片盖在应用之上，可下滑 dismiss 回到应用
        present(detailVC, animated: true)
    }

    @objc private func moreTapped() {
        let sheet = AppInfoSheetController()
        sheet.appInfo = appInfo
        sheet.currentURL = webView.url ?? url
        sheet.onShare = { [weak self] in self?.shareCurrent() }
        sheet.onOpenSafari = { [weak self] in
            if let u = self?.webView.url ?? self?.url {
                UIApplication.shared.open(u)
            }
        }
        sheet.onCopyLink = { [weak self] in
            UIPasteboard.general.string = (self?.webView.url ?? self?.url)?.absoluteString
        }
        sheet.onReload = { [weak self] in self?.webView.reload() }
        sheet.onClose = { [weak self] in self?.closeTapped() }
        // 详情页 sheet 内不再显示「查看详情」评分行（避免循环再弹详情）
        sheet.showRatingRow = !isDetailSheet
        // 评分行点击：收起 more 面板后，把站内详情页以 sheet 盖在应用之上（定位到评价区）
        sheet.onDetail = { [weak self] in
            self?.presentAppDetail(scrollToReviews: true)
        }

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium()]
            presentation.prefersGrabberVisible = true
            presentation.preferredCornerRadius = 20
        }
        present(sheet, animated: true)
    }

    private func shareCurrent() {
        guard let u = webView.url ?? url else { return }
        var items: [Any] = []
        if let name = appInfo?.name, !name.isEmpty {
            items.append("\(name) - 云乐坊")
        }
        items.append(u)
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = av.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(av, animated: true)
    }

    deinit {
        rejectPendingAuthorizations("browser closed")
        progressObservation?.invalidate()
        canGoBackObservation?.invalidate()
        contentOffsetObservation?.invalidate()
        titleObservation?.invalidate()
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "ylf", contentWorld: .page)
    }

    /// 由 Capacitor 宿主页回传一次性授权码；requestId 随机且仅在当前 WebView 生命周期有效。
    @discardableResult
    func resolveAuthorization(
        requestId: String,
        result: [String: Any]?,
        error: String?
    ) -> Bool {
        guard let pending = pendingAuthorizations.removeValue(forKey: requestId) else {
            return false
        }
        pending.timeout.cancel()
        if systemAuthorization?.requestId == requestId {
            systemAuthenticationSession?.cancel()
            systemAuthenticationSession = nil
            systemAuthorization = nil
        }
        if let error = error, !error.isEmpty {
            pending.reply(nil, error)
        }
        else {
            pending.reply(result ?? [:], nil)
        }
        return true
    }

    @discardableResult
    func beginOtherAccountAuthorization(requestId: String) -> Bool {
        guard systemAuthenticationSession == nil,
              let pending = pendingAuthorizations[requestId],
              let request = NativeSsoProtocol.readRequest(pending.request),
              let state = NativeSsoProtocol.randomState(),
              let authorizationURL = NativeSsoProtocol.authorizationURL(
                  request: request,
                  state: state)
        else {
            return false
        }

        let session = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: "yunlefun"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                guard let self = self,
                      self.systemAuthorization?.requestId == requestId
                else {
                    return
                }
                self.systemAuthenticationSession = nil
                self.systemAuthorization = nil
                if let callbackURL = callbackURL,
                   let result = NativeSsoProtocol.readCallback(
                       callbackURL,
                       expectedState: state,
                       request: request) {
                    switch result {
                    case let .success(code, issuer):
                        _ = self.resolveAuthorization(
                            requestId: requestId,
                            result: ["ok": true, "code": code, "issuer": issuer],
                            error: nil)
                    case .denied:
                        _ = self.resolveAuthorization(
                            requestId: requestId,
                            result: nil,
                            error: "HOST_AUTH_DENIED")
                    }
                }
                else {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    _ = self.resolveAuthorization(
                        requestId: requestId,
                        result: nil,
                        error: code == .canceledLogin
                            ? "HOST_AUTH_DENIED"
                            : "HOST_AUTH_FAILED")
                }
            }
        }
        session.presentationContextProvider = self
        guard session.start() else {
            return false
        }

        pending.timeout.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            _ = self?.resolveAuthorization(
                requestId: requestId,
                result: nil,
                error: "HOST_AUTH_FAILED")
        }
        pendingAuthorizations[requestId] = PendingAuthorization(
            reply: pending.reply,
            timeout: timeout,
            request: pending.request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
        systemAuthorization = NativeSsoSystemAuthorization(
            requestId: requestId,
            state: state,
            request: request)
        systemAuthenticationSession = session
        return true
    }

    func cancelPendingAuthorizations() {
        rejectPendingAuthorizations("browser closed")
    }

    func notifyHostIdentityChanged() {
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('ylf:identityChanged'))")
    }

    private func rejectPendingAuthorizations(_ reason: String) {
        systemAuthenticationSession?.cancel()
        systemAuthenticationSession = nil
        systemAuthorization = nil
        let pending = pendingAuthorizations
        pendingAuthorizations.removeAll()
        pending.values.forEach {
            $0.timeout.cancel()
            $0.reply(nil, reason)
        }
    }
}

extension WebViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}

private struct NativeSsoSystemAuthorization {
    let requestId: String
    let state: String
    let request: NativeSsoRequest
}

private struct NativeSsoRequest {
    let clientId: String
    let codeChallenge: String
    let nonce: String
    let redirectUri: String
    let scope: String
}

private enum NativeSsoResult {
    case success(code: String, issuer: String)
    case denied
}

private enum NativeSsoProtocol {
    private static let issuer = "https://www.yunle.fun"

    static func readRequest(_ input: [String: Any]) -> NativeSsoRequest? {
        guard let clientId = input["clientId"] as? String,
              let codeChallenge = input["codeChallenge"] as? String,
              let nonce = input["nonce"] as? String,
              let redirectUri = input["redirectUri"] as? String,
              let scopes = input["scope"] as? [String],
              scopes == ["identity:bootstrap"],
              input["codeChallengeMethod"] as? String == "S256",
              isClientId(clientId),
              isValue(codeChallenge),
              isValue(nonce),
              isSecureRedirect(redirectUri)
        else {
            return nil
        }
        return NativeSsoRequest(
            clientId: clientId,
            codeChallenge: codeChallenge,
            nonce: nonce,
            redirectUri: redirectUri,
            scope: scopes[0])
    }

    static func authorizationURL(request: NativeSsoRequest, state: String) -> URL? {
        guard isValue(state) else { return nil }
        let callback = "yunlefun://auth/sso?state=\(state)"
        var components = URLComponents(string: "\(issuer)/auth/sso")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: request.clientId),
            URLQueryItem(name: "redirect_uri", value: request.redirectUri),
            URLQueryItem(name: "scope", value: request.scope),
            URLQueryItem(name: "nonce", value: request.nonce),
            URLQueryItem(name: "code_challenge", value: request.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "native_callback_uri", value: callback),
        ]
        return components?.url
    }

    static func readCallback(
        _ callbackURL: URL,
        expectedState: String,
        request: NativeSsoRequest
    ) -> NativeSsoResult? {
        guard let callback = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false),
            callback.scheme == "yunlefun",
            callback.host == "auth",
            callback.path == "/sso",
            callback.fragment == nil,
            let items = callback.queryItems,
            items.count == 2,
            Set(items.map(\.name)) == Set(["state", "result"]),
            items.first(where: { $0.name == "state" })?.value == expectedState,
            let resultValue = items.first(where: { $0.name == "result" })?.value,
            let resultURL = URL(string: resultValue),
            var result = URLComponents(url: resultURL, resolvingAgainstBaseURL: false),
            let fragment = result.fragment,
            fragment.hasPrefix("ylf_sso="),
            !fragment.contains("&")
        else {
            return nil
        }
        result.fragment = nil
        guard result.url?.absoluteString == request.redirectUri else { return nil }

        let encoded = String(fragment.dropFirst("ylf_sso=".count))
        guard let data = decodeBase64Url(encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["nonce"] as? String == request.nonce,
              payload["iss"] as? String == issuer,
              payload["ticket"] == nil,
              payload["session"] == nil,
              payload["access_token"] == nil,
              payload["refresh_token"] == nil
        else {
            return nil
        }
        if payload["ok"] as? Bool == true,
           let code = payload["code"] as? String,
           isValue(code) {
            return .success(code: code, issuer: issuer)
        }
        return payload["ok"] as? Bool == false
            && payload["reason"] as? String == "access_denied"
            ? .denied
            : nil
    }

    static func randomState() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isClientId(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$",
            options: .regularExpression) != nil
    }

    private static func isValue(_ value: String) -> Bool {
        value.count == 43 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    private static func isSecureRedirect(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              !(components.host ?? "").isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            return false
        }
        return components.url?.absoluteString == value
    }

    private static func decodeBase64Url(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}

// MARK: - 页面 JSAPI 分发与鉴权

/// JSAPI 权限级别
enum JSAPIAccess {
    /// 无害 UI 控制能力，对所有页面开放
    case open
    /// 敏感能力，仅授信 host（内置第一方域 + 宿主按应用追加）可调用
    case trusted
}

extension WebViewController: WKScriptMessageHandlerWithReply {
    /// 方法注册表：新增能力在这里登记权限级别，并在 handleJSAPI 加 case
    private static var jsapiRegistry: [String: JSAPIAccess] {
        [
            "canIUse": .open,
            "getEnv": .open,
            "setCapsuleVisible": .open,
            "setTitleBarVisible": .open,
            "close": .open,
            "authorize": .trusted,
            "setClipboard": .trusted,
        ]
    }

    /// 内置授信的第一方可注册域（子域自动匹配）
    private static var firstPartyHosts: [String] {
        ["yunle.fun", "yunyoujun.cn"]
    }

    /// 来源是否授信：要求 https（本机调试地址除外），且 host 命中授信域或其子域。
    /// 基于 WKSecurityOrigin 判定（由 WebKit 进程注入，页面脚本无法伪造），
    /// 每条消息独立评估，文档内导航后自动按新源重新判定
    private func isTrustedOrigin(_ origin: WKSecurityOrigin) -> Bool {
        let host = origin.host.lowercased()
        let isLocalDev = host == "localhost" || host == "127.0.0.1"
        guard origin.protocol == "https" || isLocalDev else { return false }

        let allowed = Self.firstPartyHosts + extraTrustedHosts.map { $0.lowercased() }
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame else {
            replyHandler(nil, "forbidden: main frame only")
            return
        }
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String
        else {
            replyHandler(nil, "bad request: missing method")
            return
        }

        let trusted = isTrustedOrigin(message.frameInfo.securityOrigin)
        guard let access = Self.jsapiRegistry[method] else {
            replyHandler(nil, "unknown method: \(method)")
            return
        }
        guard access == .open || trusted else {
            replyHandler(nil, "permission denied: \(method) requires trusted host")
            return
        }
        handleJSAPI(
            method: method,
            params: body["params"] as? [String: Any] ?? [:],
            sourceOrigin: exactOrigin(message.frameInfo.securityOrigin),
            trusted: trusted,
            reply: replyHandler)
    }

    private func handleJSAPI(
        method: String,
        params: [String: Any],
        sourceOrigin: String?,
        trusted: Bool,
        reply: @escaping (Any?, String?) -> Void
    ) {
        switch method {
        case "canIUse":
            // 方法存在 + 当前来源有权调用，二合一应答，页面无需单独关心权限
            let access = Self.jsapiRegistry[params["method"] as? String ?? ""]
            reply(access == .open || (access == .trusted && trusted), nil)

        case "getEnv":
            // safeAreaInsets 取 webView 自身：沉浸模式与全屏等同；
            // 标题栏模式下视口从栏下开始，top 为 0，页面无需再避让状态栏
            reply([
                "platform": "ios",
                "appId": appInfo?.id ?? "",
                "displayMode": displayMode.rawValue,
                "trusted": trusted,
                "capsuleVisible": !capsuleHiddenByPage,
                // 标题栏当前是否在显示（沉浸模式恒为 false：无标题栏）
                "titleBarVisible": displayMode == .titlebar && titleBarVisible,
                "safeAreaInsets": [
                    "top": webView.safeAreaInsets.top,
                    "bottom": webView.safeAreaInsets.bottom,
                    "left": webView.safeAreaInsets.left,
                    "right": webView.safeAreaInsets.right,
                ],
                "capsuleRect": capsuleRectInPage(),
            ], nil)

        case "setCapsuleVisible":
            setCapsuleHiddenByPage(!(params["visible"] as? Bool ?? true))
            reply(nil, nil)

        case "setTitleBarVisible":
            // 仅标题栏模式生效，沉浸模式 no-op 但照常 resolve（页面无需分支）
            setTitleBarVisible(params["visible"] as? Bool ?? true)
            reply(nil, nil)

        case "close":
            closeTapped()
            reply(nil, nil)

        case "authorize":
            guard let sourceOrigin = sourceOrigin,
                  let onAuthorizationRequest = onAuthorizationRequest
            else {
                reply(nil, "authorization broker unavailable")
                return
            }
            let requestId = UUID().uuidString.lowercased()
            let timeout = DispatchWorkItem { [weak self] in
                _ = self?.resolveAuthorization(
                    requestId: requestId,
                    result: nil,
                    error: "authorization timed out")
            }
            pendingAuthorizations[requestId] = PendingAuthorization(
                reply: reply,
                timeout: timeout,
                request: params)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
            onAuthorizationRequest(requestId, sourceOrigin, params)

        case "setClipboard":
            guard let text = params["text"] as? String else {
                reply(nil, "bad request: missing text")
                return
            }
            UIPasteboard.general.string = text
            reply(nil, nil)

        default:
            reply(nil, "unknown method: \(method)")
        }
    }

    /// 把 WebKit 提供的安全源转换为严格 origin；默认端口省略，与 URL.origin 对齐。
    private func exactOrigin(_ origin: WKSecurityOrigin) -> String? {
        let scheme = origin.protocol.lowercased()
        let host = origin.host.lowercased()
        guard !scheme.isEmpty, !host.isEmpty else { return nil }
        let port = origin.port
        let defaultPort = (scheme == "https" && port == 443)
            || (scheme == "http" && port == 80)
            || port == 0
        return "\(scheme)://\(host)\(defaultPort ? "" : ":\(port)")"
    }

    /// 胶囊在页面视口坐标系中的布局位置（pt == CSS px），供沉浸页面避让；
    /// 滚动隐藏只是平移动画，需剔除 transform 取回布局值。
    /// 标题栏模式下胶囊位于视口上方（y 为负），页面按矩形避让自然判定无重叠
    private func capsuleRectInPage() -> [String: CGFloat] {
        var rect = rightControl.frame
        rect.origin.x -= rightControl.transform.tx
        rect.origin.y -= rightControl.transform.ty
        rect.origin.y -= webView.frame.minY
        return ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}

/// WKUserContentController 会强持有 handler，经弱引用代理转发以打破循环引用
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var delegate: WKScriptMessageHandlerWithReply?

    init(delegate: WKScriptMessageHandlerWithReply) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let delegate = delegate else {
            replyHandler(nil, "browser is gone")
            return
        }
        delegate.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        progressView.isHidden = false
        progressView.setProgress(0, animated: false)
    }

    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        // 胶囊隐藏仅对当前文档生效，跳转新页面自动恢复，避免页面把用户困在浏览器里
        setCapsuleHiddenByPage(false)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        progressView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        progressView.isHidden = true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // mailto / tel / 第三方 App scheme 交给系统处理
        if let scheme = targetURL.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            UIApplication.shared.open(targetURL)
            decisionHandler(.cancel)
            return
        }

        // 用户点击的跨站外链（含 target=_blank 新窗口）→ 按设置打开
        let isNewWindow = navigationAction.targetFrame == nil
        let isUserClick = navigationAction.navigationType == .linkActivated
        let isMainFrame = isNewWindow || navigationAction.targetFrame?.isMainFrame == true
        if (isUserClick || isNewWindow), isMainFrame, isCrossSite(targetURL) {
            switch externalLinkBehavior {
            case .defaultBrowser:
                UIApplication.shared.open(targetURL)
            case .safariView:
                // 沉浸视图之上弹系统浏览器视图，不跳出 App（与 @capacitor/browser 同为 SFSafariViewController）
                let safari = SFSafariViewController(url: targetURL)
                safari.preferredControlTintColor = UIColor(hex: appInfo?.themeColor ?? "")
                present(safari, animated: true)
            }
            decisionHandler(.cancel)
            return
        }

        // 同站的 target=_blank 继续在当前 WebView 打开
        if isNewWindow {
            webView.load(URLRequest(url: targetURL))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// 与应用初始域名是否跨站（按可注册域比较，子域之间视为同站）
    private func isCrossSite(_ target: URL) -> Bool {
        guard let targetHost = target.host?.lowercased(),
              let appHost = url?.host?.lowercased()
        else { return false }
        return registrableDomain(of: targetHost) != registrableDomain(of: appHost)
    }

    /// 取主机的可注册域（如 example.com / example.com.cn）；
    /// 不引入完整 Public Suffix List，仅覆盖常见两段式后缀
    private func registrableDomain(of host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let secondLevelSuffixes: Set<String> = [
            "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
            "co.uk", "org.uk", "co.jp", "com.hk", "com.tw", "com.au",
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let count = secondLevelSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(count).joined(separator: ".")
    }
}

// MARK: - 应用详情半屏面板（仿小程序「更多」面板）

class AppInfoSheetController: UIViewController {
    var appInfo: WebAppInfo?
    var currentURL: URL?
    var onShare: (() -> Void)?
    var onCopyLink: (() -> Void)?
    var onOpenSafari: (() -> Void)?
    var onReload: (() -> Void)?
    var onClose: (() -> Void)?
    var onDetail: (() -> Void)?
    /// 是否显示评分行（= 查看详情入口）；详情页 sheet 内隐藏，避免循环再弹详情
    var showRatingRow = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        stack.addArrangedSubview(makeHeader())
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        if let desc = appInfo?.description, !desc.isEmpty {
            let descLabel = UILabel()
            descLabel.text = desc
            descLabel.font = .systemFont(ofSize: 13)
            descLabel.textColor = .secondaryLabel
            descLabel.numberOfLines = 2
            stack.addArrangedSubview(descLabel)
            stack.setCustomSpacing(14, after: descLabel)
        }

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(6, after: divider)

        // 操作行
        stack.addArrangedSubview(makeActionRow(icon: "square.and.arrow.up", title: "分享") { [weak self] in
            self?.dismissThen { self?.onShare?() }
        })
        stack.addArrangedSubview(makeActionRow(icon: "link", title: "复制链接") { [weak self] in
            self?.onCopyLink?()
            self?.dismiss(animated: true)
        })
        stack.addArrangedSubview(makeActionRow(icon: "safari", title: "在 Safari 中打开") { [weak self] in
            self?.dismissThen { self?.onOpenSafari?() }
        })
        stack.addArrangedSubview(makeActionRow(icon: "arrow.clockwise", title: "刷新") { [weak self] in
            self?.onReload?()
            self?.dismiss(animated: true)
        })

        // 「结束」彻底释放会话（左上角是「最小化」压后台保活，此处才是真正关闭）
        let exitDivider = UIView()
        exitDivider.backgroundColor = .separator
        exitDivider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(exitDivider)
        stack.setCustomSpacing(6, after: exitDivider)

        stack.addArrangedSubview(makeActionRow(icon: "xmark", title: "结束") { [weak self] in
            self?.dismissThen { self?.onClose?() }
        })
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        // 分享/Safari 由父控制器 present，先收起本面板
        dismiss(animated: true, completion: action)
    }

    // MARK: 头部：图标 + 名称 + 评分

    private func makeHeader() -> UIView {
        let container = UIView()

        // 图标：logo 优先，否则 emoji + 主题色背景
        let iconView = UIView()
        iconView.layer.cornerRadius = 12
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.backgroundColor = UIColor(hex: appInfo?.themeColor ?? "") ?? .systemBlue

        if let logo = appInfo?.logo, let logoURL = URL(string: logo), !logo.isEmpty {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.translatesAutoresizingMaskIntoConstraints = false
            iconView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: iconView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: iconView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor),
            ])
            URLSession.shared.dataTask(with: logoURL) { data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { imageView.image = image }
            }.resume()
        }
        else {
            let emojiLabel = UILabel()
            emojiLabel.text = appInfo?.emoji ?? "🌐"
            emojiLabel.font = .systemFont(ofSize: 26)
            emojiLabel.translatesAutoresizingMaskIntoConstraints = false
            iconView.addSubview(emojiLabel)
            NSLayoutConstraint.activate([
                emojiLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
                emojiLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            ])
        }

        let nameLabel = UILabel()
        nameLabel.text = appInfo?.name.isEmpty == false ? appInfo?.name : (currentURL?.host ?? "")
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let metaLabel = UILabel()
        metaLabel.font = .systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabel
        var metaParts: [String] = []
        if let category = appInfo?.category, !category.isEmpty {
            metaParts.append(category)
        }
        if let downloads = appInfo?.downloads, !downloads.isEmpty {
            metaParts.append("\(downloads) 次使用")
        }
        metaLabel.text = metaParts.joined(separator: " · ")

        let ratingView = showRatingRow ? makeRatingView() : nil

        let textStack = UIStackView(arrangedSubviews: [nameLabel, metaLabel, ratingView].compactMap { $0 })
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            textStack.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])

        return container
    }

    /// 评分行：整行可点击，跳转站内详情页（含评价区）
    private func makeRatingView() -> UIView? {
        guard let info = appInfo, !info.id.isEmpty else { return nil }

        let rating = info.rating
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.isUserInteractionEnabled = false

        if rating > 0 {
            let starConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let fullStars = Int(rating)
            let hasHalf = rating - Double(fullStars) >= 0.5

            for i in 0..<5 {
                let star = UIImageView()
                star.tintColor = .systemOrange
                star.contentMode = .scaleAspectFit
                // 固定尺寸，避免被 StackView 拉伸变形
                star.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    star.widthAnchor.constraint(equalToConstant: 14),
                    star.heightAnchor.constraint(equalToConstant: 14),
                ])
                if i < fullStars {
                    star.image = UIImage(systemName: "star.fill", withConfiguration: starConfig)
                }
                else if i == fullStars && hasHalf {
                    star.image = UIImage(systemName: "star.leadinghalf.filled", withConfiguration: starConfig)
                }
                else {
                    star.image = UIImage(systemName: "star", withConfiguration: starConfig)
                }
                stack.addArrangedSubview(star)
            }

            let scoreLabel = UILabel()
            scoreLabel.text = String(format: rating.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", rating)
            scoreLabel.font = .systemFont(ofSize: 12, weight: .medium)
            scoreLabel.textColor = .secondaryLabel
            stack.addArrangedSubview(scoreLabel)
            stack.setCustomSpacing(5, after: stack.arrangedSubviews[4])
        }

        // 评价数 / 引导文案
        let countLabel = UILabel()
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        if info.ratingCount > 0 {
            countLabel.text = rating > 0 ? "· 共 \(info.ratingCount) 条评价" : "共 \(info.ratingCount) 条评价"
        }
        else if info.ratingCount == 0 {
            countLabel.text = "暂无评价，去写第一条"
        }
        else {
            countLabel.text = rating > 0 ? "· 查看评价" : "查看评价"
        }
        stack.addArrangedSubview(countLabel)
        if stack.arrangedSubviews.count > 1 {
            stack.setCustomSpacing(4, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        }

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        stack.addArrangedSubview(chevron)
        stack.setCustomSpacing(3, after: countLabel)

        // 包一层 control 作为点击热区
        let control = ActionRowControl()
        control.rowAction = { [weak self] in
            self?.dismiss(animated: true) { self?.onDetail?() }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(stack)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.heightAnchor.constraint(equalToConstant: 24),
        ])

        return control
    }

    // MARK: 操作行

    private func makeActionRow(icon: String, title: String, action: @escaping () -> Void) -> UIView {
        let control = ActionRowControl()
        control.rowAction = action
        control.translatesAutoresizingMaskIntoConstraints = false

        // 固定宽度图标列：各 SF Symbol 字形宽度不一，统一居中到 24pt 列内，保证各行标题左缘对齐
        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)))
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        control.addSubview(iconView)
        control.addSubview(label)

        NSLayoutConstraint.activate([
            control.heightAnchor.constraint(equalToConstant: 44),

            iconView.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor, constant: -4),
        ])

        return control
    }
}

/// 携带闭包的点击热区（评分行用）
class ActionRowControl: UIControl {
    var rowAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    @objc private func fire() {
        rowAction?()
    }
}

// MARK: - UIColor hex extension

extension UIColor {
    /// sRGB 近似相对亮度 > 0.6 视为浅色（其上前景应用深色文字 / 状态栏深色内容）
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return true }
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }

    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard !clean.isEmpty, Scanner(string: clean).scanHexInt64(&value) else { return nil }
        let a, r, g, b: UInt64
        switch clean.count {
        case 3:
            (a, r, g, b) = (255, (value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8:
            (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            return nil
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
