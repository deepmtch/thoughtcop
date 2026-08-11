# thinkpeek

An always-on-top macOS window that streams Claude Code's reasoning in real time.

Claude Code appends every message to a JSONL transcript as the turn happens, not
when it ends. `thinkpeek` tails the active transcript and renders each `thinking`
block the moment it lands on disk.

```bash
swiftc -O -swift-version 5 -o thinkpeek main.swift   # build once
./thinkpeek
```

Swift/AppKit, no dependencies. An earlier Python/Tk version is gone: the system
Tk is 8.5, deprecated on macOS 26+, and rendered a blank white content area —
window and title drew, content never did. See [History](#history).

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
some blocks arrive with `thinking: ""` and only a 2,600-char opaque `signature` —
those are rendered as `⟨sealed — signature only⟩`. thinkpeek shows exactly what is
on disk; it cannot recover what was never written.

### Evidence the writes are live

Observed inside a single unfinished turn: the transcript grew 50,350 → 64,814 →
70,415 bytes across three tool calls, and the `thinking` record for the reasoning
that preceded each call was already on disk, timestamped, before the turn's reply
was sent. Per-record `timestamp` fields advance monotonically within the turn.

## Requirements

### Functional

1. **Follow the active session.** Poll `~/.claude/projects/*/*.jsonl` and attach to
   the most recently modified file. Re-check every 2 s and switch automatically when
   the user moves to a different session — no restart, no configuration.
2. **Stream incrementally.** Tail by byte offset; never re-read the file from the
   start. New reasoning must appear within ~0.5 s of being written.
3. **Survive partial writes.** A line still being flushed must be buffered, not
   parsed as truncated JSON, and must render correctly once the newline arrives.
4. **Survive truncation/rotation.** If the file shrinks below the current offset,
   reset to 0 rather than seeking past the end.
5. **Backfill on attach.** Show the last 3 reasoning blocks so the window is never
   empty on launch.
6. **Distinguish sealed blocks.** Signature-only reasoning is displayed as such,
   never as empty space — the user must be able to tell "Claude thought nothing"
   from "the content was not persisted".
7. **Always on top,** across Spaces and over full-screen apps, without stealing focus.
8. **Read-only.** Never write to, lock, or truncate a transcript.

### Non-functional

- **Zero install.** Builds with the `swiftc` in Xcode Command Line Tools; links
  only AppKit and Foundation. No package manager, no runtime, no app bundle.
- **Single file**, readable in one sitting.
- **Negligible cost** — idle polling must not register in Activity Monitor.

## Testing

The tailing engine is testable headlessly; the window is not.

```bash
./thinkpeek --selftest
```

prints the active transcript and its last 5 reasoning blocks — no window involved.

Engine tests cover: backfill, live append, sealed-block flagging, partial-line
safety, and partial-line rejoin. All 5 pass against a real transcript.

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

Two things made this slow to diagnose and are worth remembering: `tk.Tk()` blocks
forever from a sandboxed/background shell (ignoring even `SIGALRM`), and
`screencapture` there fails with *"could not create image from display"*. Any GUI
change has to be verified by launching from a real Terminal in an Aqua session.
