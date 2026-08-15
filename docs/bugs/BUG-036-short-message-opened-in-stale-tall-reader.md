# BUG-036: Short message opened in stale tall reader

## Symptom

Opening a one-line reasoning summary displayed the line at the top of a large,
mostly empty reader. Reopening other short messages made them appear empty even
though their text was present.

## Cause

The reader used one mutable `messageHeight` value for every message. It began at
300 points and retained the height of the last manually resized reader, without
considering the newly selected message's rendered content.

## Fix

Measure the attributed text with AppKit's text layout system at the current
reader width. Open the reader at the resulting content height, clamped to 150–520
points. Long content reaches the cap and scrolls; short content no longer inherits
a stale oversized canvas. Manual resizing still works while a reader is open.

This is layout measurement, not a character-count or sentence heuristic.

## Verification

The message-view self-test verifies that a rendered one-line summary selects the
150-point minimum and a long rendered message selects the 520-point scrolling
cap.
