# BUG-059 — Claude title did not follow Claude Desktop

## User-visible failure

The ticker could label Claude reasoning with a transcript `custom-title` or
`ai-title` that differed from the conversation title Claude Desktop displayed.

## Cause

Thinkpeek read only title records embedded in `~/.claude/projects` transcripts.
Claude Desktop owns separate local Claude Code session metadata that maps each
`cliSessionId` to its local task `title`, but Thinkpeek did not consult it.

## Fix

Local Claude Code source names now prefer the title from Claude Desktop's local
`claude-code-sessions` metadata for the matching full transcript UUID. Embedded
transcript titles remain a fallback when Desktop metadata is unavailable.

Claude cloud sessions use `cse_...` identifiers and are not equivalent to these
local `cliSessionId` records. They must not be joined by title, text, or timestamp
heuristics. BUG-060 covers the stale-local-transcript case that made an unrelated
local title remain visible while other sessions ran.

## Verification

The source-context regression test parses a mixed-case Claude `cliSessionId` and
verifies that its Desktop title is preserved. The isolated multi-session test
uses an empty temporary Desktop metadata root so it cannot accidentally depend
on the developer machine's session titles.
