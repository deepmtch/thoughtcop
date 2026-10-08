# BUG-001: Fixed-width text clipped instead of wrapping

Status: fixed

## Observed behavior

Long reasoning text extended past the right edge of both the 460-point peek and
the 560-point compact card. The window width was correct, but AppKit rendered the
text using a stale/unbounded intrinsic width.

## Root cause

`NSTextField` measured the unwrapped attributed string before Auto Layout assigned
the final card width. Assigning an attributed string also introduced a paragraph
style without an explicit word-wrapping mode. The peek was separately hard-coded
to one truncated line.

## Fix

- Use `WrappingTextField`, whose intrinsic height is recomputed from its assigned
  width and whose intrinsic width cannot expand the container.
- Apply word wrapping to the attributed paragraph and text-field cell.
- Keep window widths unchanged: 460 peek, 560 compact, and 700 expanded.
- Allow the peek to grow vertically for at most three wrapped lines, capped at
  its existing 110-point maximum.

## Verification

`./.build/thoughtcrime --layout-selftest` lays out a real card at the fixed compact width.
The verified result was:

```text
wrapped: detailWidth=560 cardWidth=524 bodyWidth=496 bodyHeight=39
```

The body occupied multiple lines and remained inside the card insets.
