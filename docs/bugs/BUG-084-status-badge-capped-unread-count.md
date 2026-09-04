# BUG-084 — Status badge capped the unread count

## Evidence

With 27 unread violations, the menu-bar status item displayed `9+` while its
menu displayed `Open Violation History (27 New)…`.

## Root cause

Both surfaces used the same `newCount`, but the status-item title independently
replaced every value above nine with the hard-coded string `9+`. The menu kept
the exact value.

## Fix

The status item now formats the exact unread count through
`violationStatusBadgeTitle(unreviewed:)`. Zero still omits the badge text.

## Verification

The violation-store self-test requires exact status titles for 0, 9, 10, and 27
unread records. The complete suite and a live rendered menu-bar screenshot must
pass before completion.
