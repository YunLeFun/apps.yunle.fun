package `fun`.yunle.apps

import android.app.Activity
import android.os.Bundle

/** Receives only the state-bound result emitted by the Yunle SSO Provider. */
class HostSsoCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        HostRuntimePlugin.instance()?.deliverSystemAuthorizationCallback(intent?.data)
        finish()
    }
}
