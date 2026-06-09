# Roadmap

Where StremioX is headed, roughly in the order we'll build it. No fixed dates; it ships when it's good.

The engine and add-on protocol already work, so the focus is everything around them: the best player and interface we can build, first on Apple TV and then across the rest of our devices. The aim is an all-in-one media hub, done one solid piece at a time.

## The version path

- **0.2.0 (shipped).** Skip intro and outro, and the cinematic full-bleed redesign of movie and episode pages.
- **0.3.0 (next).** The native iPhone and iPad app, on the same engine as the Apple TV app, replacing the web-host build.
- **0.x.** The features below, shipped one solid piece at a time.
- **1.0.** Our own engine and our own streaming server, replacing the pieces we currently inherit. That milestone also brings a new identity for the app.

## Next up

1. **Skip detection that works on everything.** 0.2.0 ships crowd-sourced timestamps merged with chapter markers. The next layers make it near-universal: anime coverage through a second timestamp database, on-device detection (audio fingerprinting across episodes, black-frame and silence analysis) for titles no database knows, contributing timestamps back from the player, and an auto-skip option with a cancel countdown.
2. **iPhone and iPad.** The same native app on iOS and iPadOS, off the web host. This is 0.3.0.
3. **Smart track selection, finished.** Preferred languages and per-show memory shipped; still to come are a forced-subtitles-only mode and reject lists for tracks you never want.
4. **HDR and lossless audio, verified end to end.** HDR and Dolby Vision in 10-bit, a fallback that plays dual-layer Dolby Vision as HDR10 instead of failing, frame-rate matching, and audio passthrough so TrueHD, DTS-HD MA, and Atmos reach your receiver untouched.
5. **Binge mode.** Auto-play next already works; making it stick to the same release group across episodes so quality never jumps mid-season, plus seek-preview thumbnails on the scrubber.
6. **Cross-device continue watching.** Scrobbling and playback sync so you can pause on the TV and pick up on the iPad, alongside Trakt scrobbling, history, and a release calendar.
7. **Downloads and Usenet.** Save a title to watch offline, and pull from Usenet alongside torrents and debrid.
8. **Deep themes.** The accent system shipped; next are a theme studio, layout variants for the home screen, show-and-hide for tabs you never use, poster styling options, and a player themed down to the seek bar.
9. **Stream intelligence, finished.** Ranking and Watch Now shipped; still to come are a trust filter that drops cam-rips, dead links, and fake quality labels, keyword include and exclude filters, and debrid built in so you don't need a separate configuration site.
10. **Richer detail pages.** Ratings from more than one source, cast and crew with photos, studio badges, trailers, and where-to-stream context.
11. **Better search.** Search across every catalog your add-ons expose, with real filters.
12. **Profiles.** Separate libraries, history, and settings per person, with a parental PIN, and a way to back up or share your whole setup.
13. **Pick your metadata source.** Let any metadata add-on drive the home screen, so one provider's outage never takes the app down.

## Further out

The bigger pieces, each its own chunk of work, added as it earns its place:

- **Our own engine and server (the 1.0 milestone).** The catalog, library, and streaming stack in our own code, built from the best open-source pieces, so the app depends on nobody's backend decisions but ours. A built-in torrent engine so torrents work without debrid, and a place to plug in your own scrapers, ride along with it.
- **Live TV, done properly.** A real channel guide (EPG), catch-up and timeshift, recording, and multiview.
- **Audio.** Music, podcasts, and audiobooks in the same app.
- **Casting.** AirPlay first, then Chromecast, DLNA, and Roku.
- **Watch together.** Synced playback with chat, on a relay you can host yourself.
- **Anime, first-class.** Tracking, season merging, and a release feed.
- **Deeper playback.** Shader upscaling, tone-mapping for SDR screens, and colour and audio profiles.
- **Niceties.** Discord presence, a built-in ad and tracker blocker, and setup backup and restore.

## Shipped

- **Skip intro and outro (0.2.0).** A skip pill the moment you enter a known segment: crowd-sourced timestamps looked up by IMDB, TMDB, or TVDB id, merged with the file's named chapters, with sanity guards and on-device caching.
- **The cinematic redesign (0.2.0).** Movie and episode pages went full-bleed: the artwork fills the screen, the details sit over it, and the dead space is gone. The focused tab follows your accent.
- **Watch Now and stream ranking (0.1.7.x).** Sources ranked with cached and direct streams first, one press plays the best, long-press picks a resolution, and the full per-add-on list stays one button away.
- **Themes (0.1.7.x).** Eight accents plus a true-black OLED mode, persisted, with the whole app repainting live.
- **Player resilience (0.1.7.x).** Bounded auto-retry with a reconnecting indicator when a stream hiccups, and an in-player source switcher that keeps your position.
- **Library management (0.1.7.x).** Long-press menus on posters everywhere: dismiss from Continue Watching, add to library, mark watched and unwatched, remove from library. Finished titles leave Continue Watching on their own.
- **Smart track selection (0.1.7.x).** Audio and subtitles picked from your preferred languages automatically, with per-show memory.
- **Apple TV, native on the engine.** Home with real Continue Watching and every catalog, plus Discover, Library, Detail, the full per-add-on source list, Search, and add-on management. Watched state, resume, and live progress all run through the engine.
- **The player.** Full-screen libmpv with dependable focus and controls, a seekable scrubber with hold-to-seek, an options panel split into Audio, Subtitles, Aspect, and Episodes, audio and subtitle sync, aspect modes, language-grouped tracks, subtitle fonts for every script, and add-on load progress while streams arrive.
- **The basics.** Sign-in, smooth 4K with TrueHD and Atmos and HDR that actually play, posters that load, solid caching, and a player you can always back out of.
- **iPhone and iPad, for now.** A web UI with a native libmpv player and external-player handoff, until the native client replaces it.

## Distribution

A self-hosted update channel is coming early, so the app can update itself rather than expire like an ordinary sideload. First-run setup for add-ons and debrid rides along with it.
