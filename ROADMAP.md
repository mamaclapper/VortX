# Roadmap

A community build, no fixed schedule, in priority order. Full feature checklist:
[docs/FEATURE-PARITY.md](docs/FEATURE-PARITY.md); iOS plan: [docs/REBASE-iOS.md](docs/REBASE-iOS.md).

**Guiding bet:** the player is the differentiator. The engine (`stremio-core`) and addon protocol stay; we
build the best native UI and the best libmpv playback on top, then take it to every platform. Streams come
from addons + debrid; the on-device server stays optional/advanced.

## Phase 0: Finish the tvOS player (now)

- Reliable controls, native tab bar, server config + status, Test (done).
- Options split into **Audio / Subtitles / Aspect / Episodes** (separate, titled panels) (done).
- **Subtitle sync** (±, live value, reset) and **aspect modes** (Fit / Fill / Stretch) (done).
- **All-language subtitle fonts** (Latin/Cyrillic, CJK, Arabic, Hebrew, Thai, Devanagari fallback) (done).
- **Tracks grouped by language** (audio + subtitles) (building).
- **Subtitle Settings** sub-panel: sync, size, colour, transparency (building).
- **Audio Settings** sub-panel: audio sync/delay (building).
- **Catalog titles** read the addon's real name + type (e.g. "Trending Movies", not "Trending Trending").

## Phase 1: Player + sources, deeper (tvOS)

### Source intelligence (highest-value)
- Trust filter (drop cam-rips, dead torrents, wrong-episode, fake quality labels).
- Stream ranking + **Auto-Play Best Stream**.
- Regex/keyword stream tags and rejection lists.
- Native in-app debrid keys (multiple services, uniform cache check) alongside addons.
- Stream preloading / cache-ahead so playback doesn't buffer.

### Subtitles + tracks
- Subtitle source aggregation (OpenSubtitles-style) with dedupe, on top of subtitle addons.
- Smart track auto-selection (preferred audio/subtitle language, forced-subtitle override).
- Skip intro/outro with an on-screen button; auto next-episode.

### Playback quality
- HDR / Dolby Vision passthrough + HDR→SDR tonemapping with a target-nits setting.
- Audio passthrough (TrueHD / DTS-HD MA / Atmos bitstreaming) for receivers.
- Anime upscaling shaders with quality presets (frame-interpolation is out of scope on this hardware).
- Casting: AirPlay first.

### Look & feel
- Theme system: accent + full colour theming, presets, (later) custom layout.

### Source types
- Downloads (debrid/HTTP → local, play offline).
- Usenet (via the server/addon path).

## Phase 2: iPhone / iPad parity

Rebuild iOS/iPadOS as a native client on the engine (off the hosted web UI): share the engine + design +
player, build the touch screens and a native touch player, carry the theme system over, add an iPad layout,
retire the web host at parity.

## Phase 3: Ground-up project (new name, every device)

A fresh app for Apple, Android, Windows, Linux, and web. Reuse a shared Rust core as the brain, build our
own UI per platform, and build **our own streaming server** (torrent + Usenet fetch, remux, full
cache-ahead): the genuinely high-value piece. Phased: shared core + UI first, server in parallel.

## Cross-cutting (slot in early)

- **Distribution / auto-update:** a self-hosted update source so the app updates itself (sideloaded certs
  expire; manual re-sideload caps reach).
- First-run **onboarding** (addons + debrid setup).
- **Profiles** (per-user, parental PIN) and **Trakt** sync / scrobbling / release calendar.

## Later

- Live TV (playlist/provider sources, EPG grid, catchup, recording).
- Watch-together (synced playback, chat), multiview, webhooks.
- Apple TV Top Shelf, external-player handoff, interface scaling, CI build.

## Done

### Apple TV (native on the engine)
- Home (real Continue Watching + every catalog), Discover, Library, Detail, full source list, Search,
  Add-ons: all engine-driven; watched markers + engine resume + live progress.
- Cinematic UI on a shared design system; redesigned player.
- Reliability: sign-in seeds the engine; full-screen player with reliable focus/controls; Back returns to
  the tab; posters load; aggressive caching; broad subtitle script coverage; smooth 4K.

### Cross-platform / project
- Sign-in token in the Keychain; engine builds for tvOS + iOS.
- Unsigned sideloaded builds with checksums; security policy, private vulnerability reporting, Dependabot,
  secret scanning + push protection, engine code scanning.

### iPhone / iPad (interim)
- Hosts a web UI with a native libmpv player + external-player handoff: being replaced by the native
  client in Phase 2.
