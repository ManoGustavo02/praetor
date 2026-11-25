# Praetor 1.5.0: ícone animado da Workshop = a logo do Praetor no estilo da interface nova
# (contorno grosso, sombra dura, pílulas, animação de mola).
# Loop: o selo do capacete entra girando, as letras de PRAETOR pulam uma a uma,
# o adesivo "ADMIN SYSTEM" carimba, o capacete pisca e tudo respira.
#   python logo150.py   gera workshop/icone_workshop.gif/.png/.jpg
import math, os
from PIL import Image, ImageDraw, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
WS = os.path.join(RAIZ, "workshop")
FONTS = os.path.join(RAIZ, "praetor", "resource", "fonts")

OUT = 512
K = 2                      # desenha em 2x e reduz (borda lisa)
W = OUT * K
FRAMES, MS = 48, 66

INK = (8, 6, 16)
BG = (13, 11, 22)
PANEL = (26, 21, 48)
IVORY = (244, 241, 255)
ACC = (142, 98, 255)
ACC_L = (188, 160, 255)
ACC_D = (92, 58, 190)
YEL = (255, 211, 107)
PINK = (255, 143, 198)

DISPLAY = os.path.join(FONTS, "praetor_display.ttf")
BLACK = os.path.join(FONTS, "praetor_body_black.ttf")


def ease_back(t):
    t = max(0.0, min(1.0, t))
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2


def clamp01(t):
    return max(0.0, min(1.0, t))


# ---------------------------------------------------------------- fundo fixo: retícula + vinheta
def make_bg():
    im = Image.new("RGB", (W, W), BG)
    d = ImageDraw.Draw(im)
    step = 22 * K // 2
    cx = cy = W / 2
    for y in range(0, W + step, step):
        off = (y // step) % 2 * step / 2
        for x in range(0, W + step, step):
            px = x + off
            dist = math.hypot(px - cx, y - cy) / (W * 0.72)
            r = (1 - clamp01(dist)) * 3.2 * K
            if r > 0.6:
                d.ellipse((px - r, y - r, px + r, y + r), fill=(40, 30, 74))
    return im


def rays(d, phase):
    # linhas de ação saindo do centro; dois grupos que se revezam
    cx, cy = W / 2, W * 0.40
    n = 40
    for i in range(n):
        if (i % 2) != phase:
            continue
        a = i / n * math.tau
        da = 0.022
        r1, r2 = W * 0.30, W * 0.95
        pts = [
            (cx + math.cos(a - da) * r2, cy + math.sin(a - da) * r2),
            (cx + math.cos(a + da) * r2, cy + math.sin(a + da) * r2),
            (cx + math.cos(a) * r1, cy + math.sin(a) * r1),
        ]
        d.polygon(pts, fill=(34, 27, 62) if i % 5 else (52, 36, 104))


def star(d, x, y, r, col):
    pts = []
    for i in range(8):
        a = i / 8 * math.tau - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.32
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    d.polygon(pts, fill=col)


# ---------------------------------------------------------------- o capacete (mesmo desenho do narrador da tela de loading)
def helmet(size, blink):
    s = size / 100.0
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def P(x, y):
        return (x * s, y * s)

    # crista: arco grosso (contorno escuro + roxo claro)
    def arc_pts():
        pts = []
        for i in range(25):
            t = i / 24
            # curva quadrática (30,30) -> (50,-4) -> (74,24)
            x = (1 - t) ** 2 * 30 + 2 * (1 - t) * t * 50 + t ** 2 * 74
            y = (1 - t) ** 2 * 30 + 2 * (1 - t) * t * -4 + t ** 2 * 24
            pts.append(P(x, y))
        return pts
    pts = arc_pts()
    d.line(pts, fill=INK, width=int(17 * s), joint="curve")
    for p in (pts[0], pts[-1]):
        r = 8.5 * s
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=INK)
    d.line(pts, fill=ACC_L, width=int(10 * s), joint="curve")
    for p in (pts[0], pts[-1]):
        r = 5 * s
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=ACC_L)
    # cúpula + protetores do rosto
    body = [P(20, 60)]
    for i in range(21):
        t = i / 20
        x = (1 - t) ** 2 * 20 + 2 * (1 - t) * t * 20 + t ** 2 * 50
        y = (1 - t) ** 2 * 60 + 2 * (1 - t) * t * 22 + t ** 2 * 22
        body.append(P(x, y))
    for i in range(21):
        t = i / 20
        x = (1 - t) ** 2 * 50 + 2 * (1 - t) * t * 80 + t ** 2 * 80
        y = (1 - t) ** 2 * 22 + 2 * (1 - t) * t * 22 + t ** 2 * 60
        body.append(P(x, y))
    body += [P(72, 84), P(58, 76), P(58, 64), P(42, 64), P(42, 76), P(28, 84)]
    d.polygon(body, fill=IVORY, outline=INK)
    d.line(body + [body[0]], fill=INK, width=int(5 * s), joint="curve")
    # viseira
    d.rounded_rectangle((*P(27, 42), *P(73, 62)), radius=9 * s, fill=(18, 14, 32), outline=INK, width=int(3 * s))
    # olhos
    ry = 0.8 if blink else 5
    for ex in (40, 60):
        d.ellipse((*P(ex - 4, 52 - ry), *P(ex + 4, 52 + ry)), fill=(255, 253, 245))
    return im


# ---------------------------------------------------------------- texto com contorno + sombra dura
def outlined_text(base, text, font, x, y, fill, stroke, shadow_col, shadow_off, angle=0.0, scale=1.0):
    # desenha numa camada própria para poder girar/escalar letra por letra
    bbox = font.getbbox(text, stroke_width=stroke)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = stroke + shadow_off + 10
    layer = Image.new("RGBA", (tw + pad * 2, th + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = pad - bbox[0], pad - bbox[1]
    if shadow_col:
        d.text((ox + shadow_off, oy + shadow_off), text, font=font, fill=shadow_col, stroke_width=stroke, stroke_fill=shadow_col)
    d.text((ox, oy), text, font=font, fill=fill, stroke_width=stroke, stroke_fill=INK)
    if scale != 1.0:
        nw, nh = max(1, int(layer.width * scale)), max(1, int(layer.height * scale))
        layer = layer.resize((nw, nh), Image.LANCZOS)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    base.alpha_composite(layer, (int(x - layer.width / 2), int(y - layer.height / 2)))


def frame(i, bg):
    t = i / FRAMES
    im = bg.copy().convert("RGBA")
    d = ImageDraw.Draw(im)
    rays(d, 0)

    # brilhinhos piscando
    spots = [(0.13, 0.16, 0.0), (0.86, 0.12, 0.33), (0.90, 0.58, 0.66), (0.08, 0.62, 0.5), (0.74, 0.30, 0.15), (0.24, 0.34, 0.8)]
    for k, (sx, sy, ph) in enumerate(spots):
        a = (math.sin((t + ph) * math.tau * 2) + 1) / 2
        if a > 0.15:
            star(d, sx * W, sy * W, (10 + 14 * a) * K, YEL if k % 2 == 0 else PINK)

    # ---------------- selo do capacete: entra girando com mola, depois respira
    cx, cy = W / 2, W * 0.31
    k_in = ease_back(clamp01(i / 12))
    breathe = 1
    R = int(W * 0.205 * k_in * breathe)
    if R > 4:
        badge = Image.new("RGBA", (R * 2 + 40 * K, R * 2 + 40 * K), (0, 0, 0, 0))
        bd = ImageDraw.Draw(badge)
        o = 10 * K
        bd.ellipse((o + 12 * K, o + 12 * K, o + 2 * R + 12 * K, o + 2 * R + 12 * K), fill=INK)
        bd.ellipse((o, o, o + 2 * R, o + 2 * R), fill=ACC, outline=IVORY, width=11 * K)
        # anel interno tracejado, girando devagar
        rr = R - 26 * K
        for j in range(24):
            a0 = j / 24 * 360 + t * 90
            bd.arc((o + R - rr, o + R - rr, o + R + rr, o + R + rr), a0, a0 + 7, fill=ACC_L, width=4 * K)
        hs = int(R * 1.42)
        blink = i in (34, 35, 44)
        h = helmet(hs, blink)
        badge.alpha_composite(h, (int(o + R - hs / 2), int(o + R - hs / 2 + R * 0.06)))
        ang = (1 - k_in) * -160 + math.sin(t * math.tau) * 3
        badge = badge.rotate(ang, resample=Image.BICUBIC, expand=False)
        im.alpha_composite(badge, (int(cx - badge.width / 2), int(cy - badge.height / 2)))

    # ---------------- PRAETOR: letras pulando uma a uma e depois ondulando
    word = "PRAETOR"
    font = ImageFont.truetype(DISPLAY, 92 * K)
    widths = [font.getlength(ch) for ch in word]
    gap = -2 * K
    total = sum(widths) + gap * (len(word) - 1)
    x = W / 2 - total / 2
    base_y = W * 0.625
    for j, ch in enumerate(word):
        start = 6 + j * 2.2
        k = clamp01((i - start) / 7)
        if k <= 0:
            x += widths[j] + gap
            continue
        sc = 0.3 + 0.7 * ease_back(k)
        wave = math.sin((t * 2 - j * 0.11) * math.tau) * 5 * K if i > start + 7 else 0
        rot = (1 - k) * 25
        outlined_text(im, ch, font, x + widths[j] / 2, base_y - (1 - k) * 60 * K + wave, IVORY, 7 * K, ACC_D, 8 * K, rot, sc)
        x += widths[j] + gap

    # ---------------- adesivo "ADMIN SYSTEM" carimbando, inclinado
    ks = clamp01((i - 20) / 6)
    if ks > 0:
        sf = ImageFont.truetype(BLACK, 34 * K)
        label = "ADMIN SYSTEM"
        tw = sf.getlength(label)
        pw, ph = int(tw + 50 * K), int(54 * K)
        st = Image.new("RGBA", (pw + 14 * K, ph + 14 * K), (0, 0, 0, 0))
        sd = ImageDraw.Draw(st)
        sd.rounded_rectangle((7 * K, 7 * K, pw + 7 * K, ph + 7 * K), radius=ph // 2, fill=INK)
        sd.rounded_rectangle((0, 0, pw, ph), radius=ph // 2, fill=YEL, outline=INK, width=6 * K)
        bb = sf.getbbox(label)
        sd.text((pw / 2 - (bb[2] + bb[0]) / 2, ph / 2 - (bb[3] + bb[1]) / 2), label, font=sf, fill=INK)
        sc = 2.0 - 1.0 * ease_back(ks)
        st = st.resize((max(1, int(st.width * sc)), max(1, int(st.height * sc))), Image.LANCZOS)
        st = st.rotate(-4 + (1 - ks) * 14 + math.sin(t * math.tau) * 1.2, resample=Image.BICUBIC, expand=True)
        if ks < 1:
            a = st.getchannel("A").point(lambda v: int(v * ks))
            st.putalpha(a)
        im.alpha_composite(st, (int(W / 2 - st.width / 2), int(W * 0.765 - st.height / 2)))

    # moldura de painel de quadrinho
    d = ImageDraw.Draw(im)
    d.rectangle((6 * K, 6 * K, W - 6 * K, W - 6 * K), outline=IVORY, width=7 * K)
    return im.convert("RGB").resize((OUT, OUT), Image.LANCZOS)


def main():
    bg = make_bg()
    frames = [frame(i, bg) for i in range(FRAMES)]
    # paleta única para todos os quadros: menos tremido e arquivo menor
    pal_src = Image.new("RGB", (OUT, OUT * 3))
    for n, fi in enumerate((frames[12], frames[30], frames[-1])):
        pal_src.paste(fi, (0, OUT * n))
    pal = pal_src.quantize(colors=64, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    # segura o quadro final um pouco antes de recomeçar
    durs = [MS] * FRAMES
    durs[-1] = 600
    gif = os.path.join(WS, "icone_workshop.gif")
    q[0].save(gif, save_all=True, append_images=q[1:], duration=durs, loop=0, optimize=True, disposal=1)
    still = frames[-1]
    still.save(os.path.join(WS, "icone_workshop.png"))
    still.save(os.path.join(WS, "icone_workshop.jpg"), quality=92)
    print("gif", os.path.getsize(gif) // 1024, "KB")


if __name__ == "__main__":
    main()
