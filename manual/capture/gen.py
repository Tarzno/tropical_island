"""Builds a job file for tools/shot.gd from a list of picture specs, runs it (one game, a
window of 1500x1000), and lays the pictures out on sheets for reading through.
  cd manual/capture && python3 b2.py          pictures to shots/<batch>/, sheets to shots/
A spec: dict(name, target (an expression for tools/manual_shots.gd: a node, a place), offs
(camera offsets from it, one picture each), fov, lift, stand (how far off the player waits),
wait (frames), local (offsets in the target's own axes), setup / setup_wait (expressions run
first), tod / clock, player, aimx; or jobs=[...] for the driver's own job kinds.
`python3 compact.py <batch> [name prefixes] [tag]` makes smaller sheets of a batch.
The b*.py are the manual's batches as they were run (some names in them are from before the
compass was turned: the pictures' names only); test_*.py are measuring jobs of 2026-11-12."""
import json, subprocess, sys, os
from PIL import Image, ImageDraw
S = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(S))   # the project: two folders up from here
MS = "main.get_node('MS')"
IL = "main.get_node('IslandLife')"
def N(name): return IL + ".get_node('%s')" % name
def V(x, y, z): return "Vector3(%s, %s, %s)" % (x, y, z)

def build(batch, specs, warmup=750, pre=None, res="1500x1000"):
    out = os.path.join(S, "shots", batch); os.makedirs(out, exist_ok=True)
    jobs = [{"kind": "expr", "frames": 5, "exprs": ["add_tool('res://tools/manual_shots.gd', 'MS')"]},
            {"kind": "expr", "frames": 5, "exprs": [MS + ".set('out_dir', '%s')" % out] + (pre or [])}]
    for sp in specs:
        if "jobs" in sp:
            jobs += sp["jobs"]; continue
        if "tod" in sp: jobs.append({"kind": "tod", "preset": sp["tod"], "frames": 30})
        if "clock" in sp: jobs.append({"kind": "clock", "hour": sp["clock"], "frames": 30})
        if sp.get("setup"):
            jobs.append({"kind": "expr", "frames": sp.get("setup_wait", 20), "exprs": sp["setup"]})
            if sp.get("setup_after"): jobs.append({"kind": "expr", "frames": sp.get("after_wait", 60), "exprs": sp["setup_after"]})
        for k, off in enumerate(sp.get("offs", [])):
            fov = sp.get("fov", 35)
            if len(off) > 3: fov = off[3]
            l = sp.get("lift", (0, 0, 0))
            ex = [MS + ".set('lift', %s)" % V(*l), MS + ".set('stand', %s)" % sp.get("stand", 14.0),
                  MS + ".player(%s)" % sp.get("player", "null"),
                  (sp["aimx"].format(off=V(*off[:3]), fov=fov) if "aimx" in sp else MS + ".aim(%s, %s, %s, %s)" % (sp["target"], V(*off[:3]), fov, "true" if sp.get("local") else "false"))]
            jobs.append({"kind": "expr", "frames": 3, "exprs": ex})
            jobs.append({"kind": "expr", "frames": sp.get("wait", 80), "exprs": [MS + ".save('%s_%d.png')" % (sp["name"], k)]})
    jf = os.path.join(S, batch + ".json")
    json.dump({"out": out, "warmup": warmup, "jobs": jobs}, open(jf, "w"))
    log = os.path.join(S, batch + ".log")
    cmd = ["/Applications/Godot.app/Contents/MacOS/Godot", "--path", PROJ, "--resolution", res, "--script", "tools/shot.gd", "--", jf]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
    bad = ("leaked", "RID", "Leaked", "at: ", "still in use", "Pages in use", "never freed", "~Dependency", "ShaderRD")
    lines = [l for l in (r.stdout + r.stderr).splitlines() if not any(b in l for b in bad)]
    open(log, "w").write("\n".join(lines))
    probs = [l[:300] for l in lines if "ERROR" in l or "PARSE" in l or "rror" in l or "aimed at (0.0, 0.0, 0.0)" in l]
    print(batch, "done;", len(lines), "log lines;", len(probs), "problems")
    for p in probs[:25]: print("  ", p)
    sheets(batch, specs)

def sheets(batch, specs, per=12, tw=500):
    out = os.path.join(S, "shots", batch)
    files = []
    for sp in specs:
        for k in range(len(sp.get("offs", []))):
            f = os.path.join(out, "%s_%d.png" % (sp["name"], k))
            if os.path.exists(f): files.append(f)
        for j in sp.get("jobs", []):
            if j.get("out") and os.path.exists(os.path.join(out, j["out"])): files.append(os.path.join(out, j["out"]))
    for i in range(0, len(files), per):
        chunk = files[i:i + per]
        cols = 4; rows = (len(chunk) + cols - 1) // cols
        th = tw * 2 // 3
        sh = Image.new("RGB", (cols * tw, rows * th), (30, 30, 30))
        d = ImageDraw.Draw(sh)
        for j, f in enumerate(chunk):
            im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
            x, y = (j % cols) * tw, (j // cols) * th
            sh.paste(im, (x, y))
            lab = os.path.basename(f)[:-4]
            d.rectangle([x, y, x + 8 * len(lab) + 8, y + 16], fill=(0, 0, 0)); d.text((x + 4, y + 2), lab, fill=(255, 255, 0))
        p = os.path.join(S, "shots", "%s_sheet%d.jpg" % (batch, i // per))
        sh.save(p, quality=85); print("sheet", p)

def arr(node, prop, keys): return MS + ".g(%s, '%s', %s)" % (node, prop, json.dumps(keys).replace('"', "'"))
def ring(r, h): return [(r, h, r), (-r, h, r), (r, h, -r), (-r, h, -r)]
