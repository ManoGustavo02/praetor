# Praetor 1.5.0 + 1.7.0 (ícones de DarkRP): ícones no estilo "adesivo cartoon" (cor + contorno escuro grosso
# + sombra dura), feitos a partir do Tabler Icons (MIT, github.com/tabler/tabler-icons).
# Uso: python icones_v2.py <pasta com node_modules (@resvg/resvg-js e @tabler/icons)>
# Grava praetor/materials/praetor/icons/<nome>.png (64x64) e _fontes/icones_v3_preview.png.
import os, sys, json, subprocess
from PIL import Image, ImageFilter, ImageChops

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
SAIDA = os.path.join(RAIZ, "praetor", "materials", "praetor", "icons")
KIT = sys.argv[1]
TABLER = os.path.join(KIT, "node_modules", "@tabler", "icons", "icons")
TMP = os.path.join(KIT, "render")
os.makedirs(TMP, exist_ok=True)

BIG = 256          # desenha grande e reduz para 64 (bordas lisas)
INK = (16, 12, 28, 255)

COR = {
    "gold": "#ffc94a", "red": "#ff5c6c", "green": "#5cdc8a", "blue": "#5aaaff", "violet": "#ac86ff",
    "ice": "#86e6ff", "bone": "#f2ede2", "orange": "#ff9a42", "pink": "#ff7cc0", "white": "#f6f4ff",
    "grey": "#bcbcd2", "brown": "#d49a62", "teal": "#4ee0c8",
}

# nome: (candidatos do Tabler, cor)
BASE = {
    "afk": (["zzz"], "ice"), "anchor": (["anchor"], "blue"), "badge": (["rosette", "award"], "gold"),
    "ballot": (["checklist"], "white"), "bars": (["chart-bar"], "teal"), "bell": (["bell"], "gold"),
    "bolt": (["bolt"], "gold"), "box": (["box"], "brown"), "brief": (["briefcase"], "brown"),
    "broom": (["brush"], "orange"), "bubble": (["message-circle"], "white"), "car": (["car"], "red"),
    "check": (["check"], "green"), "chevdown": (["chevron-down"], "white"), "clipboard": (["clipboard"], "white"),
    "clock": (["clock"], "white"), "coin": (["coin"], "gold"), "copy": (["copy"], "white"),
    "cross": (["x"], "red"), "crown": (["crown"], "gold"), "cuffs": (["link"], "grey"),
    "door": (["door"], "brown"), "drop": (["droplet"], "blue"), "envelope": (["mail"], "white"),
    "eraser": (["eraser"], "pink"), "eye": (["eye"], "white"), "feather": (["feather"], "white"),
    "flag": (["flag"], "red"), "flame": (["flame"], "orange"), "gear": (["settings"], "grey"),
    "gem": (["diamond"], "ice"), "ghost": (["ghost"], "white"), "gun": (["pistol", "target-arrow", "crosshair"], "grey"),
    "halo": (["sparkles"], "gold"), "hammer": (["hammer"], "brown"), "hand": (["hand-stop"], "bone"),
    "headset": (["headset"], "violet"), "heart": (["heart"], "red"), "helm": (["helmet"], "grey"),
    "image": (["photo"], "teal"), "info": (["info-circle"], "blue"), "jail": (["building-fortress", "fence", "wall"], "grey"),
    "jump": (["arrow-big-up"], "green"), "key": (["key"], "gold"), "laurel": (["laurel-wreath"], "green"),
    "leaf": (["leaf"], "green"), "license": (["license"], "white"), "lock": (["lock"], "gold"),
    "magnet": (["magnet"], "red"), "map": (["map"], "teal"), "megaphone": (["speakerphone"], "orange"),
    "mic": (["microphone"], "white"), "music": (["music"], "violet"), "npc": (["robot"], "teal"),
    "paw": (["paw"], "brown"), "pen": (["pencil"], "gold"), "pin": (["pin"], "red"),
    "play": (["player-play"], "green"), "players": (["users"], "white"), "portal": (["spiral"], "violet"),
    "reload": (["refresh"], "white"), "reply": (["arrow-back-up"], "white"), "rocket": (["rocket"], "orange"),
    "scale": (["scale"], "gold"), "scroll": (["script"], "bone"), "send": (["send"], "white"),
    "shield": (["shield"], "blue"), "skull": (["skull"], "bone"), "snow": (["snowflake"], "ice"),
    "speed": (["gauge"], "orange"), "star": (["star"], "gold"), "stop": (["player-stop"], "red"),
    "sword": (["sword"], "grey"), "tag": (["tag"], "pink"), "target": (["target"], "red"),
    "terminal": (["terminal-2"], "green"), "title": (["typography"], "white"), "trash": (["trash"], "red"),
    "undo": (["arrow-back"], "white"), "user": (["user"], "white"), "vest": (["shirt"], "blue"),
    "warn": (["alert-triangle"], "gold"), "wrench": (["tool"], "grey"),
}
# 1.7.0: ícones de DarkRP (porte, polícia, procurado, prefeitura...)
DARKRP = {
    "permit": (["certificate", "license"], "gold"), "police": (["shield-star", "shield"], "blue"),
    "wanted": (["user-exclamation", "flag"], "red"), "moneybag": (["moneybag", "coin"], "gold"),
    "ticket": (["ticket"], "pink"), "siren": (["urgent", "alarm"], "red"),
    "broadcast": (["broadcast", "antenna"], "orange"), "gavel": (["gavel", "hammer"], "brown"),
    "notebook": (["notebook", "notes"], "bone"), "receipt": (["receipt", "file-dollar"], "green"),
    "crosshair": (["crosshair", "target"], "red"), "lockdown": (["home-lock", "lock"], "red"),
    # relatório semanal no Discord
    "calendar": (["calendar-stats", "calendar"], "violet"),
}
BASE.update(DARKRP)

# selos: sufixo -> (cor do selo, ícone branco dentro)
SELO = {"ok": ("green", "check"), "no": ("red", "x"), "plus": ("green", "plus"), "minus": ("red", "minus"),
        "id": ("blue", "hash"), "snow": ("ice", "snowflake")}

def svg_of(cands, fill_first=True):
    for n in cands:
        for kind in (("filled", "outline") if fill_first else ("outline",)):
            p = os.path.join(TABLER, kind, n + ".svg")
            if os.path.exists(p):
                return open(p, encoding="utf-8").read(), kind, n
    raise SystemExit("sem ícone: %s" % cands)

def colored(svg, kind, hexcol, stroke=2.3):
    svg = svg.replace("currentColor", hexcol)
    if kind == "outline":
        svg = svg.replace('stroke-width="2"', 'stroke-width="%s"' % stroke)
    svg = svg.replace('width="24"', 'width="%d"' % BIG).replace('height="24"', 'height="%d"' % BIG)
    return svg

jobs = []
def job(key, svg):
    path = os.path.join(TMP, key + ".svg")
    open(path, "w", encoding="utf-8").write(svg)
    jobs.append(path)
    return os.path.join(TMP, key + ".png")

files = sorted(f[:-4] for f in os.listdir(SAIDA) if f.endswith(".png"))
files = sorted(set(files) | set(DARKRP))
plan = {}
for name in files:
    base, _, suf = name.partition("_")
    if base not in BASE:
        print("sem regra:", name); continue
    cands, col = BASE[base]
    svg, kind, chosen = svg_of(cands)
    main = job("m_" + base, colored(svg, kind, COR[col]))
    badge = None
    if suf:
        if suf not in SELO: print("selo?", name); continue
        bcol, glyph = SELO[suf]
        gsvg, gk, _ = svg_of([glyph], fill_first=False)
        badge = (COR[bcol], job("g_" + glyph, colored(gsvg, gk, "#ffffff", 3.2)))
    plan[name] = (main, badge, chosen)

# render all svgs with resvg (node)
js = """
const { Resvg } = require('@resvg/resvg-js'); const fs = require('fs');
for (const p of JSON.parse(fs.readFileSync(0,'utf8'))) {
  const r = new Resvg(fs.readFileSync(p,'utf8'), { fitTo: { mode: 'width', value: %d } });
  fs.writeFileSync(p.replace(/\\.svg$/, '.png'), r.render().asPng());
}
""" % BIG
subprocess.run(["node", "-e", js], input=json.dumps(sorted(set(jobs))).encode(), cwd=KIT, check=True)

def hexrgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def sticker(img, out_w, shadow):
    """img: RGBA (cor) -> com contorno INK de out_w px e sombra dura deslocada."""
    a = img.getchannel("A")
    a = a.point(lambda v: 255 if v > 40 else 0)
    ring = a
    for _ in range(out_w // 2):
        ring = ring.filter(ImageFilter.MaxFilter(5))
    W, H = img.size
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", (W, H), (0, 0, 0, 150)), (shadow, shadow), ring)
    canvas = Image.alpha_composite(canvas, sh)
    ink = Image.new("RGBA", (W, H), INK)
    canvas.paste(ink, (0, 0), ring)
    canvas = Image.alpha_composite(canvas, img)
    return canvas

def build(name):
    main, badge, chosen = plan[name]
    src = Image.open(main).convert("RGBA")
    # encaixa o desenho em 76% do quadro (sobra espaço para contorno e sombra), centrado e quadrado
    bbox = src.getbbox() or (0, 0, BIG, BIG)
    crop = src.crop(bbox)
    cw, ch = crop.size
    k = (BIG * 0.74) / max(cw, ch)
    crop = crop.resize((max(1, round(cw * k)), max(1, round(ch * k))), Image.LANCZOS)
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ox, oy = (BIG - crop.size[0]) // 2 - 4, (BIG - crop.size[1]) // 2 - 4
    if badge: ox, oy = ox - 8, oy - 8
    img.paste(crop, (ox, oy), crop)
    out = sticker(img, 22, 12)
    if badge:
        bcol, glyph = badge
        R = 50; cx, cy = BIG - R - 14, BIG - R - 14
        b = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        from PIL import ImageDraw
        d = ImageDraw.Draw(b)
        d.ellipse((cx - R - 12, cy - R - 12, cx + R + 12, cy + R + 12), fill=INK)
        d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=hexrgb(bcol) + (255,))
        g = Image.open(glyph).convert("RGBA").resize((int(R * 1.3), int(R * 1.3)), Image.LANCZOS)
        b.paste(g, (cx - g.size[0] // 2, cy - g.size[1] // 2), g)
        out = Image.alpha_composite(out, b)
    return out.resize((64, 64), Image.LANCZOS)

prev = Image.new("RGBA", (12 * 72, ((len(plan) + 11) // 12) * 72), (34, 28, 52, 255))
for i, name in enumerate(sorted(plan)):
    ic = build(name)
    ic.save(os.path.join(SAIDA, name + ".png"))
    prev.alpha_composite(ic, ((i % 12) * 72 + 4, (i // 12) * 72 + 4))
prev.save(os.path.join(AQUI, "icones_v3_preview.png"))
print("ok", len(plan))
