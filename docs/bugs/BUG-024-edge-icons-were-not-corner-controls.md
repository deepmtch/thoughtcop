# BUG-024: Edge icons were not corner controls

## Symptom

The ticker showed four half-filled rectangle symbols. They represented left,
right, top, and bottom edge docking, but looked like four variations of the same
window. They did not communicate corner placement and only changed one axis.

## Root cause

The toolbar implemented edge movement even though the useful quick action is to
place the ticker in one of the four screen corners.

## Fix boundary

- Replace the half-window symbols with diagonal corner arrows.
- Expose Top Left, Top Right, Bottom Left, and Bottom Right in reading order.
- Move both window axes to the selected corner with a 12-point visible-frame inset.
- Replace `/edge/*` inspection actions with explicit `/corner/*` actions.
- Preserve tooltips and accessibility labels for every icon-only button.

## Verification

`./.build/thinkpeek --ticker-corner-selftest` verifies all four final origins, callback
order, and accessibility names. The running `/ui` surface reports the same four
corner controls.
