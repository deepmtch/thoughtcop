#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
./build.sh

for test in \
    --selftest \
    --layout-selftest \
    --presentation-selftest \
    --source-context-selftest \
    --ticker-selftest \
    --ticker-background-selftest \
    --message-view-selftest \
    --escape-selftest \
    --exit-controls-selftest \
    --outside-click-selftest \
    --window-position-selftest \
    --ticker-corner-selftest \
    --provider-icon-selftest \
    --settings-menu-selftest \
    --check-rules-editor-selftest \
    --window-chrome-selftest \
    --compact-width-selftest \
    --interaction-selftest
do
    ./.build/thinkpeek "$test"
done

python3 -m py_compile Scripts/watch.py
echo "all Thinkpeek tests passed"
