#!/bin/sh
set -eu

build_dir=".build"
module_cache="$build_dir/module-cache"
mkdir -p "$module_cache"

swiftc -O -swift-version 5 -module-cache-path "$module_cache" -o "$build_dir/thinkpeek" \
    Sources/App/Config.swift \
    Sources/Checker/CheckRulesStore.swift \
    Sources/Monitoring/Transcript.swift \
    Sources/Monitoring/PrivacyAudit.swift \
    Sources/Monitoring/Sessions.swift \
    Sources/Monitoring/MessageReaderState.swift \
    Sources/Checker/DriftCheck.swift \
    Sources/Infrastructure/SingleInstance.swift \
    Sources/Infrastructure/UIStateServer.swift \
    Sources/Monitoring/PresentationState.swift \
    Sources/UI/Layout/WindowGeometry.swift \
    Sources/UI/Layout/CompactWindowLayout.swift \
    Sources/UI/Controls/DetailExitControls.swift \
    Sources/UI/Ticker/TickerCornerControls.swift \
    Sources/UI/Ticker/TickerPrimaryActions.swift \
    Sources/UI/Ticker/TickerSettingsMenu.swift \
    Sources/UI/Controls/CheckRulesEditor.swift \
    Sources/UI/Ticker/ProviderIcon.swift \
    Sources/UI/Ticker/TickerBackground.swift \
    Sources/UI/Ticker/TickerView.swift \
    Sources/UI/Components/Views.swift \
    Sources/UI/Controls/FullMessageView.swift \
    Sources/UI/Controls/OutsideClickDismissal.swift \
    Sources/App/HUD.swift \
    Tests/SelfTests.swift \
    Sources/App/main.swift

if /usr/bin/pgrep -x thinkpeek >/dev/null 2>&1; then
    echo "build complete; a running Thinkpeek still uses its old binary"
    echo "run ./restart.sh to replace it with this build"
fi
