# BUG-006: Collapsed summary omitted its source session

Status: fixed

## Observed behavior

Expanded cards showed `Claude/Codex · session name` in their header, but the
collapsed peek showed only the reasoning text. In auto mode, the session picker
correctly said `Auto — all active sessions`, so the collapsed message itself did
not identify which monitored session produced it.

## Root cause

The compact history stored only each event's rendered body in `eventPreviews`.
The source string was passed to `EventCard` for its expanded header and then
discarded from the collapsed presentation path.

## Fix

- Store `(source, body)` together for every navigable summary.
- Give the collapsed peek a dedicated source label above its message.
- Publish `peekSource` separately from `peekText` through the local UI API.
- Preserve the fixed 460-point width; permit enough vertical space for one source
  line and up to three wrapped message lines.

`Auto — all active sessions` remains the monitoring-mode label. It no longer has
to double as message context because the actual source is attached to the message.

## Verification

`./.build/thinkpeek --source-context-selftest` verifies that a preview retains the exact
source/message pair. Live verification additionally requires `peekSource` to match
the source of the currently selected card while `peekText` matches its message.
