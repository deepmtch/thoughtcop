# BUG-008: Hover controls felt unavailable

Status: fixed

## Observed behavior

Moving over the collapsed HUD appeared not to reveal the settings and navigation
buttons. The only pointer interaction on the collapsed surface was window dragging.

## Root cause

The hover implementation required the pointer to remain inside for 350 ms before
revealing. That intentional pause was too long for a small transient HUD and gave
no immediate feedback. A normal click also entered the drag path, with only a
double-click providing an alternate way to reveal controls.

An automated real-pointer reproduction confirmed that the old implementation did
eventually reveal after a one-second wait; the failure was interaction latency and
the absence of a dependable single-click fallback.

## Fix

- Reveal after 80 ms of hover, fast enough to feel immediate while avoiding most
  accidental flyovers.
- Collapse 350 ms after a genuine pointer exit, leaving time to cross into controls.
- Treat a click with less than two points of window movement as an activation that
  reveals controls.
- Preserve drag behavior when the window actually moves, plus double-click reveal.
- Publish `hoverRevealDelayMs` and `clickToReveal` in the local UI state.

## Verification

`./.build/thoughtcop --hover-ux-selftest` enforces the interaction thresholds. The live
test moves the real macOS pointer from outside to the center of the peek, waits
150 ms, and requires `peekMode` to become `false` with the 560-point settings view.
