#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_APP="$PROJECT_ROOT/build/SpicetifyGUI.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_APP="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--out /path/to/SpicetifyGUI.app]" >&2
      exit 1
      ;;
  esac
done

TMP_ICONSET="/tmp/spicetify_gui_$$.iconset"
trap 'rm -rf "$TMP_ICONSET"' EXIT

echo "1/4 Generating Retina app icon..."
swift "$SCRIPT_DIR/make_icon.swift" "$TMP_ICONSET"

mkdir -p "$OUT_APP/Contents/MacOS" "$OUT_APP/Contents/Resources"
cp "$TMP_ICONSET/icon_512x512.png" "$OUT_APP/Contents/Resources/AppIcon.png"

if iconutil -c icns "$TMP_ICONSET" -o "$OUT_APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    Built AppIcon.icns with Apple iconutil."
else
  echo "    iconutil unavailable in this environment; packing standard Apple PNG-native ICNS..."
  python3 - "$TMP_ICONSET" "$OUT_APP/Contents/Resources/AppIcon.icns" << 'PY'
import os, struct, sys

iconset_dir, out_path = sys.argv[1], sys.argv[2]
# Standard Apple PNG-native ICNS OSTypes (omitting legacy icp4/icp5 for modern Finder compatibility)
mapping = [
    (b"ic11", "icon_16x16@2x.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
chunks = []
for ostype, fname in mapping:
    with open(os.path.join(iconset_dir, fname), "rb") as f:
        data = f.read()
    chunks.append(ostype + struct.pack(">I", 8 + len(data)) + data)

body = b"".join(chunks)
icns = b"icns" + struct.pack(">I", 8 + len(body)) + body
with open(out_path, "wb") as f:
    f.write(icns)
PY
fi

echo "2/4 Writing Info.plist..."
cat > "$OUT_APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SpicetifyGUI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.opensource.spicetify-gui</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Spicetify GUI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "3/4 Compiling native SwiftUI binary ($(uname -m))..."
swiftc -O -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -o "$OUT_APP/Contents/MacOS/SpicetifyGUI" \
  "$PROJECT_ROOT/src/SpicetifyGUI.swift"

echo "4/4 Signing and verifying bundle..."
rm -f "$OUT_APP"/Icon*
xattr -cr "$OUT_APP"
codesign --force --deep --sign - "$OUT_APP"
touch "$OUT_APP"

plutil -lint "$OUT_APP/Contents/Info.plist"
codesign --verify --verbose=2 "$OUT_APP"
swift -e "
import AppKit
let p = \"$OUT_APP/Contents/Resources/AppIcon.icns\"
guard let img = NSImage(contentsOfFile: p), img.representations.count >= 8 else {
    fputs(\"ERROR: AppIcon.icns failed AppKit verification\\n\", stderr)
    exit(1)
}
print(\"Icon verified: \\(img.representations.count) resolutions\")
"
echo "Done: $OUT_APP"
