# BUG-065: Claude Desktop thinking was not captured

Status: Fixed

## User-visible failure

Claude Desktop displayed a long plaintext thinking block while Doublethink stayed
on `Watching Claude and Codex…` or showed an unrelated Claude Code session. The
ticker therefore omitted the exact reasoning the user could see in Claude.

## Evidence and root cause

The local Claude Code JSONL transcript for the reported session contained no
`thinking` records. The cloud-session SSE cache contained lifecycle events, but
its `thinking_delta` payloads had empty text.

The exact reported text was instead found in Claude Desktop's Chromium cache in
a zstd-compressed response for:

`/api/organizations/<id>/chat_conversations/<id>?tree=True`

The decoded JSON has a conversation `name`, `chat_messages`, and structured
assistant content entries. The reported 3,811-character text was present under
`content[].type == "thinking"` in the conversation named
`AI grounding levels: from ungrounded to deep web access`.

Doublethink did not read this data source at all. It was therefore impossible for
the ticker to show that Desktop thinking, regardless of polling frequency.

## Fix boundary

- Monitor changed Claude Desktop conversation-cache responses off the main
  thread.
- Decode their zstd response frame and parse the documented structure directly.
- Emit only non-empty assistant content whose exact structured type is
  `thinking`.
- Use the conversation's exact `name` as the ticker source title.
- Send that plaintext thinking verbatim through the existing checker boundary.
- Do not emit user/assistant messages, tools, tool results, summaries, or
  empty/encrypted-only records.
- On startup, show the configured number of readable Desktop thinking records
  as local history, then build an exact content-identifier baseline so cached
  records are not re-emitted as new activity.

No keyword, OCR, title, timestamp, or semantic heuristic is used to decide what
counts as reasoning.

## Verification

`--claude-desktop-conversation-selftest` verifies exact multiline preservation,
 the exact title, exclusions, startup history, and one-time live delivery.

`--inspect-claude-desktop-cache` was run against the cache file from the report.
It recovered seven structured thinking records under the correct title,
including the reported 3,811-character record.

The black-box suite also writes a new compressed Claude Desktop response while
Claude Code and Codex sessions are interleaved. It verifies the exact Desktop
title/text reaches the ticker and dummy checker while adjacent message, summary,
and tool fields do not.
