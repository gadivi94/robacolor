"""Banco de pruebas: aplica looks conocidos (implementados aquí, en RGB/HSV, sin relación con el motor de la app)
a fotos reales. Para cada look g y foto i se guarda graded_g_i: sirve de referencia cuando i es la foto A
y de resultado esperado cuando i es la foto B."""
import os, sys
import numpy as np
from PIL import Image

SRC = os.environ.get('FOTOS', 'fotos/')  # carpeta con las fotos de prueba (p. ej. samples/data del repositorio de OpenCV)
OUT = os.environ.get('DATOS', 'datos/')
NAMES = ['messi5', 'home', 'fruits', 'building', 'leuvenA', 'aero1', 'aloeL', 'rgbd-color', 'butterfly', 'mcc_ccm_test']
os.makedirs(OUT, exist_ok=True)

def to_lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def to_srgb(c): c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)
def luma(rgb): return rgb @ np.array([0.2126, 0.7152, 0.0722])
def sat(rgb, s): y = luma(rgb)[..., None]; return y + (rgb - y) * s
def curve(x, pts):
    xs, ys = zip(*pts); xs, ys = np.array(xs), np.array(ys)
    # interpolación cúbica monótona (PCHIP) escrita a mano
    h = np.diff(xs); d = np.diff(ys) / h; m = np.zeros_like(xs)
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, len(xs) - 1): m[i] = 0 if d[i - 1] * d[i] <= 0 else 2 * d[i - 1] * d[i] / (d[i - 1] + d[i])
    x = np.clip(x, 0, 1); i = np.clip(np.searchsorted(xs, x, side='right') - 1, 0, len(xs) - 2)
    t = (x - xs[i]) / h[i]; t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1]
def rgb2hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1); d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx); nz = d > 1e-9
    h = np.where(nz & (mx == r), ((g - b) / np.where(nz, d, 1)) % 6, h)
    h = np.where(nz & (mx == g), (b - r) / np.where(nz, d, 1) + 2, h)
    h = np.where(nz & (mx == b), (r - g) / np.where(nz, d, 1) + 4, h)
    return h * 60, np.where(mx > 1e-9, d / np.where(mx > 1e-9, mx, 1), 0), mx
def hsv2rgb(h, s, v):
    h = (h % 360) / 60; i = np.floor(h); f = h - i; p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f)); i = i.astype(int) % 6
    return np.stack([np.choose(i, [v, q, p, p, t, v]), np.choose(i, [t, v, v, q, p, p]), np.choose(i, [p, p, t, v, v, q])], -1)
def hue_op(rgb, center, width, dh=0, ds=1.0, dv=1.0):
    h, s, v = rgb2hsv(np.clip(rgb, 0, 1))
    dist = np.abs((h - center + 180) % 360 - 180); m = np.clip(1 - dist / width, 0, 1); m = m * m * (3 - 2 * m)
    m = m * np.clip(s / 0.15, 0, 1)
    return hsv2rgb(h + dh * m, np.clip(s * (1 + (ds - 1) * m), 0, 1), np.clip(v * (1 + (dv - 1) * m), 0, 1))
def split(rgb, shadow, highlight, a_s, a_h):
    y = luma(rgb)[..., None]; ws = (1 - y) ** 2; wh = y ** 2
    ts = np.array(shadow, float); ts = ts - ts.mean(); th = np.array(highlight, float); th = th - th.mean()
    return rgb + a_s * ws * ts * 2 + a_h * wh * th * 2
def wb(rgb, r, b): lin = to_lin(np.clip(rgb, 0, 1)); lin = lin * np.array([r, 1.0, b]); return to_srgb(lin)
def expo(rgb, k): return to_srgb(to_lin(np.clip(rgb, 0, 1)) * k)

def teal_orange(x):
    x = curve(x, [(0, 0.02), (0.25, 0.21), (0.5, 0.5), (0.75, 0.80), (1, 0.98)])
    x = hue_op(x, 225, 50, dh=-25); x = hue_op(x, 110, 45, ds=0.7)
    x = split(x, (0, 0.5, 0.55), (1, 0.6, 0.2), 0.10, 0.08); return sat(x, 1.05)
def matte_film(x):
    x = curve(x, [(0, 0.0), (0.3, 0.27), (0.7, 0.74), (1, 1)]); x = 0.07 + 0.88 * x
    x = wb(x, 1.06, 0.94); x = hue_op(x, 110, 45, dh=-15, ds=0.8); x = sat(x, 0.75)
    return split(x, (0.3, 0.5, 0.6), (1, 0.9, 0.6), 0.04, 0.04)
def moody(x):
    x = expo(x, 0.72); x = curve(x, [(0, 0), (0.06, 0.0), (0.3, 0.22), (0.7, 0.76), (1, 0.97)])
    x = sat(x, 0.6); return split(x, (0.1, 0.4, 0.6), (0.9, 0.8, 0.7), 0.07, 0.02)
def golden(x):
    x = wb(x, 1.10, 0.86); x = np.clip(x, 0, 1) ** 0.92; x = hue_op(x, 40, 40, ds=1.15)
    x = sat(x, 1.18); return split(x, (0.5, 0.4, 0.3), (1, 0.8, 0.4), 0.02, 0.05)
def bw_sepia(x):
    y = luma(x)[..., None] * np.ones(3); y = curve(y, [(0, 0), (0.25, 0.19), (0.75, 0.82), (1, 1)])
    return split(y, (0.45, 0.3, 0.2), (1, 0.92, 0.75), 0.05, 0.05)
def cross(x):
    r = curve(x[..., 0], [(0, 0), (0.25, 0.20), (0.75, 0.82), (1, 1)]); g = curve(x[..., 1], [(0, 0), (0.5, 0.52), (1, 1)])
    b = curve(x[..., 2], [(0, 0.10), (0.5, 0.48), (1, 0.86)]); return sat(np.stack([r, g, b], -1), 1.1)
def cool_clean(x):
    x = wb(x, 0.94, 1.08); x = curve(x, [(0, 0), (0.25, 0.235), (0.75, 0.775), (1, 1)]); return sat(x, 0.92)
def identity(x): return x

GRADES = {'teal_orange': teal_orange, 'matte_film': matte_film, 'moody': moody, 'golden': golden, 'bw_sepia': bw_sepia, 'cross': cross, 'cool_clean': cool_clean, 'identity': identity}

def save(arr, path):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8); h, w, _ = a.shape
    rgba = np.dstack([a, np.full((h, w), 255, np.uint8)]); rgba.tofile(path); return w, h

if __name__ == '__main__':
    meta = []
    for n in NAMES:
        im = Image.open(SRC + n + '.jpg').convert('RGB'); im.thumbnail((480, 480), Image.LANCZOS)
        x = np.asarray(im, np.float64) / 255
        w, h = save(x, OUT + f'base_{n}.rgba'); meta.append(f'{n} {w} {h}')
        for g, fn in GRADES.items(): save(fn(x.copy()), OUT + f'{g}_{n}.rgba')
    open(OUT + 'meta.txt', 'w').write('\n'.join(meta) + '\n' + ' '.join(GRADES) + '\n')
    print('ok', len(meta), 'fotos x', len(GRADES), 'looks')
