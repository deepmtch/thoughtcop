#!/usr/bin/env python3
"""Black-box launch with the maximum retained violation history.

BUG-086: restoring 388 stored violations froze the main thread at launch for
minutes. This launches the built app with ViolationStore.maximumRecords (500)
stored records and requires the first rendered state within LAUNCH_LIMIT
seconds, with every record restored.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from e2e_defaults import configure_isolated_rules

RECORDS = 500          # ViolationStore.maximumRecords, the largest choice
# Limits derived from BUG-086 measurements: empty history launches in 0.5 s and
# renders a live record in 0.06–0.23 s; the fixed build launches 500 records in
# 2.3 s. Before the fix: no launch within 120 s, then 3 s per live record.
LAUNCH_LIMIT = 5.0
LIVE_LIMIT = 1.0
LIVE_RECORDS = 5
SCREENSHOT_DIRECTORY = os.environ.get("DOUBLETHINK_SCREENSHOT_DIR")
API_TOKEN = "violation-restore-e2e-token-000000000000"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def get_ui(port: int) -> dict:
    with socket.create_connection(("127.0.0.1", port), timeout=2) as connection:
        connection.sendall(
            f"GET /ui HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nConnection: close\r\n\r\n"
            .encode("ascii"))
        chunks = []
        while chunk := connection.recv(65_536):
            chunks.append(chunk)
    _, _, body = b"".join(chunks).partition(b"\r\n\r\n")
    return json.loads(body)


def post(port: int, path: str) -> None:
    with socket.create_connection(("127.0.0.1", port), timeout=30) as connection:
        connection.sendall(
            f"POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nContent-Length: 0\r\n"
            "Connection: close\r\n\r\n".encode("ascii"))
        while connection.recv(65_536):
            pass


def wait_ui(port: int, predicate, limit: float) -> dict:
    deadline = time.monotonic() + limit
    state: dict = {}
    while time.monotonic() < deadline:
        try:
            state = get_ui(port)
            if predicate(state):
                return state
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError("UI condition timed out")


def append_and_wait(port: int, transcript: Path, marker: str, limit: float) -> float:
    with transcript.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({
            "type": "assistant",
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds")
                .replace("+00:00", "Z"),
            "message": {"content": [
                {"type": "thinking", "thinking": marker, "signature": "s"}]}}) + "\n")
    sent = time.monotonic()
    wait_ui(port, lambda ui: marker in json.dumps(ui.get("events", [])), limit)
    return time.monotonic() - sent


def save_screenshot(port: int, name: str) -> None:
    if not SCREENSHOT_DIRECTORY:
        return
    with socket.create_connection(("127.0.0.1", port), timeout=30) as connection:
        connection.sendall(
            f"GET /screenshot HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nConnection: close\r\n\r\n"
            .encode("ascii"))
        chunks = []
        while chunk := connection.recv(65_536):
            chunks.append(chunk)
    _, _, body = b"".join(chunks).partition(b"\r\n\r\n")
    Path(SCREENSHOT_DIRECTORY, f"violation-restore-{name}.png").write_bytes(body)


def main() -> None:
    limit = float(sys.argv[1]) if len(sys.argv) > 1 else LAUNCH_LIMIT
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="doublethink-violations-") as temp:
        root = Path(temp)
        records = [{
            "id": f"00000000-0000-4000-8000-{index:012d}",
            "timestamp": f"2026-09-19T10:{index // 60 % 60:02d}:{index % 60:02d}.000Z",
            "source": f"Claude · session {index % 7}",
            "content": f"Stored violation {index}. " + "Reasoning text. " * 40,
            "reason": f"Reason {index}",
            "evidence": f"Evidence {index}",
            "provider": "Groq · llama-3.3-70b-versatile",
            "latencyMs": 400 + index,
            "checkPrompt": "Alert when the assistant is unsure.",
        } for index in range(RECORDS)]
        (root / "violations.json").write_text(json.dumps(records))
        for name in ["claude", "codex", "desktop", "cache"]:
            (root / name).mkdir()
        (root / "codex-index.jsonl").write_text("")
        environment = os.environ.copy()
        environment.update({
            "DOUBLETHINK_API_PORT": str(port),
            "DOUBLETHINK_CLAUDE_PROJECTS": str(root / "claude"),
            "DOUBLETHINK_CODEX_SESSIONS": str(root / "codex"),
            "DOUBLETHINK_CODEX_INDEX": str(root / "codex-index.jsonl"),
            "DOUBLETHINK_CLAUDE_DESKTOP_SESSIONS": str(root / "desktop"),
            "DOUBLETHINK_CLAUDE_CACHE": str(root / "cache"),
            "DOUBLETHINK_CLAUDE_DESKTOP_CACHE": str(root / "cache"),
            "DOUBLETHINK_PRIVACY_AUDIT_PATH": str(root / "privacy-audit.jsonl"),
            "DOUBLETHINK_VIOLATIONS_PATH": str(root / "violations.json"),
            "DOUBLETHINK_UI_API_LOG": str(root / "ui-api.jsonl"),
            "DOUBLETHINK_UI_API_TOKEN": API_TOKEN,
            "DOUBLETHINK_HISTORY_COUNT": "0",
        })
        # Exercise the largest selectable history limit.
        subprocess.run(["/usr/bin/defaults", "write", "doublethink",
                        "violationHistoryLimit", "-int", str(RECORDS)], check=True)
        started = time.monotonic()
        configure_isolated_rules()
        process = subprocess.Popen(
            ["./.build/doublethink", "--isolated-e2e", "--local-only"],
            env=environment, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
        state: dict = {}
        try:
            while time.monotonic() - started < limit:
                try:
                    state = get_ui(port)
                    if state.get("initialScanComplete") is True:
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(0.1)
            elapsed = time.monotonic() - started
            # Live use after launch: each new readable record must render
            # promptly with the full history present.
            transcript = root / "claude" / "project" / \
                "77777777-7777-4777-8777-777777777777.jsonl"
            transcript.parent.mkdir()
            transcript.touch()
            time.sleep(1.5)  # discovery of the new transcript
            live = [append_and_wait(port, transcript, f"LIVE_THOUGHT_{index}", limit)
                    for index in range(LIVE_RECORDS)]
            compact = get_ui(port)
            save_screenshot(port, "compact")

            expanded_started = time.monotonic()
            post(port, "/toggle-expanded")
            expanded = wait_ui(port, lambda ui: ui.get("compactMode") is False and
                               ui.get("peekMode") is False, limit)
            expand_seconds = time.monotonic() - expanded_started
            save_screenshot(port, "history-all")
            # Known limit (BUG-086): measured, not bounded tightly.
            expanded_live = append_and_wait(port, transcript, "EXPANDED_THOUGHT", 30)

            # The stored records are from 2026-09-19, so they are under Archive.
            post(port, "/filter/archive")
            seen_states = []

            def violations_shown(ui: dict) -> bool:
                seen_states.append((ui.get("historyFilter"), ui.get("compactMode"),
                                    ui.get("peekMode"), ui.get("messageMode"),
                                    ui.get("visibleCardCount")))
                return ui.get("historyFilter") == "archive" and \
                    ui.get("compactMode") is False and ui.get("peekMode") is False
            violations = wait_ui(port, violations_shown, limit)
            print("filter states:", sorted(set(seen_states), key=str))
            save_screenshot(port, "history-violations")
            post(port, "/filter/all")
            post(port, "/close")
            closed = wait_ui(port, lambda ui: ui.get("compactMode") is True, limit)
            after_close = append_and_wait(port, transcript, "AFTER_CLOSE_THOUGHT", limit)
        finally:
            # Keep the command log (each command's origin: http or appKit), so
            # an unexpected state can be traced to its cause.
            log = root / "ui-api.jsonl"
            if log.exists():
                Path(".local").mkdir(exist_ok=True)
                (Path(".local") / "last-restore-ui-api.jsonl").write_text(log.read_text())
            subprocess.run(["/usr/bin/defaults", "delete", "doublethink",
                            "violationHistoryLimit"], capture_output=True, check=False)
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
    print(f"launch with {RECORDS} stored violations: {elapsed:.1f} s")
    print("ticker live record latencies: " +
          ", ".join(f"{value:.2f} s" for value in live + [after_close]))
    print(f"open full history: {expand_seconds:.1f} s; live record while open: "
          f"{expanded_live:.2f} s (known limit, BUG-086)")
    assert state.get("initialScanComplete") is True, \
        f"app did not finish launching within {limit:.0f} s"
    assert elapsed < LAUNCH_LIMIT, f"launch took {elapsed:.1f} s"
    assert state.get("violationCount") == RECORDS, state.get("violationCount")
    assert max(live + [after_close]) < LIVE_LIMIT, live + [after_close]
    # Only the displayed card is in the window's layout; all are retained.
    # cardCount also counts system status cards and the violation empty state.
    assert compact["cardCount"] >= RECORDS + LIVE_RECORDS, compact["cardCount"]
    assert compact["attachedCardCount"] <= 2, compact["attachedCardCount"]
    assert expanded["visibleCardCount"] == RECORDS + LIVE_RECORDS, \
        expanded["visibleCardCount"]
    ambient = [line for line in (Path(".local") / "last-restore-ui-api.jsonl")
               .read_text().splitlines() if '"origin":"appKit"' in line]
    assert not ambient, f"real input reached the isolated app: {ambient[:3]}"
    assert violations["visibleCardCount"] == RECORDS, violations["visibleCardCount"]
    assert closed["attachedCardCount"] <= 2, closed["attachedCardCount"]
    # BUG-088: hidden views must not hold the history wider than its window.
    for state in [expanded, violations]:
        assert state["scrollViewportWidth"] <= state["windowWidth"], \
            (state["scrollViewportWidth"], state["windowWidth"])
        assert state["windowWidth"] == 380, state["windowWidth"]
    print("violation restore launch passed")


if __name__ == "__main__":
    main()
