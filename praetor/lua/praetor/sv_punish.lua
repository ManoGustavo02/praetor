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

function P.IsJailed(ply) return ply.PraetorJail ~= nil end

function P.Jail(ply, minutes, actor, pos)
	if ply:InVehicle() then ply:ExitVehicle() end
	if ply:GetMoveType() == MOVETYPE_NOCLIP then ply:SetMoveType(MOVETYPE_WALK) end
	pos = pos or ply:GetPos()
	local u = untilFrom(minutes or 0)
	ply.PraetorJail = { pos = pos, u = u }
	ply:SetNW2Vector("pr_jailpos", pos)
	ply:SetNW2Bool("pr_jailed", true)
	ply:SetNW2Int("pr_jailu", u)
	ply:StripWeapons()
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET jail_until = ? WHERE sid = ?", u, ply:SteamID64()) end
	if actor ~= false then
		P.Log("punish", "l_jail", { A = P.LogPly(actor), T = P.LogPly(ply), V = minutes and minutes > 0 and P.FormatDuration(minutes) or nil }, { actor, ply })
	end
end

function P.Unjail(ply, actor)
	if not ply.PraetorJail then return end
	ply.PraetorJail = nil
	ply:SetNW2Bool("pr_jailed", false)
	if not ply:IsBot() then P.DB.Query("UPDATE praetor_users SET jail_until = 0 WHERE sid = ?", ply:SteamID64()) end
	P.Log("punish", "l_unjail", { A = P.LogPly(actor), T = P.LogPly(ply) }, { actor, ply })
	if ply:Alive() then
		hook.Run("PlayerLoadout", ply)
	end
end

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

