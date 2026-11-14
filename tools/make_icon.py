# Turns a square artwork into a macOS-style app icon (1024 x 1024 PNG):
# superellipse ("squircle") on Apple's icon grid (824 px body, centered), soft drop shadow,
# faint top highlight and a thin inner rim. Usage: python3 make_icon.py art.png out.png
import sys
import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
S = 1024
BODY = 824
SS = 4  # supersampling for a smooth edge

art = Image.open(src).convert("RGB")
w, h = art.size
side = min(w, h)
art = art.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2)).resize((BODY, BODY), Image.LANCZOS)

# superellipse mask |x|^n + |y|^n <= 1
n = 5.0
g = (np.arange(BODY * SS) + 0.5) / (BODY * SS) * 2 - 1
X, Y = np.meshgrid(g, g)
m = (np.abs(X) ** n + np.abs(Y) ** n <= 1.0).astype(np.float32)
m = m.reshape(BODY, SS, BODY, SS).mean(axis=(1, 3))
mask = Image.fromarray((m * 255).astype(np.uint8))

a = np.asarray(art).astype(np.float32) / 255.0
# faint glossy highlight toward the top, slight darkening at the bottom
yy = np.linspace(0, 1, BODY)[:, None, None]
a = a * (1.0 - 0.10 * yy ** 2) + 0.06 * np.clip(1.0 - yy * 2.5, 0, 1)
# thin light rim just inside the edge
edge = np.asarray(mask.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0
rim = np.clip((1.0 - edge) * 2.0, 0, 1) * (m > 0.5)
a = a + rim[..., None] * 0.18
body = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
body.putalpha(mask)

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = (S - BODY) // 2
# drop shadow
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow_mask = Image.new("L", (S, S), 0)
shadow_mask.paste(mask, (off, off + 12))
sh.putalpha(shadow_mask.point(lambda v: int(v * 0.32)).filter(ImageFilter.GaussianBlur(14)))
canvas = Image.alpha_composite(canvas, sh)
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
layer.paste(body, (off, off), body)
canvas = Image.alpha_composite(canvas, layer)
canvas.save(dst)
print("saved", dst)
