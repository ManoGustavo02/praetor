-- Praetor: Expression 2 and Starfall chips on the map.
--  * Every 2 seconds the server lists the chips: name, owner, CPU (µs per tick and %
--    of the chip's quota), operations, the owner's hologram count and errors.
--  * The list is sent only to staff who asked for it (the Chips tab or the staff ESP).
--  * Flags on the list (and alerts to staff on duty with the "chips" permission):
--      cpu   - a chip stays above the CPU limit set in Settings (can lag / crash),
--      holo  - a chip parents holograms to another player (markers, trolling),
--      esp   - a chip keeps reading where the players are. Many honest chips do
--              that (radars, turrets, doors), so this one only marks the chip on
--              the list; the alert is off by default (chip_esp_alert) and much
--              stricter when on. It never goes to the security log by itself.
--  * Anti-lag (chip_autostop / chip_lag_guard): a chip that stays at the edge of
--    its CPU quota, or the heaviest chip while all chips together eat most of the
--    server tick, is stopped. Its owner and the staff are told why.
--  * Blocked names (chip_block_words): a chip whose name has one of the words is
--    refused when it is uploaded (and stopped if it was already running).
--  * Staff with chips_manage can stop a chip, remove it or remove every chip of a
--    player. Stopping runs the chip's own clean-up: E2 holograms and sounds go
--    away, and Starfall chips are stopped on every client too (client holograms,
--    render effects).
-- Nothing in Wiremod or Starfall is edited on disk; Praetor only wraps / reads.
local P = Praetor

local CLASSES = { gmod_wire_expression2 = "e2", starfall_processor = "sf" }
local HOLOS = { "gmod_wire_hologram", "starfall_hologram" }
local CPU_CHECKS = 3   -- checks in a row above the alert limit (2 s each)
local ESP_WINDOWS = 15 -- 30 seconds in a row reading most players
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

local function isErrored(ent, kind)
	if kind == "e2" then return ent.error == true end
	return (ent.error ~= nil and ent.error ~= false) or ent.instance == nil
end

-- ------------------------------------------------------------------ stopping
-- E2: the "destruct" callbacks are what remove its holograms, sounds and event
-- listeners; an error alone leaves them in the world, so they run first.
-- Starfall: the error ends the server side (its holograms and props go with it);
-- the chip also runs on every client, which is told to stop as well.
local function stop(ent, kind, why)
	why = tostring(why or "stopped by staff")
	if kind == "e2" then
		if not ent.error and isfunction(ent.Destruct) then pcall(ent.Destruct, ent) end
		if isfunction(ent.Error) then pcall(ent.Error, ent, "Expression 2 (" .. tostring(ent.name) .. "): " .. why, why) end
	else
		if ent.instance and isfunction(ent.Error) then pcall(ent.Error, ent, { message = why, traceback = "" }) end
		if util.NetworkStringToID("starfall_processor_kill") ~= 0 then
			net.Start("starfall_processor_kill")
			net.WriteEntity(ent)
			net.Broadcast()
		end
	end
	local st = state[ent]
	if st then st.cpu, st.edge, st.esp = 0, 0, 0 end
end
P.ChipStop = function(ent, why)
	local kind = IsValid(ent) and CLASSES[ent:GetClass()]
	if kind then stop(ent, kind, why) end
end

-- ------------------------------------------------------------------ alerts
local function alertTo()
	local out = {}
	local dutyOn = P.Setting("duty_on") ~= false
	for _, p in ipairs(P.WithPerm("chips")) do
		if not dutyOn or p:GetNW2Bool("pr_duty", false) then out[#out + 1] = p end
	end
	return out
end

local function raise(ent, st, kind, entry, owner, log)
	if P.Setting("chip_alerts") == false then return end
	st.alerted = st.alerted or {}
	if (st.alerted[kind] or 0) > CurTime() then return end
	st.alerted[kind] = CurTime() + ALERT_EVERY
	local args = { S = entry.on, V = entry.n, V2 = math.floor(entry.pct) .. "%" }
	for _, p in ipairs(alertTo()) do
		P.Notify(p, "chip_alert_" .. kind, args, "warn")
	end
	if log ~= false then
		P.Log("security", "l_chip_alert_" .. kind, { A = owner and P.LogPly(owner) or { n = entry.on, s = entry.os or "" }, V = entry.n, V2 = args.V2 }, { owner })
	end
	hook.Run("Praetor.ChipAlert", ent, kind, owner)
end

-- something Praetor did on its own to a chip: the owner, the staff and the log know why
local function acted(ent, kind, owner, key, args)
	if IsValid(owner) then P.Notify(owner, key .. "_you", args, "warn") end
	for _, p in ipairs(alertTo()) do
		if p ~= owner then P.Notify(p, key, args, "warn") end
	end
	P.Log("security", "l_" .. key, {
		A = owner and P.LogPly(owner) or { n = args.S or "?", s = "" }, V = args.V, V2 = args.V2,
	}, { owner })
end

-- ------------------------------------------------------------------ blocked names
local function nameWord(name)
	local list = P.Setting("chip_block_words")
	if not isstring(list) or P.Trim(list) == "" or not P.AutoModCompile then return nil end
	local block = P.AutoModCompile(list)
	if #block == 0 then return nil end
	return P.AutoModFind(tostring(name or ""), block, {}, false)
end
P.ChipNameWord = nameWord

local function nameExempt(owner)
	return IsValid(owner) and (P.IsOwner(owner) or P.Has(owner, "chips_manage"))
end

local function refuseName(owner, name, word, kind)
	if IsValid(owner) then P.Notify(owner, "err_chip_name", { V = name, S = word }, "warn") end
	P.Log("security", "l_chip_name", { A = owner and P.LogPly(owner) or { n = "?", s = "" }, V = P.Str(name, 60), S = word, V2 = kind == "sf" and "Starfall" or "E2" }, { owner })
end

-- Starfall asks every addon before it compiles a chip
local function sfDirectiveName(code, mainfile)
	local main = code
	if istable(code) then main = code[mainfile] or select(2, next(code)) end
	if not isstring(main) then return nil end
	return main:match("%-%-@name[ \t]+([^\r\n]+)")
end
hook.Add("StarfallCanCompile", "Praetor.ChipNames", function(code, mainfile, ply, ent)
	if not IsValid(ply) or nameExempt(ply) then return end
	local name = sfDirectiveName(code, mainfile)
	if not name then return end
	local word = nameWord(name)
	if not word then return end
	refuseName(ply, name, word, "sf")
	return false, "Praetor: chip name not allowed (" .. word .. ")"
end)

-- E2: the name comes from the @name line of the code, read before it runs
local function wrapE2()
	local stored = scripted_ents.GetStored("gmod_wire_expression2")
	local ENT = stored and stored.t
	if not ENT or not isfunction(ENT.Setup) or ENT.PraetorSetup then return end
	local orig = ENT.Setup
	ENT.PraetorSetup = orig
	ENT.Setup = function(self, buffer, ...)
		if isstring(buffer) then
			local owner = self.player
			local name = buffer:match("@name[ \t]+([^\r\n]+)")
			if name and IsValid(owner) and not nameExempt(owner) then
				local word = nameWord(name)
				if word then
					refuseName(owner, name, word, "e2")
					self.name = P.Str(name, 60)
					stop(self, "e2", "name not allowed (" .. word .. ")")
					return
				end
			end
		end
		return orig(self, buffer, ...)
	end
end
hook.Add("InitPostEntity", "Praetor.ChipNames", wrapE2)
timer.Simple(3, wrapE2)

-- ------------------------------------------------------------------ the scan
local overSince = 0

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
	local espNeed = math.max(3, math.ceil(others * 0.8))
	local alertLimit = tonumber(P.Setting("chip_cpu_alert")) or 80
	local autostop = P.Setting("chip_autostop") ~= false
	local stopLimit = math.Clamp(tonumber(P.Setting("chip_stop_pct")) or 95, 50, 100)
	local stopChecks = math.max(1, math.ceil((tonumber(P.Setting("chip_stop_secs")) or 10) / 2))
	local totalUs, heaviest, heaviestUs = 0, nil, 0

	local list = {}
	for cls, kind in pairs(CLASSES) do
		for _, ent in ipairs(ents.FindByClass(cls)) do
			local st = state[ent]
			if not st then st = { cpu = 0, edge = 0, esp = 0, until_ = {} } state[ent] = st end
			local owner = ownerOf(ent, kind)
			local us, pct, ops
			if kind == "e2" then us, pct, ops = cpuE2(ent) else us, pct = cpuSF(ent) end
			local err = isErrored(ent, kind)
			local name = P.Str(tostring(ent.name or "generic"), 60)
			local entry = {
				e = ent:EntIndex(), t = kind, n = name,
				on = IsValid(owner) and owner:Nick() or "?",
				os = IsValid(owner) and P.SIDOf(owner) or nil,
				us = us, pct = math.Round(pct, 1), ops = ops and math.Round(ops) or nil,
				holo = IsValid(owner) and holos[owner] or 0,
				err = err or nil,
			}

			if not err then
				totalUs = totalUs + us
				if us > heaviestUs then heaviest, heaviestUs = ent, us end

				-- a name that became blocked after the chip was placed
				if not st.nameChecked or st.nameChecked ~= name then
					st.nameChecked = name
					local word = not nameExempt(owner) and nameWord(name)
					if word then
						refuseName(owner, name, word, kind)
						stop(ent, kind, "name not allowed (" .. word .. ")")
						err = true
						entry.err = true
					end
				end
			end

			if not err then
				-- CPU above the alert limit for a while
				if pct >= alertLimit then st.cpu = st.cpu + 1 else st.cpu = 0 end
				if st.cpu >= CPU_CHECKS then
					st.until_.cpu = now + STICKY
					raise(ent, st, "cpu", entry, owner)
				end
				-- at the edge of its own quota for long: stopped
				if autostop and pct >= stopLimit then st.edge = st.edge + 1 else st.edge = 0 end
				if autostop and st.edge >= stopChecks then
					stop(ent, kind, "CPU at the limit for too long")
					acted(ent, kind, owner, "chip_autostop", { S = entry.on, V = name, V2 = math.floor(pct) .. "%" })
					entry.err = true
				end
			end

			-- reading where most players are, for a long time (list only, unless the alert is on)
			local hits = P.ChipEspHits and P.ChipEspHits[ent]
			local n = 0
			if hits then
				for p in pairs(hits) do if IsValid(p) then n = n + 1 end end
				P.ChipEspHits[ent] = nil
			end
			if not err and others >= 3 and n >= espNeed then st.esp = st.esp + 1 else st.esp = 0 end
			entry.seen = n > 0 and n or nil
			if st.esp >= ESP_WINDOWS then
				st.until_.esp = now + STICKY
				if P.Setting("chip_esp_alert") == true then raise(ent, st, "esp", entry, owner, false) end
			end

			-- holograms stuck to another player
			if P.ChipHoloPly and P.ChipHoloPly[ent] then
				P.ChipHoloPly[ent] = nil
				if not err then
					st.until_.holo = now + STICKY
					raise(ent, st, "holo", entry, owner)
				end
			end

			local f
			for k, t in pairs(st.until_) do
				if t > now then f = f or {} f[k] = true end
			end
			entry.f = f
			list[#list + 1] = entry
		end
	end

	-- all chips together eat too much of the server tick: the heaviest one stops
	if P.Setting("chip_lag_guard") ~= false and IsValid(heaviest) then
		local tickUs = engine.TickInterval() * 1000000
		local share = totalUs / tickUs * 100
		local limit = math.Clamp(tonumber(P.Setting("chip_lag_pct")) or 60, 20, 200)
		if share >= limit and heaviestUs >= tickUs * 0.1 then
			overSince = overSince + 1
			if overSince >= 3 then
				overSince = 1
				local kind = CLASSES[heaviest:GetClass()]
				local owner = ownerOf(heaviest, kind)
				local name = P.Str(tostring(heaviest.name or "generic"), 60)
				stop(heaviest, kind, "the server was lagging")
				acted(heaviest, kind, owner, "chip_lagstop", { S = IsValid(owner) and owner:Nick() or "?", V = name, V2 = math.floor(share) .. "%" })
				for _, e in ipairs(list) do if e.e == heaviest:EntIndex() then e.err = true end end
			end
		else
			overSince = 0
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
