"""A rough preview of README.md as GitHub shows it: build/readme_preview.html (light) and
build/readme_preview_dark.html, each 830 points wide like the repository's front page.
    python3 tools/readme_preview.py [--shots]
Only what README.md uses is understood (HTML blocks, ## headings, paragraphs, **bold**, *italic*,
`code`, [links](..), one kind of table); GitHub's own rendering is the one that counts.
--shots also photographs both with a headless Brave or Chrome, if one is installed."""
import os, re, sys, html, subprocess
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

def inline(t):
    t = re.sub(r"`([^`]+)`", lambda m: "<code>%s</code>" % html.escape(m.group(1)), t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*([^*\n]+?)\*(?![\w*])", r"<em>\1</em>", t)
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', t)

def render(md):
    out = []
    for block in re.split(r"\n\s*\n", md.strip()):
        b = block.strip()
        if b.startswith("## "): out.append("<h2>%s</h2>" % inline(b[3:]))
        elif b.startswith("|"):
            rows = [[c.strip() for c in r.strip().strip("|").split("|")] for r in b.split("\n")]
            body = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r) for r in rows[2:])
            out.append("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % ("".join("<th>%s</th>" % c for c in rows[0]), body))
        elif b.startswith("<p") or b.startswith("<br"): out.append(b)
        else: out.append("<p>%s</p>" % inline(b))
    return "\n".join(out)

CSS = """body{margin:0;background:%(bg)s;color:%(fg)s;font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
article{width:830px;margin:0 auto;padding:32px}
h2{font-size:1.5em;font-weight:600;margin:24px 0 16px;padding-bottom:.3em;border-bottom:1px solid %(line)s}
p{margin:0 0 16px} a{color:%(link)s;text-decoration:none} img{max-width:100%%;box-sizing:content-box}
img[align=right]{padding-left:20px}
code{font:85%% ui-monospace,SFMono-Regular,Menlo,monospace;background:%(code)s;padding:.2em .4em;border-radius:6px}
kbd{display:inline-block;padding:4px 5px;font:11px ui-monospace,SFMono-Regular,Menlo,monospace;line-height:10px;color:%(fg)s;vertical-align:middle;background:%(kbd)s;border:1px solid %(kline)s;border-radius:6px;box-shadow:inset 0 -1px 0 %(kline)s}
table{border-collapse:collapse;margin:0 0 16px} th,td{padding:6px 13px;border:1px solid %(line)s;text-align:left} tbody tr:nth-child(2n){background:%(stripe)s}"""
THEMES = {"": dict(bg="#ffffff", fg="#1f2328", line="#d1d9e0", link="#0969da", code="#eff1f3", kbd="#f6f8fa", kline="#d1d9e0", stripe="#f6f8fa"),
          "_dark": dict(bg="#0d1117", fg="#f0f6fc", line="#3d444d", link="#4493f8", code="#262c36", kbd="#151b23", kline="#3d444d", stripe="#151b23")}

if __name__ == "__main__":
    body = render(open(os.path.join(ROOT, "README.md")).read())
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    for tag, th in THEMES.items():
        p = os.path.join(ROOT, "build", "readme_preview%s.html" % tag)
        open(p, "w").write('<!doctype html><meta charset="utf-8"><base href="../"><style>%s</style><article>%s</article>' % (CSS % th, body))
        print(p)
        if "--shots" in sys.argv:
            for app in ["Brave Browser", "Google Chrome", "Chromium"]:
                exe = "/Applications/%s.app/Contents/MacOS/%s" % (app, app)
                if os.path.exists(exe):
                    png = p[:-5] + ".png"
                    subprocess.run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                                    "--window-size=894,3900", "--screenshot=" + png, "file://" + p], capture_output=True, timeout=120)
                    print(png if os.path.exists(png) else "no picture from " + app); break
