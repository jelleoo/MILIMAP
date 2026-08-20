import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

fun configuredValue(name: String, fallback: String): String =
    (localProperties.getProperty(name) ?: System.getenv(name) ?: fallback)
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")

android {
    namespace = "com.example.militarybenefits"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.militarybenefits"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField(
            "String",
            "NAVER_MAP_NCP_KEY_ID",
            "\"${configuredValue("NAVER_MAP_NCP_KEY_ID", "")}\"",
        )
        buildConfigField(
            "String",
            "MMA_SERVICE_KEY",
            "\"${configuredValue("MMA_SERVICE_KEY", "")}\"",
        )
        manifestPlaceholders["naverMapNcpKeyId"] = configuredValue(
            "NAVER_MAP_NCP_KEY_ID",
            "MISSING_NCP_KEY_ID",
        )
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    buildFeatures { buildConfig = true }
    packaging.resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui:1.7.8")
    implementation("androidx.compose.ui:ui-graphics:1.7.8")
    implementation("androidx.compose.ui:ui-tooling-preview:1.7.8")
    implementation("androidx.compose.foundation:foundation:1.7.8")
    implementation("androidx.compose.material3:material3:1.3.1")
    implementation("com.naver.maps:map-sdk:3.23.3")
    testImplementation("junit:junit:4.13.2")
    debugImplementation("androidx.compose.ui:ui-tooling:1.7.8")
}
