package com.example.milipercent.ui.map

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import com.naver.maps.map.overlay.OverlayImage

internal fun categoryAccentColorInt(category: String): Int = when (category.trim()) {
    "음식" -> 0xFFE85D3F.toInt()
    "카페" -> 0xFF9C6644.toInt()
    "병원" -> 0xFF1E9E74.toInt()
    "미용·뷰티" -> 0xFFD65780.toInt()
    "문화·여가" -> 0xFF6366F1.toInt()
    "숙박" -> 0xFF2563EB.toInt()
    else -> 0xFF315FCB.toInt()
}

internal fun createBenefitMarkerIcon(
    context: Context,
    category: String = "기타",
    selected: Boolean = false,
): OverlayImage {
    val density = context.resources.displayMetrics.density
    fun dp(value: Float): Float = value * density
    val widthDp = if (selected) 36f else 28f
    val heightDp = if (selected) 46f else 36f
    val headSizeDp = if (selected) 32f else 24f
    val headLeftDp = (widthDp - headSizeDp) / 2f
    val headTopDp = 1.5f
    val centerX = dp(widthDp / 2f)
    val centerY = dp(headTopDp + headSizeDp / 2f)

    val bitmap = Bitmap.createBitmap(
        dp(widthDp).toInt().coerceAtLeast(1),
        dp(heightDp).toInt().coerceAtLeast(1),
        Bitmap.Config.ARGB_8888,
    )
    val canvas = Canvas(bitmap)
    val accentColor = categoryAccentColorInt(category)

    val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accentColor }

    val tipY = dp(heightDp - 1.5f)
    val tailBaseY = dp(headTopDp + headSizeDp - 4f)
    val tailHalfW = dp(if (selected) 5.5f else 4.2f)

    // Subtle white rim around pin and tail so overlapping pins stay crisp.
    val rimExpand = dp(1.4f)
    canvas.drawRoundRect(
        RectF(
            dp(headLeftDp) - rimExpand,
            dp(headTopDp) - rimExpand,
            dp(headLeftDp + headSizeDp) + rimExpand,
            dp(headTopDp + headSizeDp) + rimExpand,
        ),
        dp(headSizeDp / 2f),
        dp(headSizeDp / 2f),
        borderPaint,
    )
    canvas.drawPath(
        Path().apply {
            moveTo(centerX - tailHalfW - rimExpand, tailBaseY)
            lineTo(centerX + tailHalfW + rimExpand, tailBaseY)
            lineTo(centerX, tipY + rimExpand)
            close()
        },
        borderPaint,
    )

    // Colored pin body & pointer.
    canvas.drawRoundRect(
        RectF(dp(headLeftDp), dp(headTopDp), dp(headLeftDp + headSizeDp), dp(headTopDp + headSizeDp)),
        dp(headSizeDp / 2f),
        dp(headSizeDp / 2f),
        fillPaint,
    )
    canvas.drawPath(
        Path().apply {
            moveTo(centerX - tailHalfW, tailBaseY)
            lineTo(centerX + tailHalfW, tailBaseY)
            lineTo(centerX, tipY)
            close()
        },
        fillPaint,
    )

    // White inner badge + crisp % mark.
    val innerRadius = dp(if (selected) 10.5f else 7.8f)
    canvas.drawCircle(centerX, centerY, innerRadius, borderPaint)
    val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = accentColor
        textAlign = Paint.Align.CENTER
        textSize = dp(if (selected) 13.5f else 10.5f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val textY = centerY - (textPaint.ascent() + textPaint.descent()) / 2f
    canvas.drawText("%", centerX, textY, textPaint)
    return OverlayImage.fromBitmap(bitmap)
}
