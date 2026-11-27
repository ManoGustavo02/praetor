-- Praetor: anti-crash. On by default. Every module only acts on things that are
-- certainly wrong, to avoid false positives:
--  * lag guard: measures how long each server tick really takes. When the
--    average over a second is far above normal (default 120 ms; a 66 tick
--    server runs at ~15 ms) it acts in steps: 1) freezes props stuck inside each
--    other (the usual cause of physics crashes), 2) freezes the props of the
--    player that owns most of the moving ones, 3) every moving player prop,
--    4) optionally removes the stuck ones. Staff see who caused it.
--  * spawn guard: props spawned inside other props start frozen.
--  * broken physics: NaN positions / speeds, props flung out of the world.
--  * physics budget: limits collision checks per tick so a pile of props slows
--    down instead of hanging the server (setting ac_physenv).
--  * spawn spam / chat flood / net message flood / entity cap per player.
-- Everything it does goes to the security log (Security tab) and to the staff.
local P = Praetor

local function on(key) return P.Setting("ac_enabled") and P.Setting(key) end

local function alertStaff(key, args)
	if not P.Setting("ac_notify") then return end
	local to = {}
	for _, p in ipairs(player.GetHumans()) do
		if P.IsOwner(p) or P.Has(p, "logs") then to[#to + 1] = p end
	end
	if #to > 0 then P.Send(to, "notify", { k = key, a = args, kind = "warn" }) end
end

-- goes to the Security tab too (without the red alert, staff got a notice)
local function secLog(ply, kind, info)
	if P.Security then P.Security(ply, kind, info, true) end
end

local function ownerOf(e)
	local o = (e.CPPIGetOwner and e:CPPIGetOwner()) or (e.GetCreator and e:GetCreator())
	if IsValid(o) and o:IsPlayer() then return o end
	o = e.PraetorOwner
	if IsValid(o) and o:IsPlayer() then return o end
end

-- spawned entities remember who made them (works without a prop protection addon)
hook.Add("PlayerSpawnedProp", "Praetor.ACOwner", function(ply, _, e) if IsValid(e) then e.PraetorOwner = ply end end)
hook.Add("PlayerSpawnedSENT", "Praetor.ACOwner", function(ply, e) if IsValid(e) then e.PraetorOwner = ply end end)
hook.Add("PlayerSpawnedVehicle", "Praetor.ACOwner", function(ply, e) if IsValid(e) then e.PraetorOwner = ply end end)
hook.Add("PlayerSpawnedRagdoll", "Praetor.ACOwner", function(ply, _, e) if IsValid(e) then e.PraetorOwner = ply end end)

local function physOf(e)
	if not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsWorld() or e.PraetorSitProp or e:IsVehicle() and IsValid(e:GetDriver()) then return end
	local phys = e:GetPhysicsObject()
	if IsValid(phys) then return phys end
end

-- ------------------------------------------------------------------ tick timing

local TICK = engine.TickInterval()
local frames, sum, last = {}, 0, SysTime()
local history = {}          -- one entry per second for the live chart (ms)
local secBucket, secMax, secN, secSum = math.floor(SysTime()), 0, 0, 0
P.ACState = P.ACState or { avg = 0, peak = 0, stage = 0, actions = {} }
local state = P.ACState

local function remember(kind, n, who)
	table.insert(state.actions, 1, { t = os.time(), k = kind, n = n, w = who })
	while #state.actions > 8 do table.remove(state.actions) end
end

-- ------------------------------------------------------------------ lag guard

local lagSince, cooldown = nil, 0
local mapStart = SysTime()

-- Is the physics what is slow? A hitch of the game itself (the host of a local
-- server loading a texture, alt-tab, a map change) also makes the server late,
-- and freezing props then does nothing but scare everyone. The guard only acts
-- when most frames of the last second were slow (not one long hitch) AND there
-- are props awake or stuck in each other to blame.
local function physicsBusy()
	local awake, stuck = 0, 0
	for _, e in ipairs(ents.GetAll()) do
		local phys = physOf(e)
		if phys and phys:IsMotionEnabled() and not phys:IsAsleep() then
			awake = awake + 1
			if phys:IsPenetrating() then stuck = stuck + 1 end
		end
	end
	return awake >= (tonumber(P.Setting("ac_min_awake")) or 25) or stuck >= 4, awake, stuck
end
local frozenByUs = setmetatable({}, { __mode = "k" })

local function freezePenetrating()
	local n, owners = 0, {}
	for _, e in ipairs(ents.GetAll()) do
		local phys = physOf(e)
		if phys and phys:IsMotionEnabled() and phys:IsPenetrating() then
			phys:EnableMotion(false)
			phys:Sleep()
			frozenByUs[e] = true
			n = n + 1
			local o = ownerOf(e)
			if o then owners[o] = (owners[o] or 0) + 1 end
		end
	end
	return n, owners
end

-- who owns most of the props that are awake right now
local function movingByOwner()
	local owners, total = {}, 0
	for _, e in ipairs(ents.GetAll()) do
		local phys = physOf(e)
		if phys and phys:IsMotionEnabled() and not phys:IsAsleep() then
			local o = ownerOf(e)
			if o then owners[o] = (owners[o] or 0) + 1 total = total + 1 end
		end
	end
	return owners, total
end

local function freezeOwner(ply)
	local n = 0
	for _, e in ipairs(ents.GetAll()) do
		if ownerOf(e) == ply then
			local phys = physOf(e)
			if phys and phys:IsMotionEnabled() then
				phys:EnableMotion(false)
				frozenByUs[e] = true
				n = n + 1
			end
		end
	end
	return n
end

local function freezeMoving()
	local n = 0
	for _, e in ipairs(ents.GetAll()) do
		if ownerOf(e) then
			local phys = physOf(e)
			if phys and phys:IsMotionEnabled() then
				phys:EnableMotion(false)
				frozenByUs[e] = true
				n = n + 1
			end
		end
	end
	return n
end

local function ownersText(owners)
	local list = {}
	for p, c in pairs(owners) do if IsValid(p) then list[#list + 1] = { p:Nick(), c } end end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(#list, 5) do out[i] = list[i][1] .. " (" .. list[i][2] .. ")" end
	return table.concat(out, ", ")
end

local function topOwner(owners, total)
	local best, n = nil, 0
	for p, c in pairs(owners) do if IsValid(p) and c > n then best, n = p, c end end
	if best and total > 0 and n >= math.max(10, total * 0.4) then return best, n end
end

hook.Add("Think", "Praetor.AntiCrash", function()
	local now = SysTime()
	local dt = now - last
	last = now
	-- per second numbers for the Security tab, always measured
	local sec = math.floor(now)
	if sec ~= secBucket then
		if secN > 0 then
			history[#history + 1] = { math.Round(secSum / secN * 1000, 1), math.Round(secMax * 1000, 1) }
			while #history > 60 do table.remove(history, 1) end
		end
		secBucket, secMax, secN, secSum = sec, 0, 0, 0
	end
	secN = secN + 1
	secSum = secSum + dt
	if dt > secMax then secMax = dt end

	frames[#frames + 1] = dt
	sum = sum + dt
	while sum > 1.05 and #frames > 1 do sum = sum - table.remove(frames, 1) end
	local avg = sum / #frames
	state.avg = avg * 1000
	if dt * 1000 > state.peak then state.peak = dt * 1000 end
	if not on("ac_lag") then return end
	-- the first minute of a map is loading, not a crash
	if now - mapStart < 60 then return end
	-- one tick of more than a second with props stuck in each other: a physics
	-- pile-up is starting, act at once instead of waiting for the average
	if dt > 1 and state.stage == 0 and now >= cooldown then
		local busy, _, stuck = physicsBusy()
		if busy and stuck >= 4 then
			local n, owners = freezePenetrating()
			state.stage = 1
			lagSince = lagSince or now
			cooldown = now + 1
			local who = ownersText(owners)
			remember("freeze", n, who)
			if n > 0 then
				local ms = math.Round(dt * 1000) .. " ms"
				P.Log("security", "l_ac_freeze", { V = n, V2 = who, S = ms })
				secLog(nil, "ac_freeze", n .. " props, " .. ms .. (who ~= "" and (" - " .. who) or ""))
				alertStaff("n_ac_freeze", { V = n, S = who ~= "" and who or "-" })
			end
			return
		end
	end
	if sum < 0.9 then return end
	-- the server can never be faster than its tick rate: compare above that
	local limit = math.max(0.05, TICK * 2, P.Setting("ac_lag_ms") / 1000)
	-- one long frame (a hitch) pushes the average up for a second: only count
	-- it as lag when most of the frames were slow
	local slow = 0
	for _, f in ipairs(frames) do if f > TICK * 1.5 then slow = slow + 1 end end
	local steady = slow >= #frames * 0.6

	if avg < limit or not steady then
		if lagSince and state.stage > 0 then
			remember("ok", 0)
			P.Log("security", "l_ac_recovered", { V = math.Round(now - lagSince) })
		end
		lagSince, state.stage = nil, 0
		return
	end
	if now < cooldown then return end
	lagSince = lagSince or now
	local lagFor = now - lagSince
	local ms = math.Round(avg * 1000) .. " ms"
	-- slow for a second and a half before anything is done
	if lagFor < 1.5 then return end
	if state.stage == 0 or state.stage == 2 then
		-- lag without props to blame: the server is slow for another reason
		-- (scripts, the host's game): nothing to freeze, nothing to announce
		if not physicsBusy() then cooldown = now + 3 return end
	end

	if state.stage == 0 then
		local n, owners = freezePenetrating()
		state.stage = 1
		cooldown = now + 1
		local who = ownersText(owners)
		remember("freeze", n, who)
		if n > 0 then
			P.Log("security", "l_ac_freeze", { V = n, V2 = who, S = ms })
			secLog(nil, "ac_freeze", n .. " props, " .. ms .. (who ~= "" and (" - " .. who) or ""))
			alertStaff("n_ac_freeze", { V = n, S = who ~= "" and who or "-" })
		end
	elseif state.stage == 1 and lagFor > 2 then
		state.stage = 2
		cooldown = now + 1
		local owners, total = movingByOwner()
		local ply, cnt = topOwner(owners, total)
		if ply then
			local n = freezeOwner(ply)
			remember("owner", n, ply:Nick())
			P.Log("security", "l_ac_owner", { A = P.LogPly(ply), V = n, S = ms }, { ply })
			secLog(ply, "ac_owner", n .. " props, " .. ms .. ", " .. cnt .. "/" .. total .. " moving")
			alertStaff("n_ac_owner", { S = ply:Nick(), V = n })
		end
	elseif state.stage == 2 and lagFor > 4 then
		local _, owners = freezePenetrating()
		local n = freezeMoving()
		state.stage = 3
		cooldown = now + 2
		remember("all", n, ownersText(owners))
		if n > 0 then
			P.Log("security", "l_ac_freezeall", { V = n, S = ms })
			secLog(nil, "ac_freezeall", n .. " props, " .. ms)
			alertStaff("n_ac_freezeall", { V = n })
		end
	elseif state.stage == 3 and lagFor > 8 and P.Setting("ac_lag_remove") then
		local n = 0
		for e in pairs(frozenByUs) do
			if IsValid(e) then
				local phys = e:GetPhysicsObject()
				if IsValid(phys) and phys:IsPenetrating() then e:Remove() n = n + 1 end
			end
		end
		frozenByUs = setmetatable({}, { __mode = "k" })
		state.stage = 4
		cooldown = now + 5
		remember("remove", n)
		if n > 0 then
			P.Log("security", "l_ac_remove", { V = n })
			secLog(nil, "ac_remove", n .. " props, " .. ms)
			alertStaff("n_ac_remove", { V = n })
		end
	end
end)

-- ------------------------------------------------------------------ spawn guard
-- A prop spawned inside another one starts frozen: piles of props stuck in each
-- other are what crashes the physics.

hook.Add("PlayerSpawnedProp", "Praetor.ACSpawnFreeze", function(ply, _, e)
	if not on("ac_spawn_freeze") then return end
	timer.Simple(0, function()
		if not IsValid(e) then return end
		local phys = e:GetPhysicsObject()
		if IsValid(phys) and phys:IsMotionEnabled() and phys:IsPenetrating() then
			phys:EnableMotion(false)
			phys:Sleep()
		end
	end)
end)

-- ------------------------------------------------------------------ big contraptions
-- Crash dupes are usually many props piled in the same spot and tied with ropes.
-- Pasted frozen they do nothing; unfrozen all at once, the physics has to solve
-- every collision and every rope in one tick and the server hangs or dies.
--  * Piled props: props whose centres sit in the same spot (3 or more in a few
--    units). Normal builds almost never do that, so it is a safe sign.
--  * Unfreezing (physgun reload) a contraption of ac_unfreeze_min+ frozen props:
--    when many of them are piled it stays frozen; otherwise it is unfrozen a few
--    props per tick while the server is watched, and if the ticks turn slow
--    everything goes back to frozen. A normal car or house just unfreezes over a
--    few ticks.
--  * A dupe pasted already unfrozen with many piled props is frozen at once.

-- how many of these entities share their spot with 2+ others
local function piled(list)
	local cells, n = {}, 0
	for _, e in ipairs(list) do
		if IsValid(e) then
			local p = e:WorldSpaceCenter()
			local k = math.floor(p.x / 4) .. ":" .. math.floor(p.y / 4) .. ":" .. math.floor(p.z / 4)
			cells[k] = (cells[k] or 0) + 1
		end
	end
	for _, c in pairs(cells) do if c >= 3 then n = n + c end end
	return n
end
P.ACPiled = piled

local function tooPiled(n, total)
	return n >= math.max(8, math.ceil(total * 0.2))
end

local unfreezeJobs = {}
local jobLast = SysTime()

hook.Add("OnPhysgunReload", "Praetor.ACUnfreeze", function(_, ply)
	if not on("ac_unfreeze") or not IsValid(ply) or P.IsOwner(ply) then return end
	if unfreezeJobs[ply] then return false end
	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() then return end
	local all = constraint.GetAllConstrainedEntities(ent) or { ent }
	local objs, list = {}, {}
	for _, e in pairs(all) do
		if IsValid(e) then
			list[#list + 1] = e
			for i = 0, e:GetPhysicsObjectCount() - 1 do
				local po = e:GetPhysicsObjectNum(i)
				if IsValid(po) and not po:IsMoveable() and hook.Run("CanPlayerUnfreeze", ply, e, po) ~= false then
					objs[#objs + 1] = { e, po }
				end
			end
		end
	end
	local min = math.max(5, tonumber(P.Setting("ac_unfreeze_min")) or 25)
	if #objs < min then return end -- small: GMod unfreezes it as always

	local n = piled(list)
	if tooPiled(n, #list) then
		P.Notify(ply, "n_ac_piled_you", { V = n }, "warn")
		P.Log("security", "l_ac_piled", { A = P.LogPly(ply), V = n, V2 = #list }, { ply })
		secLog(ply, "ac_piled", n .. " / " .. #list .. " props piled, unfreeze refused")
		alertStaff("n_ac_piled", { S = ply:Nick(), V = n })
		return false
	end
	unfreezeJobs[ply] = { objs = objs, i = 0, done = {}, slow = 0, total = #objs }
	ply:SendLua("if GAMEMODE.UnfrozeObjects then GAMEMODE:UnfrozeObjects(" .. #objs .. ") end")
	return false
end)

local function refreeze(job)
	for _, o in ipairs(job.done) do
		if IsValid(o[2]) then
			o[2]:EnableMotion(false)
			o[2]:Sleep()
		end
	end
end

hook.Add("Think", "Praetor.ACUnfreeze", function()
	local now = SysTime()
	local dt = now - jobLast
	jobLast = now
	if not next(unfreezeJobs) then return end
	for ply, job in pairs(unfreezeJobs) do
		-- a very slow tick, or a few slow ones, while it unfreezes: back to frozen
		if job.i > 0 then
			if dt > 0.5 then job.slow = job.slow + 2 elseif dt > 0.2 then job.slow = job.slow + 1 end
		end
		if job.slow >= 2 then
			refreeze(job)
			unfreezeJobs[ply] = nil
			if IsValid(ply) then
				local ms = math.Round(dt * 1000) .. " ms"
				P.Notify(ply, "n_ac_unfreeze_stop_you", { V = #job.done }, "warn")
				P.Log("security", "l_ac_unfreeze_stop", { A = P.LogPly(ply), V = #job.done, V2 = job.total, S = ms }, { ply })
				secLog(ply, "ac_unfreeze", #job.done .. " / " .. job.total .. " props, " .. ms)
				alertStaff("n_ac_unfreeze_stop", { S = ply:Nick(), V = #job.done })
			end
		elseif not IsValid(ply) then
			unfreezeJobs[ply] = nil
		elseif job.i < #job.objs then
			for _ = 1, 6 do
				job.i = job.i + 1
				local o = job.objs[job.i]
				if not o then break end
				if IsValid(o[1]) and IsValid(o[2]) and not o[2]:IsMoveable() then
					o[2]:EnableMotion(true)
					o[2]:Wake()
					job.done[#job.done + 1] = o
				end
			end
			job.finished = now
		elseif now - (job.finished or now) > 3 then
			-- watched for 3 seconds after the last prop: all fine
			unfreezeJobs[ply] = nil
		end
	end
end)
hook.Add("PlayerDisconnected", "Praetor.ACUnfreeze", function(ply) unfreezeJobs[ply] = nil end)

-- a dupe pasted unfrozen with a pile of props in it (called by the dupe guard)
function P.ACCheckPasted(ply, list)
	if not on("ac_unfreeze") or not istable(list) or (IsValid(ply) and P.IsOwner(ply)) then return end
	local arr, moving = {}, 0
	for _, e in pairs(list) do
		if IsValid(e) then
			arr[#arr + 1] = e
			local po = e:GetPhysicsObject()
			if IsValid(po) and po:IsMoveable() then moving = moving + 1 end
		end
	end
	if moving < 5 then return end
	local n = piled(arr)
	if not tooPiled(n, #arr) then return end
	for _, e in ipairs(arr) do
		local po = e:GetPhysicsObject()
		if IsValid(po) then po:EnableMotion(false) po:Sleep() end
	end
	if IsValid(ply) then
		P.Notify(ply, "n_ac_piled_you", { V = n }, "warn")
		P.Log("security", "l_ac_piled", { A = P.LogPly(ply), V = n, V2 = #arr }, { ply })
		secLog(ply, "ac_piled", n .. " / " .. #arr .. " props piled, pasted unfrozen: frozen")
		alertStaff("n_ac_piled", { S = ply:Nick(), V = n })
	end
end

-- ------------------------------------------------------------------ physics budget

local function applyPhysenv()
	if not physenv or not physenv.GetPerformanceSettings then return end
	local s = physenv.GetPerformanceSettings()
	P.ACPhysDefault = P.ACPhysDefault or table.Copy(s)
	if on("ac_physenv") then
		s.MaxCollisionsPerObjectPerTimestep = 6
		s.MaxCollisionChecksPerTimestep = 20000
	else
		s.MaxCollisionsPerObjectPerTimestep = P.ACPhysDefault.MaxCollisionsPerObjectPerTimestep
		s.MaxCollisionChecksPerTimestep = P.ACPhysDefault.MaxCollisionChecksPerTimestep
	end
	physenv.SetPerformanceSettings(s)
end
hook.Add("InitPostEntity", "Praetor.ACPhysenv", applyPhysenv)
hook.Add("Praetor.SettingsChanged", "Praetor.ACPhysenv", applyPhysenv)
timer.Simple(1, applyPhysenv)

-- ------------------------------------------------------------------ broken physics

local WORLD = 32000
timer.Create("Praetor.AntiCrash.Crazy", 1.5, 0, function()
	if not on("ac_crazy") then return end
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and not e:IsPlayer() and not e:IsWorld() and e:EntIndex() > 0 then
			local pos = e:GetPos()
			if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then
				local o = ownerOf(e)
				P.Log("security", "l_ac_nan", { V = e:GetClass(), A = o and P.LogPly(o) or nil }, { o })
				secLog(o, "ac_nan", e:GetClass())
				e:Remove()
			else
				local phys = physOf(e)
				if phys and phys:IsMotionEnabled() then
					local v = phys:GetVelocity()
					local av = phys:GetAngleVelocity()
					if v.x ~= v.x or av.x ~= av.x or v:LengthSqr() > 30000 * 30000 then
						phys:EnableMotion(false)
						phys:SetVelocityInstantaneous(vector_origin)
						local o = ownerOf(e)
						P.Log("security", "l_ac_speed", { V = e:GetClass(), A = o and P.LogPly(o) or nil }, { o })
						secLog(o, "ac_speed", e:GetClass())
					elseif ownerOf(e) and (math.abs(pos.x) > WORLD or math.abs(pos.y) > WORLD or math.abs(pos.z) > WORLD) then
						-- flung out of the map: it would fall forever
						local o = ownerOf(e)
						P.Log("security", "l_ac_speed", { V = e:GetClass(), A = o and P.LogPly(o) or nil }, { o })
						e:Remove()
					end
				end
			end
		end
	end
end)

-- ------------------------------------------------------------------ spawn spam + entity cap

local spawns = {}

local function ownedCount(ply)
	local n = 0
	local list = cleanup.GetList and cleanup.GetList() or {}
	for _, kinds in pairs(list[ply:UniqueID()] or {}) do
		for _, e in pairs(kinds) do if IsValid(e) then n = n + 1 end end
	end
	return n
end

-- dupes spawn a lot of props at once: that is not spam (the dupe guard already
-- checked the size)
local function pasting(ply)
	return ply.PraetorPasting or (ply.AdvDupe2 and ply.AdvDupe2.Pasting) or (ply.AdvDupe and ply.AdvDupe.Pasting)
end

local function spawnGuard(ply)
	if not P.Setting("ac_enabled") or not IsValid(ply) or P.IsOwner(ply) then return end
	local cap = P.Setting("ac_ent_cap")
	if cap > 0 and ownedCount(ply) >= cap then
		if (ply.PraetorCapMsg or 0) < CurTime() then
			ply.PraetorCapMsg = CurTime() + 3
			P.Notify(ply, "err_ent_cap", { V = cap })
		end
		return false
	end
	if not P.Setting("ac_spam") or pasting(ply) then return end
	local now = CurTime()
	local list = spawns[ply] or {}
	spawns[ply] = list
	local window = P.Setting("ac_spam_secs")
	while list[1] and list[1] < now - window do table.remove(list, 1) end
	if #list >= P.Setting("ac_spam_count") then
		if (ply.PraetorSpamMsg or 0) < now then
			ply.PraetorSpamMsg = now + 3
			P.Notify(ply, "err_spawn_spam")
			ply.PraetorSpamHits = (ply.PraetorSpamHits or 0) + 1
			if ply.PraetorSpamHits % 5 == 0 then
				P.Log("security", "l_ac_spam", { A = P.LogPly(ply) }, { ply })
				secLog(ply, "ac_spam", tostring(#list) .. " / " .. window .. "s")
				alertStaff("n_ac_spam", { S = ply:Nick() })
			end
		end
		return false
	end
	list[#list + 1] = now
end

for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnRagdoll", "PlayerSpawnVehicle", "PlayerSpawnNPC", "PlayerSpawnEffect" }) do
	hook.Add(h, "Praetor.AntiCrash", spawnGuard)
end
hook.Add("PlayerDisconnected", "Praetor.AntiCrash", function(ply) spawns[ply] = nil end)

-- ------------------------------------------------------------------ chat flood

local chats = {}
hook.Add("PlayerSay", "Praetor.AntiCrashChat", function(ply, text)
	if not on("ac_chat") or P.IsOwner(ply) or P.Has(ply, "adminchat") then return end
	local now = CurTime()
	local list = chats[ply] or {}
	chats[ply] = list
	local window = P.Setting("ac_chat_secs")
	while list[1] and list[1] < now - window do table.remove(list, 1) end
	list[#list + 1] = now
	if #list > P.Setting("ac_chat_count") then
		chats[ply] = {}
		P.SetMute(ply, 2, nil)
		P.Notify(ply, "n_ac_chatmute")
		P.Log("security", "l_ac_chat", { A = P.LogPly(ply) }, { ply })
		secLog(ply, "ac_chat", #list .. " / " .. window .. "s")
		return ""
	end
end)
hook.Add("PlayerDisconnected", "Praetor.AntiCrashChat", function(ply) chats[ply] = nil end)

-- ------------------------------------------------------------------ net flood

local netCount, netSecond = {}, 0
P._origIncoming = P._origIncoming or net.Incoming
local origIncoming = P._origIncoming
function net.Incoming(len, client)
	if IsValid(client) and P.Setting("ac_enabled") and P.Setting("ac_net") then
		local sec = math.floor(SysTime())
		if sec ~= netSecond then netSecond = sec netCount = {} end
		local n = (netCount[client] or 0) + 1
		netCount[client] = n
		local limit = P.Setting("ac_net_limit")
		if n > limit then
			if n == limit + 1 then
				P.Security(client, "net_flood", n .. " msgs/s")
				P.Log("security", "l_ac_net", { A = P.LogPly(client), V = n }, { client })
				if not P.IsOwner(client) then client:Kick("Network flood / Flood de rede") end
			end
			return
		end
	end
	return origIncoming(len, client)
end

-- ------------------------------------------------------------------ live status
-- The Security tab asks every two seconds while it is open.

P.Receive("ac_status", { perm = "security", rate = 2 }, function(ply)
	local props, awake, ents_, owners = 0, 0, 0, {}
	for _, e in ipairs(ents.GetAll()) do
		ents_ = ents_ + 1
		local o = ownerOf(e)
		if o then
			local row = owners[o]
			if not row then row = { 0, 0 } owners[o] = row end
			row[1] = row[1] + 1
			props = props + 1
			local phys = physOf(e)
			if phys and phys:IsMotionEnabled() and not phys:IsAsleep() then
				awake = awake + 1
				row[2] = row[2] + 1
			end
		end
	end
	local top = {}
	for p, r in pairs(owners) do
		if IsValid(p) then top[#top + 1] = { n = p:Nick(), s = p:SteamID64(), c = r[1], a = r[2] } end
	end
	table.sort(top, function(a, b) if a.a ~= b.a then return a.a > b.a end return a.c > b.c end)
	while #top > 6 do table.remove(top) end
	P.Send(ply, "ac_status", {
		on = P.Setting("ac_enabled") and 1 or nil,
		avg = math.Round(state.avg, 1), peak = math.Round(state.peak, 1), tick = math.Round(TICK * 1000, 1),
		limit = P.Setting("ac_lag_ms"), stage = state.stage,
		ents = ents_, props = props, awake = awake, top = top, hist = history, acts = state.actions,
	})
	state.peak = 0
end)

-- staff can unfreeze what the anti-crash froze (after fixing the cause)
P.Receive("ac_unfreeze", { perm = "security", rate = 0.5 }, function(ply)
	local n = 0
	for e in pairs(frozenByUs) do
		if IsValid(e) then
			local phys = e:GetPhysicsObject()
			if IsValid(phys) and not phys:IsPenetrating() then phys:EnableMotion(true) phys:Wake() n = n + 1 end
		end
	end
	frozenByUs = setmetatable({}, { __mode = "k" })
	P.Log("security", "l_ac_unfreeze", { A = P.LogPly(ply), V = n }, { ply })
	P.Notify(ply, "n_ac_unfrozen", { V = n }, "ok")
end)
