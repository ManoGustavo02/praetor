# Praetor: desenha os ícones em pixel art (16x16, cada letra é um pixel) e grava
# em praetor/materials/praetor/icons/<nome>.png ampliados 4x sem suavizar.
# Também grava materials/praetor/noise.png (granulado 128x128) e _fontes/icones_preview.png.
import os, random
from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
SAIDA = os.path.join(RAIZ, "praetor", "materials", "praetor", "icons")
ESCALA = 4

PAL = {
    "k": (28, 20, 24), "g": (226, 178, 96), "G": (160, 108, 48), "y": (255, 236, 176),
    "s": (196, 200, 210), "S": (116, 120, 136), "w": (244, 234, 214),
    "r": (196, 62, 50), "R": (118, 32, 34), "b": (78, 134, 206), "B": (38, 74, 132),
    "n": (138, 88, 50), "N": (88, 54, 30), "t": (214, 164, 112),
    "e": (112, 172, 78), "E": (58, 108, 48), "o": (240, 140, 48), "c": (120, 222, 230),
    "p": (168, 112, 232), "P": (98, 60, 160), "d": (52, 56, 68),
}

ICONES = {
"crown": """
k.....k.....k
kk...kyk...kk
kyk..kgk..kyk
kgk.kgggk.kgk
kggkgggggkggk
kgggggggggggk
kgrgggbgggrgk
kgggggggggggk
kGGGGGGGGGGGk
kyyyyyyyyyyyk
kkkkkkkkkkkkk
""",
"shield": """
kkkkkkkkkkkkk
kssssskbbbbbk
kswwsskbbbbBk
kswssskbbbbBk
kssssskbbbbBk
kgggggggggggk
kbbbbbkssssSk
kbbbbbkssssSk
.kbbbbkssssk.
.kbbbbksssSk.
..kbbbkssSk..
...kbbkSSk...
....kbkSk....
.....kkk.....
""",
"sword": """
............kkkk
...........kwwsk
..........kwwsk.
.........kwwsk..
........kwwsk...
.......kwwsk....
..kk..kwwsk.....
..kgkkwwsk......
...kgwwsk.......
....kgsk........
...kNkgk........
..kNk.kgk.......
.kNk...kk.......
kgk.............
kk..............
""",
"star": """
.......k.......
......kyk......
......kgk......
.....kgggk.....
kkkkkkgggkkkkkk
kygggggggggggGk
.kggggggggggGk.
..kggggggggGk..
...kgggggggk...
...kggggGGGk...
..kgggkkkGGGk..
..kggk...kGGk..
.kggk.....kGGk.
.kkk.......kkk.
""",
"gem": """
...kkkkkkk...
..kwwcccbbk..
.kwwccccbbBk.
kkkkkkkkkkkkk
kwccccccbbbBk
.kwcccccbbBk.
..kwccccbBk..
...kwcccBk...
....kwcBk....
.....kBk.....
......k......
""",
"laurel": """
..kg.......gk..
.kgGk.....kGgk.
.kgk.......kgk.
kgk.........kgk
kgGk.......kGgk
kgk.........kgk
kGgk.......kgGk
.kgk.......kgk.
.kgGk.....kGgk.
..kgk.....kgk..
...kgkk.kkgk...
....kkrkrkk....
.....krkrk.....
......k.k......
""",
"hammer": """
.kkkkkkkkkkkk.
kGgkynnnnnkgGk
kGgknnnnnnkgGk
kGgkNNNNNNkgGk
.kkkkkkkkkkkk.
.....knNk.....
.....knNk.....
.....knNk.....
.....knNk.....
.....knNk.....
..kkkkkkkkkk..
.knnnnnnnnnNk.
.kNNNNNNNNNNk.
..kkkkkkkkkk..
""",
"wrench": """
..........kk.kk.
.........kwk.kwk
.........kwskssk
..........kssssk
.........ksssSk.
........ksssk...
.......ksssk....
......ksssk.....
.....ksssk......
....ksssk.......
...ksssk........
..kwssk.........
.kwsSk..........
.ksSk...........
..kk............
""",
"eye": """
....kkkkkkk....
..kkwwwwwwwkk..
.kwwwwbbbwwwwk.
kwwwwbBkBbwwwwk
kwwwwbkkkbwwwwk
kwwwwbwkBbwwwwk
.kwwwwbbbwwwwk.
..kkwwwwwwwkk..
....kkkkkkk....
""",
"bolt": """
......kkkkk
.....kyyyk.
....kyggk..
...kyggk...
..kyggkkkk.
.kyggggggk.
kkkkkgggk..
....kggk...
...kgGk....
..kgGk.....
.kGGk......
.kGk.......
kk.........
""",
"skull": """
...kkkkkkk...
..kwwwwwwwk..
.kwwwwwwwwwk.
kwwwwwwwwwwwk
kwkkkwwwkkkwk
kwkkkwwwkkkwk
kwwwwwkwwwwSk
.kwwwkwkwwwk.
..kwwwwwwwk..
..kwkwkwkwk..
..kkkkkkkkk..
""",
"flag": """
kk............
kskkkkkkkkkk..
kskrrrrrrrrrk.
kskrryrrrrrrrk
kskrrrrrrrrrk.
kskRrrrrrrrk..
kskRRrrrrrrrk.
kskkkkkkkkkkk.
ksk...........
ksk...........
ksk...........
ksk...........
kNNk..........
kkkk..........
""",
"key": """
..kkkk..........
.kyyggk.........
kygkkGgk........
kgk..kGkkkkkkkk.
kgk..kGggggggggk
kGgkkgGkkkkGkGk.
.kGGGGk...kGkGk.
..kkkk....kkkkk.
""",
"coin": """
..kkkkkkkkk..
.kyyyyyyyyyk.
.kgggggggGGk.
.kGGGGGGGGGk.
kkkkkkkkkkkk.
kyyyyyyyyyyk.
kggggggggGGk.
kGGGGGGGGGGk.
.kkkkkkkkkkkk
.kyyyyyyyyyyk
.kgggggggggGk
.kGGGGGGGGGGk
.kkkkkkkkkkkk
""",
"scroll": """
.kkkkkkkkkkk..
kNnkwwwwwwwwk.
kNnkwSSSSSwwk.
.kkwwwwwwwwwk.
..kwSSSSSSwwk.
..kwwwwwwwwwk.
..kwSSSSSwwwk.
..kwwwwwwwwwk.
..kwSSSSSSwwk.
..kwwwwwwwwkk.
..kkkkkkkkkNnk
..kkkkkkkkkkk.
""",
"flame": """
.....k.....
....krk....
...krrk....
...krork...
..krrook.k.
.krroyokrk.
.kroyyyork.
krooyyyoork
kroyywyyork
kroyywwyork
.kroyyyork.
..krrooork.
..kkkkkkk..
""",
"leaf": """
........kkkk.
......kkeeyk.
....kkeeeeek.
...keeeeEeek.
..keeeeEeeek.
..keeeEeeeEk.
.keeeEeeeEk..
.keeEeeeEEk..
.keEeeEEEk...
.kEeEEEkk....
.kNkkk.......
kNk..........
kk...........
""",
"heart": """
..kkk...kkk..
.kwrrk.krrrk.
kwrrrrkrrrrRk
krrrrrrrrrrRk
krrrrrrrrrrRk
.krrrrrrrrRk.
..krrrrrrRk..
...krrrrRk...
....krrRk....
.....kRk.....
......k......
""",
"music": """
....kkkkkkkk
....kggggggk
....kgkkkkgk
....kgk..kgk
....kgk..kgk
....kgk..kgk
..kkkgkkkkgk
.kyggGkyggGk
.kgGGGkgGGGk
..kkkk.kkkk.
""",
"gear": """
.....kkk.....
..kk.ksk.kk..
.ksskssskssk.
..kssssssSk..
kkssskkkssSkk
ksssk...kssSk
ksssk...kssSk
kkssskkkssSkk
..ksssssSSk..
.ksskSSkSSk..
..kk.kSk.kk..
.....kkk.....
""",
"helm": """
...krrrrrk...
..krrrrrrRk..
..kkkkkkkkk..
.kssssssssSk.
kssssssssssSk
ksskkkkkkkSSk
ksssskkkssSSk
ksssskkkssSSk
.kssskkksSSk.
..kssk.kSSk..
...kk...kk...
""",
"badge": """
..kkk...kkk..
..kbbk.krrk..
...kbbkrrk...
....kbkrk....
....kkkkk....
...kyyggGk...
..kyggyggGk..
..kgyyyyyGk..
..kggyyygGk..
..kgygGygGk..
...kgggGGk...
....kkkkk....
""",
"anchor": """
.....kkk.....
....ks.sk....
.....kkk.....
...kkkskkk...
...kssssSk...
...kkkskkk...
.....ksk.....
.....ksk.....
.....ksk.....
kk...ksk...kk
ksk..ksk..ksk
.ksk.ksk.ksk.
..ksssssSSk..
...kkkkkkk...
""",
"paw": """
...kk...kk...
..kttk.kttk..
..kttk.kttk..
kk.kk...kk.kk
kttk.....kttk
kttk.kkk.kttk
.kk.ktttk.kk.
...ktttttk...
..kttttttnk..
..kttttttnk..
..kntttttnnk.
...kkk.kkk...
""",
"players": """
.........kkk...
...kkk..kwwwk..
..kwwwk.kwwwk..
..kwwwk.kwwSk..
..kwwSk..kkk...
...kkk..kbbbbk.
..kkkkkkbbbbBk.
.kgggggGkbbbBk.
kgggggggGkbbBk.
kgggggggGkbbBk.
kgggggggGkkkkk.
kkkkkkkkkk.....
""",
"mic": """
....kkkk....
...kwssSk...
...ksssSk...
...kwssSk...
...ksssSk...
...kwssSk...
.k.kssSSk.k.
.k..kSSk..k.
.kk..kk..kk.
..kk....kk..
...kkkkkk...
.....kk.....
...kkkkkk...
""",
"send": """
kk..........
kbkk........
kbbbkk......
kbbbbbkk....
kbbbbbbbkk..
kwwwwwwwwwk.
kbbbbbbbkk..
kbbbbbkk....
kbbbkk......
kbkk........
kk..........
""",
"reply": """
....k.......
...kk.......
..kbkkkkkk..
.kbbbbbbbbk.
kbbbbbbbbbbk
.kbbbbbbbbbk
..kbkkkkkbbk
...kk....kbk
....k....kbk
.........kbk
.........kk.
""",
"copy": """
kkkkkkkk....
kwwwwwwk....
kwkkkkkkkkk.
kwkwwwwwwwk.
kwkwSSSSwwk.
kwkwwwwwwwk.
kwkwSSSSSwk.
kkkwwwwwwwk.
..kwSSSwwwk.
..kwwwwwwwk.
..kkkkkkkkk.
""",
"trash": """
....kkkk....
kkkkkkkkkkkk
kssssssssssk
kkkkkkkkkkkk
.kssSsSsSsk.
.kssSsSsSsk.
.kssSsSsSsk.
.kssSsSsSsk.
.kssSsSsSsk.
.kssSsSsSsk.
..kkkkkkkk..
""",
"afk": """
....kkkkk.......
..kkyyyyk.wwww..
.kyyyyyk....w...
kyyyyyk....w....
kyyyyk....wwww..
kyyyyk..........
kyyyyk..........
kyyyyyk.........
.kyyyyyyk.......
..kkyyyyyykk....
....kkkkkk......
""",
# ---- 1.2.0: one icon per command
"door": """
kkkkkkkk........
kNnnnnnk........
kNnkknnk........
kNnkknnk........
kNnnnnnk....k...
kNnnnnnk....kk..
kNnnnyykkkkkkek.
kNnnnnnkkeeeeeek
kNnkknnkkkkkkek.
kNnkknnk....kk..
kNnnnnnk....k...
kkkkkkkk........
""",
"warn": """
.......kk.......
......kyyk......
......kggk......
.....kgkkgk.....
.....kgkkgk.....
....kggkkggk....
....kggkkggk....
...kgggkkgggk...
...kggggggggk...
..kggggkkggggk..
..kGGGGkkGGGGk..
.kGGGGGGGGGGGGk.
.kkkkkkkkkkkkkk.
""",
"bubble": """
..kkkkkkkkkkk...
.kwwwwwwwwwwwk..
kwwwwwwwwwwwwwk.
kwwSSwwSSwwSSwk.
kwwSSwwSSwwSSwk.
kwwwwwwwwwwwwSk.
.kwwwwwwwwwwSk..
..kkkwwkkkkkk...
....kwk.........
....kk..........
""",
"jail": """
kkkkkkkkkkkkkkk
ksssssssssssssk
kkkkkkkkkkkkkkk
ksk.ksk.ksk.ksk
ksk.ksk.ksk.ksk
ksk.ksk.ksk.ksk
ksk.ksk.ksk.ksk
ksk.ksk.ksk.ksk
ksk.ksk.ksk.ksk
kkkkkkkkkkkkkkk
ksssssssssssssk
kkkkkkkkkkkkkkk
""",
"snow": """
.....kkk.....
..k..kck..k..
.kck.kck.kck.
..kckkckkck..
...kccwcck...
kkkkcwwwckkkk
kcccwwwwwccck
kkkkcwwwckkkk
...kccwcck...
..kckkckkck..
.kck.kck.kck.
..k..kck..k..
.....kkk.....
""",
"broom": """
............kk
...........knk
..........knk.
.........knk..
........knk...
.......knk....
....kkkrrk....
...kyyyyyk....
..kygygygk....
.kygygygGk....
kygygygGGk....
kgygyGGGk.....
kkkkkkkk......
""",
"box": """
kkkkkkkkkkkkk
kttttttttttnk
ktkkkkkkkkknk
ktktnnnnnNknk
ktknttnnnNknk
ktknnttnnNknk
ktknnnttnNknk
ktknnnnttNknk
ktknnnnnttknk
ktkNNNNNNtknk
ktkkkkkkkkknk
knnnnnnnnnnNk
kkkkkkkkkkkkk
""",
"lock": """
...kkkkk...
..kSsssSk..
.kSk...kSk.
.ksk...ksk.
.ksk...ksk.
kkkkkkkkkkk
kgggggggggk
kgyggkgggGk
kgggkykggGk
kggggkgggGk
kgggkykggGk
kGGGGGGGGGk
kkkkkkkkkkk
""",
"car": """
....kkkkkkk.....
...kbbbbbbbk....
..kbccbcccbbk...
.kbbccbcccbbbkk.
kbbbbbbbbbbbbbbk
kbwbbbbbbbbbbrbk
kbbbbbbbbbbbbbbk
kBBkkkBBBBkkkBBk
.kkdddkkkkdddkk.
...kdk....kdk...
....k......k....
""",
"npc": """
....kkkkk....
...kssssSk...
..ksccsccSk..
..ksccsccSk..
..ksssssssk..
...kSdddSk...
....kkkkk....
..kkSsssSkk..
.kssSsssSssk.
.kssSsssSssk.
.kSkSsssSkSk.
.kk.kSkSk.kk.
....kk.kk....
""",
"pin": """
...kkkkk...
.kkrrrrrkk.
.krwrrrrRk.
krrrkkkrrRk
krrkwwwkrRk
krrkwwwkrRk
krrrkkkrrRk
.krrrrrrRk.
.krrrrrRRk.
..krrrRRk..
...krRRk...
....kRk....
.....k.....
""",
"magnet": """
...kkkkkkk...
.kkrrrrrrrkk.
krrrrkkkrrrRk
krrRk...krrRk
krrRk...krrRk
krrRk...krrRk
kkkkk...kkkkk
kwssk...kwssk
kssSk...kssSk
kkkkk...kkkkk
""",
"undo": """
...k..........
..kbkkkkkk....
.kbbbbbbbbkk..
kbbbbbbbbbbbk.
.kbbkkkkkkbbbk
..kbk.....kbbk
...k.......kbk
...........kbk
..........kbbk
......kkkkbbk.
.....kbbbbbk..
.....kkkkkk...
""",
"portal": """
....kkkkk....
..kkpppppkk..
.kppPPPPPppk.
.kpPPcccPPpk.
kpPPcwwwcPPpk
kpPcwwwwwcPpk
kpPcwwwwwcPpk
kpPcwwwwwcPpk
kpPPcwwwcPPpk
.kpPPcccPPpk.
.kppPPPPPppk.
..kkpppppkk..
....kkkkk....
""",
"jump": """
...kkkkkk.......
.kkppppppkk.....
kppkkkkkkppk....
kpk......kpk....
kpk......kpk....
kpk....kkkpkkk..
kpk....kpppppk..
kpk.....kpppk...
kpk......kpk....
kkk.......k.....
""",
"vest": """
..kkk...kkk..
.kbbBk.kBbbk.
.kbbbkkkbbbk.
kbbbbkkkbbbbk
kbbbbbkbbbbBk
kbBBBBkBBBBBk
kbbbbbkbbbbBk
kbBBBBkBBBBBk
kbbbbbkbbbbBk
kbbbbbkbbbbBk
kkkkkkkkkkkkk
""",
"halo": """
......y......
..y...y...y..
...y.....y...
...kkkkkkk...
.kkyyyyyyykk.
kyykkkkkkkggk
kgk.......kGk
kGgkkkkkkkgGk
.kkGGGGGGGkk.
...kkkkkkk...
""",
"ghost": """
...kkkkkk...
.kkwwwwwwkk.
kwwwwwwwwwwk
kwwkkwwkkwSk
kwwkkwwkkwSk
kwwwwwwwwwSk
kwwwwkkwwwSk
kwwwwwwwwwSk
kwwwwwwwwSSk
kwwSwwwSwwSk
kwk.kwk.kwSk
.k...k...kk.
""",
"feather": """
...........kkk
.........kkwck
........kwwSck
.......kwwScck
......kwwSccck
.....kwwSccck.
....kwwSccck..
...kwwScccck..
...kwSccck....
..kwScck......
.kSkkk........
kSk...........
kk............
""",
"gun": """
.kkkkkkkkkkkkk.
kwsssssssssssSk
kssssssssssssSk
kSSSSSSSSSSSSSk
.knnnNkkSk.....
.knnnNk.kk.....
.knnnNk........
knnnNk.........
knnnNk.........
kkkkk..........
""",
"user": """
....kkkk....
...kttttk...
..kttttttk..
..kttttttk..
..ktttttnk..
...kttttk...
....kkkk....
..kkbbbbkk..
.kbbbbbbbbk.
kbbbbbbbbbBk
kbbbbbbbbbBk
kbbbbbbbbbBk
kkkkkkkkkkkk
""",
"speed": """
.......kkkk.....
......kbbbbk....
ssss..kbwwbk....
......kbwwbkk...
sssss.kbbbbbbk..
......kbbbbbbbk.
sss..kbbbbbbbbbk
.....kwwwwwwwwwk
.....kkkkkkkkkkk
""",
"scale": """
.......kkkkkk
.......kwwwwk
........kwwwk
.......kwwwwk
......kwwwkwk
.....kwwwk.kk
....kwwwk....
kk.kwwwk.....
kwkwwwk......
kwwwwk.......
kwwwk........
kwwwwk.......
kkkkkk.......
""",
"hand": """
.....k.k.k.k.
....ktktktktk
....ktktktktk
....ktktktktk
.kk.ktttttttk
kttkkttttttnk
.kttttttttnnk
..ktttttttnk.
...kttttttnk.
....kttttnk..
....kkkkkk...
""",
"rocket": """
......kk......
.....kwwk.....
....kwwssk....
....kwsssk....
....kwbbsk....
....kwbbsk....
....kwsssk....
...kkwsssskk..
..krkwsssskrk.
..krkkkkkkkrk.
..kk.kook.kk..
.....kyyk.....
......kk......
""",
"drop": """
.....k.....
....kbk....
....kbk....
...kbbbk...
..kbbbbbk..
.kbwbbbbbk.
kbwbbbbbbBk
kbwbbbbbbBk
kbbbbbbbbBk
.kbbbbbbBk.
..kBBBBBk..
...kkkkk...
""",
"map": """
kkkkkkkkkkkkkkk
keeeekbbbbkeeek
kerrekbbbbkeEek
keerrkbbbbkeeek
keeerkrbbbkeeek
keeeekbrrbkeeek
kEeeekbbbrkrEek
keeEekbbbbkerrk
keeeekbbbbkeeyk
kkkkkkkkkkkkkkk
""",
"reload": """
....kkkkk.k..
..kkwwwwwkwk.
.kwwkkkkkwwk.
kwwk...kwwwk.
kwk...kkkkkk.
kwk..........
kwk.......kwk
kwk.......kwk
kwwk.....kwwk
.kwwkkkkkwwk.
..kkwwwwwkk..
....kkkkk....
""",
"terminal": """
kkkkkkkkkkkkkk
kSSSSSSSSSrygk
kkkkkkkkkkkkkk
kddddddddddddk
kdeddddddddddk
kddedddddddddk
kdeddeeeeddddk
kddddddddddddk
kkkkkkkkkkkkkk
""",
"megaphone": """
..........kk...
........kkrk...
kkkkk.kkrrrk.s.
kwwsskrrrrrk..s
kwwsskrrrrrk...
kwwsskrrrrrk..s
kkkkk.kkrrrk.s.
..kn....kkrk...
..kn......kk...
..kk...........
""",
"envelope": """
kkkkkkkkkkkkkk
kwkwwwwwwwwkwk
kwwkwwwwwwkwwk
kwwwkwwwwkwwwk
kwwwwkkkkwwwwk
kwwwwwwwwwwwSk
kwwwwwwwwwwwSk
kwwwwwwwwwwwSk
kSSSSSSSSSSSSk
kkkkkkkkkkkkkk
""",
"headset": """
...kkkkkkk...
.kksssssssskk
ksk.......ksk
ksk.......ksk
kkkk.....kkkk
kbbk.....kbbk
kbbk.....kbbk
kbbk.....kbbk
kkkk.....kkkk
..ksk........
...kskkk.....
....kkbbk....
......kk.....
""",
"ballot": """
....kkkkkk....
....kwwwwk....
....kwwwek....
....kewewk....
....kwewwk....
kkkkkkkkkkkkkk
kbbbbbbbbbbbBk
kbbbbbbbbbbbBk
kbbbwwwwwwbbBk
kbbbbbbbbbbbBk
kBBBBBBBBBBBBk
kkkkkkkkkkkkkk
""",
"tag": """
....kkkkkkkkkk
...kyyyyyyyyyk
..kggggggggggk
.kggkkgggggggk
kgggkkggggggGk
.kggggggggggGk
..kgggggggggGk
...kGGGGGGGGGk
....kkkkkkkkkk
""",
"title": """
...kkkkkkkkkk...
kk.kyyyyyyyyk.kk
krkkggggggggkkrk
krRkgwwgwwggkRrk
krRkggggggggkRrk
krkkGGGGGGGGkkrk
kRRkkkkkkkkkkRRk
kk............kk
""",
"clock": """
....kkkkk....
..kkwwwwwkk..
.kwwwwkwwwwk.
.kwwwwkwwwwk.
kwwwwwkwwwwSk
kwwwwwkwwwwSk
kwwwwwkkkkwSk
kwwwwwwwwwwSk
kwwwwwwwwwwSk
.kwwwwwwwwSk.
.kSwwwwwwSSk.
..kkSSSSSkk..
....kkkkk....
""",
"clipboard": """
....kkkkk....
.kkkkssskkkk.
knnkkkkkkknnk
knkwwwwwwwknk
knkwrwSSSwknk
knkwwwwwwwknk
knkwrwSSSwknk
knkwwwwwwwknk
knkwrwSSwwknk
knkwwwwwwwknk
knkkkkkkkkknk
kNNNNNNNNNNNk
kkkkkkkkkkkkk
""",
"brief": """
....kkkkk....
....kk.kk....
kkkkkkkkkkkkk
knnnnnnnnnnNk
knnnnnnnnnnNk
kNNNNkykNNNNk
knnnnkkknnnNk
knnnnnnnnnnNk
knnnnnnnnnnNk
kNNNNNNNNNNNk
kkkkkkkkkkkkk
""",
"chevdown": """
kk.......kk
krk.....krk
.krk...krk.
..krk.krk..
...krkrk...
....krk....
kk...k...kk
krk.....krk
.krk...krk.
..krk.krk..
...krkrk...
....krk....
.....k.....
""",
"pen": """
..........kk.
.........krrk
........ksrRk
.......kgsSk.
......kgyGk..
.....kgyGk...
....kgyGk....
...kgyGk.....
..ktgGk......
..kttk.......
.kSk.........
kk...........
""",
"cuffs": """
.kkkkk....kkkkk.
kssssSk..kssssSk
ksk..kSkkSk..ksk
ksk..kSSSSk..ksk
ksk..kSkkSk..ksk
ksssssk..kssssSk
.kkkkk....kkkkk.
""",
"target": """
....kkkkk....
..kkrrrrrkk..
.krrkkkkkrrk.
.krk.....krk.
krk..kkk..krk
krk.krrrk.krk
krk.krwrk.krk
krk.krrrk.krk
krk..kkk..krk
.krk.....krk.
.krrkkkkkrrk.
..kkrrrrrkk..
....kkkkk....
""",
"license": """
kkkkkkkkkkkkkkk
kbbbbbbbbbbbbbk
kkkkkkkkkkkkkkk
kwwwwwwwwwwwwSk
kwtttwSSSSSwwSk
kwtttwwwwwwwwSk
kwnnnwSSSSwwwSk
kwnnnwwwwwwwwSk
kSSSSSSSSSSSSSk
kkkkkkkkkkkkkkk
""",
"eraser": """
......kkkkkkk
.....krrrkbbk
....krrrkbbBk
...krrrkbbBk.
..krrrkbbBk..
.kRrrkbbBk...
kRRRkBBBk....
kkkkkkkk.....
.............
sss.sss.sss..
""",
"bars": """
..........kkk.
..........kek.
......kkk.kek.
......kbk.kek.
..kkk.kbk.kek.
..kok.kbk.kek.
..kok.kbk.kek.
..kok.kbk.kek.
..kok.kbk.kEk.
..kok.kBk.kEk.
kkkkkkkkkkkkkk
kSSSSSSSSSSSSk
kkkkkkkkkkkkkk
""",
"play": """
.kk.........
.kekk.......
.keeekk.....
.keeeeekk...
.keeeeeeekk.
.keeeeeeeeek
.keeeeeeeeek
.keeeeeeekk.
.keeeeekk...
.keeekk.....
.kEkk.......
.kk.........
""",
"stop": """
kkkkkkkkkkk
krrrrrrrrRk
krwrrrrrrRk
krrrrrrrrRk
krrrrrrrrRk
krrrrrrrrRk
krrrrrrrrRk
krrrrrrrrRk
krrrrrrrrRk
kRRRRRRRRRk
kkkkkkkkkkk
""",
"bell": """
.....kkk.....
....kgyyk....
...kggyyyk...
..kgggggyyk..
..kggggggyk..
..kggggggyk..
..kgggggggk..
.kgggggggggk.
.kgggggggggk.
kggggggggggGk
kGGGGGGGGGGGk
kkkkkkkkkkkkk
.....kgk.....
......k......
""",
"image": """
kkkkkkkkkkkkkk
kccccccccccwck
kcccccccccccck
kcccccccccccck
kccccckcccccck
kcccckekccccck
kccckeeekckcck
kcckeeeeekekck
kckeeEeeeeeeek
kkEEEEEEEEEEEk
kEEEEEEEEEEEEk
kkkkkkkkkkkkkk
""",
"info": """
...kkkkkkk...
..kbbbbbbbk..
.kbbbbwbbbbk.
kbbbbwwbbbbBk
kbbbbbbbbbbBk
kbbbbwwbbbbBk
kbbbbwwbbbbBk
kbbbbwwbbbbBk
kbbbbwwbbbbBk
.kbbbwwwbbBk.
..kBBBBBBBk..
...kkkkkkk...
""",
}

# selos 7x7 no canto de baixo à direita (variações: desbanir, desmutar...)
SELOS = {
"ok": """
.kkkkkkk.
keeeeeeek
keeeeeewk
keeeeewek
kweeeweek
keweweeek
keeweeeek
keeeeeeek
.kkkkkkk.
""",
"no": """
.kkkkkkk.
krrrrrrrk
krwrrrwrk
krrwrwrrk
krrrwrrrk
krrwrwrrk
krwrrrwrk
krrrrrrrk
.kkkkkkk.
""",
"plus": """
.kkkkkkk.
keeeeeeek
keeeweeek
keeeweeek
kewwwwwek
keeeweeek
keeeweeek
keeeeeeek
.kkkkkkk.
""",
"minus": """
.kkkkkkk.
krrrrrrrk
krrrrrrrk
krrrrrrrk
krwwwwwrk
krrrrrrrk
krrrrrrrk
krrrrrrrk
.kkkkkkk.
""",
"id": """
.kkkkkkk.
kbbbbbbbk
kbwbwwbbk
kbwbwbwbk
kbwbwbwbk
kbwbwbwbk
kbwbwwbbk
kbbbbbbbk
.kkkkkkk.
""",
"snow": """
.kkkkkkk.
kbbbbbbbk
kbwbwbwbk
kbbwwwbbk
kbwwwwwbk
kbbwwwbbk
kbwbwbwbk
kbbbbbbbk
.kkkkkkk.
""",
}

VARIACOES = [
    ("hammer", "ok"), ("hammer", "id"), ("bubble", "no"), ("bubble", "ok"), ("mic", "no"), ("mic", "ok"),
    ("jail", "ok"), ("snow", "ok"), ("gun", "no"), ("box", "no"), ("box", "snow"), ("halo", "no"),
    ("ghost", "no"), ("heart", "plus"), ("eye", "no"), ("eye", "ok"), ("music", "no"),
    ("crown", "id"), ("crown", "minus"), ("title", "no"), ("tag", "no"),
    ("brief", "no"), ("brief", "ok"), ("brief", "plus"), ("brief", "minus"),
    ("coin", "plus"), ("cuffs", "ok"), ("target", "no"), ("license", "no"),
    ("lock", "ok"), ("gun", "ok"), ("box", "ok"), ("lock", "no"),
]


def grade(nome, txt):
    linhas = [l for l in txt.strip("\n").split("\n")]
    larg = max(len(l) for l in linhas)
    ruins = [i for i, l in enumerate(linhas) if len(l) != larg]
    assert not ruins, "%s: linhas com largura errada %s (larg %d)" % (nome, ruins, larg)
    assert larg <= 16 and len(linhas) <= 16, nome
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    ox = (16 - larg) // 2
    oy = (16 - len(linhas)) // 2
    for y, l in enumerate(linhas):
        for x, ch in enumerate(l):
            if ch == ".":
                continue
            img.putpixel((ox + x, oy + y), PAL[ch] + (255,))
    return img


def main():
    os.makedirs(SAIDA, exist_ok=True)
    feitos = []
    for nome, txt in ICONES.items():
        img = grade(nome, txt)
        img.resize((16 * ESCALA, 16 * ESCALA), Image.NEAREST).save(os.path.join(SAIDA, nome + ".png"))
        feitos.append((nome, img))
    # o certo e o errado sozinhos (caixas de permissão)
    for nome, selo in (("check", "ok"), ("cross", "no")):
        img = grade(nome, SELOS[selo])
        img.resize((16 * ESCALA, 16 * ESCALA), Image.NEAREST).save(os.path.join(SAIDA, nome + ".png"))
        feitos.append((nome, img))
    base = dict(feitos)
    for nome, selo in VARIACOES:
        img = base[nome].copy()
        marca = grade("selo_" + selo, SELOS[selo])
        # o selo fica no canto de baixo à direita, por cima do desenho
        recorte = marca.crop((3, 3, 12, 12))
        img.alpha_composite(recorte, (7, 7))
        final = nome + "_" + selo
        img.resize((16 * ESCALA, 16 * ESCALA), Image.NEAREST).save(os.path.join(SAIDA, final + ".png"))
        feitos.append((final, img))
    # granulado
    rnd = random.Random(7)
    ruido = Image.new("RGBA", (128, 128))
    ruido.putdata([(v, v, v, 255) for v in (rnd.randint(0, 255) for _ in range(128 * 128))])
    ruido.save(os.path.join(RAIZ, "praetor", "materials", "praetor", "noise.png"))
    # folha de conferência
    col = 7
    lin = (len(feitos) + col - 1) // col
    folha = Image.new("RGBA", (col * 80, lin * 80), (40, 32, 36, 255))
    for i, (nome, img) in enumerate(feitos):
        folha.alpha_composite(img.resize((64, 64), Image.NEAREST), ((i % col) * 80 + 8, (i // col) * 80 + 8))
    folha.save(os.path.join(AQUI, "icones_preview.png"))
    print("ok", len(feitos), "ícones")


if __name__ == "__main__":
    main()
