# Feature parity with Stremio

A running diff of what Stremio shipped recently (all platforms) versus what StremioX has, so we know what to add. Sourced from the Stremio blog tech updates (#56 to #79, 2026), the stremio-web / stremio-core release notes, and the stremio-web feature branches.

## Stremio v6 (the current beta: App 6.0.1-beta.01, Shell 5.1.23, Server 4.20.17)

v6 is deployed to Stremio's beta channel (Mac app + web) ahead of public GitHub tags (the public repo still tags v5.0.0-beta.37, and the running build commit is not in the public history). v6 is not a rewrite: it is the same stremio-core engine StremioX already runs, with a wave of features layered on. The in-flight `feat/*` branches are the v6 program:

- **Full casting** (`feat/full-casting-support`, `android-tv-casting`): Chromecast / AirPlay.
- **Trakt integration** (`feat/trakt-import`, `fix/trakt-events`): import history and scrobble watch events.
- **EPG / live TV** (`feat/discover-epg-support`): program guide for live channels.
- **Infinite scroll on Home** (`board-infinite-scroll`): lazy-load more catalogs as you scroll.
- **Last-used stream per title** (`feat/meta-details-last-used-stream`): remember the source you played, for quick replay.
- **Interface size / UI scaling** (`feat/shell-interface-size`).
- **Stream proxying** (`proxy_streams_enabled`): proxy streams through the server.
- **Media-session controls** (`feat/media-session-control`), **hardware rendering** (`feat/hardware-rendering`), Discord rich presence (desktop), series episode picker, player polish (subtitle position, volume-on-scroll, statistics, fullscreen on Safari).

Because v6 rides on the same core, almost all of this is reachable from StremioX's existing `CoreBridge`; we just have not surfaced it. The highest-value v6 items for Apple are folded into the priority list below.

## Stremio's recent changelog, by platform

**Stremio v5 (web + desktop, the current generation, in beta)**: tech updates #69, #73, #77, #78
- Gamepad / controller support (Xbox, PlayStation, etc.).
- Media key support (play/pause, next/previous track).
- Video scale / zoom property.
- HDR badge indicator.
- Subtitle context menu (download subtitle, copy sub id, copy sub link).
- External player support for Infuse and Vidhub.
- Library items behavior improvements; translation (localization) improvements.

**Android TV v1.10.2 + Android Mobile v2.2.3 (June 2026, latest)**: tech update #79
- MPV player.
- Usenet support.
- Progressive seeking (the longer you hold, the bigger the step) + a seek-duration setting.
- Automatic subtitle selection setting.
- "Ends at" time and a clock on the player.
- Progress shown in the player's videos menu.
- Changelog in settings; refreshed settings / library / nav / login UI.

**Official Apple TV (tvOS) app**: tech update #57 (this is the feature-limited "Lite," our closest comparison)
- External player support for Infuse.
- Live video playback.
- Add to library from the dropdown menu.

## What StremioX already has (do not rebuild)

- libmpv player (Stremio only just added MPV to Android; StremioX shipped with it).
- Video fit / zoom / stretch, audio + subtitle track picking, subtitle styling, playback speed, resume.
- Watched / unwatched markers (episode, season, whole series).
- Live playback progress into the engine; engine-sourced resume.
- Full engine-driven Home, Discover, Library, Detail, per-addon Streams, Search, Add-ons (with uninstall), Settings.
- iOS: Infuse / VLC external-player handoff.
- A native design system (the recent redesign).

## The gap, prioritized (all verified absent in our code)

### High value, tractable (engine already supports these)
1. **Add to / Remove from Library on the detail page.** The engine has the actions; we never expose them, so a title can only enter the library via account sync. Core library management.
2. **Last-used stream per title (v6).** Remember the source you played for a title and offer a quick replay, instead of re-picking from the stream list every time.
3. **Infinite scroll / lazy-load more catalogs on Home (v6).** We load a fixed set of board rows; lazy-load more on scroll. This is the fix for the old "press down forever to reach more catalogs" complaint.
4. **Progressive seeking + seek-duration setting.** We have fixed plus/minus 10s; add an accelerating seek and a base-step setting.
5. **"Ends at" time + a clock on the player overlay.** Small, high-perceived-quality.
6. **Automatic subtitle selection (preferred language) + hide-other-languages filter** in the subtitle menu.
7. **Addon subtitles (OpenSubtitles) with a download / copy context menu.** Already roadmapped; v5/v6 work confirms its importance.

### Medium
8. **Trakt integration (v6).** Import history and scrobble watch events. The engine supports Trakt; higher effort (auth + an addon flow) but high value for power users.
9. **HDR / Dolby Vision badge on stream rows.** We show the addon's raw text; a parsed badge is cleaner.
10. **tvOS external-player handoff to Infuse.** The official tvOS app has this; our iOS already does.
11. **Interface size / UI scaling (v6).** Accessibility and TV-distance comfort.
12. **Media-session controls (v6), changelog in Settings, gamepad support, localization.**

### Niche / server-dependent (fits the custom-server direction)
13. **AirPlay / casting (v6).** More relevant to the iOS app than to Apple TV (the TV is already the screen).
14. **EPG / live TV (v6).** Program guide for live channels.
15. **Stream proxying (v6) and Usenet.** Both are server features and belong in a custom StremioX server.

## Notes

- Items 11 to 12 and a lot of advanced streaming live on the server side. They are the natural place for a custom StremioX streaming server (better than Stremio's proprietary `server.js` or an open-source drop-in), shipped behind a branch so stremio-core/server users stay put and others opt in.
- Nothing here blocks the current build; this is the post-stabilization backlog.
