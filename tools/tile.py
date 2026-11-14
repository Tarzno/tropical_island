import sys, numpy as np
from PIL import Image, ImageFilter
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(np.float32) / 255.0
H, W, _ = a.shape
# remove low-frequency lighting gradient (keep mean color)
blur = np.asarray(im.filter(ImageFilter.GaussianBlur(H / 6))).astype(np.float32) / 255.0
mean = a.reshape(-1, 3).mean(0)
if mode in ('flat', 'bark'):
    a = a / np.maximum(blur, 1e-3) * mean
if mode == 'bark':
    col = a.mean(axis=(0, 2), keepdims=True)
    a = a / np.maximum(col, 1e-3) * a.mean()
a = np.clip(a, 0, 1)
# seamless: blend with half-rolled copy
r = np.roll(np.roll(a, H // 2, 0), W // 2, 1)
y = np.abs(np.linspace(-1, 1, H))[:, None]
x = np.abs(np.linspace(-1, 1, W))[None, :]
w = np.clip((1 - np.maximum(x, y)) / 0.35, 0, 1)
w = w * w * (3 - 2 * w)
out = a * w[..., None] + r * (1 - w[..., None])
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(dst)
if len(sys.argv) > 4:
    # normal map from luminance high-pass
    lum = out @ np.array([0.299, 0.587, 0.114])
    lb = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
    s = float(sys.argv[5]) if len(sys.argv) > 5 else 4.0
    dx = (np.roll(lb, -1, 1) - np.roll(lb, 1, 1)) * s
    dy = (np.roll(lb, -1, 0) - np.roll(lb, 1, 0)) * s
    n = np.stack([-dx, dy, np.ones_like(dx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(sys.argv[4])
