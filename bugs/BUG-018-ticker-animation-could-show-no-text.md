# BUG-018 — Ticker animation could show no message text

## Symptom

The source/session row remained visible while the ticker row was entirely blank.
At other times, the message first appeared in the middle of a word. Opening the
full-message reader proved the complete source text still existed.

## Root cause

The Core Animation keyframes used `label.frame.width` and were installed directly
during text, layout, and visibility transitions. A presentation layer could
briefly retain geometry from the prior message while a new animation was being
installed. The state API only reported the model string, so it could claim
`peekText` was populated while no glyph intersected the clipped viewport.

## Fix

- Measure the actual attributed glyph width rather than using a potentially stale
  label frame as animation distance.
- Synchronously remove every prior animation and reset the model transform to
  identity before changing text or presentation state.
- Defer installation one main-loop turn so current layout geometry is settled.
- Use an animation generation token so deferred work from an older message cannot
  attach to the current label.
- Publish translation, measured text width, visible text width, and
  `tickerTextVisible` from the presentation layer. Each `/ui` request refreshes
  this snapshot on the main thread rather than returning stale animation metrics.

## Verification

The isolated harness samples an uninterrupted cycle and rapid long/short/reopen
transitions using glyph bounds. No sample may have less than one visible point.
`./thinkpeek --ticker-selftest` verifies that both animation endpoints show a full
viewport of text. The live UI is sampled repeatedly for at least one complete
long-message cycle; every ticker-mode response must report
`tickerTextVisible: true` and `tickerVisibleTextWidth >= 1`.

Recorded result: 96 rapid transitions produced zero blank samples. The live full
cycle produced 240/240 visible samples, zero blanks, and a minimum visible width
of 400 points while overflow animation was active.

## Follow-up

Those checks validated geometry, not whether AppKit had rasterized every glyph.
BUG-019 records the separate rendering defect discovered by inspecting real
screenshots throughout the animation.
