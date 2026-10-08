# BUG-013 — Title bar wasted compact HUD height

## Symptom

The resting HUD used a full macOS utility-window title bar above two short content
rows. The traffic-light strip materially increased the total height without adding
useful compact-mode information.

## Root cause

The panel was created with titled, closable, and utility-window style masks even
though the exact session/source is already rendered inside the HUD.

## Fix

- Use a borderless, resizable, nonactivating panel for all presentation states.
- Retain the panel title internally for state reporting while removing visible
  system chrome.
- Apply a rounded continuous content mask and native window shadow.
- Reduce the resting frame from 460 × 98 to 460 × 70 points while preserving the
  16-point source row and 26-point ticker viewport.

## Verification

`./.build/doublethink --window-chrome-selftest` creates the production style mask and
asserts a zero-point difference between frame and content height. The live state
must report `windowChromeHeight: 0`, `windowHeight: 70`, and a fully-on-screen
460-point-wide ticker.
