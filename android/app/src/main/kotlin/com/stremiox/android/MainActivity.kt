package com.stremiox.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.stremiox.android.ui.StremioXApp

/// Android + Android TV entry point. The five-tab Compose shell in [StremioXApp] matches the iOS and
/// Apple TV structure and currently runs on offline preview data. The shared stremio-core engine
/// (stremio-core-kotlin over JNI) and the libmpv player drop in behind the repository seam next.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { StremioXApp() }
    }
}
