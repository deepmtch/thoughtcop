#!/bin/sh
set -eu

build_dir=".build"
module_cache="$build_dir/module-cache"
mkdir -p "$module_cache"

swiftc -O -swift-version 5 -module-cache-path "$module_cache" -o "$build_dir/thinkpeek" \
    Config.swift \
    CheckRulesStore.swift \
    Transcript.swift \
    Sessions.swift \
    DriftCheck.swift \
    SingleInstance.swift \
    UIStateServer.swift \
    PresentationState.swift \
    WindowGeometry.swift \
    CompactWindowLayout.swift \
    DetailExitControls.swift \
    TickerCornerControls.swift \
    TickerSettingsMenu.swift \
    CheckRulesEditor.swift \
    ProviderIcon.swift \
    TickerBackground.swift \
    TickerView.swift \
    Views.swift \
    FullMessageView.swift \
    OutsideClickDismissal.swift \
    HUD.swift \
    main.swift

if /usr/bin/pgrep -x thinkpeek >/dev/null 2>&1; then
    echo "build complete; a running Thinkpeek still uses its old binary"
    echo "run ./restart.sh to replace it with this build"
fi
