"""Builds "Tropical Island - Manual.pdf" from content.py and images/.
   python3 -m venv venv && venv/bin/pip install reportlab pillow && venv/bin/python build_manual.py"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak, Flowable,
                                Table, TableStyle, KeepTogether, NextPageTemplate, FrameBreak)
from reportlab.lib.utils import ImageReader
import content as C

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "images")
OUT = os.path.join(HERE, "Tropical Island - Manual.pdf")
W, H = A4
MX, MT, MB = 17 * mm, 19 * mm, 18 * mm
CW = W - 2 * MX

# ---------------------------------------------------------------- fonts
# Nunito Sans and PT Serif, both under the SIL Open Font License 1.1 (fonts/OFL-*.txt), from the
# files in fonts/ as their makers publish them. Nunito Sans runs a step lighter than its
# weights' names say beside the serif: "Demi" is its Bold, "Bold" its ExtraBold.
FONTS = os.path.join(HERE, "fonts")
def font(name, file):
    try:
        pdfmetrics.registerFont(TTFont(name, os.path.join(FONTS, file + ".ttf"))); return True
    except Exception:
        return False
ok = all([font("Sans", "NunitoSans-Regular"), font("Sans-Med", "NunitoSans-Medium"), font("Sans-Demi", "NunitoSans-Bold"),
          font("Sans-Bold", "NunitoSans-ExtraBold"), font("Sans-It", "NunitoSans-Italic"),
          font("Serif", "PTSerif-Regular"), font("Serif-Bold", "PTSerif-Bold"), font("Serif-It", "PTSerif-Italic"), font("Serif-BoldIt", "PTSerif-BoldItalic")])
if ok:
    pdfmetrics.registerFontFamily("Serif", normal="Serif", bold="Serif-Bold", italic="Serif-It", boldItalic="Serif-BoldIt")
    pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Demi", italic="Sans-It", boldItalic="Sans-Demi")
    SANS, SANS_M, SANS_D, SANS_B, SERIF, SERIF_I = "Sans", "Sans-Med", "Sans-Demi", "Sans-Bold", "Serif", "Serif-It"
else:   # without the files in fonts/: the PDF's built-in fonts
    SANS = SANS_M = "Helvetica"; SANS_D = SANS_B = "Helvetica-Bold"; SERIF = "Times-Roman"; SERIF_I = "Times-Italic"

# ---------------------------------------------------------------- colors
LAGOON = colors.HexColor("#0B5563"); DEEP = colors.HexColor("#083B46"); SAND = colors.HexColor("#F5EFE3")
CORAL = colors.HexColor("#C8553A"); INK = colors.HexColor("#1E2A2D"); GRAY = colors.HexColor("#5E6B6E")
RULE = colors.HexColor("#D9D2C3"); PALE = colors.HexColor("#E7F1F1")
TAGCOL = {"E": colors.HexColor("#2E7D4F"), "I": colors.HexColor("#8A6D3B"), "R": CORAL, "N": colors.HexColor("#3B4C8A")}
TAGNAME = {"E": "ENDEMIC", "I": "INTRODUCED", "R": "RARE", "N": "DUSK & NIGHT"}

def st(name, **kw):
    base = dict(fontName=SERIF, fontSize=10, leading=14, textColor=INK, alignment=TA_LEFT)
    base.update(kw); return ParagraphStyle(name, **base)
BODY = st("body", fontSize=10.2, leading=14.6, spaceAfter=6)
SMALL = st("small", fontSize=9.1, leading=12.4)
H1 = st("h1", fontName=SANS_B, fontSize=22, leading=26, textColor=LAGOON, spaceAfter=3)
H2 = st("h2", fontName=SANS_D, fontSize=13, leading=16, textColor=LAGOON, spaceBefore=8, spaceAfter=3)
KICK = st("kick", fontName=SANS_D, fontSize=8, leading=10, textColor=CORAL)
LEAD = st("lead", fontName=SERIF_I, fontSize=11.5, leading=16, textColor=GRAY, spaceAfter=8)
NAME = st("name", fontName=SANS_D, fontSize=11.6, leading=13.5, textColor=DEEP)
SCI = st("sci", fontName=SERIF_I, fontSize=9, leading=11.5, textColor=GRAY)
WHERE = st("where", fontName=SANS, fontSize=8, leading=10.3, textColor=LAGOON)
DESC = st("desc", fontSize=9.2, leading=12.1)
CAP = st("cap", fontName=SANS, fontSize=7.6, leading=9.6, textColor=GRAY)

def img(slug): return os.path.join(IMG, slug + ".jpg")

def rounded_image(c, path, x, y, w, h, r=2.2 * mm):
    c.saveState()
    p = c.beginPath(); p.roundRect(x, y, w, h, r); c.clipPath(p, stroke=0, fill=0)
    iw, ih = ImageReader(path).getSize(); s = max(w / iw, h / ih)
    c.drawImage(path, x + (w - iw * s) / 2, y + (h - ih * s) / 2, iw * s, ih * s)
    c.restoreState()

class Picture(Flowable):
    """A picture with rounded corners, optionally with a caption under it."""
    def __init__(self, slug, w, h, caption=None):
        super().__init__(); self.slug, self.w, self.h, self.caption = slug, w, h, caption
        self.cp = Paragraph(caption, CAP) if caption else None
    def wrap(self, aw, ah):
        self.ch = self.cp.wrap(self.w, 100)[1] + 2 * mm if self.cp else 0
        return self.w, self.h + self.ch
    def draw(self):
        rounded_image(self.canv, img(self.slug), 0, self.ch, self.w, self.h)
        if self.cp: self.cp.drawOn(self.canv, 0, 0)

class Row(Flowable):
    """Several things side by side (pictures, mostly)."""
    def __init__(self, items, gap=4 * mm):
        super().__init__(); self.items, self.gap = items, gap
    def wrap(self, aw, ah):
        self.sizes = [i.wrap(aw, ah) for i in self.items]
        return aw, max(s[1] for s in self.sizes)
    def draw(self):
        x = 0; hh = max(s[1] for s in self.sizes)
        for i, s in zip(self.items, self.sizes):
            i.canv = self.canv
            self.canv.saveState(); self.canv.translate(x, hh - s[1]); i.draw(); self.canv.restoreState()
            x += s[0] + self.gap

class Species(Flowable):
    """One line of the field guide: the picture on the left, the words on the right, a box to tick."""
    PW, PH = 66 * mm, 44 * mm
    def __init__(self, slug, name, sci, tag, where, desc):
        super().__init__()
        self.slug, self.tag = slug, tag
        self.p = [Paragraph(name, NAME), Paragraph(sci, SCI), Paragraph("<font name='%s'>WHERE</font>  %s" % (SANS_D, where), WHERE), Paragraph(desc, DESC)]
        self.gaps = [0.6 * mm, 1.6 * mm, 1.7 * mm, 0]
    def wrap(self, aw, ah):
        self.aw = aw; self.tx = self.PW + 6 * mm; self.tw = aw - self.tx
        hs = [self.p[0].wrap(self.tw - 9 * mm, 500)[1]] + [q.wrap(self.tw, 500)[1] for q in self.p[1:]]
        self.hs = hs; self.th = sum(hs) + sum(self.gaps) + (5.2 * mm if self.tag else 0)
        self.h = max(self.PH, self.th) + 6.3 * mm
        return aw, self.h
    def draw(self):
        c = self.canv; top = self.h - 1.5 * mm
        rounded_image(c, img(self.slug), 0, top - self.PH, self.PW, self.PH)
        y = top
        # the box to tick
        c.setStrokeColor(LAGOON); c.setLineWidth(0.9); c.roundRect(self.aw - 5.2 * mm, top - 5.2 * mm, 5 * mm, 5 * mm, 1 * mm)
        if self.tag:
            x = self.tx
            for t in self.tag:
                label = TAGNAME[t]; c.setFont(SANS_D, 6.2); tw = c.stringWidth(label, SANS_D, 6.2) + 4 * mm
                c.setFillColor(TAGCOL[t]); c.roundRect(x, y - 3.9 * mm, tw, 3.9 * mm, 1.9 * mm, stroke=0, fill=1)
                c.setFillColor(colors.white); c.drawString(x + 2 * mm, y - 2.85 * mm, label); x += tw + 1.5 * mm
            y -= 5.2 * mm
        for q, hq, g in zip(self.p, self.hs, self.gaps):
            q.drawOn(c, self.tx, y - hq); y -= hq + g
        c.setStrokeColor(RULE); c.setLineWidth(0.5); c.line(0, 1.6 * mm, self.aw, 1.6 * mm)

class Band(Flowable):
    """A section heading: a band of lagoon color."""
    def __init__(self, title, sub, n):
        super().__init__(); self.title, self.n = title, n
        self.sub = Paragraph(sub, st("bs", fontName=SERIF_I, fontSize=9.6, leading=12.5, textColor=colors.white))
    def wrap(self, aw, ah):
        self.aw = aw; self.sh = self.sub.wrap(aw - 12 * mm, 200)[1]
        self.h = 13 * mm + self.sh; return aw, self.h + 4 * mm
    def draw(self):
        c = self.canv; c.setFillColor(LAGOON); c.roundRect(0, 4 * mm, self.aw, self.h, 2.5 * mm, stroke=0, fill=1)
        c.setFillColor(colors.white); c.setFont(SANS_B, 14.5); c.drawString(6 * mm, 4 * mm + self.h - 8.2 * mm, self.title)
        c.setFont(SANS_M, 8); c.setFillColor(colors.HexColor("#BFE0E0"))
        c.drawRightString(self.aw - 6 * mm, 4 * mm + self.h - 7.6 * mm, "%d to find" % self.n)
        self.sub.drawOn(c, 6 * mm, 4 * mm + 3 * mm)

class Key(Flowable):
    """A key cap."""
    def __init__(self, text): super().__init__(); self.text = text
    def wrap(self, aw, ah):
        self.w = max(pdfmetrics.stringWidth(self.text, SANS_D, 8.2) + 5 * mm, 8 * mm); return self.w, 6.2 * mm
    def draw(self):
        c = self.canv; c.setFillColor(colors.white); c.setStrokeColor(LAGOON); c.setLineWidth(0.8)
        c.roundRect(0, 0.4 * mm, self.w, 5.4 * mm, 1.3 * mm, stroke=1, fill=1)
        c.setFillColor(DEEP); c.setFont(SANS_D, 8.2); c.drawCentredString(self.w / 2, 2.0 * mm, self.text)

class Map(Flowable):
    """The island from above with numbered places, north up. The picture shows 560 m, its middle
    at x = -45, z = 0; in the game +x is west and +z north, so +x lies to the left and +z up."""
    def __init__(self, size): super().__init__(); self.size = size
    def wrap(self, aw, ah): return self.size, self.size * 0.86
    def draw(self):
        c = self.canv; s = self.size; hh = s * 0.86; cut = (s - hh) / 2
        c.saveState(); p = c.beginPath(); p.roundRect(0, 0, s, hh, 3 * mm); c.clipPath(p, stroke=0, fill=0)
        c.drawImage(img("map"), 0, -cut, s, s); c.restoreState()
        for n, x, z, name, text in C.PLACES:
            px = (0.5 - (x + 45.0) / 560.0) * s; py = (0.5 + z / 560.0) * s - cut
            c.setFillColor(CORAL); c.setStrokeColor(colors.white); c.setLineWidth(1.1); c.circle(px, py, 2.9 * mm, stroke=1, fill=1)
            c.setFillColor(colors.white); c.setFont(SANS_B, 7.6); c.drawCentredString(px, py - 0.95 * mm, str(n))
        # north arrow and scale
        c.setFillColor(colors.white); c.setStrokeColor(colors.white); c.setLineWidth(1.2)
        ax, ay = s - 11 * mm, hh - 17 * mm; c.line(ax, ay, ax, ay + 9 * mm)
        p = c.beginPath(); p.moveTo(ax, ay + 11 * mm); p.lineTo(ax - 1.6 * mm, ay + 7.4 * mm); p.lineTo(ax + 1.6 * mm, ay + 7.4 * mm); p.close(); c.drawPath(p, fill=1, stroke=0)
        c.setFont(SANS_D, 8); c.drawCentredString(ax, ay - 3.4 * mm, "N")
        bar = 100.0 / 560.0 * s; bx, by = 8 * mm, 7 * mm; c.line(bx, by, bx + bar, by); c.line(bx, by - 1 * mm, bx, by + 1 * mm); c.line(bx + bar, by - 1 * mm, bx + bar, by + 1 * mm)
        c.setFont(SANS_M, 7.5); c.drawCentredString(bx + bar / 2, by + 1.6 * mm, "100 m")

# ---------------------------------------------------------------- pages
def cover(c, doc):
    c.saveState()
    path = img("cover"); iw, ih = ImageReader(path).getSize(); s = max(W / iw, H / ih)
    c.drawImage(path, (W - iw * s) / 2, (H - ih * s) / 2, iw * s, ih * s)
    # (the veil of deep sea color under the words is part of the picture: prep_images.py)
    c.setFillColor(colors.white); c.setFont(SANS_B, 46); c.drawString(MX + 3 * mm, 58 * mm, C.TITLE)
    c.setFont(SERIF_I, 17); c.drawString(MX + 3.6 * mm, 45 * mm, C.SUBTITLE)
    c.setStrokeColor(colors.Color(1, 1, 1, alpha=0.7)); c.setLineWidth(0.8); c.line(MX + 3.6 * mm, 38.5 * mm, MX + 60 * mm, 38.5 * mm)
    c.setFont(SANS, 9.5); c.drawString(MX + 3.6 * mm, 31 * mm, "A granite island in the Seychelles  ·  day, moon and tide by your clock  ·  %d plants and animals to find" % COUNT)
    c.restoreState()

def later(c, doc):
    c.saveState(); c.setFont(SANS, 7.8); c.setFillColor(GRAY)
    c.drawString(MX, 10 * mm, "TROPICAL ISLAND"); c.drawRightString(W - MX, 10 * mm, str(doc.page))
    c.drawCentredString(W / 2, 10 * mm, getattr(doc, "running", ""))
    c.setStrokeColor(RULE); c.setLineWidth(0.5); c.line(MX, 13.5 * mm, W - MX, 13.5 * mm); c.restoreState()

class Running(Flowable):
    """Sets the words in the middle of the page's foot."""
    def __init__(self, text): super().__init__(); self.text = text
    def wrap(self, aw, ah): return 0, 0
    def draw(self): self.canv._doctemplate.running = self.text

COUNT = sum(len(s[2]) for s in C.SECTIONS)

def bullets(items, style=SMALL, gap=3.2):
    out = []
    for t in items:
        out.append(Table([[Paragraph("<font color='#C8553A'>&#8226;</font>", style), Paragraph(t, style)]], colWidths=[4.5 * mm, None],
                         style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                                           ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), gap)])))
    return out

def build():
    doc = BaseDocTemplate(OUT, pagesize=A4, leftMargin=MX, rightMargin=MX, topMargin=MT, bottomMargin=MB,
                          title="Tropical Island: a walker's manual and field guide", author="Hanno Teeling", subject="Manual")
    full = Frame(MX, MB, CW, H - MT - MB, id="full", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate("cover", [Frame(0, 0, W, H, id="c")], onPage=cover), PageTemplate("page", [full], onPageEnd=later)])
    S = [NextPageTemplate("page"), Spacer(1, 1), PageBreak()]

    # ---- welcome and controls
    S += [Running("Getting started"), Paragraph("WELCOME", KICK), Paragraph("An island to yourself", H1), Spacer(1, 2 * mm)]
    S += [Paragraph(C.WELCOME[0], LEAD)] + [Paragraph(t, BODY) for t in C.WELCOME[1:]]
    S += [Spacer(1, 2 * mm), Paragraph("Controls", H2)]
    rows = [[Key(k), Paragraph(v, SMALL)] for k, v in C.CONTROLS]
    half = (len(rows) + 1) // 2; colw = [33 * mm, CW / 2 - 33 * mm - 3 * mm]
    def keytab(r): return Table(r, colWidths=colw, style=TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 2.2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.2), ("LINEBELOW", (0, 0), (-1, -2), 0.4, RULE)]))
    S += [Table([[keytab(rows[:half]), keytab(rows[half:])]], colWidths=[CW / 2, CW / 2], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (0, 0), 8), ("LEFTPADDING", (1, 0), (1, 0), 8), ("RIGHTPADDING", (1, 0), (1, 0), 0)]))]
    S += [Spacer(1, 3 * mm), Paragraph("Good to know", H2)] + bullets(C.GOOD_TO_KNOW)
    S += [PageBreak()]

    # ---- the island
    S += [Running("The island"), Paragraph("THE ISLAND", KICK), Paragraph("Where things are", H1), Spacer(1, 1 * mm),
          Paragraph("About 190 meters wide and 420 long from north to south, in a lagoon ringed by a reef. No paths, no signs: the map below is all the guidance there is. North is up; you arrive on the west coast.", LEAD)]
    ms = 112 * mm
    legend = []
    for n, x, z, name, text in C.PLACES:
        legend.append([Paragraph("<font name='%s' color='#C8553A'>%d</font>" % (SANS_B, n), st("ln", fontName=SANS_B, fontSize=9.5, leading=11)),
                       Paragraph("<font name='%s' color='#083B46'>%s.</font> %s" % (SANS_D, name, text), st("lt", fontSize=8.5, leading=11))])
    lt = Table(legend, colWidths=[6 * mm, CW - ms - 6 * mm - 6 * mm], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.6)]))
    S += [Table([[Map(ms), lt]], colWidths=[ms + 6 * mm, CW - ms - 6 * mm], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0)]))]
    pw = (CW - 2 * 4 * mm) / 3
    S += [Spacer(1, 3 * mm), Row([Picture("summit", pw, pw * 2 / 3, "From the summit, looking west over the start beach and the reef."),
                                 Picture("grotto", pw, pw * 2 / 3, "The grotto's inner room: roots hang through a gap in the roof."),
                                 Picture("snorkel", pw, pw * 2 / 3, "Face in the water: seagrass, coral heads and the reef beyond.")])]
    S += [Spacer(1, 4 * mm)]
    for k, (title, text) in enumerate(C.MORE[:2]):
        S += [Spacer(1, 2.2 * mm)] if k else []
        S += [Paragraph("<font name='%s' color='#0B5563'>%s.</font> %s" % (SANS_D, title, text), SMALL)]
    S += [PageBreak()]

    # ---- a living world
    S += [Running("A living world"), Paragraph("A LIVING WORLD", KICK), Paragraph("Day, moon, tide and weather", H1), Spacer(1, 1 * mm),
          Paragraph("The island's cycles run by themselves, at their natural pace, and agree with each other. Each has a key, so you can also set any combination you like.", LEAD)]
    pw4 = (CW - 3 * 3 * mm) / 4
    S += [Row([Picture("day_noon", pw4, pw4 * 2 / 3, "Midday"), Picture("day_golden", pw4, pw4 * 2 / 3, "Golden hour"),
               Picture("day_sunset", pw4, pw4 * 2 / 3, "Sunset"), Picture("day_night", pw4, pw4 * 2 / 3, "Night, full moon")], gap=3 * mm), Spacer(1, 3 * mm)]
    pics = {"The moon and the stars": [("moon", "A full moon over the lagoon."), ("bat", "A fruit bat crosses the night sky.")],
            "The tide": [("tide_high", "The east headland at high water ..."), ("tide_low", "... and at low water, with its tide pools.")],
            "Rain": [("rain", "A shower on the start beach."), ("rainbow", "As the sun returns: a rainbow, far off.")],
            "The glowing sea": [("glow", "Surf lit blue by plankton.")]}
    pw2 = 47 * mm
    for title, key, text in C.FEATURES:
        if title == "Rain":
            S.append(PageBreak())
        head = Table([[Paragraph(title, H2), Key(key)]], colWidths=[None, 12 * mm], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 1), ("TOPPADDING", (0, 0), (-1, -1), 0), ("ALIGN", (1, 0), (1, 0), "RIGHT")]))
        pp = pics.get(title, [])
        if pp:
            right = Row([Picture(s_, pw2, pw2 * 2 / 3, cap) for s_, cap in pp], gap=3 * mm)
            rw = len(pp) * pw2 + (len(pp) - 1) * 3 * mm
            block = Table([[[head, Paragraph(text, SMALL)], right]], colWidths=[CW - rw - 5 * mm, rw + 5 * mm], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, 0), 0), ("RIGHTPADDING", (0, 0), (0, 0), 0), ("LEFTPADDING", (1, 0), (1, 0), 5 * mm), ("RIGHTPADDING", (1, 0), (1, 0), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (1, 0), (1, 0), 9), ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]))
        else:
            block = Table([[[head, Paragraph(text, SMALL)]]], colWidths=[CW], style=TableStyle([("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0)]))
        S += [KeepTogether([block, Spacer(1, 3.5 * mm)])]
    t, x = C.MORE[2]
    S += [Paragraph("<font name='%s' color='#0B5563'>%s.</font> %s" % (SANS_D, t, x), SMALL)]
    S += [Spacer(1, 3 * mm), Paragraph("How to meet the wildlife", H2)] + bullets(C.TIPS)
    S += [Spacer(1, 5 * mm), Picture("sunset_wide", CW, CW * 0.36, "Sunset from the summit. The sun goes down over the sea off the start beach.")]
    S += [PageBreak()]

    # ---- the field guide
    S += [Running("Field guide"), Paragraph("FIELD GUIDE", KICK), Paragraph("%d plants and animals to find" % COUNT, H1), Spacer(1, 1 * mm), Paragraph(C.GUIDE_INTRO, LEAD)]
    # the tags' legend
    cells = []
    for k in "EIRN":
        cells.append(Table([[TagPill(k), Paragraph(C.TAGS[k], st("tg", fontName=SANS, fontSize=8, leading=10, textColor=GRAY))]], colWidths=[25 * mm, None],
                           style=TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 1.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5)])))
    S += [Spacer(1, 2 * mm), Table([[cells[0], cells[1]], [cells[2], cells[3]]], colWidths=[CW / 2, CW / 2],
          style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), SAND), ("LEFTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                            ("ROUNDEDCORNERS", [6, 6, 6, 6])])), Spacer(1, 5 * mm)]
    first = True
    for title, sub, items in C.SECTIONS:
        rows = [Species(*it) for it in items]
        head = [Running("Field guide  ·  " + title), Band(title, sub, len(items))]
        if not first: S.append(Spacer(1, 3 * mm))
        S.append(KeepTogether(head + [rows[0]])); S += rows[1:]
        first = False
    S += [PageBreak()]

    # ---- the list to tick, and who made it
    S += [Running("Checklist"), Paragraph("CHECKLIST", KICK), Paragraph("Have you found them all?", H1), Spacer(1, 2 * mm)]
    flat = []
    for title, sub, items in C.SECTIONS:
        flat.append(Paragraph(title.upper(), st("ch", fontName=SANS_D, fontSize=7.2, leading=9.5, textColor=CORAL, spaceBefore=5, spaceAfter=1.5)))
        flat += [Tick(it[1]) for it in items]
    per = (len(flat) + 2) // 3; cols = [flat[:per], flat[per:2 * per], flat[2 * per:]]
    for k in range(2):      # (a heading never stands last in its column)
        while cols[k] and isinstance(cols[k][-1], Paragraph):
            cols[k + 1].insert(0, cols[k].pop())
    S += [Table([cols], colWidths=[CW / 3] * 3, style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 6)]))]
    S += [Spacer(1, 6 * mm), Table([[[Paragraph(c_, st("cr", fontName=SERIF_I, fontSize=9.5, leading=13.5, textColor=DEEP)) for c_ in C.CREDITS] +
                                    [Spacer(1, 2 * mm), Paragraph(C.COLOPHON, st("co", fontName=SANS, fontSize=7.8, leading=10.5, textColor=GRAY))]]], colWidths=[CW],
                                  style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), SAND), ("LEFTPADDING", (0, 0), (-1, -1), 12), ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                                                    ("TOPPADDING", (0, 0), (-1, -1), 9), ("BOTTOMPADDING", (0, 0), (-1, -1), 9), ("ROUNDEDCORNERS", [6, 6, 6, 6])]))]
    doc.build(S)
    print("written", OUT, "-", COUNT, "species")

class TagPill(Flowable):
    def __init__(self, k): super().__init__(); self.k = k
    def wrap(self, aw, ah): return 24 * mm, 4.4 * mm
    def draw(self):
        c = self.canv; label = TAGNAME[self.k]; tw = c.stringWidth(label, SANS_D, 6.2) + 4 * mm
        c.setFillColor(TAGCOL[self.k]); c.roundRect(0, 0.3 * mm, tw, 3.9 * mm, 1.9 * mm, stroke=0, fill=1)
        c.setFillColor(colors.white); c.setFont(SANS_D, 6.2); c.drawString(2 * mm, 1.35 * mm, label)

class Tick(Flowable):
    def __init__(self, name): super().__init__(); self.name = name
    def wrap(self, aw, ah): return aw, 4.95 * mm
    def draw(self):
        c = self.canv; c.setStrokeColor(LAGOON); c.setLineWidth(0.7); c.roundRect(0, 0.8 * mm, 3.2 * mm, 3.2 * mm, 0.6 * mm)
        c.setFillColor(INK); c.setFont(SERIF, 8.8); c.drawString(5.2 * mm, 1.3 * mm, self.name)

if __name__ == "__main__":
    build()
