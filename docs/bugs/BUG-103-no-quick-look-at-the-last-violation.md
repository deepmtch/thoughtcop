# BUG-103 — No quick look at the last violation from the menu bar

## Evidence

The user (2026-10-04) asked that hovering over the menu-bar icon show the last
violation's dialog, and approved the mockup: the alert bubble, titled "Last
violation", after a half-second rest on the icon ("ok").

## Root cause

The menu-bar icon had only a click (its menu). Seeing the last violation took
a menu click and then "Show Last Violation".

## Fix

- **Hover tracking.** A tracking area on the status-item button
  (`StatusItemHoverTracker`) and one on the bubble report the mouse entering
  and leaving.
- **Timing.** Resting on the icon for 0.5 s shows the newest stored violation
  in the bubble: "Last violation · <chat>", the quote, and "<time> · Click to
  open". The time is on the last line, so a long chat name cannot hide it.
  With none, the bubble shows "No violations yet.". It stays while the mouse
  is on the icon or the bubble, and hides 0.5 s after it leaves both.
- **Giving way.** Opening the menu hides it (`menuWillOpen`). A new
  violation's alert takes over (`violationBubbleMode` `alert` wins over
  `hover`).
- **Clicking** the bubble opens the violation (Show Last Violation), and the
  Hide-is-remembered rule of BUG-100 applies.
- **Tests.** Isolated runs ignore real hover; tests drive
  `/status-item/hover/on|off`.

## Verification

- **Screens:** `capture_screens.py` checks the hover bubble's exact title and
  hint, captures it (`08b-hover-last-violation`), checks that it hides after
  hover off, and checks the empty case ("No violations yet.").
- **Host run:** the full suite passes on the host, and the bubble screenshot
  was reviewed by eye.
- **Not tested:** a real mouse hover on the real menu bar. The test app
  ignores real input, so the user checks that.
