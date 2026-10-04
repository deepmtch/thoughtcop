# BUG-101 — The bubble opened only from its bottom strip

## Evidence

The user (2026-10-04): clicking the violation bubble's title or quote did
nothing; only a click near its bottom opened the violation.

## Root cause

The bubble's labels received the clicks themselves. Only the empty margin
belonged to the bubble view, whose `mouseDown` opens the violation.

## Fix

`ViolationBubbleView.hitTest` returns the bubble for any point inside it, so
the whole bubble acts as one button.

## Verification

- **Self-test:** `--violation-bubble-selftest` checks that clicks on the
  title, the quote, the hint and an empty corner all reach the bubble. With
  the old hit-testing it fails.
- **Host run:** the full suite passes on the host.
