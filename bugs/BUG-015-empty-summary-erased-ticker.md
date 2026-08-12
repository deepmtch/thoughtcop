# BUG-015 — Empty normalized summary erased the ticker

## Symptom

The resting HUD occasionally showed the source session and settings button but
no summary text.

## Reproduction and root cause

The parser normally rejects literal whitespace-only reasoning, but the final
presentation boundary accepted any string. In isolation, assigning a valid
summary followed by formatting-only input produced:

```text
afterFormattingOnly=""
```

`TickerView.text` normalized the second value to an empty string and replaced the
previous label. There was no invariant requiring navigable analysis to remain
non-empty after presentation normalization.

## Fix

- Define `presentableTickerText` as the shared non-empty normalization boundary.
- Discard readable analysis that becomes empty before it clears pending state,
  enters API history, creates a card, or reaches drift analysis.
- Defensively refuse empty assignments inside `TickerView`, preserving the last
  visible summary even if a future caller bypasses ingestion.
- Publish `discardedEmptySummaryCount` for runtime evidence.

## Verification

The isolated long/short/empty harness must now retain `"Visible summary"` after a
formatting-only assignment. `./thinkpeek --ticker-selftest` asserts the same
production behavior. The live HUD must expose a non-empty `peekText` while in
`single-line-ticker` mode; discarded inputs increment the counter without adding
a navigable card.
