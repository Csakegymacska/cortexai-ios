package eu.cortex.ai

import android.content.Context
import android.content.SharedPreferences
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Persistent cookie jar — a bejelentkezés újraindítás után is megmarad. */
class PrefsCookieJar(context: Context) : CookieJar {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("cx.cookies", Context.MODE_PRIVATE)

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val edit = prefs.edit()
        for (c in cookies) {
            edit.putString("${c.name}@${c.domain}", c.toString())
        }
        edit.apply()
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        return prefs.all.values.mapNotNull { raw ->
            try {
                Cookie.parse(url, raw as String)
            } catch (_: Exception) {
                null
            }
        }.filter { it.matches(url) }
    }

    fun clear() = prefs.edit().clear().apply()
}
