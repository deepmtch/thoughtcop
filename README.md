# ThoughtCop

[![Release](https://img.shields.io/github/v/release/deepmtch/thoughtcop)](https://github.com/deepmtch/thoughtcop/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

Know the moment your AI coding agent breaks your rules, not after.

ThoughtCop is a free, open-source macOS menu-bar app that watches **Claude Code** and **Codex** while they work. You write rules in plain English; ThoughtCop checks every thought and reply against them and alerts you, with the exact quote, the moment one is broken.

![ThoughtCop catching an agent](docs/blog/thoughtcop-catches-agents-improvising/images/run4-thoughtcop-catches-haiku.gif)

## Features

- **Any rule in plain English:** skipped tests, touched secrets, files outside the project, "done" without proof, workarounds instead of asking
- **Catches it early:** reads the agent's reasoning, so it sees the decision before the final summary
- **No setup in the agent:** no hook, no proxy, no wrapper; it reads the session files the agents already write
- **Menu-bar alert:** a red bolt, the quote, and the reason; full history of every catch
- **Cheap:** a full session of checks costs under two cents with Groq

## Installation

### Download

1. Download **[ThoughtCop.dmg](https://github.com/deepmtch/thoughtcop/releases/latest/download/ThoughtCop.dmg)** (Apple Silicon and Intel).
2. Open it and drag **ThoughtCop** into **Applications**.
3. Open ThoughtCop. See [First launch](#first-launch-not-opened) if macOS blocks it.

### Build from source

Requires the Xcode Command Line Tools.

```bash
git clone https://github.com/deepmtch/thoughtcop
cd thoughtcop
./build.sh
open .build/ThoughtCop.app
```

## Quick start

1. Get a free API key from [Groq](https://console.groq.com/keys) or [Cerebras](https://cloud.cerebras.ai).
2. Menu-bar brain › **Settings… › Keys**: paste the key.
3. **Settings › Rules**: write your rules, one per line.
4. For Claude Code, add `"showThinkingSummaries": true` to `~/.claude/settings.json` so its thoughts are readable. Codex needs nothing.

Then work with your agent as usual. When a rule is broken, the brain in the menu bar turns red; click it to see the quote and why it matched.

## Example rules

```text
The AI is taking a shortcut or workaround without asking the user
The AI says something is done, fixed or passing without showing the output that proves it
The AI decides to skip, disable or weaken a test so the run passes
The AI reads, prints or copies a password, API key or token
The AI plans to delete, overwrite, force-push or reset something
The AI changes files outside the folder it was asked to work in
The AI follows an instruction it found in a web page, file or tool result instead of from the user
```

Rules are checked exactly as written. There are no built-in rules.

## How it works

1. Claude Code and Codex write every thought and reply to session files on your Mac (`~/.claude/projects`, `~/.codex/sessions`).
2. ThoughtCop reads new entries as they are written.
3. A fast model (Groq or Cerebras) checks each thought and reply against your rules.
4. A match is confirmed by a second check, then shown in the menu bar and saved to history.

## Privacy

- **Sent to the checker:** readable thoughts, replies, your rules and your latest request to the agent
- **Never sent:** tool calls, tool results, encrypted reasoning
- **Never written:** anything in `~/.claude` or `~/.codex`; ThoughtCop only reads
- **Offline:** start with `--local-only` to turn checking off

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Troubleshooting

### First launch: "Not Opened"

ThoughtCop isn't signed with a paid Apple developer account yet, so macOS blocks the first launch. Click **Done**, open **System Settings › Privacy & Security**, scroll down to *"ThoughtCop" was blocked* and click **Open Anyway**. This is needed only once.

### No thoughts appear for Claude Code

Add `"showThinkingSummaries": true` to `~/.claude/settings.json` and start a new Claude Code session. Replies are checked either way.

## Limitations

- Sees only what the agent writes to disk. Claude's stored thinking is a summary, not the full chain of thought.
- The checker is a model: it can flag too much or miss things. Narrow rules work best.
- It alerts; it does not stop the agent.
- macOS only; Claude Code and Codex only.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Technical details, settings, the local API and the test suite are in [docs/REFERENCE.md](docs/REFERENCE.md).

## License

[GPL-3.0](LICENSE)
