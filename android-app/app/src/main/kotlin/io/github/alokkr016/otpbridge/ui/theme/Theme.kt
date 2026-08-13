package io.github.alokkr016.otpbridge.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = BrandOrange,
    onPrimary = OnOrange,
    primaryContainer = BrandIndigoDeep,
    onPrimaryContainer = BrandIndigoSoft,
    secondary = BrandIndigoSoft,
    onSecondary = BrandIndigoDeep,
    secondaryContainer = DarkSurfaceHigh,
    onSecondaryContainer = DarkOnSurface,
    tertiary = BrandTeal,
    background = DarkBackground,
    onBackground = DarkOnSurface,
    surface = DarkSurface,
    onSurface = DarkOnSurface,
    surfaceVariant = DarkSurfaceHigh,
    onSurfaceVariant = DarkOnVariant,
    outline = Color(0xFF3E3C56),
    error = OTPRed
)

private val LightColorScheme = lightColorScheme(
    primary = BrandIndigo,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE4E2FF),
    onPrimaryContainer = BrandIndigoDeep,
    secondary = BrandOrange,
    onSecondary = Color(0xFF2A1800),
    secondaryContainer = Color(0xFFFFE4CC),
    onSecondaryContainer = Color(0xFF3A1F00),
    tertiary = Color(0xFF1F6B63),
    background = LightBackground,
    onBackground = LightOnSurface,
    surface = LightSurface,
    onSurface = LightOnSurface,
    surfaceVariant = Color(0xFFECEAF6),
    onSurfaceVariant = LightOnVariant,
    outline = Color(0xFFC8C4DC),
    error = OTPRed
)

@Composable
fun OTPBridgeTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
        typography = Typography,
        content = content
    )
}
