-- Praetor: logs. Entries are stored as a language key + arguments so every
-- staff member reads them in their own language. Writes are buffered and saved
-- in one transaction every few seconds.
local P = Praetor

local queue = {}

function P.LogPly(p)
	if isstring(p) then return { n = P.KnownName(p) or p, s = p } end
	if not IsValid(p) then return { n = "Console", s = "CONSOLE" } end
	return { n = p:Nick(), s = P.SIDOf(p) }
end

local function plain(v, out)
	if isstring(v) or isnumber(v) then out[#out + 1] = tostring(v)
	elseif istable(v) then
		if v.n then out[#out + 1] = v.n end
		if v.s then out[#out + 1] = v.s end
		for _, x in ipairs(v) do plain(x, out) end
	end
end

-- cat: category; key: language key; args: { A = actor, T = target(s), V = value... }
-- involved: players or SteamID64 strings, used to find a player's history.
function P.Log(cat, key, args, involved)
	args = args or {}
	local sids = {}
	-- pairs: a nil first entry (arrest by command, no cop) must not hide the rest
	for _, v in pairs(involved or {}) do
		local s = isstring(v) and v or (IsValid(v) and P.SIDOf(v)) or nil
		if s and s ~= "CONSOLE" then sids[#sids + 1] = s end
	end
	local txt = {}
	for _, v in pairs(args) do plain(v, txt) end
	queue[#queue + 1] = {
		os.time(), cat, key, util.TableToJSON(args) or "{}",
		#sids > 0 and ("," .. table.concat(sids, ",") .. ",") or "",
		P.Str(table.concat(txt, " "), 400),
	}
	hook.Run("Praetor.Logged", cat, key, args)
	if P.LiveLog then P.LiveLog(cat, key, args) end
end

local function flush()
	if #queue == 0 then return end
	local batch = queue
	queue = {}
	P.DB.Begin()
	for _, e in ipairs(batch) do
		P.DB.Query("INSERT INTO praetor_logs (t, cat, k, a, sids, txt) VALUES (?, ?, ?, ?, ?, ?)", e[1], e[2], e[3], e[4], e[5], e[6])
	end
	P.DB.Commit()
end
-- written every second, so a crash loses at most one second of logs
timer.Create("Praetor.LogFlush", 1, 0, flush)

-- ------------------------------------------------------------------ sessions (crash logs)
-- Every server start is a session. A heartbeat keeps "last" up to date and a
-- clean shutdown (or map change) fills "ended". A session that never got
-- "ended" went down by a crash, and its logs can be opened in the logs tab.

P.DB.Query("INSERT INTO praetor_sessions (started, last, ended, map) VALUES (?, ?, 0, ?)", os.time(), os.time(), game.GetMap())
P.SessionId = tonumber(P.DB.Value("SELECT MAX(id) FROM praetor_sessions")) or 0
P.DB.Query("DELETE FROM praetor_sessions WHERE id < ?", P.SessionId - 60)

timer.Create("Praetor.SessionBeat", 5, 0, function()
	P.DB.Query("UPDATE praetor_sessions SET last = ? WHERE id = ?", os.time(), P.SessionId)
end)

hook.Add("ShutDown", "Praetor.LogFlush", function()
	flush()
	P.DB.Query("UPDATE praetor_sessions SET last = ?, ended = ? WHERE id = ?", os.time(), os.time(), P.SessionId)
end)

P.Receive("logs_sessions", { perm = "crash_logs", rate = 1 }, function(ply)
	local rows = P.DB.Query("SELECT id, started, last, ended, map FROM praetor_sessions WHERE id <> ? ORDER BY id DESC LIMIT 25", P.SessionId) or {}
	P.Send(ply, "logs_sessions", { rows = rows })
end)

function P.PruneLogs()
	local days = P.Setting("log_days")
	if days <= 0 then return end
	P.DB.Query("DELETE FROM praetor_logs WHERE t < ?", os.time() - days * 86400)
	P.DB.Query("DELETE FROM praetor_security WHERE t < ?", os.time() - math.max(days, 30) * 86400)
end

-- staff with the logs tab open receive new lines live
P.LogWatchers = P.LogWatchers or {}
function P.LiveLog(cat, key, args)
	local list = {}
	for p in pairs(P.LogWatchers) do
		if IsValid(p) and P.Has(p, "logs") then list[#list + 1] = p else P.LogWatchers[p] = nil end
	end
	if #list > 0 then P.Send(list, "log_live", { t = os.time(), cat = cat, k = key, a = args }) end
end

P.Receive("logs_watch", { perm = "logs", rate = 2 }, function(ply, data)
	P.LogWatchers[ply] = data.on == true or nil
end)

P.Receive("logs_query", { perm = "logs", rate = 3 }, function(ply, data)
	flush()
	local where, params = {}, {}
	if isstring(data.cat) and data.cat ~= "" and data.cat ~= "all" then
		where[#where + 1] = "cat = ?"
		params[#params + 1] = data.cat
	end
	local sid = P.ToSID64(data.sid or "")
	if sid then
		where[#where + 1] = "sids LIKE ?"
		params[#params + 1] = "%," .. sid .. ",%"
	end
	local q = P.Trim(P.Str(data.q, 60))
	if q ~= "" then
		where[#where + 1] = "txt LIKE ?"
		params[#params + 1] = "%" .. q:gsub("[%%_]", "") .. "%"
	end
	-- "before the crash" mode: only the lines of an old session
	local sess = tonumber(data.sess)
	if sess then
		if not P.Has(ply, "crash_logs") then return end
		local row = P.DB.Row("SELECT started, last FROM praetor_sessions WHERE id = ?", sess)
		if not row then return end
		where[#where + 1] = "t >= ? AND t <= ?"
		params[#params + 1] = tonumber(row.started) or 0
		params[#params + 1] = (tonumber(row.last) or 0) + 6
	end
	local page = math.Clamp(math.floor(tonumber(data.page) or 0), 0, 5000)
	local sqlq = "SELECT id, t, cat, k, a FROM praetor_logs"
	if #where > 0 then sqlq = sqlq .. " WHERE " .. table.concat(where, " AND ") end
	sqlq = sqlq .. " ORDER BY id DESC LIMIT 120 OFFSET " .. (page * 120)
	local rows = P.DB.Query(sqlq, unpack(params)) or {}
	P.Send(ply, "logs_query", { rows = rows, page = page, sess = sess })
end)

-- ------------------------------------------------------------------ what gets logged

local function wep(ent)
	if not IsValid(ent) then return "world" end
	if ent:IsPlayer() then
		local w = ent:GetActiveWeapon()
		return IsValid(w) and w:GetClass() or "hands"
	end
	return ent:GetClass()
end

hook.Add("PlayerInitialSpawn", "Praetor.LogJoin", function(ply)
	P.Log("conn", "l_join", { A = P.LogPly(ply) }, { ply })
end)



-- damage is merged per attacker/victim pair over 2 seconds to keep the log readable
local dmgAcc = {}
P.RecentDamage = P.RecentDamage or {}

hook.Add("PostEntityTakeDamage", "Praetor.LogDamage", function(ent, dmg, took)
	if not took or not P.Setting("log_damage") then return end
	if not IsValid(ent) or not ent:IsPlayer() then return end
	local att = dmg:GetAttacker()
	if not IsValid(att) or not att:IsPlayer() or att == ent then return end
	-- props thrown with the physgun have their own log line (sv_logs_game.lua)
	if P.IsPropEnt and P.IsPropEnt(dmg:GetInflictor()) then return end
	local key = att:EntIndex() .. ":" .. ent:EntIndex()
	local a = dmgAcc[key]
	if not a then
		a = { att = att, vic = ent, dmg = 0, wep = wep(att), t = CurTime() }
		dmgAcc[key] = a
	end
	a.dmg = a.dmg + dmg:GetDamage()
end)

timer.Create("Praetor.DamageFlush", 2, 0, function()
	for key, a in pairs(dmgAcc) do
		dmgAcc[key] = nil
		if IsValid(a.att) and IsValid(a.vic) then
			local amount = math.Round(a.dmg)
			P.Log("dmg", "l_damage", { A = P.LogPly(a.att), T = P.LogPly(a.vic), V = amount, V2 = a.wep }, { a.att, a.vic })
			table.insert(P.RecentDamage, 1, { t = os.time(), a = P.SIDOf(a.att), an = a.att:Nick(), v = P.SIDOf(a.vic), vn = a.vic:Nick(), d = amount, w = a.wep })
			while #P.RecentDamage > 400 do table.remove(P.RecentDamage) end
		end
	end
end)

local function spawnLog(kind)
	return function(ply, a, b)
		if not P.Setting("log_props") then return end
		local what = isstring(a) and a or (IsValid(b) and (b:GetModel() ~= "" and b:GetModel() or b:GetClass())) or (IsValid(a) and a:GetClass()) or "?"
		if isstring(a) and IsValid(b) and kind == "prop" then what = a end
		P.Log("prop", "l_spawn", { A = P.LogPly(ply), V = kind, V2 = what, M = what:find("%.mdl$") and what or nil }, { ply })
	end
end
hook.Add("PlayerSpawnedProp", "Praetor.Log", spawnLog("prop"))
hook.Add("PlayerSpawnedSENT", "Praetor.Log", function(ply, ent) spawnLog("entity")(ply, ent:GetClass()) end)
hook.Add("PlayerSpawnedVehicle", "Praetor.Log", function(ply, ent) spawnLog("vehicle")(ply, ent:GetClass()) end)
hook.Add("PlayerSpawnedNPC", "Praetor.Log", function(ply, ent) spawnLog("npc")(ply, ent:GetClass()) end)
hook.Add("PlayerSpawnedRagdoll", "Praetor.Log", spawnLog("ragdoll"))
hook.Add("PlayerSpawnedSWEP", "Praetor.Log", function(ply, ent) spawnLog("weapon")(ply, ent:GetClass()) end)

local toolSeen = {}
hook.Add("CanTool", "Praetor.LogTool", function(ply, tr, tool)
	if not P.Setting("log_props") or not IsValid(ply) then return end
	local key = ply:EntIndex() .. tool
	if toolSeen[key] and toolSeen[key] > CurTime() then return end
	toolSeen[key] = CurTime() + 3
	local ent = tr and tr.Entity
	local o = IsValid(ent) and P.EntOwner and P.EntOwner(ent) or nil
	if o and o ~= ply and not ent:IsPlayer() then
		P.Log("tool", "l_tool_other", { A = P.LogPly(ply), T = P.LogPly(o), V = tool, V2 = ent:GetClass() }, { ply, o })
		return
	end
	P.Log("tool", "l_tool", { A = P.LogPly(ply), V = tool, V2 = IsValid(ent) and ent:GetClass() or nil }, { ply })
end)
