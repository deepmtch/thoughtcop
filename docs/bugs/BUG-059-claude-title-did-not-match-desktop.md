# BUG-059 — Claude title did not follow Claude Desktop

## User-visible failure

The ticker could label Claude reasoning with a transcript `custom-title` or
`ai-title` that differed from the conversation title Claude Desktop displayed.

## Cause

Thinkpeek read only title records embedded in `~/.claude/projects` transcripts.
Claude Desktop owns separate session metadata that maps each `cliSessionId` to
the current user-facing `title`, but Thinkpeek did not consult it.

## Fix

Claude source names now prefer the title from Claude Desktop's local
`claude-code-sessions` metadata for the matching full transcript UUID. Embedded
transcript titles remain a fallback when Desktop metadata is unavailable.

## Verification

The source-context regression test parses a mixed-case Claude `cliSessionId` and
verifies that its Desktop title is preserved. The isolated multi-session test
uses an empty temporary Desktop metadata root so it cannot accidentally depend
on the developer machine's session titles.
