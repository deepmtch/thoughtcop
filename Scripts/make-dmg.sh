#!/bin/sh
# Builds ThoughtCop for Apple Silicon and Intel and packs it as
# .build/releases/ThoughtCop.dmg: open it, drag ThoughtCop to Applications.
set -eu
cd "$(dirname "$0")/.."

out=".build/releases"
work=".build/dmg"
rm -rf "$work"
mkdir -p "$out" "$work"

for arch in arm64 x86_64; do
    THOUGHTCOP_ARCH="$arch" ./build.sh >/dev/null
    cp .build/thoughtcop "$work/thoughtcop-$arch"
done

stage="$work/stage"
mkdir -p "$stage"
cp -R .build/ThoughtCop.app "$stage/ThoughtCop.app"
/usr/bin/lipo -create "$work/thoughtcop-arm64" "$work/thoughtcop-x86_64" \
    -output "$stage/ThoughtCop.app/Contents/MacOS/thoughtcop"
/usr/bin/codesign --force --deep --sign - "$stage/ThoughtCop.app"
ln -s /Applications "$stage/Applications"
# The mounted disk shows the app icon too.
cp Resources/ThoughtCop.icns "$stage/.VolumeIcon.icns"
/usr/bin/SetFile -a C "$stage" 2>/dev/null || true

rm -f "$out/ThoughtCop.dmg"
rw="$work/rw.dmg"
/usr/bin/hdiutil create -quiet -volname "ThoughtCop" -srcfolder "$stage" \
    -fs HFS+ -format UDRW "$rw"
mount=$(/usr/bin/hdiutil attach -nobrowse "$rw" | /usr/bin/awk -F'\t' '/Volumes/{print $NF}')
/usr/bin/SetFile -a C "$mount"
/usr/bin/hdiutil detach -quiet "$mount"
/usr/bin/hdiutil convert -quiet "$rw" -format UDZO -o "$out/ThoughtCop.dmg"

# Leave the local development build for this Mac's own architecture.
./build.sh >/dev/null
/usr/bin/lipo -archs "$stage/ThoughtCop.app/Contents/MacOS/thoughtcop"
echo "$out/ThoughtCop.dmg"
