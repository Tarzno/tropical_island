import sys, os, glob, re
from PIL import Image, ImageDraw
S = os.path.dirname(os.path.abspath(__file__))
def nat(s): return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]
def compact(batch, names=None, cols=6, tw=300, per=36, tag="c"):
    files = sorted(glob.glob(os.path.join(S, "shots", batch, "*.png")), key=lambda f: os.path.getmtime(f))
    if names: files = [f for f in files if any(os.path.basename(f).startswith(n) for n in names)]
    th = tw * 2 // 3; out = []
    for i in range(0, len(files), per):
        ch = files[i:i + per]; rows = (len(ch) + cols - 1) // cols
        sh = Image.new("RGB", (cols * tw, rows * th), (30, 30, 30)); d = ImageDraw.Draw(sh)
        for j, f in enumerate(ch):
            im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS); x, y = (j % cols) * tw, (j // cols) * th
            sh.paste(im, (x, y)); lab = os.path.basename(f)[:-4]
            d.rectangle([x, y, x + 7 * len(lab) + 6, y + 13], fill=(0, 0, 0)); d.text((x + 3, y + 1), lab, fill=(255, 255, 0))
        p = os.path.join(S, "shots", "%s_%s%d.jpg" % (batch, tag, i // per)); sh.save(p, quality=82); out.append(p)
    return out
if __name__ == "__main__":
    for p in compact(sys.argv[1], sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] else None, tag=sys.argv[3] if len(sys.argv) > 3 else "c"): print(p)
