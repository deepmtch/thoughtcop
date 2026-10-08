# BUG-021 — Borderless details had no visible exit

## Symptom

After **Show all** opened full history, the window had no visible way to leave it.
Removing the misleading **Collapse** action before adding its replacement made
Escape the only exit, creating a keyboard-only trap. Quit was also undiscoverable.

## Root cause

The borderless HUD omitted the lifecycle controls normally supplied by a macOS
title bar, but its custom header did not replace them.

## Fix

- Add an always-visible **Close** button to controls and full history. It returns
  directly to the one-line ticker.
- Add an always-visible **Quit** button to the reader, controls, and history, with
  Command-Q as its key equivalent.
- Put both actions in a reusable `DetailExitControls` component with tooltips and
  accessibility names.
- Keep Escape as a shortcut, never the sole exit.
- Expose `/close` and `/quit` through the local UI test surface.
- Keep compact controls header-only; message cards belong exclusively to the
  reader or full history, so the settings surface cannot clip message content.
- Explicitly reveal the history scroll view during **Show all**; hiding it for
  header-only controls must not leak into the expanded state.

## Verification

`./.build/thoughtcrime --exit-controls-selftest` checks labels, accessibility names, and
both callbacks. End-to-end UI checks verify `closeControlVisible` and
`quitControlVisible` in compact controls and full history, then `/close` must
restore a 460 × 70 ticker.

Recorded installed results:

- Narrow controls: 400 × 106, zero cards, Close/Quit visible.
- Standard controls: 560 × 74, zero cards, Close/Quit visible.
- Full history: 700 × 620, cards rendered, Close/Quit visible.
- Full-message reader: Done/Quit visible and content kept separate.
- Close: restored the 460 × 70 ticker directly.
- Quit: terminated the real process; restart returned cleanly to ticker mode.
