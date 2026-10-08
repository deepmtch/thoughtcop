#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
./build.sh

for test in \
    --config-path-selftest \
    --legacy-migration-selftest \
    --selftest \
    --session-discovery-selftest \
    --transcript-monitor-selftest \
    --evaluator-selftest \
    --provider-reasoning-selftest \
    --claude-desktop-conversation-selftest \
    --layout-selftest \
    --presentation-selftest \
    --claude-cloud-activity-selftest \
    --two-summary-card-selftest \
    --source-context-selftest \
    --ticker-selftest \
    --ticker-background-selftest \
    --message-view-selftest \
    --message-reader-freeze-selftest \
    --escape-selftest \
    --exit-controls-selftest \
    --outside-click-selftest \
    --ticker-actions-selftest \
    --window-position-selftest \
    --ticker-corner-selftest \
    --provider-icon-selftest \
    --settings-window-selftest \
    --check-rules-editor-selftest \
    --window-chrome-selftest \
    --compact-width-selftest \
    --interaction-selftest \
    --privacy-audit-selftest \
    --violation-store-selftest \
    --violation-bubble-selftest \
    --usage-selftest \
    --checker-credentials-selftest \
    --ui-command-api-selftest \
    --keyboard-navigation-selftest \
    --status-item-foreground-selftest
do
    ./.build/thoughtcrime "$test"
done

PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 -m py_compile Scripts/watch.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 -m py_compile Scripts/test_ui_api.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 -m py_compile Scripts/test_release_contract.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 -m py_compile Benchmarks/bench.py Benchmarks/bench2.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_release_contract.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_benchmark_credentials.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_multi_session_e2e.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_real_structure_e2e.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_violation_restore_e2e.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_violation_verification_e2e.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/test_reader_tabs_e2e.py
PYTHONPYCACHEPREFIX="$PWD/.local/python-cache" \
    python3 Scripts/capture_screens.py .local/screens
echo "all Thoughtcrime tests passed"
