-- Praetor: player states (mute, gag, jail, freeze, god, cloak, speed, scale),
-- teleport helpers, spectate, physgun on players.
local P = Praetor

local function untilFrom(minutes)
	if minutes == nil or minutes < 0 then return 0 end
	if minutes == 0 then return -1 end
	return os.time() + minutes * 60
end

local function active(u) return u == -1 or (u and u > os.time()) end

-- ------------------------------------------------------------------ mute / gag

function P.SetMute(ply, minutes, actor)
	local u = untilFrom(minutes)
	ply.PraetorMute = u
	ply:SetNW2Bool("pr_muted", active(u))
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET mute_until = ? WHERE sid = ?", u, ply:SteamID64()) end
	P.Log("punish", u == 0 and "l_unmute" or "l_mute", { A = P.LogPly(actor), T = P.LogPly(ply), V = minutes and minutes > 0 and P.FormatDuration(minutes) or nil }, { actor, ply })
end

function P.SetGag(ply, minutes, actor)
	local u = untilFrom(minutes)
	ply.PraetorGag = u
	ply:SetNW2Bool("pr_gagged", active(u))
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET gag_until = ? WHERE sid = ?", u, ply:SteamID64()) end
	P.Log("punish", u == 0 and "l_ungag" or "l_gag", { A = P.LogPly(actor), T = P.LogPly(ply), V = minutes and minutes > 0 and P.FormatDuration(minutes) or nil }, { actor, ply })
end

function P.IsMuted(ply) return active(ply.PraetorMute) end
function P.IsGagged(ply) return active(ply.PraetorGag) end

local muteNotice = {}
function P.ChatBlocked(ply, text)
	if not P.IsMuted(ply) then return false end
	if (muteNotice[ply] or 0) < CurTime() then
		muteNotice[ply] = CurTime() + 4
		P.Notify(ply, "err_muted")
	end
	return true
end

hook.Add("PlayerCanHearPlayersVoice", "Praetor.Gag", function(listener, talker)
	if talker.PraetorGag and P.IsGagged(talker) then return false, false end
end)

-- ------------------------------------------------------------------ jail
-- A real cell (the praetor_jail entity) around the player. Without a time the
-- jail has no end: only !unjail lets the player out. The player sees how long is
-- left (live), who jailed them and why; the others see it on a sign over the cell.
-- Who and why are kept in data/praetor/jail_info.txt, so they survive a reconnect.

local INFO_FILE = "praetor/jail_info.txt"
local jailInfo
local function infoTable()
	if not jailInfo then
		jailInfo = util.JSONToTable(file.Read(INFO_FILE, "DATA") or "") or {}
	end
	return jailInfo
end
local function saveInfo()
	file.CreateDir("praetor")
	file.Write(INFO_FILE, util.TableToJSON(infoTable()))
end

function P.IsJailed(ply) return ply.PraetorJail ~= nil end

local function removeCell(ply)
	local j = ply.PraetorJail
	if j and IsValid(j.cell) then j.cell:Remove() end
end

local function buildCell(ply)
	local j = ply.PraetorJail
	if not j then return end
	if IsValid(j.cell) then j.cell:Remove() end
	local cell = ents.Create("praetor_jail")
	if not IsValid(cell) then return end
	cell:SetPos(j.pos)
	cell:SetAngles(Angle(0, 0, 0))
	cell:Spawn()
	cell:SetPrisoner(ply)
	j.cell = cell
	-- anyone else standing where the bars go is pushed out, so nobody ends up inside a wall
	for _, o in ipairs(player.GetAll()) do
		if o ~= ply and o:Alive() and not o.PraetorJail then
			local d = o:GetPos() - j.pos
			if math.abs(d.x) < 74 and math.abs(d.y) < 74 and d.z > -40 and d.z < 120 then
				local out = Vector(d.x, d.y, 0)
				if out:LengthSqr() < 1 then out = Vector(1, 0, 0) end
				out:Normalize()
				o:SetPos(j.pos + out * 110 + Vector(0, 0, 4))
			end
		end
	end
end

-- the cell stands on the ground below the spot (not in the air if they were jumping)
function P.JailGround(pos, ignore)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 2048), filter = ignore, mask = MASK_PLAYERSOLID_BRUSHONLY })
	return tr.Hit and tr.HitPos or pos
end

local function actorName(actor)
	if actor == false then return "" end
	if actor == nil then return "Praetor" end -- automatic (warning points, custom commands)
	if IsValid(actor) and actor:IsPlayer() then return actor:Nick() end
	return "Console"
end

function P.Jail(ply, minutes, actor, pos, reason)
	if ply:InVehicle() then ply:ExitVehicle() end
	if ply:GetMoveType() == MOVETYPE_NOCLIP then ply:SetMoveType(MOVETYPE_WALK) end
	local restoring = actor == false
	pos = P.JailGround(pos or ply:GetPos(), ply)
	local u = untilFrom(minutes or 0)
	removeCell(ply)
	local sid = ply:SteamID64()
	local info = infoTable()[sid or ""] or {}
	if not restoring then
		info = { by = actorName(actor), r = P.Str(tostring(reason or ""), 120), len = (minutes or 0) * 60 }
		if sid and not ply:IsBot() then infoTable()[sid] = info saveInfo() end
	end
	ply.PraetorJail = { pos = pos, u = u }
	ply:SetNW2Vector("pr_jailpos", pos)
	ply:SetNW2Bool("pr_jailed", true)
	ply:SetNW2Int("pr_jailu", u)
	-- the time left goes as CurTime (the same clock on every side), not os.time
	local left = u > 0 and (u - os.time()) or 0
	ply:SetNW2Float("pr_jailend", u > 0 and (CurTime() + left) or 0)
	ply:SetNW2Float("pr_jaillen", u > 0 and math.max(left, tonumber(info.len) or 0) or 0)
	ply:SetNW2String("pr_jailby", tostring(info.by or ""))
	ply:SetNW2String("pr_jailr", tostring(info.r or ""))
	ply:SetVelocity(-ply:GetVelocity())
	ply:SetPos(pos)
	ply:StripWeapons()
	buildCell(ply)
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET jail_until = ? WHERE sid = ?", u, ply:SteamID64()) end
	if not restoring then
		P.Log("punish", "l_jail", { A = P.LogPly(actor), T = P.LogPly(ply), V = minutes and minutes > 0 and P.FormatDuration(minutes) or nil }, { actor, ply })
		P.Notify(ply, u > 0 and "n_jailed_t" or "n_jailed", { S = info.by ~= "" and info.by or "?", V = minutes and minutes > 0 and P.FormatDuration(minutes) or "", V2 = info.r ~= "" and info.r or "@jail_no_reason" }, "warn")
	end
end

function P.Unjail(ply, actor)
	if not ply.PraetorJail then return end
	removeCell(ply)
	ply.PraetorJail = nil
	ply:SetNW2Bool("pr_jailed", false)
	local sid = ply:SteamID64()
	if sid and infoTable()[sid] then infoTable()[sid] = nil saveInfo() end
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET jail_until = 0 WHERE sid = ?", ply:SteamID64()) end
	P.Log("punish", "l_unjail", { A = P.LogPly(actor), T = P.LogPly(ply) }, { actor, ply })
	if ply:Alive() then
		hook.Run("PlayerLoadout", ply)
	end
end

-- the cell can't be touched, and comes back after a map cleanup
local function isCell(ent) return IsValid(ent) and ent:GetClass() == "praetor_jail" end
hook.Add("PhysgunPickup", "Praetor.JailCell", function(_, ent) if isCell(ent) then return false end end)
hook.Add("CanTool", "Praetor.JailCell", function(_, tr) if tr and isCell(tr.Entity) then return false end end)
hook.Add("CanProperty", "Praetor.JailCell", function(_, _, ent) if isCell(ent) then return false end end)
hook.Add("GravGunPickupAllowed", "Praetor.JailCell", function(_, ent) if isCell(ent) then return false end end)
hook.Add("PostCleanupMap", "Praetor.JailCell", function()
	for _, ply in ipairs(player.GetAll()) do
		if ply.PraetorJail then buildCell(ply) end
	end
end)
hook.Add("PlayerDisconnected", "Praetor.JailCell", function(ply) removeCell(ply) end)

local function jailBlock(ply) if ply.PraetorJail then return false end end
for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerSpawnVehicle", "PlayerSpawnNPC",
	"PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnObject", "PlayerGiveSWEP", "CanPlayerSuicide",
	"PlayerCanPickupWeapon", "PlayerUse", "CanTool", "PlayerNoClip" }) do
	hook.Add(h, "Praetor.Jail", jailBlock)
end
hook.Add("playerCanChangeTeam", "Praetor.Jail", function(ply)
	if ply.PraetorJail then return false, "Jailed" end
end)

hook.Add("PlayerSpawn", "Praetor.States", function(ply)
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		if ply.PraetorJail then
			ply:SetPos(ply.PraetorJail.pos)
			ply:StripWeapons()
		end
		if ply.PraetorGod then ply:GodEnable() end
		if ply.PraetorSpeed and ply.PraetorSpeed ~= 1 then P.SetSpeed(ply, ply.PraetorSpeed) end
		if ply.PraetorScale and ply.PraetorScale ~= 1 then P.SetScale(ply, ply.PraetorScale) end
		if ply.PraetorCloak then P.SetCloak(ply, true) end
	end)
end)

hook.Add("Praetor.UserLoaded", "Praetor.States", function(ply, row)
	local mu, gu, ju = tonumber(row.mute_until) or 0, tonumber(row.gag_until) or 0, tonumber(row.jail_until) or 0
	if active(mu) then ply.PraetorMute = mu ply:SetNW2Bool("pr_muted", true) end
	if active(gu) then ply.PraetorGag = gu ply:SetNW2Bool("pr_gagged", true) end
	if active(ju) then
		timer.Simple(2, function()
			if not IsValid(ply) then return end
			local minutes = ju == -1 and 0 or math.max(1, math.ceil((ju - os.time()) / 60))
			P.Jail(ply, minutes, false)
		end)
	end
end)

timer.Create("Praetor.States", 0.5, 0, function()
	local now = os.time()
	for _, ply in ipairs(player.GetAll()) do
		local j = ply.PraetorJail
		if j then
			if j.u > 0 and j.u <= now then
				P.Unjail(ply)
				P.Notify(ply, "n_unjailed", nil, "ok")
			elseif ply:Alive() and ply:GetPos():DistToSqr(j.pos) > 60 * 60 then
				ply:SetPos(j.pos)
				ply:SetVelocity(-ply:GetVelocity())
			end
		end
		if ply.PraetorMute and ply.PraetorMute > 0 and ply.PraetorMute <= now then
			ply.PraetorMute = 0
			ply:SetNW2Bool("pr_muted", false)
			P.Notify(ply, "n_unmuted", nil, "ok")
		end
		if ply.PraetorGag and ply.PraetorGag > 0 and ply.PraetorGag <= now then
			ply.PraetorGag = 0
			ply:SetNW2Bool("pr_gagged", false)
		end
	end
end)

-- ------------------------------------------------------------------ freeze / god / cloak / speed / scale

function P.Freeze(ply, on)
	ply:Freeze(on)
	ply:SetNW2Bool("pr_frozen", on)
	if on then ply:SetVelocity(-ply:GetVelocity()) end
	if not on and ply.PraetorPhysFrozen then
		ply.PraetorPhysFrozen = nil
		ply:SetMoveType(MOVETYPE_WALK)
		ply.PraetorNoFall = CurTime() + 4
	end
end

function P.SetGod(ply, on)
	ply.PraetorGod = on or nil
	ply:SetNW2Bool("pr_god", on)
	if on then ply:GodEnable() else ply:GodDisable() end
end

function P.SetCloak(ply, on)
	ply.PraetorCloak = on or nil
	ply:SetNW2Bool("pr_cloak", on)
	ply:SetNoDraw(on)
	ply:DrawShadow(not on)
	ply:SetRenderMode(on and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
	ply:SetColor(Color(255, 255, 255, on and 0 or 255))
	for _, w in ipairs(ply:GetWeapons()) do w:SetNoDraw(on) end
end

hook.Add("PlayerSwitchWeapon", "Praetor.Cloak", function(ply, _, new)
	if ply.PraetorCloak and IsValid(new) then timer.Simple(0, function() if IsValid(new) then new:SetNoDraw(true) end end) end
end)

function P.SetSpeed(ply, mult)
	ply.PraetorSpeedBase = ply.PraetorSpeedBase or { ply:GetWalkSpeed(), ply:GetRunSpeed() }
	ply.PraetorSpeed = mult
	local b = ply.PraetorSpeedBase
	ply:SetWalkSpeed(b[1] * mult)
	ply:SetRunSpeed(b[2] * mult)
	if mult == 1 then ply.PraetorSpeedBase = nil end
end

function P.SetScale(ply, s)
	ply.PraetorScale = s
	ply:SetModelScale(s, 0.4)
	ply:SetViewOffset(Vector(0, 0, 64 * s))
	ply:SetViewOffsetDucked(Vector(0, 0, 28 * s))
	ply:SetHull(Vector(-16, -16, 0) * s, Vector(16, 16, 72) * s)
	ply:SetHullDuck(Vector(-16, -16, 0) * s, Vector(16, 16, 36) * s)
	ply:SetStepSize(18 * math.max(s, 0.5))
	if s == 1 then ply:ResetHull() end
end

-- ------------------------------------------------------------------ teleport helpers

local offsets = {}
for i = 0, 7 do
	local a = math.rad(i * 45)
	offsets[#offsets + 1] = Vector(math.cos(a), math.sin(a), 0)
end

-- Free spot next to `target` for `mover` (or a standard player hull).
function P.FindSpot(target, mover)
	local base = target:GetPos()
	local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
	if IsValid(mover) then mins, maxs = mover:GetHull() end
	local fwd = target:GetForward()
	fwd.z = 0
	fwd:Normalize()
	local tries = { fwd }
	for _, o in ipairs(offsets) do tries[#tries + 1] = o end
	for _, dist in ipairs({ 52, 80, 120 }) do
		for _, dir in ipairs(tries) do
			local pos = base + dir * dist + Vector(0, 0, 6)
			local tr = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID })
			local los = util.TraceLine({ start = base + Vector(0, 0, 40), endpos = pos + Vector(0, 0, 40), mask = MASK_SOLID_BRUSHONLY })
			if not tr.Hit and not los.Hit then return pos end
		end
	end
	local up = base + Vector(0, 0, 80)
	local tr = util.TraceHull({ start = up, endpos = up, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID })
	if not tr.Hit then return up end
end

function P.SaveReturn(ply)
	ply.PraetorReturn = { pos = ply:GetPos(), ang = ply:EyeAngles() }
end

function P.DoReturn(ply)
	local r = ply.PraetorReturn
	if not r then return false end
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:SetPos(r.pos)
	ply:SetEyeAngles(r.ang)
	ply.PraetorReturn = nil
	return true
end

-- Removes everything a player spawned. Returns how many entities were removed.
function P.ClearProps(ply)
	local n = 0
	local uid = ply:UniqueID()
	local list = cleanup.GetList and cleanup.GetList() or {}
	for _, kinds in pairs(list[uid] or {}) do
		for _, e in pairs(kinds) do
			if IsValid(e) then e:Remove() n = n + 1 end
		end
	end
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and not e:IsPlayer() and not e:IsWeapon() then
			local owner = (e.CPPIGetOwner and e:CPPIGetOwner()) or (e.GetCreator and e:GetCreator())
			if owner == ply then e:Remove() n = n + 1 end
		end
	end
	return n
end

-- ------------------------------------------------------------------ spectate

function P.StartSpectate(ply, target)
	ply.PraetorSpec = target
	ply:SetNW2Entity("pr_spec", target)
	P.Log("cmd", "l_spectate", { A = P.LogPly(ply), T = P.LogPly(target) }, { ply, target })
end

function P.StopSpectate(ply)
	ply.PraetorSpec = nil
	ply:SetNW2Entity("pr_spec", NULL)
end

P.Receive("spec_stop", { rate = 4 }, function(ply) P.StopSpectate(ply) end)
P.Receive("spec_next", { rate = 4, perm = "spectate" }, function(ply, data)
	local list = {}
	for _, p in ipairs(player.GetAll()) do if p ~= ply then list[#list + 1] = p end end
	if #list == 0 then return end
	local cur = ply.PraetorSpec
	local idx = 1
	for i, p in ipairs(list) do if p == cur then idx = i end end
	idx = idx + ((tonumber(data.dir) or 1) >= 0 and 1 or -1)
	if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
	P.StartSpectate(ply, list[idx])
end)

hook.Add("SetupPlayerVisibility", "Praetor.Spectate", function(ply)
	local t = ply.PraetorSpec
	if IsValid(t) then AddOriginToPVS(t:GetPos()) end
end)

hook.Add("PlayerDisconnected", "Praetor.Spectate", function(ply)
	for _, p in ipairs(player.GetAll()) do
		if p.PraetorSpec == ply then P.StopSpectate(p) end
	end
end)

-- ------------------------------------------------------------------ physgun on players

hook.Add("PhysgunPickup", "Praetor.Physgun", function(ply, ent)
	if not IsValid(ent) or not ent:IsPlayer() then return end
	if not P.Setting("physgun_players") or not P.Has(ply, "physgun_players") then return end
	if not P.CanTarget(ply, ent) then return false end -- lower ranks can't hold higher ranks
	ent.PraetorHeldBy = ply
	ent:SetMoveType(MOVETYPE_NONE)
	ent:SetVelocity(-ent:GetVelocity())
	return true
end)

-- Right click while holding = freeze in place (in the air too), like a prop. Right click again
-- on a held frozen player = unfreeze. No chat line: it is the physgun, not the !freeze command.
-- While frozen by the physgun the player takes no damage and can't move, shoot or use.
hook.Add("PhysgunDrop", "Praetor.Physgun", function(ply, ent)
	if not IsValid(ent) or not ent:IsPlayer() or ent.PraetorHeldBy ~= ply then return end
	ent.PraetorHeldBy = nil
	local right = P.Setting("physgun_freeze") and ply:KeyDown(IN_ATTACK2)
	if right and not ent.PraetorPhysFrozen then
		ent.PraetorPhysFrozen = true
		ent:SetMoveType(MOVETYPE_NONE)
		ent:SetLocalVelocity(vector_origin)
		ent:Freeze(true)
		ent:SetNW2Bool("pr_frozen", true)
		return
	end
	if ent.PraetorPhysFrozen then
		if not right then -- just moved while frozen: stays frozen where it was dropped
			ent:SetMoveType(MOVETYPE_NONE)
			ent:SetLocalVelocity(vector_origin)
			return
		end
		P.Freeze(ent, false)
		ent:SetLocalVelocity(vector_origin)
		return
	end
	ent:SetMoveType(MOVETYPE_WALK)
	ent.PraetorNoFall = CurTime() + 4
	ent:SetLocalVelocity(vector_origin)
end)

hook.Add("EntityTakeDamage", "Praetor.PhysFreeze", function(ent)
	if ent:IsPlayer() and ent.PraetorPhysFrozen then return true end
end)

local function clearPhysFreeze(ply)
	if ply.PraetorPhysFrozen then
		ply.PraetorPhysFrozen = nil
		ply:Freeze(false)
		ply:SetNW2Bool("pr_frozen", false)
	end
end
hook.Add("PlayerSpawn", "Praetor.PhysFreeze", clearPhysFreeze)
hook.Add("PlayerDeath", "Praetor.PhysFreeze", clearPhysFreeze)

hook.Add("GetFallDamage", "Praetor.Physgun", function(ply)
	if ply.PraetorNoFall and ply.PraetorNoFall > CurTime() then return 0 end
end)

hook.Add("PlayerNoClip", "Praetor.NoclipKey", function(ply, desired)
	if ply.PraetorJail or ply:GetNW2Bool("pr_frozen") then return false end
	if desired and P.Has(ply, "noclip_key") then return true end
end)

