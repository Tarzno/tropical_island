"""The pictures of README.md, written to docs/readme/ (WebP with rounded, transparent corners,
so they sit well on GitHub's light and dark pages alike):
  hero.webp     the banner: the island from over the lagoon, with the title
  day.webp      four hours of the day at one place
  guide.webp    twelve of the field guide's plants and animals
  reef.webp     under water
  map.webp      the island from above
  btn_*.webp    the two buttons;  wave.svg  the ornament between sections
    python3 tools/readme_art.py        needs Pillow (with WebP); a few seconds
Typefaces as in the manual: Nunito Sans and PT Serif, from manual/fonts/ (SIL Open Font
License 1.1). The species' names come from manual/content.py, their pictures from manual/images/,
so after a change there run this again. The two pictures in docs/readme/source/ were taken in
the game with the test driver at 2400x1040, midday (the reef at high water:
"main.get_node('IslandLife/Tide').set_state(1, true)" first):
  hero  {"kind": "shot", "pos": [105, 30, 70], "yaw": 78, "pitch": -8, "fov": 40}
  reef  {"kind": "shot", "pos": [47, -0.6, 11], "yaw": -60, "pitch": -22, "fov": 62, "frames": 220}"""
import os, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFont, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "docs", "readme")
IMG = os.path.join(ROOT, "manual", "images")
sys.path.insert(0, os.path.join(ROOT, "manual"))
import content

FONTS = os.path.join(ROOT, "manual", "fonts")
# (the weights as in manual/build_manual.py: Nunito Sans Bold where a demi-bold is meant,
# ExtraBold for the title)
def sans(size, face="Bold"): return ImageFont.truetype(os.path.join(FONTS, "NunitoSans-%s.ttf" % face), size)
def serif(size, face="Italic"): return ImageFont.truetype(os.path.join(FONTS, "PTSerif-%s.ttf" % face), size)

W = 1800                      # every full-width picture; GitHub shows them at about half that
GAP = 24                      # between tiles
TILE = ((W - 3 * GAP) // 4, 288)   # four tiles a row, 3:2
CORAL, TEAL, DEEP = (200, 85, 58), (18, 124, 136), (8, 59, 70)
WHITE = (255, 255, 255, 255)

# the twelve of the field guide, row by row (picture in manual/images, how far right its subject is)
GUIDE = [("tortoise", .45), ("tropicbird", .5), ("cocodemer", .5), ("gecko", .5),
         ("greenturtle", .5), ("manta", .5), ("idol", .5), ("lionfish", .5),
         ("ghostcrab", .5), ("pitcher", .5), ("blacktip", .5), ("jellyfish", .5)]
DAY = [("day_noon", "Midday"), ("day_golden", "Golden hour"), ("day_sunset", "Sunset"), ("day_night", "Night")]


def species():
    """picture name -> (name, scientific name), from the manual's own list"""
    found = {}
    def walk(o):
        if isinstance(o, tuple) and len(o) >= 6 and all(isinstance(x, str) for x in o[:3]):
            found[o[0]] = (o[1], o[2]); return
        if isinstance(o, (list, tuple)):
            for x in o: walk(x)
        elif isinstance(o, dict):
            for x in o.values(): walk(x)
    for n in dir(content):
        if n.isupper(): walk(getattr(content, n))
    return found


def rounded(im, r):
    """transparent round corners, smooth"""
    w, h = im.size
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], r * 4, fill=255)
    im = im.convert("RGBA"); im.putalpha(m.resize((w, h), Image.LANCZOS))
    return im


def shade(im, color, y0, y1, a_max, power=1.6):
    """blends toward a color, from nothing at y0 to a_max at y1 (y1 may lie above y0)"""
    w, h = im.size
    col = Image.new("L", (1, h), 0)
    for y in range(h):
        t = (y - y0) / float(y1 - y0)
        t = min(1.0, max(0.0, t))
        col.putpixel((0, y), int(255 * a_max * t ** power))
    return Image.composite(Image.new("RGB", (w, h), color), im.convert("RGB"), col.resize((w, h)))


def with_shadow(base, over, blur=7, strength=0.6, tint=(4, 30, 50)):
    """lays `over` (RGBA) on `base` with a soft shadow under whatever it holds"""
    w, h = base.size
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.paste(tint + (255,), (0, 0), over.split()[3].point(lambda v: int(v * strength)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    low = Image.new("RGBA", (w, h), (0, 0, 0, 0)); low.paste(sh, (0, 3), sh)
    return Image.alpha_composite(Image.alpha_composite(base.convert("RGBA"), low), over)


def tracked(d, xy, text, font, fill, track):
    """text with wider letter spacing; returns its width"""
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + track
    return x - xy[0]


def cover(path, size, cx=.5, cy=.5):
    """the picture cut to fill `size`, keeping the point (cx, cy) as near the middle as it can"""
    im = Image.open(path).convert("RGB")
    w, h = size
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x = min(max(0, round(im.width * cx - w / 2)), im.width - w)
    y = min(max(0, round(im.height * cy - h / 2)), im.height - h)
    return im.crop((x, y, x + w, y + h))


def tile(path, title, sub=None, cx=.5):
    w, h = TILE
    im = shade(cover(path, TILE, cx), (0, 18, 26), h * 0.45, h, 0.82, 1.25)
    over = Image.new("RGBA", TILE, (0, 0, 0, 0)); d = ImageDraw.Draw(over)
    if sub:
        d.text((22, h - 88), title, font=sans(32), fill=WHITE)
        d.text((22, h - 46), sub, font=serif(25), fill=(255, 255, 255, 232))
    else:
        d.text((22, h - 60), title, font=sans(34), fill=WHITE)
    return rounded(with_shadow(im, over, 4, 0.5), 20)


def sheet(tiles):
    rows = (len(tiles) + 3) // 4
    out = Image.new("RGBA", (W, rows * TILE[1] + (rows - 1) * GAP), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % 4) * (TILE[0] + GAP), (i // 4) * (TILE[1] + GAP)), t)
    return out


def hero():
    im = Image.open(os.path.join(OUT, "source", "hero.jpg")).convert("RGB")
    h = round(im.height * W / im.width)
    im = im.resize((W, h), Image.LANCZOS)
    im = shade(im, (22, 70, 132), h * 0.34, 0, 0.42, 1.4)        # the sky deeper behind the title
    im = shade(im, DEEP, h * 0.70, h, 0.80, 1.5)                 # the lagoon deeper behind the last line
    over = Image.new("RGBA", (W, h), (0, 0, 0, 0)); d = ImageDraw.Draw(over)
    d.text((84, 54), content.TITLE, font=sans(118, "ExtraBold"), fill=WHITE)
    d.text((90, 196), "A walk on a granite island in the Seychelles", font=serif(42), fill=(255, 255, 255, 248))
    x, y, f = 90, h - 80, sans(27, "Medium")
    for i, part in enumerate(["NO GOALS, NO HURRY", "DAY, MOON AND TIDE BY YOUR CLOCK",
                              "%d PLANTS AND ANIMALS TO FIND" % len(species())]):
        if i:
            d.ellipse([x + 18, y + 15, x + 25, y + 22], fill=(255, 255, 255, 200)); x += 46
        x += tracked(d, (x, y), part, f, (255, 255, 255, 240), 2.6)
    d.line([(90, h - 106), (300, h - 106)], fill=(255, 255, 255, 150), width=2)
    return rounded(with_shadow(im, over, 9, 0.62), 34)


def reef():
    im = cover(os.path.join(OUT, "source", "reef.jpg"), (W, 560), .5, .62)
    im = ImageEnhance.Color(ImageEnhance.Contrast(im).enhance(1.12)).enhance(1.10)   # the water's veil a little thinner
    im = shade(im, (0, 30, 40), 560 * 0.55, 560, 0.66, 1.4)
    over = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(over)
    d.text((48, 560 - 124), "Below the surface", font=sans(44), fill=WHITE)
    d.text((50, 560 - 66), "A coral head in the lagoon, some forty meters from the beach", font=serif(31), fill=(255, 255, 255, 235))
    return rounded(with_shadow(im, over, 5, 0.5), 30)


def island_map():
    im = Image.open(os.path.join(IMG, "map.jpg")).convert("RGB").crop((300, 130, 1310, 1340))
    im = im.resize((640, round(640 * im.height / im.width)), Image.LANCZOS)
    over = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(over)
    x, y = im.width - 66, 42                                    # north is up
    d.polygon([(x, y), (x - 14, y + 38), (x, y + 29), (x + 14, y + 38)], fill=(255, 255, 255, 235))
    d.text((x - 11, y + 44), "N", font=sans(30), fill=(255, 255, 255, 235))
    return rounded(with_shadow(im, over, 4, 0.5), 30)


def button(text, color, arrow):
    f = sans(40); pad, h = 56, 108
    tw = round(ImageDraw.Draw(Image.new("RGB", (8, 8))).textlength(text, font=f))
    w = pad + 44 + 22 + tw + pad
    big = Image.new("RGBA", (w * 3, h * 3), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * 3 - 1, h * 3 - 1], h * 3 // 2, fill=color + (255,))
    im = big.resize((w, h), Image.LANCZOS); d = ImageDraw.Draw(im)
    cx, cy, lw = pad + 20, h // 2, 6
    if arrow == "down":
        d.line([(cx, cy - 20), (cx, cy + 12)], fill=WHITE, width=lw)
        d.line([(cx - 14, cy - 2), (cx, cy + 13), (cx + 14, cy - 2)], fill=WHITE, width=lw, joint="curve")
        d.line([(cx - 18, cy + 26), (cx + 18, cy + 26)], fill=WHITE, width=lw)
    else:
        d.line([(cx - 16, cy), (cx + 14, cy)], fill=WHITE, width=lw)
        d.line([(cx, cy - 15), (cx + 15, cy), (cx, cy + 15)], fill=WHITE, width=lw, joint="curve")
    d.text((pad + 44 + 22, cy - 28), text, font=f, fill=WHITE)
    return im


WAVE = '''<svg xmlns="http://www.w3.org/2000/svg" width="168" height="22" viewBox="0 0 168 22" role="img" aria-label="">
  <path d="M4 11 q10 -13 20 0 t20 0 t20 0 t20 0 t20 0 t20 0 t20 0 t20 0" fill="none" stroke="#1F9AA6" stroke-width="2.6" stroke-linecap="round"/>
</svg>
'''

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sp = species()
    made = {
        "hero.webp": hero(),
        "day.webp": sheet([tile(os.path.join(IMG, p + ".jpg"), t) for p, t in DAY]),
        "guide.webp": sheet([tile(os.path.join(IMG, p + ".jpg"), sp[p][0], sp[p][1], cx) for p, cx in GUIDE]),
        "reef.webp": reef(),
        "map.webp": island_map(),
        "btn_download.webp": button("Download for macOS", CORAL, "down"),
        "btn_guide.webp": button("Read the field guide", TEAL, "right"),
    }
    for name, im in made.items():
        p = os.path.join(OUT, name)
        im.save(p, "WEBP", quality=88, method=6)
        print("%-18s %4d x %-4d %4d KB" % (name, im.width, im.height, os.path.getsize(p) // 1024))
    open(os.path.join(OUT, "wave.svg"), "w").write(WAVE)
    print(len(sp), "species in the manual")
