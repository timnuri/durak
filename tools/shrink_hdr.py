#!/usr/bin/env python3
"""Уменьшает .hdr (Radiance RGBE) для отражений.  python3 tools/shrink_hdr.py in.hdr out.hdr [ширина=1024]"""
import sys, numpy as np

def read_hdr(p):
    f = open(p, 'rb'); line = b''
    while True:
        line = f.readline()
        if line.strip() == b'': break
    dims = f.readline().split(); h, w = int(dims[1]), int(dims[3])
    data = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        hdr = f.read(4)
        if hdr[0] == 2 and hdr[1] == 2 and (hdr[2] << 8 | hdr[3]) == w:
            for c in range(4):
                x = 0
                while x < w:
                    n = f.read(1)[0]
                    if n > 128:
                        n -= 128; v = f.read(1)[0]; data[y, x:x + n, c] = v
                    else:
                        data[y, x:x + n, c] = np.frombuffer(f.read(n), np.uint8)
                    x += n
        else:
            rest = np.frombuffer(hdr + f.read(4 * w - 4), np.uint8).reshape(w, 4); data[y] = rest
    e = data[..., 3].astype(np.float32)
    s = np.where(e > 0, np.ldexp(1.0, (e - 136).astype(np.int32)), 0.0)
    return data[..., :3].astype(np.float32) * s[..., None]

def write_hdr(p, img):
    h, w, _ = img.shape
    m = img.max(axis=2)
    mant, ex = np.frexp(m)
    sc = np.where(m > 1e-32, mant * 256.0 / np.maximum(m, 1e-32), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(img * sc[..., None], 0, 255).astype(np.uint8)
    out[..., 3] = np.where(m > 1e-32, ex + 128, 0).astype(np.uint8)
    with open(p, 'wb') as f:
        f.write(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n' % (h, w)); f.write(out.tobytes())

img = read_hdr(sys.argv[1]); W = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
h, w, _ = img.shape; k = w // W
img = img[:h // k * k, :W * k].reshape(h // k, k, W, k, 3).mean(axis=(1, 3))
write_hdr(sys.argv[2], img); print(sys.argv[2], img.shape, float(img.max()))
