# BUG-016 — Controls window could not stay at a narrower width

## Symptom

The explicit controls view always opened at 560 points, occupying more horizontal
space than necessary. Narrowing it was either constrained or lost on the next
presentation transition.

## Root cause

`compactWidth` was a hard-coded constant and was reused as both the target and
maximum width. The header also constrained the session picker and every control
to a single row, so it could not remain usable at a materially narrower width.

## Fix

- Move compact sizing and responsive header constraints into
  `CompactWindowLayout.swift`.
- Allow native horizontal resizing from 380 through 560 points.
- Remember the selected width and reuse it for controls and full-message views.
- Stack the session/status rows above the controls below 500 points.
- Add **Width: Narrow** (400 points) and **Width: Standard** (560 points) to the
  existing settings menu.
- Preserve the resting ticker's independent 460-point width.

## Verification

`./.build/thinkpeek --compact-width-selftest` verifies clamping and responsive layout
thresholds. Live `/controls` followed by `/width/narrow` must report width 400,
`compactHeaderStyle: stacked`, and a fully-on-screen window whose screenshot
shows every navigation/settings control. `/hide` must return to the unchanged
460 × 70 ticker, and reopening controls must restore the remembered 400 width.
