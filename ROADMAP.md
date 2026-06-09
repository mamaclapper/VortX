# Roadmap

Where StremioX is headed, roughly in the order we'll build it. No fixed dates; it ships when it's good.

The engine and add-on protocol already work, so the focus is everything around them: the best player and interface we can build, first on Apple TV and then across the rest of our devices. The aim is an all-in-one media hub, done one solid piece at a time.

## Now (heading to 1.0)

1. **Smart track selection.** Pick the right audio and subtitle track automatically from your preferred languages, respect forced subtitles, remember your per-show choices, and let you set reject lists for tracks you never want.
2. **Gestures and zoom.** Aspect, zoom, and fill, pinch to zoom, and gestures for seek, volume, brightness, and hold-to-speed.
3. **HDR and lossless audio.** HDR and Dolby Vision in 10-bit, plus audio passthrough so TrueHD, DTS-HD MA, and Atmos reach your receiver untouched.
4. **Skip and continue.** Skip intro and outro, then roll straight into the next episode.
5. **Downloads and Usenet.** Save a title to watch offline, and pull from Usenet alongside torrents and debrid.
6. **Themes.** Built-in themes and a theme studio for your own colours, a true-black OLED mode, a layout you can rearrange, the player itself themeable down to the seek bar and controls, themes you can share, backgrounds that take their colour from the artwork, and motion with character.
7. **No more buffering.** Heavy caching and pre-processing so playback starts fast and stays smooth, switching audio or subtitle tracks happens instantly instead of restarting the stream, the next episode loads before you reach it, seek-preview thumbnails ride the scrubber, and the player quietly recovers (or hops to another source) if a stream stalls instead of leaving you stuck.
8. **iPhone and iPad.** The same native app on iOS and iPadOS, off the web host. This is the 1.0 headline.
9. **Watch now, or choose.** Rank the sources and auto-play the best one for the quality you prefer, with two buttons on every title: Watch Now for the top stream, or Select Streams for the full list. A trust filter drops cam-rips, dead links, wrong episodes, and fake quality labels, and debrid is built in so you don't need a separate debrid add-on.
10. **Richer detail pages.** Ratings from more than one source (IMDb, TMDB, Trakt, MAL, AniList), cast and crew with photos, studio and network badges, trailers, poster rating overlays, and award browsing.
11. **Better search.** Real filters and proper advanced search.
12. **Profiles.** Separate libraries, history, and settings per person, with a parental PIN, and a way to back up or share your whole setup.
13. **Self-hosted source.** Run your own back end instead of leaning only on add-ons.

## Further out

The bigger pieces, each its own chunk of work, added as it earns its place:

- **Live TV, done properly.** A real channel guide (EPG), catch-up and timeshift, recording, and multiview.
- **Audio.** Music, podcasts, and audiobooks in the same app.
- **Casting.** AirPlay first, then Chromecast, DLNA, and Roku.
- **Watch together.** Synced playback with chat, on a relay you can host yourself.
- **Anime, first-class.** AniList and Kitsu tracking, season merging, and a release feed.
- **Deeper playback.** Shader upscaling, tone-mapping for SDR screens, and colour and audio profiles.
- **Streaming on our terms.** A built-in torrent engine so torrents work without debrid, and a place to plug in your own scrapers.
- **Trakt and a calendar.** Scrobbling and a release calendar across your library and watchlist.
- **Niceties.** Discord presence, a built-in ad and tracker blocker, and setup backup and restore.

## Shipped

- **Apple TV, native on the engine.** Home with real Continue Watching and every catalog, plus Discover, Library, Detail, the full per-add-on source list, Search, and add-on management. Watched state, resume, and live progress all run through the engine.
- **The player.** Full-screen libmpv with dependable focus and controls, a seekable scrubber with hold-to-seek, an options panel split into Audio, Subtitles, Aspect, and Episodes, audio and subtitle sync, aspect modes, language-grouped tracks, subtitle fonts for every script, and add-on load progress while streams arrive.
- **The basics.** Sign-in, smooth 4K, posters that load, solid caching, and a player you can always back out of.
- **iPhone and iPad, for now.** A web UI with a native libmpv player and external-player handoff, until the native client replaces it.

## Distribution

A self-hosted update channel is coming early, so the app can update itself rather than expire like an ordinary sideload. First-run setup for add-ons and debrid rides along with it.
