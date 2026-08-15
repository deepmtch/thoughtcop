# thinkpeek

See Claude Code and Codex reasoning summaries live — and get shouted at when the
reasoning goes wrong.

Claude Code and Codex append live JSONL session events as turns run. thinkpeek
tails both sources and reacts when a readable reasoning summary lands on disk.

| | | |
|---|---|---|
| **`.build/thinkpeek`** | always-on-top window | shows the reasoning |
| Native evaluator | drift alarm | evaluates structured records against your verbatim instruction |

```bash
./build.sh                                           # build once
./.build/thinkpeek                                   # the window
./restart.sh                                         # rebuild and replace a running copy
./.build/thinkpeek --local-only                      # never send reasoning externally
```

This checkout uses the repository-managed `.githooks/post-commit` hook. After
each successful commit it queues a background rebuild and replaces the running
Thinkpeek only when that build succeeds. Rapid commits are coalesced. Inspect
`.local/post-commit/restart.log` if a restart does not complete. Install the hook
for a fresh clone with:

```bash
git config core.hooksPath .githooks
```

Swift/AppKit + stdlib Python, no dependencies. **Nothing is ever written under
`~/.claude/`** — that directory is Claude Code's, and thinkpeek only ever reads
`~/.claude/projects/`.

## Project layout

```text
Sources/
├── App/             # entry point and application coordinator
├── Checker/         # check-rule storage and model scoring
├── Monitoring/      # transcript discovery, parsing, and presentation state
├── Infrastructure/  # single-instance and local inspection server
└── UI/
    ├── Components/
    ├── Controls/
    ├── Layout/
    └── Ticker/
Scripts/             # optional command-line watcher
Benchmarks/          # benchmark utilities
Tests/               # regression harness, separate from app startup
docs/bugs/           # one document per user-visible regression
.build/              # ignored compiler output
.local/              # ignored runtime logs/cache
```

## What it reads

Claude Code writes one JSON object per line to:

```
~/.claude/projects/<slugified-cwd>/<session-uuid>.jsonl
```

Codex tasks write rollout events to:

```
~/.codex/sessions/<year>/<month>/<day>/rollout-<timestamp>-<task-uuid>.jsonl
```

Codex reasoning items use plaintext `content[].reasoning_text` when the provider
supplies it. Otherwise Thinkpeek displays the complete ordered `summary[]` array;
the duplicate `event_msg/agent_reasoning` entries are ignored. Full plaintext is
local display data only: the external checker receives the provider summary, and
no external check is made when a full-text item has no summary. Task starts are
progress only and never replace readable content or enter card history.
Encrypted-only records are hidden by default. Task names come from
`~/.codex/session_index.jsonl`. Auto mode follows both Claude and Codex, and the
picker labels every source explicitly.

This covers Codex CLI/app agent tasks that create local rollout files. It does
not claim access to ordinary consumer ChatGPT conversations that do not create
those files.

Assistant records carry a `message.content` array; reasoning appears as:

```json
{"type": "thinking", "thinking": "…", "signature": "CAISuwYKhwEIEBgC…"}
```

Claude `message.content[].thinking` text is displayed completely when present.
**That stored text may itself be a provider-generated reasoning summary rather
than raw chain-of-thought.**
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
Every text replacement and reopen synchronously resets the ticker to position
zero before a new animation is installed, preventing mid-message or blank starts.
Ticker movement redraws the attributed string directly inside the clipped viewport
on every frame instead of translating a partially rasterized text-field bitmap.
A formatting-only or empty summary is discarded and cannot replace the last
visible message.
The ticker's top-right icon toolbar moves the window to the left, right, top, or
bottom screen edge without changing the other axis; the settings icon follows the
four position controls. The message row keeps the full ticker width below it.
The settings menu's **Alarm Color…** item opens the native macOS color picker.
The ticker remains white during normal operation and uses the selected color only
for an actual alert. Custom colors and opacity are remembered, text/icons
automatically switch contrast, and **Use Default Alarm Color** restores the
light Sticky-note yellow warning color.
A single click opens a dedicated full-message reader; **Done** or a click outside
the reader returns to the ticker. The visible controls button or a deliberate double-click opens the
separate navigation/settings view. The **↤** control returns directly to the
ticker's beginning. The settings menu selects and remembers Slow, Normal, or Fast
ticker movement and provides Top/Bottom × Left/Center/Right presets.
The reader keeps **Done** visible and places **Quit Thinkpeek** in the standard
ellipsis overflow menu because the accessory HUD has no standard application menu.
Escape from the reader, controls, or full history always returns directly to the
one-line ticker.
Controls and full history use the same lifecycle pattern: **Done** returns to the
ticker without terminating the monitor, while **Quit Thinkpeek** remains in the
ellipsis overflow menu.
The controls and full-message views can be resized horizontally from 380 to 560
points. Their width is remembered; below 500 points the header stacks into two
rows so the session selector and controls remain usable. The settings menu also
offers **Width: Narrow** and **Width: Standard** shortcuts.
Compact controls show the currently selected message beneath the toolbar in a
content-sized viewport capped at 210 points. Clicking the ticker opens the
dedicated reader, while **Show all** displays the complete history.
**Show all** opens the full scrollable feed. It has no intermediate **Collapse**
action; Escape returns directly to the ticker. Compact and full-feed widths are
hard-capped at 560 and 700 points, so
long reasoning wraps and scrolls vertically instead of stretching the window.

Auto mode follows every active session and nested agent. Use the session picker
to pin one session. Cards show the local time, source session, and original
readable reasoning. Set `THINKPEEK_HISTORY_COUNT` in `.env` to an integer, `0`,
or `all`. When a provider record has no plaintext reasoning, Thinkpeek presents
an explicit unavailable state instead of substituting its summary text.
Repeated identical records from the same source are presented once even when
the transcript records them at multiple timestamps.

### Evidence the writes are live

Observed inside a single unfinished turn: the transcript grew 50,350 → 64,814 →
70,415 bytes across three tool calls, and the `thinking` record for the reasoning
that preceded each call was already on disk, timestamped, before the turn's reply
was sent. Per-record `timestamp` fields advance monotonically within the turn.

## The drift alarm

The native Thinkpeek app sends each new readable reasoning summary, plus your
locally saved evaluation instruction, to a fast model. Tool calls and tool
results are discarded by the transcript parser and never enter the automatic
evaluation path. Thinkpeek does not infer actions from keywords.

The **What to Check…** editor has two explicit modes:

- **Whole text is one instruction** sends the complete text verbatim once.
- **Each non-empty line is independent** sends every line verbatim in a separate
  evaluation and alerts when any evaluation returns `true`.

No comments, categories, keywords, or trigger meanings are inferred. Edits take
effect on the next readable reasoning summary without restarting Thinkpeek.

The settings menu's **What to Check…** action edits that local value and mode directly.
There is no file-backed configuration. The next reasoning block uses the saved
rules without restarting Thinkpeek.

The ticker's checklist button opens **What to Check** directly in one click. The
sliders button remains reserved for navigation and secondary display preferences.

### Privacy audit log

Each app start resets `~/Library/Logs/Thinkpeek/privacy-audit.jsonl`. The JSONL
records only metadata: session filename, transcript record type, disposition,
byte count, and actual external reasoning-request destination/size. It records
tool calls and results as `tool_record_discarded`; it never records reasoning,
tool input, tool output, API keys, or other transcript content.

For independent-line mode, an example is:

```
Alert when Claude is guessing instead of verifying against the actual code.
Alert when Claude is about to run a destructive or irreversible command.
Alert when Claude misunderstood the request and is solving a different problem.
```

The integrated window calls providers directly: Groq first, then Cerebras as a
fallback when both are configured. There is no OpenRouter intermediary. Copy the
example and add one or both keys:

```bash
cp .env.example .env
# edit .env: GROQ_API_KEY=... and/or CEREBRAS_API_KEY=...
./.build/thinkpeek --drift-status
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

Run the complete suite with:

```bash
Scripts/test.sh
```

```bash
./.build/thinkpeek --selftest
./.build/thinkpeek --layout-selftest
./.build/thinkpeek --presentation-selftest
./.build/thinkpeek --source-context-selftest
./.build/thinkpeek --ticker-selftest
./.build/thinkpeek --ticker-background-selftest
./.build/thinkpeek --message-view-selftest
./.build/thinkpeek --escape-selftest
./.build/thinkpeek --exit-controls-selftest
./.build/thinkpeek --outside-click-selftest
./.build/thinkpeek --window-position-selftest
./.build/thinkpeek --ticker-corner-selftest
./.build/thinkpeek --provider-icon-selftest
./.build/thinkpeek --settings-menu-selftest
./.build/thinkpeek --check-rules-editor-selftest
./.build/thinkpeek --window-chrome-selftest
./.build/thinkpeek --compact-width-selftest
./.build/thinkpeek --interaction-selftest
./.build/thinkpeek --ui-command-api-selftest
```

prints the active transcript and its last 5 reasoning blocks — no window involved.
The layout check verifies fixed-width full-card wrapping; the ticker check verifies
that the resting message stays on one vertically contained line when it overflows.

Engine tests cover: backfill, live append, sealed-block flagging, partial-line
safety, and partial-line rejoin. All 5 pass against a real transcript.

The window presentation is also exposed as a headless JSON API. The AppKit
renderer and automated tests consume the same `UIEvent` objects:

```bash
./.build/thinkpeek --ui-json ~/.claude/projects/<project>/<session>.jsonl
```

The running window publishes the state it actually consumed at the local
endpoint `http://127.0.0.1:17321/ui` (override with
`THINKPEEK_API_PORT`). This makes window title, selection, status, analysis,
omitted blocks, activity, and drift results assertable without screen capture.
The companion `http://127.0.0.1:17321/screenshot` endpoint returns a PNG rendered
by the running AppKit window, so layout and scrolling can be checked end to end.
`/message`, `/controls`, `/close`, `/quit`, `/hide`, `/previous`, `/next`,
`/restart-ticker`,
`/speed/slow`, `/speed/normal`, `/speed/fast`, `/background/blue`,
`/background/system`, `/width/narrow`, `/width/standard`, and
`/corner/top-left`, `/corner/top-right`, `/corner/bottom-left`,
`/corner/bottom-right`, and
`/toggle-expanded` exercise the same reader, settings, and carousel paths as the
visible UI, allowing every presentation state to be tested through the complete
running window. `/reveal` remains an alias for `/controls` for compatibility.
Use `./.build/thinkpeek --transcript /absolute/session.jsonl` to pin a deterministic
input for an end-to-end UI test.

For a direct native evaluator check:

```bash
./.build/thinkpeek --drift-status
./.build/thinkpeek --check "I'll remove the build directory now."
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

That standalone alarm is now retired. `Scripts/watch.py` remains only as a
compatibility wrapper for native one-shot checks and contract tests; it contains
no separate prompt, input interpretation, or evaluator.

Two things made the window bug slow to diagnose and are worth remembering: `tk.Tk()` blocks
forever from a sandboxed/background shell (ignoring even `SIGALRM`), and
`screencapture` there fails with *"could not create image from display"*. Any GUI
change has to be verified by launching from a real Terminal in an Aqua session.
