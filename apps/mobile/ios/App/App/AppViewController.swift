import Capacitor
import UIKit
import WebKit
import YunlefunCapacitorStorekit

private struct LocalPagePresentation {
    let routePath: String
    let kind: String
    let target: String?
}

/// 自定义 Bridge 控制器：在这里用代码注册 App 内置的 Capacitor 插件。
/// 不能依赖 capacitor.config.json 的 packageClassList —— 它由 `cap sync` 自动生成，
/// 手动添加的条目每次同步都会被抹掉。
class AppViewController: CAPBridgeViewController, WKScriptMessageHandler {
    private static let detailSheetHandlerName = "ylfDetailSheet"
    private var localPagePresentation: LocalPagePresentation?

    /// 将同一份 bundled Nuxt 应用作为独立详情 sheet 启动。
    ///
    /// Capacitor 启动时必须先加载真实存在的 index.html，不能把动态路由直接设为
    /// appStartPath；因此在 document-start 阶段用 history.replaceState 写入目标路由，
    /// 让 Nuxt 首次解析地址时直接进入详情页，同时不产生一次主壳路由跳转。
    func configureLocalDetail(routePath: String, target: String?) {
        configureLocalPage(routePath: routePath, kind: "app-detail-sheet", target: target)
    }

    /// 将 bundled Nuxt 的任意第一方路由作为独立 sheet 启动。
    func configureLocalPage(routePath: String, kind: String, target: String? = nil) {
        precondition(!isViewLoaded, "Local page presentation must be configured before loading the view")
        localPagePresentation = LocalPagePresentation(routePath: routePath, kind: kind, target: target)
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(HostRuntimePlugin())
        bridge?.registerPluginInstance(StorekitPlugin())
        installLocalDetailPresentation()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard localPagePresentation != nil,
              message.name == Self.detailSheetHandlerName,
              message.body as? String == "close"
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private static func jsonLiteral(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    private func installLocalDetailPresentation() {
        guard let presentation = localPagePresentation,
              let userContentController = webView?.configuration.userContentController
        else { return }

        userContentController.add(
            WeakLocalDetailSheetMessageHandler(delegate: self),
            name: Self.detailSheetHandlerName)

        let context: [String: Any] = [
            "version": 1,
            "kind": presentation.kind,
            "target": presentation.target ?? NSNull(),
        ]
        guard let routeJSON = Self.jsonLiteral(presentation.routePath),
              let contextJSON = Self.jsonLiteral(context)
        else { return }

        let script = """
        (function () {
          window.__YLF_NATIVE_PRESENTATION__ = Object.assign(\(contextJSON), {
            close: function () {
              window.webkit.messageHandlers.\(Self.detailSheetHandlerName).postMessage('close')
            }
          })
          window.history.replaceState(null, '', \(routeJSON))
        })()
        """
        userContentController.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
    }
}

/// WKUserContentController 会强持有 handler；用弱代理避免详情 sheet 释放后形成循环引用。
private final class WeakLocalDetailSheetMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
