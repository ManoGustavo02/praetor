-- Praetor: players (load/save, rank assignment, temp ranks, play time,
-- auto promotion, AFK, user permission overrides, player sheet).
local P = Praetor

P.NameCache = P.NameCache or {}
P.UserRows = P.UserRows or {}

function P.KnownName(sid)
	if P.NameCache[sid] then return P.NameCache[sid] end
	local n = P.DB.Value("SELECT name FROM praetor_users WHERE sid = ?", sid)
	if n then P.NameCache[sid] = n end
	return n
end

local function decode(s, def)
	if not s or s == "" or s == "NULL" then return def end
	return util.JSONToTable(s) or def
end

function P.UserRow(sid)
	return P.DB.Row("SELECT * FROM praetor_users WHERE sid = ?", sid)
end

-- Makes sure a row exists for an offline SteamID (rank changes, tags, bans...).
function P.EnsureUser(sid, name)
	local row = P.UserRow(sid)
	if row then return row end
	P.DB.Query("INSERT INTO praetor_users (sid, name, rank, first, last) VALUES (?, ?, 'user', 0, 0)", sid, P.Str(name or "", 64))
	return P.UserRow(sid)
end

-- Authority of a SteamID even when that player is offline.
function P.AuthorityOfSID(sid)
	if P.Owners[sid] then return P.OWNER_AUTHORITY, true end
	local online = P.BySID(sid)
	if IsValid(online) then return P.Authority(online), P.IsOwner(online) end
	local rank = P.DB.Value("SELECT rank FROM praetor_users WHERE sid = ?", sid) or "user"
	local r = P.Ranks[rank]
	return r and r.immunity or 0, false
end

function P.CanTargetSID(actor, sid)
	if not IsValid(actor) then return true end
	if actor:SteamID64() == sid then return true end
	local auth, owner = P.AuthorityOfSID(sid)
	return P.CanTargetAuthority(actor, auth, owner)
end

-- ------------------------------------------------------------------ rank assignment

function P.ApplyRank(ply, rank, expires)
	if not IsValid(ply) then return end
	local old = ply:GetUserGroup()
	if not P.Ranks[rank] then rank = "user" end
	P.ApplyUserGroup(ply, rank)
	ply:SetNW2Int("pr_rexp", expires or 0)
	ply:SetNW2Bool("pr_owner", P.IsOwner(ply))
	if old ~= rank then
		if CAMI then CAMI.SignalUserGroupChanged(ply, old, rank, "Praetor") end
		hook.Run("Praetor.RankChanged", ply, rank, old, expires or 0)
	end
end

-- actor: who asked (nil = system). minutes: 0 = permanent.
function P.SetRankSID(actor, sid, rank, minutes, src)
	if not P.Ranks[rank] then return false, "err_rank" end
	local row = P.EnsureUser(sid)
	local prev = row and row.rank or "user"
	minutes = math.max(0, math.floor(tonumber(minutes) or 0))
	local exp = minutes > 0 and (os.time() + minutes * 60) or 0
	local back = minutes > 0 and prev or nil
	if minutes > 0 and row and tonumber(row.rank_exp) and tonumber(row.rank_exp) > 0 and row.rank_prev and row.rank_prev ~= "NULL" then
		back = row.rank_prev -- stacking temp ranks keeps the original rank to return to
	end
	P.DB.Query("UPDATE praetor_users SET rank = ?, rank_exp = ?, rank_prev = ? WHERE sid = ?", rank, exp, back, sid)
	local ply = P.BySID(sid)
	if IsValid(ply) then P.ApplyRank(ply, rank, exp) end
	if CAMI and not IsValid(ply) then CAMI.SignalSteamIDUserGroupChanged(util.SteamIDFrom64(sid), prev, rank, "Praetor") end
	P.Log("rank", "l_setrank", {
		A = P.LogPly(actor), T = { n = IsValid(ply) and ply:Nick() or (P.KnownName(sid) or sid), s = sid },
		V = rank, V2 = minutes > 0 and P.FormatDuration(minutes) or nil, S = src,
	}, { actor, sid })
	return true
end

-- ------------------------------------------------------------------ join / leave

function P.LoadUser(ply)
	if ply:IsBot() then P.ApplyRank(ply, "user", 0) return end
	local sid = ply:SteamID64()
	local now = os.time()
	local row = P.UserRow(sid)
	if not row then
		P.DB.Query("INSERT INTO praetor_users (sid, name, rank, first, last, playtime) VALUES (?, ?, 'user', ?, ?, 0)", sid, P.Str(ply:Nick(), 64), now, now)
		row = P.UserRow(sid)
	else
		local names = decode(row.names, {})
		local nick = P.Str(ply:Nick(), 64)
		if names[1] ~= nick and row.name ~= nick then
			table.insert(names, 1, nick)
			while #names > 12 do table.remove(names) end
		end
		P.DB.Query("UPDATE praetor_users SET name = ?, last = ?, names = ?, first = CASE WHEN first = 0 THEN ? ELSE first END WHERE sid = ?",
			nick, now, util.TableToJSON(names), now, sid)
	end
	row = row or {}
	P.NameCache[sid] = ply:Nick()
	P.UserRows[sid] = row

	-- rank (with temp rank expiry)
	local rank = row.rank or "user"
	local exp = tonumber(row.rank_exp) or 0
	if exp > 0 and exp <= now then
		rank = (row.rank_prev and row.rank_prev ~= "NULL" and P.Ranks[row.rank_prev]) and row.rank_prev or "user"
		exp = 0
		P.DB.Query("UPDATE praetor_users SET rank = ?, rank_exp = 0, rank_prev = NULL WHERE sid = ?", rank, sid)
	end
	if not P.Ranks[rank] then rank = "user" end
	P.ApplyRank(ply, rank, exp)

	-- play time
	ply:SetNW2Int("pr_time", tonumber(row.playtime) or 0)
	ply:SetNW2Float("pr_join", CurTime())
	ply.PraetorSaved = CurTime()

	-- tag, title and extra permissions
	ply:SetNW2String("pr_title", (row.title and row.title ~= "NULL") and row.title or "")
	ply:SetNW2String("pr_tag", (row.tag and row.tag ~= "NULL") and row.tag or "")
	local perms = decode(row.perms, nil)
	P.UserPerms[sid] = perms
	P.SendPlayerExtras(ply)

	hook.Run("Praetor.UserLoaded", ply, row)
end

function P.SendPlayerExtras(ply)
	if not IsValid(ply) or ply:IsBot() then return end
	P.Send(ply, "userperms", P.UserPerms[ply:SteamID64()] or {})
end

local function savePlaytime(ply)
	if not IsValid(ply) or ply:IsBot() or not ply.PraetorSaved then return end
	local add = math.floor(CurTime() - ply:GetNW2Float("pr_join", CurTime()))
	if add <= 0 then return end
	local total = ply:GetNW2Int("pr_time", 0) + add
	P.DB.Query("UPDATE praetor_users SET playtime = ?, last = ? WHERE sid = ?", total, os.time(), ply:SteamID64())
	ply:SetNW2Int("pr_time", total)
	ply:SetNW2Float("pr_join", CurTime())
	ply.PraetorSaved = CurTime()
end
P.SavePlaytime = savePlaytime

hook.Add("PlayerInitialSpawn", "Praetor.Users", function(ply)
	if not P.Ready then
		timer.Simple(1, function() if IsValid(ply) then P.LoadUser(ply) P.SyncTo(ply) end end)
		return
	end
	P.LoadUser(ply)
	P.SyncTo(ply)
end)

hook.Add("PlayerDisconnected", "Praetor.Users", function(ply)
	savePlaytime(ply)
	if not ply:IsBot() then
		P.UserRows[ply:SteamID64() or ""] = nil
	end
end)

hook.Add("ShutDown", "Praetor.Users", function()
	for _, p in ipairs(player.GetHumans()) do savePlaytime(p) end
end)

-- every 60 s: play time, temp rank expiry, auto promotion
timer.Create("Praetor.UserTick", 60, 0, function()
	local now = os.time()
	for _, ply in ipairs(player.GetHumans()) do
		savePlaytime(ply)
		local exp = ply:GetNW2Int("pr_rexp", 0)
		if exp > 0 and exp <= now then
			local row = P.UserRow(ply:SteamID64())
			local back = row and row.rank_prev and row.rank_prev ~= "NULL" and P.Ranks[row.rank_prev] and row.rank_prev or "user"
			P.SetRankSID(nil, ply:SteamID64(), back, 0, "expired")
			P.Notify(ply, "n_rank_expired", { V = back })
		elseif exp == 0 then
			local hours = P.PlayTime(ply) / 3600
			local cur = ply:GetUserGroup()
			local best
			for name, r in pairs(P.Ranks) do
				if r.promote and not r.promote.off and r.promote.from == cur and hours >= r.promote.hours then
					if not best or (r.immunity or 0) > (P.Ranks[best].immunity or 0) then best = name end
				end
			end
			if best then
				local from = cur
				P.SetRankSID(nil, ply:SteamID64(), best, 0, "auto promotion")
				P.Notify(ply, "n_promoted", { V = P.Ranks[best].display }, "ok")
				P.Echo(nil, "e_promoted", { T = { ply }, V = P.Ranks[best].display })
				hook.Run("Praetor.AutoPromoted", ply, best, from, hours)
			end
		end
	end
end)

-- ------------------------------------------------------------------ AFK

hook.Add("StartCommand", "Praetor.AFK", function(ply, cmd)
	if ply:IsBot() then return end
	local b = cmd:GetButtons()
	local mx, my = cmd:GetMouseX(), cmd:GetMouseY()
	if b ~= (ply.PraetorLastButtons or 0) or mx ~= 0 or my ~= 0 then
		ply.PraetorLastButtons = b
		ply.PraetorActive = CurTime()
		if ply:GetNW2Bool("pr_afk") then ply:SetNW2Bool("pr_afk", false) end
	end
end)

hook.Add("PlayerSay", "Praetor.AFKChat", function(ply)
	ply.PraetorActive = CurTime()
	if ply:GetNW2Bool("pr_afk") then ply:SetNW2Bool("pr_afk", false) end
end)

timer.Create("Praetor.AFK", 5, 0, function()
	local limit = P.Setting("afk_time")
	if limit <= 0 then return end
	for _, ply in ipairs(player.GetHumans()) do
		local idle = CurTime() - (ply.PraetorActive or CurTime())
		if idle > limit and not ply:GetNW2Bool("pr_afk") then
			ply:SetNW2Float("pr_afk_since", ply.PraetorActive or CurTime())
			ply:SetNW2Bool("pr_afk", true)
		end
	end
end)

hook.Add("PlayerSpawn", "Praetor.AFKSpawn", function(ply) ply.PraetorActive = ply.PraetorActive or CurTime() end)

-- ------------------------------------------------------------------ users tab requests

P.Receive("user_search", { perm = { "manage_users", "view_sheet" }, rate = 3 }, function(ply, data)
	local q = P.Trim(P.Str(data.q, 64))
	local rows
	local sid = P.ToSID64(q)
	if sid then
		rows = P.DB.Query("SELECT sid, name, rank, last, playtime FROM praetor_users WHERE sid = ?", sid)
	elseif q == "" then
		rows = P.DB.Query("SELECT sid, name, rank, last, playtime FROM praetor_users ORDER BY last DESC LIMIT 60")
	elseif isstring(data.rank) and data.rank ~= "" then
		rows = P.DB.Query("SELECT sid, name, rank, last, playtime FROM praetor_users WHERE rank = ? ORDER BY last DESC LIMIT 80", data.rank)
	else
		local like = "%" .. q:gsub("[%%_]", "") .. "%"
		rows = P.DB.Query("SELECT sid, name, rank, last, playtime FROM praetor_users WHERE name LIKE ? OR names LIKE ? ORDER BY last DESC LIMIT 60", like, like)
	end
	if isstring(data.rank) and data.rank ~= "" and q == "" then
		rows = P.DB.Query("SELECT sid, name, rank, last, playtime FROM praetor_users WHERE rank = ? ORDER BY last DESC LIMIT 80", data.rank)
	end
	P.Send(ply, "user_search", { rows = rows or {}, q = q })
end)

P.Receive("user_sheet", { perm = { "view_sheet", "manage_users" }, rate = 3 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then return end
	local row = P.UserRow(sid) or { sid = sid, name = "?", rank = "user", playtime = 0 }
	local online = P.BySID(sid)
	local out = {
		sid = sid, row = row, online = IsValid(online),
		names = decode(row.names, {}),
		perms = decode(row.perms, {}),
		owner = P.Owners[sid] == true,
		bans = P.DB.Query("SELECT * FROM praetor_bans WHERE sid = ? ORDER BY id DESC LIMIT 20", sid) or {},
		warns = P.DB.Query("SELECT * FROM praetor_warns WHERE sid = ? ORDER BY id DESC LIMIT 30", sid) or {},
		notes = P.DB.Query("SELECT * FROM praetor_notes WHERE sid = ? ORDER BY id DESC LIMIT 30", sid) or {},
		jobs = P.DB.Query("SELECT * FROM praetor_jobs WHERE sid = ? ORDER BY id DESC LIMIT 40", sid) or {},
		logs = P.DB.Query("SELECT * FROM praetor_logs WHERE sids LIKE ? ORDER BY id DESC LIMIT 40", "%," .. sid .. ",%") or {},
	}
	if IsValid(online) then
		out.playtime = math.floor(P.PlayTime(online))
		row.playtime = out.playtime
	end
	out.warnpts = P.WarnPoints and P.WarnPoints(sid) or 0
	out.alts = P.AltsForSheet and P.AltsForSheet(ply, sid) or nil
	P.Send(ply, "user_sheet", out)
end)

P.Receive("user_setrank", { perm = { "setrank", "manage_users" }, rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	local rank = isstring(data.rank) and data.rank or ""
	if not sid or not P.Ranks[rank] then return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	if not P.CanManageRank(ply, rank) then P.Notify(ply, "err_rank_authority") return end
	local minutes = math.max(0, math.floor(tonumber(data.min) or 0))
	P.SetRankSID(ply, sid, rank, minutes, "menu")
	local target = P.BySID(sid)
	P.Echo(ply, minutes > 0 and "e_setrank_temp" or "e_setrank", {
		T = IsValid(target) and { target } or { P.KnownName(sid) or P.SID32(sid) },
		V = P.Ranks[rank].display, V2 = P.FormatDuration(minutes),
	})
end)

P.Receive("user_perms", { perm = "manage_users", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then return end
	if not P.CanTargetSID(ply, sid) or (IsValid(ply) and ply:SteamID64() == sid and not P.IsOwner(ply)) then
		P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid })
		return
	end
	local owner = P.IsOwner(ply)
	local out = { allow = {}, deny = {} }
	for _, kind in ipairs({ "allow", "deny" }) do
		if istable(data[kind]) then
			for _, perm in ipairs(data[kind]) do
				if isstring(perm) and P.Perms[perm] and (owner or P.Has(ply, perm)) then out[kind][perm] = true end
			end
		end
	end
	local empty = next(out.allow) == nil and next(out.deny) == nil
	local prev = P.UserPerms[sid]
	if not prev then
		local raw = P.DB.Value("SELECT perms FROM praetor_users WHERE sid = ?", sid)
		prev = (isstring(raw) and raw ~= "NULL" and util.JSONToTable(raw)) or { allow = {}, deny = {} }
	end
	local diff = {}
	for perm in pairs(out.allow) do if not (prev.allow or {})[perm] then diff[perm] = true end end
	for perm in pairs(out.deny) do if not (prev.deny or {})[perm] then diff[perm] = false end end
	for perm in pairs(prev.allow or {}) do if not out.allow[perm] and not out.deny[perm] then diff[perm] = "inherit" end end
	for perm in pairs(prev.deny or {}) do if not out.allow[perm] and not out.deny[perm] then diff[perm] = "inherit" end end
	P.EnsureUser(sid)
	P.DB.Query("UPDATE praetor_users SET perms = ? WHERE sid = ?", empty and nil or util.TableToJSON(out), sid)
	P.UserPerms[sid] = (not empty) and out or nil
	local online = P.BySID(sid)
	if IsValid(online) then P.SendPlayerExtras(online) end
	P.Log("rank", "l_userperms", { A = P.LogPly(ply), T = { n = P.KnownName(sid) or sid, s = sid } }, { ply, sid })
	if P.PermFeed then P.PermFeed(ply, "user", P.KnownName(sid) or sid, nil, diff) end
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("user_note", { perm = "user_notes", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	local text = P.Trim(P.Str(data.text, 400))
	if not sid or text == "" then return end
	P.EnsureUser(sid)
	P.DB.Query("INSERT INTO praetor_notes (sid, text, admin, admin_sid, created) VALUES (?, ?, ?, ?, ?)", sid, text, ply:Nick(), ply:SteamID64(), os.time())
	P.Log("punish", "l_note", { A = P.LogPly(ply), T = { n = P.KnownName(sid) or sid, s = sid }, V = text }, { ply, sid })
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("note_delete", { perm = "manage_users", rate = 3 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = P.DB.Row("SELECT sid FROM praetor_notes WHERE id = ?", id)
	if not row or not P.CanTargetSID(ply, row.sid) then return end
	P.DB.Query("DELETE FROM praetor_notes WHERE id = ?", id)
	P.Notify(ply, "ok_removed", nil, "ok")
end)
