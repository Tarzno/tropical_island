#!/bin/zsh
# Builds the self-contained macOS app: build/Tropical Island.app (Apple silicon only, ad-hoc signed),
# with the manual inside it.
# Needs the Godot 4.7.2 export templates in ~/Library/Application Support/Godot/export_templates.
set -e
cd "${0:A:h}/.."
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
printf '{"version": "1.0", "generated": "%s"}\n' "$(date '+%Y-%m-%d %H:%M')" > build_info.json
# the license notices the app shows under "Licenses", as a file for the repository
"$GODOT" --headless --path . --script tools/licenses_txt.gd -- THIRD-PARTY-LICENSES.txt 2>/dev/null | grep wrote
mkdir -p build
rm -rf "build/Tropical Island.app"
"$GODOT" --headless --path . --export-release "macOS" "build/Tropical Island.app"
# For Apple silicon only (since 2026-11-14: an Intel Mac's graphics are mostly too slow for the
# island, and macOS then says so before anything is started). Godot's export templates hold one
# binary for both kinds of Mac and nothing else (the preset's architecture "arm64" finds no
# template), so the export stays "universal" and the Intel half is taken out here; the entry
# for Intel goes from Info.plist with it.
BIN="build/Tropical Island.app/Contents/MacOS/Tropical Island"
[[ -f "$BIN" ]] || { echo "the export wrote no app: look at Godot's messages"; exit 1 }
lipo "$BIN" -thin arm64 -output "$BIN.arm64" && mv "$BIN.arm64" "$BIN"
PLIST="build/Tropical Island.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :LSMinimumSystemVersionByArchitecture:x86_64" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSArchitecturePriority" -c "Add :LSArchitecturePriority array" -c "Add :LSArchitecturePriority:0 string arm64" "$PLIST"
# The manual goes into the app (Contents/Resources), where Help > Manual opens it
# (scripts/menus.gd: manual_path()).
PDF="manual/Tropical Island - Manual.pdf"
if [[ -f "$PDF" ]]; then
  cp "$PDF" "build/Tropical Island.app/Contents/Resources/"
  echo "manual in the app"
else
  echo "NO MANUAL in the app: $PDF is missing (the Help menu will have no Manual entry)"
fi
# A changed binary and a file added to a signed bundle break its seal, so the app is signed
# again: ad hoc and with the hardened runtime, as Godot's export signs it (no entitlements
# there either).
codesign --force --deep --options runtime --sign - "build/Tropical Island.app" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --deep --strict "build/Tropical Island.app" && echo "signature ok"
# The app's identifier (export_presets.cfg: application/bundle_identifier): macOS takes a build
# with another one for another app, so it must not change by accident. (A Godot editor that
# was open while export_presets.cfg was changed can write its old settings back.)
ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")
[[ "$ID" == "io.github.tarzno.tropicalisland" ]] || { echo "the app's identifier is '$ID': see export_presets.cfg"; exit 1 }
ARCHS=$(lipo -archs "$BIN")
[[ "$ARCHS" == "arm64" ]] || { echo "the app is built for '$ARCHS', not for arm64 alone"; exit 1 }
echo "architecture: $ARCHS"
du -sh "build/Tropical Island.app"
