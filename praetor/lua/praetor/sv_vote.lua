-- Praetor: votes. A poll with the question and options the staff writes, a
-- map vote with pictures of the maps and a "keep the current map" card, and
-- player votes (!votekick, !voteban, !votemute, !votecleanup...). Results are
-- live; a vote is final (the window closes and it can't be changed).
--
-- Other addons: hook "Praetor.VoteEnded" (kind, question, options, counts, winnerIndex)
local P = Praetor

local KEEP = "__keep"
local MAX_OPTS = 9
local vote
local history = P.DB.Get("vote_history", {}) or {}
local pendingMap

local CFG_DEFAULT = { pool = {}, keep = true, dur = 30, delay = 10, max = 6 }
P.MapVoteCfg = P.DB.Get("mapvote", nil) or table.Copy(CFG_DEFAULT)
for k, v in pairs(CFG_DEFAULT) do if P.MapVoteCfg[k] == nil then P.MapVoteCfg[k] = v end end

-- ------------------------------------------------------------------ maps

local mapCache, mapCacheT = nil, 0
function P.MapList()
	if mapCache and mapCacheT > CurTime() then return mapCache end
	local out = {}
	for _, f in ipairs(file.Find("maps/*.bsp", "GAME")) do
		local m = f:gsub("%.bsp$", ""):lower()
		-- menu backgrounds and engine test maps are not real choices
		if not m:match("^background%d") and not m:match("^devtest") and not m:match("^test_") and m:match("^[%w_%-%.]+$") then
			out[#out + 1] = m
		end
	end
	table.sort(out)
	mapCache, mapCacheT = out, CurTime() + 60
	return out
end

local function mapExists(m)
	return isstring(m) and m:match("^[%w_%-%.]+$") and file.Exists("maps/" .. m .. ".bsp", "GAME")
end

-- ------------------------------------------------------------------ state

local function counts()
	local c = {}
	for i = 1, #vote.o do c[i] = 0 end
	for _, i in pairs(vote.votes) do c[i] = (c[i] or 0) + 1 end
	return c
end

-- the first few voters of each option, for the little avatars
local function voters()
	local v = {}
	for sid, i in pairs(vote.votes) do
		v[i] = v[i] or {}
		if #v[i] < 6 then v[i][#v[i] + 1] = sid end
	end
	return v
end

local function public()
	return {
		id = vote.id, kind = vote.kind, q = vote.q, o = vote.o, yn = vote.yn and 1 or nil, act = vote.act,
		d = math.max(0, vote.ends - CurTime()), dur = vote.dur, n = vote.by,
		c = counts(), v = voters(), cur = game.GetMap(),
	}
end

local function sidOf(ply)
	return ply:IsBot() and ("BOT_" .. ply:EntIndex()) or ply:SteamID64()
end

local function pushHistory(entry)
	table.insert(history, 1, entry)
	while #history > 15 do table.remove(history) end
	P.DB.Set("vote_history", history)
end

local function finish(cancelledBy)
	if not vote then return end
	timer.Remove("Praetor.Vote")
	timer.Remove("Praetor.VoteLive")
	local v = vote
	vote = nil
	local c = {}
	for i = 1, #v.o do c[i] = 0 end
	for _, i in pairs(v.votes) do c[i] = (c[i] or 0) + 1 end
	local total, best, tied = 0, -1, {}
	for i, n in ipairs(c) do
		total = total + n
		if n > best then best, tied = n, { i } elseif n == best then tied[#tied + 1] = i end
	end
	local win
	local passed
	if v.act and not cancelledBy then
		-- player vote: enough "yes" (setting pv_ratio, % of who voted) and at
		-- least pv_min_votes of them
		local yes, no = c[1] or 0, c[2] or 0
		local ratio = math.Clamp(P.Setting("pv_ratio"), 1, 100) / 100
		passed = yes > 0 and yes / math.max(1, yes + no) >= ratio and yes >= math.max(1, P.Setting("pv_min_votes"))
		win = (yes + no) > 0 and (passed and 1 or 2) or nil
	elseif cancelledBy then
		win = nil
	elseif total == 0 then
		-- nobody voted: a map vote keeps the map, a poll has no winner
		if v.kind == "map" then
			for i, o in ipairs(v.o) do if o == KEEP then win = i end end
		end
	elseif #tied > 1 and v.kind == "map" then
		-- a tie between maps: the current map wins if it is in the tie, else a random one
		for _, i in ipairs(tied) do if v.o[i] == KEEP then win = i end end
		win = win or tied[math.random(#tied)]
	elseif #tied == 1 then
		win = tied[1]
	end
	local go
	if win and v.kind == "map" and v.o[win] ~= KEEP and mapExists(v.o[win]) then
		go = math.Clamp(tonumber(P.MapVoteCfg.delay) or 10, 3, 60)
		pendingMap = v.o[win]
		timer.Create("Praetor.MapVoteChange", go, 1, function()
			if pendingMap then RunConsoleCommand("changelevel", pendingMap) end
		end)
	end
	P.Send(nil, "vote_end", {
		id = v.id, kind = v.kind, q = v.q, o = v.o, yn = v.yn and 1 or nil, c = c, w = win, tie = (not v.act) and #tied > 1 and total > 0 and 1 or nil,
		act = v.act, pass = passed and 1 or nil,
		x = cancelledBy and P.NameOf(cancelledBy) or nil, go = go, cur = game.GetMap(),
	})
	if cancelledBy then
		P.Log("chat", "l_vote_cancel", { A = P.LogPly(cancelledBy), V = v.q }, { cancelledBy })
		return
	end
	local wtext = win and (v.o[win] == KEEP and game.GetMap() or v.o[win]) or "-"
	P.Log("chat", "l_vote_end", { V = v.q, V2 = wtext .. " (" .. (win and c[win] or 0) .. "/" .. total .. ")" })
	pushHistory({ kind = v.kind, q = v.q, o = v.o, yn = v.yn and 1 or nil, c = c, w = win, by = v.by, t = os.time(), cur = game.GetMap(), act = v.act })
	hook.Run("Praetor.VoteEnded", v.kind, v.q, v.o, c, win)
	if v.act and v.run then
		if passed then v.run() else P.Send(nil, "notify", { k = "pv_failed", a = { S = v.act.n or "" } }) end
	end
end

-- kind "poll": question + options (less than 2 options = yes / no)
-- kind "map": options are map names, KEEP is the "keep this map" card
-- extra: fields copied into the vote (player votes: act, target, run)
function P.StartVote(caller, question, opts, dur, kind, extra)
	if vote then return false end
	kind = kind == "map" and "map" or "poll"
	local yn = kind == "poll" and #opts < 2
	if yn then opts = { "yes", "no" } end
	dur = math.Clamp(math.floor(tonumber(dur) or (kind == "map" and P.MapVoteCfg.dur or 30)), 10, 300)
	vote = {
		id = math.random(1, 2 ^ 30), kind = kind, q = question, o = opts, yn = yn, votes = {},
		by = P.NameOf(caller), dur = dur, ends = CurTime() + dur,
	}
	if istable(extra) then for k, v in pairs(extra) do vote[k] = v end end
	P.Send(nil, "vote", public())
	P.Log("chat", kind == "map" and "l_mapvote" or "l_vote", { A = P.LogPly(caller), V = question }, { caller })
	timer.Create("Praetor.Vote", dur, 1, function() finish() end)
	-- live results, at most twice a second
	timer.Create("Praetor.VoteLive", 0.5, 0, function()
		if not vote then timer.Remove("Praetor.VoteLive") return end
		if not vote.dirty then return end
		vote.dirty = nil
		P.Send(nil, "vote_upd", { id = vote.id, c = counts(), v = voters() })
	end)
	return true
end

function P.StopVote(caller)
	if not vote then return false end
	finish(IsValid(caller) and caller or game.GetWorld())
	return true
end

function P.VoteRunning() return vote ~= nil end

-- picks the maps of the vote from the pool (or every map) and starts it
function P.StartMapVote(caller, dur)
	if vote then return false, "err_vote_running" end
	local cfg = P.MapVoteCfg
	local cur = game.GetMap():lower()
	local pool = {}
	local src = (istable(cfg.pool) and #cfg.pool > 0) and cfg.pool or P.MapList()
	for _, m in ipairs(src) do
		if m ~= cur and mapExists(m) then pool[#pool + 1] = m end
	end
	if #pool == 0 and not cfg.keep then return false, "err_mapvote_empty" end
	local max = math.Clamp(math.floor(tonumber(cfg.max) or 6), 2, MAX_OPTS) - (cfg.keep and 1 or 0)
	-- random maps when the pool is bigger than the cards
	local opts = {}
	local shuffled = table.Copy(pool)
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	for i = 1, math.min(max, #shuffled) do opts[#opts + 1] = shuffled[i] end
	table.sort(opts)
	if cfg.keep then opts[#opts + 1] = KEEP end
	if #opts < 2 then return false, "err_mapvote_empty" end
	return P.StartVote(caller, "map", opts, dur or cfg.dur, "map")
end

-- ------------------------------------------------------------------ net

-- map -> Workshop id of the addons mounted on the server, so the clients can
-- show the Workshop picture of maps that have no thumbnail of their own
local mapWS
function P.MapWorkshopIds()
	if mapWS then return mapWS end
	mapWS = {}
	local ok, addons = pcall(engine.GetAddons)
	for _, a in ipairs(ok and istable(addons) and addons or {}) do
		local id = tostring(a.wsid or "")
		if a.mounted ~= false and id:match("^%d+$") and id ~= "0" and isstring(a.title) then
			local fok, found = pcall(file.Find, "maps/*.bsp", a.title)
			for _, f in ipairs(fok and istable(found) and found or {}) do
				local m = f:lower():gsub("%.bsp$", "")
				if not mapWS[m] then mapWS[m] = id end
			end
		end
	end
	return mapWS
end

-- the client asks again once it is loaded (a message sent at the first spawn can be lost)
P.Receive("map_ws", { rate = 1 }, function(ply)
	if ply.PraetorGotMapWS then return end
	ply.PraetorGotMapWS = true
	local ws = P.MapWorkshopIds()
	if next(ws) then P.Send(ply, "map_ws", { m = ws }) end
end)

hook.Add("Praetor.UserLoaded", "Praetor.Vote", function(ply)
	if not IsValid(ply) then return end
	local ws = P.MapWorkshopIds()
	if next(ws) then P.Send(ply, "map_ws", { m = ws }) end
	if vote then P.Send(ply, "vote", public()) end
end)

P.Receive("vote_answer", { rate = 4 }, function(ply, data)
	if not vote or (data.id and data.id ~= vote.id) then return end
	local i = math.floor(tonumber(data.i) or 0)
	if i < 1 or i > #vote.o then return end
	local sid = sidOf(ply)
	-- a vote is final; the player who is being voted on does not vote
	if vote.votes[sid] then return end
	if vote.target and vote.target == sid then return end
	vote.votes[sid] = i
	vote.dirty = true
end)

local function cleanOpts(list)
	local out = {}
	if not istable(list) then return out end
	for _, o in ipairs(list) do
		local t = P.Trim(P.Str(o, 40))
		if t ~= "" and #out < 8 then out[#out + 1] = t end
	end
	return out
end

P.Receive("vote_start", { perm = "vote", rate = 1 }, function(ply, data)
	local q = P.Trim(P.Str(data.q, 120))
	if q == "" then P.Notify(ply, "err_missing") return end
	if not P.StartVote(ply, q, cleanOpts(data.o), data.d, "poll") then P.Notify(ply, "err_vote_running", nil, "warn") end
end)

P.Receive("mapvote_start", { perm = "mapvote", rate = 1 }, function(ply, data)
	local ok, err = P.StartMapVote(ply, data.d)
	if not ok then P.Notify(ply, err or "err_vote_running", nil, "warn") end
end)

P.Receive("vote_cancel", { perm = { "vote", "mapvote", "stopvote" }, rate = 2 }, function(ply)
	if not P.StopVote(ply) then
		-- no vote running: maybe a map change is waiting
		if pendingMap and P.Has(ply, "mapvote") then
			timer.Remove("Praetor.MapVoteChange")
			P.Log("chat", "l_mapvote_abort", { A = P.LogPly(ply), V = pendingMap }, { ply })
			pendingMap = nil
			P.Send(nil, "vote_abort", { n = P.NameOf(ply) })
		end
	end
end)

P.Receive("mapvote_cfg", { perm = "mapvote", rate = 2 }, function(ply, data)
	local cfg = { pool = {}, keep = data.keep ~= false, dur = math.Clamp(math.floor(tonumber(data.dur) or 30), 10, 300),
		delay = math.Clamp(math.floor(tonumber(data.delay) or 10), 3, 60), max = math.Clamp(math.floor(tonumber(data.max) or 6), 2, MAX_OPTS) }
	if istable(data.pool) then
		local seen = {}
		for _, m in ipairs(data.pool) do
			m = isstring(m) and m:lower() or ""
			if not seen[m] and mapExists(m) and #cfg.pool < 300 then seen[m] = true cfg.pool[#cfg.pool + 1] = m end
		end
	end
	P.MapVoteCfg = cfg
	P.DB.Set("mapvote", cfg)
	P.Log("settings", "l_mapvote_cfg", { A = P.LogPly(ply), V = #cfg.pool }, { ply })
	P.Notify(ply, "mv_saved", nil, "ok")
	P.Send(ply, "vote_info", { maps = P.MapList(), cfg = cfg, hist = history, cur = game.GetMap(), run = vote and public() or nil, pend = pendingMap })
end)

P.Receive("vote_info", { perm = { "vote", "mapvote" }, rate = 2 }, function(ply)
	P.Send(ply, "vote_info", { maps = P.MapList(), cfg = P.MapVoteCfg, hist = history, cur = game.GetMap(), run = vote and public() or nil, pend = pendingMap })
end)

-- ------------------------------------------------------------------ player votes
-- !votekick / !voteban / !votemute / !voteclearprops <player> [reason],
-- !votecleanup and !votefreeze. Yes / no; it passes with pv_ratio % of yes
-- among who voted and at least pv_min_votes yes.

local pvLast, pvTarget = {}, {}

local function humans() return #player.GetHumans() end

local function staffOnline()
	for _, p in ipairs(player.GetHumans()) do if P.IsStaff(p) then return true end end
	return false
end

-- act: kick / ban / mute / clearprops / cleanup / freeze
function P.StartPlayerVote(caller, act, target, reason)
	if not P.Setting("pv_enabled") then return false, "err_pv_off" end
	if vote then return false, "err_vote_running" end
	if humans() < P.Setting("pv_min_players") then return false, "err_pv_players", { V = P.Setting("pv_min_players") } end
	if P.Setting("pv_no_staff") and staffOnline() and not (IsValid(caller) and P.IsStaff(caller)) then return false, "err_pv_staff_on" end
	local key = IsValid(caller) and caller:SteamID64() or "console"
	local cd = P.Setting("pv_cooldown")
	if (pvLast[key] or 0) > CurTime() and not (IsValid(caller) and P.IsStaff(caller)) then
		return false, "err_pv_wait", { V = math.ceil(pvLast[key] - CurTime()) }
	end
	local tname, tsid
	if target then
		if not IsValid(target) then return false, "err_no_target" end
		if P.IsOwner(target) or P.IsStaff(target) then return false, "err_pv_protected", { S = target:Nick() } end
		tname, tsid = target:Nick(), sidOf(target)
		if (pvTarget[tsid] or 0) > CurTime() then return false, "err_pv_target_wait", { S = tname, V = math.ceil(pvTarget[tsid] - CurTime()) } end
	end
	reason = P.Trim(P.Str(reason or "", 80))
	local q = act .. (tname and (" " .. tname) or "") .. (reason ~= "" and (" (" .. reason .. ")") or "")
	-- the ban of a vote follows the rank of who started it: never longer than
	-- that rank's longest ban, and never permanent unless the staff started it
	local banMin = math.floor(tonumber(P.Setting("pv_ban_min")) or 60)
	if IsValid(caller) and not P.IsOwner(caller) then
		local limit = P.RankOf(caller).ban_limit or 0
		if banMin <= 0 and not P.IsStaff(caller) then banMin = limit > 0 and limit or 1440 end
		if limit > 0 and (banMin <= 0 or banMin > limit) then banMin = limit end
	end
	local why = reason ~= "" and reason or P.LText(P.Setting("lang") == "pt" and "pt" or "en", "pv_reason")
	local function run()
		if act == "cleanup" then
			game.CleanUpMap()
		elseif act == "freeze" then
			for _, e in ipairs(ents.GetAll()) do
				if IsValid(e) and not e:IsPlayer() and not e:IsWorld() then
					local phys = e:GetPhysicsObject()
					if IsValid(phys) and phys:IsMoveable() then phys:EnableMotion(false) end
				end
			end
		elseif IsValid(target) then
			if act == "kick" then target:Kick("[Praetor] " .. why)
			elseif act == "ban" then P.AddBan(target:SteamID64(), tname, banMin, why, "Vote")
			elseif act == "mute" then P.SetMute(target, 10, nil)
			elseif act == "clearprops" then P.ClearProps(target) end
		elseif act == "ban" and tsid and tsid:match("^%d+$") then
			-- left before the end of the vote: still banned
			P.AddBan(tsid, tname, banMin, why, "Vote")
		end
		P.Log("punish", "l_pv_done", { V = act, S = tname or "-", V2 = why })
		P.Send(nil, "notify", { k = "pv_done_" .. act, a = { S = tname or "", V = banMin }, kind = "ok" })
	end
	local extra = { act = { a = act, n = tname, r = reason ~= "" and reason or nil, t = tsid }, target = tsid, run = run }
	if not P.StartVote(caller, q, {}, P.Setting("pv_time"), "poll", extra) then return false, "err_vote_running" end
	pvLast[key] = CurTime() + cd
	if tsid then pvTarget[tsid] = CurTime() + cd * 2 end
	P.Log("chat", "l_pv_start", { A = P.LogPly(caller), V = act, S = tname or "-" }, { caller, target })
	return true
end
