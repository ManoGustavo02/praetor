-- Praetor: the articles of the Wiki tab (cl_tab_wiki.lua), in English and Portuguese.
-- Blocks: { "h", text } heading, { "p", text } paragraph, { "b", { ... } } bullets,
-- { "n", { ... } } numbered steps, { "k", { { key, text }, ... } } key / meaning rows,
-- { "tip", text } green note, { "warn", text } amber note.
local P = Praetor

P.Wiki = {
-- ==================================================================== start
{ id = "start", icon = "star",
en = { title = "Getting started", sub = "The first minutes with Praetor", blocks = {
	{ "p", "Praetor is the admin system of the server: ranks, commands, punishments, reports, logs, the chat, the scoreboard, the loading screen and the staff tools all live in this menu. Everything you see here depends on your permissions, so two staff members can see different tabs." },
	{ "h", "Becoming the owner" },
	{ "n", {
		"Open the server console (or rcon) and type: praetor_owner add YourSteamID",
		"Join the server (or rejoin). Owners get the highest rank by themselves.",
		"Open this menu with !menu in the chat or praetor_menu in the console. Tip: bind a key, for example bind F6 praetor_menu.",
	} },
	{ "warn", "praetor_owner only works from the server console. Owners can change the protected settings (rank lock, webhook URL, loading screen base) that nobody else can touch." },
	{ "h", "Where to start" },
	{ "b", {
		"Settings > General: the language of the menu and of the chat messages.",
		"Ranks: create your staff ranks and choose what each one can do.",
		"Settings > Discord webhook: send the logs to a Discord channel (see the Logs and Discord article).",
		"Settings > Loading screen: the page players see while they join.",
	} },
	{ "tip", "Already used SAM or ULX? Settings > Import from SAM / ULX brings the ranks, users and bans over." },
} },
pt = { title = "Primeiros passos", sub = "Os primeiros minutos com o Praetor", blocks = {
	{ "p", "O Praetor é o sistema de administração do servidor: cargos, comandos, punições, denúncias, logs, o chat, o placar, a tela de loading e as ferramentas da staff ficam todos neste menu. O que aparece aqui depende das suas permissões, então dois membros da staff podem ver abas diferentes." },
	{ "h", "Virando dono" },
	{ "n", {
		"Abra o console do servidor (ou o rcon) e digite: praetor_owner add SeuSteamID",
		"Entre no servidor (ou entre de novo). Donos recebem o cargo mais alto sozinhos.",
		"Abra este menu com !menu no chat ou praetor_menu no console. Dica: deixe numa tecla, por exemplo bind F6 praetor_menu.",
	} },
	{ "warn", "O praetor_owner só funciona pelo console do servidor. Donos mudam as configurações protegidas (trava de cargos, URL do webhook, base da tela de loading), que mais ninguém pode mexer." },
	{ "h", "Por onde começar" },
	{ "b", {
		"Configurações > Geral: o idioma do menu e das mensagens do chat.",
		"Cargos: crie os cargos da staff e escolha o que cada um pode fazer.",
		"Configurações > Webhook do Discord: mande os logs para um canal do Discord (veja o artigo Logs e Discord).",
		"Configurações > Tela de loading: a página que o jogador vê enquanto entra.",
	} },
	{ "tip", "Já usava SAM ou ULX? Configurações > Importar do SAM / ULX traz os cargos, usuários e bans." },
} } },

-- ==================================================================== ranks
{ id = "ranks", icon = "crown",
en = { title = "Ranks and permissions", sub = "Who can do what", blocks = {
	{ "p", "Every player has one rank. A rank has a name, a look (colour, icon and effect used in the chat, scoreboard and over the head), a list of permissions and optional limits (props, ragdolls, vehicles...)." },
	{ "h", "Creating a rank" },
	{ "n", {
		"Open the Ranks tab and press the button to create a new rank.",
		"Give it a name and a look. The preview shows how it will appear.",
		"Tick the permissions. Each command is a permission, and so are the menu tabs and the staff tools.",
		"Save. Give the rank with !setrank name rank, or in the Users tab.",
	} },
	{ "h", "Who can act on whom" },
	{ "p", "A staff member can only use commands on players of a lower rank. Settings > Protection decides whether equal ranks can target each other and lets owners lock rank changes so a stolen account can't promote itself." },
	{ "h", "Useful extras" },
	{ "b", {
		"Promotions tab: give a rank by hours played (for example Member after 10 hours).",
		"Weekly goal: hours on duty a staff rank should do in 7 days (see Staff mode).",
		"Permissions are also read by other addons through CAMI, so ranks made here work in addons that support it.",
	} },
} },
pt = { title = "Cargos e permissões", sub = "Quem pode fazer o quê", blocks = {
	{ "p", "Todo jogador tem um cargo. O cargo tem um nome, um visual (cor, ícone e efeito usados no chat, no placar e em cima da cabeça), uma lista de permissões e limites opcionais (props, ragdolls, veículos...)." },
	{ "h", "Criando um cargo" },
	{ "n", {
		"Abra a aba Cargos e aperte o botão de criar cargo.",
		"Dê um nome e um visual. A prévia mostra como vai aparecer.",
		"Marque as permissões. Cada comando é uma permissão, assim como as abas do menu e as ferramentas da staff.",
		"Salve. Dê o cargo com !setrank nome cargo, ou pela aba Usuários.",
	} },
	{ "h", "Quem pode agir em quem" },
	{ "p", "A staff só usa comandos em jogadores de cargo mais baixo. Configurações > Proteção decide se cargos iguais podem agir entre si e deixa os donos travarem mudanças de cargo, para uma conta roubada não conseguir se promover." },
	{ "h", "Extras úteis" },
	{ "b", {
		"Aba Promoções: dá um cargo por horas jogadas (por exemplo Membro depois de 10 horas).",
		"Meta semanal: horas em serviço que um cargo da staff deve fazer em 7 dias (veja Modo staff).",
		"Outros addons leem as permissões pelo CAMI, então os cargos criados aqui funcionam nos addons que suportam.",
	} },
} } },

-- ==================================================================== commands
{ id = "commands", icon = "sword",
en = { title = "Using commands", sub = "Chat, console, targets and times", blocks = {
	{ "p", "Commands work in the chat with ! or / (for example !kick bob spam) and in the console with praetor or pr (for example pr kick bob spam). The Commands tab lists every command you can use with a short explanation, and the Shortcuts tab runs them with clicks." },
	{ "h", "Choosing players" },
	{ "k", {
		{ "bob", "part of a name is enough when only one player matches" },
		{ "^ or me", "yourself" },
		{ "@", "the player you are looking at" },
		{ "*", "everyone" },
		{ "#vip", "everyone of a rank" },
		{ "!bob", "everyone except bob" },
		{ "bob,alice", "more than one player" },
		{ "STEAM_0:...", "a SteamID (also works for bans of offline players)" },
	} },
	{ "p", "In many commands the player is optional: !god without a name means you." },
	{ "h", "Times" },
	{ "k", {
		{ "30", "minutes" },
		{ "10m 2h 3d 1w", "minutes, hours, days, weeks (they can be mixed: 1d12h)" },
		{ "0 or perm", "permanent" },
	} },
	{ "h", "Silent commands" },
	{ "p", "Start a command with ~ (for example ~ban bob 1d) and only the staff sees the message. The symbol can be changed in Settings > General, where you also choose who sees command messages." },
	{ "tip", "Staff chat: start a message with @ and only the staff reads it." },
} },
pt = { title = "Usando comandos", sub = "Chat, console, alvos e tempos", blocks = {
	{ "p", "Os comandos funcionam no chat com ! ou / (por exemplo !kick bob spam) e no console com praetor ou pr (por exemplo pr kick bob spam). A aba Comandos lista todos os comandos que você pode usar com uma explicação curta, e a aba Atalhos executa eles com cliques." },
	{ "h", "Escolhendo jogadores" },
	{ "k", {
		{ "bob", "parte do nome basta quando só um jogador combina" },
		{ "^ ou eu", "você mesmo" },
		{ "@", "o jogador que você está olhando" },
		{ "*", "todo mundo" },
		{ "#vip", "todos de um cargo" },
		{ "!bob", "todos menos o bob" },
		{ "bob,alice", "mais de um jogador" },
		{ "STEAM_0:...", "um SteamID (também serve para banir quem está offline)" },
	} },
	{ "p", "Em muitos comandos o jogador é opcional: !god sem nome é você." },
	{ "h", "Tempos" },
	{ "k", {
		{ "30", "minutos" },
		{ "10m 2h 3d 1w", "minutos, horas, dias, semanas (dá para misturar: 1d12h)" },
		{ "0 ou perm", "permanente" },
	} },
	{ "h", "Comandos silenciosos" },
	{ "p", "Comece o comando com ~ (por exemplo ~ban bob 1d) e só a staff vê a mensagem. O símbolo muda em Configurações > Geral, onde também se escolhe quem vê as mensagens dos comandos." },
	{ "tip", "Chat da staff: comece a mensagem com @ e só a staff lê." },
} } },

-- ==================================================================== staff mode
{ id = "duty", icon = "shield",
en = { title = "Staff mode", sub = "Going on duty, the shift and the goals", blocks = {
	{ "p", "Staff mode separates the time a staff member is working from the time they are just playing. Start and stop it with !staffmode (also !duty). While it is on, a card on the left of the screen shows the time of the shift." },
	{ "h", "What changes on duty" },
	{ "b", {
		"Weapons that hurt are put away and come back after (the physgun and tools stay).",
		"The staff baton: one tool with many modes (see the Staff baton article).",
		"Optional invisibility while on duty.",
		"The staff is hidden from E2 and Starfall chips, so ESP chips can't follow them.",
		"The staff ESP: every player through walls, with picture, name, health and armor.",
		"Only the time on duty counts for the hours in the Staff panel.",
	} },
	{ "p", "Each part can be turned off in Settings > Staff mode. Turning off \"Staff mode\" itself removes the whole system." },
	{ "h", "Reports only on duty (optional)" },
	{ "p", "With \"Reports only for staff on duty\" on, only staff on duty get the alerts of new reports. Taking a report or opening a support room off duty asks \"Start staff mode?\": yes starts the shift and takes it at once. It comes off by default." },
	{ "h", "End of the shift" },
	{ "p", "When the shift ends a summary shows for a few seconds: time on duty, commands, punishments, reports, rooms and baton actions. With \"End the shift when AFK\" on, a staff member who goes AFK leaves staff mode by themselves." },
	{ "h", "Weekly goals" },
	{ "n", {
		"Turn on Settings > Staff mode > Weekly hour goal per rank.",
		"In Ranks, edit a staff rank and fill \"Hours on duty per week\".",
		"Staff see the progress under their card; owners see everyone in the Staff panel.",
	} },
} },
pt = { title = "Modo staff", sub = "Entrar em serviço, o turno e as metas", blocks = {
	{ "p", "O modo staff separa o tempo em que a staff está trabalhando do tempo em que está só jogando. Entre e saia com !staffmode (também !expediente ou !duty). Enquanto está ligado, um cartão na esquerda da tela mostra o tempo do turno." },
	{ "h", "O que muda em serviço" },
	{ "b", {
		"Armas que machucam ficam guardadas e voltam depois (a physgun e as ferramentas ficam).",
		"O bastão da staff: uma ferramenta com vários modos (veja o artigo Bastão da staff).",
		"Invisibilidade opcional enquanto estiver em serviço.",
		"A staff fica escondida de chips E2 e Starfall, então chips de ESP não conseguem segui-la.",
		"O ESP da staff: todos os jogadores através das paredes, com foto, nome, vida e colete.",
		"Só o tempo em serviço conta nas horas do Painel da staff.",
	} },
	{ "p", "Cada parte pode ser desligada em Configurações > Modo staff. Desligar o próprio \"Modo staff\" tira o sistema inteiro." },
	{ "h", "Denúncias só em serviço (opcional)" },
	{ "p", "Com \"Denúncias só para a staff em serviço\" ligado, só quem está em serviço recebe os alertas de denúncias novas. Atender uma denúncia ou abrir uma sala fora de serviço pergunta \"Entrar no modo staff?\": sim começa o turno e já atende. Vem desligado." },
	{ "h", "Fim do turno" },
	{ "p", "Quando o turno acaba, um resumo aparece por alguns segundos: tempo em serviço, comandos, punições, denúncias, salas e ações com o bastão. Com \"Encerrar o turno quando ficar AFK\" ligado, quem fica AFK sai do modo staff sozinho." },
	{ "h", "Metas semanais" },
	{ "n", {
		"Ligue Configurações > Modo staff > Meta semanal de horas por cargo.",
		"Em Cargos, edite um cargo da staff e preencha \"Horas em serviço por semana\".",
		"A staff vê o progresso embaixo do cartão; os donos veem todo mundo no Painel da staff.",
	} },
} } },

-- ==================================================================== baton
{ id = "baton", icon = "wrench",
en = { title = "Staff baton", sub = "One tool, many modes", blocks = {
	{ "p", "The baton comes with staff mode and never hurts anyone. R goes to the next mode and Shift + R to the previous one. The list of modes and what each button does shows on the left of the screen." },
	{ "k", {
		{ "Hold", "hold the left button to carry a player or prop, mouse wheel to bring it closer or farther, right button to throw" },
		{ "Freeze", "freeze or unfreeze a player or prop" },
		{ "Push", "left pushes away, right pulls closer" },
		{ "Teleport", "left takes you where you aim, right brings the player you aim at" },
		{ "Info", "rank, SteamID, health and internal notes; right copies the SteamID" },
		{ "Support room", "left opens a room with the player, right ends your room" },
		{ "Jail", "left jails for 5 minutes, right releases (aiming at the cell works too)" },
		{ "Spectate", "left watches the player, right opens the free camera" },
		{ "Remove", "deletes the prop you aim at" },
		{ "Invisibility", "turns your invisibility on or off" },
		{ "ESP", "turns your staff ESP on or off" },
	} },
	{ "tip", "Every mode checks the same permission as the matching command, and everything done with the baton is in the logs." },
} },
pt = { title = "Bastão da staff", sub = "Uma ferramenta, vários modos", blocks = {
	{ "p", "O bastão vem com o modo staff e não machuca ninguém. O R vai para o próximo modo e Shift + R volta. A lista de modos e o que cada botão faz aparece na esquerda da tela." },
	{ "k", {
		{ "Segurar", "segure o botão esquerdo para carregar um jogador ou prop, rodinha para aproximar ou afastar, botão direito para arremessar" },
		{ "Congelar", "congela ou descongela um jogador ou prop" },
		{ "Empurrar", "esquerdo empurra para longe, direito puxa para perto" },
		{ "Teleporte", "esquerdo leva você para onde mira, direito traz o jogador que está mirando" },
		{ "Informações", "cargo, SteamID, vida e anotações internas; direito copia o SteamID" },
		{ "Atendimento", "esquerdo abre uma sala com o jogador, direito encerra a sua sala" },
		{ "Prender", "esquerdo prende por 5 minutos, direito solta (mirar na cela também serve)" },
		{ "Espectar", "esquerdo assiste o jogador, direito abre a câmera livre" },
		{ "Remover", "apaga o prop que está mirando" },
		{ "Invisibilidade", "liga ou desliga sua invisibilidade" },
		{ "ESP", "liga ou desliga o seu ESP da staff" },
	} },
	{ "tip", "Cada modo confere a mesma permissão do comando equivalente, e tudo o que é feito com o bastão vai para os logs." },
} } },

-- ==================================================================== esp, chips, sprays
{ id = "esp", icon = "eye",
en = { title = "ESP, chips and sprays", sub = "Seeing what players hide", blocks = {
	{ "h", "Staff ESP" },
	{ "p", "On duty, staff with the \"esp\" permission see every player through walls: a box, health and armor bars and a card with the picture, name, rank, distance, weapon and state (invisible, AFK, jailed, frozen...). Far players turn into a short label so the screen stays clean. Each staff member can turn it off with the baton or praetor_esp 0." },
	{ "p", "Staff with \"see_cloaked\" see invisible players as see-through ghosts, on duty or not." },
	{ "h", "Chips (E2 and Starfall)" },
	{ "p", "The Chips tab lists every chip on the map with its name, owner, CPU and holograms. From there you can go to a chip, stop it, remove it or remove every chip of its owner (right click)." },
	{ "p", "Staff on duty get an alert when a chip:" },
	{ "b", {
		"stays above the CPU limit (Settings > Staff mode; these chips lag or crash the server),",
		"keeps reading where most players are, like an ESP or aimbot chip,",
		"attaches holograms to another player.",
	} },
	{ "p", "Staff on duty and invisible players are also hidden from chips: searches skip them and their position reads as 0,0,0." },
	{ "h", "Sprays" },
	{ "b", {
		"Look at a spray to see whose it is and when it was made (permission spray_info).",
		"!sprayban name blocks the sprays of a player, even after they rejoin. !unsprayban gives them back.",
		"!clearsprays (or !cleardecals) wipes every spray and mark of the map for everyone.",
		"Settings > Moderation > Allow sprays turns sprays off for the whole server.",
	} },
} },
pt = { title = "ESP, chips e sprays", sub = "Vendo o que os jogadores escondem", blocks = {
	{ "h", "ESP da staff" },
	{ "p", "Em serviço, a staff com a permissão \"esp\" vê todos os jogadores através das paredes: uma caixa, barras de vida e colete e um cartão com a foto, nome, cargo, distância, arma e estado (invisível, AFK, preso, congelado...). Jogadores longe viram uma etiqueta curta para a tela não poluir. Cada um pode desligar com o bastão ou praetor_esp 0." },
	{ "p", "A staff com \"see_cloaked\" vê jogadores invisíveis como fantasmas transparentes, em serviço ou não." },
	{ "h", "Chips (E2 e Starfall)" },
	{ "p", "A aba Chips lista todos os chips do mapa com nome, dono, CPU e hologramas. Por ela dá para ir até um chip, parar, remover ou remover todos os chips do dono (botão direito)." },
	{ "p", "A staff em serviço recebe um alerta quando um chip:" },
	{ "b", {
		"passa do limite de CPU (Configurações > Modo staff; esses chips travam ou derrubam o servidor),",
		"fica lendo onde a maioria dos jogadores está, como um chip de ESP ou aimbot,",
		"prende hologramas em outro jogador.",
	} },
	{ "p", "A staff em serviço e os jogadores invisíveis também ficam escondidos dos chips: as buscas pulam eles e a posição vem como 0,0,0." },
	{ "h", "Sprays" },
	{ "b", {
		"Olhe para um spray para ver de quem é e quando foi feito (permissão spray_info).",
		"!sprayban nome bloqueia os sprays de um jogador, mesmo se ele sair e voltar. !unsprayban libera.",
		"!clearsprays (ou !cleardecals) limpa todos os sprays e marcas do mapa para todos.",
		"Configurações > Moderação > Permitir sprays desliga os sprays no servidor inteiro.",
	} },
} } },

-- ==================================================================== reports
{ id = "reports", icon = "flag",
en = { title = "Reports and support rooms", sub = "Helping players", blocks = {
	{ "p", "Players open a report with !report (or praetor_report). The staff gets an alert and the report shows on the right of the screen and in the Reports tab." },
	{ "n", {
		"Take the report (the card on the screen or the Reports tab). The player is told who took it.",
		"Talk, go to the player or open a support room.",
		"Close it with an answer. The player can rate the help with stars, shown in the Staff panel.",
	} },
	{ "h", "Support rooms" },
	{ "p", "A support room takes the staff and the players to a quiet place and brings them back when it ends. Save rooms on each map in the Support rooms tab (stand where you want it and save). Without saved rooms, Praetor builds one in the sky." },
	{ "b", {
		"!sit name opens a room with the player; !endsit ends it.",
		"Settings > Staff, rooms and accounts: god mode inside, and opening a room when a report is taken.",
	} },
	{ "tip", "Blackbox installed? \"Let Blackbox handle !report\" in Settings > Logs and reports sends the reports to it." },
} },
pt = { title = "Denúncias e salas de atendimento", sub = "Ajudando os jogadores", blocks = {
	{ "p", "O jogador abre uma denúncia com !report (ou praetor_report). A staff recebe um alerta e a denúncia aparece na direita da tela e na aba Denúncias." },
	{ "n", {
		"Atenda a denúncia (pelo cartão na tela ou pela aba Denúncias). O jogador fica sabendo quem atendeu.",
		"Converse, vá até o jogador ou abra uma sala de atendimento.",
		"Feche com uma resposta. O jogador pode avaliar o atendimento com estrelas, que aparecem no Painel da staff.",
	} },
	{ "h", "Salas de atendimento" },
	{ "p", "A sala leva a staff e os jogadores para um lugar tranquilo e traz de volta quando acaba. Salve salas em cada mapa na aba Salas de atendimento (fique onde quer e salve). Sem salas salvas, o Praetor monta uma no céu." },
	{ "b", {
		"!sit nome abre uma sala com o jogador; !endsit encerra.",
		"Configurações > Staff, salas e contas: modo deus dentro da sala, e abrir uma sala ao atender uma denúncia.",
	} },
	{ "tip", "Tem o Blackbox? \"Deixar o Blackbox cuidar do !report\" em Configurações > Logs e denúncias manda as denúncias para ele." },
} } },

-- ==================================================================== punishments
{ id = "punish", icon = "hammer",
en = { title = "Punishments", sub = "Warnings, mutes, jail and bans", blocks = {
	{ "k", {
		{ "!warn", "a warning with points. Points add up and expire after some days" },
		{ "!mute / !gag", "blocks the chat / the voice, for a time or until removed" },
		{ "!jail", "puts the player in a cell, for a time or until !unjail" },
		{ "!kick", "removes the player from the server" },
		{ "!ban / !banid", "bans an online player / a SteamID" },
	} },
	{ "h", "Automatic punishments" },
	{ "p", "Settings > Moderation > warning rules: when a player reaches a number of points, something happens (a kick, a 1 day ban...). Warnings expire after the days set there." },
	{ "h", "Bans" },
	{ "p", "The Bans tab lists every ban with reason, time and who banned, and edits or removes them. In Settings > Bans and ban screen you set the Discord link and the appeal text the banned player sees, and who is told when a banned player tries to join." },
	{ "tip", "The player sheet (Users tab, or !sheet name) shows the whole history of a player: punishments, names, alt accounts and internal notes only the staff can read." },
} },
pt = { title = "Punições", sub = "Advertências, mutes, prisão e bans", blocks = {
	{ "k", {
		{ "!warn", "uma advertência com pontos. Os pontos somam e vencem depois de alguns dias" },
		{ "!mute / !gag", "bloqueia o chat / a voz, por um tempo ou até tirar" },
		{ "!jail", "coloca o jogador numa cela, por um tempo ou até !unjail" },
		{ "!kick", "tira o jogador do servidor" },
		{ "!ban / !banid", "bane um jogador online / um SteamID" },
	} },
	{ "h", "Punições automáticas" },
	{ "p", "Configurações > Moderação > regras de advertência: quando o jogador chega num número de pontos, algo acontece (um kick, um ban de 1 dia...). As advertências vencem depois dos dias definidos ali." },
	{ "h", "Bans" },
	{ "p", "A aba Banimentos lista todos os bans com motivo, tempo e quem baniu, e edita ou remove. Em Configurações > Bans e tela de ban ficam o link do Discord e o texto de apelação que o banido vê, e quem é avisado quando um banido tenta entrar." },
	{ "tip", "A ficha do jogador (aba Usuários, ou !sheet nome) mostra o histórico inteiro: punições, nomes, contas alternativas e anotações internas que só a staff lê." },
} } },

-- ==================================================================== logs + webhook
{ id = "webhook", icon = "send",
en = { title = "Logs and Discord", sub = "Sending the logs to a Discord channel", blocks = {
	{ "p", "Everything that happens is saved in the Logs tab (commands, punishments, chat, kills, joins, DarkRP...) for the days set in Settings > Logs and reports. The Discord webhook sends the categories you choose to a channel of your Discord, as they happen." },
	{ "h", "1. Create the webhook in Discord" },
	{ "n", {
		"In Discord, open the settings of the channel that will receive the logs (the gear next to its name).",
		"Integrations > Webhooks > New Webhook.",
		"Give it a name and a picture if you want, and press Copy Webhook URL.",
	} },
	{ "h", "2. Paste it in Praetor" },
	{ "n", {
		"Here in the menu: Settings > Discord webhook.",
		"Paste the link in \"Webhook URL\". Only owners see and change this field.",
		"Choose the language of the messages and the bot name.",
		"Press \"Send a test\". A test message should show in the channel within seconds.",
	} },
	{ "h", "3. Choose what is sent" },
	{ "k", {
		{ "Commands", "every command: who used it, on whom and what" },
		{ "Punishments", "bans, kicks, mutes, jails and warnings" },
		{ "AutoMod", "messages blocked by the word filter" },
		{ "Reports", "reports opened, taken and closed" },
		{ "Ranks", "rank, tag and permission changes" },
		{ "Security", "blocked actions, anti-crash, alt accounts, suspicious chips" },
		{ "Settings", "who changed which setting" },
		{ "Chat", "every message (busy servers: a lot of messages)" },
		{ "Joins", "players joining and leaving" },
		{ "Kills", "who killed whom and with what" },
		{ "DarkRP / economy", "jobs, arrests, wanted, shops, money and doors" },
		{ "Player events", "name changes, vehicles, noclip, sprays" },
		{ "TTT rounds", "the start and end of rounds" },
	} },
	{ "h", "Weekly report" },
	{ "p", "Once a week (Monday at 12:00 by default, server time) the webhook also gets a summary of the last 7 days: players and new players, the peak online, staff hours and the most active staff, bans, kicks, warnings, reports and how fast they were closed, the average tick, the time with lag and what the anti-crash did. Numbers that can be compared show the change from the week before. Change the day and hour, or turn it off, in Settings > Discord webhook. \"Send the weekly report now\" sends one right away to see how it looks." },
	{ "tip", "A good start: Commands, Punishments, Reports, Ranks and Security. Leave Chat and Kills off on busy servers, or the channel moves too fast to read." },
	{ "warn", "Treat the webhook URL as a password: anyone with it can post in your channel. Praetor never sends it to players. If it leaks, delete the webhook in Discord and create a new one." },
	{ "h", "The test does not arrive?" },
	{ "b", {
		"Check the link: it starts with https://discord.com/api/webhooks/.",
		"The webhook may have been deleted in Discord: create a new one.",
		"Some hosts block requests to Discord. Installing the CHTTP module on the server solves it; Praetor uses it by itself.",
	} },
} },
pt = { title = "Logs e Discord", sub = "Mandando os logs para um canal do Discord", blocks = {
	{ "p", "Tudo o que acontece fica salvo na aba Logs (comandos, punições, chat, mortes, entradas, DarkRP...) pelos dias definidos em Configurações > Logs e denúncias. O webhook do Discord manda as categorias que você escolher para um canal do seu Discord, na hora em que acontecem." },
	{ "h", "1. Crie o webhook no Discord" },
	{ "n", {
		"No Discord, abra as configurações do canal que vai receber os logs (a engrenagem ao lado do nome).",
		"Integrações > Webhooks > Novo webhook.",
		"Dê um nome e uma foto se quiser, e aperte Copiar URL do webhook.",
	} },
	{ "h", "2. Cole no Praetor" },
	{ "n", {
		"Aqui no menu: Configurações > Webhook do Discord.",
		"Cole o link em \"URL do webhook\". Só os donos veem e mudam esse campo.",
		"Escolha o idioma das mensagens e o nome do bot.",
		"Aperte \"Enviar um teste\". Uma mensagem de teste deve aparecer no canal em poucos segundos.",
	} },
	{ "h", "3. Escolha o que é enviado" },
	{ "k", {
		{ "Comandos", "todo comando: quem usou, em quem e o quê" },
		{ "Punições", "bans, kicks, mutes, prisões e advertências" },
		{ "AutoMod", "mensagens bloqueadas pelo filtro de palavras" },
		{ "Denúncias", "denúncias abertas, atendidas e fechadas" },
		{ "Cargos", "mudanças de cargo, tag e permissão" },
		{ "Segurança", "ações bloqueadas, anti-crash, contas alternativas, chips suspeitos" },
		{ "Configurações", "quem mudou qual configuração" },
		{ "Chat", "todas as mensagens (servidor cheio: muitas mensagens)" },
		{ "Entradas", "jogadores entrando e saindo" },
		{ "Mortes", "quem matou quem e com o quê" },
		{ "DarkRP / economia", "profissões, prisões, procurados, lojas, dinheiro e portas" },
		{ "Eventos de jogador", "troca de nome, veículos, noclip, sprays" },
		{ "Rodadas do TTT", "início e fim das rodadas" },
	} },
	{ "h", "Relatório semanal" },
	{ "p", "Uma vez por semana (segunda às 12:00 por padrão, no horário do servidor) o webhook também recebe um resumo dos últimos 7 dias: jogadores e jogadores novos, o pico online, horas da staff e a staff mais ativa, bans, kicks, avisos, denúncias e a rapidez com que foram fechadas, o tick médio, o tempo com lag e o que o anti-crash fez. Os números que dão para comparar mostram a diferença para a semana anterior. Mude o dia e a hora, ou desligue, em Configurações > Webhook do Discord. \"Enviar o relatório agora\" manda um na hora para ver como fica." },
	{ "tip", "Um bom começo: Comandos, Punições, Denúncias, Cargos e Segurança. Deixe Chat e Mortes desligados em servidor cheio, senão o canal corre rápido demais para ler." },
	{ "warn", "Trate a URL do webhook como uma senha: quem tiver ela posta no seu canal. O Praetor nunca manda ela para os jogadores. Se vazar, apague o webhook no Discord e crie outro." },
	{ "h", "O teste não chega?" },
	{ "b", {
		"Confira o link: ele começa com https://discord.com/api/webhooks/.",
		"O webhook pode ter sido apagado no Discord: crie outro.",
		"Algumas hospedagens bloqueiam o Discord. Instalar o módulo CHTTP no servidor resolve; o Praetor usa ele sozinho.",
	} },
} } },

-- ==================================================================== tags
{ id = "tags", icon = "tag",
en = { title = "Tags and titles", sub = "The difference and where each one shows", blocks = {
	{ "k", {
		{ "Rank", "comes with the rank. Same look for everyone of the rank" },
		{ "Chat tag", "a small badge of one player, before the name in the chat, over the head and in the scoreboard" },
		{ "Title", "a line of text of one player, under the name over the head and in the scoreboard. It does not show in the chat" },
	} },
	{ "h", "Giving a tag or a title" },
	{ "n", {
		"Tags and Titles tab: choose the player (by name or SteamID, offline works too).",
		"Choose Chat tag or Title. The text under it says where it will show.",
		"Write the text, pick the colours, the effect and an icon (tags).",
		"Check the preview and press Apply. Remove takes it away.",
	} },
	{ "b", {
		"Ready titles: save titles the staff uses a lot and pick them when giving.",
		"My tag: ranks with the self_tag permission make their own tag.",
		"Commands: !settag, !cleartag, !settitle, !cleartitle.",
		"What shows over the head is chosen in Settings > Tag above the head.",
	} },
} },
pt = { title = "Tags e títulos", sub = "A diferença e onde cada um aparece", blocks = {
	{ "k", {
		{ "Cargo", "vem com o cargo. Mesmo visual para todos do cargo" },
		{ "Tag de chat", "um selo pequeno de um jogador, antes do nome no chat, em cima da cabeça e no placar" },
		{ "Título", "uma linha de texto de um jogador, embaixo do nome em cima da cabeça e no placar. Não aparece no chat" },
	} },
	{ "h", "Dando uma tag ou um título" },
	{ "n", {
		"Aba Tags e Títulos: escolha o jogador (por nome ou SteamID, offline também funciona).",
		"Escolha Tag de chat ou Título. O texto embaixo diz onde vai aparecer.",
		"Escreva o texto, escolha as cores, o efeito e um ícone (tags).",
		"Confira a prévia e aperte Aplicar. Remover tira.",
	} },
	{ "b", {
		"Títulos prontos: salve títulos que a staff usa muito e escolha na hora de dar.",
		"Minha tag: cargos com a permissão self_tag fazem a própria tag.",
		"Comandos: !settag, !cleartag, !settitle, !cleartitle.",
		"O que aparece em cima da cabeça é escolhido em Configurações > Tag em cima da cabeça.",
	} },
} } },

-- ==================================================================== announcements and votes
{ id = "announce", icon = "megaphone",
en = { title = "Announcements and votes", sub = "Talking to the whole server", blocks = {
	{ "h", "Announcements" },
	{ "p", "The Announcements tab saves messages that are sent every few minutes, when a player joins or by hand. Each one can show in the chat, as a pop-up in a corner, as a bar at the top or in the middle of the screen, with colour, icon, link and who sees it. The preview shows the real look. !announce sends a quick one." },
	{ "h", "Votes" },
	{ "b", {
		"Votes tab: a poll with a question, options and time, or a map vote with the pictures of the maps.",
		"Player votes (Settings > Player votes): players start votekicks and votebans with limits, cooldown and a minimum of players.",
	} },
} },
pt = { title = "Anúncios e votações", sub = "Falando com o servidor inteiro", blocks = {
	{ "h", "Anúncios" },
	{ "p", "A aba Anúncios salva mensagens enviadas a cada X minutos, quando um jogador entra ou na mão. Cada uma pode aparecer no chat, como pop-up num canto, como barra no topo ou no meio da tela, com cor, ícone, link e quem vê. A prévia mostra o visual real. !announce manda um rápido." },
	{ "h", "Votações" },
	{ "b", {
		"Aba Votações: uma enquete com pergunta, opções e tempo, ou a votação de mapa com as fotos dos mapas.",
		"Votações de jogadores (Configurações > Votações de jogadores): os jogadores abrem votekick e voteban com limites, tempo de espera e um mínimo de jogadores.",
	} },
} } },

-- ==================================================================== restrictions / protection
{ id = "protect", icon = "lock",
en = { title = "Restrictions, props and anti-crash", sub = "Keeping the server stable", blocks = {
	{ "h", "Restrictions" },
	{ "p", "The Restrictions tab blocks weapons, entities, NPCs, vehicles and tools, or leaves them only for some ranks. The browser shows everything the server has, with pictures. Limits per rank (props, ragdolls...) are in the rank editor." },
	{ "h", "Prop protection" },
	{ "p", "Players can only touch their own props (and those of friends they allow). Props of players who leave are cleaned after the minutes set in Settings > Prop protection. If the server already uses FPP (DarkRP) or another protection, Praetor's turns itself off." },
	{ "h", "Dupes and spawning" },
	{ "p", "Settings > Spawning and dupes limits the size of dupes, the time between them and the models that can't be spawned." },
	{ "h", "Anti-crash" },
	{ "p", "Watches the server tick: when props start to lag the server it freezes them, and if needed removes them, then tells the staff who owned them. It also blocks spam of props, chat and network messages. The Security tab shows the tick live." },
	{ "tip", "Chips that crash servers are caught by the chip alerts (see ESP, chips and sprays)." },
} },
pt = { title = "Restrições, props e anti-crash", sub = "Mantendo o servidor estável", blocks = {
	{ "h", "Restrições" },
	{ "p", "A aba Restrições bloqueia armas, entidades, NPCs, veículos e ferramentas, ou deixa só para alguns cargos. O navegador mostra tudo o que o servidor tem, com fotos. Os limites por cargo (props, ragdolls...) ficam no editor do cargo." },
	{ "h", "Proteção de props" },
	{ "p", "O jogador só mexe nos próprios props (e nos de amigos que liberar). Props de quem saiu são limpos depois dos minutos definidos em Configurações > Proteção de props. Se o servidor já usa o FPP (DarkRP) ou outra proteção, a do Praetor desliga sozinha." },
	{ "h", "Dupes e spawn" },
	{ "p", "Configurações > Spawn e dupes limita o tamanho dos dupes, o tempo entre eles e os modelos que não podem ser criados." },
	{ "h", "Anti-crash" },
	{ "p", "Acompanha o tick do servidor: quando props começam a travar, ele congela e, se precisar, remove, e avisa a staff de quem eram. Também bloqueia spam de props, chat e mensagens de rede. A aba Segurança mostra o tick ao vivo." },
	{ "tip", "Chips que derrubam servidor são pegos pelos alertas de chips (veja ESP, chips e sprays)." },
} } },

-- ==================================================================== automod + security
{ id = "automod", icon = "bolt",
en = { title = "AutoMod and security", sub = "Filters and protection of the staff", blocks = {
	{ "h", "AutoMod" },
	{ "p", "The AutoMod tab blocks chat messages with listed words (and GIF / image links if you want), with exceptions, and chooses what happens to the player. Write a message in the test box to see if it would be blocked." },
	{ "h", "Security" },
	{ "b", {
		"Rank lock (owners): rank changes only by owners, so a stolen staff account can't promote anyone.",
		"Alt accounts: players who share an IP or a Steam Family with a banned player can be reported, kicked or banned (Settings > Staff, rooms and accounts).",
		"Backdoor scan: looks for known backdoors in the server files.",
		"Every blocked action shows in the Security tab and can go to Discord.",
	} },
} },
pt = { title = "AutoMod e segurança", sub = "Filtros e proteção da staff", blocks = {
	{ "h", "AutoMod" },
	{ "p", "A aba AutoMod bloqueia mensagens do chat com palavras listadas (e links de GIF / imagem se quiser), com exceções, e escolhe o que acontece com o jogador. Escreva uma mensagem na caixa de teste para ver se seria bloqueada." },
	{ "h", "Segurança" },
	{ "b", {
		"Trava de cargos (donos): só donos mudam cargos, então uma conta da staff roubada não promove ninguém.",
		"Contas alternativas: jogadores que dividem IP ou Família Steam com um banido podem ser avisados, kickados ou banidos (Configurações > Staff, salas e contas).",
		"Busca de backdoor: procura backdoors conhecidos nos arquivos do servidor.",
		"Toda ação bloqueada aparece na aba Segurança e pode ir para o Discord.",
	} },
} } },

-- ==================================================================== loading + scoreboard
{ id = "looks", icon = "image",
en = { title = "Loading screen, scoreboard and chat", sub = "What every player sees", blocks = {
	{ "h", "Loading screen" },
	{ "n", {
		"Settings > Loading screen: turn it on.",
		"Fill the server name, a subtitle and the tips (one per line).",
		"Paste links for the logo (square .png / .jpg) and the background (.png, .jpg or .gif).",
		"Optional: the Discord invite and a music link with its volume.",
	} },
	{ "p", "The page shows the download progress by itself. If the server already had its own loading screen, it stays until you save this option." },
	{ "h", "Scoreboard (TAB)" },
	{ "p", "Settings > Scoreboard: grouping by rank, job or none, the title, DarkRP info and music while the TAB is open." },
	{ "h", "Chat and over the head" },
	{ "b", {
		"Settings > Chat: Praetor's chat box, avatars, rank tags, times, local chat distance and pictures in the chat.",
		"Settings > Tag above the head: name, avatar, rank, title, tag, job, hours, health and the card when you aim at someone.",
		"Each player turns sounds, music and the chat box off for themselves in Settings > This computer.",
	} },
} },
pt = { title = "Tela de loading, placar e chat", sub = "O que todo jogador vê", blocks = {
	{ "h", "Tela de loading" },
	{ "n", {
		"Configurações > Tela de loading: ligue.",
		"Preencha o nome do servidor, um subtítulo e as dicas (uma por linha).",
		"Cole os links do logo (.png / .jpg quadrado) e do fundo (.png, .jpg ou .gif).",
		"Opcional: o convite do Discord e um link de música com o volume.",
	} },
	{ "p", "A página mostra o progresso dos downloads sozinha. Se o servidor já tinha uma tela de loading própria, ela continua até você salvar esta opção." },
	{ "h", "Placar (TAB)" },
	{ "p", "Configurações > Placar: agrupar por cargo, profissão ou nada, o título, informações do DarkRP e música enquanto o TAB está aberto." },
	{ "h", "Chat e em cima da cabeça" },
	{ "b", {
		"Configurações > Chat: a caixa de chat do Praetor, avatares, tags de cargo, horário, distância do chat local e imagens no chat.",
		"Configurações > Tag em cima da cabeça: nome, avatar, cargo, título, tag, profissão, horas, vida e o cartão ao mirar em alguém.",
		"Cada jogador desliga sons, músicas e a caixa de chat para si em Configurações > Este computador.",
	} },
} } },

-- ==================================================================== darkrp + custom commands
{ id = "extra", icon = "gear",
en = { title = "DarkRP and custom commands", sub = "Going further", blocks = {
	{ "h", "DarkRP" },
	{ "b", {
		"Jobs tab: whitelists per job and job bans.",
		"Commands: !setjob, !rpname, !setmoney, !arrest, !wanted, !license and others.",
		"Settings > DarkRP: HUD and F4 menu: Praetor's HUD and F4 menu, each one can be turned off.",
		"F4 > City: the mayor, the laws, the wanted list (model, picture, reason, who asked and the time left) and every RP command of your job. Police and mayor take someone off the wanted list with a right click on the card.",
	} },
	{ "h", "Custom commands" },
	{ "p", "The Custom Commands tab builds new commands with blocks, without code: give a name, choose who can use it and drag actions (teleport, give a weapon, send a message, if, for each...). They work in the chat like any other command." },
} },
pt = { title = "DarkRP e comandos personalizados", sub = "Indo além", blocks = {
	{ "h", "DarkRP" },
	{ "b", {
		"Aba Profissões: whitelist por profissão e banimento de profissão.",
		"Comandos: !setjob, !rpname, !setmoney, !arrest, !wanted, !license e outros.",
		"Configurações > DarkRP: HUD e menu F4: o HUD e o menu F4 do Praetor, cada um pode ser desligado.",
		"F4 > Cidade: o prefeito, as leis, a lista de procurados (modelo, foto, motivo, quem pediu e o tempo que falta) e todos os comandos de RP da sua profissão. Polícia e prefeito tiram alguém da lista com o botão direito no cartão.",
	} },
	{ "h", "Comandos personalizados" },
	{ "p", "A aba Comandos Personalizados cria comandos novos com blocos, sem código: dê um nome, escolha quem pode usar e arraste ações (teleportar, dar arma, mandar mensagem, se, para cada...). Eles funcionam no chat como qualquer outro comando." },
} } },

-- ==================================================================== faq
{ id = "faq", icon = "info",
en = { title = "Common questions", sub = "Quick answers", blocks = {
	{ "k", {
		{ "A tab is missing", "your rank doesn't have its permission. Ask an owner or check Ranks." },
		{ "A command says I can't target", "the player's rank is equal or higher than yours." },
		{ "I don't get report alerts", "\"Reports only for staff on duty\" is on: use !staffmode." },
		{ "The ESP doesn't show", "you must be on duty, have the esp permission and the ESP on (baton)." },
		{ "Changed a setting, nothing happened", "most changes apply at once; the loading screen applies to the next player who joins." },
		{ "Webhook test fails", "see Logs and Discord > The test does not arrive?" },
	} },
} },
pt = { title = "Dúvidas comuns", sub = "Respostas rápidas", blocks = {
	{ "k", {
		{ "Falta uma aba", "seu cargo não tem a permissão dela. Peça a um dono ou confira em Cargos." },
		{ "O comando diz que não posso usar no jogador", "o cargo dele é igual ou maior que o seu." },
		{ "Não recebo alerta de denúncia", "\"Denúncias só para a staff em serviço\" está ligado: use !staffmode." },
		{ "O ESP não aparece", "precisa estar em serviço, ter a permissão esp e o ESP ligado (bastão)." },
		{ "Mudei uma configuração e nada aconteceu", "a maioria vale na hora; a tela de loading vale para o próximo jogador que entrar." },
		{ "O teste do webhook falha", "veja Logs e Discord > O teste não chega?" },
	} },
} } },
}
