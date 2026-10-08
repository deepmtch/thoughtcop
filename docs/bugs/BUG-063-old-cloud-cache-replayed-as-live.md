# BUG-063 — Old Claude cloud cache replayed as live activity

## User-visible failure

After a restart, the ticker could remain on an old Claude cloud session and
show `working…` or `waiting for you` even though that cloud turn occurred days
earlier. Fresh local Claude and Codex activity was then hard to distinguish from
the resurrected source.

## Evidence and cause

The live API reported `Claude · cloud chat gHJ6Wk` as waiting. The matching
Claude cache file was last modified on August 13, while the app was running on
August 16. `ClaudeCloudActivityMonitor` discovered every persistent SSE cache
file and initialized its read offset to zero, replaying the entire historical
stream after every Doublethink launch.

## Fix

When an existing cloud SSE cache file is discovered, its initial offset is now
the exact file size at discovery. Only bytes appended afterward can produce
live activity. There is no age threshold, timeout, or content heuristic.

The existing black-box cloud test creates the cache header before launching
Doublethink and appends lifecycle events afterward, so it verifies the same
tail-from-EOF contract used in production.
