-- Praetor: DarkRP job blacklist / whitelist.
--  blacklist: the player can't take that job (temporary or permanent, "*" = every job but the default one)
--  whitelist: jobs marked as "whitelist only" can only be taken by players on their whitelist
local P = Praetor

P.WhitelistJobs = P.WhitelistJobs or {}
P.JobCache = P.JobCache or {}

function P.LoadJobConfig()
	P.WhitelistJobs = {}
	for cmd, v in pairs(P.DB.Get("wljobs", {})) do
		if v == true and isstring(cmd) then P.WhitelistJobs[cmd] = true end
	end
end

local function loadEntries(sid)
	local c = { bl = {}, wl = {} }
	local now = os.time()
	for _, r in ipairs(P.DB.Query("SELECT job, kind, expires FROM praetor_jobs WHERE sid = ?", sid) or {}) do
		local exp = tonumber(r.expires) or 0
		if r.kind == "wl" then c.wl[r.job] = true
		elseif r.kind == "bl" and (exp == 0 or exp > now) then c.bl[r.job] = exp end
	end
	P.JobCache[sid] = c
	return c
end

hook.Add("Praetor.UserLoaded", "Praetor.Jobs", function(ply) loadEntries(ply:SteamID64()) end)
hook.Add("PlayerDisconnected", "Praetor.Jobs", function(ply) P.JobCache[ply:SteamID64() or ""] = nil end)

local function blocked(c, cmd)
	local now = os.time()
	for _, key in ipairs({ cmd, "*" }) do
		local exp = c.bl[key]
		if exp and (exp == 0 or exp > now) then return true, exp end
	end
	return false
end

function P.IsJobBlacklisted(ply, cmd)
	local c = P.JobCache[ply:SteamID64() or ""] or loadEntries(ply:SteamID64())
	return blocked(c, cmd)
end

hook.Add("playerCanChangeTeam", "Praetor.Jobs", function(ply, t, force)
	if force or ply:IsBot() then return end
	local job = RPExtraTeams and RPExtraTeams[t]
	if not job or not job.command then return end
	if t == (GAMEMODE.DefaultTeam or TEAM_CITIZEN) then return end
	if P.IsOwner(ply) then return end
	local c = P.JobCache[ply:SteamID64()] or loadEntries(ply:SteamID64())
	local bl, exp = blocked(c, job.command)
	if bl then
		local left = exp == 0 and "" or (" (" .. P.FormatDuration(math.ceil((exp - os.time()) / 60)) .. ")")
		return false, "Blacklisted from this job / Blacklist nesta profissão" .. left
	end
	if P.WhitelistJobs[job.command] and not c.wl[job.command] and not P.Has(ply, "manage_jobs") then
		return false, "Whitelist only / Só com whitelist"
	end
end)

local function kickOut(ply, cmd)
	if not P.Setting("rp_blacklist_kick") then return end
	local job = RPExtraTeams and RPExtraTeams[ply:Team()]
	if job and (cmd == "*" or job.command == cmd) and ply:Team() ~= (GAMEMODE.DefaultTeam or TEAM_CITIZEN) then
		ply:changeTeam(GAMEMODE.DefaultTeam or TEAM_CITIZEN or 1, true, true)
	end
end

function P.AddJobEntry(sid, name, cmd, kind, minutes, reason, actor)
	minutes = math.max(0, math.floor(tonumber(minutes) or 0))
	local exp = minutes > 0 and (os.time() + minutes * 60) or 0
	P.EnsureUser(sid, name)
	P.DB.Query("DELETE FROM praetor_jobs WHERE sid = ? AND job = ? AND kind = ?", sid, cmd, kind)
	P.DB.Query("INSERT INTO praetor_jobs (sid, name, job, kind, reason, admin, admin_sid, created, expires) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sid, P.Str(name or "", 64), cmd, kind, P.Str(reason or "", 200), P.NameOf(actor), IsValid(actor) and actor:SteamID64() or "", os.time(), exp)
	loadEntries(sid)
	local ply = P.BySID(sid)
	if kind == "bl" and IsValid(ply) then kickOut(ply, cmd) end
	P.Log("rp", kind == "bl" and "l_jobban" or "l_whitelist", { A = P.LogPly(actor), T = { n = name or sid, s = sid }, V = cmd, V2 = minutes > 0 and P.FormatDuration(minutes) or nil }, { actor, sid })
end

function P.RemoveJobEntry(sid, cmd, kind, actor)
	local n = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_jobs WHERE sid = ? AND job = ? AND kind = ?", sid, cmd, kind)) or 0
	if n == 0 then return false end
	P.DB.Query("DELETE FROM praetor_jobs WHERE sid = ? AND job = ? AND kind = ?", sid, cmd, kind)
	loadEntries(sid)
	P.Log("rp", kind == "bl" and "l_unjobban" or "l_unwhitelist", { A = P.LogPly(actor), T = { n = P.KnownName(sid) or sid, s = sid }, V = cmd }, { actor, sid })
	return true
end

-- ------------------------------------------------------------------ jobs tab

P.Receive("jobs_info", { perm = "manage_jobs", rate = 2 }, function(ply, data)
	local jobs = {}
	if P.IsDarkRP() then
		for i, j in pairs(RPExtraTeams) do
			jobs[#jobs + 1] = { i = i, name = j.name, cmd = j.command, col = j.color and { r = j.color.r, g = j.color.g, b = j.color.b }, cat = j.category, wl = P.WhitelistJobs[j.command] and 1 or nil, n = #team.GetPlayers(i) }
		end
	end
	local where = "1=1"
	local params = {}
	local sid = P.ToSID64(data.q or "")
	if sid then where = "sid = ?" params[1] = sid
	elseif isstring(data.job) and data.job ~= "" then where = "job = ?" params[1] = data.job end
	local rows = P.DB.Query("SELECT * FROM praetor_jobs WHERE " .. where .. " AND (expires = 0 OR expires > " .. os.time() .. ") ORDER BY id DESC LIMIT 200", unpack(params)) or {}
	P.Send(ply, "jobs_info", { jobs = jobs, rows = rows, rp = P.IsDarkRP() })
end)

P.Receive("jobs_wlflag", { perm = "manage_jobs", rate = 4 }, function(ply, data)
	local cmd = isstring(data.cmd) and data.cmd or ""
	if not P.JobByCommand(cmd) then return end
	P.WhitelistJobs[cmd] = data.on == true or nil
	P.DB.Set("wljobs", P.WhitelistJobs)
	P.Log("rp", "l_wlflag", { A = P.LogPly(ply), V = cmd, V2 = data.on and "on" or "off" }, { ply })
	P.SyncAll()
end)

P.Receive("jobs_add", { perm = "manage_jobs", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then P.Notify(ply, "err_steamid") return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	local cmd = isstring(data.cmd) and data.cmd or ""
	if cmd ~= "*" and not P.JobByCommand(cmd) then P.Notify(ply, "err_job", { S = cmd }) return end
	local kind = data.kind == "wl" and "wl" or "bl"
	P.AddJobEntry(sid, P.KnownName(sid) or P.SID32(sid), cmd, kind, data.min, data.reason, ply)
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("jobs_remove", { perm = "manage_jobs", rate = 4 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = P.DB.Row("SELECT * FROM praetor_jobs WHERE id = ?", id)
	if not row then return end
	if not P.CanTargetSID(ply, row.sid) then return end
	P.RemoveJobEntry(row.sid, row.job, row.kind, ply)
	P.Notify(ply, "ok_removed", nil, "ok")
end)

-- ------------------------------------------------------------------ wanted list (F4 City tab)
-- DarkRP keeps who is wanted and why. The list in the City tab also shows who
-- asked for it and the time left, so the server keeps those two on the player.
hook.Add("playerWanted", "Praetor.WantedInfo", function(ply, actor, reason)
	if not IsValid(ply) then return end
	ply:SetNW2String("pr_wantedby", IsValid(actor) and actor:IsPlayer() and actor:Nick() or "")
	ply:SetNW2Float("pr_wantedat", CurTime())
	ply:SetNW2Float("pr_wantedend", 0)
	-- DarkRP starts its timer right after this hook: read the exact time from it
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		local left = timer.TimeLeft(ply:SteamID64() .. " wantedtimer")
		if not left then
			local cfg = GAMEMODE and GAMEMODE.Config
			left = cfg and tonumber(cfg.wantedtime) or 0
		end
		ply:SetNW2Float("pr_wantedend", left > 0 and CurTime() + left or 0)
	end)
end)
hook.Add("playerUnWanted", "Praetor.WantedInfo", function(ply)
	if not IsValid(ply) then return end
	ply:SetNW2String("pr_wantedby", "")
	ply:SetNW2Float("pr_wantedend", 0)
end)
