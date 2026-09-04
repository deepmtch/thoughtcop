# BUG-083 — Benchmarks reused provider credentials

## Evidence

The benchmark utilities loaded a generic token and attempted to use it against
multiple provider hosts. One script also looked for a credential in a shared
temporary-file path.

## Root cause

Prototype benchmark configuration treated tokens as interchangeable strings
instead of provider-scoped capabilities.

## Fix

Each benchmark destination now reads its own named environment variable:
`CEREBRAS_API_KEY` or `OPENROUTER_API_KEY`. Missing values fail immediately and
no shared temporary credential file is read.

## Verification

The complete suite compiles both benchmark scripts. Repository inspection
asserts there is no generic `/tmp/key` path and no cross-provider credential
reuse in current source.
