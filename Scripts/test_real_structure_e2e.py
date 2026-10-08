#!/usr/bin/env python3
"""Black-box proof of exactly which transcript fields Doublethink sends out.

The running app reads canary copies of real Claude Code and Codex transcripts
(see Scripts/real_structure.py) and sends checker requests to a local dummy
server. Every canary that reaches the dummy is mapped back to its JSON path.

Default: the committed fixture in Tests/Fixtures/real-structure/.
--audit-real: canary copies of this Mac's real transcripts, created in a
temporary directory (the N most recent Claude files plus every Codex file).
No real text is written to the repository or sent anywhere: the copies contain
canaries only and the checker is a loopback dummy.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from real_structure import (  # noqa: E402
    FIXTURE_DIRECTORY, CanaryWriter, expected_outbound, expected_pairs,
    read_jsonl, real_claude_files, real_codex_files)
from e2e_defaults import configure_isolated_rules  # noqa: E402

CANARY = re.compile(r"CANARY_\d{6}")
API_TOKEN = "real-structure-e2e-ui-token-00000000000"


class DummyChecker(BaseHTTPRequestHandler):
    contents: list[str] = []
    lock = threading.Lock()

    def do_POST(self) -> None:  # noqa: N802
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size))
        with self.lock:
            # The whole request body is inspected, not only the evidence field.
            self.contents.append(json.dumps(payload))
        decision = {"alert": False, "reason": "No match", "evidence": ""}
        data = json.dumps(
            {"choices": [{"message": {"content": json.dumps(decision)}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, _format: str, *_args: object) -> None:
        pass


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def get_ui(port: int) -> dict:
    with socket.create_connection(("127.0.0.1", port), timeout=3) as connection:
        connection.sendall(
            f"GET /ui HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nConnection: close\r\n\r\n"
            .encode("ascii"))
        chunks = []
        while chunk := connection.recv(65_536):
            chunks.append(chunk)
    _, _, body = b"".join(chunks).partition(b"\r\n\r\n")
    return json.loads(body)


def wait_for(port: int, predicate, timeout: float,
             process: subprocess.Popen) -> dict:
    deadline = time.monotonic() + timeout
    latest: dict = {}
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Doublethink exited {process.returncode}: "
                                 f"{process.stderr.read() if process.stderr else ''}")
        try:
            latest = get_ui(port)
            if predicate(latest):
                return latest
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    raise AssertionError(f"condition timed out; last state keys={sorted(latest)}")


def load_sources(audit_real: bool, claude_file_count: int):
    """Returns (claude records, codex records, origin map) as canary copies."""
    if not audit_real:
        writer_origins: dict[str, str] = {}
        claude = read_jsonl(FIXTURE_DIRECTORY / "claude.jsonl")
        codex = read_jsonl(FIXTURE_DIRECTORY / "codex.jsonl")
        for records in [claude, codex]:
            for record in records:
                collect_origins(record, "$", writer_origins)
        return claude, codex, writer_origins
    writer = CanaryWriter()
    claude_files = real_claude_files()[:claude_file_count]
    codex_files = real_codex_files()
    # The most recent files change between runs; totals are only comparable
    # for the same file list.
    for path in claude_files + codex_files:
        print(f"source: {path.name} {path.stat().st_size} bytes")
    claude = [writer.record(record)
              for path in claude_files for record in read_jsonl(path)]
    codex = [writer.record(record)
             for path in codex_files for record in read_jsonl(path)]
    return claude, codex, writer.origins


def collect_origins(value, path: str, origins: dict[str, str]) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            collect_origins(item, f"{path}.{key}", origins)
    elif isinstance(value, list):
        for item in value:
            collect_origins(item, f"{path}[*]", origins)
    elif isinstance(value, str) and CANARY.fullmatch(value):
        origins[value] = path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit-real", action="store_true")
    parser.add_argument("--claude-files", type=int, default=3)
    arguments = parser.parse_args()

    claude, codex, origins = load_sources(arguments.audit_real,
                                          arguments.claude_files)
    provider_of = {}
    for provider, records in [("claude", claude), ("codex", codex)]:
        for record in records:
            found: dict[str, str] = {}
            collect_origins(record, "$", found)
            for canary in found:
                provider_of[canary] = provider
    expected = expected_outbound("claude", claude) | \
        expected_outbound("codex", codex)
    pairs = expected_pairs("claude", claude) | expected_pairs("codex", codex)

    ui_port, checker_port = free_port(), free_port()
    server = ThreadingHTTPServer(("127.0.0.1", checker_port), DummyChecker)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    with tempfile.TemporaryDirectory(prefix="doublethink-real-structure-") as temp:
        root = Path(temp)
        claude_path = root / "claude" / "project" / \
            "55555555-5555-4555-8555-555555555555.jsonl"
        codex_path = root / "codex" / "2026" / "01" / "01" / \
            "rollout-2026-01-01T00-00-00-66666666-6666-4666-8666-666666666666.jsonl"
        for path in [claude_path, codex_path]:
            path.parent.mkdir(parents=True)
            path.touch()
        (root / "codex-index.jsonl").write_text("")
        (root / "claude-desktop-sessions").mkdir()
        (root / "claude-cache").mkdir()
        environment = os.environ.copy()
        environment.update({
            "DOUBLETHINK_API_PORT": str(ui_port),
            "DOUBLETHINK_CLAUDE_PROJECTS": str(root / "claude"),
            "DOUBLETHINK_CODEX_SESSIONS": str(root / "codex"),
            "DOUBLETHINK_CODEX_INDEX": str(root / "codex-index.jsonl"),
            "DOUBLETHINK_CLAUDE_DESKTOP_SESSIONS": str(root / "claude-desktop-sessions"),
            "DOUBLETHINK_CLAUDE_CACHE": str(root / "claude-cache"),
            "DOUBLETHINK_CLAUDE_DESKTOP_CACHE": str(root / "claude-cache"),
            "DOUBLETHINK_PRIVACY_AUDIT_PATH": str(root / "privacy-audit.jsonl"),
            "DOUBLETHINK_VIOLATIONS_PATH": str(root / "violations.json"),
            "DOUBLETHINK_UI_API_LOG": str(root / "ui-api.jsonl"),
            "DOUBLETHINK_UI_API_TOKEN": API_TOKEN,
            "DOUBLETHINK_HISTORY_COUNT": "0",
        })
        configure_isolated_rules()
        process = subprocess.Popen(
            ["./.build/doublethink", "--isolated-e2e", "--dummy-checker-url",
             f"http://127.0.0.1:{checker_port}/v1/chat/completions"],
            env=environment, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True)
        try:
            wait_for(ui_port, lambda state: state.get("initialScanComplete") is True,
                     20, process)
            get_ui_post(ui_port, "/violation-bubble/off")
            started = datetime.now(timezone.utc)
            for offset, (path, record) in enumerate(
                    [(claude_path, record) for record in claude] +
                    [(codex_path, record) for record in codex]):
                if "timestamp" in record:
                    record = dict(record)
                    record["timestamp"] = (started + timedelta(milliseconds=offset)) \
                        .isoformat(timespec="milliseconds").replace("+00:00", "Z")
                with path.open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps(record, separators=(",", ":")) + "\n")

            def sent() -> set[str]:
                with DummyChecker.lock:
                    return {canary for body in DummyChecker.contents
                            for canary in CANARY.findall(body)}

            timeout = 30 + len(expected) * 0.05
            wait_for(ui_port, lambda state: expected <= sent() and
                     state.get("checkerRequestInFlight") is False,
                     timeout, process)
            time.sleep(2)  # any later, unexpected request must still be caught
            final = get_ui(ui_port)
        finally:
            # Quit through the app's own command; a session may ignore SIGTERM
            # (the Parallels guest shell does), so kill only as a fallback.
            try:
                get_ui_post(ui_port, "/quit")
            except OSError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            server.shutdown()

    outbound = sent()
    displayed = {canary for event in final.get("events", [])
                 for canary in CANARY.findall(str(event.get("text", "")))}
    sources = {canary for event in final.get("events", [])
               for canary in CANARY.findall(str(event.get("source", "")))}

    rows = collections.defaultdict(lambda: [0, 0, 0, 0])
    for canary, path in origins.items():
        row = rows[(provider_of.get(canary, "?"), path)]
        row[0] += 1
        row[1] += canary in outbound
        row[2] += canary in displayed
        row[3] += canary in sources
    # shown/title come from /ui "events", which keeps only the last 250 events;
    # they are informational and are not asserted.
    print(f"{'provider':8} {'JSON path':58} {'total':>6} {'sent':>6} "
          f"{'shown*':>6} {'title*':>6}")
    for (provider, path), (total, out, shown, title) in sorted(rows.items()):
        if out or shown or title or arguments.audit_real is False:
            print(f"{provider:8} {path:58} {total:6} {out:6} {shown:6} {title:6}")
    print("* shown/title: last 250 UI events only, not asserted")
    print(f"canary paths never sent, shown, or used as title: "
          f"{sum(1 for row in rows.values() if not any(row[1:]))}")

    with DummyChecker.lock:
        bodies = list(DummyChecker.contents)
    mispaired = []
    for body in bodies:
        envelope = json.loads(json.loads(body)["messages"][1]["content"])
        evidence = CANARY.findall(envelope["EVIDENCE_RECORD"]["content"])
        request = envelope.get("USER_REQUEST")
        sent_request = frozenset(CANARY.findall(request["text"])) if request else frozenset()
        for canary in evidence:
            expected_request = pairs.get(canary)
            # No earlier human request must be sent as null, never as text.
            if expected_request != sent_request or \
                    (not expected_request and request is not None):
                mispaired.append(origins.get(canary, canary))
    paired = sum(1 for request in pairs.values() if request)
    print(f"evidence records with an earlier human request in the same file: "
          f"{paired} of {len(pairs)} (the rest must carry USER_REQUEST null)")

    unexpected = outbound - expected
    missing = expected - outbound
    assert not unexpected, "sent outside the allowlist: " + ", ".join(
        sorted(f"{origins.get(c, '?')}" for c in unexpected))
    assert not mispaired, f"{len(mispaired)} records sent with the wrong user request"
    assert not missing, "allowlisted but never sent: " + ", ".join(
        sorted(f"{origins.get(c, '?')}" for c in missing))
    print(f"real-structure outbound boundary passed: {len(outbound)} sent, "
          f"{len(origins) - len(outbound)} withheld")


def get_ui_post(port: int, path: str) -> None:
    with socket.create_connection(("127.0.0.1", port), timeout=3) as connection:
        connection.sendall(
            f"POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nContent-Length: 0\r\n"
            "Connection: close\r\n\r\n".encode("ascii"))
        while connection.recv(65_536):
            pass


if __name__ == "__main__":
    main()
