# BUG-002: Compact card jumped to its footer

Status: fixed

## Observed behavior

One compact-window state showed the card body clipped; another showed an empty
card with only the green drift-check footer. The text still existed, but the
viewport had moved to the bottom of the card.

## Root cause

`scrollToLatest` always scrolled to the bottom. When an asynchronous drift result
made the footer visible and changed the card height, compact mode retained that
bottom offset, hiding the header and useful body.

## Fix

- Compact carousel mode always anchors its single visible card at `scrollY = 0`.
- Expanded feed mode retains bottom-following behavior.
- Footer mutations invalidate layout and notify the HUD, which reanchors the
  currently selected compact card after the new height is known.
- Publish `scrollY` through the local UI API for regression evidence.

## Verification

An end-to-end AppKit test revealed a deterministic card after its footer changed.
The API reported `windowWidth: 560`, `visibleCardCount: 1`, and `scrollY: 0`; the
captured window began at the card header and displayed the wrapped body.
