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
- Expiry, refresh thresholds, and OAuth/Rich Presence interfaces are preserved.
  Token exchange results are checked before storage; failed writes abort login.
  Sign-out deletes credentials, disconnects, and rejects late token writes until
  another authorization is started.
- The unused MusadoraKit dependency was removed; music/artwork resolution now
  belongs to the app. Upstream binary frameworks remain unchanged.

No cloud synchronization is added. iRPC's Xcode configuration already explicitly
disables CloudKit. Keychain uses a bundle-scoped service, no shared access group,
no synchronizable attribute, and `AfterFirstUnlockThisDeviceOnly` accessibility.
Switching between SwiftData and Keychain requires signing into Discord again;
the portable build cannot read or migrate the SwiftData database. Existing native
records are left intact. Sign out in each backend to delete that backend's record.
Re-signing with another team/bundle ID can change Keychain access.

Unmodified SDK executable SHA-256 values:

| Slice | SHA-256 |
| --- | --- |
| ios-arm64 | `ea9c7a1b046836f7116fd40498de099374a624f638a5d52ed15c87fba8238959` |
| ios-arm64-simulator | `cc0b534ca6827b8a32a9825f044ed8e4ed1d9c59e9c551f1c288f3497c4826c5` |

These identify the inherited binaries; they do not verify provenance against an
official Discord distribution. Original upstream source headers are retained.

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
