# BUG-022 — Ticker had no direct position controls

> Historical note: BUG-024 replaced these ambiguous edge controls with explicit
> four-corner controls.

## Symptom

Moving the resting ticker required opening controls, opening the settings menu,
and selecting one of six combined presets. The most common edge moves were not
available from the ticker itself.

## Fix

- Add an icon-only top-right toolbar for Left, Right, Top, and Bottom.
- Use window-placement SF Symbols with tooltips and explicit accessibility names.
- Move only the requested axis so horizontal moves retain height position and
  vertical moves retain horizontal position.
- Keep the settings icon after the four edge controls.
- Fix the four-button group to its 88-point intrinsic toolbar width so it cannot
  stretch and leave a gap before Settings.
- Fix the containing five-button toolbar to 114 points so the entire group stays
  together and flush-right instead of attaching arrows to the source title.
- Give the message row the full ticker width below the top-row toolbar.
- Preserve automatic foreground contrast for custom ticker backgrounds.

## Verification

`./thinkpeek --ticker-position-selftest` verifies all callbacks, accessibility
names, exact 12-point screen insets, and preservation of the orthogonal axis.
The installed `/edge/*` actions and `/screenshot` verify each real placement and
that toolbar icons do not overlap source or message text.

Recorded installed results on the 1512 × 982 display:

- Left moved to x=12 while retaining y=72.
- Top moved to y=866 while retaining x=12.
- Right moved to x=1040 while retaining y=866.
- Bottom moved to y=72 while retaining x=1040.
- All four states remained fully inside the macOS visible frame.
- The final screenshot shows one compact five-icon group flush-right, with the
  complete message row spanning underneath it.
