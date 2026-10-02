# Privacy

Thinkpeek is a local macOS utility. It discovers and reads Claude and Codex
transcript files on the Mac so it can display provider-supplied reasoning or
summaries and monitor assistant responses.

## Data that can leave the Mac

When external checking is configured, Thinkpeek sends the exact check
instruction together with one eligible plaintext reasoning record or complete
assistant response to Groq, falling back to Cerebras when configured. Each such
request also carries the user request that record answers: the latest message
you typed before it in the same session (Claude Code `user` records with
`origin.kind` `human`; Codex `UserMessage` items), verbatim up to 2,000
characters. A longer message is cut to its first and last 1,000 characters with
a marker stating how many were removed. Those providers process the request
under their own terms and privacy policies.

Thinkpeek does not send tool calls, tool results, other user-role records
(task notifications, injected context, meta messages), readable Codex provider
summaries, or encrypted/signature-only reasoning. Use `--local-only`
to prevent all external analysis.

## Data stored locally

- Check instructions and display preferences use macOS preferences.
- Groq and Cerebras credentials use the macOS login Keychain.
- Violation history is stored at
  `~/Library/Application Support/Thinkpeek/violations.json` with user-only
  permissions.
- Content-free audit and UI API logs are stored under
  `~/Library/Logs/Thinkpeek/` with user-only permissions.
- The UI API capability is stored at
  `~/Library/Application Support/Thinkpeek/ui-api-token` with user-only
  permissions.

Deleting those Thinkpeek files and Keychain entries removes the app's local
history and credentials. Removing Thinkpeek does not delete Claude or Codex
transcripts.
