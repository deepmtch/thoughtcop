# BUG-078 — Disabled violation status duplicated the menu action

## User-visible failure

The status menu showed a gray disabled row such as
`Violations · 13 new · 13 recorded` directly above
`Open Violation History…`. The duplicate hierarchy looked unavailable and made
the user scan two rows to find one action.

## Evidence and root cause

The supplied menu screenshot showed both rows. `installStatusMenu()` created a
separate actionless `NSMenuItem`, while `updateViolationMenu()` wrote counts to
that disabled item and left the actionable title unchanged.

The black strip above the menu is the macOS menu bar, not a Doublethink-owned
surface. A live `/screenshot` of the actual Doublethink ticker measured a white
background with dark foreground (`tickerBackgroundRGBA: [1, 1, 1, 1]`).

## Fix and verification

The disabled duplicate row is removed. The single action now reports its state
as `Open Violation History…`, `Open Violation History (N New)…`,
`Open Violation History (N Reviewed)…`, or
`Open Violation History (Unavailable)…`. The status-item shield and count remain
the glanceable menu-bar indicator.

The violation-store self-test covers all four exact titles. Final verification
ran the full suite successfully. The rebuilt live app exposed exactly four
non-separator menu items through `/ui`: `Show Doublethink`,
`Open Violation History (15 New)…`, `Edit Check Prompt…`, and
`Quit Doublethink`. Its rendered ticker remained white
(`tickerBackgroundRGBA: [1, 1, 1, 1]`) with dark foreground and was fully
on-screen.
