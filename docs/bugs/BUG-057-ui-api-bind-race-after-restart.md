# BUG-057 — UI API could disappear after replacement restart

## User-visible failure

The replacement Thoughtcrime process and window were alive, but port 17321 was not
listening. API-based verification and UI automation could not inspect the app.

## Cause

The new process could attempt to bind while the previous instance was still
releasing the port. `UIStateServer.start()` silently abandoned a failed listener
and wrote `api_started` before Network.framework reported that it was ready.

## Fix

The server now retries a failed bind every 200 ms for up to five seconds. It
writes `api_started` only after the listener reaches Network.framework's
`.ready` state.

## Verification

The complete suite includes an isolated real-process API test. Production
verification requires the post-commit replacement to listen on 17321 and report
`initialScanComplete=true`.
