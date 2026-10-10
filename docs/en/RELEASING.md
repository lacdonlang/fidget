# Releasing

**English** · [简体中文](../zh-CN/RELEASING.md)

Fidget is distributed outside the App Store, signed with a Developer ID and notarized (see [Architecture](ARCHITECTURE.md) for why).

## One-time setup

1. Create a **Developer ID Application** certificate (requires the Account Holder role) at [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) or in Xcode → Settings → Accounts → Manage Certificates, then check that it's in your keychain:
   ```bash
   security find-identity -v -p codesigning   # lists "Developer ID Application: Your Name (TEAMID)"
   ```
2. Store notarization credentials (create an app-specific password at appleid.apple.com):
   ```bash
   xcrun notarytool store-credentials fidget-notary \
     --apple-id "<Apple ID>" --team-id "<TEAMID>" --password "<app-specific password>"
   ```
3. Create `.signing.env` in the repository root. Git ignores it, and every script signs with it unless `CODESIGN_IDENTITY` is set in the environment:
   ```bash
   echo 'CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"' > .signing.env
   ```

## Building a release locally

```bash
make app        # build/Fidget.app with hardened runtime and timestamp
make notarize   # notarize and staple the app
make dmg        # dist/Fidget-<version>.dmg, signed
scripts/notarize.sh dist/Fidget-<version>.dmg   # optional: notarize the DMG too
```

Without an identity, the app is signed ad hoc and the hardened runtime stays off, because it would stop Sparkle from loading. The version comes from `VERSION`; the build number is derived from it (1.3.0 → 10300) and can be overridden with `BUILD_NUMBER`.

To use Xcode instead, run `make xcodeproj && open Fidget.xcodeproj` (needs `brew install xcodegen`), set `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE = Automatic` and `CODE_SIGN_IDENTITY = Apple Development` in `Config/Signing.xcconfig`, then use Product → Archive → Distribute App → Developer ID.

## CI

- `.github/workflows/ci.yml` builds and tests every push and pull request, producing an ad-hoc signed app for verification only.
- `.github/workflows/release.yml` runs when a `v*` tag is pushed: test → build and sign → notarize the app → DMG and zip → sign the zip and write the appcasts → notarize the DMG → create the GitHub Release with the DMG, the zip, `appcast.xml` and `appcast.zh-CN.xml`. Without a certificate it produces ad-hoc signed builds; without notary credentials it skips notarization.

| Secret | Contents |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | The Developer ID Application certificate exported as .p12, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The .p12 password |
| `CODESIGN_IDENTITY` | `Developer ID Application: Name (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` | Notarization credentials |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key that signs updates (see below) |

## Update signing key

- The key pair was created with Sparkle's `generate_keys`, and the private key lives in the owner's login keychain under the account `com.lacdon.fidget`:
  ```bash
  GENERATE_KEYS=.build/artifacts/sparkle/Sparkle/bin/generate_keys
  $GENERATE_KEYS --account com.lacdon.fidget                 # create the key (once)
  $GENERATE_KEYS --account com.lacdon.fidget -p              # print the public key
  $GENERATE_KEYS --account com.lacdon.fidget -x private.key  # export the private key
  ```
- The public key is `SUPublicEDKey` in `Resources/Info.plist`. Store the exported private key as a CI secret with `gh secret set SPARKLE_ED_PRIVATE_KEY < private.key`, then delete the file.
- **Back up the private key** together with the keychain. If it's lost, existing installs can never be updated again, because new signatures won't match the public key they ship with. To rotate keys, first ship a release that contains the new public key but is still signed with the old private key.
- The repository must stay public: installed apps download the appcast and the zip from the latest release without signing in.

## Release steps

1. Bump `VERSION` (and `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`).
2. Add a `## <version>` section to both `CHANGELOG.md` (English only) and `CHANGELOG.zh-CN.md`, with one `- ` line per note. These become the update notes; `scripts/make-appcast.sh` fails if either changelog lacks the section.
3. Run `make test` and go through the manual checklist in [Testing](TESTING.md).
4. Commit, then tag and push: `git tag v<version> && git push origin v<version>`. CI does the rest.
5. From the previous version, use Check for Updates… to confirm the update installs and the Accessibility permission is kept.

## Local development and TCC

macOS identifies apps by their code signature. An ad-hoc signature changes with every build, so the Accessibility permission stops working after a rebuild. Sign development builds with an Apple Development certificate (`CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app`) or run from Xcode with automatic signing.

- If several Fidget entries appear, or the switch is on but not honored, run `tccutil reset Accessibility com.lacdon.fidget` and grant the permission again (Reset Permission in the app does the same).
- With several copies of `Fidget.app` on disk (for example `build/` and Xcode's DerivedData), `open fidget://…` may reach the wrong one. Use `open -a /absolute/path/Fidget.app "fidget://…"`.

## Verifying a build

```bash
codesign -dv --verbose=4 build/Fidget.app           # signature details
spctl --assess --type execute -vv build/Fidget.app  # Gatekeeper: "accepted" once notarized
xcrun stapler validate build/Fidget.app
```
