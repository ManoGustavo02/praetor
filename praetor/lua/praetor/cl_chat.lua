-- Praetor: how player messages look in chat.
--   praetor : Praetor's own chat box (avatars, animated tags, images)
--   tags    : any other chat box (Simple Chat, aTags, the default one...) gets
--             the rank / tag colours through chat.AddText, letter by letter
--   off     : Praetor does not touch the chat
local P = Praetor
local UI = P.UI
local C = UI.C

local useBox = CreateClientConVar("praetor_chatbox", "1", true, false, "Use the Praetor chat box (0 = keep the default / other chat addon)")
P.ChatBoxVar = useBox

-- Known chat box addons: when one is running Praetor only adds colours.
local function otherChatBox()
	return (SChat ~= nil) or (atlaschat ~= nil) or (eChat ~= nil) or (HFChat ~= nil) or (LOUNGE_CHAT ~= nil) or (XeninChat ~= nil)
end

function P.ChatMode()
	local mode = P.Setting("chat_mode") or "praetor"
	if mode == "praetor" and (not useBox:GetBool() or otherChatBox()) then return "tags" end
	return mode
end

-- replies sent through the Praetor chat box arrive right before their message
P.ChatReplies = P.ChatReplies or {}
P.On("chat_reply", function(d)
	if isstring(d.from) then P.ChatReplies[d.from] = { to = d.to, n = d.n, q = d.q, t = RealTime() } end
end)

local function rankStyleFor(ply)
	if not P.Setting("chat_rank_tag") then return nil end
	local r = P.RankOf(ply)
	if not r or r.name == "user" then return nil end
	local style = r.style or { text = r.display or r.name, c1 = { r = 200, g = 200, b = 200 } }
	return style, r.icon
end

-- channel tags: "local" (players close by) and "staff" (staff chat)
local CHAN = {
	["local"] = { key = "chat_chan_local", col = function() return C.sky end },
	staff = { key = "chat_chan_staff", col = function() return C.crimsonL end },
}

-- one chat line from a player, the same way for normal, team, nearby and staff messages
function P.ChatPlayerLine(ply, text, teamChat, dead, prefixText, col1, col2, chan)
	local mode = P.ChatMode()
	local parts = {}
	local meta = { text = text, team = teamChat, dead = dead, chan = CHAN[chan or ""] and chan or nil }
	if meta.chan then
		local ch = CHAN[meta.chan]
		parts[#parts + 1] = ch.col()
		parts[#parts + 1] = "(" .. P.L(ch.key) .. ") "
	end
	if dead then
		parts[#parts + 1] = C.crimsonL
		parts[#parts + 1] = "*" .. P.L("chat_dead") .. "* "
	end
	if teamChat then
		parts[#parts + 1] = C.laurel
		parts[#parts + 1] = "(" .. P.L("chat_team") .. ") "
	end

	local nameCol, name
	local textCol = color_white
	if IsValid(ply) then
		local rank, icon = rankStyleFor(ply)
		local tag = ply:GetPraetorTag()
		if rank then P.StyleChatParts(rank, parts, "[", "] ") end
		if tag then P.StyleChatParts(tag, parts, "[", "] ") end
		meta.ply, meta.rank, meta.rankIcon, meta.tag = ply, rank, icon, tag
		local sid = ply:SteamID64()
		local rep = sid and P.ChatReplies[sid]
		if rep then
			if RealTime() - rep.t < 3 then meta.reply = rep end
			P.ChatReplies[sid] = nil
		end
		name = prefixText or ply:Nick()
		nameCol = (prefixText and col1) or team.GetColor(ply:Team())
		local r = P.RankOf(ply)
		if r and r.chat_color then textCol = P.ReadColor(r.chat_color, color_white) end
	else
		name = prefixText or "Console"
		nameCol = (prefixText and col1) or C.bronzeL
	end
	if col2 then textCol = col2 end
	meta.name, meta.nameCol, meta.textCol = name, nameCol, textCol

	parts[#parts + 1] = nameCol
	parts[#parts + 1] = name
	parts[#parts + 1] = color_white
	parts[#parts + 1] = ": "
	parts[#parts + 1] = textCol
	-- other chat boxes don't draw the reply line: at least say who it answers
	if meta.reply and mode ~= "praetor" and meta.reply.n ~= "" then
		parts[#parts + 1] = C.muted
		parts[#parts + 1] = "@" .. meta.reply.n .. " "
		parts[#parts + 1] = textCol
	end
	parts[#parts + 1] = text

	P.ChatMeta = meta
	chat.AddText(unpack(parts))
	P.ChatMeta = nil
	return true
end

hook.Add("OnPlayerChat", "Praetor.Chat", function(ply, text, teamChat, dead, prefixText, col1, col2)
	local mode = P.ChatMode()
	if mode == "off" or engine.ActiveGamemode() == "murder" then return end
	return P.ChatPlayerLine(ply, text, teamChat, dead, prefixText, col1, col2)
end)

-- messages only the players close by get
P.On("chat_local", function(d)
	local ply = isstring(d.sid) and player.GetBySteamID64(d.sid)
	if not IsValid(ply) or not isstring(d.m) then return end
	if P.ChatMode() == "off" then
		chat.AddText(C.sky, "(" .. P.L("chat_chan_local") .. ") ", team.GetColor(ply:Team()), ply:Nick(), color_white, ": " .. d.m)
		return
	end
	P.ChatPlayerLine(ply, d.m, false, not ply:Alive(), nil, nil, nil, "local")
end)
