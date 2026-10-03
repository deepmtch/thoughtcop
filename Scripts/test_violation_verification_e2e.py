#!/usr/bin/env python3
"""Black-box test of the second check and the configurable violation history.

The built app runs against a loopback dummy checker:
- evaluation: content containing ALERT is a violation; NO_EVIDENCE gives an
  empty evidence quote; everything else is clean.
- verification (requests carrying CLAIM): confirmed unless the evidence record
  contains FALSE_ALARM.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
import os
import socket
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

API_TOKEN = "violation-verification-e2e-token-0000000"
DEFAULTS_DOMAIN = "thinkpeek"  # the bare test binary's preferences domain
SEEDED = 60
LIMIT = 15.0


class DummyChecker(BaseHTTPRequestHandler):
    evaluations: list[dict] = []
    verifications: list[dict] = []
    lock = threading.Lock()

    def do_POST(self) -> None:  # noqa: N802
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size))
        system = payload["messages"][0]["content"]
        envelope = json.loads(payload["messages"][1]["content"])
        content = envelope["EVIDENCE_RECORD"]["content"]
        if "CLAIM" in envelope:
            with self.lock:
                self.verifications.append({"system": system, "envelope": envelope})
            answer = {"confirmed": "FALSE_ALARM" not in content,
                      "reason": "dummy verification"}
        else:
            with self.lock:
                self.evaluations.append({"system": system, "envelope": envelope})
            alert = "ALERT" in content
            answer = {"alert": alert,
                      "reason": "dummy claim" if alert else "No match",
                      "evidence": "" if "NO_EVIDENCE" in content or not alert
                      else "ALERT"}
        data = json.dumps(
            {"choices": [{"message": {"content": json.dumps(answer)}}]}).encode()
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


def wait_ui(port: int, predicate, limit: float = LIMIT) -> dict:
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
    raise AssertionError(f"UI condition timed out; violationCount="
                         f"{state.get('violationCount')} events="
                         f"{state.get('events', [])[-4:]}")


def clean_events_with_rejections(state: dict) -> int:
    return sum(event.get("rejectedClaims", 0) for event in state.get("events", [])
               if event.get("kind") == "drift-clean")


def append_thinking(path: Path, text: str) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({
            "type": "assistant",
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds")
                .replace("+00:00", "Z"),
            "message": {"content": [
                {"type": "thinking", "thinking": text, "signature": "s"}]}}) + "\n")


def reset_preferences() -> None:
    for key in ["violationHistoryLimit", "violationVerificationEnabled",
                "violationAlertsEnabled"]:
        subprocess.run(["/usr/bin/defaults", "delete", DEFAULTS_DOMAIN, key],
                       capture_output=True, check=False)


def main() -> None:
    reset_preferences()
    ui_port, checker_port = free_port(), free_port()
    server = ThreadingHTTPServer(("127.0.0.1", checker_port), DummyChecker)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory(prefix="thinkpeek-verification-") as temp:
        root = Path(temp)
        violations_path = root / "violations.json"
        violations_path.write_text(json.dumps([{
            "id": f"00000000-0000-4000-8000-{index:012d}",
            "timestamp": f"2026-09-19T10:00:{index:02d}.000Z",
            "source": "Claude · seeded", "content": f"Seeded violation {index}",
            "reason": "seeded", "evidence": "seeded", "provider": "Dummy",
            "latencyMs": 1, "checkPrompt": "seeded",
        } for index in range(SEEDED)]))
        transcript = root / "claude" / "project" / \
            "88888888-8888-4888-8888-888888888888.jsonl"
        transcript.parent.mkdir(parents=True)
        transcript.touch()
        for name in ["codex", "desktop", "cache"]:
            (root / name).mkdir()
        (root / "codex-index.jsonl").write_text("")
        environment = os.environ.copy()
        environment.update({
            "THINKPEEK_API_PORT": str(ui_port),
            "THINKPEEK_CLAUDE_PROJECTS": str(root / "claude"),
            "THINKPEEK_CODEX_SESSIONS": str(root / "codex"),
            "THINKPEEK_CODEX_INDEX": str(root / "codex-index.jsonl"),
            "THINKPEEK_CLAUDE_DESKTOP_SESSIONS": str(root / "desktop"),
            "THINKPEEK_CLAUDE_CACHE": str(root / "cache"),
            "THINKPEEK_CLAUDE_DESKTOP_CACHE": str(root / "cache"),
            "THINKPEEK_PRIVACY_AUDIT_PATH": str(root / "privacy-audit.jsonl"),
            "THINKPEEK_VIOLATIONS_PATH": str(violations_path),
            "THINKPEEK_UI_API_LOG": str(root / "ui-api.jsonl"),
            "THINKPEEK_UI_API_TOKEN": API_TOKEN,
            "THINKPEEK_HISTORY_COUNT": "0",
        })
        process = subprocess.Popen(
            ["./.build/thinkpeek", "--isolated-e2e", "--dummy-checker-url",
             f"http://127.0.0.1:{checker_port}/v1/chat/completions"],
            env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            # Default history limit (50) trims the seeded 60 at launch.
            launched = wait_ui(ui_port, lambda ui: ui.get("initialScanComplete") is True,
                               20)
            stored = json.loads(violations_path.read_text())
            assert launched["violationRetentionLimit"] == 50, launched["violationRetentionLimit"]
            assert launched["violationCount"] == 50, launched["violationCount"]
            assert len(stored) == 50 and stored[0]["content"] == "Seeded violation 10", \
                (len(stored), stored[0]["content"])
            assert launched["violationVerificationEnabled"] is True
            assert "Violation History" in launched["settingsMenuStructure"]

            # Lowering the limit deletes the oldest and their cards.
            request(ui_port, "POST", "/violation-history/10")
            trimmed = wait_ui(ui_port, lambda ui: ui.get("violationCount") == 10)
            assert trimmed["violationRetentionLimit"] == 10
            assert len(json.loads(violations_path.read_text())) == 10
            request(ui_port, "POST", "/filter/violations")
            listed = wait_ui(ui_port, lambda ui: ui.get("historyFilter") == "violations"
                             and ui.get("compactMode") is False)
            assert listed["visibleCardCount"] == 10, listed["visibleCardCount"]
            request(ui_port, "POST", "/close")
            request(ui_port, "POST", "/violation-history/500")
            wait_ui(ui_port, lambda ui: ui.get("violationRetentionLimit") == 500)
            time.sleep(1.5)  # transcript discovery

            # 1. Confirmed by the second check: shown and stored.
            append_thinking(transcript, "TRUE_ALERT: I will skip the test.")
            confirmed = wait_ui(ui_port, lambda ui: ui.get("violationCount") == 11)
            assert confirmed["violations"][-1]["content"].startswith("TRUE_ALERT")
            assert "confirmed by second check" in confirmed["violations"][-1]["provider"]

            # 2. Rejected by the second check: not shown, not stored.
            append_thinking(transcript, "FALSE_ALARM_ALERT: harmless text.")
            rejected = wait_ui(ui_port, lambda ui: clean_events_with_rejections(ui) == 1)
            # 3. No evidence: rejected without a verification request.
            append_thinking(transcript, "NO_EVIDENCE_ALERT: claim without quote.")
            no_evidence = wait_ui(ui_port, lambda ui: clean_events_with_rejections(ui) == 2)
            for state in [rejected, no_evidence]:
                assert state["violationCount"] == 11, state["violationCount"]
                assert not any("FALSE_ALARM" in v["content"] or "NO_EVIDENCE" in v["content"]
                               for v in state["violations"])
            assert not any("FALSE_ALARM" in v["content"] or "NO_EVIDENCE" in v["content"]
                           for v in json.loads(violations_path.read_text()))

            # 4. A resumed chat's new file begins with a copy of an old message:
            # written before launch, so it is not checked.
            resumed = transcript.parent / "99999999-9999-4999-8999-999999999999.jsonl"
            with resumed.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({
                    "type": "assistant", "timestamp": "2026-09-28T09:00:00.000Z",
                    "message": {"content": [{"type": "thinking", "signature": "s",
                                             "thinking": "OLD_COPY_ALERT: copied."}]},
                }) + "\n")
            append_thinking(resumed, "RESUMED_NEW: continuing the resumed chat.")
            skipped = wait_ui(ui_port, lambda ui: any(
                e.get("kind") == "drift-skipped-old" for e in ui.get("events", [])) and
                any("RESUMED_NEW" in str(e.get("text")) for e in ui.get("events", [])))
            assert skipped["violationCount"] == 11, skipped["violationCount"]

            # 5. Second check switched off: the first verdict is shown as before.
            request(ui_port, "POST", "/violation-verification/off")
            wait_ui(ui_port, lambda ui: ui.get("violationVerificationEnabled") is False)
            append_thinking(transcript, "FALSE_ALARM_UNVERIFIED_ALERT: shown without check.")
            unverified = wait_ui(ui_port, lambda ui: ui.get("violationCount") == 12)
            assert unverified["violations"][-1]["content"].startswith(
                "FALSE_ALARM_UNVERIFIED_ALERT")
            audit = [json.loads(line) for line in
                     (root / "privacy-audit.jsonl").read_text().splitlines()]
        finally:
            for path in ["/violation-verification/on", "/violation-history/50"]:
                try:
                    request(ui_port, "POST", path)
                except OSError:
                    pass
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
            server.shutdown()
            reset_preferences()

    with DummyChecker.lock:
        verifications = list(DummyChecker.verifications)
    with DummyChecker.lock:
        evaluated = [item["envelope"]["EVIDENCE_RECORD"]["content"]
                     for item in DummyChecker.evaluations]
    assert not any("OLD_COPY" in text for text in evaluated), evaluated
    assert any("RESUMED_NEW" in text for text in evaluated), evaluated
    verified = [item["envelope"]["EVIDENCE_RECORD"]["content"] for item in verifications]
    assert verified == ["TRUE_ALERT: I will skip the test.",
                        "FALSE_ALARM_ALERT: harmless text."], verified
    for item in verifications:
        envelope = item["envelope"]
        assert envelope["CLAIM"] == {"reason": "dummy claim", "evidence": "ALERT"}, envelope
        assert envelope["EVALUATION_INSTRUCTION"], envelope
        assert "Decide whether CLAIM is true" in item["system"]
    audit_requests = [e for e in audit if e.get("action") == "external_verification_request"]
    audit_results = [e.get("status") for e in audit
                     if e.get("action") == "external_verification_result"]
    assert len(audit_requests) == 2 and sorted(audit_results) == ["confirmed", "rejected"], \
        (audit_requests, audit_results)
    print("violation verification passed: confirmed shown, rejected and "
          "evidence-free claims dropped, toggle off shows first verdict, "
          "history limit 50 default and configurable")


if __name__ == "__main__":
    main()
