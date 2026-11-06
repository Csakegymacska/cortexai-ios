package eu.cortex.ai.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// A Cortex paletta — megegyezik az iOS app lila-fekete világával.
val Ink = Color(0xFF0B0B0F)
val InkSurface = Color(0xFF0D0D12)
val InkRaised = Color(0xFF17171D)
val InkCard = Color(0xFF22222B)
val Violet = Color(0xFF7C5CFF)
val VioletSoft = Color(0xFFB7A5FF)
val Cyan = Color(0xFF22D3EE)
val Ok = Color(0xFF34C759)
val TextDim = Color(0xFFC6C7D2)
val TextFaint = Color(0xFF8E8E99)
val Danger = Color(0xFFEF4444)

private val CortexColors = darkColorScheme(
    primary = Violet,
    onPrimary = Color.White,
    secondary = VioletSoft,
    background = Ink,
    onBackground = Color(0xFFF2F2F7),
    surface = InkSurface,
    onSurface = Color(0xFFF2F2F7),
    surfaceVariant = InkRaised,
    onSurfaceVariant = TextDim,
    outline = Color(0xFF2C2C35),
    error = Danger,
)

@Composable
fun CortexTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = CortexColors, content = content)
}
