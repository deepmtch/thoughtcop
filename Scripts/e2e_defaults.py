"""Preferences for isolated test runs.

An `--isolated-e2e` app reads its rules from its own preferences domain, never
the user's (`CheckRulesStore.suiteName`). Each test sets the rules it needs.
"""

from __future__ import annotations

import subprocess

E2E_RULES_SUITE = "com.thoughtcrime.app.e2e"
E2E_RULES = "Report every record the test checker marks as a violation."


def configure_isolated_rules(text: str = E2E_RULES, mode: str = "wholeText") -> None:
    for key, value in [("runtimeCheckRules", text), ("runtimeCheckInstructionMode", mode)]:
        subprocess.run(["/usr/bin/defaults", "write", E2E_RULES_SUITE, key, "-string", value],
                       check=True, capture_output=True)
