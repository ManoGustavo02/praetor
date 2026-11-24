-- Praetor: staff statistics. For every staff member, per day: time online,
-- time on duty, commands, punishments (kick / ban / warn / others), reports
-- closed (Praetor and Blackbox), Blackbox ratings and support rooms handled.
-- The "Staff" tab shows the week, the month or everything, with a ranking.
local P = Praetor

P.DB.Query([[CREATE TABLE IF NOT EXISTS praetor_staff_days (
	sid TEXT, day INTEGER, online INTEGER DEFAULT 0, duty INTEGER DEFAULT 0, cmds INTEGER DEFAULT 0,
	kicks INTEGER DEFAULT 0, bans INTEGER DEFAULT 0, warns INTEGER DEFAULT 0, pun INTEGER DEFAULT 0,
	reports INTEGER DEFAULT 0, cases INTEGER DEFAULT 0, sits INTEGER DEFAULT 0, stars INTEGER DEFAULT 0, rated INTEGER DEFAULT 0,
	PRIMARY KEY (sid, day))]])

local FIELDS = { "online", "duty", "cmds", "kicks", "bans", "warns", "pun", "reports", "cases", "sits", "stars", "rated" }
local FIELD = {}
for _, f in ipairs(FIELDS) do FIELD[f] = true end

local pending = {}

local function today() return tonumber(os.date("%Y%m%d")) end

function P.StaffAdd(sid, field, n)
	if not isstring(sid) or not sid:match("^%d+$") or not FIELD[field] then return end
	pending[sid] = pending[sid] or {}
	pending[sid][field] = (pending[sid][field] or 0) + (n or 1)
end

local function flush()
	if next(pending) == nil then return end
	local day = today()
	P.DB.Begin()
	for sid, t in pairs(pending) do
		P.DB.Query("INSERT OR IGNORE INTO praetor_staff_days (sid, day) VALUES (?, ?)", sid, day)
		local sets, vals = {}, {}
		for f, n in pairs(t) do
			sets[#sets + 1] = f .. " = " .. f .. " + ?"
			vals[#vals + 1] = n
		end
		vals[#vals + 1] = sid
		vals[#vals + 1] = day
		P.DB.Query("UPDATE praetor_staff_days SET " .. table.concat(sets, ", ") .. " WHERE sid = ? AND day = ?", unpack(vals))
	end
	P.DB.Commit()
	pending = {}
end
P.StaffFlush = flush

-- time online and on duty
timer.Create("Praetor.StaffTime", 30, 0, function()
	for _, p in ipairs(player.GetHumans()) do
		if P.IsStaff(p) then
			local sid = p:SteamID64()
			P.StaffAdd(sid, "online", 30)
			if p:GetNW2Bool("pr_duty", false) then P.StaffAdd(sid, "duty", 30) end
		end
	end
end)
timer.Create("Praetor.StaffFlush", 60, 0, flush)
hook.Add("ShutDown", "Praetor.StaffStats", flush)

-- commands and punishments
local PUN = {
	jail = true, mute = true, gag = true, slay = true, freeze = true, strip = true, jobban = true, rpdemote = true,
	ignite = true, slap = true, blind = true, launch = true, wanted = true, arrest = true,
}
hook.Add("Praetor.CommandRan", "Praetor.StaffStats", function(caller, id)
	if not IsValid(caller) or not caller:IsPlayer() or not P.IsStaff(caller) then return end
	local sid = caller:SteamID64()
	P.StaffAdd(sid, "cmds")
	if id == "kick" then P.StaffAdd(sid, "kicks")
	elseif id == "ban" or id == "banid" then P.StaffAdd(sid, "bans")
	elseif id == "warn" then P.StaffAdd(sid, "warns")
	elseif PUN[id] then P.StaffAdd(sid, "pun") end
end)

-- reports (Praetor) and cases (Blackbox)
hook.Add("Praetor.ReportClosed", "Praetor.StaffStats", function(id, ply)
	if IsValid(ply) then P.StaffAdd(ply:SteamID64(), "reports") end
end)
hook.Add("BBX_CaseClosed", "Praetor.StaffStats", function(c, closer)
	if not IsValid(closer) or not istable(c) then return end
	if c.verdict == "cancelled" or c.verdict == "left" then return end
	P.StaffAdd(closer:SteamID64(), "cases")
end)
hook.Add("BBX_CaseRated", "Praetor.StaffStats", function(c, stars)
	if not istable(c) or not istable(c.staff) then return end
	P.StaffAdd(tostring(c.staff.s or ""), "stars", math.Clamp(math.floor(tonumber(stars) or 0), 1, 5))
	P.StaffAdd(tostring(c.staff.s or ""), "rated", 1)
end)
hook.Add("Praetor.SitEnded", "Praetor.StaffStats", function(sit)
	for _, sid in ipairs(sit.staffSids or {}) do P.StaffAdd(sid, "sits") end
end)

-- ------------------------------------------------------------------ net

local function dayAgo(n) return tonumber(os.date("%Y%m%d", os.time() - n * 86400)) end

P.Receive("staff_stats", { perm = "staff_stats", rate = 1 }, function(ply, data)
	flush()
	local days = math.floor(tonumber(data.days) or 7)
	if days ~= 1 and days ~= 7 and days ~= 30 and days ~= 0 then days = 7 end
	local from = days == 0 and 0 or dayAgo(days - 1)
	local sums = {}
	for _, f in ipairs(FIELDS) do sums[#sums + 1] = "SUM(" .. f .. ") AS " .. f end
	local rows = P.DB.Query("SELECT sid, MAX(day) AS lastday, " .. table.concat(sums, ", ") .. " FROM praetor_staff_days WHERE day >= ? GROUP BY sid", from) or {}
	local spark = {}
	local first14 = dayAgo(13)
	for _, r in ipairs(P.DB.Query("SELECT sid, day, online FROM praetor_staff_days WHERE day >= ?", first14) or {}) do
		spark[r.sid] = spark[r.sid] or {}
		spark[r.sid][tostring(r.day)] = math.floor((tonumber(r.online) or 0) / 60)
	end
	local list, seen = {}, {}
	local function add(sid, r)
		if seen[sid] then return end
		seen[sid] = true
		local u = P.UserRow(sid) or {}
		local online = P.BySID(sid)
		local e = { sid = sid, name = IsValid(online) and online:Nick() or (u.name or "?"), rank = IsValid(online) and online:GetUserGroup() or (u.rank or "user"),
			last = IsValid(online) and os.time() or tonumber(u.last) or 0, on = IsValid(online) or nil, duty = IsValid(online) and online:GetNW2Bool("pr_duty", false) or nil }
		for _, f in ipairs(FIELDS) do e[f] = math.floor(tonumber(r and r[f]) or 0) end
		e.dutyNow = e.duty
		e.duty = math.floor(tonumber(r and r.duty) or 0)
		local sp = {}
		for i = 13, 0, -1 do sp[#sp + 1] = (spark[sid] or {})[tostring(dayAgo(i))] or 0 end
		e.spark = sp
		list[#list + 1] = e
	end
	for _, r in ipairs(rows) do add(r.sid, r) end
	for _, p in ipairs(player.GetHumans()) do
		if P.IsStaff(p) then add(p:SteamID64(), nil) end
	end
	-- staff ranks that never played in the period also show, so the owner sees who is missing
	local staffRanks = {}
	for name, r in pairs(P.Ranks) do
		local g = P.RankGroupOf(name)
		if (g and g.staff) or (not g and (r.immunity or 0) >= 40) then staffRanks[#staffRanks + 1] = name end
	end
	if #staffRanks > 0 then
		local marks = {}
		for i = 1, #staffRanks do marks[i] = "?" end
		local q = "SELECT sid FROM praetor_users WHERE rank IN (" .. table.concat(marks, ",") .. ") LIMIT 200"
		for _, r in ipairs(P.DB.Query(q, unpack(staffRanks)) or {}) do add(r.sid, nil) end
	end
	-- big servers: keep the most active ones so the message stays small
	if #list > 150 then
		table.sort(list, function(a, b) return (a.on and 1 or 0) * 1e9 + a.online > (b.on and 1 or 0) * 1e9 + b.online end)
		for i = #list, 151, -1 do list[i] = nil end
	end
	P.Send(ply, "staff_stats", { list = list, days = days, inactive = P.Setting("staff_inactive_days") or 7 })
end)
