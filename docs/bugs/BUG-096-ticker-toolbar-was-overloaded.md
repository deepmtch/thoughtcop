# BUG-096 — The ticker toolbar was overloaded and unclear

## Evidence

The user's screenshot (2026-10-04) showed eight icons on the ticker toolbar:

- four corner arrows;
- 💬, which opened Edit Rules but looks like "message";
- ⚙;
- ▭, with the tooltip "Open message navigation";
- ✕.

The user asked "what about this", approved a mockup with three icons
(History, Settings, Hide), and said "do it".

## Root cause

Each feature added its own button to the always-visible ticker. Window
placement, rules editing and a separate navigation view all competed with the
ticker's one job: showing the current thought.

## Fix

- **Three actions.** `TickerPrimaryActions` now has History
  (`clock.arrow.circlepath`, opens history), Settings and Hide. Clicking the
  text still opens the reader. The reader's ▭ button is now the same History
  button.
- **Removed.** The four corner arrows (`TickerCornerControls`), 💬, ▭, and the
  compact navigation view's `/controls` command are gone.
- **Where the removed functions live now.**

  | Removed | Now |
  |---|---|
  | Window position | Settings › General › Position (6 positions), and dragging |
  | Rules | Settings › Rules |
  | Session picker | The History header |
  | Previous / next | The reader (arrow keys) |

## Verification

- **Self-test:** `--ticker-actions-selftest` checks the three actions and that
  each calls its handler.
- **Black box:** the e2e checks that `/controls` returns 404.
- **Screens:** `capture_screens.py` asserts the toolbar's three actions. The
  full suite passes in the Parallels guest, and every screen was reviewed by
  eye.

The compact-controls view is no longer reachable from the UI or the API, but
its drawing code in `HUD.swift` remains. It is left for a separate cleanup, so
this change stays within what the user approved.

## Follow-up: the three icons floated mid-ticker

The user's screenshot showed History, Settings and Hide in the middle of the
ticker, with a wide empty gap to the right of ✕. VM screen 01 showed the same
gap, and it was missed in review. The cause was the toolbar's fixed 214 pt
width, sized for the old eight icons. The toolbar is now sized by its buttons.
`/ui` reports `tickerToolbarTrailingGap`, and `capture_screens.py` asserts it
is at most 12 pt on every ticker screen.
