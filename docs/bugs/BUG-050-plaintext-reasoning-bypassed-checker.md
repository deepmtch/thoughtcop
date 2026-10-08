# BUG-050: plaintext reasoning bypassed the checker

## User-visible failure

Thoughtcrime displayed live Claude and Codex reasoning but produced no alarm even
when that reasoning plainly matched the configured check instruction.

## Evidence and root cause

The privacy audit logged `reasoning_selected` for the affected Claude record but
no following `external_reasoning_request`. Manual evaluation of the same text
returned an alert from the configured checker.

Commit `0065641` assigned readable Claude `thinking` and Codex
`reasoning_text` blocks an empty evaluation payload and
`externallyEvaluable: false`. The HUD therefore skipped the checker before any
model request was made.

## Fix

- Use the exact plaintext reasoning as both the displayed text and evaluation
  payload.
- Mark only nonempty Claude `thinking` and Codex `reasoning_text` as externally
  evaluable.
- Continue excluding ordinary messages, tool calls/results, provider summaries,
  and encrypted-only records.
- Retain the 32 KB external-envelope limit.

## Verification

The evaluator and provider-reasoning self-tests assert exact payload equality
and external eligibility for plaintext reasoning. The boundary test also asserts
that messages, tool records, summaries, and encrypted-only records remain
excluded.
