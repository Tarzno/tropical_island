"""Writes the window's layout into the .DS_Store of the disk image's volume, after Finder has
made that file (tools/build_dmg.sh calls it; the volume is mounted where Finder does not see it):
    python dmg/fix_layout.py <mounted volume>        needs ds_store (pip install ds_store)
    python dmg/fix_layout.py --check <mounted volume>
Finder writes its own state of the moment into the file, and that differs from Mac to Mac
(found 2026-11-14, macOS 27): with View > Show Tab Bar on, the image opened with a tab bar and
every icon stood 29 points lower than asked for, on top of the line about the first start.
So the file is written anew here. From Finder's file come only the view's options (the
picture behind the icons, their size, the size of their names) and the window's place; set
from LAYOUT in make_background.py are:
  - where the three icons stand;
  - no tab bar, toolbar, sidebar or status bar;
  - the volume's hidden files below the picture. Somebody whose Finder shows hidden files
    (Cmd-Shift-.) sees them only after scrolling down; left alone they land on the title."""
import os, plistlib, struct, sys
from make_background import LAYOUT

ITEMS = {"Tropical Island.app": LAYOUT["app"], "Applications": LAYOUT["apps"], "Tropical Island - Manual.pdf": LAYOUT["manual"]}
HIDDEN = [".background", ".VolumeIcon.icns", ".fseventsd", ".Trashes"]
HIDDEN_Y = LAYOUT["height"] + 200
BARS = ["ShowTabView", "ShowToolbar", "ShowStatusBar", "ShowSidebar", "ContainerShowSidebar", "ShowPathbar"]

def blob(raw, code):
    """The property list Finder stored under a four-letter code (the first one in the file)."""
    i = raw.find(code + b"blob")
    if i < 0:
        sys.exit("fix_layout: Finder's .DS_Store has no '%s'" % code.decode())
    n = struct.unpack(">I", raw[i + 8:i + 12])[0]
    return plistlib.loads(raw[i + 12:i + 12 + n])

def places(raw):
    """Every icon's place in a .DS_Store: {name: (x, y)}. A record is the name (a count of
    UTF-16 units, then the units), 'Iloc', 'blob', 16, x, y."""
    out, i = {}, raw.find(b"Ilocblob")
    while i >= 0:
        x, y = struct.unpack(">ii", raw[i + 12:i + 20])
        j = i - 2
        while j >= 4:
            n = struct.unpack(">I", raw[j - 4:j])[0]
            if 0 < n < 256 and j + 2 * n == i:
                out[raw[j:i].decode("utf-16-be")] = (x, y); break
            j -= 2
        i = raw.find(b"Ilocblob", i + 8)
    return out

def fix(volume):
    from ds_store import DSStore
    path = os.path.join(volume, ".DS_Store")
    raw = open(path, "rb").read()
    view, win = blob(raw, b"icvp"), blob(raw, b"bwsp")
    if not view.get("backgroundImageAlias"):
        sys.exit("fix_layout: Finder stored no picture for the window")
    for key in BARS:
        if key in win:
            win[key] = False
    # (the window's size: the picture's width, the layout's height and the title bar's 28 points;
    # its place on the screen as Finder had it)
    at = win.get("WindowBounds", "{{200, 200}, {0, 0}}").split("}")[0] + "}"
    win["WindowBounds"] = "%s, {%d, %d}}" % (at, LAYOUT["width"], LAYOUT["window_h"] + 28)
    for name in ITEMS:
        if not os.path.lexists(os.path.join(volume, name)):
            sys.exit("fix_layout: %s is not on the volume" % name)
    new = path + ".new"
    with DSStore.open(new, "w+") as d:
        d["."]["bwsp"] = win
        d["."]["icvp"] = view
        d["."]["vSrn"] = ("long", 1)
        for name, (x, y) in ITEMS.items():
            d[name]["Iloc"] = (x, y)
        for i, name in enumerate(HIDDEN):
            d[name]["Iloc"] = (LAYOUT["app"][0] + 140 * i, HIDDEN_Y)
    os.replace(new, path)
    return report(volume)

def report(volume):
    """What the file says now; an error if it is not what was asked for."""
    raw = open(os.path.join(volume, ".DS_Store"), "rb").read()
    got, win, view = places(raw), blob(raw, b"bwsp"), blob(raw, b"icvp")
    want = {k: tuple(v) for k, v in ITEMS.items()}
    if {k: got.get(k) for k in want} != want or win.get("ShowTabView") or not view.get("backgroundImageAlias"):
        sys.exit("fix_layout: the layout is not as asked for: %s, tab bar %s" % (got, win.get("ShowTabView")))
    return "layout: icons at %s; hidden files at y %s; no tab bar; icon size %d, text %d, window %s" % (
        " ".join("%d,%d" % got[n] for n in ITEMS), sorted({y for n, (x, y) in got.items() if n not in ITEMS}),
        view["iconSize"], view["textSize"], win.get("WindowBounds"))

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        print(report(sys.argv[2]))
    elif len(sys.argv) == 2:
        print(fix(sys.argv[1]))
    else:
        sys.exit(__doc__)
