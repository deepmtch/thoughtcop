# BUG-011 — Hover conflated reading a message with opening controls

## Symptom

Moving the pointer across the ticker resized the window and opened navigation,
even when the user only wanted to read the current summary. A click, hover, and
double-click all led to nearly the same mixed card-and-controls interface.

## Root cause

The compact window had only two presentation states: ticker and detail. That
forced passive pointer movement, full-message reading, history navigation, and
settings into one transition.

## Fix

- Hover no longer changes presentation or window size.
- A single click opens a dedicated `FullMessageView` containing the exact source,
  rendered full text, **Controls…**, and **Done**.
- **Done** closes the reader and resumes the ticker.
- The visible controls button or a deliberate double-click opens the separate
  navigation/settings state.
- A short click-decision interval distinguishes a single click from the first
  half of a double-click; dragging remains independent.
- The state API publishes `singleClickOpensMessage`,
  `doubleClickOpensControls`, and `hoverDisclosure: false`.

## Verification

`./.build/thinkpeek --interaction-selftest` checks the click decision and drag boundary.
Live `/message`, `/controls`, and `/hide` checks verify three distinct states:
`full-message`, `compact-controls`, and `single-line-ticker`. Screenshots confirm
the full-message reader renders Markdown and contains no history navigation.
