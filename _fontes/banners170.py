# Praetor 1.7.0: banners da Oficina a partir do vídeo do menu (quadros em _fontes/video).
# Estilo sério: fundo = a própria cena escurecida, a janela do menu em 1:1 (nítida,
# nunca ampliada) à direita, título limpo à esquerda (inglês grande, português embaixo).
# Uso: python banners170.py  ->  workshop/banner_1..5.jpg (1280x720) + _previa_banners.png
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
VID = os.path.join(AQUI, "video")
FONTS = os.path.join(RAIZ, "praetor", "resource", "fonts")
OUT = os.path.join(RAIZ, "workshop")

W, H = 1280, 720
ROXO = (142, 98, 255)
ROXO_CLARO = (188, 160, 255)
BRANCO = (244, 242, 252)
CINZA = (176, 170, 198)

BLACK = os.path.join(FONTS, "praetor_body_black.ttf")
HEAVY = os.path.join(FONTS, "praetor_body_heavy.ttf")
BODY = os.path.join(FONTS, "praetor_body.ttf")

def font(path, size): return ImageFont.truetype(path, size)

# janela do menu dentro do quadro de 1176x660
WIN = (215, 90, 957, 568)

BANNERS = [
    ("players.png", "ADMIN SYSTEM", "Run your server\nfrom one menu", "Gerencie o servidor por um menu só",
     ["Players, ranks, bans, logs and reports", "ULX / SAM alternative, imports both"],
     ["Jogadores, cargos, bans, logs e denúncias", "Alternativa ao ULX / SAM, importa os dois"]),
    ("commands.png", "COMMANDS", "Every command,\nexplained", "Todos os comandos, explicados",
     ["Click one to fill its arguments", "Chat, silent and console, with clear errors"],
     ["Clique em um para preencher os argumentos", "Chat, silencioso e console, com erros claros"]),
    ("users.png", "PLAYER HISTORY", "Everything about\nevery player", "Tudo sobre cada jogador",
     ["Warnings, bans, notes and linked accounts", "Full history, even offline"],
     ["Avisos, bans, anotações e contas ligadas", "Histórico completo, até offline"]),
    ("restrictions.png", "RESTRICTIONS", "Block any weapon,\nprop or tool", "Bloqueie qualquer arma, prop ou ferramenta",
     ["Blacklist, admin only or from a rank up", "Live preview of every model"],
     ["Bloqueado, só admin ou a partir de um cargo", "Prévia de cada modelo"]),
    ("wiki.png", "BUILT-IN WIKI", "A guide for\nyour whole staff", "Um guia para toda a sua staff",
     ["Setup, staff mode, webhooks and more", "In English and Portuguese, with search"],
     ["Configuração, modo staff, webhooks e mais", "Em inglês e português, com busca"]),
]

def background(frame):
    # um quadro do vídeo sem o menu aberto (a mesma praça), sem a vida do HUD
    frame = Image.open(os.path.join(VID, "scene.png")).convert("RGB")
    # a cena inteira, 1176 -> 1280 (1.09x, dentro do limite), escurecida e com um véu à esquerda
    bg = frame.resize((W, round(frame.height * W / frame.width)), Image.LANCZOS)
    bg = bg.crop((0, (bg.height - H) // 2, W, (bg.height - H) // 2 + H)) if bg.height >= H else bg.resize((W, H), Image.LANCZOS)
    bg = bg.convert("RGBA")
    dark = Image.new("RGBA", (W, H), (10, 7, 20, 175))
    bg = Image.alpha_composite(bg, dark)
    veil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(veil)
    for x in range(W):
        a = int(max(0, min(1, (620 - x) / 520)) * 140)
        d.line((x, 0, x, H), fill=(8, 6, 16, a))
    return Image.alpha_composite(bg, veil)

def tracked(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing
    return x

def build(spec):
    name, label, title, pt, feats, feats_pt = spec
    frame = Image.open(os.path.join(VID, name)).convert("RGB")
    img = background(frame)

    # janela do menu em 1:1 à direita, com sombra suave e borda fina
    win = frame.crop(WIN)
    wx, wy = W - win.width - 40, (H - win.height) // 2 + 14
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((wx - 6, wy + 4, wx + win.width + 10, wy + win.height + 16), 18, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, sh)
    img.paste(win, (wx, wy))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((wx - 1, wy - 1, wx + win.width, wy + win.height), 12, outline=ROXO + (200,), width=2)

    # texto à esquerda (coluna de 0 a wx - 30)
    x = 52
    col_w = wx - 30 - x
    y = 112
    tracked(d, (x, y), "PRAETOR", font(BLACK, 22), ROXO_CLARO, 5)
    d.rectangle((x, y + 36, x + 46, y + 39), fill=ROXO)
    tracked(d, (x + 60, y + 29), label, font(HEAVY, 14), CINZA, 3)
    y += 76
    # título EN: maior tamanho que cabe na coluna
    size = 56
    while size > 30:
        f = font(BLACK, size)
        if max(d.textlength(l, font=f) for l in title.split("\n")) <= col_w: break
        size -= 2
    f = font(BLACK, size)
    for line in title.split("\n"):
        d.text((x + 2, y + 3), line, font=f, fill=(0, 0, 0, 160))
        d.text((x, y), line, font=f, fill=BRANCO)
        y += int(size * 1.12)
    y += 6
    fp = font(HEAVY, 24)
    while d.textlength(pt, font=fp) > col_w and fp.size > 16: fp = font(HEAVY, fp.size - 1)
    d.text((x, y), pt, font=fp, fill=ROXO_CLARO)
    y += 58
    # recursos: EN em branco, PT em cinza embaixo
    fe, fpt = font(HEAVY, 17), font(BODY, 15)
    for en, p in zip(feats, feats_pt):
        d.ellipse((x, y + 7, x + 8, y + 15), fill=ROXO)
        d.text((x + 20, y), en, font=fe, fill=BRANCO)
        d.text((x + 20, y + 23), p, font=fpt, fill=CINZA)
        y += 56
    # rodapé
    d.text((x, H - 58), "by Mano Gustavo", font=font(BODY, 15), fill=(150, 144, 172))
    return img.convert("RGB")

if __name__ == "__main__":
    outs = []
    for i, spec in enumerate(BANNERS, 1):
        im = build(spec)
        p = os.path.join(OUT, "banner_%d.jpg" % i)
        im.save(p, quality=93, subsampling=0)
        outs.append(im)
        print("ok", p)
    prev = Image.new("RGB", (W, H * len(outs) // 2 + H // 2))
    for i, im in enumerate(outs):
        prev.paste(im.resize((W // 2, H // 2), Image.LANCZOS), ((i % 2) * W // 2, (i // 2) * H // 2))
    prev.save(os.path.join(AQUI, "_previa_banners.png"))
