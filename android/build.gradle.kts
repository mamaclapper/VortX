// Root build file. Plugin versions declared here, applied per-module. Kotlin 2.0+ is required for
// the standalone Compose compiler plugin (org.jetbrains.kotlin.plugin.compose).
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
}
