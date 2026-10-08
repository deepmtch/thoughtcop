# BUG-020 — Escape left controls open

## Symptom

Escape closed the full-message reader only because its **Done** button owned an
Escape key equivalent. The controls/settings view did not share that behavior.
After **Show all**, the button changed to **Collapse**, which opened an unwanted
intermediate single-card controls view instead of returning to the ticker.

## Root cause

Keyboard dismissal belonged to one button rather than the floating window. The
history toggle also modeled compact controls as the reverse of full history, even
though ticker dismissal is the intended exit from either detail presentation.

## Fix

- Handle Escape and AppKit `cancelOperation` at the shared panel level.
- Make reader/controls/history presentations explicitly active and key while
  open; restore the previously active application when the non-activating ticker
  returns. This gives Escape a real event target without a global keyboard hook.
- Route both paths through `applyPeekMode(true)` for the message reader, controls,
  and full history.
- Keep **Show all** as a one-way expansion action and hide it in full history.
- Remove the obsolete **Collapse** action and intermediate transition.

## Verification

`./.build/thoughtcrime --escape-selftest` sends an Escape key equivalent and a responder-
chain cancel operation to the shared panel. It also verifies compact controls
offer **Show all** while full history exposes no reverse expansion button.
