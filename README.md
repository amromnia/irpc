# Afterglow

A small native iPhone app for sharing your Apple Music soundtrack on up to two
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
open this application, enable **Public Client** under OAuth2, and add:

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
2. Connect Account 1 with Discord. To connect Account 2, switch to that user in
   Discord first; if a browser opens, sign into the second user there.
3. Choose which accounts should receive your music. Select a session length and
   tap **Start sharing**. Both selected, ready accounts receive the same Music
   snapshot; a disconnected account doesn't stop the other.
4. Tap an account to see its update acknowledgement, reconnect, or disconnect it.
   Disconnecting removes only that slot's saved credentials and clears its presence.

The app rejects connecting the same Discord user to both slots. Each slot has its
own client and credential store, isolated by bundle ID, application ID, and slot.
The WSL build stores tokens in Keychain; ordinary Xcode builds use separate
SwiftData stores. Cloud synchronization is explicitly disabled in both paths.
Rebranding changes the default bundle ID and using your own OAuth application
requires fresh sign-in; old upstream credentials are not imported.

The settings button opens accent/appearance controls. iOS 26 uses native Liquid
Glass; older supported versions use material/standard controls. Reduce Transparency
uses an opaque control surface. Minimum iOS is 17.6.

## Background behavior and limitations

On iOS 26+, sessions check Music approximately every 15 seconds, for a selected
30 minutes, 2 hours, or 4 hours. The selected runtime is a finite app target, not
an OS guarantee: iOS may stop the job early. Each new session starts from a
foreground user action; there is no silent-audio fallback or automatic background
renewal. Older iOS versions require keeping the app open.

The countdown predicts for up to 30 seconds between fresh player observations and
corrects on new samples/seeks. Artwork uses MusicKit's URL first; Discord still
needs to fetch it. Discord acceptance is displayed per account and does not prove
another client rendered the activity. Force-quitting may leave stale presence until
Discord expires/clears it. See [presence notes](docs/PRESENCE.md).

## Verification

A clean unsigned WSL build and bundle checks passed. Configuration parsing,
credential namespace isolation, token serialization/expiry, and countdown/artwork
regression checks are runnable with:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash scripts/check-accounts.sh
bash scripts/check-token-storage.sh
bash scripts/check-presence.sh
```

Live two-account OAuth, simultaneous Discord presence, long-session runtime, and
visual/accessibility behavior need physical-device validation. Normal Xcode builds
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
