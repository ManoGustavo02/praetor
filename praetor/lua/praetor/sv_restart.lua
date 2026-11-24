-- Praetor: scheduled restart.
--  * times of the day (server clock) when the map reloads or the server restarts
--  * warnings before it (chat + card + sound), a countdown in the last minute
--  * players can vote to postpone it a few times (setting in the tab)
--  * staff can restart in N minutes, skip the next one or cancel
-- Other addons: hook "Praetor.BeforeRestart" (mode) runs a few seconds before.
local P = Praetor

local DEFAULT = { times = {}, mode = "map", warn = { 15, 10, 5, 1 }, vote = true, delay = 15, maxDelay = 2 }
P.RestartCfg = P.DB.Get("restart", nil) or table.Copy(DEFAULT)
for k, v in pairs(DEFAULT) do if P.RestartCfg[k] == nil then P.RestartCfg[k] = v end end

-- state of the next restart
local R = { at = nil, why = nil, delays = 0, warned = {}, skip = nil, by = nil }
P.RestartState = R

local function save() P.DB.Set("restart", P.RestartCfg) end

-- "04:30" -> next timestamp for that time (today or tomorrow)
local function nextOf(hhmm, from)
	local h, m = tostring(hhmm):match("^(%d%d?):(%d%d)$")
	h, m = tonumber(h), tonumber(m)
	if not h or h > 23 or m > 59 then return nil end
	local d = os.date("*t", from)
	d.hour, d.min, d.sec = h, m, 0
	local t = os.time(d)
	if t <= from + 30 then
		d.day = d.day + 1
		t = os.time(d)
	end
	return t
end

-- the next scheduled time (skipping the one the staff skipped)
local function nextScheduled(from)
	local best
	for _, hm in ipairs(P.RestartCfg.times or {}) do
		local t = nextOf(hm, from)
		if t and t ~= R.skip and (not best or t < best) then best = t end
	end
	return best
end

local function public()
	return {
		at = R.at, left = R.at and (R.at - os.time()) or nil, why = R.why, mode = P.RestartCfg.mode,
		delays = R.delays, maxDelay = P.RestartCfg.maxDelay, by = R.by, warn = P.RestartCfg.warn,
	}
end

local function broadcast() P.Send(nil, "rst_state", public()) end

local function plan()
	if R.why == "manual" and R.at and R.at > os.time() then return end
	local t = nextScheduled(os.time())
	R.at = t
	R.why = t and "schedule" or nil
	R.by = nil
	R.delays = 0
	R.warned = {}
	R.voted = nil
	broadcast()
end
P.RestartPlan = plan

function P.RestartIn(ply, minutes)
	minutes = math.Clamp(math.floor(tonumber(minutes) or 5), 0, 24 * 60)
	R.at = os.time() + minutes * 60
	R.why = "manual"
	R.by = P.NameOf(ply)
	R.delays = 0
	R.warned = {}
	R.voted = nil
	P.Log("settings", "l_rst_manual", { A = P.LogPly(ply), V = minutes }, { ply })
	broadcast()
	return true
end

function P.RestartCancel(ply)
	if not R.at then return false end
	if R.why == "schedule" then R.skip = R.at end
	P.Log("settings", "l_rst_cancel", { A = P.LogPly(ply) }, { ply })
	R.why = nil
	R.at = nil
	plan()
	P.Send(nil, "rst_cancel", { n = P.NameOf(ply) })
	return true
end

local function doRestart()
	local mode = P.RestartCfg.mode
	hook.Run("Praetor.BeforeRestart", mode)
	P.Log("settings", "l_rst_done", { V = mode })
	R.at = nil
	R.why = nil
	if mode == "server" then
		-- the process restarts (the host / srcds watchdog brings it back)
		RunConsoleCommand("_restart")
	else
		RunConsoleCommand("changelevel", game.GetMap())
	end
end

-- ------------------------------------------------------------------ postpone vote

local voteQ
local function startPostponeVote()
	if not P.RestartCfg.vote or R.delays >= (P.RestartCfg.maxDelay or 0) or not P.StartVote then return end
	if P.VoteRunning and P.VoteRunning() then return end
	local lang = P.Setting("lang") == "pt" and "pt" or "en"
	voteQ = P.LText(lang, "rst_vote_q", { V = P.RestartCfg.delay })
	P.StartVote(nil, voteQ, {}, 30, "poll")
end

hook.Add("Praetor.VoteEnded", "Praetor.Restart", function(kind, q, opts, counts, win)
	if not voteQ or q ~= voteQ then return end
	voteQ = nil
	if win == 1 and R.at then
		R.delays = R.delays + 1
		R.at = R.at + (P.RestartCfg.delay or 15) * 60
		R.warned = {}
	R.voted = nil
		P.Log("settings", "l_rst_delay", { V = P.RestartCfg.delay })
		P.Send(nil, "rst_delayed", { v = P.RestartCfg.delay })
		broadcast()
	end
end)

-- ------------------------------------------------------------------ clock

timer.Create("Praetor.Restart", 1, 0, function()
	if not R.at then
		-- a time was added / the day changed
		if R.why == nil and #(P.RestartCfg.times or {}) > 0 and (R.nextPlan or 0) < os.time() then
			R.nextPlan = os.time() + 30
			plan()
		end
		return
	end
	local left = R.at - os.time()
	if left <= 0 then doRestart() return end
	-- the postpone vote opens once per countdown, 5 minutes before (or at once
	-- when a restart is set for less than that), whatever warnings are picked
	if left <= 300 and left > 45 and not R.voted then
		R.voted = true
		startPostponeVote()
	end
	for _, m in ipairs(P.RestartCfg.warn or {}) do
		if left <= m * 60 and left > m * 60 - 5 and not R.warned[m] then
			R.warned[m] = true
			P.Send(nil, "rst_warn", { m = m, left = left, mode = P.RestartCfg.mode })
		end
	end
	if left == 10 then P.Send(nil, "rst_state", public()) end
end)

hook.Add("InitPostEntity", "Praetor.Restart", function() timer.Simple(2, plan) end)
hook.Add("Praetor.UserLoaded", "Praetor.Restart", function(ply)
	if IsValid(ply) then P.Send(ply, "rst_state", public()) end
end)
timer.Simple(3, function() if not R.at then plan() end end)

-- ------------------------------------------------------------------ net

local function info(ply)
	P.Send(ply, "rst_info", { cfg = P.RestartCfg, st = public(), now = os.time(), clock = os.date("%H:%M") })
end

P.Receive("rst_info", { perm = "manage_restart", rate = 2 }, function(ply) info(ply) end)

P.Receive("rst_cfg", { perm = "manage_restart", rate = 2 }, function(ply, data)
	local cfg = { times = {}, warn = {} }
	local seen = {}
	for _, t in ipairs(istable(data.times) and data.times or {}) do
		local h, m = tostring(t):match("^(%d%d?):(%d%d)$")
		h, m = tonumber(h), tonumber(m)
		if h and h <= 23 and m <= 59 then
			local s = string.format("%02d:%02d", h, m)
			if not seen[s] and #cfg.times < 12 then seen[s] = true cfg.times[#cfg.times + 1] = s end
		end
	end
	table.sort(cfg.times)
	local wseen = {}
	for _, w in ipairs(istable(data.warn) and data.warn or {}) do
		w = math.floor(tonumber(w) or 0)
		if w >= 1 and w <= 120 and not wseen[w] and #cfg.warn < 8 then wseen[w] = true cfg.warn[#cfg.warn + 1] = w end
	end
	table.sort(cfg.warn, function(a, b) return a > b end)
	cfg.mode = data.mode == "server" and "server" or "map"
	cfg.vote = data.vote == true
	cfg.delay = math.Clamp(math.floor(tonumber(data.delay) or 15), 1, 120)
	cfg.maxDelay = math.Clamp(math.floor(tonumber(data.maxDelay) or 2), 0, 10)
	P.RestartCfg = cfg
	save()
	R.skip = nil
	if R.why ~= "manual" then R.at = nil R.why = nil plan() end
	P.Log("settings", "l_rst_cfg", { A = P.LogPly(ply), V = table.concat(cfg.times, ", ") }, { ply })
	P.Notify(ply, "ok_saved", nil, "ok")
	info(ply)
end)

P.Receive("rst_now", { perm = "manage_restart", rate = 1 }, function(ply, data)
	P.RestartIn(ply, data.min)
	P.Notify(ply, "n_rst_set", { V = math.floor(tonumber(data.min) or 5) }, "ok")
	info(ply)
end)

P.Receive("rst_skip", { perm = "manage_restart", rate = 1 }, function(ply)
	if not P.RestartCancel(ply) then P.Notify(ply, "err_rst_none") end
	info(ply)
end)
