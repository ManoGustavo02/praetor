-- Praetor: screenshot of a player's screen (!screengrab <player>).
--  * the player's game sends what it is drawing as a JPEG, in pieces, without
--    any notice on their screen;
--  * the picture is kept in data/praetor_shots (the last 80) and opens for the
--    staff member who asked. The "Screenshots" tab lists the old ones;
--  * no answer in 30 seconds goes to the Security tab (a cheat can block the
--    capture, and that is suspicious by itself);
--  * every screenshot goes to the logs, so the staff can't use it in secret.
local P = Praetor

util.AddNetworkString("praetor_shot")

local CHUNK = 48000
local MAX_SIZE = 4 * 1024 * 1024
local KEEP = 80
local DIR = "praetor_shots"
file.CreateDir(DIR)

P.DB.Query([[CREATE TABLE IF NOT EXISTS praetor_shots (id INTEGER PRIMARY KEY, sid TEXT, name TEXT, by_name TEXT, by_sid TEXT,
	t INTEGER, file TEXT, w INTEGER, h INTEGER, size INTEGER, focus INTEGER)]])

local OP_ASK, OP_HEAD, OP_PART, OP_SEND = 1, 2, 3, 4
local jobs = {}     -- target -> job
local lastBy = {}   -- staff sid -> time

local function rowPublic(r)
	return {
		id = tonumber(r.id), sid = r.sid, name = r.name, by = r.by_name, bys = r.by_sid, t = tonumber(r.t) or 0,
		w = tonumber(r.w) or 0, h = tonumber(r.h) or 0, size = tonumber(r.size) or 0, focus = tonumber(r.focus) == 1 or nil,
	}
end

-- sends a saved picture to a staff member, a piece every few frames
local function stream(ply, row)
	local data = file.Read(row.file, "DATA")
	if not data or #data == 0 then P.Notify(ply, "err_sg_gone") return end
	local n = math.ceil(#data / CHUNK)
	local id = tonumber(row.id)
	P.Send(ply, "sg_meta", rowPublic(row))
	local i = 0
	timer.Create("Praetor.ShotOut." .. ply:UserID() .. "." .. id, 0.05, n, function()
		if not IsValid(ply) then return end
		i = i + 1
		local part = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
		net.Start("praetor_shot")
		net.WriteUInt(OP_SEND, 3)
		net.WriteUInt(id, 32)
		net.WriteUInt(i, 8)
		net.WriteUInt(n, 8)
		net.WriteUInt(#part, 16)
		net.WriteData(part, #part)
		net.Send(ply)
	end)
end

local function prune()
	local rows = P.DB.Query("SELECT id, file FROM praetor_shots ORDER BY id DESC LIMIT 1000 OFFSET " .. KEEP) or {}
	for _, r in ipairs(rows) do
		if r.file and file.Exists(r.file, "DATA") then file.Delete(r.file) end
		P.DB.Query("DELETE FROM praetor_shots WHERE id = ?", r.id)
	end
end

local function finish(target, job)
	jobs[target] = nil
	timer.Remove("Praetor.ShotWait." .. job.id)
	local parts = {}
	for i = 1, job.n do
		if not job.parts[i] then return end
		parts[i] = job.parts[i]
	end
	local data = table.concat(parts)
	if #data ~= job.size or data:sub(1, 2) ~= "\255\216" then
		if IsValid(job.by) then P.Notify(job.by, "err_sg_bad", { S = target:Nick() }) end
		return
	end
	local sid = target:SteamID64()
	local t = os.time()
	local path = DIR .. "/" .. sid .. "_" .. t .. "_" .. math.random(100, 999) .. ".jpg"
	file.Write(path, data)
	P.DB.Query("INSERT INTO praetor_shots (sid, name, by_name, by_sid, t, file, w, h, size, focus) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sid, target:Nick(), job.byName, job.bySid, t, path, job.w, job.h, #data, job.focus and 1 or 0)
	local id = tonumber(P.DB.Value("SELECT MAX(id) FROM praetor_shots"))
	prune()
	if job.onSaved and id then job.onSaved(id) end
	if IsValid(job.by) and id then
		local row = P.DB.Row("SELECT * FROM praetor_shots WHERE id = ?", id)
		if row then stream(job.by, row) end
	end
end

function P.ScreenGrab(caller, target)
	if not IsValid(target) or not target:IsPlayer() then return false, "err_no_target" end
	if target:IsBot() then return false, "err_sg_bot" end
	if jobs[target] then return false, "err_sg_busy", { S = target:Nick() } end
	local bySid = IsValid(caller) and caller:SteamID64() or "CONSOLE"
	if (lastBy[bySid] or 0) > CurTime() then return false, "err_sg_wait" end
	lastBy[bySid] = CurTime() + 6
	local job = {
		id = math.random(1, 2 ^ 30), by = caller, bySid = bySid, byName = IsValid(caller) and caller:Nick() or "Console",
		parts = {}, got = 0, n = nil, size = 0, start = CurTime(),
	}
	jobs[target] = job
	net.Start("praetor_shot")
	net.WriteUInt(OP_ASK, 3)
	net.WriteUInt(job.id, 32)
	net.WriteUInt(math.Clamp(math.floor(tonumber(P.Setting("sg_quality")) or 70), 20, 95), 7)
	net.Send(target)
	P.Log("cmd", "l_sg", { A = P.LogPly(caller), T = P.LogPly(target) }, { caller, target })
	timer.Create("Praetor.ShotWait." .. job.id, 30, 1, function()
		if jobs[target] ~= job then return end
		jobs[target] = nil
		if not IsValid(target) then return end
		if IsValid(caller) then P.Notify(caller, "err_sg_noanswer", { S = target:Nick() }, "warn") end
		P.Log("security", "l_sg_noanswer", { T = P.LogPly(target) }, { target })
		if P.Security then P.Security(target, "sg_noanswer", job.got > 0 and ("partial " .. job.got .. "/" .. tostring(job.n)) or "", true) end
	end)
	return true
end

-- a picture the player sends by themselves (a report with "attach my screen")
function P.ExpectShot(ply, onSaved)
	if not IsValid(ply) or jobs[ply] then return nil end
	local job = {
		id = math.random(1, 2 ^ 30), bySid = ply:SteamID64(), byName = ply:Nick(),
		parts = {}, got = 0, n = nil, size = 0, start = CurTime(), onSaved = onSaved,
	}
	jobs[ply] = job
	timer.Create("Praetor.ShotWait." .. job.id, 40, 1, function()
		if jobs[ply] == job then jobs[ply] = nil end
	end)
	return job.id
end

net.Receive("praetor_shot", function(len, ply)
	if not IsValid(ply) then return end
	local job = jobs[ply]
	if not job then return end -- nobody asked: ignored
	local op = net.ReadUInt(3)
	local id = net.ReadUInt(32)
	if id ~= job.id then return end
	if op == OP_HEAD then
		if job.n then return end
		local n, size = net.ReadUInt(8), net.ReadUInt(24)
		job.w, job.h, job.focus = net.ReadUInt(16), net.ReadUInt(16), net.ReadBool()
		if n < 1 or n > 100 or size < 64 or size > MAX_SIZE or size > n * CHUNK then
			jobs[ply] = nil
			if IsValid(job.by) then P.Notify(job.by, "err_sg_bad", { S = ply:Nick() }) end
			return
		end
		job.n, job.size = n, size
	elseif op == OP_PART then
		if not job.n then return end
		local i, l = net.ReadUInt(8), net.ReadUInt(16)
		if i < 1 or i > job.n or job.parts[i] or l < 1 or l > CHUNK then return end
		job.parts[i] = net.ReadData(l)
		job.got = job.got + 1
		if job.got >= job.n then finish(ply, job) end
	end
end)

hook.Add("PlayerDisconnected", "Praetor.Shot", function(ply)
	local job = jobs[ply]
	if not job then return end
	jobs[ply] = nil
	if IsValid(job.by) then P.Notify(job.by, "err_sg_left", { S = ply:Nick() }) end
end)

-- ------------------------------------------------------------------ menu

P.Receive("sg_list", { perm = "screengrab", rate = 2 }, function(ply, data)
	local q = P.Trim(P.Str(data.q or "", 64))
	local rows
	local sid = P.ToSID64(q)
	if sid then
		rows = P.DB.Query("SELECT * FROM praetor_shots WHERE sid = ? ORDER BY id DESC LIMIT 80", sid)
	elseif q ~= "" then
		local like = "%" .. q:gsub("[%%_]", "") .. "%"
		rows = P.DB.Query("SELECT * FROM praetor_shots WHERE name LIKE ? OR by_name LIKE ? ORDER BY id DESC LIMIT 80", like, like)
	else
		rows = P.DB.Query("SELECT * FROM praetor_shots ORDER BY id DESC LIMIT 80")
	end
	local out = {}
	for _, r in ipairs(rows or {}) do out[#out + 1] = rowPublic(r) end
	P.Send(ply, "sg_list", { list = out })
end)

P.Receive("sg_get", { perm = { "screengrab", "reports" }, rate = 2 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	-- report staff without !screengrab only open pictures attached to a report
	if not P.Has(ply, "screengrab") and not P.DB.Value("SELECT id FROM praetor_reports WHERE shot = ?", id) then return end
	local row = P.DB.Row("SELECT * FROM praetor_shots WHERE id = ?", id)
	if not row then P.Notify(ply, "err_sg_gone") return end
	stream(ply, row)
end)

P.Receive("sg_del", { perm = "screengrab", rate = 2 }, function(ply, data)
	local row = P.DB.Row("SELECT * FROM praetor_shots WHERE id = ?", math.floor(tonumber(data.id) or 0))
	if not row then return end
	if row.file and file.Exists(row.file, "DATA") then file.Delete(row.file) end
	P.DB.Query("DELETE FROM praetor_shots WHERE id = ?", row.id)
	P.Log("cmd", "l_sg_del", { A = P.LogPly(ply), T = { n = row.name or "?", s = row.sid } }, { ply, row.sid })
	P.Notify(ply, "n_sg_deleted", nil, "ok")
end)
