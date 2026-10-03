# BUG-092 — Hidden reader tabs cut off the ticker

## Evidence

User screenshot (2026-10-03): the ticker header "Claude · guidelet new sarch"
sat against the top edge, cut off, with a large gap above "Working…". The
running app reported `windowHeight` 70 while its own `/screenshot` was
164 px (82 pt) tall: the content was laid out 12 points taller than the window.

## Root cause

After the reader with session tabs closed, its tab and status rows stayed
active while hidden and required about 82 points, more than the 70-point
ticker. Depending on the window's size limits the content overflowed above the
window (user's Mac) or the ticker grew to 82 points (guest).

## Fix

Leaving message mode clears the reader's sessions, which hides the tab and
status rows and returns the text area to the header.

## Verification

- `Scripts/capture_screens.py` adds the user's sequence (ticker right after
  closing a reader with tabs) and asserts every ticker is 70 points and every
  non-editor capture's content height equals its window height.
- With the fix removed it fails: "07b-ticker-after-reader: ticker is 82 pt
  tall, not 70". With the fix the full suite passes in the Parallels guest.
- The reader-tabs test now waits for the "(1 new)" count instead of sleeping
  a fixed second (it failed once under guest load).
