# BUG-097 — The ticker was two rows tall, below a gap

## Evidence

The user's screenshot (2026-10-04) showed the ticker 70 points tall: the chat
name on one row and "Working…" on a second row, with an empty gap between it
and the menu bar. The user asked for it at the very top and one line high. The
user approved the mockup ("yes", "agree").

## Root cause

- The resting ticker used a 70-point, two-row layout.
- Top positions and top-docked resizes kept a 12-point inset from the menu
  bar.

## Fix

- **One row.** The ticker is now 28 points: provider icon, chat name (at most
  a third of the row; the provider is shown by the icon), "·", the scrolling
  text, the checker light, then History, Settings and Hide.
- **Flush to the menu bar.** Top presets, top corners, and windows docked
  near the top all touch the menu bar (`WindowPlacement`,
  `movedWindowFrame`). Bottom, left and right positions keep their inset.
- **Square top corners.** At the top, only the bottom corners are rounded.
- **Hidden reader detached.** The hidden reader's bottom constraint is active
  only while the reader shows. Its minimum height of about 39 points was
  holding the window taller than 28 (lesson BUG-092).

## Found while verifying

The user asked to run tests on the host again, because the Parallels guest is
shared with another session. On the host, the isolated test app read the
user's real rules (`com.thoughtcrime.app`: two rules, one per line). So each
record was checked twice, and the multi-session test failed. The same failure
happens at f6046d9, before today's changes.

- **Rules.** Isolated mode now reads its rules from `com.thoughtcrime.app.e2e`.
  Every e2e script sets the rules it needs (`Scripts/e2e_defaults.py`).
- **Usage.** Isolated mode writes usage to a temporary file unless a path is
  given, so tests never touch the user's real usage and cost.

The user's real settings (`com.thoughtcrime.desktop`) and rules were checked
before and after the runs and are unchanged.

## Verification

- **Self-tests:** `--window-position-selftest` checks that a top-docked
  window stays flush while it grows and shrinks. `--ticker-corner-selftest`
  checks that the top corners have no inset.
- **Screens:** `capture_screens.py` asserts:
  - every ticker screen is 28 points tall;
  - the content fills exactly that height;
  - a top position touches the menu bar with square top corners;
  - the chat name is shown without the provider.
- **Host run:** the full suite passes on the host, and every screen was
  reviewed by eye.
