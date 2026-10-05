# BUG-104 — Violation texts were too long to scan

## Evidence

The user's screenshot (2026-10-05): a violation in the reader showed a
four-line quote, a five-line "Why" and the full message. The user: "the texts
are sometimes too long … we need an executive summary … try it out first in
isolation before you make suggestions".

## Experiment

Run on the user's last 15 real violations, with `qwen/qwen3.8-27b` on Groq and
the user's two rules, one call per rule line
(scratchpad `summary_exp*.py`):

| Variant | Decisions unchanged | Summaries |
|---|---|---|
| A: `summary` field added to the check | 15/15 | vague, mostly repeating the rule ("chose a workaround without asking") |
| A with sharper wording (name the concrete action) | **14/15**, one new alert | specific |
| B: separate request after the decision | not involved | specific ("switched to Pillow without asking…"); about 0.4 s and 480 in / 21 out tokens |
| C: `summary` field added to the second check | **7/10** verdicts unchanged | vague |

The user agreed to B.

## Fix

- **Separate request.** `summarizeViolation` runs after `showAlert` has
  stored the violation, so it is outside `checkDrift` and cannot change a
  decision. It sends the record, the rules, and the violation's reason and
  quote, with no user request, and asks for "one plain sentence of at most 15
  words saying what the AI did". It falls back to the next backend like a
  check, and is audited with purpose `summary`. Its tokens are counted in
  usage without counting as a check.
- **Stored and shown.** `ViolationRecord.summary` is stored. The reader shows
  it in bold first, then the quote, then "Why and full message ▸"; the link
  expands the rest and the reader grows to fit. The bubble (alert and hover)
  and the history row's second line show the summary instead of the quote.
- **Before it arrives.** Until the summary arrives, or when the request fails,
  everything shows the quote as before. Old violations keep their quote.

## Verification

- **Screens:** `capture_screens.py` checks that the bubble shows the summary,
  that the reader starts with the summary and has the link but not Why, and
  that after `/reader/violation-details` the reader shows Why and the full
  message and grows.
- **Black box:** the multi-session e2e checks that every recorded violation
  gets its summary from the dummy checker, and that the reader text starts
  with it.
- **Host run:** the full suite passes on the host, and the reader, the
  expanded reader and the history were reviewed by eye.
