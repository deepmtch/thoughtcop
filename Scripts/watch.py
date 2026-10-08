#!/usr/bin/env python3
"""Compatibility entry point for the retired standalone terminal checker.

Evaluation now belongs to the native Doublethink executable, which preserves the
user's instruction verbatim and evaluates structured transcript evidence. This
wrapper intentionally contains no independent prompt, parser, or rule logic.
"""

import argparse
import os
import subprocess
import sys


BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARY = os.path.join(BASE, ".build", "doublethink")


def run_native(arguments):
    if not os.path.isfile(BINARY):
        sys.exit("Doublethink is not built. Run ./build.sh first.")
    return subprocess.call([BINARY, *arguments])


def main():
    parser = argparse.ArgumentParser(
        description="Compatibility wrapper for Doublethink's native evaluator."
    )
    parser.add_argument("--once", metavar="TEXT",
                        help="evaluate one reasoning-summary record")
    parser.add_argument("--selftest", action="store_true",
                        help="run the native evaluator contract tests")
    parser.add_argument("--project", help=argparse.SUPPRESS)
    parser.add_argument("--model", help=argparse.SUPPRESS)
    parser.add_argument("-v", "--verbose", action="store_true",
                        help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.once is not None:
        raise SystemExit(run_native(["--check", args.once]))
    if args.selftest:
        raise SystemExit(run_native(["--evaluator-selftest"]))

    parser.error(
        "the standalone watcher was retired; run ./restart.sh to use the "
        "native live evaluator"
    )


if __name__ == "__main__":
    main()
