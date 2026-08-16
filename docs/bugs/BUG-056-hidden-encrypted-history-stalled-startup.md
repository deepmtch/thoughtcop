# BUG-056 — Hidden encrypted history stalled startup

## User-visible failure

After encrypted records stopped becoming useless ticker placeholders, the first
monitor scan could remain busy reading a very large rollout file. The ticker
stayed on its initial “Watching” state and the UI API kept
`initialScanComplete=false`.

## Cause

Bounded-count backfill kept reading backward until it found the requested number
of presentable records. A file containing mostly encrypted or tool records could
force a scan of the entire file because those records correctly produce no UI
blocks.

## Fix

Normal finite-history backfill now reads at most the newest 2 MiB of each
transcript. Explicit unlimited-history mode still reads the complete file.
Live tailing remains byte-offset based and is not truncated.

## Verification

The transcript self-test asserts the finite and unlimited scan floors. Final
live verification requires the production API to reach
`initialScanComplete=true` after restart with zero omitted-analysis events.
