# Your Discord application and two accounts

Public application ID supplied for this build: `1572242579049808028`.
The app's working brand is **Afterglow**. Its name, client ID, and bundle identifier
are public build values in `.env`; see `.env.example`. Runtime tokens are never
stored there, committed, or requested from the user manually.

## Developer Portal setup

In [your Discord application](https://discord.com/developers/applications/1572242579049808028):

1. In **OAuth2**, enable **Public Client**.
2. Add the exact mobile redirect `discord-1572242579049808028:/authorize/callback`.
3. Configure Social SDK/presence access if the portal presents a setup step for
   your application. The wrapper requests the SDK's default presence scopes.
4. Optionally upload the generated app icon from
   `iRPC/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png` as your
   application icon. This controls the application fallback when artwork is absent.

The app already registers `discord-1572242579049808028` as a URL scheme and permits
querying the Discord URL scheme. Discord's
[mobile account-linking guide](https://discord.com/developers/discord-social-sdk/development-guides/account-linking-on-mobile)
documents the matching URI and PKCE requirements. The existing wrapper generates
a verifier/challenge; no client secret or bot token is used.

## Connect and test

1. Install the newly signed **Afterglow** app. Its bundle identifier differs from
   the previous iRPC IPA; sign it with a compatible profile and grant Music access.
2. In Discord, select your first user, then connect **Account 1** in Afterglow.
3. Switch Discord to your second user, then connect **Account 2**. If authentication
   opens a browser instead, use that second user in the browser's login session.
   The bundled SDK chooses the authorization UI; Afterglow does not collect passwords.
4. Both cards should show different users. Linking the same user twice disconnects
   the second slot and shows a message asking you to switch accounts.
5. Enable both account switches, play Music, and start sharing. Inspect both profiles
   from another Discord session. Check that track, artist, artwork, and countdown agree.
6. Turn off one switch: only its activity should clear. Turn it back on: it should
   receive the current song on the next poll. Disconnect one account and verify the
   other keeps sharing. Relaunch and confirm both slots restore independently.

These simultaneous OAuth/profile checks have **not** been performed from the Windows
workspace. The code uses two SDK clients with a single callback dispatcher; the
build and storage-isolation tests do not certify live two-user SDK behavior.

## Persistence and privacy

Keychain identity includes the actual bundle ID, Discord application ID, and account
slot. Native Xcode stores use a separate SwiftData configuration per client/slot.
CloudKit is disabled. The app keeps two fixed slots; it does not require a backend
or share account tokens with each other. One Music snapshot is sent to all selected,
ready clients. A disconnected account is skipped so it doesn't terminate the other.

Changing the client ID, bundle ID, or backend requires signing in again. Old stores
are not automatically migrated or deleted. Disconnect in an older build if you
want that build's credentials removed; revoke the old application's authorization
in Discord if no longer needed. App display-name changes alone do not change storage.

Appearance settings are local and non-sensitive. The custom accent affects the UI;
the installed icon uses the static red brand artwork.

## Build configuration

```bash
cp .env.example .env
python3 scripts/configure-app.py
bash scripts/build-wsl.sh
```

For normal Xcode, run the same configuration script before opening/building the
project. Generated local xcconfig values are shared by both app targets. For GitHub
Actions, set repository variable `DISCORD_APPLICATION_ID`; it is not a secret.
The existing workflow is optional and was not used for local compilation.
