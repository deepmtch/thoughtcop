# BUG-079: Violation status icon lost native foreground

## Symptom

With unreviewed violations, the Thinkpeek shield and `9+` count rendered black
instead of using the normal high-contrast menu-bar foreground. The status-item
background must not change when a violation is recorded.

## Evidence

The supplied screenshot showed the black shield and count against the blue
macOS menu bar. `git log -S` identified commit `dca3658` as the regression: it
added `contentTintColor = .systemRed` on 2026-09-03. The implementation before
that commit left the native status-item foreground untouched.

## Root cause

Thinkpeek applied a custom semantic tint to `NSStatusBarButton`. AppKit flattened
that custom-tinted status content to black in the user's menu-bar environment.

## Fix

Use an explicit white, non-template symbol and white attributed count while an
unreviewed violation exists. Restore native adaptive rendering after the alert
is reviewed. Do not set any status-item background. A focused AppKit self-test
verifies the white symbol and count, native restoration, and that the helper
does not enable a custom layer/background. The `/ui` diagnostic state exposes
`statusItemForegroundMode` and `statusItemImageIsTemplate` so the rendered
policy is testable without UI clicking.
