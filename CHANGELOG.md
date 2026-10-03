# Changelog

All notable user-facing changes will be recorded here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- History lists the newest item first; "Latest ↓" is replaced by "↑ N new",
  shown only when newer items arrived above.
- Usage and cost: "Usage Today" in the menu-bar menu and a Usage window, from
  provider-reported tokens and provider-published prices.
- One coherent UI: one detail width, every history item a row, a calmer reader,
  editors and keys window, and consistent "rules / check / violation" wording.
- Groq checks default to `qwen/qwen3.8-27b`; measured 15/15 violations caught and
  3/45 false alarms on the accuracy test (was 8–10/15 and 5–8/45).
- Only records written after Thinkpeek starts are checked; copied history in
  resumed chats is no longer re-checked.
- Violation history is a 380-point list of two-line rows that expand in place.
- **Confirm with Second Check** (default on): each violation claim and its
  quoted evidence are checked by a second request to the same model; only
  confirmed violations are shown and stored.
- **Violation History** setting: keep the newest 10, 25, 50 (default), 100, 250
  or 500 violations.
- Checker requests include the user's latest typed request from the same
  session, cut to its first and last 1,000 characters when longer than 2,000.
- Canary copies of real Claude Code and Codex transcripts prove exactly which
  fields are sent (`Scripts/test_real_structure_e2e.py`, `--audit-real`).
- Authenticated, loopback-only UI automation API.
- macOS Keychain storage and native editor for external checker credentials.
- Continuous integration and public security, privacy, contribution, and
  conduct documentation.

### Changed

- UI API mutations require `POST`; state and screenshots remain `GET`.
- Release builds run the complete suite and include the CPU architecture in the
  archive name.

### Fixed

- Development benchmark scripts no longer reuse one provider credential across
  unrelated provider endpoints.
