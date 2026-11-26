-- Praetor: spectate. A separate mode: your own body stays hidden where it was and
-- nothing you press reaches it. Three cameras:
--   eyes  - first person, through the eyes of the player (the default)
--   orbit - third person, around the player (mouse turns, wheel zooms)
--   free  - a free camera that flies anywhere; click a player to watch them
-- While watching, a panel shows health, armor, weapon and ammo, what the player is
-- looking at, speed and ping, and an aim line shows where they point.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local mode = "eyes"        -- when watching a player: eyes / orbit
local dist = 120           -- orbit distance
local freeSpeed = 1        -- free camera speed multiplier (mouse wheel)
local camPos               -- free camera position
local lastOrigin, lastAng  -- what the screen showed last frame
local lastTarget           -- the last player watched (E goes back to them)
local move = { f = 0, s = 0, up = 0, fast = false }
local lastButtons = 0
local hiddenWep
local sentAt = 0
local backDown = false

-- shows the weapon again only if it is still in the player's hands (a weapon put
-- away is hidden by the game itself and must stay hidden)
local function showWeapon(w)
	if not IsValid(w) then return end
	local o = w:GetOwner()
	if IsValid(o) and o:IsPlayer() and o:GetActiveWeapon() == w then w:SetNoDraw(false) end
end

local function me() return LocalPlayer() end
local function on()
	local m = me()
	return IsValid(m) and m:GetNW2Bool("pr_specon")
end
local function target()
	local m = me()
	if not IsValid(m) then return nil end
	local t = m:GetNW2Entity("pr_spec")
	if IsValid(t) and t ~= m then return t end
end
P.SpecTarget = target

local function shortNum(n) return P.ShortNum and P.ShortNum(n) or tostring(math.floor(n)) end

local function sendCam(force)
	if not camPos or (not force and RealTime() - sentAt < 0.25) then return end
	sentAt = RealTime()
	P.Request("spec_cam", { x = camPos.x, y = camPos.y, z = camPos.z })
end

-- the player closest to the middle of the screen (or right under it)
local function aimedPlayer(origin, dir)
	local tr = util.TraceLine({ start = origin, endpos = origin + dir * 12000, filter = me(), mask = MASK_SHOT })
	if IsValid(tr.Entity) and tr.Entity:IsPlayer() and tr.Entity:Alive() then return tr.Entity end
	local best, bestDot = nil, math.cos(math.rad(4))
	for _, p in ipairs(player.GetAll()) do
		if p ~= me() and p:Alive() then
			local to = p:WorldSpaceCenter() - origin
			local d = to:GetNormalized():Dot(dir)
			if d > bestDot and to:LengthSqr() < 12000 * 12000 then best, bestDot = p, d end
		end
	end
	return best
end

-- ------------------------------------------------------------------ camera
hook.Add("CalcView", "Praetor.Spectate", function(ply, pos, ang, fov)
	if not on() then camPos = nil return end
	local t = target()
	local view
	if t and mode == "eyes" and t:IsPlayer() then
		view = { origin = t:EyePos(), angles = t:EyeAngles(), fov = fov, drawviewer = false }
	elseif t then
		local center = t:IsPlayer() and (t:GetPos() + Vector(0, 0, t:Crouching() and 36 or 56)) or t:WorldSpaceCenter()
		local tr = util.TraceHull({
			start = center, endpos = center - ang:Forward() * dist,
			mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
			filter = { t, ply }, mask = MASK_SOLID_BRUSHONLY,
		})
		view = { origin = tr.HitPos, angles = ang, fov = fov, drawviewer = false }
	else
		camPos = camPos or lastOrigin or ply:EyePos()
		view = { origin = camPos, angles = ang, fov = fov, drawviewer = false }
	end
	lastOrigin, lastAng = view.origin, view.angles
	return view
end)

-- free camera flying
hook.Add("Think", "Praetor.Spectate", function()
	if not on() then
		if hiddenWep then showWeapon(hiddenWep) hiddenWep = nil end
		return
	end
	local t = target()
	if t then lastTarget = t end
	-- the weapon in the hands of the player would block the view in first person
	local w = (t and mode == "eyes" and t:IsPlayer()) and t:GetActiveWeapon() or nil
	if hiddenWep ~= w then
		if hiddenWep then showWeapon(hiddenWep) end
		hiddenWep = IsValid(w) and w or nil
		if hiddenWep then hiddenWep:SetNoDraw(true) end
	end
	if not t and camPos then
		local ang = me():EyeAngles()
		local speed = 520 * freeSpeed * (move.fast and 3 or 1)
		local dir = ang:Forward() * (move.f / 10000) + ang:Right() * (move.s / 10000) + Vector(0, 0, move.up)
		if dir:LengthSqr() > 0 then
			dir:Normalize()
			camPos = camPos + dir * speed * FrameTime()
		end
		sendCam(false)
	end
	-- Backspace leaves (not while typing in the chat or a window)
	local down = input.IsKeyDown(KEY_BACKSPACE) and not IsValid(vgui.GetKeyboardFocus()) and not gui.IsGameUIVisible()
	if down and not backDown then P.Request("spec_stop") UI.Sound("close") end
	backDown = down
end)

hook.Add("ShouldDrawLocalPlayer", "Praetor.Spectate", function()
	if on() then return false end
end)
hook.Add("PrePlayerDraw", "Praetor.Spectate", function(ply)
	if not on() then return end
	if ply == me() then return true end
	if mode == "eyes" and ply == target() then return true end
end)
hook.Add("PreDrawViewModel", "Praetor.Spectate", function() if on() then return true end end)
hook.Add("PreDrawPlayerHands", "Praetor.Spectate", function() if on() then return true end end)
hook.Add("HUDShouldDraw", "Praetor.Spectate", function(name)
	if (name == "CHudCrosshair" or name == "CHudWeaponSelection") and on() then return false end
end)

-- ------------------------------------------------------------------ keys
hook.Add("CreateMove", "Praetor.Spectate", function(cmd)
	if not on() then lastButtons = 0 return end
	local b = cmd:GetButtons()
	local pressed = bit.band(b, bit.bnot(lastButtons))
	lastButtons = b
	local function hit(k) return bit.band(pressed, k) ~= 0 end
	move.f, move.s = cmd:GetForwardMove(), cmd:GetSideMove()
	move.up = (bit.band(b, IN_JUMP) ~= 0 and 1 or 0) - (bit.band(b, IN_DUCK) ~= 0 and 1 or 0)
	move.fast = bit.band(b, IN_SPEED) ~= 0
	local wheel = cmd:GetMouseWheel()
	local t = target()
	if t then
		if hit(IN_ATTACK) then P.Request("spec_next", { dir = 1 }) end
		if hit(IN_ATTACK2) then P.Request("spec_next", { dir = -1 }) end
		if hit(IN_RELOAD) then mode = mode == "eyes" and "orbit" or "eyes" UI.Sound("click") end
		if hit(IN_USE) then
			camPos = lastOrigin
			P.Request("spec_free", camPos and { x = camPos.x, y = camPos.y, z = camPos.z } or {})
			UI.Sound("click")
		end
		if wheel ~= 0 then dist = math.Clamp(dist - wheel * 14, 40, 500) end
	else
		if (hit(IN_ATTACK) or hit(IN_ATTACK2)) and lastOrigin and lastAng then
			local p = aimedPlayer(lastOrigin, lastAng:Forward())
			if p then
				mode = hit(IN_ATTACK) and "eyes" or "orbit"
				P.Request("spec_set", { e = p:EntIndex() })
				UI.Sound("click")
			end
		end
		if hit(IN_USE) and IsValid(lastTarget) then
			P.Request("spec_set", { e = lastTarget:EntIndex() })
			UI.Sound("click")
		end
		if wheel ~= 0 then freeSpeed = math.Clamp(freeSpeed + wheel * 0.15, 0.2, 4) end
	end
	cmd:ClearMovement()
	cmd:ClearButtons()
	cmd:SetImpulse(0)
end)

-- ------------------------------------------------------------------ in the world
-- where the player aims: a thin line and a dot (in third person and free camera)
hook.Add("PostDrawTranslucentRenderables", "Praetor.Spectate", function(depth, sky)
	if sky or not on() then return end
	local t = target()
	if not (t and t:IsPlayer() and t:Alive()) or mode == "eyes" then return end
	local tr = t:GetEyeTrace()
	local from = t:EyePos() + t:EyeAngles():Forward() * 12 - Vector(0, 0, 4)
	local acc = C.bronzeL
	render.SetColorMaterial()
	render.DrawBeam(from, tr.HitPos, 1.2, 0, 1, Color(acc.r, acc.g, acc.b, 170))
	render.DrawSphere(tr.HitPos, 2.5, 10, 10, Color(acc.r, acc.g, acc.b, 230))
end)

-- ------------------------------------------------------------------ HUD
local function lookingAt(t)
	local tr = t:GetEyeTrace()
	local e = tr.Entity
	local meters = string.format("%.1f m", tr.HitPos:Distance(t:EyePos()) * 0.01905)
	if IsValid(e) and e:IsPlayer() then return e:Nick(), meters, e end
	if IsValid(e) then
		local mdl = e:GetModel() and (e:GetModel():match("([^/]+)%.mdl$")) or nil
		return e:GetClass() .. (mdl and (" (" .. mdl .. ")") or ""), meters
	end
	if tr.HitWorld then return P.L("spec_world"), meters end
	return P.L("spec_nothing"), ""
end

local function weaponText(t)
	local w = t:GetActiveWeapon()
	if not IsValid(w) then return P.L("spec_nothing"), "" end
	local name = language.GetPhrase(w:GetPrintName() or w:GetClass())
	local clip, ammoType = w:Clip1(), w:GetPrimaryAmmoType()
	local reserve = ammoType >= 0 and t:GetAmmoCount(ammoType) or -1
	local ammo = ""
	if clip >= 0 then ammo = shortNum(clip) .. " / " .. shortNum(math.max(0, reserve))
	elseif reserve >= 0 then ammo = shortNum(reserve) end
	return name, ammo
end

local function bar(x, y, w, h, frac, col, label)
	UI.Round(x, y, w, h, h / 2, C.bg, C.ink, 2)
	if frac > 0 then UI.Round(x + 2, y + 2, math.max(h - 4, (w - 4) * frac), h - 4, (h - 4) / 2, col) end
	if label then UI.Text(label, "Praetor.Tiny", x + w / 2, y + h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end

-- a key hint line: "[R] 1st/3rd person"... wrapped into the width
local function hints(list, x, y, w)
	local font = "Praetor.Tiny"
	surface.SetFont(font)
	local cx, cy, lh = x, y, S(20)
	for _, h in ipairs(list) do
		local kw = surface.GetTextSize(h[1]) + S(10)
		local tw = surface.GetTextSize(h[2])
		local need = kw + S(5) + tw + S(14)
		if cx > x and cx + need > x + w then cx, cy = x, cy + lh end
		UI.Round(cx, cy, kw, S(16), S(4), C.panel3, C.lineL, 1)
		UI.Text(h[1], font, cx + kw / 2, cy + S(8), C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		UI.Text(h[2], font, cx + kw + S(5), cy + S(8), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cx = cx + need
	end
	return cy + lh - y
end

local function hintsHeight(list, w)
	surface.SetFont("Praetor.Tiny")
	local cx, rows = 0, 1
	for _, h in ipairs(list) do
		local need = surface.GetTextSize(h[1]) + S(10) + S(5) + surface.GetTextSize(h[2]) + S(14)
		if cx > 0 and cx + need > w then cx, rows = 0, rows + 1 end
		cx = cx + need
	end
	return rows * S(20)
end

hook.Add("HUDPaint", "Praetor.Spectate", function()
	if not on() then return end
	local t = target()
	local w = math.min(ScrW() - S(40), S(560))
	local pad = S(14)
	local inner = w - pad * 2
	local x = math.floor((ScrW() - w) / 2)

	if not t then
		-- free camera: names over the players and who is under the crosshair
		local origin = lastOrigin or EyePos()
		local dir = (lastAng or EyeAngles()):Forward()
		local aimed = aimedPlayer(origin, dir)
		for _, p in ipairs(player.GetAll()) do
			if p ~= me() and p:Alive() then
				local pos = p:GetPos() + Vector(0, 0, 80)
				local d = pos:Distance(origin)
				if d < 8000 then
					local sc = pos:ToScreen()
					if sc.visible then
						local a = p == aimed and 255 or math.Clamp(255 - d / 8000 * 180, 70, 230)
						local col = p == aimed and C.amber or C.ivory
						UI.Name(p:Nick(), "Praetor.SmallB", sc.x, sc.y, Color(col.r, col.g, col.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, S(220), true)
						UI.Text(string.format("%.0f m", d * 0.01905), "Praetor.Tiny", sc.x, sc.y + S(2), Color(C.muted.r, C.muted.g, C.muted.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					end
				end
			end
		end
		-- crosshair
		local cx, cy = ScrW() / 2, ScrH() / 2
		surface.SetDrawColor(255, 255, 255, 200)
		surface.DrawRect(cx - 1, cy - S(7), 2, S(14))
		surface.DrawRect(cx - S(7), cy - 1, S(14), 2)
		if IsValid(aimed) then
			UI.Name(P.L("spec_click", { S = aimed:Nick() }), "Praetor.SmallB", cx, cy + S(16), C.amber, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, S(360), true)
		end
		local list = {
			{ "WASD", P.L("spec_k_fly") }, { P.L("spec_k_space"), P.L("spec_k_updown") }, { "Shift", P.L("spec_k_fast") },
			{ P.L("spec_k_lmb"), P.L("spec_k_watch1") }, { P.L("spec_k_rmb"), P.L("spec_k_watch3") },
			{ "E", P.L("spec_k_back") }, { "Backspace", P.L("spec_k_leave") },
		}
		local hh = hintsHeight(list, inner)
		local h = pad + S(22) + S(6) + hh + pad
		local y = ScrH() - h - S(28)
		UI.Comic(x, y, w, h, S(12), Color(C.panel.r, C.panel.g, C.panel.b, 235), C.edge, S(4), 170)
		UI.Icon("eye", x + pad, y + pad + S(3), 16)
		UI.Text(P.L("spec_free"), "Praetor.H3", x + pad + S(22), y + pad + S(11), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(string.format("x%.1f", freeSpeed), "Praetor.SmallB", x + w - pad, y + pad + S(11), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		hints(list, x + pad, y + pad + S(28), inner)
		return
	end

	-- watching a player
	if mode == "eyes" and t:IsPlayer() then
		-- crosshair where the player aims
		local cx, cy = ScrW() / 2, ScrH() / 2
		local acc = C.bronzeL
		surface.SetDrawColor(0, 0, 0, 160)
		surface.DrawRect(cx - 2, cy - 2, 5, 5)
		surface.SetDrawColor(acc.r, acc.g, acc.b, 255)
		surface.DrawRect(cx - 1, cy - 1, 3, 3)
		local gap, len = S(5), S(6)
		surface.DrawRect(cx - 1, cy - gap - len, 2, len)
		surface.DrawRect(cx - 1, cy + gap, 2, len)
		surface.DrawRect(cx - gap - len, cy - 1, len, 2)
		surface.DrawRect(cx + gap, cy - 1, len, 2)
	end

	local list = {
		{ P.L("spec_k_lmb") .. " / " .. P.L("spec_k_rmb"), P.L("spec_k_next") }, { "R", mode == "eyes" and P.L("spec_third") or P.L("spec_first") },
		{ "E", P.L("spec_k_freecam") }, { P.L("spec_k_wheel"), P.L("spec_k_zoom") }, { "Backspace", P.L("spec_k_leave") },
	}
	local hh = hintsHeight(list, inner)
	local isP = t:IsPlayer()
	local rowsH = isP and (S(26) + S(24) + S(22) + S(22) + S(22)) or S(30)
	local h = pad + S(16) + rowsH + S(8) + hh + pad
	local y = ScrH() - h - S(28)
	UI.Comic(x, y, w, h, S(12), Color(C.panel.r, C.panel.g, C.panel.b, 235), C.edge, S(4), 170)

	-- header: SPECTATING ........ 1st person
	local ty = y + pad
	UI.Text(P.L("spec_watching"), "Praetor.Tiny", x + pad, ty, C.muted)
	local modeTxt = mode == "eyes" and P.L("spec_first") or P.L("spec_third")
	surface.SetFont("Praetor.Tiny")
	local mw = surface.GetTextSize(modeTxt) + S(14)
	UI.Round(x + w - pad - mw, ty - S(2), mw, S(16), S(8), Color(C.bronze.r, C.bronze.g, C.bronze.b, 60), C.bronze, 1)
	UI.Text(modeTxt, "Praetor.Tiny", x + w - pad - mw / 2, ty + S(6), C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	ty = ty + S(16)

	if not isP then
		UI.Text(UI.Fit(t:GetClass(), "Praetor.H2", inner), "Praetor.H2", x + pad, ty + S(4), C.ivory)
	else
		-- name and rank
		local style, icon = UI.PlayerRankStyle(t)
		local badgeW = S(150)
		UI.Name(t:Nick(), "Praetor.H2", x + pad, ty + S(13), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, inner - badgeW - S(10), true)
		UI.Badge(style, icon, "Praetor.Tag", x + w - pad, ty + S(2), S(22), 255, TEXT_ALIGN_RIGHT)
		ty = ty + S(26)
		-- health and armor bars, side by side
		local half = math.floor((inner - S(10)) / 2)
		local hp, maxHp = math.max(0, t:Health()), math.max(1, t:GetMaxHealth())
		local ar = math.max(0, t:Armor())
		local maxAr = math.max(1, t.GetMaxArmor and t:GetMaxArmor() or 100)
		UI.Icon("heart", x + pad, ty + S(2), 16)
		bar(x + pad + S(22), ty + S(1), half - S(22), S(18), math.Clamp(hp / maxHp, 0, 1), C.crimson, shortNum(hp) .. " / " .. shortNum(maxHp))
		UI.Icon("vest", x + pad + half + S(10), ty + S(2), 16)
		bar(x + pad + half + S(32), ty + S(1), half - S(22), S(18), math.Clamp(ar / maxAr, 0, 1), C.sky, shortNum(ar) .. " / " .. shortNum(maxAr))
		ty = ty + S(24)
		-- weapon and ammo
		local wname, ammo = weaponText(t)
		surface.SetFont("Praetor.SmallB")
		local aw = ammo ~= "" and surface.GetTextSize(ammo) or 0
		surface.SetFont("Praetor.Tiny")
		local lw = surface.GetTextSize(P.L("spec_weapon"))
		UI.Icon("gun", x + pad, ty + S(2), 16)
		UI.Text(P.L("spec_weapon"), "Praetor.Tiny", x + pad + S(22), ty + S(10), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(UI.Fit(wname, "Praetor.SmallB", inner - S(22) - lw - S(10) - aw - S(10)), "Praetor.SmallB", x + pad + S(22) + lw + S(4), ty + S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if ammo ~= "" then UI.Text(ammo, "Praetor.SmallB", x + w - pad, ty + S(10), C.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
		ty = ty + S(22)
		-- looking at
		local what, far, who = lookingAt(t)
		surface.SetFont("Praetor.SmallB")
		local fw = far ~= "" and surface.GetTextSize(far) or 0
		surface.SetFont("Praetor.Tiny")
		local lw2 = surface.GetTextSize(P.L("spec_look"))
		UI.Icon("target", x + pad, ty + S(2), 16)
		UI.Text(P.L("spec_look"), "Praetor.Tiny", x + pad + S(22), ty + S(10), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local lookCol = IsValid(who) and C.amber or C.text
		UI.Name(what, "Praetor.SmallB", x + pad + S(22) + lw2 + S(4), ty + S(10), lookCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, inner - S(22) - lw2 - S(10) - fw - S(10))
		if far ~= "" then UI.Text(far, "Praetor.SmallB", x + w - pad, ty + S(10), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
		ty = ty + S(22)
		-- speed and ping
		local kmh = math.floor(t:GetVelocity():Length2D() * 0.01905 * 3.6 + 0.5)
		UI.Icon("speed", x + pad, ty + S(2), 16)
		UI.Text(P.L("spec_speed") .. ": " .. kmh .. " km/h", "Praetor.SmallB", x + pad + S(22), ty + S(10), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text("Ping: " .. t:Ping(), "Praetor.SmallB", x + w - pad, ty + S(10), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		ty = ty + S(22)
	end
	UI.Rect(x + pad, ty + S(3), inner, 1, C.line)
	hints(list, x + pad, ty + S(8), inner)
end)
