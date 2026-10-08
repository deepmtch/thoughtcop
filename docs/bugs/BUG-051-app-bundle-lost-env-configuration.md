# BUG-051: app-bundle restart lost checker configuration

## User-visible failure

After an automatic post-commit restart, Thoughtcrime continued displaying Claude
and Codex reasoning but reported that checking was off and produced no alarms.

## Evidence and root cause

The live UI API reported `externalAnalysisEnabled: false` and
`GROQ_API_KEY and CEREBRAS_API_KEY missing from .env`, while the repository
`.env` contained both configured names. The running process executable was
inside `.build/Thoughtcrime.app/Contents/MacOS`.

`PROJECT_ROOT` handled the raw `.build/thoughtcrime` layout only. After commit
`8760fab` switched automatic restarts to the app bundle, configuration lookup
incorrectly targeted `.build/Thoughtcrime.app/Contents/MacOS/.env` instead of the
repository `.env`.

## Fix

Resolve the repository root explicitly for both supported layouts:

- `.build/thoughtcrime`
- `.build/Thoughtcrime.app/Contents/MacOS/thoughtcrime`

No key values are logged or copied into the app bundle.

## Verification

`--config-path-selftest` asserts both layouts resolve to the same repository
root. The live UI API must report `externalAnalysisEnabled: true` after the
post-commit replacement starts.
