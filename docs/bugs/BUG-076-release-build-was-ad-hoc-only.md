# BUG-076: Release build was ad-hoc signed only

Status: Blocked on Apple credentials

## Reproduction evidence

The bundle installed in the clean Parallels guest passed structural signature
verification but `spctl --assess` returned `rejected-development-build`.
Locally, `security find-identity -v -p codesigning` reports zero valid identities,
and the `doublethink` notarization keychain profile is absent.

## Root cause

`build.sh` always signs with `codesign --sign -`, which is correct for a local
development bundle but cannot establish a Developer ID identity or notarization
ticket for direct distribution. No separate release pipeline existed.

## Fix boundary

`Scripts/release.sh` now provides a separate fail-closed distribution path. It
requires an exact Developer ID Application identity and explicit `notarytool`
keychain profile before building. It enables hardened runtime and a secure
timestamp, submits with `notarytool`, requires Apple's `Accepted` status,
staples and validates the ticket, runs Gatekeeper assessment, and recreates the
final ZIP after stapling so the distributed app contains the ticket.

The script contains no Apple credentials. Producing the first release remains
blocked until the user installs a Developer ID Application certificate and
stores a valid notarization profile in Keychain.

## Verification

The release contract test verifies every required stage and its order, rejects
`altool` and ad-hoc release signing, and is part of `Scripts/test.sh`. The final
external verification must run the release script with real credentials and
assess the resulting artifact in the clean Parallels guest.
