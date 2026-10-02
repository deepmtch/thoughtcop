# BUG-085 — Test fixtures did not match real transcript structure

## Evidence

The isolated suite (`Scripts/test_multi_session_e2e.py`) proved the outbound
checker boundary with hand-written records. Compared with this Mac's real
transcripts on 2026-10-02:

- Real Claude Code transcripts contain 17 record types (`user`, `attachment`,
  `file-history-snapshot`, `system`, …) and assistant blocks such as
  `tool_use`, `server_tool_use` and `advisor_tool_result`. The fixtures had
  none of the user, attachment, metadata or Claude tool records.
- Real Codex rollouts contain `user` and `developer` messages, `session_meta`,
  `turn_context`, `world_state` and reasoning records whose `content` is empty
  and whose `summary` is empty, with only `encrypted_content`. The fixtures had
  no user/developer messages; their raw `reasoning_text` record was not present
  in any real rollout on this Mac.
- The real Claude Desktop cache contained `chat_conversations_v2` and
  `/v1/code/sessions/watch` entries. The app's recognizers look for
  `chat_conversations/<uuid>?tree=True` and
  `/v1/code/sessions/cse_…/events/stream`; neither shape existed. Whether
  Desktop chat was simply unused or Claude Desktop changed these URLs is open.

So the suite could not show that user messages, Claude tool records, metadata
and system instructions in real files stay out of checker requests.

## Root cause

Fixtures were authored from the parser's expectations rather than captured
from production records, contrary to the existing lesson "Mock fixtures passed
while the real provider still disagreed".

## Fix

- `Scripts/real_structure.py` produces canary copies of real transcripts: every
  record, key, nesting level, array length, number, boolean and null is kept;
  each non-empty string becomes a unique `CANARY_nnnnnn` unless its JSON path is
  one the parser compares (`KEEP_PATHS`, each traced to a source line).
  Timestamps and the Codex `session_meta` id become format-valid synthetic
  values. `--write-fixture` keeps the first real record of every distinct
  record signature.
- `Tests/Fixtures/real-structure/` holds that canary fixture (43 Claude and 16
  Codex records). It contains no real string values.
- `Scripts/test_real_structure_e2e.py` runs the built app against the fixture
  with a loopback dummy checker, maps every canary in every request body back to
  its JSON path and requires the sent set to equal the documented allowlist
  exactly. `--audit-real` runs the same proof on canary copies of the real
  transcripts in a temporary directory.

## Verification

- Fixture: 7 canaries sent, all at allowlisted paths; 1,347 withheld.
- `--audit-real --claude-files 5` (5 most recent real Claude Code sessions plus
  both real Codex rollouts): 1,622 sent, 489,553 withheld, no value outside the
  allowlist sent and no allowlisted value missed.
- `./Scripts/test.sh` runs the fixture test.

## Not covered

- Claude Desktop conversation-cache and cloud-stream readers still use
  hand-written records; see Evidence for the open URL-shape question.
- Canaries are short, so the 32 KB outbound envelope limit is never reached. On
  real data an oversized reply is withheld; the audit counts it as sent. The
  real app therefore sends at most what the audit reports.
- The `shown`/`title` report columns read `/ui` events, which keep only the
  last 250 events, and are not asserted. In the fixture run the source label
  stayed "Claude · untitled" although the fixture has `customTitle`/`aiTitle`
  records; title canaries were never sent. Whether that label is a display bug
  is unresolved.
