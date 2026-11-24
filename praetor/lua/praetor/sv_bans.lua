-- Praetor: bans (online, offline by SteamID, temporary or permanent).
local P = Praetor

P.BanCache = P.BanCache or {}

function P.LoadBans()
	P.BanCache = {}
	local now = os.time()
	local rows = P.DB.Query("SELECT * FROM praetor_bans WHERE lifted = 0 AND (expires = 0 OR expires > ?)", now) or {}
	for _, r in ipairs(rows) do
		r.expires = tonumber(r.expires) or 0
		r.created = tonumber(r.created) or 0
		local cur = P.BanCache[r.sid]
		-- keep the longest active ban
		if not cur or r.expires == 0 or (cur.expires ~= 0 and r.expires > cur.expires) then P.BanCache[r.sid] = r end
	end
end

local function banMessage(b)
	local exp = (tonumber(b.expires) or 0) == 0 and "never / nunca" or (os.date("%d/%m/%Y %H:%M", b.expires) .. " (" .. P.FormatDuration(math.ceil((b.expires - os.time()) / 60)) .. ")")
	local code = b.id and ("\nCode / Código: #" .. b.id) or ""
	local link = P.Trim(P.Setting("ban_discord") or "")
	local appeal = link ~= "" and ("\n\nAppeal / Revisão: " .. link) or ""
	return string.format("You are banned from this server / Você está banido deste servidor\n\nReason / Motivo: %s\nBy / Por: %s\nExpires / Expira: %s%s%s\n\n[Praetor]",
		(b.reason and b.reason ~= "") and b.reason or "-", b.admin or "Console", exp, code, appeal)
end
P.BanMessage = banMessage

-- Can `ply` ban for this long? 0 minutes = permanent.
function P.CheckBanLimit(ply, minutes)
	if not IsValid(ply) or P.IsOwner(ply) then return true end
	local limit = P.RankOf(ply).ban_limit or 0
	if limit <= 0 then return true end
	if minutes <= 0 or minutes > limit then return false, limit end
	return true
end

function P.AddBan(sid, name, minutes, reason, admin)
	if not sid or P.Owners[sid] then return false end
	minutes = math.max(0, math.floor(tonumber(minutes) or 0))
	local now = os.time()
	local exp = minutes > 0 and (now + minutes * 60) or 0
	name = P.Str(name and name ~= "" and name or (P.KnownName(sid) or ""), 64)
	reason = P.Str(reason or "", 200)
	local adminName = IsValid(admin) and admin:Nick() or (isstring(admin) and admin or "Console")
	local adminSid = IsValid(admin) and admin:SteamID64() or ""
	P.EnsureUser(sid, name)
	P.DB.Query("INSERT INTO praetor_bans (sid, name, reason, admin, admin_sid, created, expires) VALUES (?, ?, ?, ?, ?, ?, ?)",
		sid, name, reason, adminName, adminSid, now, exp)
	local b = { sid = sid, name = name, reason = reason, admin = adminName, admin_sid = adminSid, created = now, expires = exp }
	b.id = tonumber(P.DB.Value("SELECT MAX(id) FROM praetor_bans WHERE sid = ?", sid))
	P.BanCache[sid] = b
	P.Log("punish", "l_ban", { A = P.LogPly(admin), T = { n = name, s = sid }, V = P.FormatDuration(minutes), V2 = reason }, { admin, sid })
	hook.Run("Praetor.Banned", sid, minutes, reason, admin)
	if ULib and ULib.Praetor then hook.Run("ULibPlayerBanned", util.SteamIDFrom64(sid), { reason = reason, unban = exp, admin = adminName }) end
	local ply = P.BySID(sid)
	if IsValid(ply) then
		-- the ban screen (sv_banscreen) shows the ban before the kick
		if P.BanKick then P.BanKick(ply, b) else ply:Kick(banMessage(b)) end
	end
	return true
end

function P.LiftBan(sid, admin)
	if not sid then return false end
	local had = P.BanCache[sid] ~= nil
	P.BanCache[sid] = nil
	P.DB.Query("UPDATE praetor_bans SET lifted = ?, lifted_by = ? WHERE sid = ? AND lifted = 0", os.time(), IsValid(admin) and admin:Nick() or "Console", sid)
	P.Log("punish", "l_unban", { A = P.LogPly(admin), T = { n = P.KnownName(sid) or sid, s = sid } }, { admin, sid })
	hook.Run("Praetor.Unbanned", sid, admin)
	if ULib and ULib.Praetor then hook.Run("ULibPlayerUnBanned", util.SteamIDFrom64(sid), admin) end
	return had
end

hook.Add("CheckPassword", "Praetor.Bans", function(sid64, _, _, _, joinName)
	if P.Owners[sid64] then return end
	local b = P.BanCache[sid64]
	if not b then return end
	if b.expires ~= 0 and b.expires <= os.time() then
		P.BanCache[sid64] = nil
		return
	end
	-- chat line "X tried to join, banned for Y" (sv_banscreen)
	if P.BanTryNotice then P.BanTryNotice(sid64, joinName, b) end
	-- let them in only to see the ban screen (sv_banscreen), then they are kicked
	if P.BanLetIn and P.BanLetIn(sid64, b) then return end
	return false, banMessage(b)
end)

-- expired bans leave the cache by themselves
timer.Create("Praetor.BanExpire", 60, 0, function()
	local now = os.time()
	for sid, b in pairs(P.BanCache) do
		if b.expires ~= 0 and b.expires <= now then P.BanCache[sid] = nil end
	end
end)

-- ------------------------------------------------------------------ bans tab

P.Receive("bans_list", { perm = { "manage_bans", "ban", "banid", "unban" }, rate = 3 }, function(ply, data)
	local q = P.Trim(P.Str(data.q, 64))
	local page = math.Clamp(math.floor(tonumber(data.page) or 0), 0, 1000)
	local where, params = {}, {}
	if not data.all then
		where[#where + 1] = "lifted = 0 AND (expires = 0 OR expires > ?)"
		params[#params + 1] = os.time()
	end
	local sid = P.ToSID64(q)
	if sid then
		where[#where + 1] = "sid = ?"
		params[#params + 1] = sid
	elseif q ~= "" then
		local like = "%" .. q:gsub("[%%_]", "") .. "%"
		where[#where + 1] = "(name LIKE ? OR reason LIKE ? OR admin LIKE ?)"
		params[#params + 1] = like
		params[#params + 1] = like
		params[#params + 1] = like
	end
	local s = "SELECT * FROM praetor_bans"
	if #where > 0 then s = s .. " WHERE " .. table.concat(where, " AND ") end
	s = s .. " ORDER BY id DESC LIMIT 80 OFFSET " .. page * 80
	P.Send(ply, "bans_list", { rows = P.DB.Query(s, unpack(params)) or {}, page = page })
end)

P.Receive("ban_add", { perm = "banid", rate = 1 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then P.Notify(ply, "err_steamid") return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	local minutes = math.max(0, math.floor(tonumber(data.min) or 0))
	local ok, limit = P.CheckBanLimit(ply, minutes)
	if not ok then P.Notify(ply, "err_ban_limit", { V = P.FormatDuration(limit) }) return end
	if P.AddBan(sid, data.name, minutes, data.reason, ply) then
		P.Echo(ply, "e_banid", { T = { P.KnownName(sid) or P.SID32(sid) }, V = P.FormatDuration(minutes), V2 = P.Str(data.reason, 200) })
	end
end)

P.Receive("ban_lift", { perm = "unban", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then return end
	local row = P.DB.Row("SELECT admin_sid FROM praetor_bans WHERE sid = ? AND lifted = 0 ORDER BY id DESC", sid)
	-- a ban made by someone with more authority can only be lifted by someone at least as high
	if row and row.admin_sid and row.admin_sid ~= "" and row.admin_sid ~= "NULL" and not P.IsOwner(ply) then
		local auth, owner = P.AuthorityOfSID(row.admin_sid)
		if owner or auth > P.Authority(ply) then P.Notify(ply, "err_ban_higher") return end
	end
	if P.LiftBan(sid, ply) then
		P.Echo(ply, "e_unban", { T = { P.KnownName(sid) or P.SID32(sid) } })
	end
end)

P.Receive("ban_edit", { perm = "manage_bans", rate = 2 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = P.DB.Row("SELECT * FROM praetor_bans WHERE id = ?", id)
	if not row then return end
	if not P.CanTargetSID(ply, row.sid) then P.Notify(ply, "err_authority", { S = row.name }) return end
	local minutes = math.max(0, math.floor(tonumber(data.min) or 0))
	local ok, limit = P.CheckBanLimit(ply, minutes)
	if not ok then P.Notify(ply, "err_ban_limit", { V = P.FormatDuration(limit) }) return end
	local exp = minutes > 0 and ((tonumber(row.created) or os.time()) + minutes * 60) or 0
	local reason = P.Str(data.reason or row.reason, 200)
	P.DB.Query("UPDATE praetor_bans SET reason = ?, expires = ? WHERE id = ?", reason, exp, id)
	P.LoadBans()
	P.Log("punish", "l_ban_edit", { A = P.LogPly(ply), T = { n = row.name, s = row.sid }, V = P.FormatDuration(minutes), V2 = reason }, { ply, row.sid })
	P.Notify(ply, "ok_saved", nil, "ok")
end)
