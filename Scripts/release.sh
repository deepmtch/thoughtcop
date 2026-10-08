#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ -n "$(/usr/bin/git status --porcelain --untracked-files=normal)" ]; then
    echo "release blocked: commit or remove all worktree changes first" >&2
    exit 2
fi

identity=${THOUGHTCOP_SIGNING_IDENTITY:-}
notary_profile=${THOUGHTCOP_NOTARY_PROFILE:-}

if [ -z "$identity" ]; then
    echo "release blocked: set THOUGHTCOP_SIGNING_IDENTITY to a Developer ID Application identity" >&2
    exit 2
fi
case "$identity" in
    "Developer ID Application: "*) ;;
    *)
        echo "release blocked: THOUGHTCOP_SIGNING_IDENTITY must name a Developer ID Application certificate" >&2
        exit 2
        ;;
esac
if [ -z "$notary_profile" ]; then
    echo "release blocked: set THOUGHTCOP_NOTARY_PROFILE to a notarytool keychain profile" >&2
    exit 2
fi

if ! /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/grep -F -- "\"$identity\"" >/dev/null; then
    echo "release blocked: signing identity is not available in the keychain: $identity" >&2
    exit 2
fi
if ! /usr/bin/xcrun --find notarytool >/dev/null 2>&1 \
    || ! /usr/bin/xcrun --find stapler >/dev/null 2>&1; then
    echo "release blocked: the selected Xcode does not provide notarytool and stapler" >&2
    exit 2
fi
if ! /usr/bin/xcrun notarytool history --keychain-profile "$notary_profile" \
    --output-format json >/dev/null; then
    echo "release blocked: notarytool keychain profile is missing or invalid: $notary_profile" >&2
    exit 2
fi

./Scripts/test.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    Resources/ThoughtCop-Info.plist)
architecture=$(/usr/bin/uname -m)
release_parent=".build/releases"
/bin/mkdir -p "$release_parent"
release_dir=$(/usr/bin/mktemp -d "$release_parent/ThoughtCop-$version.XXXXXX")
app="$release_dir/ThoughtCop.app"
submission_zip="$release_dir/ThoughtCop-$version-notarization.zip"
submission_json="$release_dir/notarization.json"
final_zip="$release_dir/ThoughtCop-$version-macos-$architecture.zip"

/usr/bin/ditto .build/ThoughtCop.app "$app"
/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$identity" "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

# Submit the exact signed app bytes. The final archive is recreated after
# stapling so the distributed ZIP contains Apple's ticket.
/usr/bin/ditto -c -k --keepParent "$app" "$submission_zip"
/usr/bin/xcrun notarytool submit "$submission_zip" \
    --keychain-profile "$notary_profile" --wait --output-format json \
    > "$submission_json"
status=$(/usr/bin/plutil -extract status raw -o - "$submission_json")
if [ "$status" != "Accepted" ]; then
    echo "release blocked: Apple notarization status is $status; inspect $submission_json" >&2
    exit 1
fi

/usr/bin/xcrun stapler staple "$app"
/usr/bin/xcrun stapler validate "$app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app"
/usr/bin/ditto -c -k --keepParent "$app" "$final_zip"
/usr/bin/shasum -a 256 "$final_zip" > "$final_zip.sha256"

echo "release ready: $final_zip"
echo "checksum: $final_zip.sha256"
echo "notarization result: $submission_json"
