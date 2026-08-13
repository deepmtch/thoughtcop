# BUG-030 — Controls and history ignored outside clicks

## Symptom

Clicking outside the controls or full-history window left it open. The visible
**Close** button returned to the one-line ticker, but the same outside click only
worked for the full-message reader.

## Root cause

The shared global/local mouse monitor was gated specifically on `messageMode`.
Controls and history both have `messageMode == false`, so their outside clicks
were deliberately rejected before reaching the dismissal action.

## Fix

- Define the outside-click boundary as any detail state (`peekMode == false`).
- Route the outside-click handler through `dismissDetailsToTicker()`, exactly the
  same action used by **Close** and Escape.
- Route the full-message **Done** action through that same method as well.
- Ignore clicks within the panel and all clicks while the ticker is already the
  active view.

## Verification

- `--outside-click-selftest` covers message, controls, and history eligibility,
  the inside-panel boundary, and the inactive ticker state.
- The full regression suite must pass.
- Live verification opens controls, clicks outside the panel, and confirms the
  `/ui` state returns to `single-line-ticker` at the compact ticker height.
