-- Praetor: game logs. Deaths with job / role, connections, names, vehicles,
-- noclip, DarkRP (jobs, police, money, shops, doors, hits, laws, lottery)
-- and TTT rounds. Hooks of a gamemode that is not running never fire, so
-- everything can stay registered.
local P = Praetor

local LP = function(p) return P.LogPly(p) end

-- some events can repeat fast; each key is logged at most once per window
local seen = {}
local function every(key, secs)
	local t = seen[key]
	if t and t > CurTime() then return false end
	seen[key] = CurTime() + secs
	return true
end
timer.Create("Praetor.LogSeenGC", 60, 0, function()
	local now = CurTime()
	for k, v in pairs(seen) do if v < now then seen[k] = nil end end
end)

local function col(c) return c and { r = c.r, g = c.g, b = c.b } or nil end

local function teamTag(t)
	if not t or t == TEAM_CONNECTING or t == TEAM_UNASSIGNED or t == TEAM_SPECTATOR then return nil end
	local name = team.GetName(t)
	if not name or name == "" or name == "Unassigned" then return nil end
	return { n = name, c = col(team.GetColor(t)) }
end

local TTT_COL = { traitor = Color(200, 60, 60), detective = Color(70, 120, 220), innocent = Color(90, 170, 80) }

-- DarkRP job, TTT role or the team of team based gamemodes
local function role(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return nil end
	if ply.GetRoleString and engine.ActiveGamemode() == "terrortown" then
		local r = ply:GetRoleString()
		if isstring(r) and r ~= "" then return { n = r, c = col(TTT_COL[r]) } end
	end
	if engine.ActiveGamemode() == "sandbox" then return nil end
	return teamTag(ply:Team())
end

local function owner(e)
	if not IsValid(e) then return nil end
	local o = (e.CPPIGetOwner and e:CPPIGetOwner()) or (e.GetCreator and e:GetCreator())
	if IsValid(o) and o:IsPlayer() then return o end
	if e.getDoorOwner then
		local d = e:getDoorOwner()
		if IsValid(d) then return d end
	end
	return nil
end
P.EntOwner = owner

-- physics props (the things people throw and push with)
local function isProp(e)
	if not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsWeapon() or e:IsVehicle() then return false end
	local c = e:GetClass()
	return c:sub(1, 12) == "prop_physics" or c == "prop_ragdoll" or (e:GetMoveType() == MOVETYPE_VPHYSICS and (e:GetModel() or ""):find("%.mdl$") ~= nil)
end
P.IsPropEnt = isProp

-- who is responsible for a prop: whoever holds it or threw it in the last
-- 6 seconds, else the attacker given by the engine, else the owner
local function culprit(prop, att)
	if IsValid(prop.PraetorHolder) then return prop.PraetorHolder end
	if IsValid(prop.PraetorThrower) and (prop.PraetorThrowT or 0) > CurTime() - 6 then return prop.PraetorThrower end
	if IsValid(att) and att:IsPlayer() then return att end
	return owner(prop)
end

local function weaponOf(ent)
	if not IsValid(ent) then return "world" end
	if ent:IsPlayer() then
		local w = ent:GetActiveWeapon()
		return IsValid(w) and w:GetClass() or "hands"
	end
	return ent:GetClass()
end

local function money(v)
	v = tonumber(v) or 0
	if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(v) end
	return tostring(v)
end

local function shortModel(m)
	m = tostring(m or "")
	return m:match("([^/]+)%.mdl$") or m
end

-- ------------------------------------------------------------------ deaths

hook.Add("DoPlayerDeath", "Praetor.LogDeathType", function(ply, attacker, dmg)
	ply.PraetorDeathDmg = dmg:GetDamageType()
end)

local function has(dtype, flag) return bit.band(dtype, flag) ~= 0 end

hook.Add("PlayerDeath", "Praetor.LogKill", function(victim, inflictor, attacker)
	local dtype = victim.PraetorDeathDmg or 0
	victim.PraetorDeathDmg = nil

	-- vehicles: the driver is the killer
	if IsValid(attacker) and attacker:IsVehicle() and IsValid(attacker:GetDriver()) then
		local d = attacker:GetDriver()
		if d ~= victim then
			P.Log("kill", "l_runover", { A = LP(d), T = LP(victim), V = attacker:GetClass() }, { d, victim })
			return
		end
	end

	-- props first: thrown, pushed or dropped on someone
	local prop = (isProp(inflictor) and inflictor) or (isProp(attacker) and attacker) or nil
	if prop then
		local who = culprit(prop, attacker)
		if IsValid(who) and who ~= victim then
			P.Log("kill", "l_propkill", { A = LP(who), T = LP(victim), V = shortModel(prop:GetModel()), M = prop:GetModel() }, { who, victim })
			return
		end
	end

	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
		local w = weaponOf(inflictor == attacker and attacker or inflictor)
		if IsValid(inflictor) and inflictor:IsVehicle() then
			P.Log("kill", "l_runover", { A = LP(attacker), T = LP(victim), V = inflictor:GetClass() }, { attacker, victim })
			return
		end
		local args = { A = LP(attacker), T = LP(victim), V = w, V2 = math.Round(attacker:GetPos():Distance(victim:GetPos()) * 0.01905) }
		local key = "l_kill"
		local ra, rv = role(attacker), role(victim)
		if ra and rv then key = "l_kill_role" args.J = ra args.J2 = rv end
		if victim:LastHitGroup() == HITGROUP_HEAD and not has(dtype, DMG_BLAST) then key = key .. "_hs" end
		P.Log("kill", key, args, { attacker, victim })
		return
	end

	if attacker == victim then
		P.Log("kill", "l_suicide", { A = LP(victim) }, { victim })
		return
	end

	-- props: the owner is named (prop kill)
	local thing = (IsValid(attacker) and not attacker:IsWorld() and attacker) or (IsValid(inflictor) and not inflictor:IsWorld() and inflictor) or nil
	if thing and not thing:IsPlayer() and not thing:IsNPC() then
		local o = owner(thing)
		if o and o ~= victim then
			P.Log("kill", "l_propkill", { A = LP(o), T = LP(victim), V = shortModel(thing:GetModel()), M = thing:GetModel() }, { o, victim })
			return
		end
	end
	if IsValid(attacker) and attacker:IsNPC() then
		P.Log("kill", "l_npckill", { A = LP(victim), V = attacker:GetClass() }, { victim })
		return
	end

	local key = "l_died"
	if has(dtype, DMG_FALL) then key = "l_death_fall"
	elseif has(dtype, DMG_DROWN) then key = "l_death_drown"
	elseif has(dtype, DMG_BURN) or has(dtype, DMG_SLOWBURN) then key = "l_death_fire"
	elseif has(dtype, DMG_BLAST) then key = "l_death_blast"
	elseif has(dtype, DMG_CRUSH) then key = "l_death_crush" end
	P.Log("kill", key, { A = LP(victim), V = thing and (isProp(thing) and shortModel(thing:GetModel()) or thing:GetClass()) or "world", M = thing and isProp(thing) and thing:GetModel() or nil }, { victim })
end)

-- ------------------------------------------------------------------ connections, names

gameevent.Listen("player_connect")
hook.Add("player_connect", "Praetor.LogConnect", function(d)
	if tonumber(d.bot) == 1 then return end
	local sid = util.SteamIDTo64(d.networkid or "")
	sid = sid ~= "0" and sid or nil
	P.Log("conn", "l_connecting", { A = { n = P.Str(d.name, 64), s = sid } }, { sid })
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "Praetor.LogLeave", function(d)
	if tonumber(d.bot) == 1 then return end
	local sid = util.SteamIDTo64(d.networkid or "")
	sid = sid ~= "0" and sid or nil
	P.Log("conn", "l_leave", { A = { n = P.Str(d.name, 64), s = sid }, V = P.Str(d.reason, 120) }, { sid })
end)

gameevent.Listen("player_changename")
hook.Add("player_changename", "Praetor.LogName", function(d)
	local ply = Player(d.userid)
	if not IsValid(ply) then return end
	P.Log("player", "l_rename", { A = LP(ply), V = P.Str(d.oldname, 64), V2 = P.Str(d.newname, 64) }, { ply })
end)

-- ------------------------------------------------------------------ sandbox

hook.Add("PlayerGiveSWEP", "Praetor.LogGive", function(ply, class)
	if not P.Setting("log_props") or not every(ply:EntIndex() .. "give" .. class, 3) then return end
	P.Log("prop", "l_giveswep", { A = LP(ply), V = class }, { ply })
end)

hook.Add("PlayerSpawnedEffect", "Praetor.Log", function(ply, model)
	if not P.Setting("log_props") then return end
	P.Log("prop", "l_spawn", { A = LP(ply), V = "effect", V2 = model }, { ply })
end)

hook.Add("PlayerNoClip", "Praetor.LogNoclip", function(ply)
	local before = ply:GetMoveType() == MOVETYPE_NOCLIP
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		local now = ply:GetMoveType() == MOVETYPE_NOCLIP
		if now ~= before and every(ply:EntIndex() .. "noclip", 1) then
			P.Log("player", now and "l_noclip_on" or "l_noclip_off", { A = LP(ply) }, { ply })
		end
	end)
end)

hook.Add("PlayerEnteredVehicle", "Praetor.LogVehicle", function(ply, veh)
	if not IsValid(veh) or not every(ply:EntIndex() .. "veh" .. veh:EntIndex(), 10) then return end
	-- seats inside other vehicles and chairs are noise
	if veh:GetClass() == "prop_vehicle_prisoner_pod" and IsValid(veh:GetParent()) then return end
	local o = owner(veh)
	if o and o ~= ply then
		P.Log("player", "l_vehicle_in_other", { A = LP(ply), T = LP(o), V = shortModel(veh:GetModel()) }, { ply, o })
	else
		P.Log("player", "l_vehicle_in", { A = LP(ply), V = shortModel(veh:GetModel()) }, { ply })
	end
end)

-- ------------------------------------------------------------------ props: push, damage

local function stopWatching(ent)
	if ent.PraetorCollideCB then
		ent:RemoveCallback("PhysicsCollide", ent.PraetorCollideCB)
		ent.PraetorCollideCB = nil
	end
end

local function onCollide(ent, data)
	local hit = data.HitEntity
	if not IsValid(hit) or not hit:IsPlayer() then return end
	local who = culprit(ent)
	if not IsValid(who) or who == hit then return end
	if not every(ent:EntIndex() .. "push" .. hit:EntIndex(), 4) then return end
	P.Log("prop", "l_proppush", { A = LP(who), T = LP(hit), V = shortModel(ent:GetModel()), M = ent:GetModel() }, { who, hit })
end

hook.Add("OnPhysgunPickup", "Praetor.LogPropHold", function(ply, ent)
	if not isProp(ent) then return end
	ent.PraetorHolder = ply
	if not ent.PraetorCollideCB then ent.PraetorCollideCB = ent:AddCallback("PhysicsCollide", onCollide) end
end)

hook.Add("PhysgunDrop", "Praetor.LogPropHold", function(ply, ent)
	if not IsValid(ent) or ent.PraetorHolder ~= ply then return end
	ent.PraetorHolder = nil
	ent.PraetorThrower = ply
	ent.PraetorThrowT = CurTime()
	local stamp = CurTime()
	timer.Simple(6, function()
		if IsValid(ent) and not IsValid(ent.PraetorHolder) and ent.PraetorThrowT == stamp then stopWatching(ent) end
	end)
end)

hook.Add("PostEntityTakeDamage", "Praetor.LogPropDamage", function(victim, dmg, took)
	if not took or not P.Setting("log_damage") or not IsValid(victim) or not victim:IsPlayer() then return end
	local infl, att = dmg:GetInflictor(), dmg:GetAttacker()
	local prop = (isProp(infl) and infl) or (isProp(att) and att) or nil
	if not prop then return end
	local who = culprit(prop, att)
	if not IsValid(who) or who == victim then return end
	if not every(prop:EntIndex() .. "pdmg" .. victim:EntIndex(), 1.5) then return end
	P.Log("dmg", "l_propdmg", { A = LP(who), T = LP(victim), V = math.Round(dmg:GetDamage()), V2 = shortModel(prop:GetModel()), M = prop:GetModel() }, { who, victim })
end)

hook.Add("OnPhysgunPickup", "Praetor.LogPhysPly", function(ply, ent)
	if not IsValid(ent) or not ent:IsPlayer() or not every(ply:EntIndex() .. "phys" .. ent:EntIndex(), 5) then return end
	P.Log("player", "l_physgun_ply", { A = LP(ply), T = LP(ent) }, { ply, ent })
end)

-- ------------------------------------------------------------------ jobs / teams

hook.Add("OnPlayerChangedTeam", "Praetor.LogTeam", function(ply, old, new)
	if old == new or engine.ActiveGamemode() == "sandbox" then return end
	local from, to = teamTag(old), teamTag(new)
	if not to then return end
	if from then
		P.Log(P.IsDarkRP() and "rp" or "player", "l_job", { A = LP(ply), V = from, V2 = to }, { ply })
	else
		P.Log(P.IsDarkRP() and "rp" or "player", "l_job_first", { A = LP(ply), V = to }, { ply })
	end
end)

-- ------------------------------------------------------------------ DarkRP: police

hook.Add("playerArrested", "Praetor.LogArrest", function(ply, time, cop)
	P.Log("rp", "l_arrest", { A = LP(cop), T = LP(ply), V = tostring(time or 0) .. "s" }, { cop, ply })
end)
hook.Add("playerUnArrested", "Praetor.LogUnarrest", function(ply, cop)
	P.Log("rp", "l_unarrest", { A = LP(cop), T = LP(ply) }, { cop, ply })
end)
hook.Add("playerWanted", "Praetor.LogWanted", function(ply, cop, reason)
	P.Log("rp", "l_wanted", { A = LP(cop), T = LP(ply), V = P.Str(reason, 120) }, { cop, ply })
end)
hook.Add("playerUnWanted", "Praetor.LogUnwanted", function(ply, cop)
	P.Log("rp", "l_unwanted", { A = LP(cop), T = LP(ply) }, { cop, ply })
end)
hook.Add("playerWarranted", "Praetor.LogWarrant", function(ply, cop, reason)
	P.Log("rp", "l_warrant", { A = LP(cop), T = LP(ply), V = P.Str(reason, 120) }, { cop, ply })
end)
hook.Add("playerWeaponsConfiscated", "Praetor.LogConfiscate", function(cop, ply)
	P.Log("rp", "l_confiscate", { A = LP(cop), T = LP(ply) }, { cop, ply })
end)
hook.Add("onPlayerDemoted", "Praetor.LogDemote", function(source, target, reason)
	P.Log("rp", "l_rp_demote", { A = LP(source), T = LP(target), V = P.Str(reason, 120) }, { source, target })
end)
hook.Add("onPlayerChangedName", "Praetor.LogRPName", function(ply, old, new)
	P.Log("rp", "l_rpname", { A = LP(ply), V = P.Str(old, 64), V2 = P.Str(new, 64) }, { ply })
end)

-- ------------------------------------------------------------------ DarkRP: money and shops

local function buy(ply, what, price)
	P.Log("money", "l_buy", { A = LP(ply), V = P.Str(what, 60), V2 = money(price) }, { ply })
end
hook.Add("playerBoughtCustomEntity", "Praetor.LogBuy", function(ply, t, ent, price) buy(ply, t and t.name or (IsValid(ent) and ent:GetClass()) or "?", price) end)
hook.Add("playerBoughtShipment", "Praetor.LogBuy", function(ply, t, ent, price) buy(ply, (t and t.name or "?") .. " (shipment)", price) end)
hook.Add("playerBoughtPistol", "Praetor.LogBuy", function(ply, t, wep, price) buy(ply, t and t.name or "?", price) end)
hook.Add("playerBoughtAmmo", "Praetor.LogBuy", function(ply, t, wep, price) buy(ply, t and t.name or "ammo", price) end)
hook.Add("playerBoughtFood", "Praetor.LogBuy", function(ply, t, ent, price) buy(ply, t and t.name or "food", price) end)
hook.Add("playerBoughtVehicle", "Praetor.LogBuy", function(ply, ent, price) buy(ply, IsValid(ent) and shortModel(ent:GetModel()) or "vehicle", price) end)
hook.Add("playerBoughtDoor", "Praetor.LogDoor", function(ply, ent, price)
	P.Log("money", "l_door_buy", { A = LP(ply), V = money(price) }, { ply })
end)
hook.Add("playerKeysSold", "Praetor.LogDoor", function(ply, ent, back)
	P.Log("money", "l_door_sell", { A = LP(ply), V = money(back) }, { ply })
end)

hook.Add("playerGaveMoney", "Praetor.LogMoney", function(ply, target, amount)
	P.Log("money", "l_money_give", { A = LP(ply), T = LP(target), V = money(amount) }, { ply, target })
end)
hook.Add("playerDroppedMoney", "Praetor.LogMoney", function(ply, amount)
	P.Log("money", "l_money_drop", { A = LP(ply), V = money(amount) }, { ply })
end)
hook.Add("playerPickedUpMoney", "Praetor.LogMoney", function(ply, amount)
	P.Log("money", "l_money_pick", { A = LP(ply), V = money(amount) }, { ply })
end)
hook.Add("playerDroppedCheque", "Praetor.LogCheque", function(ply, target, amount)
	P.Log("money", "l_cheque", { A = LP(ply), T = LP(target), V = money(amount) }, { ply, target })
end)
hook.Add("playerPickedUpCheque", "Praetor.LogCheque", function(ply, recipient, amount, success)
	if success then P.Log("money", "l_cheque_cash", { A = LP(ply), V = money(amount) }, { ply }) end
end)
hook.Add("lotteryStarted", "Praetor.LogLottery", function(ply, price)
	P.Log("money", "l_lottery", { A = LP(ply), V = money(price) }, { ply })
end)
hook.Add("lotteryEnded", "Praetor.LogLottery", function(participants, winner, amount)
	if IsValid(winner) then P.Log("money", "l_lottery_win", { A = LP(winner), V = money(amount) }, { winner }) end
end)

-- ------------------------------------------------------------------ DarkRP: crime, doors, hits, government

hook.Add("onLockpickCompleted", "Praetor.LogLockpick", function(ply, success, ent)
	if not success or not IsValid(ent) then return end
	local o = owner(ent)
	P.Log("rp", o and "l_lockpick_owner" or "l_lockpick", { A = LP(ply), T = o and LP(o) or nil, V = ent:GetClass() }, { ply, o })
end)
hook.Add("onDoorRamUsed", "Praetor.LogRam", function(success, ply, tr)
	local ent = tr and tr.Entity
	if not success or not IsValid(ent) then return end
	local o = owner(ent)
	P.Log("rp", o and "l_ram_owner" or "l_ram", { A = LP(ply), T = o and LP(o) or nil, V = ent:GetClass() }, { ply, o })
end)
hook.Add("onHitAccepted", "Praetor.LogHit", function(hitman, target, customer)
	P.Log("rp", "l_hit_accept", { A = LP(hitman), T = LP(target), V = LP(customer) }, { hitman, target, customer })
end)
hook.Add("onHitCompleted", "Praetor.LogHit", function(hitman, target, customer)
	P.Log("rp", "l_hit_done", { A = LP(hitman), T = LP(target), V = LP(customer) }, { hitman, target, customer })
end)
hook.Add("onHitFailed", "Praetor.LogHit", function(hitman, target, reason)
	P.Log("rp", "l_hit_fail", { A = LP(hitman), T = LP(target), V = P.Str(reason, 100) }, { hitman, target })
end)
hook.Add("addLaw", "Praetor.LogLaw", function(index, law, ply)
	P.Log("rp", "l_law_add", { A = LP(ply), V = P.Str(law, 150) }, { ply })
end)
hook.Add("removeLaw", "Praetor.LogLaw", function(index, law, ply)
	P.Log("rp", "l_law_remove", { A = LP(ply), V = P.Str(law, 150) }, { ply })
end)
hook.Add("resetLaws", "Praetor.LogLaw", function(ply)
	P.Log("rp", "l_law_reset", { A = LP(ply) }, { ply })
end)
hook.Add("agendaUpdated", "Praetor.LogAgenda", function(ply, agenda, text)
	if IsValid(ply) then P.Log("rp", "l_agenda", { A = LP(ply), V = P.Str(text, 150) }, { ply }) end
end)
hook.Add("onDarkRPWeaponDropped", "Praetor.LogDrop", function(ply, ent, wep)
	if not IsValid(ply) then return end
	local class = IsValid(wep) and wep:GetClass() or (IsValid(ent) and ent.weaponclass) or "?"
	if every(ply:EntIndex() .. "drop", 2) then P.Log("rp", "l_wep_drop", { A = LP(ply), V = class }, { ply }) end
end)

-- ------------------------------------------------------------------ TTT

hook.Add("TTTBeginRound", "Praetor.LogRound", function()
	P.Log("round", "l_round_start", { V = #player.GetHumans() })
end)
hook.Add("TTTEndRound", "Praetor.LogRound", function(result)
	local key = "l_round_end"
	if WIN_TRAITOR and result == WIN_TRAITOR then key = "l_round_traitors"
	elseif WIN_INNOCENT and result == WIN_INNOCENT then key = "l_round_innocents"
	elseif WIN_TIMELIMIT and result == WIN_TIMELIMIT then key = "l_round_time" end
	P.Log("round", key, {})
end)
hook.Add("TTTOrderedEquipment", "Praetor.LogEquip", function(ply, equipment, isItem)
	local name = tostring(equipment)
	if isItem and GetEquipmentItem then
		local it = GetEquipmentItem(ply:GetRole(), equipment)
		if it and it.name then name = LANG and LANG.TryTranslation and LANG.TryTranslation(it.name) or it.name end
	end
	P.Log("round", "l_ttt_buy", { A = LP(ply), J = role(ply), V = name }, { ply })
end)
hook.Add("TTTBodyFound", "Praetor.LogBody", function(ply, dead)
	if IsValid(ply) and IsValid(dead) then P.Log("round", "l_ttt_body", { A = LP(ply), T = LP(dead) }, { ply, dead }) end
end)
hook.Add("TTTFoundDNA", "Praetor.LogDNA", function(ply, dnaOwner)
	if IsValid(ply) and IsValid(dnaOwner) then P.Log("round", "l_ttt_dna", { A = LP(ply), T = LP(dnaOwner) }, { ply, dnaOwner }) end
end)
