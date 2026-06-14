# StremioX 0.3.0: look back, loose ends, and the plan

Written 2026-06-14 after a long stretch of rapid path changes. Goal: stop adding new things,
close the loose ends, ship a clean 0.3.0. No new features until Phase 2 is largely done.

## What actually shipped (committed on main, builds 88 to 96, NONE pushed/released)
- beta8: QR sign-in freeze, iPhone layout clipping (Home/Discover/Library), embedded server startup config.
- beta9: viewport clipping on the rest of the screens, adaptive accent ink, two crash guards, sign-in guard.
- beta10: mark-watched so Continue Watching clears, macOS window-close quits, Mac return-to-submit, cooler danger red, poster VoiceOver labels.
- beta11/12: device-aware server cache, server footprint tied to the Performance setting.
- build 96: 11471 web-proxy gated to the web-host only, the REAL server crash fix (EADDRINUSE error handler), CW hero metadata pre-enrich.

## Loose ends (the honest list)

### 1. Server changes need course-correction (user is right: it is our code, not the server)
- The REAL crash cause is an unhandled `error` event on our 11471 proxy `listen()` (EADDRINUSE on relaunch). The fix is the `proxySrv.on('error')` handler (build 96). KEEP.
- The 11471 gate (proxy off native iOS/tvOS) is fine: 11471 is OUR WKWebView shim, Stremio has no such proxy, native does not need it. KEEP.
- RECONSIDER / likely REVERT, because they chased the wrong "memory" hypothesis and disable things Stremio runs fine:
  - `NO_HTTPS_SERVER` (disables :12470, the HTTPS server Stremio uses).
  - `HLS_V2_DISABLED` (disables server-side HLS transcoding).
  - device-aware torrent cache cap (256/512MB) tied to PerformanceMode.
  Note: the official Stremio mobile build does set the first two via IOS_APP, so they are defensible, but they were NOT the crash fix and should not be presented as such. Decision needed: lean mobile config vs full config.

### 2. Multiple StremioX installs (3 to 5 copies registering)
- Dev builds wrote a StremioXMac.app into several derivedData dirs (build/out, build/out-mac, build/out-StremioXMac, ...), each got registered with LaunchServices. Removed the build dirs already. Permanent fix: one canonical build path, and an lsregister cleanup of stale registrations, and do not leave built .apps lying around.

### 3. Verification debt (the missing layer all along)
- Build-verified but NOT runtime-verified on real hardware: the server crash fix (needs your iPhone + Apple TV), S4 mark-watched (needs a real ~90%/EOF playthrough), CW hero metadata (sim died mid-check), the iPhone detail-view scaling a redditor reported.

### 4. The dead web-host target
- The `StremioX` (WKWebView) target no longer builds (PlayerScreen now needs SourcesShared types it lacks). It is abandoned for the native apps. Decide: delete it from project.yml, or fix it. Leaving it broken is a CI trap when releasing.

### 5. The full audit backlog
- docs/REVIEW-WORKLIST.md holds the 97-issue audit + 9 macOS issues. Most are LOW/medium polish. The big structural ones are S2 macOS player presentation, S3 in-player next/prev episode, S8 iPad/Mac wide-screen layout, S9 CoreBridge actor-isolation, and the rest of the accessibility pass.

### 6. Version numbering is messy
- Bumped 88 to 96 across many betas. Settle on a clean scheme for the 0.3.0 line.

### 7. PR #55 (trickplay)
- Draft, rough by the author's own note, with open questions (format, addon, hosting). Replied with the hosting design. Do NOT merge a draft until the author marks it ready and the questions are settled.

## The plan

### Phase 0: stabilize and correct course (do FIRST, then release a beta)
1. Server: keep the error handler + the 11471 gate; revert NO_HTTPS_SERVER / HLS_V2_DISABLED / the cache cap so the server runs as Stremio runs it (decision: confirm lean-vs-full with the user). One build, all three platforms green.
2. Multi-install: single canonical build path + lsregister cleanup; document it.
3. Settle the version; cut the next beta with the critical fixes (server crash, sign-in freeze, layout, accent, CW clearing + metadata).
4. You publish the GitHub release (public action stays with you). I prepare the changelog + tag.

### Phase 1: close verification debt (no new code)
- Runtime-verify on real devices: iPhone (server, sign-in, CW), Apple TV (server), iPad (layout), Mac (player). This is what has been missing and what keeps biting us.

### Phase 2: structural worklist, one focused + tested build each
- S2 macOS player, then S3 episode nav, then S8 iPad layout, then S9 actor-isolation, then the a11y pass.

### Phase 3: the LOW-priority long tail of the 97 issues.

### Phase 4: 0.3.0 final + release.

## Working rules (so we stop thrashing)
- No new features until Phase 2 is largely done.
- Every fix: root-cause with evidence (read the log, not a guess), then build, then run on the real platform, THEN claim fixed.
- 16 GB Mac: one build dir, do not hoard build/out-* per scheme, shut sims after use, do not over-spawn agents.
- No em dashes anywhere, ever.
- Public repo actions (push, release, merge, issues) stay with the user.
