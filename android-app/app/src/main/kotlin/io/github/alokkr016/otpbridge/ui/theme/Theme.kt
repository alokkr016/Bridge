package io.github.alokkr016.otpbridge.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = Color.White,
    onPrimary = Color.Black,
    primaryContainer = Card,
    onPrimaryContainer = Ink,
    secondary = Ink,
    onSecondary = Color.Black,
    secondaryContainer = Card,
    onSecondaryContainer = Ink,
    tertiary = Muted,
    background = Canvas,
    onBackground = Ink,
    surface = Canvas,
    onSurface = Ink,
    surfaceVariant = Card,
    onSurfaceVariant = Muted,
    outline = Line,
    error = OTPRed
)

@Composable
fun OTPBridgeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content
    )
}
