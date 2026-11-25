-- Praetor: spectate camera. The server sets the "pr_spec" entity; the client
-- orbits around it (or looks through its eyes) and blocks its own movement.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local firstPerson = false
local dist = 110
local lastButtons = 0

local function target()
	local me = LocalPlayer()
	if not IsValid(me) then return nil end
	local t = me:GetNW2Entity("pr_spec")
	if IsValid(t) and t ~= me then return t end
end

hook.Add("CalcView", "Praetor.Spectate", function(ply, pos, ang, fov)
	local t = target()
	if not t then return end
	if firstPerson and t:IsPlayer() then
		local eyes = t:EyePos()
		return { origin = eyes, angles = t:EyeAngles(), fov = fov, drawviewer = true }
	end
	local center = t:IsPlayer() and (t:GetPos() + Vector(0, 0, 48)) or t:WorldSpaceCenter()
	local dir = ang:Forward()
	local tr = util.TraceHull({
		start = center, endpos = center - dir * dist,
		mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
		filter = { t, ply }, mask = MASK_SOLID_BRUSHONLY,
	})
	return { origin = tr.HitPos, angles = ang, fov = fov, drawviewer = true }
end)

hook.Add("ShouldDrawLocalPlayer", "Praetor.Spectate", function()
	if target() then return false end
end)

hook.Add("PrePlayerDraw", "Praetor.Spectate", function(ply)
	local t = target()
	if t and firstPerson and ply == t then return true end
end)

hook.Add("CreateMove", "Praetor.Spectate", function(cmd)
	if not target() then lastButtons = 0 return end
	local b = cmd:GetButtons()
	local pressed = bit.band(b, bit.bnot(lastButtons))
	lastButtons = b
	if bit.band(pressed, IN_ATTACK) ~= 0 then P.Request("spec_next", { dir = 1 }) end
	if bit.band(pressed, IN_ATTACK2) ~= 0 then P.Request("spec_next", { dir = -1 }) end
	if bit.band(pressed, IN_RELOAD) ~= 0 then firstPerson = not firstPerson UI.Sound("click") end
	if bit.band(pressed, IN_JUMP) ~= 0 then P.Request("spec_stop") UI.Sound("close") end
	cmd:ClearMovement()
	cmd:ClearButtons()
	-- the mouse wheel moves the orbit camera
	local wheel = cmd:GetMouseWheel()
	if wheel ~= 0 then dist = math.Clamp(dist - wheel * 12, 40, 400) end
end)

hook.Add("HUDPaint", "Praetor.Spectate", function()
	local t = target()
	if not t then return end
	local w = S(420)
	local h = S(86)
	local x, y = ScrW() / 2 - w / 2, ScrH() - h - S(28)
	UI.Tablet(x, y, w, h, Color(C.panel.r, C.panel.g, C.panel.b, 240), C.edge)
	UI.Text(P.L("spec_watching"), "Praetor.Tiny", x + S(14), y + S(8), C.muted)
	if t:IsPlayer() then
		local style, icon = UI.PlayerRankStyle(t)
		UI.TextShadow(UI.Fit(t:Nick(), "Praetor.H2", w - S(160)), "Praetor.H2", x + S(14), y + S(24), C.ivory)
		UI.Badge(style, icon, "Praetor.Tag", x + w - S(14), y + S(26), S(24), 255, TEXT_ALIGN_RIGHT)
		local hp = math.max(0, t:Health())
		local frac = math.Clamp(hp / math.max(1, t:GetMaxHealth()), 0, 1)
		UI.Rect(x + S(14), y + S(54), w - S(28), S(6), C.bg)
		UI.Rect(x + S(14), y + S(54), (w - S(28)) * frac, S(6), C.crimsonL)
		UI.Text(hp .. " HP", "Praetor.Tiny", x + w - S(14), y + S(8), C.text, TEXT_ALIGN_RIGHT)
	else
		UI.TextShadow(t:GetClass(), "Praetor.H2", x + S(14), y + S(24), C.ivory)
	end
	UI.Text(P.L("spec_hint"), "Praetor.Tiny", x + w / 2, y + h - S(18), C.dim, TEXT_ALIGN_CENTER)
end)
