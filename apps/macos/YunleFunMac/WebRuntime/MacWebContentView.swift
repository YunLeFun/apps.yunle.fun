import SwiftUI
import WebKit

/// SwiftUI owns the selection; the runtime owns WebKit's lifetime. Detaching the
/// representable when returning to the catalogue must not discard a live page.
struct MacWebContentView: NSViewRepresentable {
    @ObservedObject var runtime: MacWebRuntime

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let webView = runtime.webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
