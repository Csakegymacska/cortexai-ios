package eu.cortex.ai

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import eu.cortex.ai.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun CortexApp(activity: MainActivity) {
    Scaffold(
        containerColor = Ink,
        bottomBar = {
            NavigationBar(containerColor = InkSurface) {
                listOf(
                    Triple(Screen.Chat, Icons.Default.Chat, "Chat"),
                    Triple(Screen.Subscription, Icons.Default.CreditCard, "Subscription"),
                    Triple(Screen.Settings, Icons.Default.Settings, "Settings"),
                ).forEach { (scr, icon, label) ->
                    NavigationBarItem(
                        selected = activity.screen == scr,
                        onClick = { activity.screen = scr },
                        icon = { Icon(icon, contentDescription = label) },
                        label = { Text(label, fontSize = 11.sp) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = VioletSoft,
                            selectedTextColor = VioletSoft,
                            unselectedIconColor = TextFaint,
                            unselectedTextColor = TextFaint,
                            indicatorColor = Violet.copy(alpha = 0.16f),
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (activity.screen) {
                Screen.Chat -> ChatScreen()
                Screen.Login -> LoginScreen(activity)
                Screen.Subscription -> SubscriptionScreen()
                Screen.Settings -> SettingsScreen(activity)
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────── Chat

data class Msg(val role: String, var text: String)

@Composable
fun ChatScreen() {
    val scope = rememberCoroutineScope()
    val messages = remember { mutableStateListOf(Msg("assistant", "Szia! A Cortex vagyok — kérdezz bármit, vagy kérj képet: „kép: …”.")) }
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    fun send() {
        val text = input.trim()
        if (text.isEmpty() || busy) return
        input = ""
        messages.add(Msg("user", text))
        val wantsImage = text.lowercase().let {
            it.startsWith("kép:") || it.startsWith("kep:") || it.startsWith("image:") ||
                (it.contains("kép") && (it.contains("generál") || it.contains("rajzol"))) ||
                it.contains("draw me") || it.contains("generate an image")
        }
        if (wantsImage) {
            // Képgenerálás a chatben — animált „készül" buborékkal.
            messages.add(Msg("assistant", "A kép készül…"))
            busy = true
            scope.launch {
                val url = withContext(Dispatchers.IO) { generateImage(text) }
                val last = messages.lastIndex
                messages[last] = Msg("assistant", if (url != null) "Kész a képed: $url" else "A kép most nem készült el. Próbáld újra kicsit később.")
                busy = false
            }
            return
        }
        messages.add(Msg("assistant", ""))
        busy = true
        scope.launch {
            val payload = JSONArray()
            messages.dropLast(1).forEach { m ->
                payload.put(JSONObject().put("role", m.role).put("content", m.text))
            }
            runCatching {
                withContext(Dispatchers.IO) {
                    Api.chatStream("void", payload) { delta ->
                        messages[messages.lastIndex] = Msg("assistant", messages.last().text + delta)
                    }
                }
            }.onFailure {
                messages[messages.lastIndex] = Msg("assistant", "Hálózati hiba — próbáld újra.")
            }
            busy = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(vertical = 16.dp),
        ) {
            items(messages) { m ->
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = if (m.role == "user") Arrangement.End else Arrangement.Start,
                ) {
                    Box(
                        Modifier
                            .widthIn(max = 300.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(if (m.role == "user") Violet.copy(alpha = 0.22f) else InkRaised)
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Text(m.text, color = Color(0xFFF2F2F7), fontSize = 15.sp)
                    }
                }
            }
        }
        if (busy) {
            LinearProgressIndicator(
                Modifier.fillMaxWidth().padding(horizontal = 14.dp).height(2.dp),
                color = Violet,
            )
        }
        // Composer
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Üzenet vagy „kép: …”", color = TextFaint, fontSize = 14.sp) },
                shape = RoundedCornerShape(22.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Violet,
                    unfocusedBorderColor = Color(0xFF2C2C35),
                    cursorColor = VioletSoft,
                ),
                maxLines = 4,
            )
            FilledIconButton(
                onClick = ::send,
                enabled = !busy && input.isNotBlank(),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = Violet),
            ) {
                Icon(Icons.Default.Send, contentDescription = "Küldés")
            }
        }
    }
}

private fun generateImage(prompt: String): String? = try {
    val client = Api.client
    val body = JSONObject().put("prompt", prompt).put("style", "auto")
    val req = okhttp3.Request.Builder()
        .url("${Api.BASE}/api/cortexai/image")
        .post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        .header("User-Agent", "CortexApp/1.0")
        .build()
    client.newCall(req).execute().use { resp ->
        val obj = JSONObject(resp.body?.string() ?: "{}")
        val id = obj.optString("id")
        if (id.isEmpty()) return null
        // státusz-várakozás
        repeat(40) {
            Thread.sleep(1500)
            val st = okhttp3.Request.Builder()
                .url("${Api.BASE}/api/cortexai/image/$id")
                .header("User-Agent", "CortexApp/1.0")
                .build()
            client.newCall(st).execute().use { r2 ->
                val o2 = JSONObject(r2.body?.string() ?: "{}")
                if (o2.optString("status") == "succeeded") return "${Api.BASE}/api/cortexai/image/$id/file"
                if (o2.optString("status") == "failed") return null
            }
        }
        null
    }
} catch (_: Exception) { null }

// ──────────────────────────────────────────────────────────────── Login

@Composable
fun LoginScreen(activity: MainActivity) {
    val scope = rememberCoroutineScope()
    var signUp by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.AccountCircle, null, Modifier.size(72.dp), tint = VioletSoft)
        Spacer(Modifier.height(10.dp))
        Text("Your Cortex account", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(
            "Sign in to sync your subscription, API keys and AI profile.",
            color = TextFaint, fontSize = 13.sp,
        )
        Spacer(Modifier.height(22.dp))
        if (signUp) {
            OutlinedTextField(username, { username = it }, label = { Text("Username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(10.dp))
        }
        OutlinedTextField(email, { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            password, { password = it }, label = { Text("Password") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(),
        )
        if (error.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text(error, color = Danger, fontSize = 13.sp)
        }
        Spacer(Modifier.height(20.dp))
        Button(
            onClick = {
                busy = true; error = ""
                scope.launch {
                    val user = withContext(Dispatchers.IO) {
                        if (signUp) Api.register(username, email, password) else Api.login(email, password)
                    }
                    busy = false
                    if (user != null) {
                        activity.signedIn(user.optString("username"), user.optString("email"))
                    } else {
                        error = "Sign-in failed. Check your credentials."
                    }
                }
            },
            enabled = !busy && email.contains("@") && password.length >= 6 && (!signUp || username.length >= 3),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(14.dp),
        ) {
            Text(if (signUp) "Create Account" else "Sign In", fontSize = 16.sp)
        }
        Spacer(Modifier.height(12.dp))
        Text(
            if (signUp) "Already have an account? Sign in" else "New here? Create an account",
            color = VioletSoft, fontSize = 13.sp,
            modifier = Modifier.clickable { signUp = !signUp },
        )
    }
}

// ──────────────────────────────────────────────────────────────── Előfizetés

@Composable
fun SubscriptionScreen() {
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<JSONObject?>(null) }
    var selected by remember { mutableStateOf("pro") }
    var code by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        status = withContext(Dispatchers.IO) { Api.subStatus() }
    }

    Column(
        Modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.AutoAwesome, null, Modifier.size(40.dp), tint = VioletSoft)
            Text("Cortex AI", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text("Choose your plan. Cancel anytime.", color = TextFaint, fontSize = 13.sp)
        }
        listOf(
            Triple("free", "Free", "5M tokens / day"),
            Triple("pro", "Pro", "50M tokens / day · 1 990 Ft/mo"),
            Triple("max", "Max", "500M tokens / day · 4 990 Ft/mo"),
        ).forEach { (id, label, blurb) ->
            val active = status?.optString("tier") == id
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(InkRaised)
                    .clickable { selected = id }
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (selected == id) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                    null, tint = if (selected == id) VioletSoft else TextFaint,
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(label, fontWeight = FontWeight.SemiBold, color = Color.White, fontSize = 15.sp)
                        if (active) {
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "ACTIVE", color = Cyan, fontSize = 9.sp, fontWeight = FontWeight.Black,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(Cyan.copy(alpha = 0.16f))
                                    .padding(horizontal = 5.dp, vertical = 2.dp),
                            )
                        }
                    }
                    Text(blurb, color = TextFaint, fontSize = 11.sp)
                }
            }
        }
        Button(
            onClick = {
                if (selected == "free") {
                    scope.launch { status = withContext(Dispatchers.IO) { Api.subStatus() } }
                } else {
                    val url = status?.optString("revolut") ?: "https://revolut.me/tibikegh12"
                    context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, Uri.parse(url)))
                }
            },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(14.dp),
        ) {
            Text(if (selected == "free") "Continue" else "Continue — pay with Apple Pay or card", fontSize = 15.sp)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                code, { code = it }, modifier = Modifier.weight(1f),
                placeholder = { Text("Redemption code", fontSize = 13.sp) }, singleLine = true,
            )
            Button(
                onClick = {
                    scope.launch {
                        val obj = withContext(Dispatchers.IO) { Api.redeem(code) }
                        message = if (obj.optBoolean("ok")) "Activated successfully!"
                        else Api.errorOf(obj)
                        status = withContext(Dispatchers.IO) { Api.subStatus() }
                    }
                },
                enabled = code.isNotBlank(),
            ) { Text("Redeem") }
        }
        if (message.isNotEmpty()) {
            Text(message, color = if (message.startsWith("Activated")) Color(0xFF4ADE80) else TextDim, fontSize = 13.sp)
        }
    }
}

// ──────────────────────────────────────────────────────────────── Beállítások

@Composable
fun SettingsScreen(activity: MainActivity) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var aiName by remember { mutableStateOf("Cortex") }
    var persona by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf("") }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) {
            scope.launch {
                val b64 = withContext(Dispatchers.IO) {
                    val bytes = context.contentResolver.openInputStream(uri)?.readBytes() ?: return@withContext null
                    android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                }
                if (b64 != null) {
                    val ok = withContext(Dispatchers.IO) { Api.uploadAvatar(b64) }
                    saved = if (ok) "Profile picture updated." else "Upload failed."
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) { Api.aiProfile() }?.let {
            aiName = it.optString("ai_name", "Cortex")
            persona = it.optString("persona")
        }
    }

    Column(
        Modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("Account", color = TextFaint, fontSize = 11.sp, fontWeight = FontWeight.Black)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.AccountCircle, null, Modifier.size(44.dp), tint = VioletSoft)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(activity.userName.ifEmpty { "Guest" }, fontWeight = FontWeight.SemiBold, color = Color.White)
                Text(activity.userEmail, color = TextFaint, fontSize = 12.sp)
            }
            OutlinedButton(onClick = { picker.launch("image/*") }) { Text("Photo", fontSize = 12.sp) }
        }
        if (activity.userName.isEmpty()) {
            OutlinedButton(onClick = { activity.screen = Screen.Login }, Modifier.fillMaxWidth()) {
                Text("Sign in or create an account")
            }
        }

        Text("Your AI", color = TextFaint, fontSize = 11.sp, fontWeight = FontWeight.Black)
        OutlinedTextField(aiName, { aiName = it }, label = { Text("AI name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            persona, { persona = it }, label = { Text("Personality — how should your AI talk?") },
            modifier = Modifier.fillMaxWidth().height(120.dp),
        )
        Button(
            onClick = {
                scope.launch {
                    val ok = withContext(Dispatchers.IO) { Api.saveAiProfile(aiName, persona, "balanced") }
                    saved = if (ok) "Saved." else "Save failed."
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Save AI profile") }
        if (saved.isNotEmpty()) Text(saved, color = VioletSoft, fontSize = 13.sp)

        if (activity.userName.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = {
                    scope.launch {
                        withContext(Dispatchers.IO) { Api.logout() }
                        activity.signedOut()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Sign out", color = Danger) }
        }
    }
}
