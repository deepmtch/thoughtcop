#!/usr/bin/env python3
"""Exact-structure canary copies of real Claude Code and Codex transcripts.

A canary copy keeps every record, key, nesting level, array length, number,
boolean, null, and record order of the real transcript. Each non-empty string
value is replaced by a unique token (``CANARY_000001``) unless its JSON path is
listed in KEEP_PATHS. Empty and whitespace-only strings stay verbatim, because
the parser treats them differently from readable text.

KEEP_PATHS is not a guess about which values look structural. It lists exactly
the string values Thinkpeek's parser compares or validates:

- Transcript.swift ``blocks(in:)``: top-level ``type``, ``subtype`` and
  ``operation``; Codex ``payload.type``, ``payload.role``, ``payload.phase``,
  ``payload.content[*].type`` and ``payload.summary[*].type``; Claude
  ``message.content[*].type`` and ``message.content[*].name`` (compared with
  ``AskUserQuestion``).
- ``timestamp`` is replaced with a format-valid synthetic value so ordering and
  ISO-8601 parsing in Sessions.swift still work.
- Sessions.swift ``codexSessionMetadataID``: ``session_meta`` ``payload.id`` is
  replaced with a deterministic synthetic UUID because it is UUID-validated.

Object keys are kept verbatim. Any change to what the parser reads must update
KEEP_PATHS and ALLOWLIST in the same commit.

Usage:
    python3 Scripts/real_structure.py --write-fixture
        Rebuild Tests/Fixtures/real-structure/ from this Mac's real transcripts:
        the first real record of every distinct record signature, canaried.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import uuid
from pathlib import Path

CLAUDE_PROJECTS = Path(os.path.expanduser("~/.claude/projects"))
CODEX_DIRECTORIES = [Path(os.path.expanduser("~/.codex/sessions")),
                     Path(os.path.expanduser("~/.codex/archived_sessions"))]
FIXTURE_DIRECTORY = Path(__file__).resolve().parent.parent / \
    "Tests" / "Fixtures" / "real-structure"

KEEP_PATHS = {
    "$.type", "$.subtype", "$.operation",
    "$.payload.type", "$.payload.role", "$.payload.phase",
    "$.payload.content[*].type", "$.payload.summary[*].type",
    "$.message.content[*].type", "$.message.content[*].name",
}
TIMESTAMP_PATH = "$.timestamp"
CODEX_SESSION_ID_PATH = "$.payload.id"

# The documented outbound allowlist (PRIVACY.md, LESSONS-LEARNED.md), mirroring
# Transcript.swift ``blocks(in:)`` item by item. A canary in one of these fields
# must reach the checker; every other canary must not.
# (provider, record predicate, item-list getter, item type, text field)
def _payload(record: dict) -> dict:
    return record["payload"] if isinstance(record.get("payload"), dict) else {}


def _message_content(record: dict) -> list:
    message = record.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    return content if isinstance(content, list) else []


ALLOWLIST = [
    ("claude", lambda record: record.get("type") == "assistant",
     _message_content, "thinking", "thinking"),
    ("claude", lambda record: record.get("type") == "assistant" and
     record.get("isApiErrorMessage") is not True,
     _message_content, "text", "text"),
    ("codex", lambda record: record.get("type") == "response_item" and
     _payload(record).get("type") == "message" and
     _payload(record).get("role") == "assistant",
     lambda record: _payload(record).get("content") or [],
     "output_text", "text"),
    ("codex", lambda record: record.get("type") == "response_item" and
     _payload(record).get("type") == "reasoning",
     lambda record: _payload(record).get("content") or [],
     "reasoning_text", "text"),
]


class CanaryWriter:
    """Replaces string values and remembers where each canary came from."""

    def __init__(self) -> None:
        self.count = 0
        self.timestamps = 0
        self.origins: dict[str, str] = {}

    def token(self, path: str) -> str:
        self.count += 1
        value = f"CANARY_{self.count:06d}"
        self.origins[value] = path
        return value

    def synthetic_timestamp(self) -> str:
        self.timestamps += 1
        seconds, milliseconds = divmod(self.timestamps, 1000)
        minutes, seconds = divmod(seconds, 60)
        hours, minutes = divmod(minutes, 60)
        return (f"2000-01-01T{hours:02d}:{minutes:02d}:{seconds:02d}."
                f"{milliseconds:03d}Z")

    def record(self, record: dict) -> dict:
        return self.value(record, "$", record)

    def value(self, value, path: str, record: dict):
        if isinstance(value, dict):
            return {key: self.value(item, f"{path}.{key}", record)
                    for key, item in value.items()}
        if isinstance(value, list):
            return [self.value(item, f"{path}[*]", record) for item in value]
        if not isinstance(value, str):
            return value
        if not value.strip():
            return value
        if path in KEEP_PATHS:
            return value
        if path == TIMESTAMP_PATH:
            return self.synthetic_timestamp()
        if path == CODEX_SESSION_ID_PATH and record.get("type") == "session_meta":
            return str(uuid.uuid5(uuid.NAMESPACE_URL, f"thinkpeek-{value}"))
        return self.token(path)


def expected_outbound(provider: str, records: list[dict]) -> set[str]:
    expected: set[str] = set()
    for record in records:
        for entry_provider, applies, items, item_type, field in ALLOWLIST:
            if entry_provider != provider or not applies(record):
                continue
            for item in items(record):
                if not isinstance(item, dict) or item.get("type") != item_type:
                    continue
                value = item.get(field)
                if isinstance(value, str) and value.startswith("CANARY_"):
                    expected.add(value)
    return expected


def read_jsonl(path: Path) -> list[dict]:
    records: list[dict] = []
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                records.append(value)
    return records


def record_signature(record: dict) -> tuple:
    """Distinguishes record kinds by the exact fields the parser branches on."""
    payload = record.get("payload") if isinstance(record.get("payload"), dict) else {}
    message = record.get("message") if isinstance(record.get("message"), dict) else {}
    content = message.get("content")
    blocks: list[str] = []
    if isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            kind = str(block.get("type"))
            if kind == "thinking":
                text = block.get("thinking")
                kind += ":readable" if isinstance(text, str) and text.strip() \
                    else ":empty"
            blocks.append(kind)
    payload_items = []
    for key in ["content", "summary"]:
        items = payload.get(key)
        if isinstance(items, list):
            payload_items += [f"{key}:{item.get('type')}" for item in items
                              if isinstance(item, dict)]
        elif items is not None:
            payload_items.append(f"{key}:{type(items).__name__}")
    return (record.get("type"), record.get("subtype"),
            record.get("isApiErrorMessage") is True,
            type(content).__name__, tuple(sorted(set(blocks))),
            payload.get("type"), payload.get("role"), payload.get("phase"),
            tuple(sorted(set(payload_items))))


def real_claude_files() -> list[Path]:
    return sorted((Path(path) for path in glob.glob(
        str(CLAUDE_PROJECTS / "**" / "*.jsonl"), recursive=True)),
        key=lambda path: path.stat().st_mtime, reverse=True)


def real_codex_files() -> list[Path]:
    files: list[Path] = []
    for directory in CODEX_DIRECTORIES:
        files += [Path(path) for path in glob.glob(
            str(directory / "**" / "*.jsonl"), recursive=True)]
    return sorted(files, key=lambda path: path.stat().st_mtime, reverse=True)


def first_record_per_signature(files: list[Path]) -> list[dict]:
    seen: set[tuple] = set()
    selected: list[dict] = []
    for path in files:
        for record in read_jsonl(path):
            signature = record_signature(record)
            if signature in seen:
                continue
            seen.add(signature)
            selected.append(record)
    return selected


def write_fixture() -> None:
    FIXTURE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    writer = CanaryWriter()
    for name, files in [("claude.jsonl", real_claude_files()),
                        ("codex.jsonl", real_codex_files())]:
        records = [writer.record(record)
                   for record in first_record_per_signature(files)]
        if not records:
            raise SystemExit(f"no real records found for {name}")
        with (FIXTURE_DIRECTORY / name).open("w", encoding="utf-8") as stream:
            for record in records:
                stream.write(json.dumps(record, separators=(",", ":")) + "\n")
        print(f"{name}: {len(records)} records from {len(files)} real files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-fixture", action="store_true")
    if parser.parse_args().write_fixture:
        write_fixture()
    else:
        parser.print_help()
