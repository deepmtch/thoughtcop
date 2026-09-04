# BUG-082 — Installed build had no credential store

## Evidence

Provider keys were read only from the process environment or a repository
`.env`. A distributed `.app` is not inside that checkout, so external checking
could appear disabled with no supported way to configure it securely.

## Root cause

Development configuration was used as the production credential design.

## Fix

Groq and Cerebras keys now have separate generic-password entries in the macOS
login Keychain. A native **Provider Credentials…** editor uses secure fields,
never preloads saved values, and offers explicit removal. Process environment
and a development checkout `.env` remain higher-precedence overrides.

## Verification

`--checker-credentials-selftest` uses a fake store to prove override precedence,
Keychain fallback, replace/remove behavior, secure AppKit fields, and a `0600`
API capability file. The UI API publishes configuration booleans only.
