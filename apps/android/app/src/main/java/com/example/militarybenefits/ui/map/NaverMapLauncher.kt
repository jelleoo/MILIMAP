package com.example.militarybenefits.ui.map

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.example.militarybenefits.data.Benefit

internal fun Context.openNaverMap(benefit: Benefit): Boolean {
    val appUrl = if (benefit.latitude != null && benefit.longitude != null) {
        NaverMapUrl.place(
            storeName = benefit.name,
            latitude = benefit.latitude,
            longitude = benefit.longitude,
            appName = packageName,
        )
    } else {
        NaverMapUrl.search(benefit.name, packageName)
    }

    val openedInApp = isNaverMapInstalled() && startMapIntent(
        url = appUrl,
        targetPackage = NaverMapUrl.PACKAGE_NAME,
    )
    return openedInApp || startMapIntent(NaverMapUrl.webSearch(benefit.name))
}

@Suppress("DEPRECATION")
private fun Context.isNaverMapInstalled(): Boolean = runCatching {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        packageManager.getPackageInfo(
            NaverMapUrl.PACKAGE_NAME,
            PackageManager.PackageInfoFlags.of(0),
        )
    } else {
        packageManager.getPackageInfo(NaverMapUrl.PACKAGE_NAME, 0)
    }
}.isSuccess

private fun Context.startMapIntent(url: String, targetPackage: String? = null): Boolean =
    runCatching {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            targetPackage?.let(::setPackage)
            if (this@startMapIntent !is Activity) {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        startActivity(intent)
    }.isSuccess
