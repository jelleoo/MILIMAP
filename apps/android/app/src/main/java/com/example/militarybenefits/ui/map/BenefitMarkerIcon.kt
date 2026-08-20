package com.example.militarybenefits.ui.map

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import com.naver.maps.map.overlay.OverlayImage

internal fun createBenefitMarkerIcon(context: Context): OverlayImage {
    val density = context.resources.displayMetrics.density
    fun dp(value: Float): Float = value * density

    val width = dp(52f).toInt()
    val height = dp(64f).toInt()
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    fun drawPin(color: Int, offsetY: Float) {
        paint.color = color
        canvas.drawRoundRect(
            RectF(dp(4f), dp(2f) + offsetY, dp(48f), dp(48f) + offsetY),
            dp(16f),
            dp(16f),
            paint,
        )
        canvas.drawPath(
            Path().apply {
                moveTo(dp(18f), dp(44f) + offsetY)
                lineTo(dp(34f), dp(44f) + offsetY)
                lineTo(dp(26f), dp(62f) + offsetY)
                close()
            },
            paint,
        )
    }

    drawPin(color = 0x290C1933, offsetY = dp(1.5f))
    drawPin(color = 0xFF7D9EF9.toInt(), offsetY = 0f)

    paint.color = android.graphics.Color.WHITE
    canvas.drawCircle(dp(26f), dp(25f), dp(15f), paint)

    paint.apply {
        color = 0xFF172033.toInt()
        textAlign = Paint.Align.CENTER
        textSize = dp(20f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val textY = dp(25f) - (paint.ascent() + paint.descent()) / 2f
    canvas.drawText("%", dp(26f), textY, paint)

    paint.color = android.graphics.Color.WHITE
    canvas.drawCircle(dp(44f), dp(8f), dp(6f), paint)
    paint.color = 0xFFFFDA58.toInt()
    canvas.drawCircle(dp(44f), dp(8f), dp(4.5f), paint)

    return OverlayImage.fromBitmap(bitmap)
}
