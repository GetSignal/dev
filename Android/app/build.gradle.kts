plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.example.signal_android"
    compileSdk = 35

    // Allow CI/local overrides
    val apiBase: String = System.getenv("API_BASE_URL") ?: (project.findProperty("API_BASE_URL") as String? ?: "https://api.example.com")
    val enableScrub: Boolean = (System.getenv("ENABLE_LONG_PRESS_SCRUB") ?: (project.findProperty("ENABLE_LONG_PRESS_SCRUB") as String? ?: "false")).toBoolean()

    defaultConfig {
        applicationId = "com.example.signal_android"
        minSdk = 22
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Feature flags and endpoints
        // Endpoint + feature flags (can be overridden via env or -P props)
        buildConfigField("String", "API_BASE_URL", '"' + apiBase + '"')
        buildConfigField("boolean", "ENABLE_LONG_PRESS_SCRUB", enableScrub.toString())
        buildConfigField("boolean", "AUTOMATION_METRICS", (System.getenv("AUTOMATION_METRICS") ?: "false").toBoolean().toString())
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation("androidx.viewpager2:viewpager2:1.0.0")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation("com.google.android.exoplayer:exoplayer:2.19.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
