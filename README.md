# thinkpeek

See Claude Code and Codex reasoning summaries live — and get shouted at when
either the reasoning or an assistant response violates your check instruction.

Claude Code and Codex append live JSONL session events as turns run. thinkpeek
tails both sources, displays readable reasoning when the provider supplies it,
and checks complete assistant-response records even when reasoning is omitted.

| | | |
|---|---|---|
| **`.build/thinkpeek`** | always-on-top window | shows the reasoning |
| Native evaluator | drift alarm | evaluates structured records against your verbatim instruction |

```bash
./build.sh                                           # build once
./.build/thinkpeek                                   # the window
./restart.sh                                         # rebuild and replace a running copy
./.build/thinkpeek --local-only                      # never send evidence externally
```

`build.sh` intentionally creates an ad-hoc signed development bundle. It is not
a distributable release. A direct-download release requires an installed
Developer ID Application certificate and a validated `notarytool` keychain
profile:

```bash
export THINKPEEK_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)'
export THINKPEEK_NOTARY_PROFILE='thinkpeek-notary'
./Scripts/release.sh
```

The release command fails before building if either credential is unavailable.
It signs with hardened runtime and a secure timestamp, waits for Apple to accept
the notarization, staples and validates the ticket, runs Gatekeeper assessment,
then creates a final ZIP and SHA-256 checksum under `.build/releases/`.

This checkout uses the repository-managed `.githooks/post-commit` hook. After
each successful commit it rebuilds and replaces the running Thinkpeek exactly
once, only when that build succeeds. The build produces a minimal macOS app
bundle and the hook opens it through LaunchServices; it deliberately does not
register a restartable `launchd` service. Inspect
`.local/post-commit/restart.log` if a restart does not complete. Install the hook
for a fresh clone with:

```bash
git config core.hooksPath .githooks
```

Thinkpeek is a native Swift/AppKit app. Building requires Xcode Command Line
Tools; Claude Desktop cache monitoring and its tests require `zstd`
(`brew install zstd`). Python 3 is used only by the test and compatibility
scripts. **Nothing is ever written under `~/.claude/`** — that directory is
Claude Code's, and Thinkpeek only reads its supported session data.

## Install from source

```bash
git clone <repository-url>
cd thinkpeek
brew install zstd
./Scripts/test.sh
open .build/Thinkpeek.app
```

The development bundle is ad-hoc signed for the local Mac. It is not the
notarized distribution artifact. In the running app, choose **Provider
Credentials…** from the menu bar to save Groq or Cerebras keys in the macOS
login Keychain. The secure fields are never prefilled; leaving one blank keeps
its saved value. `--local-only` disables external checking entirely.

See [PRIVACY.md](PRIVACY.md) before enabling external checking and
[SECURITY.md](SECURITY.md) for the local API and disclosure boundaries.

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
docs/LESSONS-LEARNED.md # mandatory regression-prevention rules
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
supplies it. When Codex supplies only a readable `summary[]`, ThinkPeek displays
the complete summary locally; duplicate `event_msg/agent_reasoning` entries are
ignored. Plaintext reasoning is displayed locally and sent verbatim to the
configured external checker. Provider summaries are local-display-only and are
never sent. Complete assistant responses are evaluated but are not presented as
thoughts; a response appears in Thinkpeek only when it triggers a violation or
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
setting. thinkpeek reports operation start immediately and displays readable
reasoning only when plaintext exists; response checking does not depend on that
optional stream.

## Native window

The AppKit window is a resizable, always-on-top HUD rather than a terminal view.
Its borderless resting state is one 28-point row: the provider icon, the chat
name, the scrolling text, then History, Settings and Hide. At a top position it
touches the menu bar, with only its bottom corners rounded. Overflowing text pauses at the beginning,
moves horizontally, pauses at the end, and quickly returns. With macOS Reduce
Motion enabled, it remains clipped and stationary. Hover never changes the UI.
Every text replacement and reopen synchronously resets the ticker to position
zero before a new animation is installed, preventing mid-message or blank starts.
Ticker movement redraws the attributed string directly inside the clipped viewport
on every frame instead of translating a partially rasterized text-field bitmap.
A formatting-only or empty summary is discarded and cannot replace the last
visible message.
The ticker's toolbar has three actions: **History** (all items, violations and
archive, with the session picker), **Settings** and **Hide**. Clicking the text
opens the reader. Six window positions are in **Settings › General ›
Position**, and the window can be dragged.

All settings are in one **Settings** window: **Settings… (⌘,)** in the menu-bar
menu, or either ⚙ button. Its tabs are **General** (scroll speed, ticker
width, position, violation color), **Alerts** (Flash red, then show bubble;
Confirm with second check; violation history), **Rules** and **Keys**. General
and Alerts apply immediately; Rules and Keys have Revert and Save.
**Settings › General › Violation color › Choose…** opens the native macOS color picker.
The ticker always uses the semantic macOS window surface; a violation never
changes its background. The violation color colors the menu-bar flash. Custom
colors are remembered, and **Use Default** restores red.
**Settings › Alerts** has two separate switches. **Flash menu-bar icon red**
(on by default) turns the shield and count red for 3 seconds when a violation
arrives. **Show bubble** (off by default) shows a bubble under the icon for 5
seconds, after the flash when both are on, with the session and the quoted
evidence; clicking it opens that violation in the reader. If macOS has hidden
the icon (a full menu bar), the bubble appears at the top right below the menu
bar. The ticker selection, a hidden window, and open detail views are never
changed by the alert. There is no sound.
A single click opens a dedicated full-message reader; **Done** or a click outside
the reader returns to the ticker. The reader's History button opens history.
Settings › General selects and remembers Slow, Normal, or
Fast ticker movement and provides Top/Bottom × Left/Center/Right presets.
The reader keeps **Done** visible. **Hide Thinkpeek** is the ticker's direct X
action and is remembered across restarts; a violation opened from the bubble
or menu bar returns to hidden when closed, and menu bar › **Show Thinkpeek**
shows the ticker again. **Quit Thinkpeek** remains available from the menu bar.
Escape from the reader or history always returns directly to the one-line
ticker. History uses the same lifecycle pattern: **Done** returns to the ticker
without terminating the monitor. Settings › General offers **Ticker width:
Narrow** and **Standard**. History has no intermediate **Collapse** action;
Escape returns directly to the ticker. Compact and full-feed widths are
hard-capped at 560 and 700 points, so
long reasoning wraps and scrolls vertically instead of stretching the window.
The expanded header uses a native **All | Violations N** segmented filter.
Keyboard navigation follows standard list/carousel conventions: Left, Up, or K
selects the previous message; Right, Down, or J selects the next; Home and End
jump to the first and latest messages; Return or Space opens the selected
message; Escape returns to the ticker; and Command-Shift-V opens violations.
Focused text editors and standard controls retain their native arrow, Space,
Return, Home, End, J, and K behavior.

Auto mode follows every active session and nested agent. Use the session picker
to pin one session. Cards show the local time, source session, and original
readable reasoning. Set `THINKPEEK_HISTORY_COUNT` in `.env` to an integer, `0`,
or `all`. When a provider record contains neither plaintext reasoning nor a
readable summary, Thinkpeek presents an explicit unavailable state.
Repeated identical records from the same source are presented once even when
the transcript records them at multiple timestamps.

### Evidence the writes are live

Observed inside a single unfinished turn: the transcript grew 50,350 → 64,814 →
70,415 bytes across three tool calls, and the `thinking` record for the reasoning
that preceded each call was already on disk, timestamped, before the turn's reply
was sent. Per-record `timestamp` fields advance monotonically within the turn.

## The drift alarm

The native Thinkpeek app sends each new complete assistant response and each new
readable reasoning record, plus your locally saved evaluation instruction and the
latest request you typed before that record, to a fast model. Tool calls and tool results are discarded by the transcript parser
and never enter the automatic evaluation path. Thinkpeek does not infer actions
from keywords.

The **Settings › Rules** editor has two explicit modes:

- **Whole text is one instruction** sends the complete text verbatim once.
- **Each non-empty line is independent** sends every line verbatim in a separate
  evaluation and alerts when any evaluation returns `true`.

No comments, categories, keywords, or trigger meanings are inferred. Edits take
effect on the next assistant response or readable reasoning record without
restarting Thinkpeek.

### Violation history

Every reported violation must quote evidence. With **Violation Alerts → Confirm
with Second Check** on (the default), Thinkpeek sends the claim, its evidence,
your instruction, the original record and your request to the same model and
asks whether the claim is true. Only confirmed violations are shown and stored;
rejected or evidence-free claims are dropped. Turn the setting off to show the
first verdict directly.

Each shown violation is appended to the local 0600-permission store at
`~/Library/Application Support/Thinkpeek/violations.json`. **Violation History**
in the display settings keeps the newest 10, 25, 50 (default), 100, 250 or 500
violations; lowering it deletes the oldest immediately. A record preserves
the source provider/session, time, matched reason, quoted evidence, original
evidence record, evaluator provider, latency, and the exact check prompt in
force.
Every new violation updates the unread menu-bar count and gives its shield an
alert tint. By default it does not interrupt the ticker, play a sound, or post a
VoiceOver announcement. With the flash or the bubble on, it posts a VoiceOver
announcement; the bubble states the violation in words (never color alone).

The menu-bar shield carries the new-violation count. **Open Violation History…**
opens the violation list even after the ticker has been hidden or the app has
restarted; **Show Last Violation**, directly below it, opens the newest
violation in the reader. History has three tabs: **All**, **Violations** (those
whose transcript record is less than one hour old) and **Archive** (older ones,
moved there at the exact one-hour mark even while history is open). The
retention limit covers both tabs together, and archiving does not mark a
violation reviewed. The same state is available through `/ui`; `/violations`,
`/last-violation`, `/filter/all`, `/filter/violations` and `/filter/archive`
drive the same actions without clicking the UI.

**Settings › Rules** edits that local value and mode directly.
There is no file-backed configuration. The next response or reasoning block uses
the saved rules without restarting Thinkpeek.

Every ⚙ button and menu bar › **Settings…** open the same window.

### Privacy audit log

Each app start resets `~/Library/Logs/Thinkpeek/privacy-audit.jsonl`. The JSONL
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
installed app, use the menu-bar **Provider Credentials…** editor. For a
development checkout, environment variables or the ignored `.env` file are
explicit overrides:

```bash
cp .env.example .env
chmod 600 .env
# edit .env: GROQ_API_KEY=... and/or CEREBRAS_API_KEY=...
./.build/thinkpeek --drift-status
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

Run the opt-in real Claude CLI → transcript → ThinkPeek API latency probe with:

```bash
python3 Scripts/test_live_claude_api.py
```

It invokes one tool-free authenticated Claude CLI turn with a small budget cap, polls the
local ThinkPeek API without clicking the UI, and fails unless the matching
Claude session reaches the ticker as `Working…` before the CLI turn finishes.

```bash
./.build/thinkpeek --selftest
./.build/thinkpeek --claude-desktop-conversation-selftest
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
`THINKPEEK_API_PORT`). Every request requires `Authorization: Bearer <token>`;
the random token is stored with mode `0600` at
`~/Library/Application Support/Thinkpeek/ui-api-token`. This makes window title,
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
token=$(<"$HOME/Library/Application Support/Thinkpeek/ui-api-token")
printf 'Authorization: Bearer %s\n' "$token" | \
  curl --header @- http://127.0.0.1:17321/ui
printf 'Authorization: Bearer %s\n' "$token" | \
  curl --header @- -X POST http://127.0.0.1:17321/controls
```
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
