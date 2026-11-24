# Praetor: baixa os sons escolhidos (todos CC0, achados por buscar.py), corta,
# normaliza e grava OGG Vorbis mono 44.1 kHz em praetor/sound/praetor/.
# Também escreve _fontes/CREDITOS_SONS.md.
# Uso: python baixar.py            (todos)
#      python baixar.py gavel seal (só esses)
import io, json, os, sys, urllib.request
from math import gcd

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

AQUI = os.path.dirname(os.path.abspath(__file__))
BRUTOS = os.path.join(AQUI, "brutos")
RAIZ = os.path.dirname(os.path.dirname(AQUI))
SAIDA = os.path.join(RAIZ, "praetor", "sound", "praetor")
CREDITOS = os.path.join(RAIZ, "_fontes", "CREDITOS_SONS.md")
SR = 44100

# arquivo: (categoria, título exato no Openverse, início s, duração máx s, pico, fade-out s)
ESCOLHA = {
    "click":  ("click",  "Button Clicking 2 (Single)",   0.0, 0.16, 0.55, 0.05),
    "open":   ("open",   "Soft Cover Book Open 1.wav",   0.0, 0.9,  0.6,  0.3),
    "close":  ("close",  "bkClose.wav",                  0.0, 0.6,  0.6,  0.2),
    "tab":    ("tab",    "Page Turn 02.wav",             0.0, 0.55, 0.5,  0.2),
    "notify": ("notify", "bell ding 1.wav",              0.0, 1.4,  0.45, 0.8),
    "report": ("report", "Paper Rustle",                 0.0, 0.9,  0.6,  0.3),
    "gavel":  ("gavel",  "Gavel on wooden desk",         0.0, 0.7,  0.8,  0.25),
    "warn":   ("warn",   "Percussive Alert 1_2",         0.0, 0.7,  0.5,  0.25),
    "error":  ("error",  "SeriousError01d.aif",          0.0, 0.35, 0.4,  0.1),
    "seal":   ("seal",   "Office stamp",                 0.0, 0.5,  0.75, 0.15),
    "chat":   ("chat",   "Pop 2",                        0.0, 0.15, 0.35, 0.04),
}


def baixar(url, destino):
    if os.path.exists(destino) and os.path.getsize(destino) > 0:
        return
    req = urllib.request.Request(url, headers={"User-Agent": "sound-fetch-script/1.0"})
    with urllib.request.urlopen(req, timeout=90) as r:
        dados = r.read()
    with open(destino, "wb") as f:
        f.write(dados)


def ler(caminho):
    try:
        x, sr = sf.read(caminho, always_2d=True, dtype="float64")
    except Exception:
        # mp3 e formatos que o libsndfile não abre: ffmpeg do imageio
        import subprocess, imageio_ffmpeg
        tmp = caminho + ".conv.wav"
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", caminho, tmp], check=True)
        x, sr = sf.read(tmp, always_2d=True, dtype="float64")
    x = x.mean(axis=1)
    if sr != SR:
        g = gcd(int(sr), SR)
        x = resample_poly(x, SR // g, int(sr) // g)
    return x


def ataque(x, limiar=0.05):
    a = np.abs(x)
    idx = np.where(a > (a.max() or 1) * limiar)[0]
    return max(0, idx[0] - int(SR * 0.004)) if len(idx) else 0


def main(so):
    res = json.load(open(os.path.join(AQUI, "resultados.json"), encoding="utf-8"))
    os.makedirs(BRUTOS, exist_ok=True)
    os.makedirs(SAIDA, exist_ok=True)
    linhas = []
    for nome, (cat, titulo, ini, dur, pico, fade) in ESCOLHA.items():
        cand = [c for c in res.get(cat, []) if c["titulo"] == titulo]
        if not cand:
            print("não achei", nome, titulo)
            continue
        c = cand[0]
        if (c.get("licenca") or "").lower() != "cc0":
            print("licença errada", nome, c.get("licenca"))
            continue
        linhas.append("| %s.ogg | %s | %s | CC0 | %s |" % (
            nome, titulo.replace("|", "/"), c.get("autor") or "?", c.get("pagina") or c["url"]))
        if so and nome not in so:
            continue
        ext = os.path.splitext(c["url"].split("?")[0])[1] or ".mp3"
        bruto = os.path.join(BRUTOS, nome + ext)
        try:
            baixar(c["url"], bruto)
            x = ler(bruto)
        except Exception as e:
            print("falhou", nome, e)
            continue
        x = x[int(ini * SR):]
        x = x[ataque(x):]
        x = x[:int(dur * SR)].copy()
        nf = min(len(x), int(fade * SR))
        if nf > 0:
            x[-nf:] *= np.linspace(1, 0, nf) ** 2
        ni = min(len(x), int(0.003 * SR))
        x[:ni] *= np.linspace(0, 1, ni)
        x = x - x.mean()
        x = x / (np.abs(x).max() or 1) * pico
        sf.write(os.path.join(SAIDA, nome + ".ogg"), x.astype("float32"), SR, format="OGG", subtype="VORBIS")
        print("ok %-8s %5.2fs  %s" % (nome, len(x) / SR, titulo))

    with io.open(CREDITOS, "w", encoding="utf-8") as f:
        f.write("# Créditos dos sons / Sound credits\n\n")
        f.write("Todos os sons vêm do Openverse (openverse.org) e são de domínio público (CC0). "
                "Foram cortados, normalizados e convertidos para OGG mono.\n")
        f.write("All sounds come from Openverse (openverse.org) and are public domain (CC0). "
                "They were trimmed, normalized and converted to mono OGG.\n\n")
        f.write("| Arquivo | Título original | Autor | Licença | Link |\n|---|---|---|---|---|\n")
        f.write("\n".join(linhas) + "\n")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
