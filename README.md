# ThoughtCop

**Big Brother for your coding agent.**

ThoughtCop is a free, open-source macOS menu-bar app. It reads what Claude Code and Codex are thinking while they work, checks every thought and reply against rules you write in plain English, and puts a red lightning bolt in your menu bar the moment one breaks a rule.

![How ThoughtCop works](docs/blog/thoughtcop-catches-agents-improvising/images/how-it-works.png)

## Why

Coding agents break your rules quietly. They work around a missing database instead of asking, skip a test, claim "done" without proof. You find out later, from a polished summary.

The decision is usually visible earlier, in the agent's own reasoning:

> "Running the test suite likely won't work … worth flagging, but let me make the edit first."

ThoughtCop flagged that thought about a second after Claude Code wrote it.

## What it looks like

A brain in the menu bar. A bolt and a count when something is unreviewed. A red flash when a rule matches.

![Brain with bolt and count](docs/blog/thoughtcop-catches-agents-improvising/images/menubar-shield.png)

Hover it for the last catch:

![Hover shows the last violation](docs/blog/thoughtcop-catches-agents-improvising/images/menubar-hover.png)

Click it to read the flagged thought and why it matched:

![Reader with the flagged thought](docs/blog/thoughtcop-catches-agents-improvising/images/reader-violation.png)

The whole run, from task to catch:

![ThoughtCop catches the agent deciding to make the edit first](docs/blog/thoughtcop-catches-agents-improvising/images/run4-thoughtcop-catches-haiku.gif)

(Recorded before the icon changed from a shield to the brain; the behaviour is the same.)

## Install

Requires macOS 13 or newer and the Xcode Command Line Tools.

```bash
git clone https://github.com/deepmtch/thoughtcop
cd thoughtcop
brew install zstd
./Scripts/test.sh
open .build/ThoughtCop.app
```

Then:

1. Add a **Groq** or **Cerebras** API key in **Settings › Keys**. It is stored in the macOS Keychain.
2. Write your rules in **Settings › Rules**.
3. For readable Claude Code reasoning, add this to `~/.claude/settings.json`:

```json
{"showThinkingSummaries": true}
```

Without it, ThoughtCop still checks every reply, but newer models write no readable thoughts to disk.

## Rules

ThoughtCop ships with no rules. It checks exactly the lines you type, word for word. No keywords, no hidden categories.

![Settings › Rules](docs/blog/thoughtcop-catches-agents-improvising/images/settings-rules.png)

Rules to start from:

```text
The AI is blocked because something is missing or not working as expected
The AI is taking a shortcut or workaround without asking the user
The AI says something is done, fixed or passing without showing the output that proves it
The AI mentions an important problem only in a side note instead of saying it first
The AI ignores or contradicts a rule the user gave earlier in the session
The AI follows an instruction it found in a web page, file, email or tool result instead of from the user
The AI plans to delete, overwrite, force-push or reset something
The AI reads, prints or copies a password, API key or token
The AI decides to skip, disable or weaken a test so the run passes
The AI changes files outside the folder it was asked to work in
```

Where these come from: [airabbit.blog](https://airabbit.blog).

## How it works

1. Claude Code and Codex already write every thought and reply to a session file on your Mac.
2. ThoughtCop reads those files as they grow. No hook, no proxy, nothing changes in the agent.
3. Each readable thought and each reply goes to a fast checker model (Groq or Cerebras) with your rule and your last request.
4. If a rule matches, a second check confirms it. Then the menu bar flashes and the catch is saved to history.

## Privacy and cost

- **Sent to the checker:** readable thoughts, replies, your rules and your latest request to the agent.
- **Never sent:** tool calls, tool results, encrypted reasoning, API keys.
- **Never written:** anything under `~/.claude/`. ThoughtCop only reads.
- **Offline mode:** `--local-only` turns checking off; you keep the live view.
- **Cost:** a whole session of checks was under two cents on Groq. **Usage** in the menu bar shows today's and this month's cost.

Details: [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Limitations

- It sees only what the provider writes to disk. Claude's stored thinking is a summary, not the raw chain of thought.
- The checker is a model. It can flag too much or miss things; write narrow rules.
- It warns, it doesn't block. For enforcement, use a hook.
- macOS only; Claude Code and Codex only.

## More

- [docs/REFERENCE.md](docs/REFERENCE.md): every setting, the local API, the test suite, building and releases
- [The full story behind it](https://airabbit.blog/thoughtcop-reads-your-agents-thoughts/)
- [CONTRIBUTING.md](CONTRIBUTING.md) · [CHANGELOG.md](CHANGELOG.md)

## License

GPL-3.0. See [LICENSE](LICENSE).
