#!/usr/bin/env python3
"""Verify that the release pipeline cannot regress to an ad-hoc artifact."""

from pathlib import Path


script = (Path(__file__).parent / "release.sh").read_text()

required = [
    '"Developer ID Application: "*',
    "/usr/bin/security find-identity -v -p codesigning",
    "/usr/bin/codesign --force --options runtime --timestamp",
    "/usr/bin/codesign --verify --deep --strict --verbose=2",
    "/usr/bin/xcrun notarytool submit",
    '--keychain-profile "$notary_profile" --wait --output-format json',
    'if [ "$status" != "Accepted" ]',
    "/usr/bin/xcrun stapler staple",
    "/usr/bin/xcrun stapler validate",
    "/usr/sbin/spctl --assess --type execute --verbose=4",
    '/usr/bin/shasum -a 256 "$final_zip"',
]
for exact in required:
    assert exact in script, f"missing release requirement: {exact}"

assert "notarytool submit" in script and "altool" not in script
assert "--sign -" not in script

sign = script.index("/usr/bin/codesign --force --options runtime --timestamp")
submit = script.index("/usr/bin/xcrun notarytool submit")
staple = script.index("/usr/bin/xcrun stapler staple")
gatekeeper = script.index("/usr/sbin/spctl --assess --type execute --verbose=4")
final_archive = script.index('/usr/bin/ditto -c -k --keepParent "$app" "$final_zip"')
assert sign < submit < staple < gatekeeper < final_archive

print("release contract: developerID=true hardenedRuntime=true timestamp=true "
      "notarytool=true staple=true gatekeeper=true finalTicketIncluded=true")
