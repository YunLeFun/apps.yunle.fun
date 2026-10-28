import SwiftUI
import YunleSupportUI

/// Account-scoped Support cookies remain owned and revoked by the host App.
struct SupportBrowserView: View {
    let page: SupportBrowserPage

    var body: some View {
        SupportBrowser(url: page.url, cookies: page.access?.cookies ?? [])
    }
}
