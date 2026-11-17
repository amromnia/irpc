# Presence behavior and troubleshooting

The build uses upstream Discord application ID `1370062110272520313` in
`ContentView.swift`. Forking the source does not create a Discord application or
give control over its portal settings. To use your own application, replace that
ID and configure its Social SDK/iOS OAuth settings, then sign out before connecting
to the new application. Do not carry credentials across client IDs. No application
secret belongs in this iOS app.

## Longer sessions

The original 30-minute cutoff was imposed by iRPC's loop, not a fixed OS limit.
The app now offers 30 minutes, 2 hours (default), and 4 hours, remembered locally.
It submits one finite job with the corresponding number of 15-second polling
intervals; requests can add to the actual duration. The system may expire it early.

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

Previously the SDK wrapper ignored `artworkURL` from the current MusicKit entry
and always fetched the song/album again. It now prefers that HTTPS URL, then a
cached URL, then catalog artwork if needed. This avoids unnecessary catalog
requests for library-only songs that already have artwork. There is no guarantee
an external URL is reachable from Discord. A question-mark placeholder can remain
when no fetchable artwork exists and the application's fallback icon is missing.
Changing the application icon requires access to that application's portal;
external album URLs do not.

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
so they cannot submit an older update after a clear or a newer update. The polling
caller also no longer clears presence again after a canceled SDK call: Stop already
clears it, and that extra clear could affect a subsequently started session. These
are correctness improvements; they are not proof of the reported startup cause.

## Verification

`bash scripts/check-presence.sh` exercises the same timeline/artwork policy used by
the SDK wrapper: stable deadlines on repeated samples, correction, seeking, bounded
prediction, reset, invalid durations, and supplied-artwork priority. The unchanged
deadline assertion failed with the former timestamp calculation and passes with
the new policy. `bash scripts/check-token-storage.sh` covers credential serialization
and expiry. The unsigned IPA is compiled and inspected locally using the WSL build
script. Full session runtime, Discord-side image fetching, startup reliability, and
visual countdown behavior still require an iPhone/Discord test.
