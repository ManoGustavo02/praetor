-- Praetor: support rooms ("sits"). A staff member takes the players of a report
-- to a quiet room, talks, decides, and everyone goes back to where they were.
--  * rooms are saved per map: stand somewhere and use !setsit, or create them
--    in the "Support rooms" tab;
--  * with no free room the server builds one up in the sky: a floor and four
--    walls, only where there is open sky and nothing in the way (never inside
--    walls or buildings);
--  * works with Praetor reports and with Blackbox cases: !sit with no name uses
--    the case you claimed, Blackbox's "Return" button and closing the case end
--    the room, and the positions are also written into the case so Blackbox can
--    send people back by itself.
local P = Praetor

P.Sits = P.Sits or {}
local MAX_ROOMS = 10
local PLATE = "models/hunter/plates/plate8x8.mdl"
local HALF = 189.8
local nextId = 1

-- names made by the server follow the server language
local function srvLang() return P.Setting("lang") == "pt" and "pt" or "en" end

-- ------------------------------------------------------------------ saved rooms (per map)

local function roomKey() return "sits_" .. game.GetMap():lower() end

function P.LoadSitRooms()
	local list = P.DB.Get(roomKey(), {})
	P.SitRooms = {}
	for _, r in ipairs(istable(list) and list or {}) do
		if istable(r) and istable(r.pos) and tonumber(r.pos[1]) then
			P.SitRooms[#P.SitRooms + 1] = { id = tostring(r.id or #P.SitRooms + 1), name = P.Str(r.name or "", 32), pos = { tonumber(r.pos[1]), tonumber(r.pos[2]), tonumber(r.pos[3]) }, yaw = tonumber(r.yaw) or 0, by = r.by }
		end
	end
end
P.LoadSitRooms()

local function saveRooms() P.DB.Set(roomKey(), P.SitRooms) end
local function vec(t) return Vector(t[1], t[2], t[3]) end

local function roomById(id)
	for i, r in ipairs(P.SitRooms) do if r.id == id then return r, i end end
end

local function roomBusy(id)
	for _, s in pairs(P.Sits) do if s.room.id == id then return s end end
end

function P.AddSitRoom(ply, name)
	if #P.SitRooms >= MAX_ROOMS then return false, "err_sit_full" end
	local pos = ply:GetPos()
	local id = tostring(os.time()) .. math.random(100, 999)
	name = P.Trim(P.Str(name or "", 32))
	if name == "" then name = P.LText(srvLang(), "sit_room_n", { V = #P.SitRooms + 1 }) end
	P.SitRooms[#P.SitRooms + 1] = { id = id, name = name, pos = { math.Round(pos.x, 1), math.Round(pos.y, 1), math.Round(pos.z, 1) }, yaw = math.Round(ply:EyeAngles().y), by = ply:Nick() }
	saveRooms()
	P.Log("report", "l_sit_room", { A = P.LogPly(ply), V = name, V2 = game.GetMap() }, { ply })
	return true, name
end

-- ------------------------------------------------------------------ a room in the sky

local SPAWNS = { "info_player_start", "info_player_deathmatch", "info_player_combine", "info_player_rebel",
	"info_player_terrorist", "info_player_counterterrorist", "gmod_player_start", "info_player_teamspawn" }

local function hullFree(c)
	local tr = util.TraceHull({ start = c + Vector(0, 0, 8), endpos = c + Vector(0, 0, 8), mins = Vector(-HALF - 10, -HALF - 10, 0), maxs = Vector(HALF + 10, HALF + 10, 400), mask = MASK_SOLID })
	return not tr.Hit and not tr.StartSolid
end

local function inWorld(c)
	for _, o in ipairs({ Vector(0, 0, 20), Vector(HALF, HALF, 20), Vector(-HALF, HALF, 20), Vector(HALF, -HALF, 20), Vector(-HALF, -HALF, 20), Vector(0, 0, 390) }) do
		if not util.IsInWorld(c + o) then return false end
	end
	return true
end

local function skySpot(near)
	local origins = {}
	if near then origins[#origins + 1] = near end
	for _, cls in ipairs(SPAWNS) do
		for _, e in ipairs(ents.FindByClass(cls)) do
			if #origins < 24 then origins[#origins + 1] = e:GetPos() end
		end
	end
	for _, p in ipairs(player.GetAll()) do if #origins < 40 then origins[#origins + 1] = p:GetPos() end end
	local offs = { Vector(0, 0, 0) }
	for _, d in ipairs({ 900, 1800 }) do
		for _, a in ipairs({ 0, 45, 90, 135, 180, 225, 270, 315 }) do
			local r = math.rad(a)
			offs[#offs + 1] = Vector(math.cos(r) * d, math.sin(r) * d, 0)
		end
	end
	local tries = 0
	for _, o in ipairs(origins) do
		for _, off in ipairs(offs) do
			tries = tries + 1
			if tries > 300 then return nil end
			local start = o + off + Vector(0, 0, 64)
			if util.IsInWorld(start) then
				local tr = util.TraceLine({ start = start, endpos = start + Vector(0, 0, 32768), mask = MASK_SOLID_BRUSHONLY })
				if tr.HitSky then
					local floorZ = tr.HitPos.z - 440
					-- well above the ground the trace started from (never inside the map)
					if floorZ > o.z + 200 then
						local c = Vector(start.x, start.y, floorZ)
						-- other sky rooms already up count as "in the way" (MASK_SOLID sees props)
						if inWorld(c) and hullFree(c) then return c end
					end
				end
			end
		end
	end
end

local function plate(pos, ang)
	local e = ents.Create("prop_physics")
	if not IsValid(e) then return nil end
	e:SetModel(PLATE)
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	e:SetMaterial("models/debug/debugwhite")
	e:SetColor(Color(62, 66, 76))
	local ph = e:GetPhysicsObject()
	if IsValid(ph) then ph:EnableMotion(false) end
	e:SetMoveType(MOVETYPE_NONE)
	e.PraetorSitProp = true
	e.PhysgunDisabled = true
	e.m_tblToolsAllowed = {}
	e:SetNW2Bool("pr_sitprop", true)
	return e
end

local function buildSkyRoom(c)
	local props = {}
	local function add(e) if IsValid(e) then props[#props + 1] = e end end
	add(plate(c + Vector(0, 0, -1.5), Angle(0, 0, 0)))
	add(plate(c + Vector(HALF, 0, HALF), Angle(90, 0, 0)))
	add(plate(c + Vector(-HALF, 0, HALF), Angle(90, 0, 0)))
	add(plate(c + Vector(0, HALF, HALF), Angle(90, 90, 0)))
	add(plate(c + Vector(0, -HALF, HALF), Angle(90, 90, 0)))
	return props
end

-- the room props can't be moved, tooled, damaged or removed by players
local function isSitProp(e) return IsValid(e) and e.PraetorSitProp == true end
hook.Add("PhysgunPickup", "Praetor.Sits", function(_, e) if isSitProp(e) then return false end end)
hook.Add("CanTool", "Praetor.Sits", function(_, tr) if tr and isSitProp(tr.Entity) then return false end end)
hook.Add("CanProperty", "Praetor.Sits", function(_, _, e) if isSitProp(e) then return false end end)
hook.Add("GravGunPickupAllowed", "Praetor.Sits", function(_, e) if isSitProp(e) then return false end end)
hook.Add("CanPlayerUnfreeze", "Praetor.Sits", function(_, e) if isSitProp(e) then return false end end)

-- ------------------------------------------------------------------ placing players

local SPOTS = {}
for _, d in ipairs({ 0, 50, 90, 130 }) do
	for _, a in ipairs({ 0, 60, 120, 180, 240, 300 }) do
		local r = math.rad(a)
		SPOTS[#SPOTS + 1] = Vector(math.cos(r) * d, math.sin(r) * d, 0)
		if d == 0 then break end
	end
end

local function freeSpot(base, ply)
	local mins, maxs = ply:GetHull()
	for _, off in ipairs(SPOTS) do
		local p = base + off + Vector(0, 0, 6)
		local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply })
		if not tr.Hit then return p end
	end
	return base + Vector(0, 0, 6)
end

local function bbxCase(id) return BBX and BBX.Cases and id and BBX.Cases[id] or nil end

-- where a member stands: staff on one side, the others in front of them
local function placeIn(sit, ply)
	local center = sit.room.c
	local yaw = sit.room.yaw or 0
	local fwd = Angle(0, yaw, 0):Forward()
	local isStaff = sit.staff[ply:SteamID64()] == true
	local base = center + fwd * (isStaff and -70 or 70)
	local pos = freeSpot(base, ply)
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:SetPos(pos)
	ply:SetLocalVelocity(vector_origin)
	local look = center + fwd * (isStaff and 70 or -70)
	local ang = (look - pos):Angle()
	ply:SetEyeAngles(Angle(0, ang.y, 0))
end

local function remember(sit, ply)
	local sid = ply:SteamID64()
	if sit.back[sid] then return end
	sit.back[sid] = { pos = ply:GetPos(), ang = ply:EyeAngles() }
	P.SaveReturn(ply)
	-- Blackbox's "Return" uses its own list: give it the same spot
	local c = bbxCase(sit.case)
	if c and BBX.Id then
		c.back = c.back or {}
		local id = BBX.Id(ply)
		if not c.back[id] then c.back[id] = { pos = ply:GetPos(), ang = ply:EyeAngles() } end
	end
end

-- ------------------------------------------------------------------ state for the clients

local function members(sit)
	local list = {}
	for sid in pairs(sit.members) do
		local p = player.GetBySteamID64(sid)
		if IsValid(p) then list[#list + 1] = p end
	end
	return list
end

local function packSit(sit)
	local m = {}
	for sid in pairs(sit.members) do
		local p = player.GetBySteamID64(sid)
		m[#m + 1] = { sid = sid, n = IsValid(p) and p:Nick() or (P.KnownName(sid) or "?"), st = sit.staff[sid] or nil }
	end
	return { id = sit.id, room = sit.room.name, gen = sit.room.gen or nil, start = sit.start, age = os.time() - sit.start, m = m, case = sit.case, rep = sit.report }
end

local function syncSit(sit)
	local data = packSit(sit)
	P.Send(members(sit), "sit_state", data)
	P.Send(P.WithPerm("reports"), "sit_list", { list = P.SitList() })
end

function P.SitList()
	local out = {}
	for _, s in pairs(P.Sits) do out[#out + 1] = packSit(s) end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

function P.SitOf(ply)
	if not IsValid(ply) then return nil end
	for _, s in pairs(P.Sits) do if s.members[ply:SteamID64()] then return s end end
end

-- ------------------------------------------------------------------ start / add / end

function P.SitAdd(sit, ply, asStaff)
	if not IsValid(ply) then return false end
	local other = P.SitOf(ply)
	if other and other ~= sit then return false end
	local sid = ply:SteamID64()
	if not sid then return false end
	if not ply:Alive() then ply:Spawn() end
	remember(sit, ply)
	sit.members[sid] = true
	if asStaff then sit.staff[sid] = true end
	placeIn(sit, ply)
	return true
end

-- targets: list of players. opts: { case = Blackbox case id, report = Praetor report id, room = saved room id }
function P.StartSit(caller, targets, opts)
	if not IsValid(caller) then return false, "err_console" end
	opts = opts or {}
	local cur = P.SitOf(caller)
	if cur then
		local n = 0
		for _, t in ipairs(targets or {}) do if t ~= caller and P.SitAdd(cur, t, false) then n = n + 1 end end
		syncSit(cur)
		return n > 0, n > 0 and nil or "err_sit_already"
	end
	for _, t in ipairs(targets or {}) do
		if P.SitOf(t) then return false, "err_sit_busy_t", { S = t:Nick() } end
	end

	-- the room: the one asked for, a free saved one, or one built in the sky
	local room
	if opts.room then
		local r = roomById(opts.room)
		if not r then return false, "err_sit_noroom" end
		if roomBusy(r.id) then return false, "err_sit_room_busy" end
		room = { id = r.id, name = r.name, c = vec(r.pos), yaw = r.yaw }
	else
		for _, r in ipairs(P.SitRooms) do
			if not roomBusy(r.id) then room = { id = r.id, name = r.name, c = vec(r.pos), yaw = r.yaw } break end
		end
	end
	if not room then
		if not P.Setting("sit_auto") then return false, "err_sit_noroom" end
		local c = skySpot(caller:GetPos())
		if not c then return false, "err_sit_nosky" end
		local id = "gen" .. nextId
		room = { id = id, name = P.LText(srvLang(), "sit_sky"), c = c, yaw = caller:EyeAngles().y, gen = true }
		room.props = buildSkyRoom(c)
	end

	local sit = { id = nextId, room = room, members = {}, staff = {}, back = {}, start = os.time(), by = caller:SteamID64(), case = opts.case, report = opts.report }
	nextId = nextId + 1
	P.Sits[sit.id] = sit
	P.SitAdd(sit, caller, true)
	for _, t in ipairs(targets or {}) do
		if t ~= caller then P.SitAdd(sit, t, false) end
	end
	syncSit(sit)
	local tl = {}
	for _, t in ipairs(targets or {}) do if t ~= caller then tl[#tl + 1] = t end end
	P.Log("report", "l_sit_start", { A = P.LogPly(caller), T = #tl > 0 and (function() local o = {} for _, t in ipairs(tl) do o[#o + 1] = P.LogPly(t) end return o end)() or nil, V = room.name }, { caller, unpack(tl) })
	hook.Run("Praetor.SitStarted", sit, caller)
	return true
end

function P.EndSit(sit, by, silent)
	if not sit or not P.Sits[sit.id] then return end
	P.Sits[sit.id] = nil
	local c = sit.room.c
	local staffSids = {}
	for sid in pairs(sit.staff) do staffSids[#staffSids + 1] = sid end
	for sid in pairs(sit.members) do
		local p = player.GetBySteamID64(sid)
		local b = sit.back[sid]
		if IsValid(p) then
			-- only people still in the room go back (Blackbox may have moved them already)
			if b and p:GetPos():DistToSqr(c) < 900 * 900 then
				if p:InVehicle() then p:ExitVehicle() end
				p:SetPos(b.pos)
				p:SetEyeAngles(b.ang)
				p:SetLocalVelocity(vector_origin)
			end
			P.Send(p, "sit_state", { off = true })
		end
	end
	for _, e in ipairs(sit.room.props or {}) do if IsValid(e) then e:Remove() end end
	if not silent then
		P.Log("report", "l_sit_end", { A = IsValid(by) and P.LogPly(by) or nil, V = sit.room.name, V2 = P.FormatDuration(math.max(1, math.ceil((os.time() - sit.start) / 60))) }, { by })
	end
	sit.staffSids = staffSids
	P.Send(P.WithPerm("reports"), "sit_list", { list = P.SitList() })
	hook.Run("Praetor.SitEnded", sit, by)
end

-- the staff member's own open case or report, to start a room with no names
local function claimedFor(ply)
	if BBX and BBX.Cases and BBX.Id then
		local me = BBX.Id(ply)
		for id, c in pairs(BBX.Cases) do
			if c.st == "claimed" and c.staff and c.staff.s == me then
				local list = {}
				local rep = c.rep and BBX.ById(c.rep.s)
				local tgt = c.tgt and BBX.ById(c.tgt.s)
				if IsValid(rep) then list[#list + 1] = rep end
				if IsValid(tgt) and tgt ~= rep then list[#list + 1] = tgt end
				return list, { case = id }
			end
		end
	end
	local row = P.DB.Row("SELECT * FROM praetor_reports WHERE status = 'claimed' AND staff_sid = ? ORDER BY id DESC LIMIT 1", ply:SteamID64())
	if row then
		local list = {}
		local a, b = P.BySID(row.sid), (row.tsid or "") ~= "" and P.BySID(row.tsid) or nil
		if IsValid(a) then list[#list + 1] = a end
		if IsValid(b) and b ~= a then list[#list + 1] = b end
		return list, { report = tonumber(row.id) }
	end
end
P.SitClaimedFor = claimedFor

-- ------------------------------------------------------------------ keeping it tidy

hook.Add("PlayerSpawn", "Praetor.Sits", function(ply)
	local sit = P.SitOf(ply)
	if not sit then return end
	timer.Simple(0, function() if IsValid(ply) and P.Sits[sit.id] then placeIn(sit, ply) end end)
end)

hook.Add("EntityTakeDamage", "Praetor.Sits", function(ent, dmg)
	if isSitProp(ent) then return true end
	if ent:IsPlayer() and P.Setting("sit_god") and P.SitOf(ent) then return true end
end)

hook.Add("PlayerDisconnected", "Praetor.Sits", function(ply)
	local sit = P.SitOf(ply)
	if not sit then return end
	local sid = ply:SteamID64()
	sit.members[sid] = nil
	local staffLeft, othersLeft = false, false
	for s in pairs(sit.members) do
		if sit.staff[s] then staffLeft = true else othersLeft = true end
	end
	sit.staff[sid] = nil
	if not staffLeft or not othersLeft then
		timer.Simple(0, function() P.EndSit(sit, nil) end)
	else
		syncSit(sit)
	end
end)

-- map cleanup removes the walls: build them again
hook.Add("PostCleanupMap", "Praetor.Sits", function()
	for _, s in pairs(P.Sits) do
		if s.room.gen then s.room.props = buildSkyRoom(s.room.c) end
	end
end)

-- Blackbox: closing the case or pressing "Return" ends its room
hook.Add("BBX_CaseClosed", "Praetor.Sits", function(c, closer)
	for _, s in pairs(P.Sits) do if s.case == c.id then P.EndSit(s, closer) end end
end)
hook.Add("BBX_Teleport", "Praetor.Sits", function(c, ply, act)
	if act ~= "return" then return end
	for _, s in pairs(P.Sits) do if s.case == c.id then P.EndSit(s, ply) end end
end)
-- automatic room when a case / report is claimed (setting sit_on_claim)
hook.Add("BBX_CaseClaimed", "Praetor.Sits", function(c, ply)
	if not P.Setting("sit_on_claim") or not IsValid(ply) or not P.Has(ply, "sit") then return end
	timer.Simple(0.2, function()
		if not IsValid(ply) or P.SitOf(ply) then return end
		local list = {}
		local rep = c.rep and BBX.ById(c.rep.s)
		local tgt = c.tgt and BBX.ById(c.tgt.s)
		if IsValid(rep) then list[#list + 1] = rep end
		if IsValid(tgt) and tgt ~= rep then list[#list + 1] = tgt end
		local ok, err, args = P.StartSit(ply, list, { case = c.id })
		if not ok and err then P.Notify(ply, err, args) end
	end)
end)
hook.Add("Praetor.ReportClaimed", "Praetor.Sits", function(id, ply, row)
	if not P.Setting("sit_on_claim") or not IsValid(ply) or not P.Has(ply, "sit") or P.SitOf(ply) then return end
	local list = {}
	local a, b = P.BySID(row.sid), (row.tsid or "") ~= "" and P.BySID(row.tsid) or nil
	if IsValid(a) then list[#list + 1] = a end
	if IsValid(b) and b ~= a then list[#list + 1] = b end
	local ok, err, args = P.StartSit(ply, list, { report = id })
	if not ok and err then P.Notify(ply, err, args) end
end)
-- closing the Praetor report ends its room too
hook.Add("Praetor.ReportClosed", "Praetor.Sits", function(id, ply)
	for _, s in pairs(P.Sits) do if s.report == id then P.EndSit(s, ply) end end
end)

-- ------------------------------------------------------------------ menu

local function canSit(ply) return P.Has(ply, "sit") end

P.Receive("sit_rooms", { perm = { "sit", "manage_sits" }, rate = 1 }, function(ply)
	local list = {}
	for _, r in ipairs(P.SitRooms) do
		list[#list + 1] = { id = r.id, name = r.name, pos = r.pos, by = r.by, busy = roomBusy(r.id) and true or nil }
	end
	P.Send(ply, "sit_rooms", { map = game.GetMap(), list = list, sits = P.SitList(), max = MAX_ROOMS })
end)

P.Receive("sit_room_add", { perm = "manage_sits", rate = 1 }, function(ply, data)
	local ok, res = P.AddSitRoom(ply, data.name)
	if not ok then P.Notify(ply, res, { V = MAX_ROOMS }) return end
	P.Notify(ply, "n_sit_room_saved", { S = res }, "ok")
	P.Handlers_sit_rooms(ply)
end)

P.Receive("sit_room_edit", { perm = "manage_sits", rate = 1 }, function(ply, data)
	local r, i = roomById(tostring(data.id or ""))
	if not r then return end
	if data.del then
		table.remove(P.SitRooms, i)
		P.Log("report", "l_sit_room_del", { A = P.LogPly(ply), V = r.name }, { ply })
	elseif data.here then
		local pos = ply:GetPos()
		r.pos = { math.Round(pos.x, 1), math.Round(pos.y, 1), math.Round(pos.z, 1) }
		r.yaw = math.Round(ply:EyeAngles().y)
	elseif isstring(data.name) then
		local n = P.Trim(P.Str(data.name, 32))
		if n ~= "" then r.name = n end
	end
	saveRooms()
	P.Handlers_sit_rooms(ply)
end)

P.Receive("sit_room_go", { perm = { "sit", "manage_sits" }, rate = 1 }, function(ply, data)
	local r = roomById(tostring(data.id or ""))
	if not r then return end
	P.SaveReturn(ply)
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:SetPos(freeSpot(vec(r.pos), ply))
end)

P.Receive("sit_start", { perm = "sit", rate = 1 }, function(ply, data)
	local list = {}
	for _, sid in ipairs(istable(data.sids) and data.sids or {}) do
		local p = isstring(sid) and P.BySID(sid)
		if IsValid(p) and p ~= ply then
			if not P.CanTarget(ply, p) then P.Notify(ply, "err_authority", { S = p:Nick() }) return end
			list[#list + 1] = p
			if #list >= 8 then break end
		end
	end
	local opts = {}
	if tonumber(data.report) then opts.report = math.floor(tonumber(data.report)) end
	if tonumber(data.case) then opts.case = math.floor(tonumber(data.case)) end
	if isstring(data.room) and data.room ~= "" then opts.room = data.room end
	if #list == 0 and not opts.report and not opts.case then
		local auto, o = claimedFor(ply)
		if auto then list, opts = auto, o end
	end
	local ok, err, args = P.StartSit(ply, list, opts)
	if not ok and err then P.Notify(ply, err, args) return end
	P.Notify(ply, "n_sit_started", nil, "ok")
end)

P.Receive("sit_end", { perm = "sit", rate = 1 }, function(ply, data)
	local sit = P.Sits[tonumber(data.id) or -1] or P.SitOf(ply)
	if not sit then P.Notify(ply, "err_sit_none") return end
	if not sit.staff[ply:SteamID64()] and not P.Has(ply, "manage_sits") then P.Notify(ply, "err_no_perm", { S = "sit" }) return end
	P.EndSit(sit, ply)
end)

P.Receive("sit_join", { perm = "sit", rate = 1 }, function(ply, data)
	local sit = P.Sits[tonumber(data.id) or -1]
	if not sit then return end
	if P.SitAdd(sit, ply, true) then syncSit(sit) end
end)

function P.Handlers_sit_rooms(ply)
	local list = {}
	for _, r in ipairs(P.SitRooms) do
		list[#list + 1] = { id = r.id, name = r.name, pos = r.pos, by = r.by, busy = roomBusy(r.id) and true or nil }
	end
	P.Send(ply, "sit_rooms", { map = game.GetMap(), list = list, sits = P.SitList(), max = MAX_ROOMS })
end

-- staff that join get the rooms running now
hook.Add("Praetor.UserLoaded", "Praetor.Sits", function(ply)
	if next(P.Sits) and P.Has(ply, "reports") then P.Send(ply, "sit_list", { list = P.SitList() }) end
end)

P.SitCanUse = canSit
