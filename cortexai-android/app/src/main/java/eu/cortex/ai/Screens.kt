package eu.cortex.ai

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import eu.cortex.ai.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

// ──────────────────────────────────────────────────────────────── Váz

@Composable
fun CortexApp(activity: MainActivity) {
    Scaffold(
        containerColor = Ink,
        bottomBar = { CortexBottomBar(activity) },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (activity.screen) {
                Screen.Chat -> ChatScreen()
                Screen.Images -> ImagesScreen()
                Screen.Live -> LiveScreen()
                Screen.Anime -> AnimeScreen()
                Screen.Profile -> ProfileScreen(activity)
                Screen.Login -> LoginScreen(activity)
            }
        }
    }
}

private data class Tab(val screen: Screen, val icon: ImageVector, val label: String)

@Composable
private fun CortexBottomBar(activity: MainActivity) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(InkSurface)
            .border(width = 1.dp, color = Color(0xFF1B1B23))
            .padding(vertical = 8.dp),
    ) {
        listOf(
            Tab(Screen.Chat, Icons.Default.Chat, "Chat"),
            Tab(Screen.Images, Icons.Default.Image, "Images"),
            Tab(Screen.Live, Icons.Default.PlayCircle, "Live"),
            Tab(Screen.Anime, Icons.Default.LiveTv, "Anime"),
            Tab(Screen.Profile, Icons.Default.Person, "Profile"),
        ).forEach { tab ->
            val active = activity.screen == tab.screen
            Column(
                Modifier
                    .weight(1f)
                    .clickable { activity.screen = tab.screen }
                    .padding(vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(
                    tab.icon, contentDescription = tab.label,
                    Modifier.size(22.dp),
                    tint = if (active) Violet else Color(0xFF6B6B78),
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    tab.label, fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
                    color = if (active) Violet else Color(0xFF6B6B78),
                )
            }
        }
    }
}

/** A Cortex városgrafika — Canvas, hálózat nélkül is működik. */
@Composable
fun CityArt(modifier: Modifier = Modifier, dawn: Boolean = false) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        drawRect(
            Brush.verticalGradient(
                listOf(
                    if (dawn) Color(0xFF3A1458) else Color(0xFF1B0F38),
                    if (dawn) Color(0xFF4B2A7A) else Color(0xFF2E1465),
                    Color(0xFF0B0B0F),
                )
            )
        )
        var x = -10f
        var i = 0
        while (x < w + 10f && i < 40) {
            val tw = w * (0.06f + ((i * 37) % 5) * 0.012f)
            val th = h * (0.25f + ((i * 53) % 7) * 0.075f)
            val c = listOf(Color(0xFF120B26), Color(0xFF0F0A20), Color(0xFF140C2B))[i % 3]
            drawRect(c, Offset(x, h - th), Size(tw, th))
            if (i % 2 == 0) {
                drawRect(
                    if (i % 4 == 0) Color(0xFF7C5CFF) else Color(0xFF0A84FF),
                    Offset(x + tw * 0.25f, h - th + 12f),
                    Size(tw * 0.14f, h * 0.02f),
                )
            }
            x += tw * 1.15f
            i++
        }
        drawOval(Color(0x1F7C5CFF), Offset(w * 0.08f, h * 0.86f), Size(w * 0.84f, h * 0.12f))
    }
}

@Composable
private fun DiamondMark(size: Int) {
    Canvas(Modifier.size(size.dp)) {
        val s = this.size.minDimension
        val p = androidx.compose.ui.graphics.Path().apply {
            moveTo(s / 2f, 0f); lineTo(s, s / 2f); lineTo(s / 2f, s); lineTo(0f, s / 2f); close()
        }
        drawPath(p, Color(0xEEEDEAFF))
    }
}

@Composable
private fun AssistantAvatar() {
    Box(
        Modifier
            .size(28.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(Brush.linearGradient(listOf(Violet, Color(0xFF4B2FD6)))),
        contentAlignment = Alignment.Center,
    ) { DiamondMark(12) }
}

// ──────────────────────────────────────────────────────────────── Chat

data class Msg(
    val role: String,
    val text: String,
    val imagePrompt: String? = null,
    val imageUrl: String? = null,
    val working: Boolean = false,
)

@Composable
fun ChatScreen() {
    val scope = rememberCoroutineScope()
    val messages = remember {
        mutableStateListOf(
            Msg("assistant", "Szia, Tibi! Ma miben segíthetek? Kép, számítás, fordítás — vagy csak beszélgetünk.")
        )
    }
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    fun send() {
        val text = input.trim()
        if (text.isEmpty() || busy) return
        input = ""
        messages.add(Msg("user", text))
        val wantsImage = text.lowercase().let {
            it.startsWith("image:") || it.startsWith("kép:") || it.startsWith("kep:") ||
                it.contains("generate an image") || it.contains("draw me") ||
                it.contains("rajzolj") || it.contains("generálj képet")
        }
        if (wantsImage) {
            val prompt = text.replaceFirst(Regex("^(image|kép|kep)\\s*:\\s*", RegexOption.IGNORE_CASE), "").ifBlank { text }
            messages.add(Msg("assistant", "", imagePrompt = prompt, working = true))
            busy = true
            scope.launch {
                val url = withContext(Dispatchers.IO) { generateImage(prompt) }
                val idx = messages.indexOfLast { it.imagePrompt == prompt }
                if (idx >= 0) {
                    messages[idx] = Msg("assistant", "", imagePrompt = prompt, imageUrl = url, working = false)
                }
                busy = false
            }
            return
        }
        messages.add(Msg("assistant", ""))
        busy = true
        scope.launch {
            val payload = JSONArray()
            messages.dropLast(1).forEach { m ->
                if (m.text.isNotBlank() && m.imagePrompt == null) {
                    payload.put(JSONObject().put("role", m.role).put("content", m.text))
                }
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(vertical = 16.dp),
        ) {
            item {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(99.dp))
                            .background(InkCard)
                            .padding(horizontal = 12.dp, vertical = 4.dp),
                    ) { Text("TODAY", color = TextFaint, fontSize = 10.sp, fontWeight = FontWeight.SemiBold) }
                }
            }
            items(messages) { m ->
                if (m.imagePrompt != null) {
                    Row(Modifier.fillMaxWidth()) {
                        AssistantAvatar()
                        Spacer(Modifier.width(9.dp))
                        ImageCard(
                            prompt = m.imagePrompt, url = m.imageUrl, working = m.working,
                            modifier = Modifier.weight(1f),
                        )
                    }
                } else if (m.role == "user") {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Box(
                            Modifier
                                .widthIn(max = 280.dp)
                                .clip(RoundedCornerShape(18.dp, 18.dp, 6.dp, 18.dp))
                                .background(Violet)
                                .padding(horizontal = 14.dp, vertical = 11.dp),
                        ) { Text(m.text, color = Color.White, fontSize = 15.sp) }
                    }
                } else {
                    Row(Modifier.fillMaxWidth()) {
                        AssistantAvatar()
                        Spacer(Modifier.width(9.dp))
                        Column(Modifier.weight(1f)) {
                            Text("CORTEX", color = TextFaint, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp)
                            Spacer(Modifier.height(4.dp))
                            Box(
                                Modifier
                                    .clip(RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp))
                                    .background(InkRaised)
                                    .padding(horizontal = 14.dp, vertical = 11.dp),
                            ) { Text(m.text, color = Color(0xFFDDDEE8), fontSize = 15.sp, lineHeight = 22.sp) }
                        }
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
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                Modifier
                    .size(38.dp)
                    .clip(RoundedCornerShape(13.dp))
                    .background(InkCard)
                    .border(1.dp, Color(0xFF2A2A35), RoundedCornerShape(13.dp)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Default.Add, "More", Modifier.size(18.dp), tint = Color(0xFFB9BAC6)) }
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Message or \"image: ...\"", color = TextFaint, fontSize = 14.sp) },
                shape = RoundedCornerShape(22.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Violet,
                    unfocusedBorderColor = Color(0xFF2A2A35),
                    cursorColor = VioletSoft,
                ),
                maxLines = 4,
            )
            FilledIconButton(
                onClick = ::send,
                enabled = !busy && input.isNotBlank(),
                modifier = Modifier.size(40.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = Violet),
            ) {
                Icon(Icons.Default.Send, contentDescription = "Send", Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun ImageCard(prompt: String, url: String?, working: Boolean, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(18.dp))
            .background(InkRaised)
            .padding(11.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(180.dp)
                .clip(RoundedCornerShape(12.dp)),
        ) {
            if (url != null) {
                AsyncImage(
                    model = url, contentDescription = null,
                    modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop,
                )
            } else {
                CityArt(Modifier.fillMaxSize())
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .clip(RoundedCornerShape(99.dp))
                    .background(if (working) Color(0x247C5CFF) else Color(0x2434C759))
                    .padding(horizontal = 9.dp, vertical = 3.dp),
            ) {
                Text(
                    if (working) "GENERATING" else "READY",
                    color = if (working) VioletSoft else Ok, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                )
            }
            Spacer(Modifier.width(8.dp))
            Text(
                prompt.take(38), color = Color(0xFFDDDEE8), fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Box(
                Modifier
                    .clip(RoundedCornerShape(9.dp))
                    .background(InkCard)
                    .border(1.dp, Color(0xFF2A2A35), RoundedCornerShape(9.dp))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) { Text("Download", color = Color(0xFFB9BAC6), fontSize = 10.5.sp, fontWeight = FontWeight.Bold) }
        }
        Text("prompt: $prompt", color = TextFaint, fontSize = 10.5.sp, lineHeight = 15.sp)
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

// ──────────────────────────────────────────────────────────────── Images

data class ImageItem(val prompt: String, val url: String? = null, val working: Boolean = false)

@Composable
fun ImagesScreen() {
    val scope = rememberCoroutineScope()
    val itemsList = remember {
        mutableStateListOf(
            ImageItem("Neon city — rain"),
            ImageItem("Violet dawn skyline"),
            ImageItem("Cyber district"),
        )
    }
    var prompt by remember { mutableStateOf("") }

    Column(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column {
            Text("Image Studio", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text("Cortex Void Canvas — FLUX engine.", color = TextFaint, fontSize = 13.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                prompt, { prompt = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("A purple-black cyber anime girl...", color = TextFaint, fontSize = 13.sp) },
                shape = RoundedCornerShape(12.dp), singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
                ),
            )
            Button(
                onClick = {
                    val p = prompt.trim()
                    if (p.isEmpty()) return@Button
                    prompt = ""
                    itemsList.add(0, ImageItem(p, working = true))
                    scope.launch {
                        val url = withContext(Dispatchers.IO) { generateImage(p) }
                        val idx = itemsList.indexOfFirst { it.prompt == p }
                        if (idx >= 0) itemsList[idx] = ImageItem(p, url = url, working = false)
                    }
                },
                shape = RoundedCornerShape(12.dp),
            ) { Text("Generate") }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(itemsList) { item ->
                Column(
                    Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(InkRaised),
                ) {
                    Box(Modifier.fillMaxWidth().height(110.dp)) {
                        if (item.url != null) {
                            AsyncImage(
                                model = item.url, contentDescription = null,
                                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop,
                            )
                        } else {
                            CityArt(Modifier.fillMaxSize())
                        }
                    }
                    Row(
                        Modifier.padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            item.prompt.take(20), color = Color(0xFFDDDEE8), fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold, maxLines = 1,
                            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                        )
                        Box(
                            Modifier
                                .clip(RoundedCornerShape(99.dp))
                                .background(if (item.working) Color(0x247C5CFF) else Color(0x2434C759))
                                .padding(horizontal = 7.dp, vertical = 2.dp),
                        ) {
                            Text(
                                if (item.working) "..." else "Ready",
                                color = if (item.working) VioletSoft else Ok,
                                fontSize = 9.sp, fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────── Live

@Composable
fun LiveScreen() {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column {
            Text("Live", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text("Watch party and community screenings.", color = TextFaint, fontSize = 13.sp)
        }
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(InkRaised)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Ok))
                Spacer(Modifier.width(8.dp))
                Text("Watch party", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            }
            Text(
                "Live screenings with Hungarian subtitles, directly from the CortexAnime community.",
                color = TextFaint, fontSize = 12.sp, lineHeight = 17.sp,
            )
            Button(
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://cortanime.eu/watch")))
                },
                shape = RoundedCornerShape(11.dp),
            ) { Text("Open watch party") }
        }
        Text("WEEKLY SCHEDULE", color = TextFaint, fontSize = 10.sp, fontWeight = FontWeight.Black)
        listOf(
            Triple("MON", "Violet Evergarden", "EP 4 — 18:00"),
            Triple("WED", "Akagami no Shirayuki", "EP 6 — 18:00"),
            Triple("FRI", "Soredemo Ayumu", "EP 5 — 18:00"),
            Triple("SUN", "Welsh & Shedar", "EP 6 — 20:00"),
        ).forEach { (day, title, time) ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(InkRaised)
                    .padding(13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0x247C5CFF))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                ) { Text(day, color = VioletSoft, fontSize = 10.sp, fontWeight = FontWeight.Bold) }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(time, color = TextFaint, fontSize = 11.sp)
                }
                Icon(Icons.Default.PlayCircle, null, Modifier.size(20.dp), tint = Violet)
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────── Anime

@Composable
fun AnimeScreen() {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("CortexAnime", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text("Translated episodes and the catalog.", color = TextFaint, fontSize = 13.sp)
            }
            OutlinedButton(
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://cortanime.eu/anime")))
                },
                shape = RoundedCornerShape(11.dp),
            ) { Text("Open site", fontSize = 12.sp) }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(
                listOf(
                    Triple("Violet Evergarden", "HU subs — EP 1-3", false),
                    Triple("Akagami no Shirayuki", "HU subs — EP 1-5", true),
                    Triple("Soredemo Ayumu", "HU subs — EP 1-4", false),
                    Triple("Kamisama Hajimemashita", "HU subs — EP 1", true),
                    Triple("Welsh & Shedar", "HU subs — EP 1-5", false),
                    Triple("Weekly schedule", "New episodes daily", true),
                )
            ) { (title, sub, dawn) ->
                Column(
                    Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(InkRaised),
                ) {
                    Box(Modifier.fillMaxWidth().height(110.dp)) {
                        CityArt(Modifier.fillMaxSize(), dawn = dawn)
                    }
                    Column(Modifier.padding(10.dp)) {
                        Text(
                            title, color = Color(0xFFDDDEE8), fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                        Text(sub, color = TextFaint, fontSize = 9.5.sp)
                    }
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────── Profil

@Composable
fun ProfileScreen(activity: MainActivity) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var status by remember { mutableStateOf<JSONObject?>(null) }
    var selected by remember { mutableStateOf("pro") }
    var code by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
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
        status = withContext(Dispatchers.IO) { Api.subStatus() }
        withContext(Dispatchers.IO) { Api.aiProfile() }?.let {
            aiName = it.optString("ai_name", "Cortex")
            persona = it.optString("persona")
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("Profile", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)

        // Fiók
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(InkRaised)
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(Violet),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    activity.userName.firstOrNull()?.uppercase() ?: "G",
                    color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp,
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    activity.userName.ifEmpty { "Guest" },
                    fontWeight = FontWeight.SemiBold, color = Color.White, fontSize = 14.sp,
                )
                Text(activity.userEmail.ifEmpty { "Not signed in" }, color = TextFaint, fontSize = 11.5.sp)
            }
            OutlinedButton(onClick = { picker.launch("image/*") }, shape = RoundedCornerShape(10.dp)) {
                Text("Photo", fontSize = 11.5.sp)
            }
        }
        if (activity.userName.isEmpty()) {
            Button(
                onClick = { activity.screen = Screen.Login },
                modifier = Modifier.fillMaxWidth().height(46.dp),
                shape = RoundedCornerShape(12.dp),
            ) { Text("Sign in or create an account") }
        }

        // Saját AI
        Text("YOUR AI", color = TextFaint, fontSize = 10.sp, fontWeight = FontWeight.Black)
        OutlinedTextField(
            aiName, { aiName = it }, label = { Text("AI name") }, singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
            ),
        )
        OutlinedTextField(
            persona, { persona = it }, label = { Text("Personality — how should your AI talk?") },
            modifier = Modifier.fillMaxWidth().height(110.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
            ),
        )
        Button(
            onClick = {
                scope.launch {
                    val ok = withContext(Dispatchers.IO) { Api.saveAiProfile(aiName, persona, "balanced") }
                    saved = if (ok) "Saved." else "Save failed."
                }
            },
            modifier = Modifier.fillMaxWidth().height(46.dp),
            shape = RoundedCornerShape(12.dp),
        ) { Text("Save AI profile") }
        if (saved.isNotEmpty()) Text(saved, color = VioletSoft, fontSize = 12.5.sp)

        // Előfizetés
        Text("SUBSCRIPTION", color = TextFaint, fontSize = 10.sp, fontWeight = FontWeight.Black)
        listOf(
            Triple("free", "Free", "5M tokens / day · 2 API keys"),
            Triple("pro", "Pro", "50M tokens / day · 10 keys · 1 990 Ft/mo"),
            Triple("max", "Max", "500M tokens / day · 40 keys · 4 990 Ft/mo"),
        ).forEach { (id, label, blurb) ->
            val active = status?.optString("tier") == id
            val sel = selected == id
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (sel) Color(0x1A7C5CFF) else InkRaised)
                    .then(if (sel) Modifier.border(1.dp, Violet, RoundedCornerShape(14.dp)) else Modifier)
                    .clickable { selected = id }
                    .padding(13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (sel) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                    null, tint = if (sel) Violet else TextFaint, Modifier.size(18.dp),
                )
                Spacer(Modifier.width(11.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(label, fontWeight = FontWeight.Bold, color = Color.White, fontSize = 14.sp)
                        if (active) {
                            Spacer(Modifier.width(8.dp))
                            Box(
                                Modifier
                                    .clip(RoundedCornerShape(5.dp))
                                    .background(Color(0x2434C759))
                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                            ) { Text("ACTIVE", color = Ok, fontSize = 8.5.sp, fontWeight = FontWeight.Black) }
                        }
                    }
                    Text(blurb, color = TextFaint, fontSize = 10.5.sp)
                }
            }
        }
        Button(
            onClick = {
                if (selected == "free") {
                    scope.launch { status = withContext(Dispatchers.IO) { Api.subStatus() } }
                } else {
                    val url = status?.optString("revolut") ?: "https://revolut.me/tibikegh12"
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }
            },
            modifier = Modifier.fillMaxWidth().height(48.dp),
            shape = RoundedCornerShape(12.dp),
        ) { Text(if (selected == "free") "Continue" else "Continue — pay with card or Revolut", fontSize = 13.sp) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                code, { code = it }, modifier = Modifier.weight(1f),
                placeholder = { Text("Redemption code", fontSize = 12.5.sp) }, singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
                ),
            )
            Button(
                onClick = {
                    scope.launch {
                        val obj = withContext(Dispatchers.IO) { Api.redeem(code) }
                        message = if (obj.optBoolean("ok")) "Activated successfully!" else Api.errorOf(obj)
                        status = withContext(Dispatchers.IO) { Api.subStatus() }
                    }
                },
                enabled = code.isNotBlank(),
                shape = RoundedCornerShape(11.dp),
            ) { Text("Redeem") }
        }
        if (message.isNotEmpty()) {
            Text(message, color = if (message.startsWith("Activated")) Ok else TextDim, fontSize = 12.5.sp)
        }

        if (activity.userName.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            OutlinedButton(
                onClick = {
                    scope.launch {
                        withContext(Dispatchers.IO) { Api.logout() }
                        activity.signedOut()
                    }
                },
                modifier = Modifier.fillMaxWidth().height(46.dp),
                shape = RoundedCornerShape(12.dp),
            ) { Text("Sign out", color = Danger) }
        }
    }
}

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
        Box(
            Modifier.size(72.dp).clip(RoundedCornerShape(22.dp)).background(Brush.linearGradient(listOf(Violet, Color(0xFF4B2FD6)))),
            contentAlignment = Alignment.Center,
        ) { DiamondMark(30) }
        Spacer(Modifier.height(12.dp))
        Text("Your Cortex account", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(
            "Sign in to sync your subscription, API keys and AI profile.",
            color = TextFaint, fontSize = 13.sp,
        )
        Spacer(Modifier.height(22.dp))
        if (signUp) {
            OutlinedTextField(
                username, { username = it }, label = { Text("Username") }, singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
                ),
            )
            Spacer(Modifier.height(10.dp))
        }
        OutlinedTextField(
            email, { email = it }, label = { Text("Email") }, singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
            ),
        )
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            password, { password = it }, label = { Text("Password") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Violet, unfocusedBorderColor = Color(0xFF2A2A35), cursorColor = VioletSoft,
            ),
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
