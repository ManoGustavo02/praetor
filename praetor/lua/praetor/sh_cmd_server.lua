-- Praetor: server and chat commands.
local P = Praetor
local C = P.AddCommand

-- ------------------------------------------------------------------ server

C({ id = "map", cat = "server", def = "superadmin", aliases = { "changelevel" },
	args = { { type = "map", hint = "map" }, { type = "text", hint = "gamemode", optional = true, default = "", rest = false } },
	run = function(caller, map, gm)
		P.Echo(caller, "e_map", { V = map })
		timer.Simple(3, function()
			if gm ~= "" and gm:match("^[%w_]+$") then RunConsoleCommand("gamemode", gm) end
			RunConsoleCommand("changelevel", map)
		end)
	end })

C({ id = "restart", cat = "server", def = "superadmin", aliases = { "reloadmap" },
	args = {},
	run = function(caller)
		P.Echo(caller, "e_restart", {})
		timer.Simple(3, function() RunConsoleCommand("changelevel", game.GetMap()) end)
	end })

C({ id = "cleanup", cat = "server", def = "superadmin", aliases = { "cleanmap" },
	args = {},
	run = function(caller)
		game.CleanUpMap()
		P.Echo(caller, "e_cleanup", {})
	end })

C({ id = "freezeprops", cat = "server", def = "admin",
	args = {},
	run = function(caller)
		local n = 0
		for _, e in ipairs(ents.FindByClass("prop_physics*")) do
			local phys = e:GetPhysicsObject()
			if IsValid(phys) and phys:IsMoveable() then
				phys:EnableMotion(false)
				n = n + 1
			end
		end
		P.Echo(caller, "e_freezeprops", { V = n })
	end })

C({ id = "stopsound", cat = "server", def = "admin", aliases = { "stopsounds" },
	args = {},
	run = function(caller)
		for _, p in ipairs(player.GetHumans()) do p:ConCommand("stopsound") end
		P.Echo(caller, "e_stopsound", {})
	end })

-- also wipes every player spray (and the record of whose spray was where)
C({ id = "cleardecals", cat = "server", def = "admin", aliases = { "decals", "clearsprays", "limparsprays", "limparmarcas" },
	args = {},
	run = function(caller)
		for _, p in ipairs(player.GetHumans()) do p:ConCommand("r_cleardecals") end
		if P.ClearSprays then P.ClearSprays() end
		P.Echo(caller, "e_cleardecals", {})
	end })

-- rcon is limited to server owners on purpose: a compromised staff account must
-- never be able to run console commands.
C({ id = "rcon", cat = "server", def = "superadmin", owner_only = true,
	args = { { type = "text", hint = "command" } },
	run = function(caller, line)
		if IsValid(caller) and not P.IsOwner(caller) then return "err_owner_only" end
		local blocked = { "praetor_owner", "rcon_password", "sv_password", "lua_run", "lua_openscript" }
		local first = (P.SplitArgs(line)[1] or ""):lower()
		for _, b in ipairs(blocked) do
			if first == b then return "err_rcon_blocked" end
		end
		game.ConsoleCommand(line .. "\n")
		P.Log("security", "l_rcon", { A = P.LogPly(caller), V = line }, { caller })
		P.Notify(caller, "ok_done", nil, "ok")
	end })

-- ------------------------------------------------------------------ chat

C({ id = "announce", cat = "chat", def = "admin", aliases = { "csay" },
	args = { { type = "text", hint = "message" } },
	run = function(caller, msg)
		P.Send(nil, "announce", { t = msg, n = P.NameOf(caller) })
		P.Log("chat", "l_announce", { A = P.LogPly(caller), V = msg }, { caller })
	end })

C({ id = "tsay", cat = "chat", def = "admin", aliases = { "broadcast" },
	args = { { type = "text", hint = "message" } },
	run = function(caller, msg)
		P.ChatTo(nil, P.Col.bronzeL, msg)
		P.Log("chat", "l_announce", { A = P.LogPly(caller), V = msg }, { caller })
	end })

C({ id = "pm", cat = "chat", def = "user", aliases = { "psay", "msg", "whisper" },
	args = { { type = "player", single = true, higher = true, notself = true }, { type = "text", hint = "message" } },
	run = function(caller, t, msg)
		if not IsValid(caller) then return "err_console" end
		if P.IsMuted and P.IsMuted(caller) then return "err_muted" end
		local data = { from = caller:Nick(), fsid = caller:SteamID64(), to = t[1]:Nick(), tsid = t[1]:SteamID64(), m = msg }
		P.Send({ caller, t[1] }, "pm", data)
		P.Log("chat", "l_pm", { A = P.LogPly(caller), T = P.LogPly(t[1]), V = msg }, { caller, t[1] })
	end })

C({ id = "asay", cat = "chat", def = "user", aliases = { "adminchat", "staffchat" },
	args = { { type = "text", hint = "message" } },
	run = function(caller, msg)
		if not IsValid(caller) then return end
		local to = P.WithPerm("adminchat")
		if not table.HasValue(to, caller) then to[#to + 1] = caller end
		P.Send(to, "adminchat", { n = caller:Nick(), sid = caller:SteamID64(), m = msg, staff = P.Has(caller, "adminchat") and 1 or nil })
		P.Log("chat", "l_adminchat", { A = P.LogPly(caller), V = msg }, { caller })
	end })

C({ id = "clearchat", cat = "chat", def = "admin",
	args = {},
	run = function(caller)
		P.Send(nil, "clearchat", {})
		P.Echo(caller, "e_clearchat", {})
	end })

C({ id = "vote", cat = "chat", def = "admin",
	args = { { type = "text", hint = "question" } },
	run = function(caller, q)
		-- "Question? | option 1 | option 2" ; without options it is a yes / no vote
		local parts = string.Explode("|", q)
		local question = P.Trim(parts[1])
		local opts = {}
		for i = 2, math.min(#parts, 7) do
			local o = P.Trim(P.Str(parts[i], 40))
			if o ~= "" then opts[#opts + 1] = o end
		end
		if question == "" then return "err_missing" end
		if not P.StartVote(caller, P.Str(question, 120), opts) then return "err_vote_running" end
	end })

C({ id = "mapvote", cat = "chat", def = "admin", aliases = { "votemap" },
	args = { { type = "number", hint = "seconds", optional = true, default = 0 } },
	run = function(caller, secs)
		local ok, err = P.StartMapVote(caller, (tonumber(secs) or 0) > 0 and secs or nil)
		if not ok then return err or "err_vote_running" end
	end })

C({ id = "stopvote", cat = "chat", def = "moderator", aliases = { "cancelvote" },
	args = {},
	run = function(caller)
		if not P.StopVote(caller) then return "err_no_vote" end
	end })

-- scheduled restart (times are set in the Restart tab)
C({ id = "restartin", cat = "server", def = "superadmin", perm = "manage_restart", aliases = { "reiniciar" },
	args = { { type = "number", hint = "minutes" } },
	run = function(caller, min)
		min = math.floor(tonumber(min) or -1)
		if min < 0 or min > 1440 then return "err_rst_min" end
		P.RestartIn(caller, min)
		P.Echo(caller, "e_restartin", { V = min })
	end })

C({ id = "cancelrestart", cat = "server", def = "superadmin", perm = "manage_restart", aliases = { "stoprestart" },
	args = {},
	run = function(caller)
		if not P.RestartCancel(caller) then return "err_rst_none" end
		P.Echo(caller, "e_cancelrestart", {})
	end })
