# BUG-034: Checker failure looked like a user warning

## Symptom

When ThoughtCop could not send or score an evaluation, the ticker and message
reader used the same warning symbol and nearly the same presentation as a
successful user-configured warning. The reader header still named the monitored
Codex or Claude task, making an internal ThoughtCop failure look like task output.

## Cause

`MessagePreview` attached both evaluation outcomes to the monitored message but
did not expose presentation severity or a presentation-specific source.
`EventCard` also gave configured warnings the red error color while checker
failures received only a red footer.

## Fix

- Model reader tone explicitly as normal, warning, or error.
- Attribute configured warnings to `ThoughtCop · Warning` and use amber.
- Attribute evaluator failures to `ThoughtCop · Check error`, prefix them with a
  stop/error symbol, and use a red wash plus a red leading stripe.
- Preserve the original monitored source and content inside the detail body so
  attribution remains factual.
- Give history cards separate amber-warning and red-error treatments.

## Verification

The evaluator self-test checks warning and failure source, text, and tone. The
message-view self-test verifies that an error snapshot reaches the dedicated
reader with the error tone intact.
