# BUG-099 — Clicking the ticker opened the reader and closed it at once

## Evidence

The user (2026-10-04): clicking "2 active" on the ticker showed the reader
for a moment, then the ticker came back. The live command log
(`~/Library/Logs/Thoughtcrime/ui-api.jsonl`) showed every click as an `appKit`
"message" command followed by "close" in the same second.

## Root cause

The outside-click monitor took each click's location but decided only later,
on the next main-queue turn. By then the click had already opened the reader.
The reader is 380 points wide and keeps the ticker's right edge, while the
ticker is 560 points. A click on the left part of the ticker, where "2 active"
is, therefore lay outside the new reader frame, and the reader closed.

## Fix

`OutsideClickMonitor.handleClick(at:)` evaluates `shouldDismiss`
synchronously, against the window as it is at the moment of the click. Only
the resulting close is queued.

## Verification

- **Self-test:** `--outside-click-selftest` simulates the exact case: a click
  on the left part of a 560-point ticker, which opens a 380-point reader.
  The reader must stay open, and a later real outside click must still close
  it.
- **Host run:** the full suite passes on the host.
