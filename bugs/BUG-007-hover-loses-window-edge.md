# BUG-007: Hover expansion lost the chosen window edge

Status: fixed

## Observed behavior

When the collapsed HUD was placed at the bottom of the screen, hovering expanded
the settings/card view. After the pointer left and the HUD collapsed, it no longer
returned to the original bottom position; it floated higher on screen.

## Root cause

Two behaviors combined:

1. `resizePanel` unconditionally preserved `frame.maxY`, so every resize was
   anchored to the old top edge.
2. Tightening `minSize`/`maxSize` before the custom resize let AppKit mutate the
   frame immediately, losing the original inset before our geometry ran.

## Fix

- Infer whether the current frame is docked near the left, right, top, or bottom.
- Preserve the chosen edge and its inset while changing width or height.
- Preserve the center for a freely floating window.
- Keep this geometry in `WindowGeometry.swift`, independent of the HUD controller.
- Keep both current and target sizes legal during a mode transition; apply the
  final mode constraints only after the anchored resize completes.
- Reapply the captured placement after AppKit's content layout settles, using the
  actual final frame size rather than assuming the requested height was retained.

This also makes the left/right and top corner presets stable across hover cycles,
not only the reported bottom placement.

## Verification

`./thinkpeek --window-position-selftest` performs a complete collapsed → expanded
→ collapsed cycle from the bottom-right preset. Both the 12-point bottom inset and
12-point right inset remain unchanged. It also verifies that a floating window
keeps its center.

The live bottom-right API cycle reported:

```text
before:   x=1040 y=82 width=460 height=98
expanded: x=940  y=82 width=560 height=210
after:    x=1040 y=82 width=460 height=98
```
