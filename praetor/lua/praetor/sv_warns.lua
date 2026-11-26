-- Praetor: warnings with points and automatic punishments.
local P = Praetor

function P.WarnPoints(sid)
	local days = P.Setting("warn_decay_days")
	local since = days > 0 and (os.time() - days * 86400) or 0
	return tonumber(P.DB.Value("SELECT SUM(points) FROM praetor_warns WHERE sid = ? AND created >= ?", sid, since)) or 0
end

function P.AddWarn(sid, name, reason, points, actor)
	points = math.Clamp(math.floor(tonumber(points) or 1), 1, 10)
	local before = P.WarnPoints(sid)
	P.EnsureUser(sid, name)
	P.DB.Query("INSERT INTO praetor_warns (sid, reason, points, admin, admin_sid, created) VALUES (?, ?, ?, ?, ?, ?)",
		sid, P.Str(reason, 200), points, P.NameOf(actor), IsValid(actor) and actor:SteamID64() or "", os.time())
	local after = before + points
	P.Log("punish", "l_warn", { A = P.LogPly(actor), T = { n = name or P.KnownName(sid) or sid, s = sid }, V = reason, V2 = after }, { actor, sid })

	local ply = P.BySID(sid)
	if IsValid(ply) then
		P.Send(ply, "warned", { r = P.Str(reason, 200), by = P.NameOf(actor), pts = after })
	end

	-- the strongest rule crossed by this warning is applied
	local rule
	for _, r in ipairs(P.Setting("warn_rules")) do
		if before < r.pts and after >= r.pts then rule = r end
	end
	if not rule then return after end
	local why = string.format("%d warning points", after)
	timer.Simple(1, function()
		local target = P.BySID(sid)
		if rule.act == "ban" then
			P.AddBan(sid, name, rule.min, why, nil)
			P.Echo(nil, "e_autoban", { T = { name or sid }, V = after, V2 = P.FormatDuration(rule.min) })
		elseif IsValid(target) then
			if rule.act == "kick" then
				P.Echo(nil, "e_autokick", { T = { target }, V = after })
				target:Kick(why)
			elseif rule.act == "jail" then
				P.Jail(target, rule.min, nil, nil, why)
				P.Echo(nil, "e_autojail", { T = { target }, V = after, V2 = P.FormatDuration(rule.min) })
			elseif rule.act == "mute" then
				P.SetMute(target, rule.min, nil)
				P.Echo(nil, "e_automute", { T = { target }, V = after, V2 = P.FormatDuration(rule.min) })
			end
		end
	end)
	return after
end

P.Receive("warn_add", { perm = "warn", rate = 1 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	local reason = P.Trim(P.Str(data.reason, 200))
	if not sid or reason == "" then return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	local name = P.KnownName(sid) or P.SID32(sid)
	P.AddWarn(sid, name, reason, data.pts, ply)
	local online = P.BySID(sid)
	P.Echo(ply, "e_warn", { T = { IsValid(online) and online or name }, V = reason })
end)

P.Receive("warn_delete", { perm = "manage_users", rate = 3 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = P.DB.Row("SELECT sid FROM praetor_warns WHERE id = ?", id)
	if not row or not P.CanTargetSID(ply, row.sid) then return end
	P.DB.Query("DELETE FROM praetor_warns WHERE id = ?", id)
	P.Log("punish", "l_warn_del", { A = P.LogPly(ply), T = { n = P.KnownName(row.sid) or row.sid, s = row.sid } }, { ply, row.sid })
	P.Notify(ply, "ok_removed", nil, "ok")
end)
