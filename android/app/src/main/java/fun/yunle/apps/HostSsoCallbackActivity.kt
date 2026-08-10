package `fun`.yunle.apps

import android.app.Activity
import android.os.Bundle

/** Receives only state-bound SSO or external OAuth results for the active host session. */
class HostSsoCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        HostRuntimePlugin.instance()?.deliverSystemAuthorizationCallback(intent?.data)
        finish()
    }
}
