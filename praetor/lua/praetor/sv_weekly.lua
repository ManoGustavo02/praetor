-- Praetor: weekly report on Discord. Once a week (day and hour in Settings, server
-- time) the webhook gets a summary of the last 7 days: players and new players,
-- the peak online, staff hours and the most active staff, bans / kicks / warnings,
-- reports and how fast they were closed, and how the server ran (tick, time with
-- lag, anti-crash). Numbers that can be compared show the change from the week
-- before. To have the server numbers, the tick and the players online are sampled
-- every 10 seconds and kept per day (praetor_health_days).
local P = Praetor

P.DB.Query([[CREATE TABLE IF NOT EXISTS praetor_health_days (
	day INTEGER PRIMARY KEY, peak INTEGER DEFAULT 0, peak_t INTEGER DEFAULT 0, ms_sum REAL DEFAULT 0,
	ms_n INTEGER DEFAULT 0, worst REAL DEFAULT 0, lag_n INTEGER DEFAULT 0)]])

local DAY = 86400
local function dayOf(t) return tonumber(os.date("%Y%m%d", t)) end
local function midnight(t)
	local d = os.date("*t", t)
	return os.time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

-- ------------------------------------------------------------------ samples

local started = SysTime()
local acc

local function flushHealth()
	if not acc or acc.n + acc.samples == 0 then return end
	P.DB.Query("INSERT OR IGNORE INTO praetor_health_days (day) VALUES (?)", acc.day)
	P.DB.Query("UPDATE praetor_health_days SET ms_sum = ms_sum + ?, ms_n = ms_n + ?, lag_n = lag_n + ?, worst = MAX(worst, ?) WHERE day = ?",
		acc.sum, acc.n, acc.lag, acc.worst, acc.day)
	P.DB.Query("UPDATE praetor_health_days SET peak = ?, peak_t = ? WHERE day = ? AND peak < ?", acc.peak, acc.peakT, acc.day, acc.peak)
	acc = nil
end

timer.Create("Praetor.WeeklySample", 10, 0, function()
	local now = os.time()
	local day = dayOf(now)
	if acc and acc.day ~= day then flushHealth() end
	acc = acc or { day = day, sum = 0, n = 0, lag = 0, worst = 0, peak = 0, peakT = 0, samples = 0 }
	acc.samples = acc.samples + 1
	local online = #player.GetHumans()
	if online > acc.peak then acc.peak, acc.peakT = online, now end
	-- the first minute and a half of a map is loading, not lag
	local ms = P.ACState and tonumber(P.ACState.avg)
	if ms and ms > 0 and SysTime() - started > 90 then
		acc.sum = acc.sum + ms
		acc.n = acc.n + 1
		if ms > acc.worst then acc.worst = ms end
		if ms >= (tonumber(P.Setting("ac_lag_ms")) or 120) then acc.lag = acc.lag + 1 end
	end
end)
timer.Create("Praetor.WeeklyFlush", 60, 0, flushHealth)
hook.Add("ShutDown", "Praetor.Weekly", flushHealth)

-- ------------------------------------------------------------------ numbers

local function num(q, ...)
	local r = P.DB.Row(q, ...)
	if not r then return 0 end
	local _, v = next(r)
	return math.floor(tonumber(v) or 0)
end

local function delta(now, before)
	local d = now - before
	if d == 0 or before == 0 and now == 0 then return "" end
	return " (" .. (d > 0 and "+" or "") .. d .. ")"
end

local function hours(sec) return (string.format("%.1f", (tonumber(sec) or 0) / 3600):gsub("%.0$", "")) end

-- everything from fromT (inclusive) to toT (exclusive), both at midnight
local function collect(fromT, toT)
	local fromD, toD = dayOf(fromT), dayOf(toT)
	local prevT = fromT - 7 * DAY
	local prevD = dayOf(prevT)
	if P.StaffFlush then P.StaffFlush() end
	flushHealth()
	local r = {}
	r.players = num("SELECT COUNT(*) AS n FROM praetor_users WHERE last >= ?", fromT)
	r.new = num("SELECT COUNT(*) AS n FROM praetor_users WHERE first >= ? AND first < ?", fromT, toT)
	r.newPrev = num("SELECT COUNT(*) AS n FROM praetor_users WHERE first >= ? AND first < ?", prevT, fromT)
	r.bans = num("SELECT COUNT(*) AS n FROM praetor_bans WHERE created >= ? AND created < ?", fromT, toT)
	r.bansPrev = num("SELECT COUNT(*) AS n FROM praetor_bans WHERE created >= ? AND created < ?", prevT, fromT)
	r.warns = num("SELECT COUNT(*) AS n FROM praetor_warns WHERE created >= ? AND created < ?", fromT, toT)
	r.opened = num("SELECT COUNT(*) AS n FROM praetor_reports WHERE created >= ? AND created < ?", fromT, toT)
	r.openedPrev = num("SELECT COUNT(*) AS n FROM praetor_reports WHERE created >= ? AND created < ?", prevT, fromT)
	r.closed = num("SELECT COUNT(*) AS n FROM praetor_reports WHERE closed >= ? AND closed < ?", fromT, toT)
	r.closeAvg = num("SELECT AVG(closed - created) AS n FROM praetor_reports WHERE closed >= ? AND closed < ? AND closed > created", fromT, toT)
	r.acActs = num("SELECT COUNT(*) AS n FROM praetor_security WHERE t >= ? AND t < ? AND (kind LIKE 'ac%' OR kind LIKE 'dupe%')", fromT, toT)
	r.alerts = num("SELECT COUNT(*) AS n FROM praetor_security WHERE t >= ? AND t < ? AND NOT (kind LIKE 'ac%' OR kind LIKE 'dupe%')", fromT, toT)

	local st = P.DB.Row([[SELECT SUM(duty) AS duty, SUM(online) AS online, SUM(kicks) AS kicks, SUM(pun) AS pun,
		SUM(reports) + SUM(cases) AS reports FROM praetor_staff_days WHERE day >= ? AND day < ?]], fromD, toD) or {}
	r.duty, r.staffOnline = tonumber(st.duty) or 0, tonumber(st.online) or 0
	r.kicks, r.pun = math.floor(tonumber(st.kicks) or 0), math.floor(tonumber(st.pun) or 0)
	r.top = P.DB.Query([[SELECT sid, SUM(duty) AS duty, SUM(online) AS online, SUM(reports) + SUM(cases) AS reports
		FROM praetor_staff_days WHERE day >= ? AND day < ? GROUP BY sid ORDER BY SUM(duty) DESC, SUM(online) DESC LIMIT 3]], fromD, toD) or {}
	local prevDuty = P.DB.Row("SELECT SUM(duty) AS d FROM praetor_staff_days WHERE day >= ? AND day < ?", prevD, fromD) or {}
	r.dutyPrev = tonumber(prevDuty.d) or 0

	local hd = P.DB.Row("SELECT SUM(ms_sum) AS s, SUM(ms_n) AS n, MAX(worst) AS w, SUM(lag_n) AS lag FROM praetor_health_days WHERE day >= ? AND day < ?", fromD, toD) or {}
	r.msN = tonumber(hd.n) or 0
	r.ms = r.msN > 0 and (tonumber(hd.s) or 0) / r.msN or 0
	r.worst = tonumber(hd.w) or 0
	r.lagMin = math.floor((tonumber(hd.lag) or 0) * 10 / 60 + 0.5)
	local pk = P.DB.Row("SELECT peak, peak_t FROM praetor_health_days WHERE day >= ? AND day < ? ORDER BY peak DESC, peak_t ASC LIMIT 1", fromD, toD)
	r.peak, r.peakT = pk and math.floor(tonumber(pk.peak) or 0) or 0, pk and tonumber(pk.peak_t) or 0
	return r
end

-- ------------------------------------------------------------------ the embed

local function build(fromT, toT)
	local L = P.Setting("webhook_lang")
	local function T(k, a) return P.LText(L, k, a) end
	local r = collect(fromT, toT)
	local fields = {}
	local function field(name, lines)
		fields[#fields + 1] = { name = T(name), value = P.Str(table.concat(lines, "\n"), 1000), inline = name ~= "wk_top" }
	end

	local pl = { T("wk_players_v", { V = r.players, V2 = r.new .. delta(r.new, r.newPrev) }) }
	if r.peak > 0 then pl[#pl + 1] = T("wk_peak", { V = r.peak, S = os.date("%d/%m %H:%M", r.peakT) }) end
	field("wk_players", pl)

	local dutyH, prevH = tonumber(hours(r.duty)) or 0, tonumber(hours(r.dutyPrev)) or 0
	local dd = ""
	if dutyH ~= prevH and (dutyH > 0 or prevH > 0) then dd = " (" .. (dutyH > prevH and "+" or "") .. hours(r.duty - r.dutyPrev) .. " h)" end
	field("wk_staff", { T("wk_staff_v", { V = hours(r.duty) .. dd, V2 = hours(r.staffOnline) }) })

	field("wk_mod", {
		T("wk_mod_v", { V = r.bans .. delta(r.bans, r.bansPrev), V2 = r.kicks, V3 = r.warns }),
		T("wk_mod_v2", { V = r.pun }),
	})

	local rep = { T("wk_reports_v", { V = r.opened .. delta(r.opened, r.openedPrev), V2 = r.closed }) }
	if r.closeAvg > 0 then
		local s = r.closeAvg < 3600 and T("wk_min", { V = math.max(1, math.floor(r.closeAvg / 60 + 0.5)) }) or T("wk_hours", { V = hours(r.closeAvg) })
		rep[#rep + 1] = T("wk_reports_t", { S = s })
	end
	field("wk_reports", rep)

	local sv = {}
	if r.msN > 0 then
		sv[#sv + 1] = T("wk_server_v", { V = string.format("%.1f", r.ms), V2 = math.floor(r.worst + 0.5) })
		sv[#sv + 1] = r.lagMin > 0 and T("wk_server_lag", { V = r.lagMin }) or T("wk_server_ok")
	else
		sv[#sv + 1] = T("wk_nodata")
	end
	sv[#sv + 1] = T("wk_server_ac", { V = r.acActs, V2 = r.alerts })
	field("wk_server", sv)

	local top = {}
	for i, row in ipairs(r.top) do
		if (tonumber(row.duty) or 0) <= 0 and (tonumber(row.online) or 0) <= 0 then break end
		local name = P.KnownName(row.sid) or row.sid
		local key = (tonumber(row.duty) or 0) > 0 and "wk_top_line" or "wk_top_line_on"
		top[#top + 1] = T(key, { V = i, S = (tostring(name):gsub("([\\%*_~`|>])", "\\%1")), V2 = hours((tonumber(row.duty) or 0) > 0 and row.duty or row.online),
			V3 = math.floor(tonumber(row.reports) or 0) })
	end
	if #top == 0 then top[1] = T("wk_top_none") end
	field("wk_top", top)

	return {
		title = T("wk_title"),
		description = T("wk_period", { S = os.date("%d/%m", fromT), S2 = os.date("%d/%m", toT - 1) }) .. "\n" .. T("wk_head", { V = r.players, V2 = r.new }),
		color = 9331455,
		fields = fields,
	}
end

function P.WeeklyReport(fromT, toT, done)
	if not P.WebhookPost then if done then done(0) end return end
	local embed = build(fromT, toT)
	embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
	embed.footer = { text = P.Str(GetHostName(), 120) }
	P.WebhookPost({ embed }, done)
end

-- ------------------------------------------------------------------ schedule

local WDAY = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }

-- the last time the report should have gone out (never in the future)
local function lastSlot(now)
	local t = os.date("*t", now)
	local want = WDAY[P.Setting("webhook_weekly_day")] or 2
	local hour = math.Clamp(math.floor(tonumber(P.Setting("webhook_weekly_hour")) or 12), 0, 23)
	local back = (t.wday - want) % 7
	local slot = os.time({ year = t.year, month = t.month, day = t.day - back, hour = hour, min = 0, sec = 0 })
	if slot > now then slot = os.time({ year = t.year, month = t.month, day = t.day - back - 7, hour = hour, min = 0, sec = 0 }) end
	return slot
end

local function check()
	if not P.Setting("webhook_weekly") or P.Setting("webhook_url") == "" then return end
	local now = os.time()
	local sent = tonumber((P.DB.Get("weekly_sent", {}) or {}).t) or 0
	-- the first time: start counting now, the first report goes at the next slot
	if sent == 0 then P.DB.Set("weekly_sent", { t = now }) return end
	local slot = lastSlot(now)
	if sent >= slot then return end
	P.DB.Set("weekly_sent", { t = now })
	local toT = midnight(slot)
	P.WeeklyReport(toT - 7 * DAY, toT)
end
timer.Create("Praetor.WeeklyCheck", 300, 0, function()
	local ok, err = pcall(check)
	if not ok then ErrorNoHalt("[Praetor] weekly report: " .. tostring(err) .. string.char(10)) end
end)
hook.Add("InitPostEntity", "Praetor.Weekly", function() timer.Simple(90, function() pcall(check) end) end)

-- "send now" in Settings: the last 7 days, today included
P.Receive("webhook_weekly_now", { perm = "settings", owner = true, rate = 0.1 }, function(ply)
	if P.Setting("webhook_url") == "" then P.Notify(ply, "err_webhook_none") return end
	local toT = midnight(os.time()) + DAY
	P.WeeklyReport(toT - 7 * DAY, toT, function(code)
		if not IsValid(ply) then return end
		if code >= 200 and code < 300 then P.Notify(ply, "ok_weekly", nil, "ok")
		else P.Notify(ply, "err_webhook", { V = code == 0 and "-" or code }) end
	end)
end)
