# BUG-079: Violation status icon lost native foreground

## Symptom

With unreviewed violations, ThoughtCop overrode the menu bar's native foreground.
That made the shield/count capable of disagreeing with every neighboring icon.
A later forced-white attempt made the mismatch explicit: the shield was white
while the count and every neighboring item were black. The status-item
background must not change when a violation is recorded.

## Evidence

`git log -S` identified commit `dca3658` as the regression: it added
`contentTintColor = .systemRed` on 2026-09-03. The implementation before that
commit left the native status-item foreground untouched. The final supplied
screenshot showed why another fixed color is also wrong: AppKit selected black
for all neighboring items while the forced ThoughtCop shield remained white.

## Root cause

ThoughtCop applied a custom semantic tint to `NSStatusBarButton` instead of
letting the status bar choose one foreground consistently for the current
wallpaper/menu-bar appearance.

## Fix

Restore the pre-regression policy explicitly: clear `contentTintColor` after
updating violation state so AppKit supplies the native adaptive foreground. Do
not set any status-item background. A focused AppKit self-test first applies a
custom tint and verifies that the production helper clears it.
The `/ui` diagnostic state exposes `statusItemUsesNativeForeground` so the
foreground policy is testable without UI clicking.
