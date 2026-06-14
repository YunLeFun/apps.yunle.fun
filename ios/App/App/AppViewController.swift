import Capacitor
import UIKit

/// 自定义 Bridge 控制器：在这里用代码注册 App 内置的 Capacitor 插件。
/// 不能依赖 capacitor.config.json 的 packageClassList —— 它由 `cap sync` 自动生成，
/// 手动添加的条目每次同步都会被抹掉。
class AppViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(InAppWebViewPlugin())
    }
}
