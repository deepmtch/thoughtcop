# BUG-058 — Transcript discovery blocked the main UI thread

## User-visible failure

Thinkpeek could hang at startup and periodically stop responding after launch,
especially with a large Claude or Codex transcript history.

## Cause

Startup synchronously enumerated and read metadata for every transcript to build
an offset snapshot. The 0.5-second monitor refresh and five-second session picker
refresh repeated recursive enumeration and metadata reads on AppKit's main thread.
Process sampling showed the timer callback inside `activeTranscriptPaths` and
`FileManager.attributesOfItem`.

## Fix

One serialized utility queue now produces a shared transcript snapshot for
offsets, active monitors, and picker sessions. A second serialized worker owns
tailer construction, file reads, and JSON parsing. AppKit only applies completed
snapshots and parsed blocks. Slow scans and monitor updates cannot overlap, and
neither startup nor timer callbacks wait for transcript filesystem work.

## Verification

The discovery and monitor regression tests each inject 250 ms of work and verify
that requesting it returns in under 50 ms, concurrent work is rejected, and the
result is eventually delivered. The multi-session black-box test verifies the
real app API, transcript monitoring, checker, ticker selection, and concurrent
providers.
