-- Praetor: Expression 2 and Starfall chips on the map.
--  * Every 2 seconds the server lists the chips: name, owner, CPU (µs per tick and %
--    of the chip's quota), operations, the owner's hologram count and errors.
--  * The list is sent only to staff who asked for it (the Chips tab or the staff ESP).
--  * Suspicious chips raise an alert to staff on duty (permission "chips"):
--      cpu   - a chip stays above the CPU limit set in Settings (can lag / crash),
--      esp   - a chip keeps reading where most of the other players are (ESP / aimbot),
--      holo  - a chip parents holograms to another player (wallhack markers, trolling).
--  * Staff with chips_manage can stop a chip, remove it or remove every chip of a player.
-- Nothing in Wiremod or Starfall is edited; Praetor only reads their entities.
local P = Praetor

local CLASSES = { gmod_wire_expression2 = "e2", starfall_processor = "sf" }
local HOLOS = { "gmod_wire_hologram", "starfall_hologram" }
local CPU_CHECKS = 3   -- checks in a row above the limit (2 s each)
local ESP_WINDOWS = 3  -- windows in a row reading most players
local STICKY = 60      -- a flag stays on the list this long after the chip calms down
local ALERT_EVERY = 120

local state = setmetatable({}, { __mode = "k" })
local subs = {}
P.ChipList = P.ChipList or {}

local function ownerOf(ent, kind)
	local o
	if kind == "e2" then o = ent.player
	else o = ent.owner or (istable(ent.instance) and ent.instance.player) end
	if not (IsValid(o) and o:IsPlayer()) then
		o = (ent.CPPIGetOwner and ent:CPPIGetOwner()) or (ent.GetCreator and ent:GetCreator())
	end
	return IsValid(o) and o:IsPlayer() and o or nil
end

local function cpuE2(ent)
	local c = ent.context
	if not istable(c) then return 0, 0, 0 end
	local t = tonumber(c.timebench) or 0
	local quota = tonumber(e2_timequota) or -1
	-- without a time quota (wire_expression2_unlimited) the reference is one server tick
	local pct = quota > 0 and t / quota * 100 or t / engine.TickInterval() * 100
	local soft = tonumber(e2_softquota) or 0
	local ops = soft > 0 and (tonumber(c.prfbench) or 0) / soft * 100 or 0
	return math.Round(t * 1000000), pct, ops
end

local function cpuSF(ent)
	local inst = ent.instance
	local perf = istable(inst) and inst.perf
	if not istable(perf) or not isfunction(perf.getCpuReadableMetrics) then return 0, 0 end
	local ok, us, pct = pcall(perf.getCpuReadableMetrics, perf)
	if not ok then return 0, 0 end
	return tonumber(us) or 0, tonumber(pct) or 0
end

local function alertTo()
	local out = {}
	local dutyOn = P.Setting("duty_on") ~= false
	for _, p in ipairs(P.WithPerm("chips")) do
		if not dutyOn or p:GetNW2Bool("pr_duty", false) then out[#out + 1] = p end
	end
	return out
end

local function raise(ent, st, kind, entry, owner)
	if P.Setting("chip_alerts") == false then return end
	st.alerted = st.alerted or {}
	if (st.alerted[kind] or 0) > CurTime() then return end
	st.alerted[kind] = CurTime() + ALERT_EVERY
	local args = { S = entry.on, V = entry.n, V2 = math.floor(entry.pct) .. "%" }
	for _, p in ipairs(alertTo()) do
		P.Notify(p, "chip_alert_" .. kind, args, "warn")
	end
	P.Log("security", "l_chip_alert_" .. kind, { A = owner and P.LogPly(owner) or { n = entry.on, s = entry.os or "" }, V = entry.n, V2 = args.V2 }, { owner })
	hook.Run("Praetor.ChipAlert", ent, kind, owner)
end

local function scan()
	local now = CurTime()
	local holos = {}
	for _, cls in ipairs(HOLOS) do
		for _, h in ipairs(ents.FindByClass(cls)) do
			local o = (h.CPPIGetOwner and h:CPPIGetOwner()) or (h.GetPlayer and h:GetPlayer())
			if IsValid(o) then holos[o] = (holos[o] or 0) + 1 end
		end
	end
	local others = math.max(0, player.GetCount() - 1)
	local espNeed = math.max(3, math.ceil(others * 0.6))

	local list = {}
	for cls, kind in pairs(CLASSES) do
		for _, ent in ipairs(ents.FindByClass(cls)) do
			local st = state[ent]
			if not st then st = { cpu = 0, esp = 0, until_ = {} } state[ent] = st end
			local owner = ownerOf(ent, kind)
			local us, pct, ops
			if kind == "e2" then us, pct, ops = cpuE2(ent) else us, pct = cpuSF(ent) end
			local err = kind == "e2" and ent.error == true or (kind == "sf" and ent.error ~= nil and ent.error ~= false)
			local entry = {
				e = ent:EntIndex(), t = kind,
				n = string.sub(tostring(ent.name or "generic"), 1, 60),
				on = IsValid(owner) and owner:Nick() or "?",
				os = IsValid(owner) and P.SIDOf(owner) or nil,
				us = us, pct = math.Round(pct, 1), ops = ops and math.Round(ops) or nil,
				holo = IsValid(owner) and holos[owner] or 0,
				err = err or nil,
			}

			-- CPU above the limit for a while
			local limit = tonumber(P.Setting("chip_cpu_alert")) or 80
			if not err and pct >= limit then st.cpu = st.cpu + 1 else st.cpu = 0 end
			if st.cpu >= CPU_CHECKS then
				st.until_.cpu = now + STICKY
				raise(ent, st, "cpu", entry, owner)
			end

			-- reading where most players are, window after window
			local hits = P.ChipEspHits and P.ChipEspHits[ent]
			local n = 0
			if hits then
				for p in pairs(hits) do if IsValid(p) then n = n + 1 end end
				P.ChipEspHits[ent] = nil
			end
			if others >= 2 and n >= espNeed then st.esp = st.esp + 1 else st.esp = 0 end
			entry.seen = n > 0 and n or nil
			if st.esp >= ESP_WINDOWS then
				st.until_.esp = now + STICKY
				raise(ent, st, "esp", entry, owner)
			end

			-- holograms stuck to another player
			if P.ChipHoloPly and P.ChipHoloPly[ent] then
				P.ChipHoloPly[ent] = nil
				st.until_.holo = now + STICKY
				raise(ent, st, "holo", entry, owner)
			end

			local f
			for k, t in pairs(st.until_) do
				if t > now then f = f or {} f[k] = true end
			end
			entry.f = f
			list[#list + 1] = entry
		end
	end
	-- suspicious first, then by CPU
	table.sort(list, function(a, b)
		local fa, fb = a.f ~= nil, b.f ~= nil
		if fa ~= fb then return fa end
		return (a.pct or 0) > (b.pct or 0)
	end)
	P.ChipList = list

	local to = {}
	for p in pairs(subs) do
		if IsValid(p) and P.Has(p, "chips") then to[#to + 1] = p else subs[p] = nil end
	end
	if #to > 0 then P.Send(to, "chips", { list = list }) end
end
timer.Create("Praetor.Chips", 2, 0, function()
	local ok, err = pcall(scan)
	if not ok then ErrorNoHalt("[Praetor] chips: " .. tostring(err) .. string.char(10)) end
end)

P.Receive("chips_sub", { perm = "chips", rate = 0.2 }, function(ply, data)
	subs[ply] = data.on and true or nil
	if data.on then P.Send(ply, "chips", { list = P.ChipList }) end
end)

-- ------------------------------------------------------------------ actions
local function chipFrom(ply, data)
	local ent = Entity(tonumber(data.e) or -1)
	if not IsValid(ent) or not CLASSES[ent:GetClass()] then
		P.Notify(ply, "err_chip_gone", nil, "warn")
		return
	end
	return ent, CLASSES[ent:GetClass()]
end

local function mayTouch(ply, owner)
	if not IsValid(owner) or owner == ply then return true end
	if P.CanTarget(ply, owner) then return true end
	P.Notify(ply, "err_chip_immune", { S = owner:Nick() }, "warn")
	return false
end

P.Receive("chip_goto", { perm = "chips", rate = 0.5 }, function(ply, data)
	local ent = chipFrom(ply, data)
	if not ent then return end
	local pos = P.FindSpot(ent, ply) or (ent:GetPos() + Vector(0, 0, 40))
	P.SaveReturn(ply)
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:SetPos(pos)
	ply:SetEyeAngles((ent:GetPos() - ply:EyePos()):Angle())
end)

local function stop(ent, kind)
	if kind == "e2" then
		if isfunction(ent.Error) then ent:Error("Expression 2 (" .. tostring(ent.name) .. "): stopped by staff", "stopped by staff") end
	elseif isfunction(ent.Error) then
		ent:Error({ message = "Stopped by staff", traceback = "" })
	end
end

P.Receive("chip_stop", { perm = "chips_manage", rate = 0.3 }, function(ply, data)
	local ent, kind = chipFrom(ply, data)
	if not ent then return end
	local owner = ownerOf(ent, kind)
	if not mayTouch(ply, owner) then return end
	stop(ent, kind)
	local name = tostring(ent.name or "generic")
	if IsValid(owner) and owner ~= ply then P.Notify(owner, "chip_stopped_you", { S = ply:Nick(), V = name }, "warn") end
	P.Notify(ply, "ok_chip_stopped", { V = name }, "ok")
	P.Log("cmd", "l_chip_stop", { A = P.LogPly(ply), T = owner and P.LogPly(owner) or { n = "?", s = "" }, V = name }, { ply, owner })
end)

P.Receive("chip_remove", { perm = "chips_manage", rate = 0.3 }, function(ply, data)
	local ent, kind = chipFrom(ply, data)
	if not ent then return end
	local owner = ownerOf(ent, kind)
	if not mayTouch(ply, owner) then return end
	local name = tostring(ent.name or "generic")
	ent:Remove()
	if IsValid(owner) and owner ~= ply then P.Notify(owner, "chip_removed_you", { S = ply:Nick(), V = name }, "warn") end
	P.Notify(ply, "ok_chip_removed", { V = name }, "ok")
	P.Log("cmd", "l_chip_remove", { A = P.LogPly(ply), T = owner and P.LogPly(owner) or { n = "?", s = "" }, V = name }, { ply, owner })
end)

P.Receive("chip_remove_owner", { perm = "chips_manage", rate = 0.5 }, function(ply, data)
	local ent, kind = chipFrom(ply, data)
	if not ent then return end
	local owner = ownerOf(ent, kind)
	if not IsValid(owner) then P.Notify(ply, "err_chip_gone", nil, "warn") return end
	if not mayTouch(ply, owner) then return end
	local n = 0
	for cls, k in pairs(CLASSES) do
		for _, e in ipairs(ents.FindByClass(cls)) do
			if ownerOf(e, k) == owner then e:Remove() n = n + 1 end
		end
	end
	if owner ~= ply then P.Notify(owner, "chip_removed_all_you", { S = ply:Nick() }, "warn") end
	P.Notify(ply, "ok_chip_removed_all", { S = owner:Nick(), V = n }, "ok")
	P.Log("cmd", "l_chip_remove_all", { A = P.LogPly(ply), T = P.LogPly(owner), V = n }, { ply, owner })
end)

hook.Add("PlayerDisconnected", "Praetor.Chips", function(ply) subs[ply] = nil end)
