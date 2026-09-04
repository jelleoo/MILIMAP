package com.example.milipercent.ui.map

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
    val bitmap = Bitmap.createBitmap(dp(52f).toInt(), dp(64f).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = 0xFF7D9EF9.toInt()
    canvas.drawRoundRect(RectF(dp(4f), dp(2f), dp(48f), dp(48f)), dp(16f), dp(16f), paint)
    canvas.drawPath(Path().apply {
        moveTo(dp(18f), dp(44f)); lineTo(dp(34f), dp(44f)); lineTo(dp(26f), dp(62f)); close()
    }, paint)
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
    return OverlayImage.fromBitmap(bitmap)
}
