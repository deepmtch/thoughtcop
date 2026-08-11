# thinkpeek

See what Claude Code is thinking, live — and get shouted at when the thinking
goes wrong.

Claude Code appends every message to a JSONL transcript as the turn happens, not
when it ends. Both halves of thinkpeek tail that file and react the moment a
`thinking` block lands on disk.

| | | |
|---|---|---|
| **`thinkpeek`** | always-on-top window | shows the reasoning |
| **`watch.py`** | drift alarm | shouts when it matches your triggers |

```bash
swiftc -O -swift-version 5 -o thinkpeek main.swift   # build once
./thinkpeek                                          # the window
./thinkpeek --local-only                             # never send reasoning externally
python3 watch.py --project /private/tmp -v           # the alarm (second terminal)
```

Swift/AppKit + stdlib Python, no dependencies. **Nothing is ever written under
`~/.claude/`** — that directory is Claude Code's, and thinkpeek only ever reads
`~/.claude/projects/`.

## What it reads

Claude Code writes one JSON object per line to:

```
~/.claude/projects/<slugified-cwd>/<session-uuid>.jsonl
```

Assistant records carry a `message.content` array; reasoning appears as:

```json
{"type": "thinking", "thinking": "…", "signature": "CAISuwYKhwEIEBgC…"}
```

**The stored text is Claude's *summarized* reasoning, not raw chain-of-thought.**
A 250-character `thinking` string can represent a much longer reasoning pass, and
some blocks arrive with `thinking: ""` and only an opaque `signature`. Opus 5
does this by default unless Claude Code is configured to request summaries:

```json
{"showThinkingSummaries": true}
```

Add that key to `~/.claude/settings.json`. Existing omitted blocks cannot be
recovered retroactively. thinkpeek reports operation start immediately and then
shows either the readable summary or an explicit omitted-summary marker.

## Native window

The AppKit window is a resizable, always-on-top card feed rather than a terminal
view. It loads the complete reasoning history for the selected session, keeps all
text selectable, and scrolls normally. Live events follow the bottom only while
you are already near it; if you scroll upward, a **Latest** counter reports new
items without moving your reading position.

Auto mode follows every active session and nested agent. Use the session picker
to pin one session and inspect its complete history. Cards show the local time,
source session, readable summary, and a clear marker when Claude persisted only
an encrypted signature.

### Evidence the writes are live

Observed inside a single unfinished turn: the transcript grew 50,350 → 64,814 →
70,415 bytes across three tool calls, and the `thinking` record for the reasoning
that preceded each call was already on disk, timestamped, before the turn's reply
was sent. Per-record `timestamp` fields advance monotonically within the turn.

## The drift alarm

`watch.py` sends each new reasoning block, plus your `triggers.txt`, to a very
fast model and fires a terminal banner + bell + macOS notification if anything
matches — typically 300–550 ms after the reasoning hits disk, well before the
turn ends.

`triggers.txt` is the whole configuration: one plain-English rule per line, `#`
for comments, re-read on every check so edits take effect with no restart.

```
Claude is guessing or assuming instead of verifying against the actual code
Claude is about to run a destructive or irreversible command (rm -rf, force push)
Claude misunderstood the request and is solving a different problem
```

The integrated window calls providers directly: Groq first, then Cerebras as a
fallback when both are configured. There is no OpenRouter intermediary. Copy the
example and add one or both keys:

```bash
cp .env.example .env
# edit .env: GROQ_API_KEY=... and/or CEREBRAS_API_KEY=...
./thinkpeek --drift-status
```

`.env` is ignored by git; `.env.example` contains only empty placeholders and
model defaults. Normal launches read it and `--local-only` is the explicit
no-network mode. The status line and `/ui` API report whether external analysis
is enabled and name the exact direct provider. Every live card changes from
**Sending…** to either **AI checked**, **Drift detected**, or **AI check failed**.

## Requirements

### Functional

1. **Follow every active operation.** Auto mode tails every recently touched
   transcript, including concurrent sessions and nested sub-agents. Each reasoning
   block is labeled with its source session; a session can still be pinned manually.
2. **Stream incrementally.** Tail by byte offset; never re-read the file from the
   start. New reasoning must appear within ~0.5 s of being written.
3. **Survive partial writes.** A line still being flushed must be buffered, not
   parsed as truncated JSON, and must render correctly once the newline arrives.
4. **Survive truncation/rotation.** If the file shrinks below the current offset,
   reset to 0 rather than seeking past the end.
5. **Complete history on attach.** Load every reasoning block for a pinned or
   selected session so the full conversation remains inspectable and scrollable.
6. **Distinguish sealed blocks.** Signature-only reasoning is displayed as such,
   never as empty space — the user must be able to tell "Claude thought nothing"
   from "the content was not persisted".
7. **Always on top,** across Spaces and over full-screen apps, without stealing focus.
8. **Read-only.** Never write to, lock, or truncate a transcript, and never
   create anything under `~/.claude/`.
9. **Never silently drop a block.** A reasoning block that arrives split across
   two writes must still be shown and still be scored — a missed block is a
   missed alarm.

### Non-functional

- **Zero install.** Builds with the `swiftc` in Xcode Command Line Tools; links
  only AppKit and Foundation. No package manager, no runtime, no app bundle.
- **Single file**, readable in one sitting.
- **Negligible cost** — idle polling must not register in Activity Monitor.

## Testing

The tailing engine and the actual native window presentation are both testable.

```bash
./thinkpeek --selftest
```

prints the active transcript and its last 5 reasoning blocks — no window involved.

Engine tests cover: backfill, live append, sealed-block flagging, partial-line
safety, and partial-line rejoin. All 5 pass against a real transcript.

The window presentation is also exposed as a headless JSON API. The AppKit
renderer and automated tests consume the same `UIEvent` objects:

```bash
./thinkpeek --ui-json ~/.claude/projects/<project>/<session>.jsonl
```

The running window publishes the state it actually consumed at the local,
read-only endpoint `http://127.0.0.1:17321/ui` (override with
`THINKPEEK_API_PORT`). This makes window title, selection, status, analysis,
omitted blocks, activity, and drift results assertable without screen capture.
The companion `http://127.0.0.1:17321/screenshot` endpoint returns a PNG rendered
by the running AppKit window, so layout and scrolling can be checked end to end.
Use `./thinkpeek --transcript /absolute/session.jsonl` to pin a deterministic
input for an end-to-end UI test.

For the alarm:

```bash
python3 watch.py --selftest                     # backend, model, latency, triggers
python3 watch.py --once "I'll rm -rf the build dir without checking"
```

## History

The first implementation was Python + Tk, chosen for zero-install (system Python
ships Tk). It opened an always-on-top window that stayed blank white — no dark
background, no text. The cause showed up in the launch output:

```
DEPRECATION WARNING: The system version of Tk is deprecated and may be removed
in a future release.
```

macOS 27 with Tk 8.5 (a 2009-era Aqua build): the window chrome draws, the
content area does not. Not fixable from the Python side, so the UI was rewritten
in AppKit. The tailing logic was ported unchanged — it was never the problem.

The drift alarm was built separately, in `~/.claude/reasoning-watch/`, and moved
here. Two bugs came with it: it wrote its own state into `~/.claude/`, and its
tailer called `splitlines()` on each chunk while advancing the file offset — so a
record still being flushed parsed as truncated JSON and was **silently dropped
forever**. Reproduced against the pre-fix copy (block lost), fixed by holding the
trailing partial line in a buffer, re-tested (block scored).

Two things made the window bug slow to diagnose and are worth remembering: `tk.Tk()` blocks
forever from a sandboxed/background shell (ignoring even `SIGALRM`), and
`screencapture` there fails with *"could not create image from display"*. Any GUI
change has to be verified by launching from a real Terminal in an Aqua session.
