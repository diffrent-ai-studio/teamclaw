pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "teamclaw-android"

include(":core:design", ":core:model", ":core:deeplink", ":core:network", ":core:auth")
include(":feature:onboarding")
include(":app")
