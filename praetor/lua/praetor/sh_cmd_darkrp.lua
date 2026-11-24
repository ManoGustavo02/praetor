-- Praetor: DarkRP commands (only work when the gamemode is DarkRP or a derive).
local P = Praetor
local C = P.AddCommand

local function rp() return P.IsDarkRP() end

C({ id = "setjob", cat = "darkrp", def = "admin", aliases = { "forcejob" },
	args = { { type = "player" }, { type = "job", hint = "job" } },
	run = function(caller, t, cmd)
		if not rp() then return "err_no_darkrp" end
		local job, idx = P.JobByCommand(cmd)
		for _, p in ipairs(t) do p:changeTeam(idx, true, true) end
		P.Echo(caller, "e_setjob", { T = t, V = job.name })
	end })

C({ id = "jobban", cat = "darkrp", def = "admin", aliases = { "blacklist", "teamban" }, preset = true,
	args = { { type = "offline", hint = "player / steamid" }, { type = "job", hint = "job" }, { type = "duration", hint = "time", optional = true, default = 0 }, { type = "text", hint = "reason", optional = true, default = "" } },
	run = function(caller, who, cmd, minutes, reason)
		if not rp() then return "err_no_darkrp" end
		P.AddJobEntry(who.sid, who.name, cmd, "bl", minutes, reason, caller)
		local job = P.JobByCommand(cmd)
		P.Echo(caller, minutes > 0 and "e_jobban_t" or "e_jobban", { T = { IsValid(who.ply) and who.ply or who.name }, V = job and job.name or cmd, V2 = P.FormatDuration(minutes) })
	end })

C({ id = "unjobban", cat = "darkrp", def = "admin", aliases = { "unblacklist", "teamunban" },
	args = { { type = "offline", hint = "player / steamid" }, { type = "job", hint = "job" } },
	run = function(caller, who, cmd)
		if not rp() then return "err_no_darkrp" end
		if not P.RemoveJobEntry(who.sid, cmd, "bl", caller) then return "err_no_entry" end
		local job = P.JobByCommand(cmd)
		P.Echo(caller, "e_unjobban", { T = { IsValid(who.ply) and who.ply or who.name }, V = job and job.name or cmd })
	end })

C({ id = "whitelist", cat = "darkrp", def = "admin", aliases = { "jobwhitelist", "wl" },
	args = { { type = "offline", hint = "player / steamid" }, { type = "job", hint = "job" } },
	run = function(caller, who, cmd)
		if not rp() then return "err_no_darkrp" end
		P.AddJobEntry(who.sid, who.name, cmd, "wl", 0, "", caller)
		local job = P.JobByCommand(cmd)
		P.Echo(caller, "e_whitelist", { T = { IsValid(who.ply) and who.ply or who.name }, V = job and job.name or cmd })
	end })

C({ id = "unwhitelist", cat = "darkrp", def = "admin", aliases = { "unwl" },
	args = { { type = "offline", hint = "player / steamid" }, { type = "job", hint = "job" } },
	run = function(caller, who, cmd)
		if not rp() then return "err_no_darkrp" end
		if not P.RemoveJobEntry(who.sid, cmd, "wl", caller) then return "err_no_entry" end
		local job = P.JobByCommand(cmd)
		P.Echo(caller, "e_unwhitelist", { T = { IsValid(who.ply) and who.ply or who.name }, V = job and job.name or cmd })
	end })

C({ id = "rpdemote", cat = "darkrp", def = "moderator", aliases = { "forcedemote" }, preset = true,
	args = { { type = "player" } },
	run = function(caller, t)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do p:changeTeam(GAMEMODE.DefaultTeam or TEAM_CITIZEN or 1, true, true) end
		P.Echo(caller, "e_rpdemote", { T = t })
	end })

C({ id = "setmoney", cat = "darkrp", def = "superadmin",
	args = { { type = "player", single = true }, { type = "number", hint = "amount", min = 0, max = 1e12 } },
	run = function(caller, t, n)
		if not rp() then return "err_no_darkrp" end
		local p = t[1]
		p:addMoney(n - (p:getDarkRPVar("money") or 0))
		P.Echo(caller, "e_setmoney", { T = t, V = DarkRP.formatMoney and DarkRP.formatMoney(n) or n })
	end })

C({ id = "addmoney", cat = "darkrp", def = "superadmin", aliases = { "givemoney" },
	args = { { type = "player" }, { type = "number", hint = "amount", min = -1e12, max = 1e12 } },
	run = function(caller, t, n)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do p:addMoney(n) end
		P.Echo(caller, "e_addmoney", { T = t, V = DarkRP.formatMoney and DarkRP.formatMoney(n) or n })
	end })

C({ id = "rpname", cat = "darkrp", def = "admin", aliases = { "setname", "forcename" },
	args = { { type = "player", single = true }, { type = "text", hint = "name", max = 32 } },
	run = function(caller, t, name)
		if not rp() then return "err_no_darkrp" end
		local old = t[1]:Nick()
		if DarkRP.storeRPName then DarkRP.storeRPName(t[1], name) end
		t[1]:setDarkRPVar("rpname", name)
		P.Echo(caller, "e_rpname", { T = { old }, V = name })
	end })

C({ id = "arrest", cat = "darkrp", def = "admin", aliases = { "jailrp" },
	args = { { type = "player" }, { type = "number", hint = "seconds", min = 0, max = 86400, optional = true, default = 0 } },
	run = function(caller, t, secs)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do
			if p:isArrested() then p:unArrest() end
			p:arrest(secs > 0 and secs or nil, IsValid(caller) and caller or nil)
		end
		P.Echo(caller, "e_arrest", { T = t })
	end })

C({ id = "unarrest", cat = "darkrp", def = "admin",
	args = { { type = "player" } },
	run = function(caller, t)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do if p:isArrested() then p:unArrest(IsValid(caller) and caller or nil) end end
		P.Echo(caller, "e_unarrest", { T = t })
	end })

C({ id = "wanted", cat = "darkrp", def = "admin", aliases = { "setwanted" },
	args = { { type = "player" }, { type = "text", hint = "reason", optional = true, default = "Admin" } },
	run = function(caller, t, reason)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do p:wanted(IsValid(caller) and caller or nil, reason, 300) end
		P.Echo(caller, "e_wanted", { T = t, V = reason })
	end })

C({ id = "unwanted", cat = "darkrp", def = "admin",
	args = { { type = "player" } },
	run = function(caller, t)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do if p:isWanted() then p:unWanted(IsValid(caller) and caller or nil) end end
		P.Echo(caller, "e_unwanted", { T = t })
	end })

C({ id = "license", cat = "darkrp", def = "admin", aliases = { "givelicense", "gunlicense" },
	args = { { type = "player" } },
	run = function(caller, t)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do p:setDarkRPVar("HasGunlicense", true) end
		P.Echo(caller, "e_license", { T = t })
	end })

C({ id = "unlicense", cat = "darkrp", def = "admin", aliases = { "takelicense" },
	args = { { type = "player" } },
	run = function(caller, t)
		if not rp() then return "err_no_darkrp" end
		for _, p in ipairs(t) do p:setDarkRPVar("HasGunlicense", nil) end
		P.Echo(caller, "e_unlicense", { T = t })
	end })
