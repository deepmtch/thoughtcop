# BUG-012 — Ticker reading speed was not configurable

## Symptom

The ticker always travelled at 34 points per second. Users with different reading
speeds had no way to slow it down or make long summaries pass more quickly.

## Root cause

Movement speed was a compile-time constant rather than presentation state.

## Fix

- Add Slow (22 pt/s), Normal (34 pt/s), and Fast (52 pt/s) presets.
- Expose them in the explicit controls view's combined ticker/window settings
  menu, avoiding an extra button that crowds the header.
- Persist the selected preset with user defaults.
- Restart the current ticker animation immediately when speed changes.
- Publish both the preset and effective points per second in the local state API.

## Verification

The ticker self-test asserts ordered, distinct preset rates. Live calls to
`/speed/slow`, `/speed/normal`, and `/speed/fast` verify that the running renderer
changes `tickerSpeed` and `tickerPointsPerSecond` without leaving ticker mode.
