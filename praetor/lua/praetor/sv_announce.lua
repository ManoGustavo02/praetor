-- Praetor: announcements and pop-ups. Saved messages that show up every few
-- minutes, when a player joins, or only when sent by hand. Each one picks where
-- it shows (chat, pop-up in the corner, bar at the top, middle of the screen),
-- its colour, icon (or a drawn one), link, time on screen and who sees it.
local P = Praetor

local MAX = 40
local WHERE = { chat = true, popup = true, banner = true, center = true }
local WHEN = { timer = true, join = true, manual = true }
local WHO = { all = true, staff = true, users = true }
local CORNER = { tr = true, tl = true, br = true, bl = true }

P.AnnList = P.DB.Get("announce", {}) or {}
local nextAt = {}

local function save() P.DB.Set("announce", P.AnnList) end

local function clean(d)
	if not istable(d) then return nil end
	local it = {}
	it.id = isstring(d.id) and d.id:match("^[%w]+$") and #d.id <= 16 and d.id or nil
	it.title = P.Trim(P.Str(d.title, 60))
	it.text = P.Trim(P.Str(d.text, 300))
	if it.title == "" and it.text == "" then return nil end
	local link = P.Trim(P.Str(d.link, 200))
	it.link = link:match("^https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+$") and link or nil
	it.where = WHERE[d.where] and d.where or "popup"
	it.when = WHEN[d.when] and d.when or "timer"
	it.who = WHO[d.who] and d.who or "all"
	it.corner = CORNER[d.corner] and d.corner or "br"
	it.every = math.Clamp(math.floor(tonumber(d.every) or 10), 1, 240)
	it.life = math.Clamp(math.floor(tonumber(d.life) or 10), 3, 60)
	local c = istable(d.col) and d.col or {}
	it.col = { r = math.Clamp(math.floor(tonumber(c.r) or 92), 0, 255), g = math.Clamp(math.floor(tonumber(c.g) or 132), 0, 255), b = math.Clamp(math.floor(tonumber(c.b) or 255), 0, 255) }
	it.icon = isstring(d.icon) and d.icon:match("^[%w_]+$") and #d.icon <= 32 and d.icon or "megaphone"
	it.snd = d.snd ~= false
	it.on = d.on ~= false
	return it
end

local function audience(it)
	if it.who == "all" then return nil end
	local out = {}
	for _, p in ipairs(player.GetHumans()) do
		local staff = P.IsStaff(p)
		if (it.who == "staff" and staff) or (it.who == "users" and not staff) then out[#out + 1] = p end
	end
	return out
end

local function payload(it, by)
	return { title = it.title, text = it.text, link = it.link, where = it.where, corner = it.corner, life = it.life, col = it.col, icon = it.icon, snd = it.snd and 1 or nil, by = by }
end

function P.ShowAnnouncement(it, target, by)
	if target == nil then
		local to = audience(it)
		if to and #to == 0 then return end
		P.Send(to, "ann_show", payload(it, by))
	else
		P.Send(target, "ann_show", payload(it, by))
	end
end

-- the scheduler: each message has its own clock
timer.Create("Praetor.Announce", 5, 0, function()
	if #player.GetHumans() == 0 then return end
	local now = CurTime()
	for i, it in ipairs(P.AnnList) do
		if it.on and it.when == "timer" then
			-- the first round is spread out so they do not all show at once
			if not nextAt[it.id] then nextAt[it.id] = now + it.every * 60 * 0.5 + i * 20 end
			if now >= nextAt[it.id] then
				nextAt[it.id] = now + it.every * 60
				P.ShowAnnouncement(it)
			end
		end
	end
end)

hook.Add("Praetor.UserLoaded", "Praetor.Announce", function(ply)
	local list = {}
	for _, it in ipairs(P.AnnList) do
		if it.on and it.when == "join" then list[#list + 1] = it end
	end
	for i, it in ipairs(list) do
		timer.Simple(6 + (i - 1) * 4, function()
			if not IsValid(ply) then return end
			local staff = P.IsStaff(ply)
			if it.who == "all" or (it.who == "staff" and staff) or (it.who == "users" and not staff) then
				P.ShowAnnouncement(it, ply)
			end
		end)
	end
end)

-- ------------------------------------------------------------------ net

local function sendList(ply) P.Send(ply, "ann_list", { list = P.AnnList }) end

P.Receive("ann_list", { perm = "manage_announce", rate = 2 }, function(ply) sendList(ply) end)

P.Receive("ann_save", { perm = "manage_announce", rate = 3, max = 8192 }, function(ply, data)
	local it = clean(data.it)
	if not it then P.Notify(ply, "err_missing") return end
	local idx
	if it.id then
		for i, o in ipairs(P.AnnList) do if o.id == it.id then idx = i end end
	end
	if not idx then
		if #P.AnnList >= MAX then P.Notify(ply, "an_full", { V = MAX }, "warn") return end
		it.id = string.format("%x%x", os.time() % 0xFFFFFF, math.random(0, 0xFFFF))
		P.AnnList[#P.AnnList + 1] = it
	else
		P.AnnList[idx] = it
	end
	nextAt[it.id] = nil
	save()
	P.Log("settings", "l_ann_save", { A = P.LogPly(ply), V = it.title ~= "" and it.title or it.text }, { ply })
	P.Notify(ply, "an_saved", nil, "ok")
	sendList(ply)
	P.Send(ply, "ann_saved", { id = it.id })
end)

P.Receive("ann_del", { perm = "manage_announce", rate = 3 }, function(ply, data)
	for i, o in ipairs(P.AnnList) do
		if o.id == data.id then
			table.remove(P.AnnList, i)
			nextAt[o.id] = nil
			save()
			P.Log("settings", "l_ann_del", { A = P.LogPly(ply), V = o.title ~= "" and o.title or o.text }, { ply })
			break
		end
	end
	sendList(ply)
end)

P.Receive("ann_move", { perm = "manage_announce", rate = 6 }, function(ply, data)
	local from = math.floor(tonumber(data.i) or 0)
	local to = from + (data.d == 1 and 1 or -1)
	if P.AnnList[from] and P.AnnList[to] then
		P.AnnList[from], P.AnnList[to] = P.AnnList[to], P.AnnList[from]
		save()
	end
	sendList(ply)
end)

-- sends a message now (saved or not) to its audience
P.Receive("ann_send", { perm = { "announce", "manage_announce" }, rate = 1, max = 8192 }, function(ply, data)
	local it = clean(data.it)
	if not it then P.Notify(ply, "err_missing") return end
	P.ShowAnnouncement(it, nil, P.NameOf(ply))
	P.Log("chat", "l_announce", { A = P.LogPly(ply), V = it.title ~= "" and (it.title .. ": " .. it.text) or it.text }, { ply })
	P.Notify(ply, "an_sent", nil, "ok")
end)
