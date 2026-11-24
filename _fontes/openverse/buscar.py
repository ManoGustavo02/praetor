# Praetor: procura sons CC0 no Openverse e guarda os candidatos em resultados.json.
# Uso: python buscar.py            (todas as categorias)
#      python buscar.py gavel seal (só essas)
import json, os, sys, time, urllib.parse, urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = os.path.join(AQUI, "resultados.json")

BUSCAS = {
    "click":  ["button click", "ui click", "switch click", "mouse click"],
    "open":   ["book open", "scroll unroll", "leather book open", "drawer open"],
    "close":  ["book close", "book slam soft", "drawer close", "leather close"],
    "tab":    ["page flip", "page turn", "paper flip"],
    "notify": ["small bell", "bell ding", "desk bell", "chime single"],
    "report": ["paper rustle", "letter envelope", "paper slide", "envelope"],
    "gavel":  ["gavel", "judge gavel", "wood knock", "wooden hammer hit"],
    "warn":   ["warning horn", "alert low", "brass horn short", "gong small"],
    "error":  ["error buzz", "denied", "wrong buzzer", "wood thud"],
    "seal":   ["stamp", "rubber stamp", "wax seal", "stamp paper"],
    "chat":   ["pop", "soft pop", "bubble pop", "tick"],
}


def buscar(q, n=15):
    url = "https://api.openverse.org/v1/audio/?" + urllib.parse.urlencode(
        {"q": q, "license": "cc0", "page_size": n})
    req = urllib.request.Request(url, headers={"User-Agent": "sound-search-script/1.0"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r).get("results", [])


def main(nomes):
    dados = json.load(open(SAIDA, encoding="utf-8")) if os.path.exists(SAIDA) else {}
    for nome in nomes:
        vistos, lista = set(), []
        for q in BUSCAS[nome]:
            try:
                res = buscar(q)
            except Exception as e:
                print("falhou", nome, q, e)
                continue
            for r in res:
                if r["id"] in vistos:
                    continue
                vistos.add(r["id"])
                lista.append({
                    "id": r["id"], "titulo": r["title"], "dur": r.get("duration"),
                    "url": r["url"], "autor": r.get("creator"), "licenca": r.get("license"),
                    "pagina": r.get("foreign_landing_url"),
                    "tags": [t["name"] for t in (r.get("tags") or [])][:6],
                })
            time.sleep(0.7)
        dados[nome] = lista
        json.dump(dados, open(SAIDA, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        print("==", nome, len(lista))
        for i, c in enumerate(lista[:30]):
            d = c["dur"] and "%.1fs" % (c["dur"] / 1000) or "?"
            print("  %2d %-46s %7s %s" % (i, c["titulo"][:46], d, ",".join(c["tags"])[:50]))


if __name__ == "__main__":
    main(sys.argv[1:] or list(BUSCAS))
