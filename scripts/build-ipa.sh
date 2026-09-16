#!/bin/bash
# Create the unsigned Release IPA that SideStore signs during installation.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo 'BUILD_NUMBER must be an integer from 1 to 9999.' >&2
    exit 1
fi

source_build="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION = ([0-9]+);/\1/p' WrapPin.xcodeproj/project.pbxproj | sort -u)"
if [[ ! "$source_build" =~ ^[0-9]+$ ]] || (( BUILD_NUMBER <= source_build )); then
    echo "BUILD_NUMBER must exceed the source build ($source_build)." >&2
    exit 1
fi

# Use a fresh staging directory; refuse to mix output from earlier runs.
build_root="$PWD/build"
archive="$build_root/WrapPin.xcarchive"
staging="$build_root/ipa-staging"
output="$build_root/ipa"
for directory in "$archive" "$staging" "$output"; do
    if [[ -e "$directory" ]]; then
        echo "Build output already exists: $directory. Move it aside before rebuilding." >&2
        exit 1
    fi
done
mkdir -p "$build_root/logs"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

xcodebuild archive \
    -project WrapPin.xcodeproj \
    -scheme WrapPin \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -derivedDataPath "$build_root/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    DEVELOPMENT_TEAM= \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    "WRAPPIN_BUILD_TIMESTAMP=$timestamp" \
    WRAPPIN_BUNDLE_IDENTIFIER=com.suversal.wrappin \
    "WRAPPIN_TELEMETRY_APP_ID=${WRAPPIN_TELEMETRY_APP_ID:-}" \
    "WRAPPIN_TELEMETRY_NAMESPACE=${WRAPPIN_TELEMETRY_NAMESPACE:-}" \
    2>&1 | tee "$build_root/logs/archive.log"

app="$archive/Products/Applications/WrapPin.app"
plist="$app/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
packaged_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
[[ "$packaged_build" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == 'com.suversal.wrappin' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :WrapPinBuildTimestamp' "$plist")" == "$timestamp" ]]
[[ ! -e "$app/_CodeSignature" && ! -e "$app/embedded.mobileprovision" ]]
xcrun lipo -verify_arch arm64 "$app/WrapPin"
for resource in PrivacyInfo.xcprivacy WrapPin-LICENSE.txt THIRD_PARTY_NOTICES.txt idevice-LICENSE.txt; do
    if [[ -z "$(find "$app" -type f -name "$resource" -print -quit)" ]]; then
        echo "Missing packaged resource: $resource" >&2
        exit 1
    fi
done

mkdir -p "$staging/Payload" "$output"
ditto "$app" "$staging/Payload/WrapPin.app"
package="WrapPin-${version}-build${packaged_build}.ipa"
(
    cd "$staging"
    COPYFILE_DISABLE=1 /usr/bin/zip -qry "$output/$package" Payload
)
unzip -tq "$output/$package"
(
    cd "$output"
    shasum -a 256 "$package" > "$package.sha256"
)
{
    echo "Package: $package"
    echo "Commit: $(git rev-parse HEAD)"
    echo "Built at: $timestamp"
    echo 'Signing: unsigned; install using SideStore or another signing tool'
    xcodebuild -version
    echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
    if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        echo "Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
    fi
    cat "$output/$package.sha256"
} > "$output/build-info.txt"
cat "$output/build-info.txt"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$output/build-info.txt" >> "$GITHUB_STEP_SUMMARY"
fi
