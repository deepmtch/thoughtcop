# BUG-003: Position control opened a blank menu

Status: fixed

## Observed behavior

Opening the position control produced a tall, narrow, apparently empty menu.

## Root cause

Each menu item received a directional symbol and then had its title explicitly
set to an empty string. In the menu presentation used by AppKit, those images did
not provide a usable label, so six empty rows were displayed.

## Fix

Keep the existing `Top Left`, `Top Center`, `Top Right`, `Bottom Left`,
`Bottom Center`, and `Bottom Right` titles while retaining their symbols and
tooltips. No positioning behavior or window dimensions changed.

## Verification

All six `NSMenuItem` instances now retain non-empty titles. The selected toolbar
item may still use its compact symbol, while the opened menu has readable rows.
