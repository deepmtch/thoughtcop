# BUG-098 — The ticker background turned red on a violation

## Evidence

The user's screenshot (2026-10-04) showed the ticker with a red background
reading "…tion: The AI is using a workaround (re-trigger…", which then switched
back to the normal background. The user: "The background … should never
change. It is only the icon itself".

## Root cause

A check finishes about a second after a message appears. When the message on
the ticker was judged a violation, the ticker repainted it in violation style:
`TickerAppearance.background(alarmActive:)` returned the violation color. The
red background stayed until the next message replaced that one.

## Fix

`TickerAppearance.background` always returns the semantic window surface. The
violation color now colors only the menu-bar flash (BUG-094). The ticker may
still show a violation's text, but its background never changes.

## Verification

- **Self-test:** `--ticker-background-selftest` checks that a violation, with
  either a custom or the default color, gives the same background as normal.
- **Black box:** the multi-session e2e shows a violation in the ticker and
  asserts the same background color and `normal-semantic` mode as the item
  before it.
- **Host run:** the full suite passes on the host.
