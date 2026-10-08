# BUG-081 — UI API exposed local transcripts

## Evidence

The running app accepted unauthenticated `GET /ui` and unauthenticated action
requests. The state contains rendered Claude/Codex text, and action paths can
change or terminate the visible app. Binding to localhost alone did not prevent
another local process or browser-origin request from reaching it.

## Root cause

The inspection server was originally treated as a test-only convenience. It had
neither a caller capability nor HTTP method separation, and its listener did
not explicitly require a loopback endpoint.

## Fix

Thoughtcrime creates a random bearer capability in a `0600` application-support
file, requires it on every request, explicitly binds `127.0.0.1`, keeps `/ui`
and `/screenshot` read-only, and requires `POST` for actions. Responses are
marked `no-store` and the command log remains content-free.

## Verification

`Scripts/test_multi_session_e2e.py` proves unauthenticated requests return 401,
mutating GET and state-changing POST misuse return 405, unknown routes return
404, and `lsof` shows only `127.0.0.1`. `Scripts/test_ui_api.py` then drives the
real AppKit state with the capability.
