-- Praetor: staff mode (!duty). Starts the shift clock (time on duty in the staff
-- panel, counted to the second), puts away the weapons that hurt (guns with ammo
-- and melee weapons; physgun, gravity gun, tool gun, camera, keys... stay) and
-- gives the staff baton. Turning it off gives the weapons back.
local P = Praetor

-- never put away
local SAFE = {
	weapon_physgun = true, weapon_physcannon = true, gmod_tool = true, gmod_camera = true, praetor_baton = true,
	keys = true, pocket = true, weapon_keypadchecker = true, weaponchecker = true, arrest_stick = true,
	unarrest_stick = true, door_ram = true, lockpick = true, med_kit = true, weapon_medkit = true,
}
-- melee weapons that hurt but use no ammo
local MELEE = { weapon_crowbar = true, weapon_stunstick = true, stunstick = true, weapon_fists = true }

local function hurts(w)
	local c = w:GetClass()
	if SAFE[c] then return false end
	if MELEE[c] then return true end
	if w:GetPrimaryAmmoType() >= 0 or w:GetSecondaryAmmoType() >= 0 then return true end
	-- Lua melee weapons (knives, bats...) say how much they hit
	local pr = w.Primary
	if istable(pr) and (tonumber(pr.Damage) or 0) > 0 then return true end
	return false
end
P.WeaponHurts = hurts

-- adds the time on duty since the last count (to the second)
function P.DutyTick(ply)
	local t = ply.PraetorDutyTick
	if not t or not P.StaffAdd then return end
	local n = math.floor(CurTime() - t)
	if n >= 1 then
		P.StaffAdd(ply:SteamID64(), "duty", n)
		ply.PraetorDutyTick = t + n
	end
end

local function putAway(ply)
	local saved = ply.PraetorDutySaved or {}
	if P.Setting("duty_strip") ~= false then
		for _, w in ipairs(ply:GetWeapons()) do
			if IsValid(w) and hurts(w) then
				saved[#saved + 1] = { c = w:GetClass(), clip = w:Clip1(), clip2 = w:Clip2() }
				ply:StripWeapon(w:GetClass())
			end
		end
	end
	ply.PraetorDutySaved = saved
	if P.Setting("duty_baton") ~= false and not ply:HasWeapon("praetor_baton") then
		ply:Give("praetor_baton")
		ply:SelectWeapon("praetor_baton")
	end
end

local function giveBack(ply)
	if ply:HasWeapon("praetor_baton") then ply:StripWeapon("praetor_baton") end
	for _, e in ipairs(ply.PraetorDutySaved or {}) do
		if not ply:HasWeapon(e.c) then
			local w = ply:Give(e.c, true) -- the ammo the player had stays with them
			if IsValid(w) then
				if (e.clip or -1) >= 0 then w:SetClip1(e.clip) end
				if (e.clip2 or -1) >= 0 then w:SetClip2(e.clip2) end
			end
		end
	end
	ply.PraetorDutySaved = nil
end

function P.SetDuty(ply, on)
	if not IsValid(ply) or on == ply:GetNW2Bool("pr_duty", false) then return end
	if on then
		ply.PraetorDutyTick = CurTime()
		ply:SetNW2Bool("pr_duty", true)
		ply:SetNW2Float("pr_dutysince", CurTime())
		if ply:Alive() then putAway(ply) end
		-- invisible while on duty (only if this turned it on: a staff already
		-- invisible stays so after the shift)
		if P.Setting("duty_cloak") == true and not ply.PraetorCloak then
			ply.PraetorDutyCloak = true
			P.SetCloak(ply, true)
		end
	else
		P.DutyTick(ply)
		ply.PraetorDutyTick = nil
		ply:SetNW2Bool("pr_duty", false)
		if ply:Alive() then giveBack(ply) else ply.PraetorDutySaved = nil end
		if ply.PraetorDutyCloak then
			ply.PraetorDutyCloak = nil
			if ply.PraetorCloak then P.SetCloak(ply, false) end
		end
	end
	hook.Run("Praetor.DutyChanged", ply, on)
end

-- after dying the new loadout is put away again (and given back when duty ends)
hook.Add("PlayerSpawn", "Praetor.Duty", function(ply)
	if not ply:GetNW2Bool("pr_duty", false) then return end
	ply.PraetorDutySaved = {}
	timer.Simple(0.3, function()
		if IsValid(ply) and ply:Alive() and ply:GetNW2Bool("pr_duty", false) then putAway(ply) end
	end)
end)

-- DarkRP job change: the new job's weapons are put away too
hook.Add("OnPlayerChangedTeam", "Praetor.Duty", function(ply)
	if not ply:GetNW2Bool("pr_duty", false) then return end
	timer.Simple(0.5, function()
		if IsValid(ply) and ply:Alive() and ply:GetNW2Bool("pr_duty", false) then putAway(ply) end
	end)
end)

hook.Add("PlayerDisconnected", "Praetor.Duty", function(ply) P.DutyTick(ply) end)

-- the baton belongs to staff mode: it can't be dropped (DarkRP /drop) nor picked up off duty
hook.Add("canDropWeapon", "Praetor.Duty", function(_, w)
	if IsValid(w) and w:GetClass() == "praetor_baton" then return false end
end)
hook.Add("PlayerCanPickupWeapon", "Praetor.Duty", function(ply, w)
	if IsValid(w) and w:GetClass() == "praetor_baton" and not ply:GetNW2Bool("pr_duty", false) then return false end
end)
