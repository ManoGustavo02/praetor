-- Praetor: prop protection on the client.
--  * a small card under the crosshair says whose thing you aim at: green when
--    you can touch it (yours, or you are staff), red when you can't, grey for
--    map entities;
--  * when the server refuses a touch the card turns red and shakes;
--  * client side CPPI (CPPIGetOwner) for addons that ask on the client.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local function ownerOf(e)
	if not IsValid(e) then return nil end
	local o = e:GetNW2Entity("pr_owner")
	if IsValid(o) then return o end
end

local function ownerName(e)
	local o = ownerOf(e)
	if IsValid(o) then return o:Nick() end
	local n = e:GetNW2String("pr_oname", "")
	if n ~= "" then return n end
end

local function mine(e)
	local sid = e:GetNW2String("pr_osid", "")
	return sid ~= "" and sid == LocalPlayer():SteamID64()
end

-- ------------------------------------------------------------------ refused

local flash -- { e, t, n }
P.On("pp_denied", function(d)
	flash = { e = d.e, t = RealTime(), n = d.n }
	UI.Sound("error")
end)

-- ------------------------------------------------------------------ the card

local TOOLS = { weapon_physgun = true, gmod_tool = true, weapon_physcannon = true }
local shown, alpha = nil, 0

hook.Add("HUDPaint", "Praetor.PP", function()
	if not P.Setting("pp_hud") or not GetGlobal2Bool("pr_pp_on", false) then return end
	local lp = LocalPlayer()
	if not IsValid(lp) or not lp:Alive() then return end
	local wep = lp:GetActiveWeapon()
	local holding = IsValid(wep) and TOOLS[wep:GetClass()]
	local tr = lp:GetEyeTrace()
	local e = tr.Entity
	local ok = IsValid(e) and not e:IsPlayer() and not e:IsWorld() and tr.HitPos:DistToSqr(tr.StartPos) < 1400 * 1400
	-- with a physgun / toolgun the card is always there, with anything else only on others' things
	if ok and not holding and (mine(e) or e:GetNW2String("pr_osid", "") == "") then ok = false end
	local fl = flash and RealTime() - flash.t < 1.4 and flash or nil
	if fl and IsValid(Entity(fl.e)) then
		e = Entity(fl.e)
		ok = true
	end
	if ok then shown = e end
	alpha = Lerp(FrameTime() * 14, alpha, ok and 1 or 0)
	if alpha < 0.02 or not IsValid(shown) then return end
	e = shown

	local sid = e:GetNW2String("pr_osid", "")
	local staff = P.MyHas("pp_all")
	local col, icon, title, sub
	if sid == "" then
		col, icon = C.muted, "map"
		title = P.L("pp_world")
		sub = staff and P.L("pp_staff_can") or nil
	elseif mine(e) then
		col, icon = C.laurel, "lock_ok"
		title = P.L("pp_yours")
	else
		local n = ownerName(e) or (fl and fl.n) or "?"
		title = P.L("pp_of", { S = n })
		if staff then
			col, icon = C.amber, "shield"
			sub = P.L("pp_staff_can")
		else
			col, icon = C.crimsonL, "lock"
			sub = P.L("pp_cant")
		end
		if not ownerOf(e) then sub = P.L("pp_left") .. (sub and ("  ·  " .. sub) or "") end
	end
	if fl and fl.e == e:EntIndex() then col, icon = C.crimsonL, "lock" sub = P.L("pp_denied") end

	surface.SetFont("Praetor.SmallB")
	local tw = surface.GetTextSize(title)
	surface.SetFont("Praetor.Tiny")
	local sw = sub and surface.GetTextSize(sub) or 0
	local w = math.max(tw, sw) + S(48)
	local h = sub and S(40) or S(28)
	local x = ScrW() / 2 - w / 2
	local y = ScrH() / 2 + S(34)
	if fl then
		local age = RealTime() - fl.t
		if age < 0.35 then x = x + math.sin(age * 60) * (0.35 - age) * S(18) end
	end
	local a = alpha * 255
	UI.Round(x, y, w, h, S(8), Color(14, 15, 20, 225 * alpha), Color(col.r, col.g, col.b, 200 * alpha))
	UI.Round(x + 1, y + S(6), S(3), h - S(12), S(1), Color(col.r, col.g, col.b, a))
	UI.Icon(icon, x + S(12), y + h / 2 - 8, 16, Color(col.r, col.g, col.b, a))
	UI.Text(title, "Praetor.SmallB", x + S(36), sub and y + S(13) or y + h / 2, Color(235, 236, 240, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if sub then UI.Text(sub, "Praetor.Tiny", x + S(36), y + S(29), Color(col.r, col.g, col.b, a * 0.9), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end)

-- ------------------------------------------------------------------ settings note

P.On("pp_state", function(d)
	local note = P.PPNote
	if not IsValid(note) then return end
	if d.foreign then
		note:SetText(P.L("pp_foreign", { S = tostring(d.foreign) }))
		note:SetVisible(true)
	else
		note:SetVisible(false)
	end
	local p = note:GetParent()
	if IsValid(p) then p:InvalidateLayout() end
end)

-- ------------------------------------------------------------------ CPPI on the client

local function defineCPPI()
	if FPP or (CPPI and not CPPI.Praetor) then return end
	CPPI = { Praetor = true, CPPI_DEFER = 102112, CPPI_NOTIMPLEMENTED = 7080 }
	function CPPI:GetName() return "Praetor Prop Protection" end
	function CPPI:GetVersion() return Praetor.Version or "1" end
	function CPPI:GetInterfaceVersion() return 1.3 end
	function CPPI:GetNameFromUID(uid)
		for _, p in ipairs(player.GetAll()) do if p:UniqueID() == tostring(uid) then return p:Nick() end end
	end
	local PLY = FindMetaTable("Player")
	function PLY:CPPIGetFriends() return {} end
	local ENT = FindMetaTable("Entity")
	function ENT:CPPIGetOwner()
		local o = ownerOf(self)
		if IsValid(o) then return o, o:UniqueID() end
		return nil, CPPI.CPPI_NOTIMPLEMENTED
	end
end

if GAMEMODE then defineCPPI() else hook.Add("Initialize", "Praetor.PPCPPI", defineCPPI) end
