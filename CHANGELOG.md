# Changelog

All notable user-facing changes will be recorded here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

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
