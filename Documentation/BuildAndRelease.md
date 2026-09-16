# Build and Release Guide

This guide covers WrapPin's development builds and the GitHub Actions IPA workflow.

## Current release identity

- Marketing version: `1.0.6`
- Current build: `9`
- Bundle identifier: `com.suversal.wrappin`
- Minimum deployment target: iOS 27
- Supported device family: iPhone

The version and build are shown in **Settings** inside the app. The built date and time come from the timestamp embedded for that packaged build.

## Version and build rules

WrapPin uses two separate numbers:

- The **version** describes the public release. Increase it for each subsequent stable release.
- The **build** identifies one exact install. Increase it once for every build installed on a test iPhone or packaged as an IPA.

Ordinary compile checks do not consume a build number. Build numbers must never move backwards for a later install or upload.

Both values are stored in the target build settings:

- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

Keep the Debug and Release configurations identical.

## Build in Xcode

1. Open `WrapPin.xcodeproj`.
2. Select the **WrapPin** scheme.
3. Select the connected iPhone.
4. Open **Signing & Capabilities** and confirm the development team.
5. Press **Run**.

The simulator can validate most interface states, but it cannot perform the real RPPairing handshake or start a location session.

## Native pairing engine

The prebuilt `Frameworks/WrapPinPairingFFI.xcframework` should be committed with both arm64 iPhone and arm64 Apple Silicon simulator slices.

Only rebuild it after changing `Native/WrapPinPairingFFI`. The rebuild requires Rust targets for:

- `aarch64-apple-ios`
- `aarch64-apple-ios-sim`

Run `scripts/build-pairing-engine.sh` from the project directory. Confirm the app still builds for both a physical iPhone and the simulator afterwards.

## Archive preparation

Before creating an archive:

1. Finish the regression checklist.
2. Increase `CURRENT_PROJECT_VERSION` for the archive.
3. Confirm the public version.
4. Use the Release configuration.
5. Confirm the app icon and display name.
6. Set and verify the build timestamp.
7. For a public build, set the TelemetryDeck App ID and namespace and confirm no secret token is present.
8. Confirm `WrapPinPairingFFI.xcframework` is embedded and signed.
9. Confirm the app bundle contains `WrapPin-LICENSE.txt`, `THIRD_PARTY_NOTICES.txt` and `idevice-LICENSE.txt`.
10. Build once for a physical iPhone.

Then select **Any iOS Device (arm64)** and choose **Product → Archive**. Xcode opens Organizer after a successful archive.

## IPA and SideStore

### Build with GitHub Actions

The `Build IPA` workflow packages an unsigned Release archive on GitHub's
`xcode-27` macOS runner. It uses the committed native XCFramework; Rust, Apple
certificates, provisioning profiles and Apple account credentials are not needed.
The runner is currently a public preview and may use a beta Xcode 27. The exact
Xcode version and SDK are recorded in `build-info.txt` for each package.

1. Commit and push `.github/workflows/build-ipa.yml` and `scripts/build-ipa.sh`
   to the repository's default branch so the manual trigger becomes available.
2. Open **Actions → Build IPA → Run workflow**, then choose the branch to build.
3. Enter a new **build_number** greater than all builds previously packaged or
   installed. The source currently uses `9`, so the first CI build can use `10`.
   The script checks against the source build only; it cannot detect an earlier
   manual/CI build number. Use a new number for each new package, including reruns.
4. Download the `WrapPin-IPA-…` artifact from the completed run and extract it.
   It contains `WrapPin-<version>-build<number>.ipa`, its `.sha256` file, and
   `build-info.txt`. Artifacts are kept for 30 days. Build logs are kept separately
   for 14 days, including when the archive fails.
5. Run `shasum -a 256 -c WrapPin-<version>-build<number>.ipa.sha256` in the
   extracted directory, then import the IPA from Files into SideStore.

The marketing version comes from the project. The supplied build number and a
fresh UTC build timestamp override the archive settings without modifying source
files. Record the new build in both project configurations before the next release
and keep subsequent local and CI builds increasing. The workflow runs the existing
localization, failure-stage and background-session checks before archiving. It
checks the package's identity, arm64 executable, privacy manifest and legal files;
SideStore installation and real-device pairing/location acceptance remain manual.
It does not create tags or publish GitHub Releases.

Optional repository **Settings → Secrets and variables → Actions → Variables**:

- `WRAPPIN_TELEMETRY_APP_ID`
- `WRAPPIN_TELEMETRY_NAMESPACE`

Leave both unset to build without a telemetry destination. These are ingestion
identifiers embedded in the app, not secret API tokens. CI always uses the public
bundle identifier `com.suversal.wrappin` and never needs `Local.private.xcconfig`.

The same script can be run on a Mac with Xcode 27 and the iOS 27 SDK:

```sh
BUILD_NUMBER=10 bash scripts/build-ipa.sh
```

Outputs are under the ignored `build/` directory. Move an existing
`build/WrapPin.xcarchive`, `build/ipa-staging` and `build/ipa` aside before rerunning.

### Install the unsigned IPA

WrapPin's SideStore IPA is built from an optimized, unsigned Release archive. SideStore applies the user's personal development certificate during installation. The native pairing engine is statically linked into the app binary, so it does not need a separate framework or extension.

For personal SideStore installation:

1. Use the verified IPA from `Releases`, or create a new one from a Release archive.
2. Move the IPA to Files or another location SideStore can access.
3. Open SideStore, choose the IPA and allow SideStore to sign/install it with the configured Apple ID.
4. Keep Developer Mode enabled.
5. Complete WrapPin's pairing on the installed copy if its signing identity gives it a new Keychain container.

SideStore re-signing and Apple's free-account limits can affect expiry, app identifiers and available entitlements. The final IPA must therefore be tested as a SideStore install rather than assuming an Xcode-installed build is equivalent. With a free Apple Account, SideStore normally refreshes the signed installation within Apple's seven-day development period.

Do not treat an Xcode Debug `.app` folder renamed to `.ipa` as a release package. Use the verified Release archive/package workflow.

## Privacy statistics configuration

Optional statistics are sent directly to TelemetryDeck's Ingest API. WrapPin does not embed its SDK and permits only the event names and app/build values defined in `UsageAnalyticsService.swift`.

Three build settings configure a public or locally signed build:

- `WRAPPIN_BUNDLE_IDENTIFIER`
- `WRAPPIN_TELEMETRY_APP_ID`
- `WRAPPIN_TELEMETRY_NAMESPACE`

The tracked `Configuration/Local.xcconfig` keeps the public bundle identifier and leaves the TelemetryDeck ingestion identifiers blank. Copy `Configuration/Local.private.xcconfig.example` to the ignored `Configuration/Local.private.xcconfig` to override the bundle identifier for a personal team, set `DEVELOPMENT_TEAM`, or configure both TelemetryDeck values for a release. The telemetry values are ingestion identifiers, not an account password or API token. Without both values, the client sends nothing. Keeping the live destination and signing identity outside the public project prevents forks from accidentally adding data to WrapPin's dashboard or inheriting the repository owner's Apple team.

Before packaging a configured build, inspect the event structure, confirm the privacy disclosure still matches it, and run the privacy rows in the regression checklist. Never add coordinates, place text, searches, saved locations, routes, pairing material, device names, user-supplied text or diagnostic content to an event.

## Release records

For each distributed build, record:

- Version and build number.
- Date and time created.
- Xcode and iOS versions used.
- Signing method.
- Device used for testing.
- Regression checklist result.
- Known issues.

This makes a problem report traceable to the exact binary shown in WrapPin's Settings screen.
