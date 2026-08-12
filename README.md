# thinkpeek

See Claude Code and Codex reasoning summaries live — and get shouted at when the
reasoning goes wrong.

Claude Code and Codex append live JSONL session events as turns run. thinkpeek
tails both sources and reacts when a readable reasoning summary lands on disk.

| | | |
|---|---|---|
| **`thinkpeek`** | always-on-top window | shows the reasoning |
| **`watch.py`** | drift alarm | shouts when it matches your triggers |

```bash
./build.sh                                           # build once
./thinkpeek                                          # the window
./restart.sh                                         # rebuild and replace a running copy
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

Codex tasks write rollout events to:

```
~/.codex/sessions/<year>/<month>/<day>/rollout-<timestamp>-<task-uuid>.jsonl
```

Codex readable summaries arrive as `event_msg/agent_reasoning`; task starts are
also represented internally as progress only: they never replace a readable
summary or enter card history. Encrypted-only records are hidden by default. Task names come from
`~/.codex/session_index.jsonl`. Auto mode follows both Claude and Codex, and the
picker labels every source explicitly.

This covers Codex CLI/app agent tasks that create local rollout files. It does
not claim access to ordinary consumer ChatGPT conversations that do not create
those files.

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

The AppKit window is a resizable, always-on-top HUD rather than a terminal view.
Its borderless resting state keeps a fixed 460 × 70-point frame: the exact source session on
top and a single-line ticker below. Overflowing text pauses at the beginning,
moves horizontally, pauses at the end, and quickly returns. With macOS Reduce
Motion enabled, it remains clipped and stationary. Hover never changes the UI.
A single click opens a dedicated full-message reader; **Done** or a click outside
the reader returns to the ticker. The visible controls button or a deliberate double-click opens the
separate navigation/settings view. The **↤** control returns directly to the
ticker's beginning. The settings menu selects and remembers Slow, Normal, or Fast
ticker movement and provides Top/Bottom × Left/Center/Right presets.
**Show all** explicitly locks open the full scrollable feed until **Collapse** is
selected. Compact and full-feed widths are hard-capped at 560 and 700 points, so
long reasoning wraps and scrolls vertically instead of stretching the window.

Auto mode follows every active session and nested agent. Use the session picker
to pin one session. Cards show the local time, source session, and readable summary.
Set `THINKPEEK_HISTORY_COUNT` in `.env` to an integer, `0`, or `all`. Encrypted
signature-only cards are hidden unless `THINKPEEK_SHOW_ENCRYPTED=true`.
Repeated identical summaries from the same source are presented once even when
the transcript records them at multiple timestamps.

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
   Claude and Codex transcript, including concurrent sessions and nested Claude
   sub-agents. Each reasoning block is labeled with its platform and source task;
   a session can still be pinned manually.
2. **Stream incrementally.** Tail by byte offset; never re-read the file from the
   start. New reasoning must appear within ~0.5 s of being written.
3. **Survive partial writes.** A line still being flushed must be buffered, not
   parsed as truncated JSON, and must render correctly once the newline arrives.
4. **Survive truncation/rotation.** If the file shrinks below the current offset,
   reset to 0 rather than seeking past the end.
5. **Configurable history on attach.** Load the latest three readable summaries
   by default; allow an integer, zero, or the complete history through `.env`.
6. **Handle sealed blocks explicitly.** Signature-only reasoning is hidden by
   default and can be displayed as an omitted-summary card through `.env`; it is
   never presented as if readable analysis existed.
7. **Always on top,** across Spaces and over full-screen apps, without stealing focus.
8. **Read-only.** Never write to, lock, or truncate a transcript, and never
   create anything under `~/.claude/`.
9. **Never silently drop a block.** A reasoning block that arrives split across
   two writes must still be shown and still be scored — a missed block is a
   missed alarm.

### Non-functional

- **Zero install.** Builds with the `swiftc` in Xcode Command Line Tools; links
  only AppKit and Foundation. No package manager, no runtime, no app bundle.
- **Small focused Swift files.** Transcript parsing, session discovery, drift
  checks, API serving, reusable views, HUD coordination, and startup each have a
  separate source file.
- **Negligible cost** — idle polling must not register in Activity Monitor.

## Testing

The tailing engine and the actual native window presentation are both testable.

```bash
./thinkpeek --selftest
./thinkpeek --layout-selftest
./thinkpeek --presentation-selftest
./thinkpeek --source-context-selftest
./thinkpeek --ticker-selftest
./thinkpeek --message-view-selftest
./thinkpeek --outside-click-selftest
./thinkpeek --window-position-selftest
./thinkpeek --window-chrome-selftest
./thinkpeek --interaction-selftest
```

prints the active transcript and its last 5 reasoning blocks — no window involved.
The layout check verifies fixed-width full-card wrapping; the ticker check verifies
that the resting message stays on one vertically contained line when it overflows.

Engine tests cover: backfill, live append, sealed-block flagging, partial-line
safety, and partial-line rejoin. All 5 pass against a real transcript.

The window presentation is also exposed as a headless JSON API. The AppKit
renderer and automated tests consume the same `UIEvent` objects:

```bash
./thinkpeek --ui-json ~/.claude/projects/<project>/<session>.jsonl
```

The running window publishes the state it actually consumed at the local
endpoint `http://127.0.0.1:17321/ui` (override with
`THINKPEEK_API_PORT`). This makes window title, selection, status, analysis,
omitted blocks, activity, and drift results assertable without screen capture.
The companion `http://127.0.0.1:17321/screenshot` endpoint returns a PNG rendered
by the running AppKit window, so layout and scrolling can be checked end to end.
`/message`, `/controls`, `/hide`, `/previous`, `/next`, `/restart-ticker`,
`/speed/slow`, `/speed/normal`, `/speed/fast`, and
`/toggle-expanded` exercise the same reader, settings, and carousel paths as the
visible UI, allowing every presentation state to be tested through the complete
running window. `/reveal` remains an alias for `/controls` for compatibility.
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
