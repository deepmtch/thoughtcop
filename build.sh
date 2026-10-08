#!/bin/sh
set -eu

build_dir=".build"
module_cache="$build_dir/module-cache"
target_arch=$(/usr/bin/uname -m)
mkdir -p "$module_cache"

swiftc -O -swift-version 5 -target "$target_arch-apple-macos13.0" \
    -framework Security \
    -module-cache-path "$module_cache" -o "$build_dir/doublethink" \
    Sources/App/Config.swift \
    Sources/App/LegacyMigration.swift \
    Sources/Checker/CheckRulesStore.swift \
    Sources/Checker/CheckerCredentials.swift \
    Sources/Checker/ViolationStore.swift \
    Sources/Monitoring/Transcript.swift \
    Sources/Monitoring/ClaudeCloudActivity.swift \
    Sources/Monitoring/ClaudeDesktopConversation.swift \
    Sources/Monitoring/PrivacyAudit.swift \
    Sources/Monitoring/Sessions.swift \
    Sources/Monitoring/MessageReaderState.swift \
    Sources/Checker/DriftCheck.swift \
    Sources/Checker/UsageStore.swift \
    Sources/Infrastructure/SingleInstance.swift \
    Sources/Infrastructure/UIStateServer.swift \
    Sources/Monitoring/PresentationState.swift \
    Sources/UI/Layout/WindowGeometry.swift \
    Sources/UI/Layout/CompactWindowLayout.swift \
    Sources/UI/Controls/DetailExitControls.swift \
    Sources/UI/Controls/ViolationBubble.swift \
    Sources/UI/Controls/SettingsWindow.swift \
    Sources/UI/Ticker/TickerCornerControls.swift \
    Sources/UI/Ticker/TickerPrimaryActions.swift \
    Sources/UI/Ticker/CheckerActivityIndicator.swift \
    Sources/UI/Controls/CheckRulesEditor.swift \
    Sources/UI/Controls/ProviderCredentialsEditor.swift \
    Sources/UI/Controls/UsageWindow.swift \
    Sources/UI/Ticker/ProviderIcon.swift \
    Sources/UI/Ticker/TickerBackground.swift \
    Sources/UI/Ticker/TickerView.swift \
    Sources/UI/Components/Views.swift \
    Sources/UI/Controls/FullMessageView.swift \
    Sources/UI/Controls/OutsideClickDismissal.swift \
    Sources/App/HUD.swift \
    Tests/SelfTests.swift \
    Sources/App/main.swift

# A minimal app bundle lets LaunchServices own the GUI process. Launching a raw
# executable from a Git hook leaves it tied to the hook's process lifetime.
app_contents="$build_dir/Doublethink.app/Contents"
mkdir -p "$app_contents/MacOS"
cp "$build_dir/doublethink" "$app_contents/MacOS/doublethink"
cp "Resources/Doublethink-Info.plist" "$app_contents/Info.plist"
mkdir -p "$app_contents/Resources"
cp "Resources/Doublethink.icns" "$app_contents/Resources/Doublethink.icns"
/usr/bin/codesign --force --deep --sign - "$build_dir/Doublethink.app"
/usr/bin/touch "$build_dir/build.stamp"

if /usr/bin/pgrep -x doublethink >/dev/null 2>&1; then
    echo "build complete; a running Doublethink still uses its old binary"
    echo "run ./restart.sh to replace it with this build"
fi
