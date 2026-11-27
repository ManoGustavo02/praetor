-- Praetor: DarkRP's RP commands in two languages.
--  * Every command of the F4 "City" tab and of the commands drawer has its
--    DarkRP chat name (/dropmoney, /wanted...) and Portuguese names
--    (/soltardinheiro, /procurar...). Experienced players can type either one in
--    the chat; accents and upper case don't matter (/anúncio = /anuncio).
--  * The Portuguese name is turned into the DarkRP command on the server, so
--    DarkRP still decides who can use it (a citizen typing /toque gets the same
--    answer as /lockdown).
-- Server: Settings > DarkRP > rp_aliases.
local P = Praetor

-- id = { DarkRP chat command, { Portuguese names }, argument hint }
P.RPCmds = {
	dropmoney  = { "dropmoney", { "soltardinheiro", "soltargrana", "largardinheiro" }, "<valor|amount>" },
	give       = { "give", { "dardinheiro", "dargrana", "pagar" }, "<valor|amount>" },
	cheque     = { "cheque", { "cheque", "escrevercheque" }, "<jogador|player> <valor|amount>" },
	drop       = { "drop", { "soltararma", "largararma" }, "" },
	selldoors  = { "unownalldoors", { "venderportas", "venderpropriedades" }, "" },
	demote     = { "demote", { "demitir", "votardemissao" }, "<jogador|player> <motivo|reason>" },
	advert     = { "advert", { "anuncio", "anunciar" }, "<texto|text>" },
	jobname    = { "job", { "profissao", "nomeprofissao" }, "<nome|name>" },
	license    = { "requestlicense", { "pedirporte", "porte" }, "" },
	cr         = { "cr", { "policia", "socorro", "190" }, "<mensagem|message>" },
	agenda     = { "agenda", { "agenda", "pauta" }, "<texto|text>" },
	hitprice   = { "hitprice", { "precohit", "precocontrato" }, "<valor|amount>" },
	wanted     = { "wanted", { "procurar", "procurado" }, "<jogador|player> <motivo|reason>" },
	unwanted   = { "unwanted", { "tirarprocurado", "desprocurar" }, "<jogador|player>" },
	warrant    = { "warrant", { "mandado", "mandadobusca" }, "<jogador|player> <motivo|reason>" },
	givelicense = { "givelicense", { "darporte" }, "" },
	lockdown   = { "lockdown", { "toque", "toquederecolher", "recolher" }, "" },
	unlockdown = { "unlockdown", { "fimtoque", "fimdotoque", "liberar" }, "" },
	addlaw     = { "addlaw", { "criarlei", "novalei", "addlei" }, "<lei|law>" },
	removelaw  = { "removelaw", { "tirarlei", "removerlei" }, "<número|number>" },
	resetlaws  = { "resetlaws", { "limparleis", "resetarleis" }, "" },
	placelaws  = { "placelaws", { "quadroleis", "colocarleis" }, "" },
	broadcast  = { "broadcast", { "comunicado", "transmitir" }, "<mensagem|message>" },
	lottery    = { "lottery", { "loteria", "sorteio" }, "<valor|amount>" },
}

local FOLD = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
	["é"] = "e", ["ê"] = "e", ["è"] = "e", ["ë"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ò"] = "o", ["ö"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ç"] = "c",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["É"] = "e", ["Ê"] = "e",
	["Í"] = "i", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ú"] = "u", ["Ç"] = "c",
}
local function fold(s)
	s = tostring(s or ""):lower()
	for a, b in pairs(FOLD) do s = s:gsub(a, b) end
	return s
end
P.RPFold = fold

-- the Portuguese name a player of that language sees first
function P.RPCmdName(id, lang)
	local d = P.RPCmds[id]
	if not d then return nil end
	if lang == "pt" and d[2][1] then return d[2][1] end
	return d[1]
end

-- argument hint in one language ("<valor>" / "<amount>")
function P.RPCmdArgs(id, lang)
	local d = P.RPCmds[id]
	if not d or d[3] == "" then return "" end
	return (d[3]:gsub("<([^|>]+)|([^>]+)>", function(pt, en) return "<" .. (lang == "pt" and pt or en) .. ">" end))
end

if CLIENT then return end

-- alias -> DarkRP command (only names that are not DarkRP commands already)
local alias
local function build()
	alias = {}
	for _, d in pairs(P.RPCmds) do
		for _, a in ipairs(d[2]) do
			if a ~= d[1] then alias[fold(a)] = d[1] end
		end
	end
end

-- Called by the chat hook for "/name rest". Returns true when it was an RP alias.
function P.RPAlias(ply, name, rest)
	if not P.IsDarkRP() or P.Setting("rp_aliases") == false or not IsValid(ply) then return false end
	if not alias then build() end
	-- the drawer with every command of my job
	local f = fold(name)
	if f == "comandos" or f == "rpcmds" or f == "rpcommands" or f == "comandosrp" then
		P.Send(ply, "rp_drawer", {})
		return true
	end
	local cmd = alias[f]
	if not cmd then return false end
	-- a real DarkRP command with the same name always wins
	if DarkRP and DarkRP.getChatCommand and DarkRP.getChatCommand(fold(name)) then return false end
	-- nothing in the text may start a second console command
	rest = tostring(rest or ""):gsub("[;\r\n]", " "):sub(1, 400)
	rest = P.Trim(rest)
	ply:ConCommand("darkrp " .. cmd .. (rest ~= "" and (" " .. rest) or ""))
	return true
end
