# Presence behavior and troubleshooting

The current build uses your configured Discord application, with the public ID
read from `.env`/build variables and baked into the bundle. The example value is
`1572242579049808028`. Upstream ID `1370062110272520313` is no longer used as a
fallback. Each account authorizes independently; see [account setup](ACCOUNTS.md).
No client secret belongs in the app.

## Longer sessions

The original 30-minute cutoff was imposed by iRPC's loop, not a fixed OS limit.
The app now offers 30 minutes, 2 hours (default), and 4 hours, remembered locally.
It submits one finite job with the corresponding number of configured polling
intervals (5, 15, or 30 seconds); requests can add to the actual duration. The system may expire it early.

Apple's [continued-processing guide](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
requires a foreground user action and progress reporting. Background session
chaining and silent audio are not used to manufacture continuous execution. A
longer selected session does not establish that iOS will allow the whole session.

## Countdown and artwork

Discord's [SDK timestamp reference](https://discord.com/developers/docs/social-sdk/classdiscordpp_1_1ActivityTimestamps.html)
specifies milliseconds and describes an end timestamp as a client-rendered
countdown. The app keeps that predicted deadline steady for repeated identical
player samples, for up to 30 seconds of prediction. New samples and seeks correct
the estimate; clearing presence resets the prediction. Invalid/unknown durations
do not produce a fabricated end timestamp.

The app's Music screen now reads `currentEntry.artwork` and the underlying
`Song.artwork`/`MusicVideo.artwork`, then renders the Artwork object with native
[ArtworkImage](https://developer.apple.com/documentation/musickit/artworkimage).
The upstream playback helper only extracts queue-entry artwork, leaving a gap when
the Song carries artwork separately. Apple also recommends ArtworkImage over a
custom AsyncImage path in [this framework discussion](https://developer.apple.com/forums/thread/685311).
This source inspection does not prove which condition occurred on the user's phone.

While the affected song is playing, use **Settings → Diagnostics → Check playback & artwork**. The report distinguishes missing objects, missing generated URLs,
non-HTTP native resources, HTTP failures, and image-decoding failures. Query strings
are removed from displayed/copied URLs. A successful diagnostic HTTP request still
does not prove native rendering or Discord-side downloading succeeded.

Discord uses a public HTTPS URL separately. The reported `musicKit://artwork/library/…`
URL is a device-local MusicKit resource, not an image Discord can download. The
former SDK fallback incorrectly treated a playback/library ID as a catalog ID.
The reported catalog call then failed with `MusicKit.MusicTokenRequestError 5`.
Local Music authorization does not establish that the app can generate an Apple
Music API developer token. Automatic generation requires the MusicKit App Service
for the app's actual signed bundle identifier; see
[Apple's configuration guide](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api).
Changing the signing bundle/team can affect that path. No private key or token
should be embedded in the client to work around it.

Version 1.2 uses Apple's token-free public store metadata first:

1. Accept an existing public HTTPS MusicKit artwork URL.
2. Look up a verified `MPMediaItem.playbackStoreID` using the public lookup API.
   Library IDs are never treated as store IDs.
3. If no store ID/result is available, search and require matching title, artist,
   album (when supplied), and duration within two seconds. Different artwork among
   otherwise matched results is treated as ambiguous. Live versions and covers
   must not silently replace the reported song.
4. A configured native MusicKit catalog can still provide artwork absent from the
   public store. A developer-token failure is remembered for the process rather
   than being retried on every track.

This does not upload device artwork or use another developer's credentials. The
public lookup uses an ephemeral session without cookie/credential storage. It
uses the US store, spaces requests by 3.1 seconds, and backs off after HTTP 429.
Public artwork resolution is shared across all Discord accounts and cached for
the current complete track metadata. Missing results retry after a minute.

The local artwork URI in the reports is identical across different songs, so the
cache also includes title/artist/album. The SDK wrapper no longer reuses an image
by library ID when the caller supplied no public artwork. Stale lookup completion
is checked against the complete sampled track before publication.

A live check for **It's Going Down Now** found public store track `1733408557`,
matching the provided artists, the Persona 3 Reload soundtrack album, and a
186.093-second duration. Both exact-ID and verified-search requests returned the
same artwork, whose URL returned HTTP 200 with `image/jpeg`. Run
`bash scripts/check-public-artwork.sh --live` to repeat the check. Offline matching
checks use the captured factual fields in `tests/fixtures/public-artwork-persona.json`.
See Apple's [lookup](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html)
and [result-field documentation](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html).

Diagnostics include album/duration, music item/store IDs, actual bundle ID,
resolution source, public URL, and an HTTP/image-decoding probe. Query strings are
redacted from copied URLs. Public lookup/image checks are verified locally;
on-device resolution and Discord-side image rendering still require verification.
A library-only upload or content absent from the public store may lack public
artwork. The application's default icon can be set in the Discord Developer Portal.

See [Discord's asset guide](https://discord.com/developers/discord-social-sdk/development-guides/setting-rich-presence)
for asset keys and externally hosted image URLs. The activity name's C-string
length is also corrected to the full UTF-8 length of `Apple Music`.

## Intermittent startup: not yet reproduced on device

Reported behavior: presence sometimes did not start, then worked after opening
iRPC, stopping the prior session, and starting another. After recovery it kept
working with the screen off. This observation does not identify whether the cause
was scheduler startup, Music state, Discord connection, or activity publication.

The app now distinguishes preparing an update, awaiting acknowledgement, accepted,
and rejected; it shows the last acceptance time. A connected/authenticated account
alone does not establish that a presence update was accepted. If startup fails
again, record those status lines, the session state, whether Music is playing, and
whether Discord shows another activity. Do not share tokens or authorization codes.

Stale catalog lookups and callbacks are invalidated by a presence generation number
so they cannot submit an older update after a clear or a newer update. Each account
has its own presence generation. Stop clears all account presences, while
disconnect clears only that account. These are correctness improvements; they are not proof of the reported startup cause.

## Verification

`bash scripts/check-presence.sh` exercises the same timeline/artwork policy used by
the SDK wrapper: stable deadlines on repeated samples, correction, seeking, bounded
prediction, reset, invalid durations, and supplied-artwork priority. The unchanged
deadline assertion failed with the former timestamp calculation and passes with
the new policy. `bash scripts/check-token-storage.sh` covers credential serialization
and expiry. The unsigned IPA is compiled and inspected locally using the WSL build
script. Full session runtime, Discord-side image fetching, startup reliability, and
visual countdown behavior still require an iPhone/Discord test.

## Optional background refresh

Settings can request [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest)
opportunities after sharing starts. iOS decides when or whether to launch them;
the requested 15-minute earliest time is not a periodic timer. Each wake restores
saved credentials, waits a bounded time for connection, samples Music once, and
attempts publication. It does not open interactive authentication. Stop sharing
cancels pending work. OS expiration cancels the current refresh operation.

Auto-start on opening is separate: it attempts once per foreground visit after
permissions/accounts are ready. A manual stop suppresses another attempt during
that visit. Neither feature silently renews a continued-processing job.

## Playback controls

The main play button resumes the existing SystemMusicPlayer queue if paused and
starts sharing. If Music is already playing, it starts sharing without restarting
the song. While both playback and sharing are active, pause pauses Music and stops
sharing. Automatic sharing on launch and background refresh never start playback.
No replacement queue is created from recently played history; an empty queue needs
a song chosen in Apple Music.

Next skips to the next queue entry. Previous restarts the current entry after three
seconds, otherwise skips to the previous entry. Track changes invalidate in-flight
public-artwork publication so an earlier song cannot be posted after a skip.
Device tests should cover queue ends, an empty queue, external pause/resume, and
rapid play/pause/skip interactions. Motion options are native and configurable in Settings. The play/pause symbols
rotate and scale between states; control presses use spring feedback and optional
haptics. Reduce Motion and the animation switch disable those effects.

## Live Activity

The embedded `AfterglowStatus.appex` uses WidgetKit/ActivityKit to display sharing
status and current track metadata on the Lock Screen and Dynamic Island. Enable
it in Settings. It uses local ActivityKit updates, with no App Group, extra token
storage, remote push service, or credential access in the extension. Metadata is
bounded to fit the ActivityKit content-size limit.

The app starts it in the foreground, coalesces metadata/status updates, refreshes
its stale date periodically while executing, and ends it when sharing stops or
the option is disabled. A dismissed activity is not recreated during the same
session. After 90 seconds without updates, the extension shows a stale state;
continued presence is not inferred from an old snapshot.

A Live Activity does **not** provide more execution time. It can help a user see
that reopening the app is needed. Apple documents the update and sandbox rules in
[Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
Signing/install tools must sign the embedded `.appex` as well as the app.

True beat/amplitude analysis is not implemented. The Follow playback preference
uses the actual Music playback state, without microphone recording or synthetic
beat claims. Apple excludes FairPlay-protected audio from audio processing taps;
see [What's new in HLS](https://developer.apple.com/streaming/Whats-new-HLS.pdf).

## 1.3: playback presentation and rendering

Reported sequence: foregrounding while Music plays initializes the button/vapor
correctly; pausing/resuming from Afterglow then controls playback/sharing while the
button and vapor remain paused until relaunch. This has not been reproduced on a
physical device from the Windows workspace. The source had no direct playback
notification subscription, suppressed the foreground tick during a continued job,
and reread MusicKit state immediately after issuing commands.

The UI, sharing gate, and vapor now share a presentation state driven by native
`MPMusicPlayerController` playback notifications (generation explicitly enabled),
foreground readback, and successful commands. MusicKit's cached status is retained
only in diagnostics. Successful commands are reflected immediately; up to 1.5
seconds of delayed, contradictory readback is tolerated, after which actual system
state takes precedence. The foreground tick runs during continued-processing jobs
without starting a second presence-publishing loop. Empty-queue metadata sampling
no longer waits on MusicKit catalog history.

`check-playback-state.sh` exercises 100 pause/resume cycles with delayed snapshots,
external pauses, permission reset, and bounded recovery. These are policy tests;
they do not certify Apple's notification delivery on a phone. Repeat the reported
pause/resume sequence and compare the three playback-state lines in Diagnostics
if it persists.

The former renderer requested 8 FPS in Low Power Mode and 24 FPS otherwise. Version
1.3 requests a native 30/60 FPS selection, with a 30 FPS Low Power maximum, using
CADisplayLink's frame-rate range. The fluid solver eliminates per-cell repeated
trigonometry, precomputes the static vortex field, and owns bounded reusable numeric
buffers. Its pointer-based storage was run through the existing one-minute flow
checks for all styles under Address Sanitizer. A local Release benchmark improved
median solver/image-data frame time from 2.37/2.66/2.51 ms (Vapor/Vortex/Wisps) to
0.44/0.40/0.49 ms. This excludes UIKit image submission and isn't phone FPS.

`bash scripts/check-vapor.sh --benchmark` repeats the portable benchmark. Diagnostics
report the last active layer-update rate, end-to-end worker/render latency, target,
and Low Power state; paused/background time is excluded. Rendering still stops
when hidden, backgrounded, disabled, or suppressed by Reduce Motion.

## 1.4: cold launch and permission loading

The first-launch icon was also gated by `sharing && playing`, so an already-playing
song with sharing off displayed Play. The icon/action now follows actual Music
playback. A Start sharing action remains available when playback is active and
sharing is off, avoiding any need to pause/resume the song just to enable presence.

Startup reads MusicKit and media-library permission providers, starts native
playback notifications, and seeds the initial playing state from MusicKit while
MediaPlayer has not provided a definitive state. It never calls prepare/play/pause
to discover the current state. After hydration, actual state-change notifications
and successful commands supersede the initial snapshot, including the bounded
command reconciliation introduced in 1.3.

A loader covers permission and metadata checks and the saved SDK-account handshake.
The centre button shows a spinner; Music controls and connection prompts are gated.
Saved-account waiting is bounded to three seconds for unavailable networks. Account
records that exist are routed to Accounts rather than described as absent. The
same loading path covers foreground re-entry, with no new authorization prompt.
MusicKit metadata reads wait for MusicKit authorization even if the media-library
permission provider has already hydrated, so that transient mismatch isn't shown
as a permission failure.

The portable playback-state check covers a cold bridge paired with a playing
MusicKit snapshot, authoritative pause notifications, and the existing command
race cases. Real cold-launch notification timing remains a device check.

## 1.6: track transitions and countdown expiry

The old worker slept for the selected 5/15/30-second resend interval. Native item
notifications only refreshed the play-state flag, and `poll` awaited artwork
resolution before sending any metadata. These independent delays could leave the
previous track visible until another sample or the next track.

The active worker now samples every two seconds; `PresenceUpdatePolicy` bypasses
the resend interval for changed track/queue entry, artwork, account set, and
play/pause. Native notifications request an immediate check. Artwork runs in a
separate cancellable task, with identity checks before caching or republishing.
The selected interval remains the heartbeat for unchanged presence.

`PresenceTimeline` retains the deadline of identical samples, including after
expiry. Known-duration activities send only an end timestamp. Each SDK manager
owns a cancellable expiry task which clears that activity at the deadline; newer
updates, stop, sign-out, and removal invalidate it. Expiry preserves the timeline
so the next stale sample cannot revive the song. A seek/repeat or advancing
player sample can establish a corrected deadline. Unknown duration sends no timer.
This requires active process execution and network delivery; it cannot guarantee
Discord-side timing after iOS suspends the app or during connectivity loss.

Regression checks: `bash scripts/check-presence.sh` covers stale/expired samples,
seek/repeat, no elapsed-counter timestamps, immediate track changes and pause,
artwork enrichment, notification overrides, and unchanged-update throttling.

## 1.7: bounded waiting presence and Listening activity

1.6 cleared immediately at a song deadline or missing/paused sample. 1.7 instead
publishes "Waiting for next track", retaining the previous cover and putting the
previous track/artist in the state field. This activity has no timestamps. Its
single deadline defaults to 30 seconds and is configurable as 15/30/60 seconds.
Repeated stale samples cannot restart it, even after it clears. New valid
playback resets the transition; explicit stop/sign-out still clears immediately.
The same generation-guarded SDK expiry task transitions from song → waiting →
cleared. New track/artwork updates invalidate older scheduled actions.

The activity type now requests `Discord_ActivityTypes_Listening`. The bundled
SDK exposes the enum, but its version accessors in the arm64 binary return
0.0.0, so the presence of the enum does not establish runtime support. Discord's
release notes added Listening support in SDK 1.5 (2025-08-13). Actual icon/layout
and server acceptance require a live test; if Playing remains, upgrading the
inherited SDK is the next step. This change does not replace the SDK binaries.
External assets support animated GIF/WebP/AVIF according to Discord's guide;
a small hosted equalizer could accompany the cover. No animated asset is
configured or hosted by this change. Uploaded portal assets do not provide the
same animation support. Rich Presence does not provide custom card layout or
arbitrary UI animation.

Source: https://github.com/discord/discord-api-docs/blob/main/developers/discord-social-sdk/development-guides/setting-rich-presence.mdx
Regression: `bash scripts/check-presence.sh` also checks fixed transition
deadlines, stale polls after timeout, reset, and configurable later transitions.

SDK activity-type release notes: https://discord.com/developers/docs/social-sdk/release_notes.html
