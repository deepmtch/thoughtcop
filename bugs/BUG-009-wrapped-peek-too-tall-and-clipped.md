# BUG-009: Wrapped resting summary was too tall and clipped

Status: fixed

## Observed behavior

The resting HUD wrapped a long summary across as many as three lines. It occupied
too much screen space, and in some frames the source/first text line was pushed
under the title-bar boundary and appeared cut off.

## Root cause

The collapsed presentation reused a multiline intrinsic-height text field inside
a small utility window. AppKit could enforce a different final frame height after
layout, while the stack still expected space for a source line plus three body
lines. This was the wrong information density for an ambient HUD regardless of
the clipping defect.

## Established interaction used

The resting view now follows the conventional ticker pattern:

- one clipped line rather than a multiline block;
- a pause at the beginning before movement;
- constant-speed horizontal travel only when the text overflows;
- a pause at the end and quick return to the beginning;
- full content available in a dedicated single-click reader;
- a **↤** control in the revealed header to return immediately to the start;
- no repetitive animation when macOS Reduce Motion is enabled.

Inline Markdown is parsed before the ticker's plain-text normalization, so syntax
markers such as `**` and backticks are not exposed in the compact UI.

Core Animation keyframes provide the pauses and travel without a continuously
firing timer. The source session remains in its own fixed-height row above the
ticker, so neither line can intrude into the title bar.

## Verification

`./thinkpeek --ticker-selftest` verifies that multiline input is normalized to one
line, overflowing content is detected, and the label remains vertically inside
its 26-point viewport. Live verification checks a fixed 460 × 98-point resting
window, `uiStyle: single-line-ticker`, and the **↤** return-to-start path. The
later interaction split is recorded in BUG-011.
