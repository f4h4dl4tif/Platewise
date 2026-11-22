#!/bin/bash
# Builds a universal Platewise.app and wraps it in an installer package: dist/Platewise-<version>.pkg
set -euo pipefail
cd "$(dirname "$0")"

UNIVERSAL=1 ./build.sh
ARCHS=$(lipo -archs build/Platewise.app/Contents/MacOS/Platewise)
case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) ;; *) echo "Expected a universal binary, got: $ARCHS"; exit 1;; esac

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications" dist
cp -R build/Platewise.app "$WORK/root/Applications/"

# Always install into /Applications, even if another copy of Platewise exists elsewhere on the Mac.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK/components.plist"

pkgbuild --root "$WORK/root" \
  --component-plist "$WORK/components.plist" \
  --scripts Installer/scripts \
  --identifier local.platewise.Platewise.pkg \
  --version "$VERSION" \
  --install-location / \
  "$WORK/Platewise-component.pkg" >/dev/null

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Platewise</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="default"><line choice="app"/></line></choices-outline>
    <choice id="default"/>
    <choice id="app" visible="false"><pkg-ref id="local.platewise.Platewise.pkg"/></choice>
    <pkg-ref id="local.platewise.Platewise.pkg" version="$VERSION" onConclusion="none">Platewise-component.pkg</pkg-ref>
</installer-gui-script>
XML

OUT="dist/Platewise-$VERSION.pkg"
productbuild --distribution "$WORK/distribution.xml" \
  --resources Installer/resources \
  --package-path "$WORK" \
  "$OUT" >/dev/null

echo "Created $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"

# Ship the install guide next to the package: as a loose file and in a zip with the .pkg.
GUIDE="Installer/How to Install.txt"
cp "$GUIDE" "dist/How to Install.txt"
ZIPDIR="$WORK/Platewise-$VERSION"
mkdir -p "$ZIPDIR"
cp "$OUT" "$GUIDE" "$ZIPDIR/"
ZIP="dist/Platewise-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$ZIPDIR" "$ZIP"
echo "Created $(pwd)/$ZIP (installer + How to Install.txt)"

# Also make a drag-to-Applications disk image from the same universal build.
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R build/Platewise.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$GUIDE" "$STAGE/"
DMG="dist/Platewise-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Platewise" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
echo "Created $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
