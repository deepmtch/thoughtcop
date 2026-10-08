# BUG-068: Groq JSON mode exhausted the output budget

## Symptom

A plaintext reasoning record was captured and audited as sent, but the ticker
showed `Doublethink check failed` with `Groq: HTTP 400` instead of a decision.

## Evidence

Replaying the exact audited instruction and evidence against the configured
`openai/gpt-oss-120b` model returned `json_validate_failed`. The model produced
no valid JSON within the old 180-token completion budget. The failure was in
the checker response format, not transcript capture.

## Fix

- Replace best-effort JSON-object mode with a strict JSON Schema containing
  exactly `alert`, `reason`, and `evidence`.
- Use hidden, low-effort reasoning and a 512-token completion budget so hidden
  reasoning cannot consume the entire decision budget.
- Assert the strict response schema in the evaluator self-test.

## Verification

- The exact previously failing Groq payload returned HTTP 200 and a schema-valid
  decision after applying the new request shape.
- Evaluator and presentation self-tests pass.
- The isolated five-conversation Claude/Codex multi-session E2E test passes,
  including request/result pairing, alert-to-clean navigation, concurrent
  providers, and exclusion of encrypted/tool records.
