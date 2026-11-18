package `fun`.yunle.apps

import org.json.JSONObject

internal fun JSONObject.readString(key: String): String? = opt(key) as? String
