# Local Afterglow Windows/WSL build

Verified November 17, 2026 on Windows 11 + WSL2 Ubuntu with Swift 6.4.1,
Xcode 27.1's extracted Darwin/iOS SDK, and xtool 2.0.0-beta.1. All compilation,
resource conversion, linking, and IPA packaging run locally. No Mac or hosted
build is involved. The original `iRPC.xcodeproj` remains the build input.

## Build

Use a checkout on WSL's native filesystem. Do not use the experimental
`irpc-noassets` directory or compile from `/mnt/c`.

```bash
cd ~/ios-projects/irpc
# Apply/pull this fork's committed changes first; preserve any local experiments.
sudo apt install imagemagick python3
cp .env.example .env
# Set public application values if needed.
python3 scripts/configure-app.py
bash scripts/check-token-storage.sh
bash scripts/build-wsl.sh
```

The build script generates loose resources, exports `IRPC_XTOOL=1`, and runs:

```bash
xtool dev build --scheme iRPC-Xtool --configuration release --ipa --verbose
```

Output: `xtool/Afterglow.ipa`. Full log: `build/xtool-build.log`.
The script finishes by checking the IPA structure, icon bytes, Discord PNG,
configured bundle identifier (default `com.amromnia.afterglow`), minimum iOS (`17.6`), Music usage
description, background task settings, linked libraries, embedded Discord
framework, and absence of an app code signature/provisioning profile/SwiftData
link/catalog JSON files. The SDK framework's inherited signature is not treated
as an app signature; your signer must re-sign embedded frameworks too.

The implementation was tested in `/home/amr/ios-projects/irpc-xtool-build`, an
isolated native Linux copy of this fork's working source. The pre-existing WSL
checkout and its experiments were preserved. The unsigned artifact was also
copied to the Windows checkout's ignored `build/Afterglow-unsigned.ipa`.

## Compatibility inventory

| Item | Normal `iRPC` target | `iRPC-Xtool` target |
| --- | --- | --- |
| Source/UI/Music/Discord/background processing | Shared Swift source | Same functionality and SDK |
| Asset catalog | Original `Assets.xcassets` through actool | Catalog excluded from target membership |
| App icons | Original app icon set | Original PNGs copied byte-for-byte as loose resources; icon plist keys supplied |
| Discord custom symbol | Original `.symbolset` | Regular-M glyph extracted from the same SVG sheet and rasterized as a template PNG |
| AccentColor | Empty color entry; platform default | Same platform default |
| SF Symbols, artwork, avatar images | System symbols / MusicKit.ArtworkImage / AsyncImage avatars | Same |
| Token storage | Isolated per-account SwiftData via `TokenStorage` | Isolated per-account Keychain via `TokenStorage`, explicit compile flag |
| CloudKit | Already explicitly disabled | No cloud sync; device-only Keychain item |
| SwiftData macros | Original model retained | Entire model/export/consumer paths excluded |
| Build mode | Standard Xcode Debug/Release | Separate target/scheme, Debug/Release with `IRPC_XTOOL` |
| Bitcode stripping | Default build behavior | Disabled for copied frameworks; xtool has no usable bitcode-strip tool here |
| Swift runtime lookup | Standard Xcode search paths | Adds `$(SWIFT_RESOURCE_DIR)/iphoneos` from the extracted Xcode toolchain |

No storyboards, XIBs, app intents, SwiftUI previews, generated asset references,
or additional app macro models were found. Core iOS frameworks remain linked;
the portability change concerns the build host, not replacing iOS frameworks.
Swift package sources still use MusadoraKit/MusicKit and NowPlayingKit.

ScrobbleKit had no app source consumers; LaunchAtLogin-Modern was an unused
macOS-oriented package reference. Both were removed after checking usage.
MusadoraKit is fixed to 6.1.0 and NowPlayingKit to revision
`6b18f98ae1e0e23ff4f6dc8b63d6e321aa5aede6`. DiscordSocialKit is a maintained local
fork under `Vendor/DiscordSocialKit`, rather than a mutable remote checkout.
See [its fork notes](../Vendor/DiscordSocialKit/FORK.md) for source provenance,
storage details, and unchanged binary hashes.

## Resources and designer updates

AssetKit was investigated first. Its [documented supported types](https://github.com/xtool-org/AssetKit/blob/main/README.md)
include image/color/app-icon sets, but not this catalog's custom `.symbolset`.
This build therefore uses a plain-resource path; it does not install a fake
actool or pretend to generate `Assets.car`.

`scripts/prepare-xtool-resources.py` writes only to ignored `Resources/Xtool`,
outside the synchronized app folder. The target has explicit PNG resource
references, so catalog `Contents.json` files cannot collide in the bundle.
The original catalog is never renamed, moved, or modified. The rendered Discord
glyph uses its original path geometry, alpha transparency, and template tinting;
it is not a replacement logo. It uses the default Regular-M glyph, not all 27
weight/size variants in the symbol sheet.

Edit the original catalog when updating assets, then rerun the build script.
Changes to existing PNGs or the default SVG glyph are picked up automatically.
Adding/removing/renaming app-icon files also requires updating the xtool target's
resource references. New catalog types or a now-explicit AccentColor cause the
script to fail with an actionable message until matching portable handling is
added. The IPA verifier detects missing expected icon files.

## Persistence and migration

The networking implementation has no knowledge of database queries. It calls
`TokenStorage.load/save/delete`; saving replaces only that account slot’s credentials. All account clients share one SDK callback pump.
The SwiftData adapter keeps the existing model schema and rolls back failed
writes. The Keychain adapter updates an existing item atomically or inserts a new
one, distinguishes a missing item from storage failure, and rejects corrupt data.
Token expiry and refresh thresholds survive JSON round-trips. Tokens/secrets are
not printed by the new storage code. Sign Out deletes the current backend's item.

The native fork already used `cloudKitDatabase: .none`; the older upstream README's
CloudKit claim does not describe this checkout. Neither build synchronizes tokens
to CloudKit. The portable backend does not automatically migrate a SwiftData
database: sign into Discord again after switching build modes. Native records
remain intact, so sign out in the native build too if you want them deleted.
Neither backend switch nor disabling CloudKit deletes historical cloud records
from versions that may previously have synced them.

## Signing and installation

The unsigned build is verified. xtool's auth status reports an existing login,
but no iPhone was visible during the device probe. Signing, installation, and
device functionality are therefore not yet verified. With the phone attached
to WSL, unlocked, trusted, and Developer Mode enabled:

```bash
cd ~/ios-projects/irpc
xtool auth status
# Only if your existing login needs renewal:
xtool auth login
```

The unsigned script rejects `--sign` to avoid mixing artifacts. For signing, run
the underlying command directly so the unsigned verification step is not applied:

```bash
IRPC_XTOOL=1 xtool dev build --scheme iRPC-Xtool --configuration release --ipa --sign
xtool install --usb xtool/Afterglow.ipa
xtool launch --help
```

Use the direct signed command after the unsigned script has prepared resources.
Signing may select/update provisioning identifiers and profiles; use the bundle
identifier and MusicKit/Discord OAuth configuration appropriate to your account.
The exact installation command above is supported by the installed xtool version.
The existing zsign workflow can alternatively sign the unsigned IPA; it must sign
both the app and the embedded Discord framework with a matching profile.

On the phone, verify the icon and tinted Discord glyph, Music access, Discord
authorization, relaunch persistence, refresh after token aging, sign-out/relaunch,
pause/resume and track changes, and the background-session tests in README.
Successful compilation does not prove those runtime behaviors.

## Resolved build failures and remaining limits

1. `actool ... is not an executable file`: the dedicated target excludes the
   catalog and includes generated loose resources.
2. `SwiftDataMacros.PersistentModelMacro ... not found`: the explicit portable
   package/app paths use Keychain and a Codable token record; no dummy macro.
3. `bitcode_strip ... is not an executable file`: disabled copied-framework
   bitcode stripping only in the portable target.
4. `_swift_FORCE_LOAD_$_swiftCompatibility56` undefined: added the extracted
   toolchain's iPhoneOS runtime library search path; no fake symbol/stub library.

The local linker still emits warnings about its platform support and some
auto-linked SDK frameworks. The actual link succeeds using real SDK libraries;
no private framework or stub was added. The inherited Discord SDK binary remains
a provenance trust question from the earlier review. Normal Xcode builds retain
their storage/catalog path but have not been run on macOS during this work.

## Public configuration and rebranding

`Config/App.xcconfig` is shared by the two application targets. The configuration
script validates allowlisted values from `.env` or environment variables and writes
ignored `Config/Local.xcconfig`/`Config/BuildIdentity.json`. Both app plists include
the selected Discord client ID and URL scheme. The verifier compares the actual
bundle against those generated public values. No `.env` file or token is packaged.

The installed display/product name is Afterglow and the default bundle identifier
is now `com.amromnia.afterglow`. Internal project/target names remain stable. This
is a new app identity relative to the old IPA and needs a matching signing profile
and fresh Discord/Music authorization. The old app's credentials are not copied.

The initial redesigned app was also built from a clean native WSL copy at
`/home/amr/ios-projects/afterglow-verify`. iOS 26 glass APIs compile through xtool.
Multi-account OAuth/live presence and visual behavior remain device tests.
