# BUG-038: Automatic checker read tool records

## Severity

Privacy boundary violation.

## Symptom

ThoughtCop was intended to evaluate readable reasoning summaries only. Commit
`979856e` expanded the automatic evaluator to Codex and Claude tool calls and
tool results. A 41,245-byte tool-catalog result exposed this expansion when it
hit the local outbound-size limit.

## Exact source record

- Transcript: a redacted Codex rollout fixture
- Timestamp: redacted
- Type: `custom_tool_call_output`
- Call ID: redacted
- Stored output size: 41,245 bytes

The corresponding command printed matching entries from `ALL_TOOLS`, including
tool descriptions and schemas. `Transcript.swift` copied the complete `output`
field into an `EvaluationRecord`, and `HUD.swift` automatically evaluated every
new `.evidence` block.

## Fix

- `EvaluationRecord` can represent only `reasoning_summary` with readable
  `content`; it can no longer hold arbitrary transcript fields.
- Codex `custom_tool_call` and `custom_tool_call_output` records return no blocks.
- Claude `tool_use` and `tool_result` content returns no blocks.
- Remove the `.evidence` block kind and its automatic HUD evaluation branch.
- Remove the arbitrary `--check-record` CLI path; the explicit `--check` command
  accepts reasoning text only.
- Keep the outbound size boundary for unusually large reasoning summaries.

No keyword filter, semantic classifier, truncation, or heuristic is involved.
The permitted record type is enforced structurally.

## Verification

The evaluator self-test feeds representative Codex and Claude tool records into
the production transcript parser and requires zero returned blocks. It feeds a
Codex reasoning summary and requires one `reasoning_summary` evaluation record.
The full native regression suite must pass before release.
