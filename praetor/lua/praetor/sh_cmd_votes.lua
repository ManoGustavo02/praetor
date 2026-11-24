-- Praetor: votes started by players.
--  !votekick <player> [reason]     !voteban <player> [reason]
--  !votemute <player> [reason]     !voteclearprops <player> [reason]
--  !votecleanup                    !votefreeze
-- Staff and owners can't be voted on. Settings: pv_* (Settings > Player votes).
local P = Praetor
local C = P.AddCommand

local function target(act)
	return function(caller, t, reason)
		local ply = t and t[1]
		if not IsValid(ply) then return "err_no_target" end
		local ok, err, args = P.StartPlayerVote(caller, act, ply, reason)
		if not ok then
			if err then P.Notify(caller, err, args) end
			return
		end
	end
end

local function plain(act)
	return function(caller)
		local ok, err, args = P.StartPlayerVote(caller, act)
		if not ok then
			if err then P.Notify(caller, err, args) end
			return
		end
	end
end

local PLY = { type = "player", single = true, notself = true }
local WHY = { type = "text", hint = "reason", optional = true, default = "" }

C({ id = "votekick", cat = "chat", def = "user", aliases = { "vkick" }, args = { PLY, WHY }, run = target("kick") })
C({ id = "voteban", cat = "chat", def = "user", aliases = { "vban" }, args = { PLY, WHY }, run = target("ban") })
C({ id = "votemute", cat = "chat", def = "user", aliases = { "vmute" }, args = { PLY, WHY }, run = target("mute") })
C({ id = "voteclearprops", cat = "chat", def = "user", aliases = { "vclearprops" }, args = { PLY, WHY }, run = target("clearprops") })
C({ id = "votecleanup", cat = "chat", def = "user", aliases = { "vcleanup", "votecleanmap" }, args = {}, run = plain("cleanup") })
C({ id = "votefreeze", cat = "chat", def = "user", aliases = { "vfreeze" }, args = {}, run = plain("freeze") })
