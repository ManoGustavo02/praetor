# Praetor Admin System

A full admin mod for Garry's Mod that replaces SAM or ULX on its own: ranks, 94 commands, logs, chat box, scoreboard, AutoMod, reports, bans with a ban screen, votes, staff panel, prop protection and a loading screen. Everything is set up in one in-game menu.

- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3844482190
- Loading screen: https://praetor-loading.vercel.app/ (Vercel, serves this repo's `docs/loading` from GitHub Pages)

## Folders

| Folder | What it is |
|---|---|
| `praetor/` | The addon (put it in `garrysmod/addons/`) |
| `docs/loading/` | The loading screen page (GitHub Pages, served at praetor-loading.vercel.app) |
| `workshop/` | Workshop description, changelog and pictures |

## Loading screen

Praetor sets `sv_loadingurl` by itself (Settings > Loading screen). The page reads its look from the link:
`name`, `sub`, `accent` (hex), `tips` (split by `|`), `music` (`1`, `0` or a link), `vol`, `bg`, `logo`, `discord`.

## Credits

Made by Mano Gustavo. Fonts: Bagel Fat One and Nunito (SIL Open Font License 1.1, renamed "Praetor Display" / "Praetor Body").

---

# Praetor Admin System (PT-BR)

Um admin mod completo para Garry's Mod que substitui o SAM ou o ULX sozinho: cargos, 94 comandos, logs, chat, TAB, AutoMod, denúncias, bans com tela de ban, votações, painel da staff, proteção de props e tela de loading. Tudo configurado num menu dentro do jogo.

A pasta `praetor/` é o addon. A pasta `docs/loading/` é a tela de loading, que o Praetor liga sozinho em Configurações > Tela de loading.
