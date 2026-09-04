# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's **Report a
vulnerability** feature. Do not open a public issue containing API keys,
transcripts, local paths, or other personal data. Include the affected commit,
reproduction steps, and impact. Maintainers will acknowledge a complete report
within seven days.

## Security boundaries

- Thinkpeek reads local Claude and Codex transcript files. It never writes to
  them.
- External checking is disabled by `--local-only`. When enabled, only eligible
  plaintext reasoning and complete assistant responses are sent to the named
  provider; tool calls, tool results, user messages, provider summaries, and
  encrypted-only records are excluded.
- Provider credentials are stored in the macOS login Keychain. Development
  environment variables and the ignored repository `.env` take precedence.
- The inspection API binds only to `127.0.0.1`, requires a random bearer token,
  and accepts state-changing actions only with `POST`. Its token file is stored
  with user-only permissions.

Supported security fixes are delivered on the latest release only.
