"""The picture behind the icons in the disk image's window: dmg/backdrop_source.jpg (taken in
the game: tools/shot.gd at 2160x1500, {"kind": "shot", "pos": [75, 28, 5], "yaw": 97.5,
"pitch": -13.5, "fov": 62}, midday) with the title, an arrow and a deeper sea under the icons'
names (Finder writes them black in light mode and white in dark mode: both must be readable).
  python3 dmg/make_background.py [--mock]      needs Pillow; writes build/dmg/background*.png
The layout (window, icon places) is in LAYOUT below; tools/build_dmg.sh reads it from here
(--shell), so the arrow in the picture and the icons in the window cannot drift apart."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "build", "dmg")
# the manual's typefaces (manual/fonts/: Nunito Sans and PT Serif, SIL Open Font License 1.1)
FONTS = os.path.join(HERE, "..", "manual", "fonts")
def face(name, size): return ImageFont.truetype(os.path.join(FONTS, name + ".ttf"), size)

# in points, as Finder counts them (the picture is drawn at twice that for Retina screens)
# Measured in Finder on macOS 27 (2026-11-12): the title bar takes 28 points, a tab bar (View >
# Show Tab Bar) another 40, and Finder brings up a scroll bar as soon as the window's inside is
# lower than an icon's middle + half its size + some 55 to 60 points. So the window is made a
# little lower than the picture (window_h: no empty strip under it), and the icons stand high
# enough for a window with a tab bar (window_h - 40) to hold them without scrolling.
LAYOUT = dict(width=720, height=500, window_h=496, icon=100, text=13,
              app=(150, 340), apps=(360, 340), manual=(570, 340))
W, H = LAYOUT["width"], LAYOUT["height"]
NOTE = "First start: if macOS will not open the app, allow it under System Settings \u203a Privacy & Security \u203a \u201cOpen Anyway\u201d."
NOTE_FACE = "NunitoSans-Medium"

def render(scale):
    w, h = W * scale, H * scale
    im = Image.open(os.path.join(HERE, "backdrop_source.jpg")).convert("RGB").resize((w, h), Image.LANCZOS)
    px = im.load()
    # the sea deepens toward the viewer: the icons' names stand on a mid-dark teal
    deep = (10, 92, 110)
    y0, y1 = 296 * scale, 420 * scale
    for y in range(y0, h):
        t = min(1.0, (y - y0) / float(y1 - y0))
        a = 0.66 * t * t * (3 - 2 * t)
        for x in range(w):
            r, g, b = px[x, y]
            px[x, y] = (int(r + (deep[0] - r) * a), int(g + (deep[1] - g) * a), int(b + (deep[2] - b) * a))
    # the sky a little deeper at the top, for the title
    top = (24, 74, 138)
    for y in range(0, 150 * scale):
        a = 0.34 * (1 - y / float(150 * scale)) ** 1.5
        for x in range(w):
            r, g, b = px[x, y]
            px[x, y] = (int(r + (top[0] - r) * a), int(g + (top[1] - g) * a), int(b + (top[2] - b) * a))

    over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    f_title = face("NunitoSans-ExtraBold", 38 * scale)
    f_sub = face("PTSerif-Italic", 15 * scale)
    f_hint = face("PTSerif-Italic", 13 * scale)
    tx = 40 * scale
    d.text((tx, 26 * scale), "Tropical Island", font=f_title, fill=(255, 255, 255, 255))
    d.text((tx + 2 * scale, 76 * scale), "A walk on a granite island in the Seychelles", font=f_sub, fill=(255, 255, 255, 245))
    # the arrow from the app to the Applications folder
    ax0, ax1 = (LAYOUT["app"][0] + 72) * scale, (LAYOUT["apps"][0] - 72) * scale
    ay = (LAYOUT["app"][1] - 6) * scale
    lw = 5 * scale
    d.line([(ax0, ay), (ax1, ay)], fill=(255, 255, 255, 235), width=lw)
    hd = 13 * scale
    d.line([(ax1 - hd, ay - hd), (ax1, ay), (ax1 - hd, ay + hd)], fill=(255, 255, 255, 235), width=lw, joint="curve")
    for cx, cy in [(ax0, ay), (ax1, ay), (ax1 - hd, ay - hd), (ax1 - hd, ay + hd)]:
        d.ellipse([cx - lw / 2, cy - lw / 2, cx + lw / 2, cy + lw / 2], fill=(255, 255, 255, 235))
    hint = "drag to install"
    tw = d.textlength(hint, font=f_hint)
    d.text(((ax0 + ax1) / 2 - tw / 2, ay + 20 * scale), hint, font=f_hint, fill=(255, 255, 255, 240))
    # The first start, in one line under the icons' names: the app is signed ad hoc and not
    # notarized, so a Mac that got the image over the net refuses it until its owner allows it.
    # (Low enough to clear the names, high enough for a window with a tab bar: 456 points.)
    f_note = face(NOTE_FACE, 11 * scale)
    tw = d.textlength(NOTE, font=f_note)
    d.text((w / 2 - tw / 2, 428 * scale), NOTE, font=f_note, fill=(255, 255, 255, 235))
    # a soft shadow under everything drawn
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    alpha = over.split()[3].point(lambda v: int(v * 0.55))
    sh.paste((6, 40, 70, 255), (0, 0), alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(5 * scale))
    off = Image.new("RGBA", (w, h), (0, 0, 0, 0)); off.paste(sh, (0, 2 * scale), sh)
    im = Image.alpha_composite(im.convert("RGBA"), off)
    im = Image.alpha_composite(im, over)
    return im.convert("RGB")

def mock(im, scale):
    """Roughly what Finder will put on top, to judge the picture without building an image."""
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", LAYOUT["text"] * scale)   # (Finder's own; the mock is not part of the image)
    s = LAYOUT["icon"] * scale
    icon = Image.open(os.path.join(HERE, "..", "icon.png")).convert("RGBA").resize((s, s), Image.LANCZOS)
    cov = Image.open(os.path.join(HERE, "..", "manual", "images", "cover.jpg")).convert("RGB")
    cov = cov.resize((int(s * 0.707), s), Image.LANCZOS)
    for key, lab, col in [("app", "Tropical Island", (255, 255, 255)), ("apps", "Applications", (0, 0, 0)), ("manual", "Tropical Island - Manual", (255, 255, 255))]:
        cx, cy = LAYOUT[key][0] * scale, LAYOUT[key][1] * scale
        if key == "app": im.paste(icon, (cx - s // 2, cy - s // 2), icon)
        elif key == "manual": im.paste(cov, (cx - cov.width // 2, cy - s // 2))
        else: d.rounded_rectangle([cx - s * 0.42, cy - s * 0.34, cx + s * 0.42, cy + s * 0.36], 8 * scale, fill=(70, 160, 235))
        tw = d.textlength(lab, font=f)
        d.text((cx - tw / 2, cy + s // 2 + 5 * scale), lab, font=f, fill=col)
        d.text((cx - tw / 2, cy + s // 2 + 22 * scale), lab, font=f, fill=(255 - col[0],) * 3)
    return im

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if "--shell" in sys.argv:      # for tools/build_dmg.sh: eval "$(python3 dmg/make_background.py --shell)"
        L = LAYOUT
        print("BG_W=%d BG_H=%d WIN_H=%d ICON=%d TEXT=%d APP_X=%d APP_Y=%d APPS_X=%d APPS_Y=%d MAN_X=%d MAN_Y=%d" % (
            L["width"], L["height"], L["window_h"], L["icon"], L["text"], *L["app"], *L["apps"], *L["manual"]))
        sys.exit(0)
    one, two = render(1), render(2)
    one.save(os.path.join(OUT, "background.png")); two.save(os.path.join(OUT, "background@2x.png"))
    if "--mock" in sys.argv:
        mock(two, 2).save(os.path.join(OUT, "mock.png"))
    print("background 720x500 and 1440x1000 in", os.path.normpath(OUT))
