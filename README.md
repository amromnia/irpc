# Afterglow

A small native iPhone app for sharing your Apple Music soundtrack on multiple
Discord accounts. Built with SwiftUI, with Liquid Glass controls on iOS 26,
light/dark appearances, and a customizable accent color.

Afterglow is a fork of [itoolio/iRPC](https://github.com/itoolio/iRPC). Original
project credits and Apache 2.0 licensing are retained below. The internal Xcode
project/target names remain `iRPC` for build compatibility; the installed app and
its interface use the configured Afterglow name.

## Configure your own Discord application

Copy `.env.example` to `.env`, then set these **public** build values:

```dotenv
DISCORD_APPLICATION_ID=1572242579049808028
APP_DISPLAY_NAME=Afterglow
APP_BUNDLE_IDENTIFIER=com.amromnia.afterglow
```

The `.env` file and generated `Config/Local.xcconfig` are ignored by Git. An
Application ID is public and will be visible inside the compiled app; this is
configuration, not a way to hide a secret. Never put a client secret, bot token,
or user token here. Environment variables override `.env` values.

In the [Discord Developer Portal](https://discord.com/developers/applications),
open this application. Under **Social SDK → Getting Started**, complete and
**submit** the setup form to enable Social SDK. The SDK requests exactly
`openid sdk.social_layer_presence`; an `invalid_scope` error can indicate that
Social SDK has not been activated. URL-generator checkboxes do not configure the
SDK request. See [Discord setup](https://discord.com/developers/discord-social-sdk/getting-started)
and [scope documentation](https://discord.com/developers/discord-social-sdk/core-concepts/oauth2-scopes).
Enable **Public Client** under OAuth2, and add:

```text
discord-1572242579049808028:/authorize/callback
```

The build script registers the corresponding iOS URL scheme. A different Discord
application needs a matching redirect and fresh authorization. See
[account setup and testing](docs/ACCOUNTS.md).

## Build locally on Windows/WSL

From a native WSL filesystem checkout, with Swift 6.4.1, an extracted Xcode 27.1
iOS SDK, xtool 2.0.0-beta.1, Python 3, and ImageMagick:

```bash
cp .env.example .env
# Edit .env if desired.
bash scripts/build-wsl.sh
```

The unsigned output is `xtool/Afterglow.ipa`. It still needs signing before
installation. [BUILD-WSL.md](docs/BUILD-WSL.md) contains exact signing/install
commands and build limitations. No cloud compilation or Mac is used by this path.

For normal Xcode builds, run `python3 scripts/configure-app.py` after setting
`.env`, open `iRPC.xcodeproj`, select the `iRPC` scheme, and configure your team.
Xcode retains the native asset catalog and SwiftData storage path. The optional
GitHub Actions workflow reads the `DISCORD_APPLICATION_ID` repository variable;
it is not needed for local builds.

## Use

1. Allow Music access, then play something in Apple Music.
2. Open **Accounts**, tap **+**, and connect Discord. Repeat for each account,
   switching the active Discord/browser user before authorizing another user.
3. Enable the accounts that should receive updates. On **Music**, tap the round
   play button to resume Music and share; if Music is already playing, it keeps
   its position. Pause pauses Music, stops sharing, and cancels refresh requests.
   Previous/next control the existing Music queue.
4. Tap an account to view acknowledgements, reconnect, or remove it.
5. **Settings** contains session length, update interval, auto-start on opening,
   optional background refresh, appearance, and artwork diagnostics.

There is no fixed account-count cap. Each account has an independent SDK client
and credential store; practical capacity depends on the device and Discord.
Duplicate Discord users are rejected. Existing accounts from the two-slot build
are discovered once and retained. Removed account IDs are never reused.

Credential stores are isolated by bundle ID, application ID, and account ID.
WSL builds use Keychain; normal Xcode builds use separate SwiftData stores.
CloudKit synchronization is explicitly disabled in both paths. The local account
registry contains only numeric IDs. Rebranding/changing the OAuth application can
require fresh sign-in; upstream credentials are not imported.

The bottom tab bar uses native Liquid Glass on iOS 26. Earlier supported systems
use their standard tab bar. Minimum iOS is 17.6.

## Appearance and status (1.1)

Settings remembers **Off / Vapor / Vortex / Wisps** (default Wisps), color source
(Custom / Accent / Artwork), vapor color, speed, opacity, and Follow playback.
The default is subtle dark red with no added white highlights. Artwork color uses
MusicKit's average background color when available, or samples native library
artwork; neutral/unavailable colors retain the custom tint. Sampled colors are
darkened to keep the background subdued. Color sampling does not upload artwork.

Follow playback pauses the vapor with Music. It does not analyze beats or audio
amplitude. Apple Music does not expose the protected playback stream to this app.
Button rotations, spring presses, and haptics have independent switches. Reduce
Motion suppresses motion, off-screen/background views stop rendering, and Low
Power Mode limits the selected render cadence to 30 FPS. A native 30/60 FPS
picker controls the target, with 60 FPS as the default. The native fluid solver runs on a serial
worker, not the UI thread. Off removes the renderer entirely.

An optional **Live Activity → Show while sharing** displays the current song,
artist, countdown, and sharing status on the Lock Screen / Dynamic Island. Tap it
to reopen the app. It does not extend background execution. Status becomes stale
after 90 seconds without an update, and respects user dismissal for that session.
It is a Live Activity, not a Home Screen widget, and needs no App Group or push
server. About contains only the app version. This release is **1.5, build 6**.

## Background behavior and artwork

On iOS 26+, continued-processing sessions target 30 minutes, 2 hours, or 4 hours,
with checks every 5, 15 (default), or 30 seconds. iOS may end a session early.
Auto-start attempts sharing when opening the app once Music access and an account
are ready. A manual stop suppresses auto-start until the next foreground visit.
Continued-processing jobs are not automatically chained in the background.

Optional background refresh requests short, system-scheduled opportunities while
sharing is requested. Earliest scheduling is 15 minutes; actual timing can be much
later or absent. It does not maintain a continuous connection or promise continuous
presence. A refresh restores saved credentials, samples Music, and attempts a
bounded publish. Stop sharing cancels pending refreshes. Foreground sharing also
works on older supported iOS versions.

The countdown predicts for up to 30 seconds and corrects on fresh samples/seeks.
The Music screen uses native `MusicKit.ArtworkImage`, reading artwork from the
queue entry and the underlying Song/MusicVideo. The playback dependency previously
only inspected the queue-entry artwork. Settings → Artwork diagnostics reports
which source exists, whether the generated URL works over HTTP, and whether the
image decodes. URL query strings are omitted from copied diagnostics. This change
identified device-local `musicKit://` artwork in the reported trace. Version 1.2
resolves public artwork without requiring a MusicKit developer token: it uses the
playback store ID with Apple's public lookup, or a strictly verified metadata
search. Title, artist, album (when known), and duration must match; ambiguous
covers are rejected. The configured MusicKit catalog remains a secondary option.

The reported Persona track was found through both public routes, and its artwork
returned HTTP 200 in a live regression check. This verifies public resolution;
Discord-side rendering still needs a device check. See [presence notes](docs/PRESENCE.md).

## Verification

A clean unsigned WSL build and bundle checks passed. Configuration parsing,
credential namespace isolation, token serialization/expiry, and countdown/artwork
regression checks are runnable with:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash scripts/check-accounts.sh
bash scripts/check-token-storage.sh
bash scripts/check-presence.sh
bash scripts/check-vapor.sh
bash scripts/check-vapor.sh --benchmark
bash scripts/check-playback-state.sh
bash scripts/check-public-artwork.sh
# Optional network verification of the reported song:
bash scripts/check-public-artwork.sh --live
```

Live multi-account OAuth, simultaneous Discord presence, long-session runtime, and
visual/accessibility behavior, native vapor cadence/battery use, artwork sampling,
and Live Activity appearance/lifecycle need physical-device validation. Normal Xcode builds
have not been run on macOS during this work. The inherited precompiled Discord SDK
still has an unverified provenance question; see [fork notes](Vendor/DiscordSocialKit/FORK.md).

## Brand assets

`Resources/Brand/AppIcon.svg` is the versioned vector source. Regenerate catalog
icons with `python3 scripts/prepare-brand.py` on Linux/macOS with ImageMagick,
then commit the resulting PNGs. The WSL resource script derives loose resources
from that catalog. System SF Symbols are used for interface controls.

## License and credits

Apache License 2.0; see [LICENSE](LICENSE). Forked from
[itoolio/iRPC](https://github.com/itoolio/iRPC), with original credits to
[@thehairy](https://github.com/thehairy) and [@castdrian](https://github.com/castdrian).
Original source headers and the dependency's provenance notes remain in the repository.

## 1.3 playback state and motion performance

Playback UI state now follows native system-player notifications and a foreground
readback independently of Discord polling or continued-processing tasks. Successful
play/pause commands update the presentation immediately; contradictory old snapshots
are ignored briefly, with a bounded 1.5-second reconciliation window. Metadata
refresh no longer makes a catalog-history request when the Music queue is empty.

The fluid solver reuses owned buffers, precomputes separable force terms, and runs
on a user-initiated serial worker. A local optimized benchmark measured about
0.4–0.5 ms per solver/image-data frame, compared with 2.4–2.7 ms before this change.
These desktop measurements are not an iPhone frame-rate guarantee. Rendering now
targets the selected 30/60 FPS, with a 30 FPS maximum in Low Power Mode; the previous
8 FPS limit is removed. Speed remains a separate setting. Reduce Motion, pause,
Off, backgrounding, and hidden tabs still stop animation.

Settings → Diagnostics → Check playback & artwork includes the current UI,
MediaPlayer and MusicKit state plus the last active vapor update rate and render
time. Update counts measure layer submissions rather than compositor presentation.
Actual iPhone cadence and the reported pause/resume sequence still need device
verification; no physical-device playback run was available in this workspace.

## 1.4 startup readiness

The centre playback button shows a loading indicator while permission, initial
playback/metadata, and saved-account restoration are checked. Music controls are
disabled and permission/connection prompts are hidden until those checks finish.
Saved-account handshakes are bounded to three seconds; an unavailable saved account
opens the Accounts page rather than being presented as a new missing connection.

On cold launch, the existing MusicKit playing snapshot seeds the UI while the
MediaPlayer bridge hydrates. Actual playback notifications and subsequent commands
then take precedence, preserving the 1.3 pause/resume behavior. The playback icon
reflects Music itself, independently of the sharing switch. If Music is playing but
sharing is off, **Start sharing** enables presence without interrupting the song.
Pause pauses Music and stops sharing. No playback command is issued during startup.

## 1.5 dependency cleanup

Removed unused MusadoraKit references from both app targets and the local
DiscordSocialKit package. Music playback and artwork use Apple frameworks and
NowPlayingKit; NowPlayingKit has no external package dependencies.
