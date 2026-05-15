import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val secrets = Properties().apply {
    val local = rootProject.file("local.properties")
    if (local.exists()) load(local.inputStream())
    val defaults = rootProject.file("secrets.defaults.properties")
    if (defaults.exists()) load(defaults.inputStream())
}

android {
    namespace = "tech.teamclaw.android"
    compileSdk = 35
    defaultConfig {
        applicationId = "tech.teamclaw.mobile.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.1.5"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "SUPABASE_URL", "\"${secrets.getProperty("SUPABASE_URL", "")}\"")
        buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", "\"${secrets.getProperty("SUPABASE_PUBLISHABLE_KEY", "")}\"")
        buildConfigField("String", "SENTRY_DSN", "\"${secrets.getProperty("SENTRY_DSN", "")}\"")
        buildConfigField("String", "APPLE_SERVICE_ID", "\"${secrets.getProperty("APPLE_SERVICE_ID", "")}\"")
        buildConfigField("String", "GOOGLE_OAUTH_CLIENT_ID", "\"${secrets.getProperty("GOOGLE_OAUTH_CLIENT_ID", "")}\"")

        // AppAuth-Android injects a manifest placeholder for its OAuth redirect
        // intent filter. We don't use AppAuth's built-in RedirectUriReceiverActivity
        // (Apple sign-in is launched via Custom Tabs and returns through our own
        // teamclaw://auth-callback handler), so set a dummy value that AppAuth's
        // manifest merger accepts.
        manifestPlaceholders["appAuthRedirectScheme"] = "teamclaw"
    }
    buildTypes {
        debug { }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources {
            // HiveMQ pulls in Netty, which ships META-INF service descriptors
            // and INDEX.LIST files that collide between netty-* artifacts.
            excludes += "META-INF/INDEX.LIST"
            excludes += "META-INF/io.netty.versions.properties"
            excludes += "META-INF/native-image/**"
            pickFirsts += "META-INF/AL2.0"
            pickFirsts += "META-INF/LGPL2.1"
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation(project(":core:design"))
    implementation(project(":core:network"))
    implementation(project(":core:auth"))
    implementation(project(":core:model"))
    implementation(project(":core:deeplink"))
    implementation(project(":feature:onboarding"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.nav.compose)
    implementation(libs.sentry.android)
    implementation(libs.sentry.compose)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    testImplementation(libs.junit.jupiter)
    testImplementation(libs.truth)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.compose.ui.test.junit4)
}

tasks.withType<Test> { useJUnitPlatform() }
