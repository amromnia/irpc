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

While the affected song is playing, use **Settings → Artwork diagnostics → Check
artwork**. The report distinguishes missing objects, missing generated URLs,
non-HTTP native resources, HTTP failures, and image-decoding failures. Query strings
are removed from displayed/copied URLs. A successful diagnostic HTTP request still
does not prove native rendering or Discord-side downloading succeeded.

Discord uses a URL asset separately. The SDK wrapper prefers the MusicKit URL,
then its cached/catalog artwork policy. Discord must fetch the image itself; an
in-app success does not establish Discord reachability. Uploading your application
icon in the Developer Portal configures the app's default icon, including the
question-mark case where no usable artwork is supplied.

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
