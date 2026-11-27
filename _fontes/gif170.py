# Praetor 1.7.0: ícone animado da Oficina com cara séria.
# Fundo = telas reais do menu (quadros do vídeo em _fontes/video), escurecidas, quase em 1:1.
# No meio: PRAETOR + ADMIN SYSTEM, limpo, sem enfeite. As telas trocam com uma cortina
# vertical (uma linha roxa varre da esquerda para a direita) e o nome da seção muda embaixo.
#   python gif170.py   gera workshop/icone_workshop.gif/.png/.jpg e _fontes/_previa_gif.png
import os
from PIL import Image, ImageDraw, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
VID = os.path.join(AQUI, "video")
WS = os.path.join(RAIZ, "workshop")
FONTS = os.path.join(RAIZ, "praetor", "resource", "fonts")
BLACK = os.path.join(FONTS, "praetor_body_black.ttf")
HEAVY = os.path.join(FONTS, "praetor_body_heavy.ttf")

S = 512
WIN = (215, 90, 957, 568)          # janela do menu dentro do quadro do vídeo
ROXO = (142, 98, 255)
ROXO_CLARO = (196, 172, 255)
BRANCO = (246, 244, 252)
CINZA = (168, 162, 190)

CENAS = [
    ("players.png", "PLAYERS", 0.95),
    ("commands.png", "COMMANDS", 0.60),
    ("users.png", "PLAYER HISTORY", 0.55),
    ("restrictions.png", "RESTRICTIONS", 0.50),
    ("wiki.png", "BUILT-IN WIKI", 0.55),
]
HOLD = 1700      # ms parado em cada tela
WIPE = 10        # quadros da cortina
WIPE_MS = 40
RULE = 6         # quadros da linha crescendo depois da troca
RULE_MS = 40


def font(p, s): return ImageFont.truetype(p, s)


def tracked_w(d, text, f, sp):
    return sum(d.textlength(c, font=f) for c in text) + sp * (len(text) - 1)


def tracked(d, cx, y, text, f, fill, sp):
    x = cx - tracked_w(d, text, f, sp) / 2
    for c in text:
        d.text((x, y), c, font=f, fill=fill)
        x += d.textlength(c, font=f) + sp


def fundo(nome, foco):
    win = Image.open(os.path.join(VID, nome)).convert("RGB").crop(WIN)
    k = S / win.height                                  # 478 -> 512 (1.07x)
    win = win.resize((round(win.width * k), S), Image.LANCZOS)
    x = round((win.width - S) * foco)
    bg = win.crop((x, 0, x + S, S)).convert("RGBA")
    # escurece e tinge de roxo bem escuro; o meio fica ainda mais escuro para o título
    bg = Image.alpha_composite(bg, Image.new("RGBA", (S, S), (9, 6, 18, 140)))
    veu = Image.new("L", (S, S), 0)
    dv = ImageDraw.Draw(veu)
    for i in range(60):
        a = int(165 * (i / 60) ** 1.6)
        m = 60 - i
        dv.rounded_rectangle((m * 1.2 - 20, 150 + m * 0.9, S - m * 1.2 + 20, 414 - m * 0.9), 40, fill=a)
    bg = Image.composite(Image.new("RGBA", (S, S), (6, 4, 12, 255)), bg, veu)
    # vinheta nas bordas
    vin = Image.new("L", (S, S), 0)
    dv = ImageDraw.Draw(vin)
    for i in range(40):
        dv.rectangle((i, i, S - 1 - i, S - 1 - i), outline=int(120 * (1 - i / 40) ** 2))
    bg = Image.composite(Image.new("RGBA", (S, S), (4, 3, 8, 255)), bg, vin)
    return bg


def titulo(img, secao, regua=1.0):
    d = ImageDraw.Draw(img)
    cx = S // 2
    tracked(d, cx, 166, "GARRY'S MOD", font(HEAVY, 15), CINZA, 6)
    f = font(BLACK, 84)
    sp = 6
    while tracked_w(d, "PRAETOR", f, sp) > 430: f = font(BLACK, f.size - 2)
    tracked(d, cx + 2, 196 + 3, "PRAETOR", f, (0, 0, 0, 200), sp)
    tracked(d, cx, 196, "PRAETOR", f, BRANCO, sp)
    # linha roxa fina (cresce do centro depois de cada troca)
    meia = int(120 * regua)
    if meia > 0:
        d.rectangle((cx - meia, 304, cx + meia, 306), fill=ROXO)
    tracked(d, cx, 320, "ADMIN SYSTEM", font(HEAVY, 22), ROXO_CLARO, 7)
    # seção atual
    fs = font(HEAVY, 13)
    w = tracked_w(d, secao, fs, 4)
    y = 382
    d.ellipse((cx - w / 2 - 16, y + 5, cx - w / 2 - 9, y + 12), fill=ROXO)
    tracked(d, cx + 6, y, secao, fs, CINZA, 4)
    # moldura fina
    d.rectangle((0, 0, S - 1, S - 1), outline=(70, 52, 120))
    return img


def montar():
    fundos = [fundo(n, f) for n, _, f in CENAS]
    quadros, durs = [], []
    for i, (_, secao, _) in enumerate(CENAS):
        prox = (i + 1) % len(CENAS)
        # linha crescendo + parado
        for r in range(1, RULE + 1):
            t = r / RULE
            quadros.append(titulo(fundos[i].copy(), secao, 1 - (1 - t) ** 3))
            durs.append(RULE_MS if r < RULE else HOLD)
        # cortina: a próxima tela entra da esquerda, com uma linha roxa na borda
        for w in range(1, WIPE + 1):
            t = w / WIPE
            t = t * t * (3 - 2 * t)
            x = int(S * t)
            im = fundos[i].copy()
            if x > 0:
                im.paste(fundos[prox].crop((0, 0, x, S)), (0, 0))
            secao_q = CENAS[prox][1] if t > 0.5 else secao
            im = titulo(im, secao_q, 0.0 if w == WIPE else 1.0)
            if 0 < x < S:
                ImageDraw.Draw(im).rectangle((x - 1, 0, x + 1, S), fill=ROXO)
            quadros.append(im)
            durs.append(WIPE_MS)
    return quadros, durs


if __name__ == "__main__":
    quadros, durs = montar()
    rgb = [q.convert("RGB") for q in quadros]
    # uma paleta só para todos os quadros (assim cada quadro guarda só o que mudou)
    amostra = Image.new("RGB", (S, S * len(CENAS)))
    for i in range(len(CENAS)):
        amostra.paste(rgb[i * (RULE + WIPE) + RULE - 1], (0, S * i))
    pal = amostra.quantize(255, method=Image.MEDIANCUT)
    q = [im.quantize(palette=pal, dither=Image.NONE) for im in rgb]
    gif = os.path.join(WS, "icone_workshop.gif")
    q[0].save(gif, save_all=True, append_images=q[1:], duration=durs, loop=0, optimize=False, disposal=1)
    still = rgb[RULE - 1]
    still.save(os.path.join(WS, "icone_workshop.png"))
    still.save(os.path.join(WS, "icone_workshop.jpg"), quality=92)
    prev = Image.new("RGB", (S * 3, S * 2), (0, 0, 0))
    for i in range(len(CENAS)):
        prev.paste(rgb[i * (RULE + WIPE) + RULE - 1], ((i % 3) * S, (i // 3) * S))
    prev.paste(rgb[RULE + WIPE // 2], (2 * S, S))
    prev.save(os.path.join(AQUI, "_previa_gif.png"))
    print("ok", gif, os.path.getsize(gif) // 1024, "KB", len(q), "quadros")
