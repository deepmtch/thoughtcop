# ThoughtCop reference

Everything about how ThoughtCop works, for developers and the curious. The short version is in the [README](../README.md).

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
supplies it. When Codex supplies only a readable `summary[]`, ThoughtCop displays
the complete summary locally; duplicate `event_msg/agent_reasoning` entries are
ignored. Plaintext reasoning is displayed locally and sent verbatim to the
configured external checker. Provider summaries are local-display-only and are
never sent. Complete assistant responses are evaluated but are not presented as
thoughts; a response appears in ThoughtCop only when it triggers a violation or
its check fails. Each checked record is sent with your latest typed request
from the same session (cut to its first and last 1,000 characters when longer
than 2,000). Tool calls, tool results, other user-role records, and
encrypted-only records are not sent. Task starts are progress only and never replace readable
content or enter card history.
Encrypted-only records are hidden by default. Task names come from
`~/.codex/session_index.jsonl`. Auto mode follows both Claude and Codex, and the
picker labels every source explicitly. When multiple sessions are active, the
ticker names every working/waiting session instead of hiding all but the most
recently updated source.

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
recovered retroactively, and a host application can explicitly override the
setting. ThoughtCop reports operation start immediately and displays readable
reasoning only when plaintext exists; response checking does not depend on that
optional stream.

## The window and settings

### The ticker

- A resizable, always-on-top, borderless row 28 points high: provider icon, chat name, scrolling text, then **History**, **Settings** and **Hide**.
- At a top position it touches the menu bar; only the bottom corners are rounded.
- Long text pauses at the start, scrolls, pauses at the end and returns. With **Reduce Motion** on it stays still.
- Hover never changes the UI. Clicking the text opens the reader.
- Every new text restarts the scroll from position zero, so it never starts mid-message or blank. An empty or formatting-only summary never replaces the last visible message.
- Six positions are in **Settings › General › Position**, and the window can be dragged.
- **Hide ThoughtCop** (the X) is remembered across restarts. Menu bar › **Show ThoughtCop** brings it back; **Quit ThoughtCop** is also in the menu bar.

### Reader and history

- A single click opens the full-message reader. **Done**, a click outside it, or Escape returns to the ticker.
- **History** shows all items, violations and the archive, with the session picker. Its header has an **All | Violations N** filter. **Done** or Escape returns to the ticker without stopping the monitor.
- Widths are capped at 560 points (ticker) and 700 points (history), so long reasoning wraps and scrolls instead of stretching the window.
- A violation opened from the bubble or the menu bar returns to hidden when closed, if the ticker was hidden.

### Keyboard

| Key | Action |
|---|---|
| Left, Up, K | previous message |
| Right, Down, J | next message |
| Home / End | first / latest message |
| Return, Space | open the selected message |
| Escape | back to the ticker |
| Command-Shift-V | open violations |

Text fields and standard controls keep their normal behaviour for these keys.

### Settings

One **Settings** window, opened with **Settings… (⌘,)** in the menu-bar menu or either ⚙ button.

- **General:** scroll speed (Slow, Normal, Fast), ticker width (Narrow, Standard), position, violation color. Applies immediately. **Choose…** opens the macOS color picker; **Use Default** restores red.
- **Alerts:** applies immediately.
  - **Flash menu-bar icon red** (on by default) turns brain, bolt and count red for 3 seconds when a violation arrives.
  - **Show bubble** (off by default) shows the session and the quoted evidence under the icon for 5 seconds, after the flash when both are on. Clicking it opens the violation. If macOS has hidden the icon, the bubble appears at the top right.
  - **Confirm with second check** and the violation history size.
  - Alerts never change the ticker selection, a hidden window or an open view, and never play a sound.
- **Rules** and **Keys:** with **Revert** and **Save**.

The ticker always uses the normal macOS window surface; a violation never changes its background.

### Sessions

- Auto mode follows every active session and nested agent; the session picker pins one.
- Cards show local time, source session and the original readable reasoning.
- `THOUGHTCOP_HISTORY_COUNT` in `.env` sets how many past summaries load on start: an integer, `0`, or `all`.
- When a record has neither readable reasoning nor a readable summary, ThoughtCop shows that explicitly.
- Identical records from the same source are shown once.

### Evidence the writes are live

Observed inside a single unfinished turn: the transcript grew 50,350 → 64,814 →
70,415 bytes across three tool calls, and the `thinking` record for the reasoning
that preceded each call was already on disk, timestamped, before the turn's reply
was sent. Per-record `timestamp` fields advance monotonically within the turn.

## The drift alarm

The native ThoughtCop app sends each new complete assistant response and each new
readable reasoning record, plus your locally saved evaluation instruction and the
latest request you typed before that record, to a fast model. Tool calls and tool results are discarded by the transcript parser
and never enter the automatic evaluation path. ThoughtCop does not infer actions
from keywords.

The **Settings › Rules** editor has two explicit modes:

- **Whole text is one instruction** sends the complete text verbatim once.
- **Each non-empty line is independent** sends every line verbatim in a separate
  evaluation and alerts when any evaluation returns `true`.

No comments, categories, keywords, or trigger meanings are inferred. Edits take
effect on the next assistant response or readable reasoning record without
restarting ThoughtCop.

### Violation history

Every reported violation must quote evidence. With **Settings › Alerts › Confirm
with second check** on (the default), ThoughtCop sends the claim, its evidence,
your instruction, the original record and your request to the same model and
asks whether the claim is true. Only confirmed violations are shown and stored;
rejected or evidence-free claims are dropped. Turn the setting off to show the
first verdict directly.

Each shown violation is appended to the local 0600-permission store at
`~/Library/Application Support/ThoughtCop/violations.json`. **Violation History**
in the display settings keeps the newest 10, 25, 50 (default), 100, 250 or 500
violations; lowering it deletes the oldest immediately. A record preserves
the source provider/session, time, matched reason, quoted evidence, original
evidence record, evaluator provider, latency, and the exact check prompt in
force.
Every new violation updates the unread menu-bar count and gives its brain an
alert tint. By default it does not interrupt the ticker, play a sound, or post a
VoiceOver announcement. With the flash or the bubble on, it posts a VoiceOver
announcement; the bubble states the violation in words (never color alone).

The menu-bar brain carries the new-violation count and a bolt while any is unreviewed. **Open Violation History…**
opens the violation list even after the ticker has been hidden or the app has
restarted; **Show Last Violation**, directly below it, opens the newest
violation in the reader. Resting the mouse on the menu-bar icon for half a
second shows the last violation in the bubble; click it to open it.
Each violation gets a one-line summary from a separate request after it is
recorded (it never affects the decision). The reader, the bubble and the
history row show the summary first; the reader keeps the quote below and
"Why and full message ▸" one click away. History has three tabs: **All**, **Violations** (those
whose transcript record is less than one hour old) and **Archive** (older ones,
moved there at the exact one-hour mark even while history is open). The
retention limit covers both tabs together, and archiving does not mark a
violation reviewed. The same state is available through `/ui`; `/violations`,
`/last-violation`, `/filter/all`, `/filter/violations` and `/filter/archive`
drive the same actions without clicking the UI.

**Settings › Rules** edits that local value and mode directly.
There is no file-backed configuration. The next response or reasoning block uses
the saved rules without restarting ThoughtCop.

Every ⚙ button and menu bar › **Settings…** open the same window.

### Privacy audit log

Each app start resets `~/Library/Logs/ThoughtCop/privacy-audit.jsonl`. The JSONL
records only metadata: session filename, transcript record type, disposition,
byte count, and actual external evaluation destination/size. It distinguishes
reasoning requests from assistant-response requests and records tool calls and
results as `tool_record_discarded`; it never records reasoning, response text,
tool input, tool output, API keys, or other transcript content.

For independent-line mode, an example is:

```
Alert when Claude is guessing instead of verifying against the actual code.
Alert when Claude is about to run a destructive or irreversible command.
Alert when Claude misunderstood the request and is solving a different problem.
```

The integrated window calls providers directly: Groq first, then Cerebras as a
fallback when both are configured. There is no OpenRouter intermediary. For an
installed app, use the menu-bar **Settings › Keys** editor. For a
development checkout, environment variables or the ignored `.env` file are
explicit overrides:

```bash
cp .env.example .env
chmod 600 .env
# edit .env: GROQ_API_KEY=... and/or CEREBRAS_API_KEY=...
./.build/thoughtcop --drift-status
```

`.env` is ignored by git; `.env.example` contains only empty placeholders and
model defaults. Process environment and a development checkout's `.env` take
precedence over Keychain values. `--local-only` is the explicit no-network
mode. The status line and `/ui` API report whether external analysis is enabled
and name the exact direct provider, but never expose credentials. Every live card changes from
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
6. **Handle sealed blocks explicitly.** Signature-only reasoning is excluded;
   it is never presented as if readable analysis existed.
7. **Always on top,** across Spaces and over full-screen apps, without stealing focus.
8. **Read-only.** Never write to, lock, or truncate a transcript, and never
   create anything under `~/.claude/`.
9. **Never silently drop a block.** A reasoning block that arrives split across
   two writes must still be shown and still be scored — a missed block is a
   missed alarm.

### Non-functional

- **Native build.** Builds with the `swiftc` in Xcode Command Line Tools and
  produces both a command-line test binary and a minimal `.app` bundle. It uses
  Apple system frameworks; `zstd` is required for Claude Desktop cache support.
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

Run the opt-in real Claude CLI → transcript → ThoughtCop API latency probe with:

```bash
python3 Scripts/test_live_claude_api.py
```

It invokes one tool-free authenticated Claude CLI turn with a small budget cap, polls the
local ThoughtCop API without clicking the UI, and fails unless the matching
Claude session reaches the ticker as `Working…` before the CLI turn finishes.

```bash
./.build/thoughtcop --selftest
./.build/thoughtcop --claude-desktop-conversation-selftest
./.build/thoughtcop --layout-selftest
./.build/thoughtcop --presentation-selftest
./.build/thoughtcop --source-context-selftest
./.build/thoughtcop --ticker-selftest
./.build/thoughtcop --ticker-background-selftest
./.build/thoughtcop --message-view-selftest
./.build/thoughtcop --escape-selftest
./.build/thoughtcop --exit-controls-selftest
./.build/thoughtcop --outside-click-selftest
./.build/thoughtcop --window-position-selftest
./.build/thoughtcop --ticker-corner-selftest
./.build/thoughtcop --provider-icon-selftest
./.build/thoughtcop --settings-menu-selftest
./.build/thoughtcop --check-rules-editor-selftest
./.build/thoughtcop --window-chrome-selftest
./.build/thoughtcop --compact-width-selftest
./.build/thoughtcop --interaction-selftest
./.build/thoughtcop --ui-command-api-selftest
```

prints the active transcript and its last 5 reasoning blocks — no window involved.
The layout check verifies fixed-width full-card wrapping; the ticker check verifies
that the resting message stays on one vertically contained line when it overflows.

Engine tests cover: backfill, live append, sealed-block flagging, partial-line
safety, and partial-line rejoin. All 5 pass against a real transcript.

The window presentation is also exposed as a headless JSON API. The AppKit
renderer and automated tests consume the same `UIEvent` objects:

```bash
./.build/thoughtcop --ui-json ~/.claude/projects/<project>/<session>.jsonl
```

The running window publishes the state it actually consumed at the local
endpoint `http://127.0.0.1:17321/ui` (override with
`THOUGHTCOP_API_PORT`). Every request requires `Authorization: Bearer <token>`;
the random token is stored with mode `0600` at
`~/Library/Application Support/ThoughtCop/ui-api-token`. This makes window title,
selection, status, analysis, omitted blocks, activity, and drift results
assertable without screen capture.
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
`/ui` and `/screenshot` use `GET`; every action endpoint uses `POST`. The server
binds only to IPv4 loopback and returns no-store responses.

```bash
token=$(<"$HOME/Library/Application Support/ThoughtCop/ui-api-token")
printf 'Authorization: Bearer %s\n' "$token" | \
  curl --header @- http://127.0.0.1:17321/ui
printf 'Authorization: Bearer %s\n' "$token" | \
  curl --header @- -X POST http://127.0.0.1:17321/controls
```
Use `./.build/thoughtcop --transcript /absolute/session.jsonl` to pin a deterministic
input for an end-to-end UI test.

For a direct native evaluator check:

```bash
./.build/thoughtcop --drift-status
./.build/thoughtcop --check "I'll remove the build directory now."
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

## Building, releases and the commit hook

`build.sh` intentionally creates an ad-hoc signed development bundle. It is not
a distributable release. A direct-download release requires an installed
Developer ID Application certificate and a validated `notarytool` keychain
profile:

```bash
export THOUGHTCOP_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)'
export THOUGHTCOP_NOTARY_PROFILE='thoughtcop-notary'
./Scripts/release.sh
```

The release command fails before building if either credential is unavailable.
It signs with hardened runtime and a secure timestamp, waits for Apple to accept
the notarization, staples and validates the ticket, runs Gatekeeper assessment,
then creates a final ZIP and SHA-256 checksum under `.build/releases/`.

This checkout uses the repository-managed `.githooks/post-commit` hook. After
each successful commit it rebuilds and replaces the running ThoughtCop exactly
once, only when that build succeeds. The build produces a minimal macOS app
bundle and the hook opens it through LaunchServices; it deliberately does not
register a restartable `launchd` service. Inspect
`.local/post-commit/restart.log` if a restart does not complete. Install the hook
for a fresh clone with:

```bash
git config core.hooksPath .githooks
```

ThoughtCop is a native Swift/AppKit app. Building requires Xcode Command Line
Tools; Claude Desktop cache monitoring and its tests require `zstd`
(`brew install zstd`). Python 3 is used only by the test and compatibility
scripts. **Nothing is ever written under `~/.claude/`** — that directory is
Claude Code's, and ThoughtCop only reads its supported session data.

### Project layout

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
docs/LESSONS-LEARNED.md # mandatory regression-prevention rules
.build/              # ignored compiler output
.local/              # ignored runtime logs/cache
```
