package com.mtog.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF284B63),
    secondary = Color(0xFF9D5C4B),
    tertiary = Color(0xFF2E6E58),
    background = Color(0xFFF7F2EB),
    surface = Color(0xFFFFFFFF),
    onPrimary = Color.White,
    onBackground = Color(0xFF1E2630),
    onSurface = Color(0xFF1E2630)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF9BC1D9),
    secondary = Color(0xFFD8A28F),
    tertiary = Color(0xFF8BC0A8)
)

@Composable
fun MtoGTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        typography = MaterialTheme.typography,
        content = content
    )
}
