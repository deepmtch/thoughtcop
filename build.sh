#!/bin/sh
set -eu

module_cache="${TMPDIR:-/tmp}/thinkpeek-swift-module-cache"
mkdir -p "$module_cache"

swiftc -O -swift-version 5 -module-cache-path "$module_cache" -o thinkpeek \
    Config.swift \
    Transcript.swift \
    Sessions.swift \
    DriftCheck.swift \
    SingleInstance.swift \
    UIStateServer.swift \
    PresentationState.swift \
    WindowGeometry.swift \
    Views.swift \
    HUD.swift \
    main.swift

if /usr/bin/pgrep -x thinkpeek >/dev/null 2>&1; then
    echo "build complete; a running Thinkpeek still uses its old binary"
    echo "run ./restart.sh to replace it with this build"
fi
