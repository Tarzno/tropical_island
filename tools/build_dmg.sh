#!/bin/zsh
# Builds the disk image for a release: build/Tropical-Island-<version>-macos-arm64.dmg (no
# spaces: GitHub turns them into dots in a release's file names), holding the app
# (as built by tools/build_app.sh), a link to /Applications and the manual, in a Finder window
# with a picture of the island behind them (dmg/make_background.py; the layout is there).
#   zsh tools/build_dmg.sh
# Needs what macOS has (hdiutil, tiffutil, SetFile, Finder) and a Python with Pillow and ds_store:
# the manual's environment if there is one (manual/venv/bin/pip install pillow ds_store), else python3.
# Finder is told by AppleScript to lay the window out: the first time macOS asks whether the
# terminal may control Finder. The image is HFS+ and lzma-compressed (ULMO: macOS 10.15 and
# later, the app's own minimum). hdiutil calls itself deprecated on macOS 27 and still works.
# The app is signed ad hoc only: see "The disk image" in HANDOFF.md for what that means.
set -e
cd "${0:A:h}/.."
APP="build/Tropical Island.app"
PDF="manual/Tropical Island - Manual.pdf"
VOL="Tropical Island"
D=build/dmg
[[ -d "$APP" ]] || { echo "no app: run zsh tools/build_app.sh first"; exit 1 }
[[ -f "$PDF" ]] || { echo "no manual: build it first (docs/development.md, \"Manual\", says how)"; exit 1 }
[[ -e "/Volumes/$VOL" ]] && { echo "a volume named '$VOL' is mounted: eject it first"; exit 1 }
PY=python3; [[ -x manual/venv/bin/python ]] && PY=manual/venv/bin/python
$PY -c "import PIL, ds_store" 2>/dev/null || { echo "$PY has no Pillow or no ds_store (manual/venv/bin/pip install pillow ds_store)"; exit 1 }
codesign --verify --deep --strict "$APP"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Tropical Island")
[[ "$ARCHS" == "arm64" ]] || { echo "the app is built for '$ARCHS', not for arm64 alone: run zsh tools/build_app.sh"; exit 1 }
OUT="build/Tropical-Island-$VER-macos-arm64.dmg"

# the picture, at one and at two pixels a point, as one TIFF
mkdir -p $D
$PY dmg/make_background.py
eval "$($PY dmg/make_background.py --shell)"

# what the image holds
rm -rf $D/stage $D/rw.dmg
mkdir -p $D/stage/.background
ditto "$APP" "$D/stage/Tropical Island.app"
cp "$PDF" $D/stage/
ln -s /Applications $D/stage/Applications
tiffutil -cathidpicheck $D/background.png $D/background@2x.png -out $D/stage/.background/background.tiff

# a writable image, mounted, for Finder to arrange
hdiutil create -quiet -srcfolder $D/stage -volname "$VOL" -fs HFS+ -format UDRW -ov $D/rw.dmg 2>/dev/null
hdiutil attach -quiet -readwrite -noverify -noautoopen $D/rw.dmg 2>/dev/null
SetFile -a E "/Volumes/$VOL/Tropical Island - Manual.pdf"  # ".pdf" hidden where Finder hides extensions
# (the window's size is set last, and again after reopening: set before the toolbar is hidden
# it did not stick on 2026-11-12)
osascript - "$VOL" $BG_W $WIN_H $ICON $TEXT $APP_X $APP_Y $APPS_X $APPS_Y $MAN_X $MAN_Y <<'APPLESCRIPT'
on run argv
	set volName to item 1 of argv
	set w to (item 2 of argv) as integer
	set h to (item 3 of argv) as integer
	set b to {200, 120, 200 + w, 120 + h + 28}
	tell application "Finder"
		tell disk volName
			open
			delay 1
			set win to container window
			set current view of win to icon view
			set toolbar visible of win to false
			set statusbar visible of win to false
			set pathbar visible of win to false
			set opts to icon view options of win
			set arrangement of opts to not arranged
			set icon size of opts to (item 4 of argv) as integer
			set text size of opts to (item 5 of argv) as integer
			set label position of opts to bottom
			set shows icon preview of opts to true
			set shows item info of opts to false
			set background picture of opts to file ".background:background.tiff"
			set position of item "Tropical Island.app" to {(item 6 of argv) as integer, (item 7 of argv) as integer}
			set position of item "Applications" to {(item 8 of argv) as integer, (item 9 of argv) as integer}
			set position of item "Tropical Island - Manual.pdf" to {(item 10 of argv) as integer, (item 11 of argv) as integer}
			set bounds of win to b
			update without registering applications
			delay 1
			close
			delay 1
			open
			delay 2
			set bounds of container window to b
			delay 1
			close
		end tell
	end tell
end run
APPLESCRIPT
sync
for i in {1..20}; do [[ -s "/Volumes/$VOL/.DS_Store" ]] && break; sleep 0.5; done
[[ -s "/Volumes/$VOL/.DS_Store" ]] || { echo "Finder wrote no layout (.DS_Store)"; exit 1 }
# The volume's own icon, after Finder has done: Finder's "update" takes a volume icon away
# again, file and flag (macOS 27, found 2026-11-12).
cp "$APP/Contents/Resources/icon.icns" "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL"
rm -rf "/Volumes/$VOL/.fseventsd"
sync
hdiutil detach -quiet "/Volumes/$VOL" 2>/dev/null

# What Finder has written depends on how the Finder of the moment is set: with its tab bar
# showing, the image opened with a tab bar and every icon stood 29 points too low (2026-11-14).
# So the layout is written anew from dmg/make_background.py's LAYOUT, with the volume mounted
# where Finder does not look (dmg/fix_layout.py says what is kept of Finder's file).
mkdir -p $D/mnt
hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse -mountpoint $D/mnt $D/rw.dmg 2>/dev/null
$PY dmg/fix_layout.py $D/mnt
rm -rf $D/mnt/.fseventsd
sync
hdiutil detach -quiet $D/mnt 2>/dev/null

# the release: compressed, read-only
rm -f "$OUT"
hdiutil convert -quiet $D/rw.dmg -format ULMO -o "$OUT" 2>/dev/null
hdiutil verify -quiet "$OUT" 2>/dev/null && echo "image verified"
rm -rf $D/stage $D/rw.dmg
du -h "$OUT"
shasum -a 256 "$OUT"
