#!/usr/bin/env python3
"""Black-box test of the reader's session tabs and live / paused behaviour.

Two Claude sessions write thoughts. The reader opened on session A's newest
message follows A live; B's messages only raise B's "(N new)" count; going to
an older message pauses; "Jump to latest" resumes; a tab switches session.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from e2e_defaults import configure_isolated_rules

API_TOKEN = "reader-tabs-e2e-token-000000000000000000"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def request(port: int, method: str, path: str) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
        connection.sendall(
            f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nContent-Length: 0\r\n"
            "Connection: close\r\n\r\n".encode("ascii"))
        chunks = []
        while chunk := connection.recv(65_536):
            chunks.append(chunk)
    return b"".join(chunks).partition(b"\r\n\r\n")[2]


def wait_ui(port: int, predicate, limit: float = 15) -> dict:
    deadline = time.monotonic() + limit
    state: dict = {}
    while time.monotonic() < deadline:
        try:
            state = json.loads(request(port, "GET", "/ui"))
            if predicate(state):
                return state
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError(
        "UI condition timed out: " + json.dumps(
            {k: state.get(k) for k in ["messageMode", "readerLive", "readerTabs",
                                       "readerSelectedTab", "readerStatus",
                                       "messageReaderText", "currentIndex"]}))


def think(path: Path, text: str) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({
            "type": "assistant",
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "message": {"content": [{"type": "thinking", "thinking": text,
                                     "signature": "s"}]}}) + "\n")


def main() -> None:
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="thoughtcop-reader-tabs-") as temp:
        root = Path(temp)
        project = root / "claude" / "project"
        project.mkdir(parents=True)
        alpha = project / "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl"
        beta = project / "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jsonl"
        alpha.touch()
        beta.touch()
        desktop = root / "desktop" / "account"
        desktop.mkdir(parents=True)
        (desktop / "local_a.json").write_text(json.dumps(
            {"cliSessionId": alpha.stem, "title": "Alpha"}))
        (desktop / "local_b.json").write_text(json.dumps(
            {"cliSessionId": beta.stem, "title": "Beta"}))
        for name in ["codex", "cache"]:
            (root / name).mkdir()
        (root / "codex-index.jsonl").write_text("")
        environment = os.environ.copy()
        environment.update({
            "THOUGHTCOP_API_PORT": str(port),
            "THOUGHTCOP_CLAUDE_PROJECTS": str(root / "claude"),
            "THOUGHTCOP_CODEX_SESSIONS": str(root / "codex"),
            "THOUGHTCOP_CODEX_INDEX": str(root / "codex-index.jsonl"),
            "THOUGHTCOP_CLAUDE_DESKTOP_SESSIONS": str(root / "desktop"),
            "THOUGHTCOP_CLAUDE_CACHE": str(root / "cache"),
            "THOUGHTCOP_CLAUDE_DESKTOP_CACHE": str(root / "cache"),
            "THOUGHTCOP_PRIVACY_AUDIT_PATH": str(root / "audit.jsonl"),
            "THOUGHTCOP_VIOLATIONS_PATH": str(root / "violations.json"),
            "THOUGHTCOP_UI_API_LOG": str(root / "ui-api.jsonl"),
            "THOUGHTCOP_UI_API_TOKEN": API_TOKEN,
            "THOUGHTCOP_HISTORY_COUNT": "0",
            "THOUGHTCOP_USAGE_PATH": str(root / "usage.json"),
        })
        configure_isolated_rules()
        process = subprocess.Popen(["./.build/thoughtcop", "--isolated-e2e", "--local-only"],
                                   env=environment, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        try:
            wait_ui(port, lambda ui: ui.get("initialScanComplete") is True, 20)
            time.sleep(1.5)
            think(beta, "BETA_ONE: first beta thought.")
            wait_ui(port, lambda ui: "BETA_ONE" in json.dumps(ui.get("events", [])))
            think(alpha, "ALPHA_ONE: first alpha thought.")
            wait_ui(port, lambda ui: "ALPHA_ONE" in ui.get("peekText", ""))

            request(port, "POST", "/message")
            opened = wait_ui(port, lambda ui: ui.get("messageMode") is True)
            assert opened["readerLive"] is True, opened["readerLive"]
            assert "Alpha" in opened["readerSelectedTab"], opened["readerSelectedTab"]
            assert opened["readerTabs"][0] == "All", opened["readerTabs"]
            assert any("Beta" in tab for tab in opened["readerTabs"]), opened["readerTabs"]

            # Live: Alpha's next message replaces the reader.
            think(alpha, "ALPHA_TWO: second alpha thought.")
            wait_ui(port, lambda ui: "ALPHA_TWO" in ui.get("messageReaderText", ""))
            # Another session: counted on its tab, the reader stays.
            think(beta, "BETA_TWO: second beta thought.")
            counted = wait_ui(port, lambda ui: any(
                "Beta" in tab and "(1 new)" in tab for tab in ui.get("readerTabs", [])))
            assert "ALPHA_TWO" in counted["messageReaderText"], counted["messageReaderText"]

            # Older message: paused; a new Alpha message does not replace it.
            request(port, "POST", "/previous")
            paused = wait_ui(port, lambda ui: ui.get("readerLive") is False)
            assert "ALPHA_ONE" in paused["messageReaderText"], paused["messageReaderText"]
            assert paused["readerStatus"].startswith("❚❚ Paused · message 1 of 2"), \
                paused["readerStatus"]
            think(alpha, "ALPHA_THREE: third alpha thought.")
            # Wait until the new message is processed (counted), then check
            # that the paused reader did not move.
            still = wait_ui(port, lambda ui: any(
                "Alpha" in tab and "(1 new)" in tab for tab in ui.get("readerTabs", [])))
            assert "ALPHA_ONE" in still["messageReaderText"], still["messageReaderText"]

            # Jump to latest resumes live; a tab switches session.
            request(port, "POST", "/reader-latest")
            resumed = wait_ui(port, lambda ui: ui.get("readerLive") is True and
                              "ALPHA_THREE" in ui.get("messageReaderText", ""))
            assert not any("Alpha" in t and "new)" in t for t in resumed["readerTabs"])
            beta_index = next(i for i, tab in enumerate(resumed["readerTabs"]) if "Beta" in tab)
            request(port, "POST", f"/reader-tab/{beta_index}")
            switched = wait_ui(port, lambda ui: "BETA_TWO" in ui.get("messageReaderText", ""))
            assert "Beta" in switched["readerSelectedTab"] and switched["readerLive"] is True
            request(port, "POST", "/close")
        finally:
            try:
                request(port, "POST", "/quit")
            except OSError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
    print("reader tabs passed: live follows own session, other sessions counted, "
          "older message pauses, jump to latest resumes, tabs switch session")


if __name__ == "__main__":
    main()
