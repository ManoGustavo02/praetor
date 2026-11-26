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

-- ------------------------------------------------------------------ the week and the goal
local function dayAgo(n) return tonumber(os.date("%Y%m%d", os.time() - n * 86400)) end

-- seconds on duty in the last 7 days (today included), saved ones only
function P.WeekDuty(sid)
	if P.StaffFlush then P.StaffFlush() end
	local r = P.DB.Row("SELECT SUM(duty) AS d FROM praetor_staff_days WHERE sid = ? AND day >= ?", sid, dayAgo(6))
	return math.floor(tonumber(r and r.d) or 0)
end

-- weekly goal (hours on duty) of a rank; nil when goals are off or the rank has none
function P.DutyGoalOf(rank)
	if P.Setting("duty_goal") ~= true then return nil end
	local r = P.Ranks and P.Ranks[rank or ""]
	local g = r and tonumber(r.goal) or 0
	return g > 0 and g or nil
end

-- ------------------------------------------------------------------ what was done in the shift
local PUN = {
	kick = true, ban = true, banid = true, warn = true, jail = true, jailtp = true, mute = true, gag = true, slay = true,
	freeze = true, strip = true, jobban = true, rpdemote = true, ignite = true, slap = true, blind = true, launch = true,
}

function P.ShiftCount(ply, field, n)
	local s = IsValid(ply) and ply.PraetorShift
	if s then s[field] = (s[field] or 0) + (n or 1) end
end

hook.Add("Praetor.CommandRan", "Praetor.Shift", function(caller, id)
	if not IsValid(caller) or not caller.PraetorShift then return end
	P.ShiftCount(caller, "cmds")
	if PUN[id] then P.ShiftCount(caller, "pun") end
end)
hook.Add("Praetor.ReportClosed", "Praetor.Shift", function(_, ply) P.ShiftCount(ply, "rep") end)
hook.Add("BBX_CaseClosed", "Praetor.Shift", function(c, closer)
	if istable(c) and (c.verdict == "cancelled" or c.verdict == "left") then return end
	P.ShiftCount(closer, "rep")
end)
hook.Add("Praetor.SitEnded", "Praetor.Shift", function(sit)
	for _, sid in ipairs(istable(sit) and sit.staffSids or {}) do P.ShiftCount(P.BySID(sid), "sits") end
end)

local function summary(ply, why)
	local s = ply.PraetorShift or {}
	local secs = math.max(0, math.floor(CurTime() - (s.t0 or CurTime())))
	local d = {
		secs = secs, cmds = s.cmds or 0, pun = s.pun or 0, rep = s.rep or 0, sits = s.sits or 0, baton = s.baton or 0,
		week = ply:GetNW2Int("pr_weekbase", 0) + secs, goal = P.DutyGoalOf(ply:GetUserGroup()), why = why,
	}
	P.Send(ply, "duty_summary", d)
	P.Log("cmd", "l_duty_shift", { A = P.LogPly(ply), V = P.FormatHours(secs), C = d.cmds, P = d.pun, R = d.rep + d.sits, B = d.baton }, { ply })
end

function P.SetDuty(ply, on, why)
	if not IsValid(ply) or on == ply:GetNW2Bool("pr_duty", false) then return end
	if on then
		ply.PraetorDutyTick = CurTime()
		ply.PraetorShift = { t0 = CurTime() }
		ply:SetNW2Int("pr_weekbase", P.WeekDuty(ply:SteamID64()))
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
		summary(ply, why)
		ply.PraetorDutyTick = nil
		ply.PraetorShift = nil
		ply.PraetorEsp = nil
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

-- ------------------------------------------------------------------ AFK ends the shift
-- (setting duty_afk): the AFK time of the server (afk_time) passed without moving
timer.Create("Praetor.DutyAFK", 5, 0, function()
	-- staff mode turned off in Settings: whoever is on duty leaves it
	if P.Setting("duty_on") == false then
		for _, p in ipairs(player.GetHumans()) do
			if p:GetNW2Bool("pr_duty", false) then P.SetDuty(p, false) end
		end
		return
	end
	if P.Setting("duty_afk") == false then return end
	for _, p in ipairs(player.GetHumans()) do
		if p:GetNW2Bool("pr_duty", false) and p:GetNW2Bool("pr_afk", false) and not p:GetNW2Bool("pr_specon", false) then
			P.SetDuty(p, false, "afk")
			P.Notify(p, "duty_afk_off", {}, "warn")
			P.Log("cmd", "l_duty_afk", { A = P.LogPly(p) }, { p })
		end
	end
end)

-- ------------------------------------------------------------------ staff ESP
-- players far away are normally not sent to a client; for a staff member with the
-- ESP on (and on duty) every player is, so the ESP shows the real positions
P.Receive("esp_state", { perm = "esp", rate = 4 }, function(ply, data)
	ply.PraetorEsp = data.on == true and ply:GetNW2Bool("pr_duty", false) and P.Setting("staff_esp") ~= false or nil
	ply:SetNW2Bool("pr_esp", ply.PraetorEsp == true)
end)

hook.Add("SetupPlayerVisibility", "Praetor.StaffESP", function(ply)
	if not ply.PraetorEsp then return end
	for _, p in player.Iterator() do
		if p ~= ply then AddOriginToPVS(p:GetPos()) end
	end
end)

-- ------------------------------------------------------------------ reports need staff mode
-- (setting duty_reports) Taking a report or a support room off duty asks first:
-- "Start staff mode?". Yes starts it and does what was asked right away.
local RETRY = { report_claim = "reports", sit_start = "sit", sit_join = "sit" }

-- true = stopped here (the player was asked)
function P.NeedDuty(ply, op, data)
	if not IsValid(ply) or P.Setting("duty_reports") ~= true or P.Setting("duty_on") == false then return false end
	if ply:GetNW2Bool("pr_duty", false) then return false end
	if not P.Has(ply, "duty") then return false end -- ranks without staff mode work as before
	P.Send(ply, "duty_ask", { op = RETRY[op or ""] and op or nil, d = RETRY[op or ""] and data or nil })
	return true
end

P.Receive("duty_join", { perm = "duty", rate = 1 }, function(ply, data)
	if not ply:GetNW2Bool("pr_duty", false) then
		P.SetDuty(ply, true)
		P.Echo(ply, "e_duty_on", {})
		P.Log("cmd", "l_duty_on", { A = P.LogPly(ply) }, { ply })
	end
	local op = isstring(data.op) and data.op or nil
	local perm = op and RETRY[op]
	local rc = perm and P.Receivers and P.Receivers[op]
	if rc and P.Has(ply, perm) then
		local ok, err = pcall(rc.fn, ply, istable(data.d) and data.d or {})
		if not ok then ErrorNoHalt("[Praetor] duty_join " .. op .. ": " .. tostring(err) .. "\n") end
	end
end)

