# Praetor: ícone animado da Workshop (512x512, pixel art 128 ampliado 4x + título nítido).
# Loop: estandartes balançando no alto, tochas, brasas subindo, log rolando na tábua,
# ícone de cargo trocando e o martelo do pretor batendo duas vezes no bloco de mármore.
#   python gif.py   gera workshop/icone_workshop.gif/.png/.jpg e _fontes/_previa_menu.png
import math, os, random
from PIL import Image, ImageDraw, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
WS = os.path.join(RAIZ, "workshop")
ICONS = os.path.join(RAIZ, "praetor", "materials", "praetor", "icons")
FONTS = os.path.join(RAIZ, "praetor", "resource", "fonts")
os.makedirs(WS, exist_ok=True)

N, ESC, FRAMES, MS = 128, 4, 72, 70
CICLO = 24  # o martelo bate a cada 24 quadros

C = {
    "bg": (24, 18, 30), "brick": (36, 28, 44), "brickL": (46, 36, 56), "mortar": (18, 13, 22),
    "col": (150, 138, 128), "colL": (196, 186, 172), "colD": (96, 86, 82),
    "purple": (92, 38, 110), "purpleL": (128, 62, 148), "purpleD": (58, 22, 72),
    "gold": (226, 178, 96), "goldL": (255, 230, 160), "goldD": (150, 100, 44),
    "wood": (124, 78, 44), "woodL": (164, 108, 62), "woodD": (78, 46, 26),
    "marble": (214, 208, 200), "marbleD": (160, 152, 146), "marbleV": (186, 178, 170),
    "paper": (232, 220, 190), "paperD": (200, 184, 146), "ink": (60, 46, 40),
    "red": (196, 62, 50), "blue": (80, 134, 206), "green": (112, 172, 78),
    "out": (14, 10, 16), "fire1": (255, 236, 160), "fire2": (248, 160, 56), "fire3": (206, 72, 40),
    "floor": (30, 24, 36), "floorL": (40, 32, 48),
}
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def icon(nome):
    im = Image.open(os.path.join(ICONS, nome + ".png")).convert("RGBA")
    return im.resize((16, 16), Image.NEAREST)


# ---------------------------------------------------------------- fundo fixo
def fundo():
    r = random.Random(5)
    img = Image.new("RGB", (N, N), C["bg"])
    p = img.load()
    for y in range(N):
        fila = y // 6
        for x in range(N):
            if y % 6 == 0:
                c = C["mortar"]
            elif (x + (fila % 2) * 6) % 12 == 0:
                c = C["mortar"]
            else:
                c = C["brick"] if (x // 12 + fila) % 3 else C["brickL"]
                if r.random() < 0.05:
                    c = C["mortar"]
            p[x, y] = c
    # vinheta pontilhada
    for y in range(N):
        for x in range(N):
            dx, dy = (x - 64) / 64, (y - 60) / 64
            d = dx * dx + dy * dy
            if d > 0.55 and BAYER[y % 4][x % 4] < (d - 0.55) * 30:
                p[x, y] = C["mortar"]
    d = ImageDraw.Draw(img)
    # piso
    d.rectangle([0, 106, N, N], fill=C["floor"])
    for x in range(0, N, 10):
        d.line([x, 106, x - 8, N], fill=C["floorL"])
    d.line([0, 106, N, 106], fill=C["goldD"])
    # colunas
    for x0 in (0, 116):
        d.rectangle([x0, 0, x0 + 11, 105], fill=C["col"])
        for xx in range(x0 + 2, x0 + 11, 3):
            d.line([xx, 4, xx, 101], fill=C["colD"])
        d.line([x0 + 1, 0, x0 + 1, 105], fill=C["colL"])
        d.rectangle([x0 - 1, 100, x0 + 12, 105], fill=C["colL"])
        d.rectangle([x0 - 1, 103, x0 + 12, 105], fill=C["colD"])
    # suporte das tochas
    for x in (13, 112):
        d.rectangle([x, 84, x + 2, 90], fill=C["woodD"])
        d.rectangle([x - 1, 82, x + 3, 84], fill=C["goldD"])
    # bloco de mármore do martelo
    d.rectangle([45, 92, 75, 105], fill=C["out"])
    d.rectangle([46, 93, 74, 104], fill=C["marble"])
    d.rectangle([46, 101, 74, 104], fill=C["marbleD"])
    d.line([51, 94, 56, 99], fill=C["marbleV"])
    d.line([63, 95, 69, 98], fill=C["marbleV"])
    d.line([46, 93, 74, 93], fill=(240, 236, 228))
    # tábua do log (moldura)
    d.rectangle([15, 74, 41, 104], fill=C["out"])
    d.rectangle([16, 75, 40, 103], fill=C["paper"])
    d.rectangle([16, 75, 40, 76], fill=C["paperD"])
    return img


# ---------------------------------------------------------------- partes animadas
BANDEIRAS = [(22, "crown"), (56, "shield"), (90, "sword")]


def estandartes(img, f):
    p = img.load()
    for bx, nome in BANDEIRAS:
        tecido = Image.new("RGBA", (18, 30), (0, 0, 0, 0))
        d = ImageDraw.Draw(tecido)
        d.rectangle([0, 0, 17, 22], fill=C["purple"])
        d.polygon([(0, 22), (17, 22), (17, 29), (9, 24), (0, 29)], fill=C["purple"])
        d.rectangle([0, 0, 1, 26], fill=C["purpleL"])
        d.rectangle([16, 0, 17, 26], fill=C["purpleD"])
        d.line([0, 2, 17, 2], fill=C["gold"])
        d.line([0, 20, 17, 20], fill=C["gold"])
        tecido.alpha_composite(icon(nome).crop((2, 2, 14, 14)), (3, 6))
        tp = tecido.load()
        fase = 2 * math.pi * f / FRAMES + bx * 0.11
        for y in range(30):
            off = int(round(math.sin(fase + y * 0.22) * (y / 30) * 2.2))
            for x in range(18):
                c = tp[x, y]
                if c[3] == 0:
                    continue
                X, Y = bx + x + off, 4 + y
                if 0 <= X < N:
                    sombra = 0.85 if math.sin(fase + y * 0.22 + x * 0.3) < -0.4 else 1.0
                    p[X, Y] = tuple(int(v * sombra) for v in c[:3])
        # haste
        for x in range(bx - 2, bx + 20):
            p[x, 3] = C["goldD"]
            p[x, 2] = C["gold"]


def tochas(img, f):
    r = random.Random(f * 31 + 7)
    p = img.load()
    for cx in (14, 113):
        h = 7 + r.randint(0, 2)
        for y in range(h):
            larg = max(0, int((h - y) * 0.45 + r.random() * 0.8))
            for dx in range(-larg, larg + 1):
                t = y / h
                c = C["fire1"] if abs(dx) < larg * 0.4 and t < 0.6 else (C["fire2"] if t < 0.8 else C["fire3"])
                X, Y = cx + dx + (1 if (y > h // 2 and r.random() < 0.3) else 0), 81 - y
                p[X, Y] = c
        # brilho na parede
        for a in range(18):
            ang = a / 18 * 2 * math.pi
            X, Y = int(cx + math.cos(ang) * 9), int(76 + math.sin(ang) * 7)
            if BAYER[Y % 4][X % 4] < 5 + (f % 3):
                q = p[X, Y]
                p[X, Y] = (min(255, q[0] + 30), min(255, q[1] + 16), q[2])


def brasas(img, f):
    p = img.load()
    r = random.Random(11)
    for i in range(26):
        x0 = r.randrange(14, 114)
        vel = r.choice([1, 2])
        fase = r.randrange(FRAMES)
        y = 106 - (((f + fase) % FRAMES) * vel * 96 // FRAMES) % 96  # sobe 96 px por volta: fecha o loop
        x = x0 + int(round(math.sin((f + i) * 0.35) * 1.5))
        if 8 <= y < 106:
            p[x, y] = C["fire1"] if i % 3 else C["fire2"]


LINHAS = []
_r = random.Random(4)
for i in range(12):
    LINHAS.append((_r.choice(["red", "gold", "blue", "green", "gold", "red"]), _r.randint(8, 19)))


def tabua(img, f):
    p = img.load()
    rolagem = (f * 48 // FRAMES) % 48  # 12 linhas x 4 px = 48: fecha o loop
    for i in range(12 * 2):
        cor, comp = LINHAS[i % 12]
        y = 78 + i * 4 - rolagem
        if y < 78 or y > 101:
            continue
        p[18, y] = C[cor]
        p[19, y] = C[cor]
        for x in range(21, 21 + comp):
            if x < 39 and (x * 3 + i) % 7:
                p[x, y] = C["ink"]
    # linha nova piscando no fim
    if (f // 4) % 2 == 0:
        for x in range(18, 39):
            p[x, 102] = C["paperD"]


ICONES_CICLO = ["crown", "shield", "sword", "gem"]


def cargo(img, f):
    nome = ICONES_CICLO[(f // 12) % 4]
    t = f % 12
    esc = [0.4, 0.8, 1.15, 1.0][t] if t < 4 else 1.0
    lado = max(4, int(round(16 * esc)))
    ic = icon(nome).resize((lado, lado), Image.NEAREST)
    cx, cy = 99, 84
    d = ImageDraw.Draw(img)
    # pedestal
    d.rectangle([91, 94, 107, 105], fill=C["out"])
    d.rectangle([92, 95, 106, 104], fill=C["colL"])
    d.rectangle([92, 101, 106, 104], fill=C["col"])
    # aura
    raio = 10 + (1 if (f // 3) % 2 else 0)
    p = img.load()
    for a in range(28):
        ang = a / 28 * 2 * math.pi + f * 0.1
        X, Y = int(cx + math.cos(ang) * raio), int(cy + math.sin(ang) * raio)
        if a % 2 == 0:
            p[X, Y] = C["gold"] if a % 4 else C["goldL"]
    bob = int(round(math.sin(f / FRAMES * 4 * math.pi) * 1.5))
    img.paste(ic, (cx - lado // 2, cy - lado // 2 + bob), ic)


def sprite_martelo():
    s = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    # cabo (do pivô em 32,32 para a esquerda)
    d.rectangle([12, 30, 33, 33], fill=C["out"])
    d.rectangle([13, 31, 32, 32], fill=C["wood"])
    d.line([13, 31, 32, 31], fill=C["woodL"])
    # cabeça
    d.rectangle([0, 25, 15, 38], fill=C["out"])
    d.rectangle([1, 26, 14, 37], fill=C["wood"])
    d.rectangle([1, 26, 14, 27], fill=C["woodL"])
    d.rectangle([1, 35, 14, 37], fill=C["woodD"])
    for bx in (3, 11):
        d.rectangle([bx, 26, bx + 1, 37], fill=C["gold"])
    # punho dourado no pivô
    d.rectangle([30, 29, 35, 34], fill=C["out"])
    d.rectangle([31, 30, 34, 33], fill=C["gold"])
    return s


MARTELO = sprite_martelo()
PIVO = (84, 88)


def angulo(t):
    # t: quadro dentro do ciclo de 24
    if t < 14:      # sobe devagar
        return -8 - 50 * (t / 13) ** 0.8
    if t < 18:      # desce rápido
        return -58 * (1 - (t - 13) / 4) ** 2
    if t < 20:
        return 0
    return -3 * (t - 19) / 4 if t < 22 else -3 + 3 * (t - 21) / 2  # quique


def martelo(img, f):
    t = f % CICLO
    a = angulo(t)
    rot = MARTELO.rotate(a, resample=Image.NEAREST)
    img.paste(rot, (PIVO[0] - 32, PIVO[1] - 32), rot)


def impacto(img, f):
    t = (f % CICLO) - 17
    if t < 0:
        t += CICLO
    if t > 9:
        return
    p = img.load()
    r = random.Random(f // CICLO + 9)
    ox, oy = 60, 92
    # anel de choque
    if t < 5:
        raio = 3 + t * 4
        for a in range(40):
            ang = a / 40 * math.pi
            X, Y = int(ox + math.cos(ang) * raio * 1.5), int(oy - math.sin(ang) * raio * 0.55)
            if 0 <= X < N and 0 <= Y < N and BAYER[Y % 4][X % 4] < 12 - t * 2:
                p[X, Y] = C["goldL"]
    # faíscas
    for i in range(14):
        vx = r.uniform(-2.4, 2.4)
        vy = r.uniform(-3.2, -1.2)
        x = ox + vx * t
        y = oy + vy * t + 0.35 * t * t
        if 0 <= x < N and 0 <= y < 106:
            c = C["fire1"] if t < 4 else C["fire2"]
            p[int(x), int(y)] = c
            if t < 3:
                p[int(x - vx * 0.4), int(y - vy * 0.4)] = C["fire2"]


def tremor(f):
    t = f % CICLO
    return {17: (1, 1), 18: (-1, 0), 19: (1, -1)}.get(t, (0, 0))


# ---------------------------------------------------------------- título nítido
def fonte(nome, tam):
    return ImageFont.truetype(os.path.join(FONTS, nome), tam)


def texto_contorno(txt, f, cor_topo, cor_base, contorno, sombra):
    bb = f.getbbox(txt)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    pad = contorno + sombra + 4
    W, H = w + pad * 2, h + pad * 2
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((pad - bb[0], pad - bb[1]), txt, font=f, fill=255)
    # sombra
    sh = Image.new("RGBA", (W, H), (8, 4, 10, 230))
    grossa = Image.new("L", (W, H), 0)
    ImageDraw.Draw(grossa).text((pad - bb[0], pad - bb[1]), txt, font=f, fill=255, stroke_width=contorno, stroke_fill=255)
    out.paste(sh, (sombra, sombra), grossa)
    # contorno
    ct = Image.new("RGBA", (W, H), C["out"] + (255,))
    out.paste(ct, (0, 0), grossa)
    # degradê vertical
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    for y in range(H):
        k = min(1, max(0, (y - pad) / max(1, h)))
        gd.line([0, y, W, y], fill=tuple(int(cor_topo[i] * (1 - k) + cor_base[i] * k) for i in range(3)) + (255,))
    out.paste(grad, (0, 0), mask)
    return out, mask


def preparar_titulo():
    f = fonte("praetor_cinzel_black.ttf", 96)
    tit, mask = texto_contorno("PRAETOR", f, C["goldL"], C["goldD"], 7, 6)
    if tit.width > 460:
        k = 460 / tit.width
        tit = tit.resize((460, int(tit.height * k)), Image.LANCZOS)
        mask = mask.resize(tit.size, Image.LANCZOS)
    fs = fonte("praetor_barlow_bold.ttf", 34)
    sub, _ = texto_contorno("ADMIN SYSTEM", fs, (250, 244, 230), (212, 200, 184), 5, 4)
    return tit, mask, sub


TIT, TIT_MASK, SUB = preparar_titulo()


def compor_titulo(quadro, f):
    t = f % CICLO
    escala = {17: 1.09, 18: 1.06, 19: 1.03, 20: 1.01}.get(t, 1.0)
    tit = TIT
    mask = TIT_MASK
    # brilho que atravessa as letras
    faixa = Image.new("L", tit.size, 0)
    pos = int((f % CICLO) / CICLO * (tit.width + 200)) - 100
    ImageDraw.Draw(faixa).polygon([(pos, 0), (pos + 40, 0), (pos - 30, tit.height), (pos - 70, tit.height)], fill=150)
    from PIL import ImageChops
    faixa = ImageChops.multiply(faixa, mask)
    tit = tit.copy()
    tit.paste(Image.new("RGBA", tit.size, (255, 252, 230, 255)), (0, 0), faixa)
    if escala != 1.0:
        tit = tit.resize((int(tit.width * escala), int(tit.height * escala)), Image.LANCZOS)
    cy = 205
    quadro.alpha_composite(tit, (256 - tit.width // 2, cy - tit.height // 2))
    quadro.alpha_composite(SUB, (256 - SUB.width // 2, 278 - SUB.height // 2))


# ---------------------------------------------------------------- montagem
def quadro(f, base):
    img = base.copy()
    estandartes(img, f)
    tochas(img, f)
    tabua(img, f)
    cargo(img, f)
    martelo(img, f)
    impacto(img, f)
    brasas(img, f)
    dx, dy = tremor(f)
    if dx or dy:
        img = img.transform(img.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy), resample=Image.NEAREST, fillcolor=C["mortar"])
    big = img.resize((N * ESC, N * ESC), Image.NEAREST).convert("RGBA")
    compor_titulo(big, f)
    return big.convert("RGB")


def main():
    base = fundo()
    quadros = [quadro(f, base) for f in range(FRAMES)]
    # paleta única a partir de vários quadros
    amostra = Image.new("RGB", (512, 512 * 4))
    for i, f in enumerate((0, 12, 18, 30)):
        amostra.paste(quadros[f], (0, 512 * i))
    pal = amostra.quantize(colors=200, method=Image.MEDIANCUT)
    gif = [q.quantize(palette=pal, dither=Image.NONE) for q in quadros]
    destino = os.path.join(WS, "icone_workshop.gif")
    gif[0].save(destino, save_all=True, append_images=gif[1:], duration=MS, loop=0, optimize=True, disposal=1)
    print("gif %.0f KB" % (os.path.getsize(destino) / 1024))
    vitrine = quadros[19]
    vitrine.save(os.path.join(WS, "icone_workshop.png"))
    vitrine.save(os.path.join(WS, "icone_workshop.jpg"), quality=95)
    # prévia de como o menu de addons corta (y 140 a 420)
    prev = vitrine.copy()
    d = ImageDraw.Draw(prev)
    d.line([0, 140, 512, 140], fill=(255, 0, 0), width=2)
    d.line([0, 420, 512, 420], fill=(255, 0, 0), width=2)
    folha = Image.new("RGB", (512 * 3, 512))
    folha.paste(prev, (0, 0))
    folha.paste(quadros[8], (512, 0))
    folha.paste(quadros[18], (1024, 0))
    folha.save(os.path.join(AQUI, "_previa_menu.png"))


if __name__ == "__main__":
    main()
