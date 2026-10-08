# BUG-014 — Full-message reader ignored outside clicks

## Symptom

After opening the dedicated full-message reader, clicking elsewhere left the
reader open. The only dismissal path was the explicit **Done** button.

## Root cause

The borderless nonactivating panel only handled controls inside its own content.
It did not observe mouse-down events delivered elsewhere on the system.

## Fix

- Add a focused `OutsideClickMonitor` module covering local and global left,
  right, and other mouse-down events.
- Compare pointer locations in screen coordinates against the panel frame.
- Dismiss only when `messageMode` is active and the click is outside the panel.
- Route dismissal through the same `applyPeekMode(true)` transition as **Done**.
- Leave ticker and navigation/settings states unaffected.

## Verification

`./.build/thoughtcop --outside-click-selftest` verifies inside/outside boundaries and
ensures the rule is inactive outside message mode. The live check opens
`full-message`, posts a real click outside the panel, and verifies the running
state returns to `single-line-ticker` at 460 × 70 points.
