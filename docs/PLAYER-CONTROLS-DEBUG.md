# StremioX tvOS player: remote-input / controls bug (second opinion wanted)

## Summary
SwiftUI tvOS app. The video player (`TVPlayerView`) is presented with `.fullScreenCover` and plays video
via **libmpv (MPVKit)** rendered into a `CAMetalLayer`. The on-screen control bar will **not reliably
show or respond to the Siri remote**. ~5 approaches tried, none work. Need a reliable way to (a) keep all
remote input owned by the player while it is on screen, and (b) show/navigate the control bar.

## Environment
- tvOS (Apple TV 4K and the tvOS Simulator — same behavior). Xcode 16. Swift / SwiftUI.
- App shell: `TabView` (top tab bar) → each tab is a `NavigationStack`. A Detail view is pushed; tapping a
  stream presents `TVPlayerView` via `.fullScreenCover(item:)`.
- Player core: **MPVKit 0.41.0** (libmpv) rendered into a `CAMetalLayer` (`vo=gpu-next`,
  `gpu-api=vulkan`, `gpu-context=moltenvk`) inside a `UIViewControllerRepresentable`
  (`MPVMetalPlayerView` → `MPVMetalViewController`).

## Symptoms (with the CURRENT build = approach 5 below)
- The control bar shows at player launch, then auto-hides after 8s.
- After it hides, pressing the remote (swipe / Up / Select) does **not** reliably bring it back. Sometimes
  it flashes for ~0.5s then vanishes and never returns no matter what button is pressed.
- Pressing **Right arrow before playback started dismissed the whole player** once.
- Net: the control bar is effectively unusable. (Note: playback itself, subtitles, etc. all work — this is
  purely the remote-input / control-bar-focus problem.)

## What we've tried (all failed)
1. SwiftUI `.focusable()` on the root `ZStack` + `.onMoveCommand` / `.onTapGesture` / `.onExitCommand`
   + `@FocusState`. Controls rarely showed; focus never seemed to land inside the cover.
2. A focusable `Button` (full-screen, `Color.clear` label) as a catch layer → it DID grab focus, but tvOS
   painted a full-screen **white focus highlight** over the whole video.
3. A focusable `Color.clear` catch layer (not a Button) → no highlight, but `onMoveCommand` still did not
   fire reliably (focus did not seem to stay on it).
4. `.defaultFocus`, deferring the focus assignment to the next runloop, etc. → no change.
5. **CURRENT:** moved ALL remote handling to a UIKit `UIView` (`CatchView`) overriding `pressesBegan`,
   driving the control bar + options panel from plain `@State` (no SwiftUI focus anywhere). Added a focus
   "trap" via `didUpdateFocus` that re-grabs focus if it tries to leave. Still broken (symptoms above).

## Current hypothesis
The `.fullScreenCover` on tvOS is **not isolating focus**: a directional press both fires our handler AND
the focus engine moves focus out to the `TabView`'s tab bar behind the cover, after which the player stops
receiving input. The `didUpdateFocus` re-grab did not fix it. We suspect the real fix is to NOT use
`.fullScreenCover` (e.g. present the player as a root-level overlay above the `TabView`, or as a fully
UIKit-hosted player view controller that owns its focus environment / traps focus), or some other
focus-isolation technique we are missing.

## The question
On tvOS, what is the correct, reliable way to keep ALL Siri-remote input (arrows, select, menu, play/pause)
owned by this libmpv player while it is on screen, and to drive an on-screen control bar, given the player
is a SwiftUI `.fullScreenCover` over a `TabView`, with the video in a `CAMetalLayer` via a
`UIViewControllerRepresentable`? Is `.fullScreenCover` the problem? Should the whole player be a
`UIViewController` that manages focus? How do we trap focus so directional input cannot escape to the tab
bar, while still letting Menu dismiss the player?

## The code
Three files follow:
1. `TVPlayerView.swift` — the SwiftUI player view, control bar, options panel, and the UIKit `CatchView`
   remote handler (this is where the bug lives).
2. `MPVMetalPlayerView.swift` — the `UIViewControllerRepresentable` wrapper.
3. `MPVMetalViewController.swift` — the libmpv + `CAMetalLayer` core (for context; note the tvOS comment
   in `viewDidLoad` about deliberately NOT adding a tap gesture recognizer).

---

### 1. app/SourcesTV/TVPlayerView.swift

```swift
import SwiftUI
import UIKit
import os

/// Full-screen libmpv player for tvOS. All remote input is handled at the UIKit level by a focusable
/// `RemoteCatcher` (pressesBegan), and the control bar / options panel are driven by plain state with
/// no SwiftUI focus, because SwiftUI `@FocusState` is unreliable inside a full-screen cover on tvOS.
/// Shares the MPVKit core with the iOS app.
struct TVPlayerView: View {
    let url: URL
    let title: String
    var meta: PlaybackMeta? = nil          // when set, resume + record watch progress to the library
    var episodes: [Video] = []             // series' ordered episodes (empty for movies) → Next/Prev/list

    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var core: CoreBridge
    @State private var markedWatched = false   // mark the engine watched once, near end of playback
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = MPVMetalPlayerView.Coordinator()
    @State private var buffering = true
    @State private var isPaused = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var videoHeight = 0          // metadata line: encoded height (2160 -> "4K")
    @State private var audioCodec = ""          // metadata line: active audio codec (e.g. "eac3")
    @State private var isHDR = false            // metadata line: HDR/DV detected (sig-peak > 1)
    @State private var resumeSeconds: Double? = nil   // nil until fetched; applied once duration known
    @State private var appliedResume = false
    @State private var lastSaved = -1.0               // last position persisted (throttle)
    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?
    @State private var audioTracks: [MPVTrack] = []
    @State private var subtitleTracks: [MPVTrack] = []
    @State private var showOptions = false             // audio/subtitle/episode list panel
    @State private var optionRow = 0                   // highlighted row in the options panel
    @State private var loadFailed = false              // playback couldn't start
    @State private var loadErrorMsg = ""
    @State private var hasStartedPlaying = false
    @State private var loadTimeout: Task<Void, Never>?
    // Current episode (changes when switching via Next/Prev/Episodes or auto-advance). Seeded from
    // the passed url/title/meta in onAppear so the first load is unchanged.
    @State private var curURL: URL?
    @State private var curTitle: String = ""
    @State private var curMeta: PlaybackMeta?

    /// Which on-screen control is currently highlighted (driven by remote left/right, not SwiftUI focus).
    private enum Control: Hashable { case close, back, play, fwd, audio, subs, prev, next, episodes }
    @State private var selected: Control = .play
    private let plog = Logger(subsystem: "com.stremiox.app", category: "tvplayer")

    private var controlsHidden: Bool { !showInfo && !showOptions && !loadFailed }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            MPVMetalPlayerView(coordinator: coordinator)
                .play(url)
                .onPropertyChange { _, name, data in
                    switch name {
                    case MPVProperty.pausedForCache: if let b = data as? Bool { buffering = b }
                    case MPVProperty.pause:
                        if let b = data as? Bool {
                            isPaused = b
                            if b { saveProgress(at: currentTime) }   // persist on pause
                        }
                    case MPVProperty.timePos:
                        if let d = data as? Double {
                            if d > 0, !hasStartedPlaying {            // playback actually began
                                hasStartedPlaying = true; loadTimeout?.cancel(); loadFailed = false
                            }
                            currentTime = d
                            if lastSaved < 0 || abs(d - lastSaved) >= 20 {   // persist ~every 20s
                                lastSaved = d
                                saveProgress(at: d)
                                core.reportProgress(timeSeconds: d, durationSeconds: duration)   // live -> engine
                            }
                            if !markedWatched, duration > 0, d / duration >= 0.9, let m = curMeta {
                                markedWatched = true            // ~90% in → flip the watched marker live
                                core.markPlaybackWatched(m)
                            }
                        }
                    case MPVProperty.videoParamsSigPeak:
                        if let p = data as? Double { isHDR = p > 1.0 }
                    case MPVProperty.duration:
                        if let d = data as? Double { duration = d; maybeResume() }
                    case MPVProperty.trackList:
                        refreshTracks()
                        let s = coordinator.player?.mediaSummary()
                        videoHeight = s?.height ?? 0; audioCodec = s?.audioCodec ?? ""
                    case MPVProperty.endFileError:
                        loadTimeout?.cancel()
                        if !hasStartedPlaying { loadErrorMsg = (data as? String) ?? ""; withAnimation { loadFailed = true } }
                    case MPVProperty.endFileEof:
                        if !markedWatched, let m = curMeta { markedWatched = true; core.markPlaybackWatched(m) }
                        autoAdvance()                                // episode finished → play next, else exit
                    default: break
                    }
                }
                .ignoresSafeArea()

            // UIKit owns ALL remote input (reliable inside the full-screen cover, unlike SwiftUI focus).
            RemoteCatcher { handlePress($0) }

            if buffering && !loadFailed {
                ProgressView().controlSize(.large).tint(Theme.Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showInfo && !showOptions && !loadFailed { controlBar }
            if showOptions { optionsPanel }
            if loadFailed { loadErrorOverlay }
        }
        .onAppear {
            if curURL == nil { curURL = url; curTitle = title; curMeta = meta }   // seed from initial
            showInfo = true; selected = .play; scheduleHide(); startLoadTimeout()
            if let m = curMeta {
                if let engineResume = core.engineResumeSeconds(for: m) {
                    resumeSeconds = engineResume; maybeResume()       // engine library = source of truth
                } else {
                    Task { resumeSeconds = await account.resumeOffset(for: m); maybeResume() }
                }
            } else {
                resumeSeconds = 0   // selftest / no library context, nothing to resume
            }
        }
        .onDisappear {
            hideTask?.cancel(); loadTimeout?.cancel()
            saveProgress(at: currentTime)
            core.reportProgress(timeSeconds: currentTime, durationSeconds: duration)   // flush final position to the engine
        }
    }

    // MARK: - Remote handling (all input arrives here from the UIKit catcher)

    private func handlePress(_ type: UIPress.PressType) {
        if loadFailed {
            switch type {
            case .menu: saveProgress(at: currentTime); dismiss()
            case .select, .playPause: retryLoad()
            default: break
            }
            return
        }
        if showOptions {
            switch type {
            case .menu: closePanel()
            case .upArrow: moveOption(-1)
            case .downArrow: moveOption(1)
            case .select: activateOption()
            default: break
            }
            return
        }
        if controlsHidden {
            switch type {
            case .menu: saveProgress(at: currentTime); dismiss()
            case .playPause: toggle()
            default: showControls()                       // any swipe / select reveals the bar
            }
            return
        }
        // Control bar is shown: navigate it.
        switch type {
        case .menu: saveProgress(at: currentTime); dismiss()
        case .playPause: toggle()
        case .select: activate(selected)
        case .leftArrow: moveSelected(-1)
        case .rightArrow: moveSelected(1)
        case .upArrow, .downArrow: flashControls()        // keep the bar up
        default: break
        }
    }

    /// Controls in remote left/right order (close is leftmost, then transport, then audio/subs/episodes).
    private var visibleControls: [Control] {
        var c: [Control] = [.close, .back]
        if episodes.count > 1 && hasPrevEpisode { c.append(.prev) }
        c.append(.play)
        if episodes.count > 1 && hasNextEpisode { c.append(.next) }
        c.append(.fwd)
        if !audioTracks.isEmpty { c.append(.audio) }
        c.append(.subs)
        if episodes.count > 1 { c.append(.episodes) }
        return c
    }

    private func moveSelected(_ d: Int) {
        let v = visibleControls
        let i = v.firstIndex(of: selected) ?? 0
        selected = v[max(0, min(v.count - 1, i + d))]
        flashControls()
    }

    private func activate(_ c: Control) {
        switch c {
        case .close: saveProgress(at: currentTime); dismiss()
        case .back:  seek(-10)
        case .fwd:   seek(10)
        case .play:  toggle()
        case .prev:  playPrevious()
        case .next:  playNext()
        case .audio, .subs, .episodes: openPanel()
        }
    }

    // MARK: - Control bar

    /// Resolution / HDR / audio summary under the title, read live from mpv.
    private var metadataLine: String {
        var parts: [String] = []
        switch videoHeight {
        case 2000...:     parts.append("4K")
        case 1300..<2000: parts.append("1440p")
        case 900..<1300:  parts.append("1080p")
        case 600..<900:   parts.append("720p")
        case 1..<600:     parts.append("\(videoHeight)p")
        default:          break
        }
        if isHDR { parts.append("HDR") }
        if !audioCodec.isEmpty { parts.append(audioLabel(audioCodec)) }
        return parts.joined(separator: "  ·  ")
    }

    private func audioLabel(_ c: String) -> String {
        switch c.lowercased() {
        case "eac3":               return "EAC3"
        case "ac3":                return "AC3"
        case "truehd":             return "TrueHD"
        case "dts", "dts-hd", "dca": return "DTS"
        case "aac":                return "AAC"
        case "flac":               return "FLAC"
        case "opus":               return "Opus"
        case "mp3":                return "MP3"
        default:                   return c.uppercased()
        }
    }

    private var controlBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Space.lg) {
                ctrlButton(.close, "chevron.left")
                Spacer(minLength: Theme.Space.lg)
                VStack(alignment: .trailing, spacing: 6) {
                    if !curTitle.isEmpty {
                        Text(curTitle).font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                    }
                    if !metadataLine.isEmpty {
                        Text(metadataLine).font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 60).padding(.top, 50)
            .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            VStack(spacing: Theme.Space.lg) {
                HStack(spacing: Theme.Space.md) {
                    Text(timeString(currentTime)).font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    scrubber
                    Text(timeString(duration)).font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ZStack {
                    HStack(spacing: Theme.Space.md) {
                        ctrlButton(.back, "gobackward.10")
                        if episodes.count > 1 && hasPrevEpisode { ctrlButton(.prev, "backward.end.fill") }
                        ctrlButton(.play, isPaused ? "play.fill" : "pause.fill", big: true)
                        if episodes.count > 1 && hasNextEpisode { ctrlButton(.next, "forward.end.fill") }
                        ctrlButton(.fwd, "goforward.10")
                    }
                    HStack(spacing: Theme.Space.md) {
                        if !audioTracks.isEmpty { ctrlButton(.audio, "waveform") }
                        ctrlButton(.subs, "captions.bubble")
                        if episodes.count > 1 { ctrlButton(.episodes, "list.bullet") }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 60).padding(.bottom, 50)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
        }
        .transition(.opacity)
    }

    /// Slim ember seek bar with a knob. Position display; seeking is via the ±10 controls.
    private var scrubber: some View {
        GeometryReader { geo in
            let frac = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.textPrimary.opacity(0.22)).frame(height: 6)
                Capsule().fill(Theme.Palette.accent).frame(width: max(0, w * frac), height: 6)
                Circle().fill(Theme.Palette.accent).frame(width: 18, height: 18)
                    .shadow(color: Theme.Palette.accent.opacity(0.6), radius: 6)
                    .offset(x: max(0, w * frac - 9))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 18)
    }

    /// Circular control, highlighted (ember fill + lift) when it is the selected control. Visual only;
    /// activation is driven by the remote handler, not a tap.
    private func ctrlButton(_ c: Control, _ icon: String, big: Bool = false) -> some View {
        let sel = (selected == c)
        let d: CGFloat = big ? 92 : 64
        return Image(systemName: icon)
            .font(.system(size: big ? 38 : 26, weight: .semibold))
            .foregroundStyle(sel ? Theme.Palette.canvas : Theme.Palette.textPrimary)
            .frame(width: d, height: d)
            .background(Circle().fill(sel ? Theme.Palette.accent : Theme.Palette.textPrimary.opacity(0.12)))
            .scaleEffect(sel ? 1.12 : 1.0)
            .animation(.easeOut(duration: 0.18), value: sel)
    }

    // MARK: - Options panel (audio / subtitles / episodes), driven by optionRow

    private struct OptionRow: Identifiable { let id = UUID(); let label: String; let isSelected: Bool; let action: () -> Void }

    private var optionRows: [OptionRow] {
        var rows: [OptionRow] = []
        for t in audioTracks {
            rows.append(OptionRow(label: "Audio  ·  " + t.label, isSelected: t.selected) {
                coordinator.player?.setAudioTrack(t.id); refreshTracksSoon()
            })
        }
        rows.append(OptionRow(label: "Subtitles  ·  Off", isSelected: subtitleTracks.allSatisfy { !$0.selected }) {
            coordinator.player?.setSubtitleTrack(-1); refreshTracksSoon()
        })
        for t in subtitleTracks {
            rows.append(OptionRow(label: "Subtitles  ·  " + t.label, isSelected: t.selected) {
                coordinator.player?.setSubtitleTrack(t.id); refreshTracksSoon()
            })
        }
        if episodes.count > 1 {
            for ep in episodes {
                rows.append(OptionRow(label: "E\(ep.episodeNumber)  ·  \(ep.episodeTitle)", isSelected: ep.id == curMeta?.videoId) {
                    play(episode: ep)
                })
            }
        }
        return rows
    }

    private var optionsPanel: some View {
        let rows = optionRows
        return HStack(spacing: 0) {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            HStack {
                                Text(row.label).lineLimit(1)
                                    .foregroundStyle(i == optionRow ? Theme.Palette.canvas : Theme.Palette.textPrimary)
                                Spacer()
                                if row.isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(i == optionRow ? Theme.Palette.canvas : Theme.Palette.accent)
                                }
                            }
                            .padding(.horizontal, Theme.Space.lg).padding(.vertical, Theme.Space.sm)
                            .background(i == optionRow ? Theme.Palette.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .id(i)
                        }
                    }
                    .padding(Theme.Space.lg)
                }
                .onChange(of: optionRow) { _ in withAnimation { proxy.scrollTo(optionRow, anchor: .center) } }
            }
            .frame(width: 760)
            .frame(maxHeight: .infinity)
            .background(Theme.Palette.surface1.opacity(0.98))
        }
        .ignoresSafeArea()
        .transition(.move(edge: .trailing))
    }

    private func moveOption(_ d: Int) {
        let count = optionRows.count
        guard count > 0 else { return }
        optionRow = max(0, min(count - 1, optionRow + d))
    }
    private func activateOption() {
        let rows = optionRows
        guard optionRow >= 0, optionRow < rows.count else { return }
        rows[optionRow].action()
    }

    private func openPanel() {
        refreshTracks()
        hideTask?.cancel()
        optionRow = optionRows.firstIndex { $0.isSelected } ?? 0
        withAnimation { showOptions = true }
    }
    private func closePanel() {
        withAnimation { showOptions = false }
        showInfo = true; selected = .play; scheduleHide()
    }

    private func refreshTracks() {
        audioTracks = coordinator.player?.tracks(ofType: "audio") ?? []
        subtitleTracks = coordinator.player?.tracks(ofType: "sub") ?? []
    }
    private func refreshTracksSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { refreshTracks() }
    }

    // MARK: - Load failure

    private var loadErrorOverlay: some View {
        ZStack {
            Theme.Palette.canvas.opacity(0.94).ignoresSafeArea()
            VStack(spacing: Theme.Space.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 60)).foregroundStyle(Theme.Palette.danger)
                Text("This source didn't load")
                    .font(Theme.Typography.sectionTitle).foregroundStyle(Theme.Palette.textPrimary)
                Text(loadErrorMsg.isEmpty
                     ? "It may still be downloading on your source, offline, or an unsupported link."
                     : "It may be unavailable, offline, or unsupported.  (\(loadErrorMsg))")
                    .font(Theme.Typography.body).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 900)
                Text("Menu = back to sources    ·    Play/Pause = retry")
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textTertiary).padding(.top, Theme.Space.xs)
            }
            .padding(Theme.Space.screenEdge)
        }
        .transition(.opacity)
    }

    private func startLoadTimeout() {
        loadTimeout?.cancel()
        loadTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !hasStartedPlaying else { return }
            if loadErrorMsg.isEmpty { loadErrorMsg = "Timed out, the source never started." }
            withAnimation { loadFailed = true }
        }
    }

    private func retryLoad() {
        withAnimation { loadFailed = false }
        buffering = true; hasStartedPlaying = false; appliedResume = false; loadErrorMsg = ""
        coordinator.player?.loadFile(curURL ?? url)
        startLoadTimeout()
    }

    // MARK: - Episode navigation (series only; `episodes` is the season's ordered list)

    private var episodeIndex: Int? { episodes.firstIndex { $0.id == curMeta?.videoId } }
    private var hasNextEpisode: Bool { episodeIndex.map { $0 + 1 < episodes.count } ?? false }
    private var hasPrevEpisode: Bool { (episodeIndex ?? 0) > 0 }

    private func playNext() { if let i = episodeIndex, i + 1 < episodes.count { play(episode: episodes[i + 1]) } }
    private func playPrevious() { if let i = episodeIndex, i > 0 { play(episode: episodes[i - 1]) } }

    /// Auto-advance when an episode ends: next episode if there is one, otherwise leave the player.
    private func autoAdvance() {
        if hasNextEpisode { playNext() } else { saveProgress(at: currentTime); dismiss() }
    }

    /// Switch to another episode in place: flush progress, resolve a stream, then reload mpv.
    private func play(episode v: Video) {
        guard let m = curMeta else { return }
        saveProgress(at: currentTime)
        withAnimation { showOptions = false }
        buffering = true; hasStartedPlaying = false; appliedResume = false
        loadFailed = false; currentTime = 0; duration = 0; lastSaved = -1; resumeSeconds = nil
        let newMeta = PlaybackMeta(libraryId: m.libraryId, videoId: v.id, type: "series",
                                   name: m.name, poster: m.poster, season: v.season, episode: v.episode)
        curMeta = newMeta
        curTitle = "\(m.name) · S\(v.season ?? 0)E\(v.episodeNumber) · \(v.episodeTitle)"
        showInfo = true; selected = .play; flashControls()
        Task {
            var client = AddonClient(); client.streamSources = account.streamSources
            let streams = await client.streams(type: "series", videoId: v.id)
            guard let s = streams.first(where: { $0.isPlayable }), let u = StremioServer.resolveURL(for: s) else {
                loadErrorMsg = "No playable source found for this episode."
                withAnimation { loadFailed = true }
                return
            }
            StremioServer.prepare(s)                       // torrents: create on the local server
            curURL = u
            resumeSeconds = await account.resumeOffset(for: newMeta)
            coordinator.player?.loadFile(u)
            startLoadTimeout()
        }
    }

    // MARK: - Playback helpers

    /// Seek to the saved position once BOTH the resume offset is fetched and the duration is known.
    private func maybeResume() {
        guard !appliedResume, duration > 0, let r = resumeSeconds else { return }
        appliedResume = true
        guard r > 5, r < duration - 10 else { return }   // ignore trivial / near-end positions
        coordinator.player?.seek(to: r)
        currentTime = r
        lastSaved = r
    }

    /// Persist the current position to the account library (no-op without a library context).
    private func saveProgress(at position: Double) {
        guard let m = curMeta, duration > 0, position >= 0 else { return }
        let dur = duration
        Task { await account.saveProgress(for: m, positionSeconds: position, durationSeconds: dur) }
    }

    private func toggle() {
        if loadFailed { retryLoad(); return }   // Play/Pause retries a failed source
        coordinator.player?.togglePause()
        showControls()
    }

    private func seek(_ delta: Double) {
        coordinator.player?.seek(by: delta)
        flashControls()
    }

    /// Reveal the bar from a hidden state, selecting Play, and restart the auto-hide timer.
    private func showControls() {
        withAnimation { showInfo = true }
        if controlsHidden || selected == .close { selected = .play }
        scheduleHide()
    }
    /// Keep the bar visible and reset the auto-hide timer, without changing the selection.
    private func flashControls() {
        withAnimation { showInfo = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !showOptions else { return }
            withAnimation { showInfo = false }
        }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - UIKit remote catcher

/// A focusable UIView that captures every Siri-remote press and forwards it to SwiftUI. This is far more
/// reliable than SwiftUI `@FocusState` + `onMoveCommand` inside a full-screen cover on tvOS.
private struct RemoteCatcher: UIViewRepresentable {
    var onPress: (UIPress.PressType) -> Void

    func makeUIView(context: Context) -> CatchView {
        let v = CatchView(); v.onPress = onPress; return v
    }
    func updateUIView(_ uiView: CatchView, context: Context) { uiView.onPress = onPress }

    final class CatchView: UIView {
        var onPress: ((UIPress.PressType) -> Void)?
        override var canBecomeFocused: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { setNeedsFocusUpdate(); updateFocusIfNeeded() }
        }

        /// Trap focus: a directional press both fires our handler AND tells the focus engine to move
        /// focus (up to the tab bar behind the cover). If it tries to leave, pull it straight back, so
        /// the player keeps owning the remote and the controls stay reachable.
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if window != nil, context.nextFocusedItem !== self {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window != nil else { return }
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                switch press.type {
                case .select, .menu, .playPause, .upArrow, .downArrow, .leftArrow, .rightArrow:
                    onPress?(press.type); handled = true
                default: break
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
    }
}

```

### 2. app/Sources/Player/MPVMetalPlayerView.swift

```swift
import Foundation
import SwiftUI

struct MPVMetalPlayerView: UIViewControllerRepresentable {
    @ObservedObject var coordinator: Coordinator
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let mpv =  MPVMetalViewController()
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        let coord = context.coordinator
        mpv.onSingleTap = { [weak coord] in coord?.onTap?() }

        context.coordinator.player = mpv
        return mpv
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }

    static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator) {
        (uiViewController as? MPVMetalViewController)?.stop()
    }

    public func makeCoordinator() -> Coordinator {
        coordinator
    }
    
    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }
    
    func onPropertyChange(_ handler: @escaping (MPVMetalViewController, String, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }

    func onTap(_ handler: @escaping () -> Void) -> Self {
        coordinator.onTap = handler
        return self
    }
    
    @MainActor
    public final class Coordinator: MPVPlayerDelegate, ObservableObject {
        weak var player: MPVMetalViewController?
        
        var playUrl : URL?
        var onPropertyChange: ((MPVMetalViewController, String, Any?) -> Void)?
        var onTap: (() -> Void)?
        
        func play(_ url: URL) {
            player?.loadFile(url)
        }
        
        func propertyChange(mpv: OpaquePointer, propertyName: String, data: Any?) {
            guard let player else { return }
            
            self.onPropertyChange?(player, propertyName, data)
        }
    }
}


```

### 3. app/Sources/Player/MPVMetalViewController.swift

```swift
import Foundation
import UIKit
import Libmpv
import os

// warning: metal API validation has been disabled to ignore crash when playing HDR videos.
// Edit Scheme -> Run -> Diagnostics -> Metal API Validation -> Turn it off
// https://github.com/KhronosGroup/MoltenVK/issues/2226
final class MPVMetalViewController: UIViewController {
    var metalLayer = MetalLayer()
    var mpv: OpaquePointer!
    var playDelegate: MPVPlayerDelegate?
    lazy var queue = DispatchQueue(label: "mpv", qos: .userInitiated)
    
    var playUrl: URL?
    var onSingleTap: (() -> Void)?
    var hdrAvailable : Bool = false
    private let mpvLog = Logger(subsystem: "com.stremiox.app", category: "mpv")
    var hdrEnabled = false {
        didSet {
            // FIXME: target-colorspace-hint does not support being changed at runtime.
            // this option should be set as early as possible otherwise can cause issues
            // not recommended to use this way.
            if hdrEnabled {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
            } else {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "no"))
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        
        view.layer.addSublayer(metalLayer)

        // iOS only: a tap toggles the touch controls. On tvOS this UIKit recognizer would swallow
        // the Siri-remote Select press before SwiftUI's player controls see it, so don't add it,         // the tvOS player drives everything through SwiftUI focus + command modifiers.
        #if os(iOS)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        view.addGestureRecognizer(tap)
        #endif

        setupMpv()
        
        if let url = playUrl {
            loadFile(url)
        }
    }
    
    private var lastLaidOutSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let didResize = lastLaidOutSize != .zero && size != lastLaidOutSize

        // Always size the drawable to the current bounds, not only on resize. If the first layout
        // leaves a stale/auto drawable, the video renders against the wrong surface and the size
        // mode (fill/fit) looks different per clip. Pinning it every layout makes every video fill
        // identically. (MetalLayer ignores <=1px sizes, so this is safe during transitions.)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        metalLayer.drawableSize = CGSize(width: size.width * metalLayer.contentsScale,
                                         height: size.height * metalLayer.contentsScale)
        CATransaction.commit()

        lastLaidOutSize = size

        // libmpv sets the video output up for whatever size it STARTS at but doesn't refill the
        // surface after a live resize (the video ends up tiny in a corner after rotating). Rebuild
        // the video output (vid no → auto) at the new size.
        if didResize { reconfigureVideoOutput() }
    }

    private func reconfigureVideoOutput() {
        guard mpv != nil else { return }
        checkError(mpv_set_option_string(mpv, "vid", "no"))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            self.checkError(mpv_set_option_string(self.mpv, "vid", "auto"))
            self.applyVideoSize { self.setString($0, $1) }   // re-apply size after the rebuild
        }
    }

    @objc private func handleSingleTap() { onSingleTap?() }

    #if os(iOS)
    /// Force the player into landscape (or back to portrait), for users who keep
    /// device auto-rotation off. Uses the iOS 16+ scene geometry request. (tvOS has no
    /// rotation, it's always landscape, so this is iOS-only.)
    func setOrientation(landscape: Bool) {
        guard let scene = view.window?.windowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    #endif

    func setupMpv() {
        mpv = mpv_create()
        if mpv == nil {
            print("failed creating context\n")
            exit(1)
        }

        // Apply the "fast" profile first so it sets the baseline (cheaper scaling, no debanding/dither,
        // static HDR peak); the explicit options below override anything we care about. This is the
        // documented remedy for 4K frame drops on constrained GPUs, which is what stutters on device.
        checkError(mpv_set_option_string(mpv, "profile", "fast"))

        // https://mpv.io/manual/stable/#options
#if DEBUG
        checkError(mpv_request_log_messages(mpv, "v"))
#else
        checkError(mpv_request_log_messages(mpv, "no"))
#endif
#if os(macOS)
        checkError(mpv_set_option_string(mpv, "input-media-keys", "yes"))
#endif
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        // Bundle a broad CJK font and point libass at the folder so non-Latin subtitles (e.g. Korean)
        // render instead of empty boxes. CoreText fallback alone did not cover them in this build, so we
        // ship the font and set it as the default subtitle font directly.
        if let res = Bundle.main.resourcePath {
            checkError(mpv_set_option_string(mpv, "sub-fonts-dir", res + "/fonts"))
        }
        checkError(mpv_set_option_string(mpv, "sub-font", "Noto Sans CJK KR"))
        checkError(mpv_set_option_string(mpv, "embeddedfonts", "yes"))
        // User-configured subtitle appearance (size / colour / background), see SubtitleStyle.
        for (name, value) in SubtitleStyle.mpvOptions {
            checkError(mpv_set_option_string(mpv, name, value))
        }
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        // Hardware-decode via VideoToolbox on both device and the (Apple-Silicon) simulator.
        // This keeps decoded frames as GPU textures, which matters for more than speed: software
        // decode puts frames in CPU memory, forcing libplacebo to upload them via a PBO, and
        // that path (vkAllocateMemory → MTLSimDevice) crashes the simulator's Metal driver on
        // large 4K frames. GPU-resident frames skip the upload entirely. A launch arg overrides
        // for diagnostics: -stremiox-hwdec <videotoolbox|no|auto-safe>.
        let hwdec: String = {
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-stremiox-hwdec"), i + 1 < a.count { return a[i + 1] }
            return "videotoolbox"
        }()
        checkError(mpv_set_option_string(mpv, "hwdec", hwdec))
        mpvLog.log("hwdec = \(hwdec, privacy: .public)")
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        // Apply the saved video-size mode up front so the first frame is sized correctly + uniformly.
        applyVideoSize { self.checkError(mpv_set_option_string(self.mpv, $0, $1)) }

        // Debrid/addon stream URLs (e.g. debridio) are web-ready links meant for a browser
        // <video>; their resolvers often 500/504 on ffmpeg's default "Lavf/*" User-Agent. The
        // web player fetched them with the browser UA, so present a Safari-like UA here. Also
        // follow HTTP redirects to the final CDN file (debrid resolvers 30x to it).
        checkError(mpv_set_option_string(mpv, "user-agent",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"))
        checkError(mpv_set_option_string(mpv, "network-timeout", "30"))
        // Reconnect on dropped/stalled HTTP (debrid CDNs sometimes reset mid-stream); without this
        // a hiccup looks like an infinite buffer. Followed by hard failure → MPV_EVENT_END_FILE.
        checkError(mpv_set_option_string(mpv, "stream-lavf-o",
            "reconnect=1,reconnect_streamed=1,reconnect_delay_max=7"))

        // Aggressive read-ahead cache: buffer far past the play head so transient network dips on big
        // 4K streams don't stall playback (the main cause of on-device stutter). The forward cache is
        // capped by RAM, so it's larger on the Apple TV (4GB) than on iPhone. Some back-buffer keeps
        // short rewinds instant.
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "demuxer-readahead-secs", "300"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "64MiB"))
#if os(tvOS)
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "512MiB"))
#else
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "256MiB"))
#endif

//        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes")) // HDR passthrough
//        checkError(mpv_set_option_string(mpv, "tone-mapping-visualize", "yes"))  // only for debugging purposes
//        checkError(mpv_set_option_string(mpv, "profile", "fast"))   // can fix frame drop in poor device when play 4k

        
        checkError(mpv_initialize(mpv))
        
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.trackList, MPV_FORMAT_NONE)
        mpv_set_wakeup_callback(self.mpv, { (ctx) in
            let client = unsafeBitCast(ctx, to: MPVMetalViewController.self)
            client.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        setupNotification()
    }
    
    public func setupNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc public func enterBackground() {
        // fix black screen issue when app enter foreground again
        pause()
        checkError(mpv_set_option_string(mpv, "vid", "no"))
    }
    
    @objc public func enterForeground() {
        checkError(mpv_set_option_string(mpv, "vid", "auto"))
        applyVideoSize { self.setString($0, $1) }   // re-apply size after the rebuild
        play()
    }

    /// Tear mpv down safely when the player closes. Clearing the wakeup callback first
    /// prevents it from firing into a deallocated controller (the crash on close), and
    /// destruction is serialized onto the event queue so it can't race `readEvents`.
    func stop() {
        NotificationCenter.default.removeObserver(self)
        guard let handle = mpv else { return }
        mpv_set_wakeup_callback(handle, nil, nil)
        queue.async { [weak self] in
            self?.mpv = nil
            mpv_terminate_destroy(handle)
        }
    }

    deinit {
        // Safety net: if the view controller is torn down without stop() (e.g. an
        // unexpected dealloc), make sure mpv can't call back into freed memory.
        if let handle = mpv {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv = nil
            mpv_terminate_destroy(handle)
        }
    }

    func loadFile(
        _ url: URL
    ) {
        var args = [url.absoluteString]
        var options = [String]()
        
        args.append("replace")

        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }

        mpvLog.log("loadFile → \(url.absoluteString, privacy: .public)")
        command("loadfile", args: args)
    }
    
    func togglePause() {
        getFlag(MPVProperty.pause) ? play() : pause()
    }
    
    func play() {
        setFlag(MPVProperty.pause, false)
    }
    
    func pause() {
        setFlag(MPVProperty.pause, true)
    }

    func seek(to seconds: Double) {
        command("seek", args: [String(seconds), "absolute"])
    }

    /// Relative seek (e.g. -10 / +10), used by the tvOS remote's left/right.
    func seek(by seconds: Double) {
        command("seek", args: [String(format: "%.1f", seconds), "relative"])
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }
    
    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }
    
    private func getFlag(_ name: String) -> Bool {
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }
    
    private func setFlag(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    private func setString(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        mpv_set_property_string(mpv, name, value)
    }

    /// Read the current audio/subtitle/video tracks from mpv's `track-list`.
    func tracks(ofType type: String) -> [MPVTrack] {
        guard mpv != nil else { return [] }
        let count = getInt("track-list/count")
        guard count > 0 else { return [] }
        var result: [MPVTrack] = []
        for i in 0..<count where (getString("track-list/\(i)/type") ?? "") == type {
            result.append(MPVTrack(
                id: getInt("track-list/\(i)/id"),
                type: type,
                title: getString("track-list/\(i)/title") ?? "",
                lang: getString("track-list/\(i)/lang") ?? "",
                selected: getFlag("track-list/\(i)/selected")
            ))
        }
        return result
    }

    func setAudioTrack(_ id: Int) { setString(MPVProperty.aid, id < 0 ? "no" : String(id)) }
    func setSubtitleTrack(_ id: Int) { setString(MPVProperty.sid, id < 0 ? "no" : String(id)) }

    /// Current media summary for the player's metadata line: encoded video height (e.g. 2160) and the
    /// active audio codec (e.g. "eac3"). Both can be 0/"" early in load, before the first frame.
    func mediaSummary() -> (height: Int, audioCodec: String) {
        guard mpv != nil else { return (0, "") }
        return (getInt("video-params/h"), getString("audio-codec-name") ?? "")
    }

    /// Persisted video-size mode, read at startup so the first frame already uses it.
    private(set) var videoSizeMode = UserDefaults.standard.string(forKey: "stremiox.videoSize") ?? "original"

    /// Video sizing. "original" (default) = the whole frame at its correct aspect, with bars where
    /// the film is wider/narrower than the screen, exactly like actual Stremio. "zoom" crops to fill
    /// the screen; "stretch" distorts to fill. The render now looks identical across clips because
    /// the drawable is pinned to the screen size every layout (the real "4 videos 4 sizes" fix).
    func setVideoSize(_ mode: String) {
        videoSizeMode = mode
        UserDefaults.standard.set(mode, forKey: "stremiox.videoSize")
        applyVideoSize { self.setString($0, $1) }
    }

    /// Apply `videoSizeMode` via `set`, `mpv_set_option_string` before init, `setString` (property)
    /// after, so the mode is realised identically at startup and on every video-output rebuild.
    private func applyVideoSize(_ set: (String, String) -> Void) {
        switch videoSizeMode {
        case "zoom", "fill": set("keepaspect", "yes"); set("panscan", "1.0")   // crop to fill
        case "stretch":      set("keepaspect", "no");  set("panscan", "0.0")   // distort to fill
        default:             set("keepaspect", "yes"); set("panscan", "0.0")   // original: whole frame, keep aspect
        }
    }

    func setSpeed(_ speed: Double) { setString(MPVProperty.speed, String(format: "%.2f", speed)) }

    /// Re-apply the current subtitle appearance to a running player (used after a settings change).
    func applySubtitleStyle() {
        for (name, value) in SubtitleStyle.mpvOptions { setString(name, value) }
    }

    func command(
        _ command: String,
        args: [String?] = [],
        checkForErrors: Bool = true,
        returnValueCallback: ((Int32) -> Void)? = nil
    ) {
        guard mpv != nil else {
            return
        }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        //print("\(command) -- \(args)")
        let returnValue = mpv_command(mpv, &cargs)
        if checkForErrors {
            checkError(returnValue)
        }
        if let cb = returnValueCallback {
            cb(returnValue)
        }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        if !args.isEmpty, args.last == nil {
            fatalError("Command do not need a nil suffix")
        }
        
        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)
        
        return strArgs
    }
    
    /// Deliver a property change on the main thread, dropping it if the player has been torn
    /// down (mpv == nil). Without the guard, a queued block force-unwraps the nil IUO mpv and
    /// traps, the crash on close.
    private func emit(_ name: String, _ data: Any?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: data)
        }
    }

    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            
            while self.mpv != nil {
                let event = mpv_wait_event(self.mpv, 0)
                if event?.pointee.event_id == MPV_EVENT_NONE {
                    break
                }
                
                switch event!.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    let dataOpaquePtr = OpaquePointer(event!.pointee.data)
                    if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
                        let propertyName = String(cString: property.name)
                        switch propertyName {
                        case MPVProperty.videoParamsSigPeak:
                            if let sigPeak = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { [weak self] in
                                    guard let self, let mpv = self.mpv else { return }   // dropped if torn down
                                    let maxEDRRange = self.view.window?.screen.potentialEDRHeadroom ?? 1.0
                                    // display screen support HDR and current playing HDR video
                                    self.hdrAvailable = maxEDRRange > 1.0 && sigPeak > 1.0
                                    self.playDelegate?.propertyChange(mpv: mpv, propertyName: propertyName, data: sigPeak)
                                }
                            }
                        case MPVProperty.pausedForCache:
                            let buffering = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? true
                            self.emit(propertyName, buffering)
                        case MPVProperty.timePos, MPVProperty.duration:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                self.emit(propertyName, value)
                            }
                        case MPVProperty.pause:
                            let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? false
                            self.emit(propertyName, paused)
                        case MPVProperty.trackList:
                            self.emit(propertyName, nil)
                        default: break
                        }
                    }
                case MPV_EVENT_END_FILE:
                    // A file finished, if it ENDED IN ERROR (couldn't open: dead/uncached link,
                    // refused, unsupported, timed out), surface it so the UI can stop "buffering
                    // forever" and let the user pick another source.
                    if let data = event!.pointee.data {
                        let ef = UnsafePointer<mpv_event_end_file>(OpaquePointer(data)).pointee
                        if ef.reason == MPV_END_FILE_REASON_ERROR {
                            let msg = String(cString: mpv_error_string(ef.error))
                            self.mpvLog.error("end-file error: \(msg, privacy: .public)")
                            self.emit(MPVProperty.endFileError, msg)
                        } else if ef.reason == MPV_END_FILE_REASON_EOF {
                            self.emit(MPVProperty.endFileEof, nil)   // natural end → auto-play-next
                        }
                    }
                case MPV_EVENT_SHUTDOWN:
                    print("event: shutdown\n");
                    mpv_terminate_destroy(mpv);
                    mpv = nil;
                    break;
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event!.pointee.data)) {
                        let prefix = String(cString: msg.pointee.prefix)
                        let level = String(cString: msg.pointee.level)
                        let text = String(cString: msg.pointee.text).trimmingCharacters(in: .newlines)
                        if !text.isEmpty { self.mpvLog.log("[\(prefix, privacy: .public)/\(level, privacy: .public)] \(text, privacy: .public)") }
                    }
                default:
                    let eventName = mpv_event_name(event!.pointee.event_id )
                    print("event: \(String(cString: (eventName)!))");
                }
                
            }
        }
    }
    
    
    private func checkError(_ status: CInt) {
        if status < 0 {
            print("MPV API error: \(String(cString: mpv_error_string(status)))\n")
        }
    }
    
}

```
