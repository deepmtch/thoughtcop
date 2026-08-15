# BUG-037: Detail header looked like a debug toolbar

## Symptom

The controls view devoted two dense rows to a full-width session picker, a
truncated checker implementation status, navigation, restart, settings, history,
Close, and Quit. Every action had nearly equal visual weight.

## Cause

The responsive header treated checker diagnostics as permanent primary UI and
used text buttons for lifecycle and view commands. Even the standard 560-point
width used a 74-point two-band composition.

## Fix

- Use one 52-point toolbar row at standard width.
- Keep a two-row, 88-point fallback only for the explicit narrow width.
- Remove the truncated checker status from the visual toolbar; retain its exact
  value in the local UI state and on the session picker's help tooltip.
- Use standard SF Symbols for previous, next, restart, history, return-to-ticker,
  and quit, with complete tooltips and accessibility labels.
- Keep the required return and quit functions visible without promoting them as
  large primary text actions.

## Verification

Responsive-layout tests assert the compact heights at narrow and standard widths.
Exit-control tests assert visible symbol controls, semantic accessibility names,
and working close/quit callbacks.
