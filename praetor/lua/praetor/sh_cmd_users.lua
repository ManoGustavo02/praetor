-- Praetor: rank, title, tag and info commands.
local P = Praetor
local C = P.AddCommand

local function rankCheck(caller, rank)
	if not P.CanManageRank(caller, rank) then return false end
	return true
end

C({ id = "setrank", cat = "users", def = "superadmin", aliases = { "adduser", "giverank", "setgroup" },
	args = { { type = "player", single = true }, { type = "rank" }, { type = "duration", hint = "time", optional = true, default = 0 } },
	run = function(caller, t, rank, minutes)
		if not rankCheck(caller, rank) then return "err_rank_authority" end
		P.SetRankSID(caller, t[1]:SteamID64(), rank, minutes, "command")
		P.Echo(caller, minutes > 0 and "e_setrank_temp" or "e_setrank", { T = t, V = P.Ranks[rank].display, V2 = P.FormatDuration(minutes) })
	end })

C({ id = "setrankid", cat = "users", def = "superadmin", aliases = { "adduserid", "giverankid" },
	args = { { type = "offline", hint = "steamid" }, { type = "rank" }, { type = "duration", hint = "time", optional = true, default = 0 } },
	run = function(caller, who, rank, minutes)
		if not rankCheck(caller, rank) then return "err_rank_authority" end
		P.SetRankSID(caller, who.sid, rank, minutes, "command")
		P.Echo(caller, minutes > 0 and "e_setrank_temp" or "e_setrank", { T = { who.name }, V = P.Ranks[rank].display, V2 = P.FormatDuration(minutes) })
	end })

C({ id = "removerank", cat = "users", def = "superadmin", aliases = { "removeuser", "demoterank" },
	args = { { type = "offline", hint = "player / steamid" } },
	run = function(caller, who)
		P.SetRankSID(caller, who.sid, "user", 0, "command")
		P.Echo(caller, "e_removerank", { T = { IsValid(who.ply) and who.ply or who.name } })
	end })

C({ id = "settitle", cat = "users", def = "moderator", perm = "manage_titles",
	args = { { type = "offline", hint = "player / steamid" }, { type = "text", hint = "title", max = 32 } },
	run = function(caller, who, text)
		P.SetTitleSID(who.sid, { text = text, c1 = { r = 232, g = 194, b = 122 }, fx = "none" }, caller)
		P.Echo(caller, "e_settitle", { T = { IsValid(who.ply) and who.ply or who.name }, V = text })
	end })

C({ id = "cleartitle", cat = "users", def = "moderator", perm = "manage_titles",
	args = { { type = "offline", hint = "player / steamid" } },
	run = function(caller, who)
		P.SetTitleSID(who.sid, nil, caller)
		P.Echo(caller, "e_cleartitle", { T = { IsValid(who.ply) and who.ply or who.name } })
	end })

-- settag bob "King of the Hill" ff8800 ff2200 shine
C({ id = "settag", cat = "users", def = "admin", perm = "manage_tags",
	args = {
		{ type = "offline", hint = "player / steamid" },
		{ type = "text", hint = "tag", rest = false, max = 24 },
		{ type = "text", hint = "#color", optional = true, default = "", rest = false },
		{ type = "text", hint = "#color2", optional = true, default = "", rest = false },
		{ type = "text", hint = "effect", optional = true, default = "none", rest = false },
	},
	run = function(caller, who, text, c1, c2, fx)
		local function hex(h)
			h = tostring(h or ""):gsub("#", "")
			if not h:match("^%x%x%x%x%x%x$") then return nil end
			return { r = tonumber(h:sub(1, 2), 16), g = tonumber(h:sub(3, 4), 16), b = tonumber(h:sub(5, 6), 16) }
		end
		local style = P.CleanStyle({ text = text, c1 = hex(c1) or { r = 237, g = 228, b = 211 }, c2 = hex(c2), fx = fx })
		if not style then return "err_missing" end
		P.SetTagSID(who.sid, style, caller)
		P.Echo(caller, "e_settag", { T = { IsValid(who.ply) and who.ply or who.name }, V = style.text })
	end })

C({ id = "cleartag", cat = "users", def = "admin", perm = "manage_tags",
	args = { { type = "offline", hint = "player / steamid" } },
	run = function(caller, who)
		P.SetTagSID(who.sid, nil, caller)
		P.Echo(caller, "e_cleartag", { T = { IsValid(who.ply) and who.ply or who.name } })
	end })

C({ id = "duty", cat = "users", def = "moderator", aliases = { "onduty", "staffmode" },
	args = {},
	run = function(caller)
		if not IsValid(caller) then return "err_console" end
		local on = not caller:GetNW2Bool("pr_duty", false)
		caller:SetNW2Bool("pr_duty", on)
		P.Echo(caller, on and "e_duty_on" or "e_duty_off", {})
		P.Log("cmd", on and "l_duty_on" or "l_duty_off", { A = P.LogPly(caller) }, { caller })
	end })

C({ id = "who", cat = "users", def = "user", aliases = { "staff", "online" },
	args = {},
	run = function(caller)
		if not IsValid(caller) then
			for _, p in ipairs(player.GetAll()) do print(string.format("%-28s %-14s %s", p:Nick(), p:GetUserGroup(), p:SteamID())) end
			return
		end
		P.Send(caller, "open_menu", { tab = "players" })
	end })

C({ id = "playtime", cat = "users", def = "user", aliases = { "time", "hours" },
	args = { { type = "player", single = true, self_default = true, optional = true, higher = true } },
	run = function(caller, t)
		P.Notify(caller, "n_playtime", { S = t[1]:Nick(), V = P.FormatHours(P.PlayTime(t[1])) })
		local nx = P.NextPromotion(t[1]:GetUserGroup())
		if nx and t[1]:GetNW2Int("pr_rexp", 0) == 0 then
			local left = nx.hours * 3600 - P.PlayTime(t[1])
			if left > 0 then
				P.Notify(caller, "n_next_promo", { V = P.Ranks[nx.rank] and P.Ranks[nx.rank].display or nx.rank, V2 = P.FormatHours(left) })
			end
		end
	end })

C({ id = "warns", cat = "users", def = "moderator", aliases = { "warnings" },
	args = { { type = "offline", hint = "player / steamid", higher = true } },
	run = function(caller, who)
		if IsValid(caller) then P.Send(caller, "open_menu", { tab = "users", sid = who.sid }) return end
		print(who.name .. ": " .. P.WarnPoints(who.sid) .. " warning points")
	end })

C({ id = "sheet", cat = "users", def = "moderator", perm = "view_sheet", aliases = { "profile", "ficha" },
	args = { { type = "offline", hint = "player / steamid", higher = true } },
	run = function(caller, who)
		if not IsValid(caller) then return "err_console" end
		P.Send(caller, "open_menu", { tab = "users", sid = who.sid })
	end })
