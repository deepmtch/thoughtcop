# BUG-029: User instruction was reinterpreted and alerts were hidden

> Scope correction: the structured tool-record expansion described below was
> removed by BUG-038. Automatic evaluation is reasoning-only.

## Symptom

The saved text included `WARN. WHEN CODE IS BEING CHANGED`, but the ticker showed
code work without a warning. Opening the message also did not show its check
result.

## Evidence

- The native app loaded both saved lines and sent the target summary to Groq.
- The old hidden prompt converted those lines into numbered “strict” triggers.
- The exact planning summary returned clean in 3/3 isolated checks.
- Nearby implementation summaries sometimes alerted, but the result was stored
  only on an `EventCard` footer. Ticker/detail previews stored only source, text,
  and kind, so those views could not display the warning.
- A single verbatim binary instruction passed 40/40 isolated cases, including
  arbitrary wording, exact case, and evidence containing prompt injection.
- Sending the existing two-line text as one instruction was unreliable: the
  model ignored one line or the other depending on message placement.

## Root cause

There were three independent boundaries:

1. Doublethink added semantic policy (“be strict”) and numbered the user's text.
2. It checked only reasoning summaries, not the structured tool evidence already
   present in Claude and Codex transcripts.
3. Asynchronous results mutated card footers but were not part of the message
   model consumed by the ticker and full-message reader.

## Fix

- The transport wrapper defines only a strict binary JSON response. Each user
  instruction is sent verbatim and evidence is sent as a separate data record.
- The editor makes structure explicit: whole text is one instruction, or each
  non-empty line is independently evaluated. Existing text retains the old
  editor's explicit independent-line contract; no content is inspected to pick
  the mode.
- Historical implementation only: Claude and Codex tool records were briefly
  parsed as evaluation evidence. BUG-038 removed this expansion completely.
- Clean tool evidence remains out of the feed. Alerted or failed evidence creates
  a navigable origin card.
- Each message owns `pending`, `clear`, `alert`, or `failed` evaluator state.
  Ticker and full-message views render from that same object.
- Invalid JSON, provider failure, and oversized evidence are visible failures,
  never silent clean results.
- The obsolete Python watcher no longer contains a second heuristic checker. Its
  compatibility entry point delegates one-shot checks and contract tests to the
  native executable and fails visibly for the retired live-watcher mode.

## Verification

- `Scripts/test.sh`: all native regression checks pass.
- Compiled Swift evaluator with the exact saved two-line text:
  - completed edit evidence: 5/5 alerts;
  - exact planning-only summary: 5/5 no alerts.
- Restarted native app `/ui` state confirmed `eachLine`, two verbatim
  instructions, a structured `drift-alert` carrying source and evidence, and the
  same alert rendered in `peekText` as the active one-line ticker message.
- Pure regression coverage verifies verbatim preservation, explicit modes,
  Claude/Codex structured evidence parsing, strict decision JSON, invalid-result
  rejection, and alert propagation into ticker/detail presentation.
