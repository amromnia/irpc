# iRPC — Apple Music presence for Discord

A SwiftUI iPhone/iPad app that shares Apple Music playback through DiscordSocialKit.
Requires iOS 17.6 or later. Background sharing requires iOS 26 or later.

## Build an unsigned IPA on GitHub

1. Push these files to your fork and enable GitHub Actions if prompted.
2. Open **Actions → Build unsigned iOS IPA → Run workflow**, or push a branch.
3. Download the **iRPC-unsigned** artifact from the completed run and unzip it.
4. Sign `iRPC-unsigned.ipa` with your installation tool before installing it.

No signing certificate, provisioning profile, Apple account, or repository secret is
needed by CI. The workflow uses a device Release build and packages the app under
`Payload/iRPC.app`; it does not run a signed archive export. The accompanying SHA-256
file lets you check the downloaded IPA. Artifacts expire after 14 days.

The workflow uses Xcode 26.3 on `macos-26` and the checked-in Swift package lockfile.
If GitHub retires that Xcode installation, update `DEVELOPER_DIR` to an available
Xcode 26+ installation. Dependency resolution intentionally fails rather than
silently selecting unreviewed versions.

For local builds, open `iRPC.xcodeproj`, select the shared **iRPC** scheme, and set
your signing team and bundle identifier. The inherited Discord application ID is
still in `ContentView.swift`; use an application you control and configure its iOS
OAuth settings before distributing your own version. Re-signing or changing the
bundle identifier may require corresponding OAuth configuration. Apple Music
catalog/history requests also need working MusicKit configuration for your signed
app; an unsigned build cannot establish that those services will work.

## Sharing

Authorize Music access, connect Discord, and tap **Start Sharing for 30 Minutes**.
On iOS 26+, a `BGContinuedProcessingTask` checks playback approximately every 15
seconds and submits Discord presence updates. Pausing playback clears presence.
The session ends after 120 checks plus their waiting intervals, or earlier on
Stop, loss of authorization/connection, a processing error, system expiration,
or cancellation through the system task UI. Actual duration includes request time.
Each new session requires another tap in the foreground.

This is an experiment with a finite listening session, not a promise of continuous
background execution. iOS controls execution and may stop the task early. Closing
the app from the app switcher terminates it without a cleanup callback, so Discord
presence may remain visible until it expires or the connection is cleared.
The system progress UI describes completed polling intervals, not acknowledged
Discord deliveries. The dependency exposes delivery failures through logging.

On iOS 17.6–25, **Start Sharing While Open** uses the existing foreground updater
and stops sharing when iRPC enters the background. Silent audio and notification
keep-alives have been removed. Discord tokens are stored locally with cloud sync
disabled; the dependency still uses SwiftData rather than Keychain.

## Verification

CI compiles the real device app, checks that the background task keys are present,
checks the app has no signing identity or provisioning profile, and validates the
IPA ZIP. Compilation and on-device behavior have not been run from the Windows
development workspace.

After signing and installing on a physical iPhone:

1. Deny Music access and confirm sharing cannot start; then grant access and connect Discord.
2. Start Music, tap Start, lock the phone, change tracks, and check the Discord
   activity from another device. Allow one polling interval plus network latency.
3. Pause and resume Music and confirm presence clears and returns.
4. Test Stop and system UI cancellation; confirm the button resets and presence clears.
5. Rapidly stop/restart a session and confirm only one session runs.
6. Test network loss and restoration, system expiration, force quit, and a full
   120-check session. Record actual background runtime and whether Music state
   remains fresh; the API does not guarantee a full 30 minutes.
7. On an older supported iOS version, confirm sharing stops after backgrounding.

See [the implementation/security review](docs/REVIEW.md) for findings, unresolved
trust questions, and the native-versus-Expo recommendation.

## License and credits

Apache License 2.0; see [LICENSE](LICENSE). Forked from
[itoolio/iRPC](https://github.com/itoolio/iRPC), with original credits to
[@thehairy](https://github.com/thehairy) and [@castdrian](https://github.com/castdrian).
