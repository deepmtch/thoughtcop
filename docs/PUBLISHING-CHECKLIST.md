# Publishing checklist

## Source gate

- [x] License, privacy, security, contribution, conduct, and changelog files.
- [x] `.env`, build products, caches, and local logs excluded from Git.
- [x] Loopback UI API authenticated and mutations restricted to `POST`.
- [x] Provider credentials stored in Keychain for installed builds.
- [x] Benchmarks use provider-specific environment variables.
- [x] CI runs the complete suite on macOS.
- [x] Release script fails closed and reruns the complete suite.
- [ ] Review or rewrite pre-publication history for old binaries and author
  metadata. History rewriting needs explicit owner approval.

## Distribution gate

- [ ] Final app icon and current screenshots.
- [ ] Developer ID Application certificate available.
- [ ] Valid `notarytool` Keychain profile available.
- [ ] Release script produces an architecture-labeled, notarized ZIP.
- [ ] Gatekeeper accepts the ZIP on a clean Mac.
- [ ] GitHub repository name, description, topics, and default branch confirmed.
- [ ] Branch protection requires the Tests workflow.
- [ ] Tag and GitHub release notes match `CHANGELOG.md`.
