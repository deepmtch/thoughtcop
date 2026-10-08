# BUG-039: Codex reasoning item was split into summary lines

## Symptom

Opening `Planning prefilter for reasoning records` showed one line in the reader,
although the matching Codex reasoning item contained additional readable text.

## Exact evidence

At `2026-08-15T15:07:15.041Z`, the authoritative
`response_item.reasoning.summary` array contains, in order:

1. `Assessing selective JSON parsing approach`
2. `Planning prefilter for reasoning records`

The same record carries 4,216 bytes of encrypted reasoning. Those bytes are not
readable, but both summary entries are readable and must be shown.

Across the audited session, Codex wrote 1,068 `event_msg.agent_reasoning` records
and exactly 1,068 summary-array entries grouped into 594 response records.

## Cause

ThoughtCop parsed each duplicated `event_msg.agent_reasoning` entry as an
independent message and ignored every non-empty `response_item.reasoning.summary`
array. The full-message reader therefore opened one fragment instead of the
complete readable reasoning item.

## Fix

- Ignore duplicated individual Codex reasoning events.
- Parse the authoritative response reasoning array.
- Preserve every non-empty summary entry in order, separated by a blank line.
- Keep encrypted-only response records represented as omitted analysis.

Claude thinking records retain their existing reasoning-only path.

## Verification

The production parser test provides one duplicate individual event and one
two-entry response summary. It requires zero blocks for the duplicate and one
reasoning block containing both entries in order.
