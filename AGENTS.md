# Thinkpeek engineering rules

## Non-negotiable: no heuristics

Heuristics are forbidden in this repository.

- Do not guess, infer, broaden, narrow, classify, or reinterpret user-authored
  instructions, prompts, rules, configuration, or data.
- Do not add keyword matching, semantic expansion, implicit categories,
  undocumented defaults, or special cases as substitutes for the user's exact
  instruction.
- Preserve user-authored checker instructions verbatim. A transport wrapper may
  specify only the machine-readable response format; it must not change the
  meaning, scope, strictness, or trigger conditions of the user's instruction.
- Do not assume any structure in user input, including one-rule-per-line,
  keywords, sentence style, casing, or domain vocabulary, unless the user
  explicitly defines that structure.
- If the available evidence cannot answer the user's instruction, expose that
  limitation or fail visibly. Never manufacture a decision with a heuristic.
- A heuristic may be introduced only when the user explicitly requests that
  exact heuristic. Its behavior and boundaries must then be documented and
  covered by tests.

This rule applies to application code, prompts, UI behavior, tests, scripts,
fallbacks, and future changes.
