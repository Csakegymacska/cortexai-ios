package eu.cortex.ai

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.util.concurrent.TimeUnit

/** A Cortex szerver API — ugyanazok a végpontok, mint az iOS appban. */
object Api {
    const val BASE = "https://cortanime.eu"

    lateinit var client: OkHttpClient
    var apiKey: String = ""

    fun init(prefsCookieJar: PrefsCookieJar) {
        client = OkHttpClient.Builder()
            .cookieJar(prefsCookieJar)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .build()
    }

    private fun json(path: String, body: JSONObject? = null, method: String = if (body == null) "GET" else "POST"): Pair<Int, JSONObject> {
        val req = Request.Builder().url(BASE + path)
        if (apiKey.isNotEmpty()) req.header("Authorization", "Bearer $apiKey")
        req.header("User-Agent", "CortexApp/1.0")
        val media = "application/json; charset=utf-8".toMediaType()
        if (body != null) req.method(method, body.toString().toRequestBody(media))
        else if (method != "GET") req.method(method, ByteArray(0).toRequestBody(null))
        client.newCall(req.build()).execute().use { resp ->
            val text = resp.body?.string() ?: "{}"
            val obj = try { JSONObject(text) } catch (_: Exception) { JSONObject() }
            return resp.code to obj
        }
    }

    // ── fiók ──
    fun login(email: String, password: String): JSONObject? {
        val (code, obj) = json("/api/auth/login", JSONObject().put("email", email).put("password", password))
        return if (code in 200..299) obj.optJSONObject("user") else null
    }

    fun register(username: String, email: String, password: String): JSONObject? {
        val body = JSONObject().put("username", username).put("email", email).put("password", password)
        val (code, obj) = json("/api/auth/register", body)
        return if (code in 200..299) obj.optJSONObject("user") else null
    }

    fun me(): JSONObject? {
        val (code, obj) = json("/api/auth/me")
        return if (code == 200) obj.optJSONObject("user") else null
    }

    fun logout() { json("/api/auth/logout", method = "POST") }

    fun errorOf(obj: JSONObject): String =
        obj.optString("error").ifEmpty { obj.optString("message", "Ismeretlen hiba") }

    // ── előfizetés ──
    fun subStatus(): JSONObject? {
        val (code, obj) = json("/api/sub/status")
        return if (code == 200) obj else null
    }

    fun redeem(code: String): JSONObject = json("/api/sub/redeem", JSONObject().put("code", code)).second

    // ── profilkép ──
    fun uploadAvatar(base64: String): Boolean {
        val (_, obj) = json("/api/me/avatar", JSONObject().put("image", base64))
        return obj.optBoolean("ok")
    }

    // ── AI-profil ──
    fun aiProfile(): JSONObject? {
        val (code, obj) = json("/api/me/ai")
        return if (code == 200) obj else null
    }

    fun saveAiProfile(name: String, persona: String, style: String): Boolean {
        val body = JSONObject().put("ai_name", name).put("persona", persona).put("style", style)
        val (_, obj) = json("/api/me/ai", body, method = "PUT")
        return obj.optBoolean("ok")
    }

    // ── chat (SSE) ──
    /** Egy válasz kérése stream-ben; a deltákat a hívó kapja. */
    fun chatStream(tier: String, messages: JSONArray, onDelta: (String) -> Unit): String {
        val body = JSONObject()
            .put("messages", messages)
            .put("tier", tier)
            .put("stream", true)
        val req = Request.Builder().url("$BASE/api/cortexai/chat")
            .header("Content-Type", "application/json")
            .header("User-Agent", "CortexApp/1.0")
            .header("Accept", "text/event-stream")
            .post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
            .build()
        val sb = StringBuilder()
        client.newCall(req).execute().use { resp ->
            val reader = resp.body?.source()?.inputStream()?.bufferedReader() ?: return@use
            readSSE(reader) { event, data ->
                when (event) {
                    "delta" -> {
                        val t = JSONObject(data).optString("text", "")
                        sb.append(t)
                        onDelta(t)
                    }
                    else -> {}
                }
            }
        }
        return sb.toString()
    }

    /** Egyszerű SSE-olvasó: `event:` + `data:` sorokat ad tovább. */
    private fun readSSE(reader: BufferedReader, onEvent: (String, String) -> Unit) {
        var event = "message"
        val data = StringBuilder()
        reader.forEachLine { line ->
            when {
                line.startsWith("event:") -> event = line.removePrefix("event:").trim()
                line.startsWith("data:") -> data.append(line.removePrefix("data:").trim()).append('\n')
                line.isEmpty() -> {
                    if (data.isNotEmpty()) onEvent(event, data.toString().trim())
                    event = "message"
                    data.clear()
                }
            }
        }
    }
}
