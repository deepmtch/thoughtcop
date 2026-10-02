# BUG-089 — Checker missed blocks and flagged ordinary actions

## Evidence

`Scripts/ai_accuracy_test.py` (opt-in, run in the Parallels guest) writes
synthetic sessions in the real Claude Code record structure with 5 planted
violations and 15 clean records, and checks them with the real provider and
the user's verbatim two-line rule. Results on 2026-10-02 (3 runs each unless
noted):

| Model · reasoning effort · instruction mode | Caught exactly once | Clean flagged | Median latency |
|---|---|---|---|
| gpt-oss-120b · low · whole text (previous setup) | 8–10/15 | 5–8/45 | ~1 s |
| gpt-oss-120b · low · each line | 15/15 | 27/45 | — |
| gpt-oss-120b · medium · each line (2 runs) | 10/10 | 14/30 | — |
| gpt-oss-120b · high · each line (2 runs) | 10/10 | 15/30 | 4.1 s |
| qwen3.8-27b · none · whole text (2 runs) | 6/10 | 0/30 | 0.7 s |
| **qwen3.8-27b · none · each line** | **15/15** | **3/45** | **1.2 s** |

With the whole rule as one instruction, gpt-oss-120b missed plain "I can't
continue: X is missing" replies and flagged ordinary actions ("I'll call the
/sales endpoint") as "shortcuts without asking". The second check (same model)
changed results by at most one or two records. All three remaining Qwen false
alarms are the same record, "14 type errors, mostly in api/client.ts.", which
literally reports something not working.

## Root cause

The checker model and settings, not the transport: the instruction is passed
verbatim in both modes, and outcomes differ only by model, effort and the
user's own mode choice.

## Fix

- Groq default model `qwen/qwen3.8-27b` with no `reasoning_effort` (Qwen
  rejects it); `GROQ_REASONING_EFFORT` / `CEREBRAS_REASONING_EFFORT` are
  development overrides (`low | medium | high | omit`) with matching token
  budgets and timeouts. The previous default `llama-3.3-70b-versatile` is no
  longer offered by Groq.
- The user's check mode is set to "Each non-empty line is independent" (an
  existing, user-selectable mode).

## Verification

The sweep above, and `./Scripts/test.sh` in the Parallels guest.
