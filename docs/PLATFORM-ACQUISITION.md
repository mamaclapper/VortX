# Platform acquisition notes — how official Stremio builds each non-Apple client

Research 2026-06-13 to accelerate the Android, Android TV, and Windows/desktop tracks of the [0.3.0 PRD](0.3.0-PRD.md). Unlike the iOS app (which uses the PRIVATE `stremio-core-premium`), every non-Apple Stremio client is built from PUBLIC pieces, so we learn from source, not binary teardown. Verified by inspecting the official APKs' native-lib layout (download → unzip → list; not executed) and the GitHub org.

## What official Stremio ships (stremio.com/downloads, 2026-06-13)

| Platform | Version | Format | Notes |
|---|---|---|---|
| Windows | 5.0.22 (x64, ARM) | `.exe` (StremioSetup) | built on `stremio-shell-ng` |
| macOS | 5.1.24 (ARM, Intel) | `.dmg` (stremio-shell-macos) | same shell-ng line |
| Linux | 4.4 / Flatpak | `.deb`, flatpak | older 4.x line |
| Android phone | 2.2.3 | `.apk` (arm/arm64/x86_64) | `com.stremio.one` |
| Android TV | 1.10.2 | `.apk` (arm/arm64/x86_64) | **lags the phone 2.x line** |
| iOS | web only (native v2.0.0 on App Store) | — | private core |
| Samsung/LG/Sony/etc. | store apps | — | out of scope for us |

**Positioning intel:** their Android TV (1.10.2) trails the phone app (2.2.3), the same "TV client lags" pattern as iOS-TV-is-Lite. A polished native Android TV app is an edge, like our tvOS one.

## Official open-source repos + licenses (reuse matters)

| Repo | Lang | License | Use for us |
|---|---|---|---|
| `Stremio/stremio-core` | Rust | **MIT** | already vendored; the engine for every platform |
| `Stremio/stremio-core-kotlin` | Rust | custom (verify) | Android JNI binding — reference / reuse if license allows |
| `Stremio/stremio-web` | JS (React) | **GPL-2.0** | desktop UI; embedding it makes that app GPL-2.0 |
| `Stremio/stremio-shell-ng` | Rust | custom/none | desktop shell reference (Rust + WebView2 + mpv) |
| `Stremio/stremio-shell` | C++ (Qt5) | none | legacy desktop (superseded by shell-ng) |
| `Stremio/libmpv-android`, `vlc-android`, `nodejs-mobile`, `ffmpeg-android-maker` | mixed | open | Android player + server building blocks |

License rule: stremio-core (MIT) is freely reusable. stremio-web (GPL-2.0) and the custom-licensed shells are **reference unless we accept their license terms** for a given track. Do not assume MIT.

## Verified Android stack (from the v1.10.2 TV + v2.2.3 phone APK native libs — identical on both)

Both APKs bundle exactly:
- **`libstremio_core_kotlin.so`** — stremio-core (MIT) + the `stremio-core-kotlin` JNI binding. This is the engine + bridge, same role as our `StremioXCore.xcframework` + `CoreBridge` on Apple.
- **`libmpv.so` + `libav{codec,format,util,filter,device}.so` + `libass.so` + `libasskt.so`** — **mpv is the primary player** (same engine family as our Apple libmpv/MPVKit). `libasskt` = an mpv/libass Kotlin wrapper.
- **`libvlc.so` + `libvlcjni.so`** — VLC bundled as an alternate backend (runtime-switchable player, the Chillio-style feature).
- **`libmedia3ext.so` + `libgav1JNI.so`** — AndroidX Media3 (ExoPlayer) + dav1d AV1 — a third backend / AV1 path.
- **`libnode.so` + `libstremio-server.so` + `assets/server.js`** — nodejs-mobile running the SAME server.js streaming server we ship (4.21.0 family).
- **`libplayer.so`** — their player-abstraction layer over the three backends.
- libcrashlytics (Firebase) — we'd use our own / none.

## Our build plan, de-risked

### Android + Android TV (track 10)
Write only the **Kotlin/Compose UI** (phone) + a **Compose-for-TV / Leanback** surface; everything below is open-source we assemble:
1. **Engine:** build `stremio-core` for Android (`aarch64-linux-android`, `armeabi-v7a`, `x86_64`) via the `stremio-core-kotlin` binding (reference it; confirm its license before copying code). Mirror our JSON `CoreBridge` contract in Kotlin. Port `StreamRanking` / `SourcePreferences` logic to Kotlin (or call the Rust core).
2. **Player:** `libmpv-android` primary (matches our Apple mpv); optionally Media3/ExoPlayer + libVLC as fallbacks later.
3. **Server:** `nodejs-mobile` (Android) + our existing `server.js` in assets, identical to how official does it and how our iOS/tvOS NodeServer works.
4. **UI:** our own design system ported to Compose (the tvOS `Theme` tokens carry over conceptually).
First concrete step when this track starts: stand up the Rust core Android cross-compile + a "hello, schemaVersion" JNI smoke test, exactly like the iOS engine smoke test.

### Windows / desktop (track 11)
Follow **`stremio-shell-ng`'s** architecture (it's the current shipping desktop): a **Rust shell + WebView2 + mpv**, hosting a web UI + the embedded server. Two options:
- **(a) Tauri shell** (Rust) + a web UI + `server.js` + mpv sidecar — closest to shell-ng, lightest. If we embed `stremio-web` (GPL-2.0) the desktop app is GPL-2.0; or we build our own web UI.
- **(b)** Reuse shell-ng directly if its license permits (currently unclear — treat as reference).
macOS desktop already has a cheaper path for us: **Mac Catalyst on our iOS SwiftUI** (track 9), no shell needed.

### Apple (tracks 1, 9) — unchanged, still first
iOS/iPadOS native on the shared `SourcesShared` + `Sources/Player`; Mac via Catalyst once iOS lands. 60-70% already built and shared.

## Net effect on sequencing
The Android stack is now fully mapped to open-source parts, so the Android/TV track can start its **core-JNI cross-compile** in parallel with the Apple UI work whenever we choose — it no longer needs discovery. Windows follows shell-ng. Apple-shared remains the fastest path to a shippable 0.3.0, so it stays first.
