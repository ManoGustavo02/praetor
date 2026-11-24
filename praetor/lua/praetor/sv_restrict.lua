-- Praetor: restrictions. Weapons, entities, NPCs, vehicles, props and tools can
-- be blacklisted (nobody), kept for staff, or opened from a rank up. Staff with
-- "manage_restrict" set them with a right click in the spawn menu (Q) or in the
-- Restrictions tab. Owners are never restricted.
--
-- Rule: { k = kind, c = class, m = "block" | "staff" | "rank", r = rank,
--         pk = also stop picking up / receiving (weapons), by, t }
local P = Praetor

local KINDS = { weapon = true, entity = true, npc = true, vehicle = true, prop = true, tool = true }
local MAX_RULES = 2000

P.Restrict = P.DB.Get("restrict", {}) or {}

local function key(kind, class) return kind .. ":" .. tostring(class or ""):lower():gsub("\\", "/") end
P.RestrictKey = key

local function save() P.DB.Set("restrict", P.Restrict) end
local function broadcast() P.Send(nil, "rs_list", { list = P.Restrict }) end

hook.Add("Praetor.UserLoaded", "Praetor.Restrict", function(ply)
	if IsValid(ply) then P.Send(ply, "rs_list", { list = P.Restrict }) end
end)

-- true when this player may use the item
function P.RestrictAllows(ply, kind, class)
	local rule = P.Restrict[key(kind, class)]
	if not rule then return true end
	if not IsValid(ply) or P.IsOwner(ply) then return true end
	if rule.m == "block" then return false end
	-- "admin only": staff ranks and admin (or anything that inherits it)
	if rule.m == "staff" then return P.IsStaff(ply) or P.Inherits(ply:GetUserGroup(), "admin") end
	if rule.m == "rank" then
		local rk = P.Ranks[rule.r or ""]
		if not rk then return true end
		return P.Inherits(ply:GetUserGroup(), rk.name) or P.Authority(ply) >= (rk.immunity or 0)
	end
	return true
end

local told = {}
local function deny(ply, kind, class, pickup)
	local k = ply:EntIndex() .. kind .. class
	if (told[k] or 0) > CurTime() then return end
	told[k] = CurTime() + (pickup and 6 or 1.5)
	local rule = P.Restrict[key(kind, class)] or {}
	local rk = P.Ranks[rule.r or ""]
	-- the client shows a card next to the icon that was clicked (or in the
	-- middle of the screen) with the item, the rule and the rank it needs
	P.Send(ply, "rs_denied", { k = kind, c = class, m = rule.m or "block", r = rule.r, rn = rk and (rk.display or rk.name) or nil, pk = pickup and 1 or nil })
end

local function check(ply, kind, class)
	if not IsValid(ply) or not class then return end
	if P.RestrictAllows(ply, kind, class) then return end
	deny(ply, kind, tostring(class))
	return false
end

hook.Add("PlayerSpawnSWEP", "Praetor.Restrict", function(ply, class) return check(ply, "weapon", class) end)
hook.Add("PlayerGiveSWEP", "Praetor.Restrict", function(ply, class) return check(ply, "weapon", class) end)
hook.Add("PlayerSpawnSENT", "Praetor.Restrict", function(ply, class) return check(ply, "entity", class) end)
hook.Add("PlayerSpawnNPC", "Praetor.Restrict", function(ply, class) return check(ply, "npc", class) end)
hook.Add("PlayerSpawnVehicle", "Praetor.Restrict", function(ply, model, name) return check(ply, "vehicle", name) end)
hook.Add("PlayerSpawnProp", "Praetor.Restrict", function(ply, model) return check(ply, "prop", model) end)
hook.Add("PlayerSpawnRagdoll", "Praetor.Restrict", function(ply, model) return check(ply, "prop", model) end)
hook.Add("PlayerSpawnEffect", "Praetor.Restrict", function(ply, model) return check(ply, "prop", model) end)
hook.Add("CanTool", "Praetor.Restrict", function(ply, tr, tool) return check(ply, "tool", tool) end)

-- picking a weapon up from the floor, from a job loadout or from another addon
hook.Add("PlayerCanPickupWeapon", "Praetor.Restrict", function(ply, wep)
	if not IsValid(wep) then return end
	local class = wep:GetClass()
	local rule = P.Restrict[key("weapon", class)]
	if not rule or rule.pk == false then return end
	if P.RestrictAllows(ply, "weapon", class) then return end
	deny(ply, "weapon", class, true)
	return false
end)

-- ------------------------------------------------------------------ management

local function cleanRule(d)
	if not istable(d) then return nil end
	local kind = isstring(d.k) and d.k or ""
	local class = isstring(d.c) and P.Trim(d.c) or ""
	if not KINDS[kind] or class == "" or #class > 200 then return nil end
	if not class:match("^[%w_%-%./\\]+$") then return nil end
	local m = d.m
	if m ~= "block" and m ~= "staff" and m ~= "rank" then return nil end
	local r = m == "rank" and isstring(d.r) and P.Ranks[d.r] and d.r or nil
	if m == "rank" and not r then return nil end
	return { k = kind, c = class:lower():gsub("\\", "/"), m = m, r = r, pk = kind == "weapon" and d.pk ~= false or nil }
end

local function describe(rule)
	if rule.m == "rank" then return rule.m .. " " .. tostring(rule.r) end
	return rule.m
end

P.Receive("rs_set", { perm = "manage_restrict", rate = 6 }, function(ply, data)
	local rule = cleanRule(data)
	if not rule then P.Notify(ply, "err_internal") return end
	local k = key(rule.k, rule.c)
	if not P.Restrict[k] and table.Count(P.Restrict) >= MAX_RULES then P.Notify(ply, "rs_full", { V = MAX_RULES }, "warn") return end
	-- a rank above the editor's own cannot be picked as the floor
	if rule.m == "rank" and not P.CanManageRank(ply, rule.r) and not P.Inherits(ply:GetUserGroup(), rule.r) then
		P.Notify(ply, "err_rank_authority") return
	end
	rule.by = ply:SteamID64()
	rule.t = os.time()
	P.Restrict[k] = rule
	save()
	broadcast()
	P.Log("settings", "l_rs_set", { A = P.LogPly(ply), V = rule.c, V2 = describe(rule) }, { ply })
	P.Notify(ply, "rs_saved", { S = rule.c }, "ok")
end)

P.Receive("rs_del", { perm = "manage_restrict", rate = 6 }, function(ply, data)
	local k = key(isstring(data.k) and data.k or "", isstring(data.c) and data.c or "")
	local rule = P.Restrict[k]
	if not rule then return end
	P.Restrict[k] = nil
	save()
	broadcast()
	P.Log("settings", "l_rs_del", { A = P.LogPly(ply), V = rule.c }, { ply })
	P.Notify(ply, "rs_freed", { S = rule.c }, "ok")
end)

-- takes a weapon out of everyone's hands (owners and higher ranks keep it)
P.Receive("rs_strip", { perm = "manage_restrict", rate = 2 }, function(ply, data)
	local class = isstring(data.c) and data.c:lower() or ""
	if class == "" then return end
	local n = 0
	for _, p in ipairs(player.GetAll()) do
		local reach = p == ply or P.CanTarget(ply, p)
		-- data.all: everyone below the caller; otherwise only who is not allowed
		if p:HasWeapon(class) and reach and (data.all or not P.RestrictAllows(p, "weapon", class)) then
			p:StripWeapon(class)
			n = n + 1
		end
	end
	P.Log("settings", "l_rs_strip", { A = P.LogPly(ply), V = class, V2 = n }, { ply })
	P.Notify(ply, "rs_stripped", { S = class, V = n }, "ok")
end)

-- removes every spawned copy of an entity / NPC / vehicle / prop model
P.Receive("rs_clear", { perm = "manage_restrict", rate = 2 }, function(ply, data)
	local kind = isstring(data.k) and data.k or ""
	local class = isstring(data.c) and data.c:lower():gsub("\\", "/") or ""
	if class == "" or not KINDS[kind] or kind == "weapon" or kind == "tool" then return end
	local n = 0
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and not e:IsPlayer() and not e:IsWeapon() and e:CreatedByMap() == false then
			local hit
			if kind == "prop" then hit = tostring(e:GetModel() or ""):lower() == class
			elseif kind == "vehicle" then hit = (e.VehicleName and e.VehicleName:lower() == class) or e:GetClass() == class
			else hit = e:GetClass() == class end
			if hit then
				local owner = e.CPPIGetOwner and e:CPPIGetOwner() or nil
				if not IsValid(owner) or owner == ply or P.CanTarget(ply, owner) then
					e:Remove()
					n = n + 1
				end
			end
		end
	end
	P.Log("settings", "l_rs_clear", { A = P.LogPly(ply), V = class, V2 = n }, { ply })
	P.Notify(ply, "rs_cleared", { S = class, V = n }, "ok")
end)

-- gives a weapon to a player (needs the "give" command)
P.Receive("rs_give", { perm = "give", rate = 4 }, function(ply, data)
	local class = isstring(data.c) and data.c or ""
	local target = isstring(data.sid) and data.sid ~= "" and (data.sid:match("^%$(%d+)$") and Player(tonumber(data.sid:match("^%$(%d+)$"))) or (P.ToSID64(data.sid) and player.GetBySteamID64(P.ToSID64(data.sid)))) or nil
	if class == "" or not IsValid(target) then return end
	if target ~= ply and not P.CanTarget(ply, target) then P.Notify(ply, "err_authority", { S = target:Nick() }, "warn") return end
	if not list.Get("Weapon")[class] and not weapons.GetStored(class) then return end
	target:Give(class)
	P.Log("cmd", "l_rs_give", { A = P.LogPly(ply), T = P.LogPly(target), V = class }, { ply, target })
end)
