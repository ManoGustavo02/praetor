-- Praetor: prop protection.
--  * everything a player spawns (props, entities, vehicles, NPCs, ragdolls,
--    things made by tools and dupes) belongs to that player;
--  * players only touch their own things: physgun, gravgun, toolgun, the
--    context menu (remove, drive, edit...), unfreeze and damage. Nobody touches
--    the things of others, not of a friend and not of the staff;
--  * ranks with "Touch everyone's props" (pp_all) hold, move, freeze, tool and
--    delete any prop. Deleting someone else's things goes to the logs;
--  * props of someone who left are removed after pp_cleanup_min minutes, unless
--    the player comes back first (the props are theirs again);
--  * map entities (doors, map props) are kept for the staff unless pp_world;
--  * speaks CPPI, so wire, AdvDupe2 and other addons see the owners. When
--    another prop protection runs (FPP from DarkRP, SPP...) Praetor steps aside
--    and only keeps track of the owners.
local P = Praetor
local PP = P.PP or {}
P.PP = PP

-- ------------------------------------------------------------------ owners

local bySid = {} -- sid -> { [ent] = true }

function PP.OwnerSID(e) return IsValid(e) and e.PraetorOwnerSID or nil end

function PP.Owner(e)
	if not IsValid(e) then return nil end
	local o = e.PraetorOwner
	if IsValid(o) then return o end
	local sid = e.PraetorOwnerSID
	if sid then
		o = player.GetBySteamID64(sid)
		if IsValid(o) then e.PraetorOwner = o return o end
	end
end

function PP.SetOwner(e, ply)
	if not IsValid(e) or e:IsPlayer() or e:IsWorld() then return end
	local old = e.PraetorOwnerSID
	if old and bySid[old] then bySid[old][e] = nil end
	if not IsValid(ply) or not ply:IsPlayer() then
		e.PraetorOwner, e.PraetorOwnerSID = nil, nil
		e:SetNW2Entity("pr_owner", NULL)
		e:SetNW2String("pr_osid", "")
		e:SetNW2String("pr_oname", "")
		return
	end
	local sid = ply:SteamID64() or ("bot" .. ply:UserID())
	e.PraetorOwner = ply
	e.PraetorOwnerSID = sid
	bySid[sid] = bySid[sid] or {}
	bySid[sid][e] = true
	e:SetNW2Entity("pr_owner", ply)
	e:SetNW2String("pr_osid", sid)
	e:SetNW2String("pr_oname", ply:Nick())
end

local function claim(ply, e)
	if IsValid(e) and not e.PraetorOwnerSID then PP.SetOwner(e, ply) end
end

hook.Add("PlayerSpawnedProp", "Praetor.PP", function(ply, _, e) claim(ply, e) end)
hook.Add("PlayerSpawnedSENT", "Praetor.PP", function(ply, e) claim(ply, e) end)
hook.Add("PlayerSpawnedVehicle", "Praetor.PP", function(ply, e) claim(ply, e) end)
hook.Add("PlayerSpawnedRagdoll", "Praetor.PP", function(ply, _, e) claim(ply, e) end)
hook.Add("PlayerSpawnedNPC", "Praetor.PP", function(ply, e) claim(ply, e) end)
hook.Add("PlayerSpawnedEffect", "Praetor.PP", function(ply, _, e) claim(ply, e) end)
hook.Add("PlayerSpawnedSWEP", "Praetor.PP", function(ply, e) claim(ply, e) end)

-- things made by tools and dupes go through cleanup.Add and the undo list
local function wrapLibs()
	if cleanup and cleanup.Add and not PP.cleanupWrapped then
		PP.cleanupWrapped = true
		local orig = cleanup.Add
		cleanup.Add = function(ply, kind, e, ...)
			if IsValid(ply) and ply:IsPlayer() then claim(ply, e) end
			return orig(ply, kind, e, ...)
		end
	end
	if undo and undo.Create and not PP.undoWrapped then
		PP.undoWrapped = true
		local cur = { ents = {} }
		local oCreate, oAdd, oPly, oFinish = undo.Create, undo.AddEntity, undo.SetPlayer, undo.Finish
		undo.Create = function(...) cur = { ents = {} } return oCreate(...) end
		undo.AddEntity = function(e, ...)
			if IsValid(e) then cur.ents[#cur.ents + 1] = e end
			return oAdd(e, ...)
		end
		undo.SetPlayer = function(ply, ...)
			cur.ply = ply
			return oPly(ply, ...)
		end
		undo.Finish = function(...)
			if IsValid(cur.ply) and cur.ply:IsPlayer() then
				for _, e in ipairs(cur.ents) do claim(cur.ply, e) end
			end
			cur = { ents = {} }
			return oFinish(...)
		end
	end
end
wrapLibs()
hook.Add("Initialize", "Praetor.PP", wrapLibs)

hook.Add("EntityRemoved", "Praetor.PP", function(e)
	local sid = e.PraetorOwnerSID
	if sid and bySid[sid] then bySid[sid][e] = nil end
end)

function PP.EntsOf(sid)
	local out = {}
	for e in pairs(bySid[sid] or {}) do
		if IsValid(e) then out[#out + 1] = e end
	end
	return out
end

-- ------------------------------------------------------------------ who left / who came back

hook.Add("PlayerDisconnected", "Praetor.PP", function(ply)
	local sid = ply:SteamID64()
	if not sid or not bySid[sid] then return end
	local min = tonumber(P.Setting("pp_cleanup_min")) or 0
	if min <= 0 then return end
	timer.Create("Praetor.PPLeft." .. sid, min * 60, 1, function()
		if IsValid(player.GetBySteamID64(sid)) then return end
		local n = 0
		for _, e in ipairs(PP.EntsOf(sid)) do
			e:Remove()
			n = n + 1
		end
		bySid[sid] = nil
		if n > 0 then P.Log("prop", "l_pp_left", { T = { n = P.KnownName(sid) or sid, s = sid }, V = n }, { sid }) end
	end)
end)

hook.Add("PlayerInitialSpawn", "Praetor.PP", function(ply)
	local sid = ply:SteamID64()
	if not sid then return end
	timer.Remove("Praetor.PPLeft." .. sid)
	for _, e in ipairs(PP.EntsOf(sid)) do PP.SetOwner(e, ply) end
end)

-- ------------------------------------------------------------------ is it on?

local function foreignPP()
	if FPP then return "FPP" end
	if CPPI and not CPPI.Praetor then
		local ok, name = pcall(function() return CPPI:GetName() end)
		return ok and isstring(name) and name or "CPPI"
	end
end

function PP.Active()
	if not P.Setting("pp_enabled") then return false end
	if PP.foreign then return false end
	return true
end

-- ------------------------------------------------------------------ the rule

-- true = may touch, false = may not. kind: "physgun", "gravgun", "tool",
-- "remove", "property", "unfreeze", "damage", "use"
function PP.CanTouch(ply, e, kind)
	if not IsValid(e) or e:IsWorld() then return true end
	if e:IsPlayer() then return true end
	if not IsValid(ply) or not ply:IsPlayer() then return true end
	if e.PraetorSitProp then return P.Has(ply, "pp_all") end
	local sid = e.PraetorOwnerSID
	if sid and sid == ply:SteamID64() then return true end
	if P.Has(ply, "pp_all") then return true end
	if not sid then
		-- a map entity: tools that only stick things to it are fine, the rest is staff only
		if kind == "tool" or kind == "use" then return true end
		return P.Setting("pp_world") == true
	end
	if kind == "use" then return not P.Setting("pp_use") end
	if kind == "damage" then return not P.Setting("pp_damage") end
	return false
end

-- a small "this is X's" flash on the player's screen (at most twice a second)
local function denied(ply, e)
	if not IsValid(ply) then return end
	if (ply.PraetorPPMsg or 0) > CurTime() then return end
	ply.PraetorPPMsg = CurTime() + 0.6
	local sid = e.PraetorOwnerSID
	P.Send(ply, "pp_denied", { e = e:EntIndex(), n = sid and (e:GetNW2String("pr_oname", "") ~= "" and e:GetNW2String("pr_oname") or P.KnownName(sid)) or nil })
end

local function check(ply, e, kind)
	if not PP.Active() then return end
	if PP.CanTouch(ply, e, kind) then return end
	if kind ~= "damage" and kind ~= "use" then denied(ply, e) end
	return false
end

hook.Add("PhysgunPickup", "Praetor.PP", function(ply, e)
	if IsValid(e) and e:IsPlayer() then return end
	return check(ply, e, "physgun")
end)
hook.Add("GravGunPickupAllowed", "Praetor.PP", function(ply, e) return check(ply, e, "gravgun") end)
hook.Add("GravGunPunt", "Praetor.PP", function(ply, e) return check(ply, e, "gravgun") end)
hook.Add("CanPlayerUnfreeze", "Praetor.PP", function(ply, e) return check(ply, e, "unfreeze") end)
hook.Add("CanProperty", "Praetor.PP", function(ply, prop, e)
	local r = check(ply, e, prop == "remove" and "remove" or "property")
	if r == false then return false end
	if prop == "remove" and PP.Active() then PP.LogStaffRemove(ply, e) end
end)
hook.Add("CanDrive", "Praetor.PP", function(ply, e) return check(ply, e, "property") end)
hook.Add("CanEditVariable", "Praetor.PP", function(e, ply) return check(ply, e, "property") end)
hook.Add("PlayerUse", "Praetor.PP", function(ply, e) return check(ply, e, "use") end)

local REMOVE_TOOLS = { remover = true }
hook.Add("CanTool", "Praetor.PP", function(ply, tr, tool)
	local e = tr and tr.Entity
	if not IsValid(e) or e:IsWorld() or e:IsPlayer() then return end
	local kind = REMOVE_TOOLS[tool] and "remove" or "tool"
	if REMOVE_TOOLS[tool] and not e.PraetorOwnerSID and PP.Active() and not P.Setting("pp_world") and not P.Has(ply, "pp_all") then
		denied(ply, e)
		return false
	end
	local r = check(ply, e, kind)
	if r == false then return false end
	if REMOVE_TOOLS[tool] and PP.Active() then PP.LogStaffRemove(ply, e) end
end)

hook.Add("EntityTakeDamage", "Praetor.PP", function(e, dmg)
	if not PP.Active() or not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsNextBot() then return end
	local att = dmg:GetAttacker()
	if IsValid(att) and not att:IsPlayer() then
		-- a prop or a vehicle hitting: the owner of that thing is the attacker
		local o = PP.Owner(att)
		att = IsValid(o) and o or (IsValid(att:GetOwner()) and att:GetOwner():IsPlayer() and att:GetOwner()) or nil
	end
	if not IsValid(att) or not att:IsPlayer() then return end
	if not PP.CanTouch(att, e, "damage") then return true end
end)

-- staff deleting a player's things goes to the logs
function PP.LogStaffRemove(ply, e)
	if not IsValid(ply) or not IsValid(e) then return end
	local sid = e.PraetorOwnerSID
	if not sid or sid == ply:SteamID64() then return end
	if (ply.PraetorPPLog or 0) > CurTime() then return end
	ply.PraetorPPLog = CurTime() + 0.5
	local name = e:GetNW2String("pr_oname", "")
	P.Log("prop", "l_pp_remove", { A = P.LogPly(ply), T = { n = name ~= "" and name or (P.KnownName(sid) or sid), s = sid }, V = e:GetModel() or e:GetClass() }, { ply, sid })
end

-- ------------------------------------------------------------------ CPPI

local function defineCPPI()
	PP.foreign = foreignPP()
	if PP.foreign then
		MsgC(Color(201, 147, 74), "[Praetor] prop protection: ", PP.foreign, " is running, Praetor only keeps track of the owners\n")
		return
	end
	if CPPI and CPPI.Praetor then return end
	CPPI = {
		Praetor = true,
		CPPI_DEFER = 102112,
		CPPI_NOTIMPLEMENTED = 7080,
	}
	function CPPI:GetName() return "Praetor Prop Protection" end
	function CPPI:GetVersion() return Praetor.Version or "1" end
	function CPPI:GetInterfaceVersion() return 1.3 end
	function CPPI:GetNameFromUID(uid)
		for _, p in ipairs(player.GetAll()) do if p:UniqueID() == tostring(uid) then return p:Nick() end end
	end

	local PLY = FindMetaTable("Player")
	-- Praetor has no friends list: nobody shares their props
	function PLY:CPPIGetFriends() return {} end

	local ENT = FindMetaTable("Entity")
	function ENT:CPPIGetOwner()
		local o = PP.Owner(self)
		if IsValid(o) then return o, o:UniqueID() end
		return nil, CPPI.CPPI_NOTIMPLEMENTED
	end
	function ENT:CPPISetOwner(ply) PP.SetOwner(self, ply) return true end
	function ENT:CPPISetOwnerUID(uid)
		for _, p in ipairs(player.GetAll()) do
			if p:UniqueID() == tostring(uid) then PP.SetOwner(self, p) return true end
		end
		return false
	end
	local function can(kind) return function(self, ply) return not PP.Active() or PP.CanTouch(ply, self, kind) end end
	ENT.CPPICanTool = function(self, ply) return not PP.Active() or PP.CanTouch(ply, self, "tool") end
	ENT.CPPICanPhysgun = can("physgun")
	ENT.CPPICanPickup = can("gravgun")
	ENT.CPPICanPunt = can("gravgun")
	ENT.CPPICanUse = can("use")
	ENT.CPPICanDamage = can("damage")
	ENT.CPPIDrive = can("property")
	ENT.CPPICanProperty = can("property")
	ENT.CPPICanEditVariable = can("property")
end
P.PPDefineCPPI = defineCPPI

-- the clients only show the owner card while the protection is in charge
local function pushState() SetGlobal2Bool("pr_pp_on", PP.Active()) end
PP.PushState = pushState

local function boot()
	defineCPPI()
	pushState()
end
if GAMEMODE then boot() else hook.Add("Initialize", "Praetor.PPCPPI", boot) end
hook.Add("Praetor.SettingsChanged", "Praetor.PP", function() pushState() end)
timer.Simple(5, pushState)

-- state for the menu (the settings say when another addon is in charge)
P.Receive("pp_state", { perm = { "settings", "security" }, rate = 2 }, function(ply)
	local n = 0
	for _, list in pairs(bySid) do for e in pairs(list) do if IsValid(e) then n = n + 1 end end end
	P.Send(ply, "pp_state", { foreign = PP.foreign, on = PP.Active() or nil, n = n })
end)
