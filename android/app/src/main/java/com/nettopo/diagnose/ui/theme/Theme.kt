package com.nettopo.diagnose.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Match Mac version: #020617 background, cyan accent
val Slate950 = Color(0xFF020617)
val Slate900 = Color(0xFF0F172A)
val Slate800 = Color(0xFF1E293B)
val Slate600 = Color(0xFF475569)
val Slate400 = Color(0xFF94A3B8)
val Cyan400 = Color(0xFF22D3EE)
val Cyan500 = Color(0xFF06B6D4)
val Cyan600 = Color(0xFF0891B2)
val Blue500 = Color(0xFF3B82F6)
val Green500 = Color(0xFF22C55E)
val Yellow500 = Color(0xFFEAB308)
val Orange500 = Color(0xFFF97316)
val Red500 = Color(0xFFEF4444)
val White = Color(0xFFFFFFFF)
val Gray400 = Color(0xFF9CA3AF)
val Gray500 = Color(0xFF6B7280)

private val DarkColorScheme = darkColorScheme(
    primary = Cyan500,
    secondary = Blue500,
    tertiary = Color(0xFF7C3AED),
    background = Slate950,
    surface = Slate900,
    surfaceVariant = Slate800,
    onPrimary = Slate950,
    onBackground = White,
    onSurface = White,
    onSurfaceVariant = Gray400,
    outline = Slate600
)

@Composable
fun NetDiagnoseTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography(),
        content = content
    )
}
