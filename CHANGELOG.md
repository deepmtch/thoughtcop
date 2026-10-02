# Changelog

All notable user-facing changes will be recorded here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

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
