# BUG-045: Ticker background used a hand cursor

## Symptom

Hovering anywhere over the compact ticker changed the pointer into an open hand.
The entire floating panel therefore looked like a web link or a permanently
grabbed object.

## Cause

`CompactInteractionView` installed an `.openHand` cursor rectangle over its full
bounds and temporarily pushed `.closedHand` during every drag.

## Fix

The ticker background now uses the standard macOS arrow while preserving its
single-click, double-click, and window-drag behavior. Visible controls retain
their normal native interaction behavior.

## Verification

`--interaction-selftest` instantiates the real compact interaction view in ticker
mode and asserts that its background cursor is `NSCursor.arrow`.
