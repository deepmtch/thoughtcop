# Thinkpeek lessons learned

These are release invariants extracted from real failures. They are mandatory
review material under `AGENTS.md`, not historical commentary.

## Provider evidence and identity

| Learned from | Permanent rule | Required proof |
|---|---|---|
| Claude/Codex sometimes showed `Working…` with no thought | Distinguish plaintext reasoning, provider summary, encrypted/empty reasoning, assistant response, tool activity, and lifecycle records. Never call one type another. Empty/encrypted reasoning is unavailable; say so explicitly. | Parser fixtures for every record type plus privacy-audit assertions. |
| It was unclear whether Thinkpeek waited for a JSON attribute or the provider had written nothing | Consume only newline-complete JSONL records and retain partial bytes until the line completes. Once a complete record contains empty/encrypted reasoning, report that exact limitation; do not wait for that record to mutate. | Partial-line split/rejoin tests and empty-reasoning fixtures. |
| Claude had useful final text but no plaintext thinking, so prompt violations were missed | Evaluate complete assistant responses as factual evidence even when thinking is absent. Do not display clean responses as thoughts. | Both Claude and Codex response fixtures and black-box checker requests. |
| Provider summaries and duplicate events looked like original reasoning | Show provider summaries locally only; never send them to the checker or duplicate them as separate thoughts. | External-request content assertions and audit actions. |
| `task 01a02dee` replaced the Codex sidebar title | Resolve identity from authoritative transcript metadata. Filename parsing is compatibility fallback only; never assume the last UUID owns the task. | A real-shape double-UUID fixture and exact title assertion. |
| A combined `Claude + Codex` status did not identify the displayed item | Every readable item carries its exact provider and session title. Aggregate wording is allowed only for aggregate activity, never for a specific thought or violation. | Source labels in events, ticker, reader, history, and screenshots. |
| Active Claude was hidden by later Codex activity | A one-line HUD cannot silently discard concurrent state. When multiple sessions are active, show every exact source and whether it is working or waiting. | Concurrent-provider black-box assertion on `peekSource` and `peekText`. |

## Checker correctness and observability

| Learned from | Permanent rule | Required proof |
|---|---|---|
| User-authored rules were reinterpreted | Preserve the check instruction verbatim. Wrappers define only transport/schema; no keyword rules, categories, semantic expansion, or line splitting unless explicitly selected by the user. | Serialized-envelope equality tests. |
| Tool calls, tool results, and user data risked entering checks | The outbound allowlist is reasoning text and assistant responses only. Everything else is explicitly rejected and audited without content. | Privacy audit plus dummy-checker payload inspection. |
| Checker work was invisible or briefly reported idle | Register request state and the visible indicator atomically when evidence is accepted. Keep a request/result pair with the same ID for every outbound attempt. | `/ui` in-flight/light assertions and paired audit IDs. |
| A transient test failure disappeared on retry | A retry is not evidence. Diagnose and remove the race; then rerun the full suite. | Deterministic repeated black-box completion. |
| Violations disappeared when the HUD was hidden | Persist violations independently of window visibility. Expose new/reviewed state in the menu bar and provide All/Violations filtering. | Store self-test and hide/reopen black-box flow. |

## UI and interaction

| Learned from | Permanent rule | Required proof |
|---|---|---|
| Hide and Quit were confused or buried | The HUD close action means Hide/return to ticker; Quit belongs in the menu bar with Command-Q. Never make quitting the only way to dismiss a transient view. | Lifecycle self-tests and menu inspection. |
| The borderless reader/history lacked an obvious exit | Every detail surface has a visible `Done` action and Escape returns directly to the ticker. | Exit and Escape tests. |
| Clicking outside an expanded thought hid the entire app | Outside click dismisses details to the ticker, never quits or destroys monitoring; an open editor is protected from outside-click dismissal. | Outside-click state matrix. |
| Position arrows disappeared after toolbar changes | Primary ticker actions and four corner controls are separate, fixed groups. A layout change must assert every control remains inside the rendered frame. | Accessibility-name inventory, width tests, and screenshot. |
| `Checks On` and a gear appeared inside history filters | Controls must be grouped by task. History contains history scope/navigation only; prompt editing and display settings stay on configuration surfaces. Labels describe actions, not misleading status. | Mode-specific control-visibility assertions through `/ui`. |
| A long settings list and monochrome debug toolbar were hard to scan | Use native hierarchy, semantic colors, provider icons, spacing, and destructive/alert emphasis. Visual polish is verified from an actual rendered PNG, not object existence. | `/screenshot` inspection at standard and narrow widths. |
| Users could not navigate recorded messages efficiently | Preserve Previous/Next, Home/End, arrows/J/K, Return/Space, and a fixed Latest action without stealing keys from editors. | Keyboard event tests and history API flow. |
| New messages replaced a message being read | Freeze the reader snapshot while open; closing resumes the latest stream. | Reader-freeze black-box test. |
| Always-on-top or position behavior regressed during resizing | The panel remains floating and anchored inside the visible screen across ticker/detail transitions. | Window-level and geometry tests against the running app. |

## Architecture, testing, and delivery

| Learned from | Permanent rule | Required proof |
|---|---|---|
| Manual clicking made failures hard to reproduce | Every user action routes through one command handler shared by AppKit and the local HTTP API. `/ui` exposes the state actually rendered, not a test-only model. | Command-path self-test and API action log. |
| Mock fixtures passed while the real provider still disagreed | Start diagnosis from the real Claude/Codex record and running app state. Create fixtures only after capturing the production record shape, identity, timestamps, and lifecycle exactly. | A redacted production-shape fixture plus live `/ui` evidence. |
| State flags passed while the pixels were wrong | For visual changes, verify both `/ui` and `/screenshot`; neither alone is sufficient. | Saved PNG inspection plus state assertions. |
| Unit parsers passed while concurrent production flow failed | Keep unit/parser tests, but require the isolated end-to-end test for discovery, concurrent providers, checker ordering, persistence, and UI commands. | `Scripts/test_multi_session_e2e.py`. |
| Rebuilds left an old process and old UI running | Build success does not update a live app. Replacement must start the new bundle, terminate the old instance only after launch, and end with exactly one process. | Post-commit restart log, PID count, and live `/ui`. |
| Fixing one toolbar broke another control | Review every mode that reuses the changed view: ticker, compact controls, full reader, all-history, violations-history, menu bar, narrow width, keyboard, and accessibility. | `docs/UI-CHECKLIST.md` and mode-specific regression assertions. |
| Changes were described before being committed and running | Completion means: code and docs committed, full suite green, replacement verified, one process running, and worktree clean. | Commit ID, test output, PID check, and `git status --short`. |
| Parallel investigation created a risk of unowned changes | Subagents may gather evidence in parallel when requested, but the primary agent owns edits, integration, tests, commit, restart, and final verification. | Clean diff review and one primary-agent commit. |

## Release gate

For every user-visible change:

1. Capture the failing provider record and/or rendered state.
2. State the exact root cause in `docs/bugs/BUG-NNN-*.md`.
3. Implement the smallest source-level fix without heuristics.
4. Add a focused test and extend the isolated black-box flow when boundaries are
   crossed.
5. Run `./Scripts/test.sh`.
6. Restart the real app, inspect `/ui`, and inspect `/screenshot` for UI changes.
7. Commit, let the post-commit hook rebuild, and verify exactly one current
   Thinkpeek process with a clean worktree.
