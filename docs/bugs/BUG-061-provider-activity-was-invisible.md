# BUG-061 — Provider activity was invisible when no plaintext reasoning arrived

## User-visible failure

Claude could visibly show `Working on it…` and several Codex tasks could be
running while Thoughtcrime remained on `Watching Claude and Codex…`. The user
could not tell whether monitoring was alive, which provider had changed, or
whether a reasoning record was currently being checked externally.

## Evidence and cause

The privacy audit showed fresh Codex activity, encrypted reasoning, tool calls,
and tool results. Those records were correctly excluded from the checker, but
the parser discarded most of them before presentation saw any activity.

The one existing operation-start path updated only the native panel title. The
borderless ticker draws its own header, so the visible header remained
`Thoughtcrime`. Claude's cloud tasks also publish exact lifecycle events through
the Desktop app's cached session SSE stream rather than local Claude Code JSONL,
which the monitor did not observe.

## Fix

Activity and content now have independent paths:

- every live local Claude/Codex record produces a content-free activity update;
- exact start and completion records maintain per-session active state;
- Claude Desktop cloud SSE `status`, `stream_event`, and `result` records drive
  the same state without reading or displaying their message content;
- the visible ticker header shows the active provider or `Claude + Codex` while
  useful ticker text remains unchanged;
- the existing orange lightbulb independently shows an outbound checker request.

Plaintext reasoning remains the only content displayed and sent to the checker.
Messages, summaries, tools, and encrypted records drive activity only.

## Verification

The black-box test now simulates a Claude cloud lifecycle plus two Claude and
two Codex local conversations. It asserts simultaneous provider activity,
per-provider completion, exact checker payload equality, visible checker-light
state, out-of-order results, and exclusion of encrypted/tool/summary content.

