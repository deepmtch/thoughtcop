# Doublethink engineering rules

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

## Mandatory regression memory

Before changing monitoring, checker, lifecycle, or UI code, read:

- `docs/LESSONS-LEARNED.md`
- `docs/UI-CHECKLIST.md` for user-visible changes
- the relevant records in `docs/bugs/`

Every user-visible regression fix must include all of the following in the same
commit:

1. Evidence from the real provider record, running `/ui` state, or rendered UI.
2. A root-cause fix rather than a filename, timing, provider, or UI special case.
3. An automated regression at the lowest useful layer and, when behavior crosses
   process/UI boundaries, the isolated black-box suite.
4. A bug record and any new reusable lesson learned.
5. `./Scripts/test.sh`, a live `/screenshot` inspection for visual changes, and a
   verified post-commit replacement with exactly one current process.

Do not declare success from compilation, a unit test, a retry after a flaky
failure, or UI state flags alone.
