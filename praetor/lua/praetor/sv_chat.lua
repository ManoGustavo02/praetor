-- Praetor: chat extras for the Praetor chat box.
--  * replies: the box sends the message with the reply it answers; the reply is
--    shown to everyone right before the message itself goes through ply:Say, so
--    every PlayerSay hook (commands, AutoMod, DarkRP...) still runs as usual.
--  * staff can delete a message for everyone (permission chat_delete).
local P = Praetor

P.RegisterPerm("chat_delete", "chat", "moderator")

local MAX_CHARS = 126

-- staff tab of the chat box: same as "@ message"
local function staffSay(ply, text)
	if not P.Has(ply, "adminchat") then return end
	local to = P.WithPerm("adminchat")
	P.Send(to, "adminchat", { n = ply:Nick(), sid = ply:SteamID64(), m = text, staff = 1 })
	P.Log("chat", "l_adminchat", { A = P.LogPly(ply), V = text }, { ply })
end

-- "Nearby" tab: only players within chat_local_dist units read it
local function localSay(ply, text)
	local dist = P.Setting("chat_local_dist") or 0
	if dist <= 0 then ply:Say(text, false) return end
	if P.AutoModBlock and P.AutoModBlock(ply, text) then return end
	if P.ChatBlocked and P.ChatBlocked(ply, text) then return end
	local pos = ply:GetPos()
	local d2 = dist * dist
	local to = {}
	for _, p in ipairs(player.GetHumans()) do
		if p == ply or p:GetPos():DistToSqr(pos) <= d2 then to[#to + 1] = p end
	end
	P.Send(to, "chat_local", { sid = ply:SteamID64(), m = text })
	P.Log("chat", "l_chat_local", { A = P.LogPly(ply), V = text }, { ply })
	hook.Run("Praetor.LocalChat", ply, text, to)
end

P.Receive("chat_say", { rate = 3, max = 2048 }, function(ply, data)
	local text = isstring(data.text) and P.Str(data.text, MAX_CHARS) or ""
	if P.Trim(text) == "" then return end
	local first = text:sub(1, 1)
	local isCommand = first == "!" or first == "/"
	if not isCommand and data.ch == "staff" then staffSay(ply, P.Trim(text)) return end
	if not isCommand and data.ch == "local" then localSay(ply, P.Trim(text)) return end
	local teamOnly = data.team == true
	local to = isstring(data.to) and data.to:match("^%d+$") and data.to or nil
	-- a message the AutoMod will block does not announce a reply either
	if to and P.Setting("automod") and not P.AutoModSkips(ply) and P.AutoModScan(text) then to = nil end
	if to then
		local quote = P.Str(isstring(data.q) and data.q or "", 80)
		local name = P.Str(isstring(data.n) and data.n or "", 32)
		-- same people that will see the message (team chat stays in the team)
		local targets = {}
		for _, p in ipairs(player.GetHumans()) do
			if not teamOnly or p:Team() == ply:Team() then targets[#targets + 1] = p end
		end
		P.Send(targets, "chat_reply", { from = ply:SteamID64(), to = to, n = name, q = quote })
	end
	ply:Say(text, teamOnly)
end)

P.Receive("chat_delete", { perm = "chat_delete", rate = 2, max = 1024 }, function(ply, data)
	local sid = isstring(data.sid) and data.sid:match("^%d+$") and data.sid or nil
	local text = isstring(data.text) and P.Str(data.text, MAX_CHARS + 8) or nil
	if not sid or not text then return end
	local target = player.GetBySteamID64(sid)
	if IsValid(target) and target ~= ply and not P.CanTarget(ply, target) then
		P.Notify(ply, "err_authority", { S = target:Nick() }, "warn")
		return
	end
	P.Send(nil, "chat_deleted", { sid = sid, text = text, by = ply:Nick() })
	P.Log("chat", "l_chat_delete", { A = P.LogPly(ply), T = IsValid(target) and P.LogPly(target) or { s = sid, n = sid }, V = text }, { ply, target })
end)
