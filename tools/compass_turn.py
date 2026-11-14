"""One-off (2026-11-12): turns the island's compass words around in the project's texts.
Until then the notes and the code called +x "east" and -z "north"; but the sun sets over the
+x sea, so +x is WEST, -x east, +z NORTH, -z south: every north <-> south, east <-> west.
  python3 tools/compass_turn.py            what would change (new lines, for reading through)
  python3 tools/compass_turn.py --write    do it
Kept only as a record of what was done: running it again would turn everything back."""
import re, sys, glob, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWAP = {"north": "south", "south": "north", "east": "west", "west": "east"}
# the world's own geography and sky, and words already in the true sense: left alone
KEEP = ["Southeast Asia", "western Indian Ocean", "northern winter", "southern starfield", "southern core", "southern sky",
        "north of Mahé", "Bird Island, north of", "from Southeast", "of the western", "over the sea in the west", "over the island in the east",
        "East Africa", "Southern Cross", "north-west monsoon"]
WORD = re.compile(r"(?<![A-Za-z])(north|south|east|west)(?:([- ]?)(east|west))?(?![a-z])|(?-i:(?<=[a-z])(North|South|East|West)(?![a-z]))", re.I)

def case_like(src, word):
    if src.isupper() and len(src) > 1: return word.upper()
    if src[0].isupper(): return word.capitalize()
    return word

def turn(text):
    held = {}
    for i, k in enumerate(KEEP):
        for m in set(re.findall(re.escape(k), text, re.I)):
            key = "\x00%d_%d\x00" % (i, len(held)); held[key] = m; text = text.replace(m, key)
    def sub(m):
        if m.group(4):
            return case_like(m.group(4), SWAP[m.group(4).lower()])
        out = case_like(m.group(1), SWAP[m.group(1).lower()])
        if m.group(3):
            out += m.group(2) + case_like(m.group(3), SWAP[m.group(3).lower()])
        return out
    # (suffixes like -ern, -ward stay as they are: the lookahead above stops at a small letter,
    # so "northern" is caught here)
    text = re.sub(r"(?<![A-Za-z])(north|south|east|west)(?=(ern|erly|ward|wards|most)(?![a-z]))", lambda m: case_like(m.group(1), SWAP[m.group(1).lower()]), text, flags=re.I)
    text = WORD.sub(sub, text)
    # the terrain tools' short names
    text = re.sub(r"\b(TIP|TAPER)_([NS])\b", lambda m: m.group(1) + "_" + ("S" if m.group(2) == "N" else "N"), text)
    for key, m in held.items(): text = text.replace(key, m)
    return text

FILES = ["README.md", "HANDOFF.md", "manual/content.py", "assets/models/island.json"] + \
    sorted(glob.glob(os.path.join(ROOT, "scripts/*.gd"))) + sorted(glob.glob(os.path.join(ROOT, "shaders/*.gdshader*"))) + \
    [f for f in sorted(glob.glob(os.path.join(ROOT, "tools/*.gd")) + glob.glob(os.path.join(ROOT, "tools/*.py")) + glob.glob(os.path.join(ROOT, "manual/capture/*.py"))) if not f.endswith("compass_turn.py")]
SKIP_LINES = {"manual/capture/b18_convict_idol.py": (5,)}     # file -> line numbers (from 1) left as they are (a picture's name)

if __name__ == "__main__":
    write = "--write" in sys.argv
    extra = [a for a in sys.argv[1:] if not a.startswith("--")]
    n = 0
    for f in FILES + extra:
        p = f if os.path.isabs(f) else os.path.join(ROOT, f)
        old = open(p).read().split("\n"); new = []
        for i, l in enumerate(old):
            t = l if (i + 1) in SKIP_LINES.get(os.path.relpath(p, ROOT), ()) else turn(l)
            if t != l:
                n += 1
                if not write: print("%s:%d: %s" % (os.path.relpath(p, ROOT), i + 1, t.strip()[:260]))
            new.append(t)
        if write and new != old: open(p, "w").write("\n".join(new))
    print(n, "lines", "changed" if write else "would change")
