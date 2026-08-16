# BUG-055 — Multi-session checker flow lacked a black-box test

## Gap

Component tests covered parsing, the checker envelope, cards, ticker controls,
and the local UI API separately. They did not prove that concurrent Claude and
Codex sessions flow through the running AppKit application correctly.

## Test harness

`Scripts/test_multi_session_e2e.py` launches an isolated real Thinkpeek process
against temporary Claude/Codex transcript roots and a deterministic local HTTP
checker. It never uses production keys or logs.

The test writes concurrent fixtures containing:

- plaintext Claude thinking that must alert;
- plaintext Codex `reasoning_text` that must remain clean;
- a Codex tool call that must never reach the checker;
- encrypted/summary-only Codex reasoning that must never reach the checker or
  the ticker.

The dummy checker deliberately completes Codex before Claude. The test observes
the lightbulb through the real UI API, waits for both outcomes, verifies paired
audit records, confirms the latest clean Codex text remains selected, navigates
back to the Claude warning, and navigates forward to Codex again.

## Isolation

Test-only paths, API port, audit file, UI log, and localhost checker URL are
injected through explicit isolated-process configuration. Production launches
continue using the normal transcript locations and real configured providers.
