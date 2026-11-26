-- Praetor: player reports ("the desk"). When the Blackbox addon is installed
-- (and the setting allows it) !report is left for Blackbox and this module
-- stays quiet. Without it:
--  * the player picks who (people they just fought or talked with come first),
--    a category and writes what happened; a picture of their own screen from
--    the moment they opened the window can go with it;
--  * damage between the two and the last chat lines of both are attached by
--    the server, plus how many times the target was reported before;
--  * every report gets a priority (category, repeated reports against the same
--    player, reporters that sent false reports before count less);
--  * staff and reporter talk inside the report; the reporter follows it live
--    (queue position, who is handling it) and answers "did it help?" at the end;
--  * staff close with an outcome (punished, warned, no proof, false report,
--    solved) and a note the reporter reads.
local P = Praetor

local CATS = { cheating = 3, rdm = 2, prop_abuse = 2, exploit = 2, insult = 1, rules = 1, help = 1, other = 1 }
P.ReportCats = { "rdm", "cheating", "prop_abuse", "insult", "exploit", "rules", "help", "other" }
local OUTCOMES = { punished = true, warned = true, noproof = true, false_report = true, solved = true }

-- columns added in 1.4.0
do
	local have = {}
	for _, c in ipairs(sql.Query("PRAGMA table_info(praetor_reports)") or {}) do have[c.name] = true end
	for col, typ in pairs({ cat = "TEXT", outcome = "TEXT", prio = "INTEGER DEFAULT 0", rating = "INTEGER DEFAULT 0",
		shot = "INTEGER DEFAULT 0", ctx = "TEXT", claimed = "INTEGER DEFAULT 0" }) do
		if not have[col] then sql.Query("ALTER TABLE praetor_reports ADD COLUMN " .. col .. " " .. typ) end
	end
	P.DB.Query([[CREATE TABLE IF NOT EXISTS praetor_report_msgs (id INTEGER PRIMARY KEY AUTOINCREMENT, rid INTEGER,
		sid TEXT, name TEXT, staff INTEGER DEFAULT 0, t INTEGER, text TEXT)]])
end

local cooldown = {}

local function staff() return P.WithPerm("reports") end

-- who gets the alerts: staff on duty (setting duty_reports). The others only get
-- the counter updated, so an open reports tab stays right.
local function alertStaff()
	local all = staff()
	if P.Setting("duty_reports") ~= true or P.Setting("duty_on") == false then return all, {} end
	local on, off = {}, {}
	for _, p in ipairs(all) do
		if p:GetNW2Bool("pr_duty", false) then on[#on + 1] = p else off[#off + 1] = p end
	end
	return on, off
end

local function openCount()
	return tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE status != 'closed'")) or 0
end
P.ReportOpenCount = openCount

local function getRow(id) return P.DB.Row("SELECT * FROM praetor_reports WHERE id = ?", math.floor(tonumber(id) or 0)) end

-- ------------------------------------------------------------------ chat memory (context for reports)

local chatLog = {}
hook.Add("PlayerSay", "Praetor.ReportChat", function(ply, text)
	if not IsValid(ply) or not isstring(text) or text == "" then return end
	table.insert(chatLog, 1, { t = os.time(), s = ply:SteamID64(), n = ply:Nick(), m = P.Str(text, 160) })
	while #chatLog > 300 do table.remove(chatLog) end
end)

local function chatOf(sids, limit)
	local out = {}
	local since = os.time() - 600
	for _, c in ipairs(chatLog) do
		if c.t < since then break end
		if sids[c.s] then out[#out + 1] = c end
		if #out >= limit then break end
	end
	return out
end

-- ------------------------------------------------------------------ people to report

-- the players the reporter fought with or heard from in the last minutes, most recent first
P.Receive("report_people", { rate = 1 }, function(ply)
	local me = ply:SteamID64()
	local since = os.time() - 600
	local seen, list = {}, {}
	local function add(sid, why, t)
		if not sid or sid == me or seen[sid] then return end
		local p = P.BySID(sid)
		if not IsValid(p) or p:IsBot() then return end
		seen[sid] = true
		list[#list + 1] = { sid = sid, why = why, ago = os.time() - t }
	end
	for _, d in ipairs(P.RecentDamage or {}) do
		if d.t < since or #list >= 6 then break end
		if d.v == me then add(d.a, "hurt_you", d.t) elseif d.a == me then add(d.v, "you_hurt", d.t) end
	end
	for _, c in ipairs(chatLog) do
		if c.t < since or #list >= 8 then break end
		add(c.s, "talked", c.t)
	end
	P.Send(ply, "report_people", { list = list })
end)

-- ------------------------------------------------------------------ priority

local function falseReports(sid)
	return tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE sid = ? AND outcome = 'false_report'", sid)) or 0
end

local function priorityOf(cat, tsid, reporter)
	local p = (CATS[cat] or 1) * 10
	if tsid and tsid ~= "" then
		local recent = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE tsid = ? AND created > ?", tsid, os.time() - 1800)) or 0
		p = p + math.min(recent, 5) * 8
	end
	p = p - math.min(falseReports(reporter), 3) * 6
	return math.Clamp(p, 0, 99)
end

-- ------------------------------------------------------------------ live state for the reporter

local function queuePos(id)
	return (tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE status = 'open' AND id <= ?", id)) or 0)
end

-- the reporter's little card: status, queue position, who is on it, new messages
function P.ReportPushState(row)
	if not row then return end
	local ply = P.BySID(row.sid)
	if not IsValid(ply) then return end
	local id = tonumber(row.id)
	P.Send(ply, "report_state", {
		id = id, st = row.status, pos = row.status == "open" and queuePos(id) or nil,
		by = (row.staff_name and row.staff_name ~= "NULL" and row.staff_name ~= "") and row.staff_name or nil,
		cat = row.cat, t = row.tname, out = row.outcome ~= "NULL" and row.outcome or nil,
	})
end

local function pushAllOpen()
	for _, r in ipairs(P.DB.Query("SELECT * FROM praetor_reports WHERE status = 'open'") or {}) do P.ReportPushState(r) end
end

local function staffUpdate(id)
	P.Send(staff(), "report_upd", { id = id, open = openCount() })
end

-- ------------------------------------------------------------------ send

P.Receive("report_send", { rate = 0.5, max = 16384 }, function(ply, data)
	if not P.Setting("reports") then return end
	local sid = ply:SteamID64()
	local cd = P.Setting("reports_cooldown")
	if cooldown[sid] and cooldown[sid] > CurTime() then
		P.Notify(ply, "err_report_wait", { V = math.ceil(cooldown[sid] - CurTime()) })
		return
	end
	local cat = isstring(data.cat) and CATS[data.cat] and data.cat or "other"
	local text = P.Trim(P.Str(data.text, 600))
	local tsid = P.ToSID64(data.tsid or "")
	if tsid == sid then tsid = nil end
	if not tsid and cat ~= "help" and cat ~= "other" and text == "" then P.Notify(ply, "err_report_who") return end
	-- one open report per reporter and target
	if P.DB.Value("SELECT id FROM praetor_reports WHERE sid = ? AND tsid = ? AND status != 'closed'", sid, tsid or "") then
		P.Notify(ply, "err_report_dup")
		return
	end
	local tname = tsid and (P.KnownName(tsid) or P.SID32(tsid)) or ""
	cooldown[sid] = CurTime() + cd

	-- what the server knows about the two of them
	local dmg = {}
	if tsid then
		local since = os.time() - 300
		for _, d in ipairs(P.RecentDamage or {}) do
			if d.t < since then break end
			if (d.a == tsid and d.v == sid) or (d.a == sid and d.v == tsid) then dmg[#dmg + 1] = d end
			if #dmg >= 30 then break end
		end
	end
	local who = { [sid] = true }
	if tsid then who[tsid] = true end
	local ctx = { dmg = dmg, chat = chatOf(who, 16) }
	if tsid then
		ctx.before = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE tsid = ?", tsid)) or 0
		ctx.punished = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE tsid = ? AND outcome IN ('punished', 'warned')", tsid)) or 0
	end
	ctx.falses = falseReports(sid)
	local tp = tsid and P.BySID(tsid)
	if IsValid(tp) and IsValid(ply) then ctx.dist = math.floor(tp:GetPos():Distance(ply:GetPos()) / 52.5) end

	local prio = priorityOf(cat, tsid, sid)
	local reasonText = P.LText(P.Setting("lang") == "pt" and "pt" or "en", "reason_" .. cat)
	P.DB.Query("INSERT INTO praetor_reports (sid, name, tsid, tname, reason, text, created, status, verdict, cat, prio, ctx) VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)",
		sid, ply:Nick(), tsid or "", tname, reasonText, text, os.time(), "{}", cat, prio, util.TableToJSON(ctx))
	local id = tonumber(P.DB.Value("SELECT MAX(id) FROM praetor_reports")) or 0
	P.Log("report", "l_report", { A = P.LogPly(ply), T = tsid and { n = tname, s = tsid } or nil, V = reasonText }, { ply, tsid })
	local onDuty, offDuty = alertStaff()
	if #onDuty > 0 then P.Send(onDuty, "report_new", { id = id, n = ply:Nick(), t = tname, r = reasonText, cat = cat, prio = prio, open = openCount() }) end
	if #offDuty > 0 then P.Send(offDuty, "report_upd", { id = id, open = openCount() }) end
	hook.Run("Praetor.ReportCreated", id, ply, tsid, reasonText, text)
	P.ReportPushState(getRow(id))

	-- the picture of the reporter's screen comes right after
	if data.shot and P.ExpectShot then
		local jobId = P.ExpectShot(ply, function(shotId)
			P.DB.Query("UPDATE praetor_reports SET shot = ? WHERE id = ?", shotId, id)
			staffUpdate(id)
		end)
		if jobId then P.Send(ply, "report_shot_go", { job = jobId }) end
	end
end)

-- ------------------------------------------------------------------ the reporter's own reports

P.Receive("report_mine", { rate = 2 }, function(ply)
	local rows = P.DB.Query("SELECT id, tname, cat, reason, status, staff_name, created, closed, outcome, rating, verdict FROM praetor_reports WHERE sid = ? ORDER BY id DESC LIMIT 8", ply:SteamID64()) or {}
	for _, r in ipairs(rows) do
		r.id = tonumber(r.id)
		local v = util.JSONToTable(r.verdict or "") or {}
		r.note = v.text
		r.verdict = nil
		if r.status == "open" then r.pos = queuePos(r.id) end
		-- the last 15 messages, oldest first (keeps the answer under the net limit)
		r.msgs = P.DB.Query("SELECT * FROM (SELECT id, name, staff, t, text FROM praetor_report_msgs WHERE rid = ? ORDER BY id DESC LIMIT 15) ORDER BY id ASC", r.id) or {}
	end
	P.Send(ply, "report_mine", { list = rows })
end)

P.Receive("report_cancel", { rate = 1 }, function(ply, data)
	local row = getRow(data.id)
	if not row or row.sid ~= ply:SteamID64() or row.status == "closed" then return end
	local v = util.JSONToTable(row.verdict or "") or {}
	v.text = P.LText(P.Setting("lang") == "pt" and "pt" or "en", "rp_cancelled_note")
	P.DB.Query("UPDATE praetor_reports SET status = 'closed', closed = ?, outcome = 'cancelled', verdict = ? WHERE id = ?", os.time(), util.TableToJSON(v), row.id)
	P.Notify(ply, "n_report_cancelled", nil, "ok")
	staffUpdate(tonumber(row.id))
	local s = row.staff_sid and P.BySID(row.staff_sid)
	if IsValid(s) then P.Notify(s, "n_report_cancelled_staff", { V = row.id, S = ply:Nick() }, "warn") end
	hook.Run("Praetor.ReportClosed", tonumber(row.id), nil, "cancelled", row)
	pushAllOpen()
end)

P.Receive("report_rate", { rate = 1 }, function(ply, data)
	local row = getRow(data.id)
	if not row or row.sid ~= ply:SteamID64() or row.status ~= "closed" or (tonumber(row.rating) or 0) ~= 0 then return end
	local r = data.good == true and 1 or -1
	P.DB.Query("UPDATE praetor_reports SET rating = ? WHERE id = ?", r, row.id)
	P.Notify(ply, "n_report_thanks", nil, "ok")
	local s = row.staff_sid and P.BySID(row.staff_sid)
	if IsValid(s) then P.Send(s, "report_rated", { id = tonumber(row.id), good = r == 1 or nil, n = ply:Nick() }) end
	if r == 1 and row.staff_sid and P.StaffAdd then P.StaffAdd(row.staff_sid, "stars", 5) P.StaffAdd(row.staff_sid, "rated", 1)
	elseif row.staff_sid and P.StaffAdd then P.StaffAdd(row.staff_sid, "stars", 1) P.StaffAdd(row.staff_sid, "rated", 1) end
end)

-- ------------------------------------------------------------------ messages (staff <-> reporter)

local function addMsg(row, ply, text, isStaff)
	text = P.Trim(P.Str(text, 300))
	if text == "" then return false end
	P.DB.Query("INSERT INTO praetor_report_msgs (rid, sid, name, staff, t, text) VALUES (?, ?, ?, ?, ?, ?)",
		row.id, ply:SteamID64(), ply:Nick(), isStaff and 1 or 0, os.time(), text)
	local m = { rid = tonumber(row.id), n = ply:Nick(), st = isStaff and 1 or nil, t = os.time(), m = text }
	if isStaff then
		local rep = P.BySID(row.sid)
		if IsValid(rep) then P.Send(rep, "report_msg", { rid = m.rid, n = m.n, st = 1, t = m.t, m = m.m, you = 1 }) end
	end
	-- every staff member with the report open sees it (the client filters)
	local to = staff()
	if not isStaff then
		P.Send(to, "report_msg", m)
	else
		for i = #to, 1, -1 do if to[i] == ply then table.remove(to, i) end end
		if #to > 0 then P.Send(to, "report_msg", m) end
	end
	return true
end

P.Receive("report_say", { rate = 0.7 }, function(ply, data)
	local row = getRow(data.id)
	if not row or row.status == "closed" then return end
	local isStaff = P.Has(ply, "reports") and row.sid ~= ply:SteamID64()
	if not isStaff and row.sid ~= ply:SteamID64() then return end
	addMsg(row, ply, data.m, isStaff)
end)

-- ------------------------------------------------------------------ staff desk

local function staffRow(r)
	r.id = tonumber(r.id)
	r.prio = tonumber(r.prio) or 0
	r.shot = tonumber(r.shot) or 0
	r.created = tonumber(r.created) or 0
	r.rating = tonumber(r.rating) or 0
	r.claimed = tonumber(r.claimed) or 0
	local v = util.JSONToTable(r.verdict or "") or {}
	r.note = v.text
	r.ctx = util.JSONToTable(r.ctx or "") or { dmg = v.dmg }
	r.verdict = nil
	r.ron = IsValid(P.BySID(r.sid)) or nil
	r.ton = (r.tsid or "") ~= "" and IsValid(P.BySID(r.tsid)) or nil
	return r
end

P.Receive("reports_list", { perm = "reports", rate = 3 }, function(ply, data)
	local mode = data.mode
	local rows
	if mode == "closed" then
		rows = P.DB.Query("SELECT * FROM praetor_reports WHERE status = 'closed' ORDER BY id DESC LIMIT 60")
	elseif mode == "mine" then
		rows = P.DB.Query("SELECT * FROM praetor_reports WHERE status != 'closed' AND staff_sid = ? ORDER BY id DESC LIMIT 60", ply:SteamID64())
	else
		rows = P.DB.Query("SELECT * FROM praetor_reports WHERE status != 'closed' ORDER BY prio DESC, id ASC LIMIT 80")
	end
	local out = {}
	for _, r in ipairs(rows or {}) do
		-- the queue only needs the card; the detail comes with report_get
		r = staffRow(r)
		r.ctx, r.text, r.note = nil, nil, nil
		out[#out + 1] = r
	end
	-- reports against the same player in the open list
	local against = {}
	if mode ~= "closed" then
		for _, r in ipairs(out) do if (r.tsid or "") ~= "" then against[r.tsid] = (against[r.tsid] or 0) + 1 end end
	end
	P.Send(ply, "reports_list", { rows = out, mode = mode, open = openCount(), against = against })
end)

P.Receive("report_get", { perm = "reports", rate = 4 }, function(ply, data)
	local row = getRow(data.id)
	if not row then return end
	local r = staffRow(row)
	r.msgs = P.DB.Query("SELECT name, staff, t, text FROM praetor_report_msgs WHERE rid = ? ORDER BY id ASC LIMIT 60", r.id) or {}
	P.Send(ply, "report_get", r)
end)

P.Receive("report_claim", { perm = "reports", rate = 2 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = getRow(id)
	if not row or row.status == "closed" then return end
	if row.sid == ply:SteamID64() or row.tsid == ply:SteamID64() then P.Notify(ply, "err_report_own") return end
	if data.drop then
		if row.staff_sid ~= ply:SteamID64() then return end
		P.DB.Query("UPDATE praetor_reports SET status = 'open', staff_sid = NULL, staff_name = NULL WHERE id = ?", id)
		P.Log("report", "l_report_drop", { A = P.LogPly(ply), V = id }, { ply, row.sid })
		staffUpdate(id)
		P.ReportPushState(getRow(id))
		return
	end
	-- taking a report needs staff mode: the player is asked to start it (and the report is taken right after)
	if P.NeedDuty and P.NeedDuty(ply, "report_claim", { id = id, take = data.take }) then return end
	if row.status == "claimed" and row.staff_sid ~= ply:SteamID64() then
		local other = P.BySID(row.staff_sid or "")
		if IsValid(other) and not data.take then P.Notify(ply, "err_report_taken", { S = other:Nick() }) return end
	end
	P.DB.Query("UPDATE praetor_reports SET status = 'claimed', staff_sid = ?, staff_name = ?, claimed = ? WHERE id = ?", ply:SteamID64(), ply:Nick(), os.time(), id)
	local reporter = P.BySID(row.sid)
	if IsValid(reporter) then P.Notify(reporter, "n_report_claimed", { S = ply:Nick() }, "ok") end
	P.Log("report", "l_report_claim", { A = P.LogPly(ply), V = id }, { ply, row.sid })
	staffUpdate(id)
	P.ReportPushState(getRow(id))
	pushAllOpen()
	hook.Run("Praetor.ReportClaimed", id, ply, row)
end)

P.Receive("report_close", { perm = "reports", rate = 2 }, function(ply, data)
	local id = math.floor(tonumber(data.id) or 0)
	local row = getRow(id)
	if not row or row.status == "closed" then return end
	local verdict = P.Trim(P.Str(data.verdict, 300))
	local outcome = isstring(data.outcome) and OUTCOMES[data.outcome] and data.outcome or "solved"
	local old = util.JSONToTable(row.verdict or "") or {}
	old.text = verdict
	P.DB.Query("UPDATE praetor_reports SET status = 'closed', closed = ?, staff_sid = ?, staff_name = ?, verdict = ?, outcome = ? WHERE id = ?",
		os.time(), ply:SteamID64(), ply:Nick(), util.TableToJSON(old), outcome, id)
	local reporter = P.BySID(row.sid)
	if IsValid(reporter) then P.Send(reporter, "report_done", { id = id, by = ply:Nick(), v = verdict, r = row.reason, out = outcome, t = row.tname }) end
	P.Log("report", "l_report_close", { A = P.LogPly(ply), V = id, V2 = P.LText("en", "rp_out_" .. outcome) .. (verdict ~= "" and (": " .. verdict) or "") }, { ply, row.sid })
	staffUpdate(id)
	pushAllOpen()
	hook.Run("Praetor.ReportClosed", id, ply, verdict, row)
end)

-- ------------------------------------------------------------------ reminders

-- staff that join see how many reports are waiting
hook.Add("Praetor.UserLoaded", "Praetor.Reports", function(ply)
	timer.Simple(6, function()
		if not IsValid(ply) or not P.Has(ply, "reports") then return end
		local n = openCount()
		if n > 0 then P.Notify(ply, "n_reports_waiting", { V = n }) end
	end)
end)

-- a report nobody took for 2 minutes rings again (every 2 minutes)
timer.Create("Praetor.ReportRemind", 120, 0, function()
	if not P.Setting("reports") or (BBX and P.Setting("reports_blackbox")) then return end
	local n = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_reports WHERE status = 'open' AND created < ?", os.time() - 120)) or 0
	if n == 0 then return end
	local to = alertStaff()
	if #to > 0 then P.Send(to, "report_remind", { n = n, open = openCount() }) end
end)

-- the reporter left: the staff sees it on the card (and the queue moves)
hook.Add("PlayerDisconnected", "Praetor.Reports", function()
	timer.Simple(0.5, function() P.Send(staff(), "report_upd", { open = openCount() }) end)
end)
