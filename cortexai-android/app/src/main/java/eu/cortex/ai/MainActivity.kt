package eu.cortex.ai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import eu.cortex.ai.ui.CortexTheme
import kotlinx.coroutines.launch

enum class Screen { Chat, Login, Subscription, Settings }

class MainActivity : ComponentActivity() {

    var screen by mutableStateOf(Screen.Chat)
    var userName by mutableStateOf("")
    var userEmail by mutableStateOf("")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val jar = PrefsCookieJar(applicationContext)
        Api.init(jar)
        Api.apiKey = getSharedPreferences("cx.prefs", MODE_PRIVATE).getString("apiKey", "") ?: ""

        setContent {
            CortexTheme {
                CortexApp(activity = this)
            }
        }

        // Munkamenet visszatöltése induláskor — a bejelentkezés megmarad.
        lifecycleScope.launch {
            val u = runCatching { Api.me() }.getOrNull()
            if (u != null) {
                userName = u.optString("username")
                userEmail = u.optString("email")
            }
        }
    }

    fun signedIn(name: String, email: String) {
        userName = name
        userEmail = email
        screen = Screen.Chat
    }

    fun signedOut() {
        userName = ""
        userEmail = ""
        screen = Screen.Login
    }
}
