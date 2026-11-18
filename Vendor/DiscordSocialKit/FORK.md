# Maintained local DiscordSocialKit fork

Upstream: https://github.com/itoolio/DiscordSocialKit

Base revision: `425e949ef11b54823a4902ff34c8c02771c20e8c`.
This directory is the source of truth, versioned in the iRPC Git repository;
there is no generated-checkout patch or separate remote dependency fork to update.

Focused changes:

- `TokenStorage` owns loading, replacement, and deletion. Discord networking uses
  that interface and reports storage failure instead of assuming an empty store.
- `SwiftDataTokenStorage` preserves the original model/schema and
  `setModelContext` interface in ordinary Xcode builds.
- The explicit `IRPC_XTOOL=1` manifest setting defines `IRPC_XTOOL` for this package.
  The portable build uses a Codable token record and `KeychainTokenStorage`.
  SwiftData model/macros/exports are excluded from that build.
- Token expiry, refresh thresholds, and OAuth interfaces are preserved.
  Token exchange results are checked before storage; failed writes abort login.
  Sign-out deletes credentials, disconnects, and rejects late token writes until
  another authorization is started.
- The unused MusadoraKit dependency was removed; music/artwork resolution now
  belongs to the app.
- Discord's inherited binaries were replaced with the official 1.11.24259 release
  XCFramework from the user-provided Developer Portal download. Both device and
  simulator slices and their headers are replaced together. `SDK.json` records
  the archive and binary hashes; `License-Notices.txt` preserves the release's notices.
- Account metadata uses `GetCurrentUserV2` and drops its optional handle safely.
  Owned metadata strings are freed, and avatar arguments use animated GIF/static
  PNG in the SDK's documented order. Diagnostics report the runtime SDK version.

No cloud synchronization is added. iRPC's Xcode configuration already explicitly
disables CloudKit. Keychain uses a bundle-scoped service, no shared access group,
no synchronizable attribute, and `AfterFirstUnlockThisDeviceOnly` accessibility.
Switching between SwiftData and Keychain requires signing into Discord again;
the portable build cannot read or migrate the SwiftData database. Existing native
records are left intact. Sign out in each backend to delete that backend's record.
Re-signing with another team/bundle ID can change Keychain access.

## Discord Social SDK 1.11.24259

Source: `DiscordSocialSdk-1.11.24259.zip`, downloaded by the user from the Discord
Developer Portal and provided under `build/`. The archive is not committed.
Only the official **release iOS XCFramework** is included; macOS, Android, Linux,
Windows, debug builds, and optional Krisp voice processing are not imported.
The iOS library has no required Krisp load dependency; the app does not use voice.
The SDK binary and headers are copied byte-for-byte, without binary patching.
Each slice's module map exposes `cdiscord.h` directly: the official umbrella
also includes the C++ wrapper unconditionally, which fails pure Swift/C module
scanning in xtool (`atomic` not found). We consume only the C API, so no C++
interoperability or extra C++ header search paths are needed. This module map
adjustment applies to both Xcode and portable builds.

| Slice | SHA-256 |
| --- | --- |
| ios-arm64 | `445e2261b7f001d04f6b467b982e899ce173dc03894bc7a185ce6cebc3a5509f` |
| ios-arm64-simulator | `b4e94f6d8f1cbf796667b11f24ac5fe3adfd68083553191470033124730f2c1a` |

`SDK.json` also records the source archive SHA-256. `scripts/verify-ipa.py`
checks that the embedded device SDK matches the pinned release exactly.
This establishes equality to the supplied download; no independent publisher
signature verification is claimed. The old unversioned upstream executables
remain available in Git history. Original wrapper source headers are retained.

Release notes: https://discord.com/developers/docs/social-sdk/release_notes.html

## Multiple-account integration

The app creates an independent client for each added account, each with a `DiscordCredentialScope` identified by
application ID and slot. Keychain uses separate account attributes within a service
that includes the bundle/client ID; normal Xcode uses separate named SwiftData stores.
Each save/delete affects only that slot. `Discord_RunCallbacks` runs from one shared
serial pump for all clients, rather than concurrently from one loop per manager.
Changing the application ID never imports the previous client's tokens. The multi-client
source path compiles; simultaneous live account authorization still needs device tests.

Account slots have no fixed count cap. Removing an account drops its SDK client
on the serial callback queue. Callback contexts use weak manager references and
SDK user-data free hooks, so removed accounts are not retained by status callbacks.
Presence request buffers are released by their SDK free hook, including cancellation.

The app now resolves public catalog artwork from MusicKit Song relationships once
per sampled track. The wrapper no longer makes catalog-ID requests using playback
IDs. It accepts the supplied public HTTPS artwork. The app owns metadata-based
resolution/caching; a missing URL no longer reuses an image by an ambiguous
library ID.

## Listening timing (app 1.9)

Valid Listening activity carries both start/end timestamps in milliseconds;
unknown timing and the bounded next-track waiting state carry neither. The app
owns sampling and resend policy. Unused `updateCurrentPlayback`/`clearPlayback`
cache APIs and their legacy Timer path are removed. `startPresenceUpdates` only
enables publication, and stop clears synchronously. SDK activity, asset, and
timestamp objects are dropped after submission according to the official C++
wrapper's ownership behavior. SDK binaries are unchanged by this cleanup.
