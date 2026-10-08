# BUG-077 — Claude cache monitor continuously consumed more than one CPU core

## User-visible failure

Activity Monitor showed ThoughtCop at 177% CPU while the HUD was hidden. Hiding
the HUD did not stop the monitoring queue, so the machine remained hot.

## Production evidence

The live Claude cache contained 19,584 files (1.2 GB), of which exactly two
contained Claude session SSE stream URLs and 65 contained Desktop conversation
records. A five-second process sample recorded
2,170 of 2,200 samples on `thoughtcop.claude-cloud-activity`; 1,842 samples were
inside `FileManager.attributesOfItem` and 208 were in directory enumeration.
The live `/ui` state reported `tickerOverflowing: false`, excluding ticker
animation as the primary cause.

## Root cause

The HUD requests cloud polling every 0.2 seconds. Once per second,
`discoverStreams()` enumerated the entire lifetime Chromium cache and called
`attributesOfItem` for every non-stream file before its size cache could reject
unchanged entries. A scan lasted longer than its one-second interval, so the
next accepted poll immediately began another scan. The separate Claude Desktop
conversation monitor repeated the same directory enumeration and metadata pass
five times per second, and its initial pass fully read every cache file before
rejecting non-conversation headers. Serialization prevented overlap but produced
continuous busy loops.

A second sample after correcting both Claude cache monitors reduced their active
samples from 2,539 to 30, but exposed 146 samples in transcript discovery. That
worker was rereading and reparsing the latest timestamp from all 734 Claude and
Codex transcripts every 0.5 seconds even when their size and modification time
were unchanged.

## Fix

Both cache monitors now maintain the exact set of cache entry names. Header
inspection is limited to newly appeared names and entries whose initial header
is still incomplete. Removed names are forgotten, so recreating an entry is
discoverable. Recognized SSE streams and conversation files retain the
0.2-second change path, preserving live event latency. The Desktop monitor reads
full content only after a 4 KiB header positively identifies a conversation.

Transcript discovery now caches the latest activity timestamp by each file's
exact size and modification date. Directory discovery still finds new sessions,
but unchanged transcript tails are not reopened or reparsed; a real append
invalidates the stamp on the next scan and retains the existing polling latency.
The recursive Claude/Codex tree is likewise cached and rebuilt only when an
indexed directory's exact modification timestamp changes. Existing active files
remain on the independent 0.2-second tail path.

The 19,584-entry self-test proves that an unchanged directory produces zero new
inspection candidates, then verifies add, remove, and same-name recreation. A
separate transcript test proves two unchanged scans perform one tail parse total
and an exact file append performs the second. A directory-index test proves a
new transcript is discovered after the parent directory changes.

## Live verification

The final rebuilt process reported 13.6–14.1% CPU while this Codex task was
actively producing records, down from the captured 177%. In a five-second
sample, transcript monitoring appeared in 19 samples, transcript discovery in
13, Claude Desktop monitoring in 3, and Claude cloud monitoring in 1. The four
monitoring queues therefore fell from 2,539 sampled stacks before correction to
36 after correction. The live `/ui` endpoint remained ready and continued to
identify the active `Codex · Thought watch` source.
