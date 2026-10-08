# BUG-035: Size limit was misattributed and duplicated

## Symptom

A 41,245-byte tool result produced two failures saying that instruction 1 and
instruction 2 each exceeded a "32 KB provider limit."

## Evidence

The matching transcript record was an `exec` result containing the available
tool catalog. ThoughtCop rejected the serialized request locally before Groq or
Cerebras received it. The check ran inside the per-instruction loop, which
duplicated the same preflight failure.

## Cause

The 32,000-byte boundary is a local transmission-safety policy, not a documented
provider limit. It was enforced after evaluation had already branched by
instruction.

## Fix

- Serialize and measure every instruction envelope before evaluation begins.
- If any request exceeds the local boundary, emit one ThoughtCop error.
- State both the exact request size and the exact local limit.
- Do not truncate, summarize, classify, or send any part of the oversized record.

Sending larger verbatim transcript records requires an explicit user-controlled
opt-in because tool results can contain sensitive local data.

## Verification

The evaluator self-test constructs a 41,245-character tool result and verifies
that its serialized envelope is measured above the explicit local limit.
