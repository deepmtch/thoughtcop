# BUG-069: Omitted thinking bypassed response checks

## Symptom

Claude Desktop showed that a task was working, but ThoughtCop displayed only
`Working…` and recorded no violation after Claude returned a response that the
user expected the configured check instruction to flag.

## Evidence

The live Claude Desktop child process for the affected session was launched with
`--output-format stream-json` and the explicit flag
`--thinking-display omitted`. Its session JSONL contained signature-only
`thinking` blocks whose `thinking` field was empty, followed by ordinary
assistant `text` blocks containing the response.

ThoughtCop's parser accepted only non-empty `thinking` records for evaluation.
The privacy audit therefore recorded `encrypted_reasoning_not_sent` and no
external request for the response. No later write populated the empty field.

## Fix

- Continue displaying and evaluating non-empty provider reasoning exactly as
  recorded.
- Parse complete Claude `message.content[].text` and Codex assistant
  `response_item/message.content[].output_text` records as
  `assistant_response` evidence.
- Parse assistant `content[].type == "text"` from Claude Desktop's structured
  conversation-cache responses through the same response-only evaluation path.
- Evaluate live assistant responses immediately without labeling or displaying
  them as thoughts. A response creates a card only for a violation or a visible
  checker failure.
- Exclude explicit Claude API-error messages, user messages, tools, and tool
  results.
- Record content-free audit metadata separately for reasoning and assistant
  response evaluation.

## Regression coverage

The evaluator self-test asserts exact Claude and Codex response extraction,
event typing, API-error exclusion, and response-versus-thought presentation.
The privacy-audit self-test asserts response selection and outbound request/result
metadata while proving response content is absent from the audit log.
