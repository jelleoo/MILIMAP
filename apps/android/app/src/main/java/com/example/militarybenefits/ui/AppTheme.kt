package com.example.militarybenefits.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val PrimaryBlue = Color(0xFF7D9EF9)
val PrimaryDark = Color(0xFF315FCB)
val PrimarySoft = Color(0xFFE9EFFF)
val Navy = Color(0xFF172033)
val Canvas = Color(0xFFF6F8FC)
val Muted = Color(0xFF697386)
val Line = Color(0xFFE4E8F0)
val Success = Color(0xFF2F9E66)
val Warning = Color(0xFFD58B13)
val Danger = Color(0xFFD65353)
val AccentYellow = Color(0xFFFFDA58)

private val AppColors = lightColorScheme(
    primary = PrimaryDark,
    onPrimary = Color.White,
    primaryContainer = PrimaryBlue,
    onPrimaryContainer = Navy,
    secondary = Navy,
    onSecondary = Color.White,
    background = Canvas,
    onBackground = Navy,
    surface = Color.White,
    onSurface = Navy,
    outline = Line,
    error = Danger,
)

@Composable
fun MilitaryBenefitTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = AppColors, typography = Typography(), content = content)
}
