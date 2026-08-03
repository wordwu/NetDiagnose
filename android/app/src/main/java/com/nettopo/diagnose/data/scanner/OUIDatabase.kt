package com.nettopo.diagnose.data.scanner

import android.content.Context
import org.json.JSONObject

/**
 * IEEE 全量 MAC 厂商库（约 4 万条，存于 assets/oui.json）
 * 首次使用时从 assets 加载，之后常驻内存。
 */
object OUIDatabase {
    private var entries: Map<String, String>? = null

    fun init(context: Context) {
        if (entries != null) return
        try {
            val text = context.assets.open("oui.json").bufferedReader().use { it.readText() }
            val obj = JSONObject(text)
            val map = HashMap<String, String>(obj.length())
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                map[k] = obj.getString(k)
            }
            entries = map
        } catch (_: Exception) {
            entries = emptyMap()
        }
    }

    fun lookup(mac: String): String? {
        val oui = mac.uppercase().filter { it in "0123456789ABCDEF" }.take(6)
        if (oui.length < 6) return null
        return entries?.get(oui)
    }
}
