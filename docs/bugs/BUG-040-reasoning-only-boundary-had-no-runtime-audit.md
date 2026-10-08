# BUG-040: Reasoning-only boundary had no runtime audit

## Symptom

After the tool-record privacy regression, there was no independent runtime record
showing what Doublethink selected, discarded, or sent after launch.

## Fix

Add a per-launch JSONL audit at
`~/Library/Logs/Doublethink/privacy-audit.jsonl`. It records:

- app start and declared `reasoning_only` scope;
- selected readable reasoning metadata;
- encrypted reasoning withheld from evaluation;
- duplicate Codex reasoning events discarded in favor of complete arrays;
- tool-call and tool-result records discarded;
- actual external reasoning request destination and serialized envelope size.

The audit never stores transcript content, instructions, tool arguments/results,
credentials, or model responses. The file is created with owner-only permissions.

## Verification

The audit self-test supplies recognizable secret strings as tool output and
reasoning content. It requires the correct dispositions and external-request
metadata while requiring both secret strings to be absent from the log.
