plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "tech.teamclaw.android.core.design"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    api(platform(libs.compose.bom))
    api(libs.compose.ui)
    api(libs.compose.material3)
    api(libs.compose.foundation)
    debugApi(libs.compose.ui.tooling)
    api(libs.compose.ui.tooling.preview)

    testImplementation(libs.junit.jupiter)
    testImplementation(libs.truth)
}

tasks.withType<Test> { useJUnitPlatform() }
