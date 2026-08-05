package `fun`.yunle.apps

import android.os.Bundle
import com.getcapacitor.BridgeActivity

class MainActivity : BridgeActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        registerPlugin(HostRuntimePlugin::class.java)
        super.onCreate(savedInstanceState)
    }
}
