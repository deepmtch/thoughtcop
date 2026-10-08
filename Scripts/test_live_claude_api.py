#!/usr/bin/env python3
"""Real Claude CLI -> transcript -> Thoughtcrime API latency probe.

This is intentionally opt-in because it invokes the user's authenticated Claude
CLI and may consume a small amount of model usage. It never clicks the UI.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path


API_URL = os.environ.get("THOUGHTCRIME_UI_URL", "http://127.0.0.1:17321/ui")
TIMEOUT = float(os.environ.get("THOUGHTCRIME_LIVE_TEST_TIMEOUT", "60"))
CLAUDE = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
API_TOKEN_PATH = Path(os.environ.get(
    "THOUGHTCRIME_UI_API_TOKEN_PATH",
    Path.home() / "Library/Application Support/Thoughtcrime/ui-api-token",
))


def api_state() -> dict:
    token = os.environ.get("THOUGHTCRIME_UI_API_TOKEN") or API_TOKEN_PATH.read_text().strip()
    request = urllib.request.Request(
        API_URL, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def locate_transcript(session_id: str) -> Path | None:
    root = Path.home() / ".claude" / "projects"
    matches = list(root.rglob(f"{session_id}.jsonl"))
    return matches[0] if matches else None


def transcript_milestones(path: Path | None) -> dict[str, bool]:
    result = {"created": path is not None, "activity": False, "readableThinking": False}
    if path is None:
        return result
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return result
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get("type") in {"queue-operation", "assistant", "system"}:
            result["activity"] = True
        if record.get("type") == "assistant":
            for item in record.get("message", {}).get("content", []):
                if item.get("type") == "thinking" and str(item.get("thinking", "")).strip():
                    result["readableThinking"] = True
    return result


def main() -> int:
    session_id = str(uuid.uuid4())
    session_name = f"Thoughtcrime live API probe {session_id[:8]}"
    command = [
        CLAUDE,
        "-p",
        "--session-id", session_id,
        "--name", session_name,
        "--output-format", "stream-json",
        "--verbose",
        "--safe-mode",
        "--max-budget-usd", "0.25",
        (
            "This is a local UI integration probe. Do not use tools. Briefly analyze "
            "why deterministic black-box testing is useful, then finish with the exact "
            "marker THOUGHTCRIME_LIVE_PROBE_COMPLETE."
        ),
    ]
    started = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=Path(__file__).resolve().parents[1],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    transcript_seen: float | None = None
    activity_seen: float | None = None
    api_seen: float | None = None
    matching_state: dict = {}
    transcript: Path | None = None
    deadline = started + TIMEOUT

    while time.monotonic() < deadline:
        now = time.monotonic()
        transcript = transcript or locate_transcript(session_id)
        milestones = transcript_milestones(transcript)
        if milestones["created"] and transcript_seen is None:
            transcript_seen = now
        if milestones["activity"] and activity_seen is None:
            activity_seen = now
        try:
            state = api_state()
            source = str(state.get("peekSource", ""))
            if source == f"Claude · {session_name}" and api_seen is None:
                api_seen = now
                matching_state = {
                    "peekSource": source,
                    "peekText": state.get("peekText"),
                    "operationPending": state.get("operationPending"),
                    "windowVisible": state.get("windowVisible"),
                }
        except Exception:
            pass
        if process.poll() is not None:
            break
        time.sleep(0.05)

    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
    stdout, stderr = process.communicate()
    finished = time.monotonic()
    stream_result: dict = {}
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "result":
            stream_result = {
                "subtype": event.get("subtype"),
                "isError": event.get("is_error"),
                "result": event.get("result"),
            }
    report = {
        "sessionId": session_id,
        "claudeExitCode": process.returncode,
        "claudeDurationMs": round((finished - started) * 1000),
        "transcriptCreatedMs": None if transcript_seen is None else
            round((transcript_seen - started) * 1000),
        "transcriptActivityMs": None if activity_seen is None else
            round((activity_seen - started) * 1000),
        "thoughtcrimeApiMs": None if api_seen is None else round((api_seen - started) * 1000),
        "thoughtcrimeState": matching_state,
        "readableThinkingPersisted": transcript_milestones(transcript)["readableThinking"],
        "claudeCompleted": "THOUGHTCRIME_LIVE_PROBE_COMPLETE" in stdout,
        "claudeResult": stream_result,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    if process.returncode != 0:
        print(stderr[-2000:], file=sys.stderr)
        return 1
    if activity_seen is None or api_seen is None:
        return 1
    if api_seen >= finished:
        return 1
    if matching_state.get("peekText") != "Working…":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
