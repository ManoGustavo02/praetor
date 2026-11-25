# Praetor 1.5.0: sons de interface com cara de cartoon (pop, bolha, swish, boing),
# todos CC0 do Openverse (achados com a busca que gerou resultados_v2.json).
# Corta, normaliza e grava OGG mono em praetor/sound/praetor/ e atualiza CREDITOS_SONS.md.
import io, json, os, re
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
import baixar as B   # reaproveita baixar() / ler() / ataque()

AQUI = os.path.dirname(os.path.abspath(__file__))
SR = B.SR

# arquivo: (categoria, título exato, início s, duração máx s, pico, fade-out s, velocidade)
#   velocidade < 1 deixa mais grave e lento (o "close" é o mesmo swish do "open", mais grave)
ESCOLHA = {
    "click":  ("pop",         "Pop 1.ogg",                   0.0, 0.16, 0.50, 0.05, 1.0),
    "hover":  ("hover",       "hover over a button.wav",     0.0, 0.09, 0.22, 0.03, 1.0),
    "open":   ("whoosh_up",   "Quick Swish",                 0.0, 0.30, 0.45, 0.12, 1.08),
    "close":  ("whoosh_up",   "Quick Swish",                 0.0, 0.32, 0.38, 0.14, 0.82),
    "tab":    ("pop",         "Mouth Pop 2",                 0.0, 0.22, 0.45, 0.06, 1.0),
    "toggle": ("toggle",      "Toggle Switch",               0.0, 0.20, 0.45, 0.06, 1.0),
    "notify": ("chime",       "Chime Notification",          0.0, 0.70, 0.42, 0.30, 1.0),
    "ok":     ("success",     "Fantasy_ui_Button_2.wav",     0.0, 0.85, 0.40, 0.40, 1.0),
    "error":  ("bonk",        "Boing.flac",                  0.0, 0.40, 0.42, 0.12, 1.0),
    "chat":   ("pop",         "Pop 02.wav",                  0.0, 0.10, 0.30, 0.03, 1.0),
}


def speed(x, f):
    if abs(f - 1) < 1e-3:
        return x
    up, down = 100, int(round(100 * f))
    return resample_poly(x, up, down)


def main():
    res = json.load(open(os.path.join(AQUI, "resultados_v2.json"), encoding="utf-8"))
    os.makedirs(B.BRUTOS, exist_ok=True)
    linhas = []
    for nome, (cat, titulo, ini, dur, pico, fade, vel) in ESCOLHA.items():
        cand = [c for c in res.get(cat, []) if c["t"] == titulo]
        if not cand:
            print("não achei", nome, titulo); continue
        c = cand[0]
        if (c.get("lic") or "").lower() != "cc0":
            print("licença errada", nome, c.get("lic")); continue
        ext = os.path.splitext(c["u"].split("?")[0])[1] or ".mp3"
        bruto = os.path.join(B.BRUTOS, "v2_" + re.sub(r"\W+", "_", titulo) + ext)
        B.baixar(c["u"], bruto)
        x = B.ler(bruto)
        x = x[int(ini * SR):]
        x = x[B.ataque(x):]
        x = speed(x, vel)
        x = x[:int(dur * SR)].copy()
        nf = min(len(x), int(fade * SR))
        if nf > 0: x[-nf:] *= np.linspace(1, 0, nf) ** 2
        ni = min(len(x), int(0.003 * SR))
        x[:ni] *= np.linspace(0, 1, ni)
        x = x - x.mean()
        x = x / (np.abs(x).max() or 1) * pico
        sf.write(os.path.join(B.SAIDA, nome + ".ogg"), x.astype("float32"), SR, format="OGG", subtype="VORBIS")
        print("ok %-7s %5.2fs  %s (%s)" % (nome, len(x) / SR, titulo, c.get("by")))
        linhas.append("| %s.ogg | %s | %s | CC0 | %s |" % (nome, titulo.replace("|", "/"), c.get("by") or "?", c.get("land") or c["u"]))

    # mantém as linhas dos sons antigos que continuam (report, gavel, warn, seal)
    velho = io.open(B.CREDITOS, encoding="utf-8").read() if os.path.exists(B.CREDITOS) else ""
    novos = set(ESCOLHA)
    for l in velho.splitlines():
        m = re.match(r"\| (\w+)\.ogg \|", l)
        if m and m.group(1) not in novos and os.path.exists(os.path.join(B.SAIDA, m.group(1) + ".ogg")):
            linhas.append(l)
    with io.open(B.CREDITOS, "w", encoding="utf-8") as f:
        f.write("# Créditos dos sons / Sound credits\n\n")
        f.write("Todos os sons vêm do Openverse (openverse.org) e são de domínio público (CC0). "
                "Foram cortados, normalizados e convertidos para OGG mono.\n")
        f.write("All sounds come from Openverse (openverse.org) and are public domain (CC0). "
                "They were trimmed, normalized and converted to mono OGG.\n\n")
        f.write("| Arquivo | Título original | Autor | Licença | Link |\n|---|---|---|---|---|\n")
        f.write("\n".join(sorted(linhas)) + "\n")


if __name__ == "__main__":
    main()
