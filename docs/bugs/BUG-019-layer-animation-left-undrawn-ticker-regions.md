# BUG-019 — Layer animation left ticker text regions undrawn

## Symptom

The source/session row stayed visible while the message row became completely
blank for several seconds. The text later reappeared in the middle of a sentence.
Clicking the ticker during the blank interval opened the full-message reader with
the complete message.

## Evidence and root cause

This was not an empty transcript event. The full-message reader and ticker are
fed by the same `eventPreviews[compactIndex].text`, and `TickerView.text` rejects
empty normalized strings. Screenshots showed the same populated message disappear
during movement and reappear later at a suffix.

The ticker moved the layer of a clipped, layer-backed `NSTextField` using a Core
Animation transform. AppKit rasterized the initially visible portion of that
field, but a presentation-layer-only transform did not reliably request drawing
for glyph regions that began outside the viewport. The geometric visibility
check added for BUG-018 therefore reported text inside the viewport even when its
backing content had not been drawn.

## Fix

- Remove the moving `NSTextField` entirely.
- Replace the layer-only keyframe transform with a main-run-loop ticker timer.
- Draw the attributed string directly at the current offset inside the small
  clipped ticker viewport on every frame, so no offscreen glyph raster is reused.
- Preserve the existing start pause, configured movement speed, end pause, fast
  return, Reduce Motion behavior, and explicit reset action.
- Report the actual drawing offset in presentation diagnostics.

An intermediate attempt moved the `NSTextField` through its AppKit frame and
invalidated it on every tick. A live screenshot still reproduced the blank row,
so that approach was rejected before commit; direct viewport drawing is the final
implementation.

## Verification

Build and run every existing self-test. Exercise long text through full cycles
and rapid long/short/open/close transitions. Image-based sampling must verify
that visible ink remains in the message row during movement; geometry alone is
not accepted as proof for this defect.

Recorded result: the final isolated renderer produced 201/201 ink-bearing frames
over a complete cycle and 53/53 ink-bearing frames during rapid replacements and
reopens. The installed app then produced 80/80 consecutive live screenshots with
message-row ink while actively scrolling; the minimum grayscale deviation was
0.135367 versus the 0.02
blank-frame threshold.
