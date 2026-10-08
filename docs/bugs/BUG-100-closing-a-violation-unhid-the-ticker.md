# BUG-100 — Closing a violation un-hid the ticker

## Evidence

The user (2026-10-04) had hidden the ticker. They clicked a violation bubble,
read the violation, and closed the reader. Doublethink then showed the ticker
again instead of staying hidden. The user: "when I have closed it once, it
must remember this".

## Root cause

Opening a violation from the bubble, Show Last Violation or Open Violation
History cleared `hiddenByUser`. Closing the reader then went to the ticker,
like any detail view, so the earlier Hide was lost.

## Fix

- **Remember the Hide.** Opening a violation while Doublethink is hidden sets
  `returnToHiddenOnClose`. Closing the reader or history (Done, Escape or an
  outside click) then hides Doublethink again.
- **Undo for good.** Menu bar › Show Doublethink, or a new Hide, clears that
  state. `/ui` reports `returnsToHiddenOnClose`.

## Verification

- **Black box:** the multi-session e2e checks three cases:
  - Show Last Violation while hidden, then close: hidden again;
  - bubble click while hidden, then close: hidden again;
  - after Show Doublethink, opening and closing Violations keeps the ticker
    visible.
- **Host run:** the full suite passes on the host.

## Also: Hide now survives restarts

`hiddenByUser` was in memory only, so every restart (each commit restarts the
app) showed the ticker again. `HiddenPreference` (`tickerHidden`) saves Hide,
and launch keeps a hidden Doublethink hidden. Show Doublethink clears it.
Isolated tests neither read nor write it. `--settings-window-selftest`
checks that it is off by default and remembered when set.
