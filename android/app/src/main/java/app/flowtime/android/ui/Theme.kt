package app.flowtime.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val FlowBlue = Color(0xFF4F8CFF)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF79A7FF),
    secondary = Color(0xFF65D9FF),
    background = Color.Black,
    surface = Color(0xFF111214),
    surfaceVariant = Color(0xFF202124),
    onBackground = Color.White,
    onSurface = Color.White
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF1769D2),
    secondary = FlowBlue,
    background = Color(0xFFF5F5F7),
    surface = Color.White,
    surfaceVariant = Color(0xFFE9E9ED),
    onBackground = Color(0xFF111114),
    onSurface = Color(0xFF111114)
)

@Composable
fun FlowtimeTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = MaterialTheme.typography,
        content = content
    )
}
