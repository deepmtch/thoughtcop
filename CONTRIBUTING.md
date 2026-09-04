# Contributing

Contributions are welcome. By contributing, you agree that your contribution is
licensed under GPL-3.0.

1. Create a focused branch from `develop`.
2. Follow `AGENTS.md`, especially the evidence and regression-record rules.
3. Run `./Scripts/test.sh` on macOS 13 or newer.
4. Do not commit transcripts, API keys, `.env`, screenshots containing personal
   data, build output, or local logs.
5. Explain user-visible behavior changes and include their focused test.

Pull requests should target `develop`. Distribution changes must preserve the
fail-closed signing and notarization checks in `Scripts/release.sh`.
