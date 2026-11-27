-- Praetor: DarkRP HUD. A card at the bottom left (avatar, name, job, health,
-- armor, hunger, money and salary on one grid), the ammo at the bottom right, the
-- agenda at the top left and a banner during a lockdown.
-- Server: Settings > DarkRP (hud, hud_hunger, hud_agenda). Each player can
-- turn it off with praetor_hud 0 and get DarkRP's own HUD back.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local hudVar = CreateClientConVar("praetor_hud", "1", true, false, "Praetor's DarkRP HUD (0 = DarkRP's own)", 0, 1)

local HUD = P.HUD or {}
P.HUD = HUD

local function on()
	return P.IsDarkRP() and P.Setting("hud") ~= false and hudVar:GetBool()
end
HUD.On = on

local function rp(var)
	local me = LocalPlayer()
	return IsValid(me) and me.getDarkRPVar and me:getDarkRPVar(var) or nil
end

local function money(v)
	v = tonumber(v) or 0
	if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(v) end
	return "$" .. string.Comma(v)
end

local function inkOn(c)
	return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 150 and C.ink or color_white
end

-- ------------------------------------------------------------------ hide the default parts

local HIDE = {
	CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true,
	DarkRP_HUD = true, DarkRP_LocalPlayerHUD = true, DarkRP_Hungermod = true,
	DarkRP_LockdownHUD = true, DarkRP_ArrestedHUD = true,
}
hook.Add("HUDShouldDraw", "Praetor.HUD", function(name)
	if not HIDE[name] and name ~= "DarkRP_Agenda" then return end
	if not on() then return end
	if name == "DarkRP_Agenda" then
		if P.Setting("hud_agenda") ~= false then return false end
		return
	end
	return false
end)

-- ------------------------------------------------------------------ the avatar (a real Steam picture, painted by hand)

local avatar
local function drawAvatar(x, y, size)
	local me = LocalPlayer()
	if not IsValid(avatar) then
		avatar = vgui.Create("AvatarImage")
		avatar:SetPaintedManually(true)
		avatar:SetPlayer(me, 64)
		avatar.ply = me
	end
	if avatar.ply ~= me then avatar:SetPlayer(me, 64) avatar.ply = me end
	avatar:SetSize(size, size)
	avatar:SetPos(x, y)
	avatar:PaintManual()
end

-- ------------------------------------------------------------------ smooth numbers

-- shown values follow the real ones; a light "ghost" part shows what was just lost
local show = { hp = 100, ar = 0, en = 100, money = 0, ghostHp = 100 }
local floaters = {}
local lastMoney, lastHp
local hitAt = 0

local function track()
	local me = LocalPlayer()
	local hp, ar = math.max(0, me:Health()), me:Armor()
	local m = tonumber(rp("money")) or 0
	if lastHp and hp < lastHp then hitAt = RealTime() end
	lastHp = hp
	if lastMoney and m ~= lastMoney then
		-- a "+$100" / "-$50" floats up from the money pill
		floaters[#floaters + 1] = { t = RealTime(), v = m - lastMoney }
		if #floaters > 5 then table.remove(floaters, 1) end
		if m > lastMoney then UI.Sound("ok") end
	end
	lastMoney = m
	local ft = FrameTime()
	show.hp = Lerp(math.min(1, ft * 10), show.hp, hp)
	show.ar = Lerp(math.min(1, ft * 10), show.ar, ar)
	show.en = Lerp(math.min(1, ft * 6), show.en, tonumber(rp("Energy")) or 100)
	show.money = Lerp(math.min(1, ft * 6), show.money, m)
	if math.abs(show.money - m) < 1 then show.money = m end
	-- the ghost waits a moment, then slides down
	if RealTime() - hitAt > 0.45 then show.ghostHp = Lerp(math.min(1, ft * 4), show.ghostHp, hp) end
	if show.ghostHp < hp then show.ghostHp = hp end
end

-- ------------------------------------------------------------------ pieces

local function fontH(f)
	surface.SetFont(f)
	local _, h = surface.GetTextSize("ÁgjM")
	return h
end

-- flat rounded bar with a ghost part (what was just lost)
local function bar(x, y, w, h, frac, ghost, col)
	frac, ghost = math.Clamp(frac, 0, 1), math.Clamp(ghost or 0, 0, 1)
	UI.Round(x, y, w, h, h / 2, Color(0, 0, 0, 120))
	if ghost > frac then UI.Round(x, y, math.max(h, w * ghost), h, h / 2, Color(255, 255, 255, 150)) end
	if frac > 0 then
		UI.Round(x, y, math.max(h, w * frac), h, h / 2, col)
		UI.Round(x + S(3), y + 1, math.max(0, w * frac - S(6)), math.max(1, math.floor(h / 3)), S(1), Color(255, 255, 255, 45))
	end
end

local function pill(x, y, text, font, fill, icon, fg)
	surface.SetFont(font)
	local tw = surface.GetTextSize(text)
	local h = fontH(font) + S(6)
	local w = tw + S(16) + (icon and S(20) or 0)
	UI.Comic(x, y, w, h, h / 2, fill, C.ink, S(2))
	local tx = x + S(8)
	if icon then UI.Icon(icon, tx, y + (h - 16) / 2, 16) tx = tx + S(20) end
	draw.SimpleText(text, font, tx, y + h / 2, fg or inkOn(fill), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return w, h
end

local function shadowText(text, font, x, y, col, ax, ay)
	draw.SimpleText(text, font, x + 1, y + 1, Color(0, 0, 0, 170), ax, ay)
	draw.SimpleText(text, font, x, y, col, ax, ay)
end

-- ------------------------------------------------------------------ main card
-- One card, three rows on a grid:
--   header  avatar | name, job
--   bars    icon | bar | value      (health, armor, hunger)
--   footer  money | salary
-- Every row is placed from the real height of its fonts, the icons and the
-- values sit in fixed columns, nothing hangs out of the card.

local born
local function drawMain()
	local me = LocalPlayer()
	local sh = ScrH()
	born = born or RealTime()
	local k = UI.EaseBack(math.min(1, (RealTime() - born) / 0.5))
	local hasHunger = P.Setting("hud_hunger") ~= false and rp("Energy") ~= nil

	local pad = S(14)
	local W = S(340)
	local av = S(50)
	local nameH, tinyH, smallH, moneyH = fontH("Praetor.H2"), fontH("Praetor.Tiny"), fontH("Praetor.SmallB"), fontH("Praetor.BodyB")
	local pillH = tinyH + S(6)
	local headH = math.max(av, nameH + S(4) + pillH)
	local barH, rowH = S(9), math.max(S(20), smallH)
	local rows = hasHunger and 3 or 2
	local footH = moneyH
	local H = pad + headH + S(12) + 1 + S(10) + rows * rowH + (rows - 1) * S(4) + S(10) + 1 + S(10) + footH + pad

	local x = S(22)
	local y = sh - H - S(22) + math.floor((1 - k) * S(60))

	local hp, mhp = show.hp, math.max(1, me:GetMaxHealth())
	local low = me:Health() / mhp <= 0.25 and me:Alive()
	local edge = C.lineL
	if low then edge = P.LerpColor((math.sin(RealTime() * 8) + 1) / 2, C.lineL, C.crimson) end
	local shake = math.max(0, 0.25 - (RealTime() - hitAt)) * 4
	x = x + math.floor(math.sin(RealTime() * 70) * S(3) * shake)

	UI.Comic(x, y, W, H, S(14), Color(C.panel.r, C.panel.g, C.panel.b, 238), edge, S(4))
	local ix, iw = x + pad, W - pad * 2

	-- header: avatar with a frame in the job colour, name and job
	local job = rp("job") or team.GetName(me:Team())
	local jc = team.GetColor(me:Team())
	local hy = y + pad
	local ay = hy + math.floor((headH - av) / 2)
	UI.Round(ix - S(3), ay - S(3), av + S(6), av + S(6), S(12), jc, C.ink)
	drawAvatar(ix, ay, av)
	local tx = ix + av + S(12)
	local tw = ix + iw - tx
	local ty = hy + math.floor((headH - (nameH + S(4) + pillH)) / 2)
	UI.Name(me:Nick(), "Praetor.H2", tx, ty, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, tw, true)
	-- job pill, and the gun license seal next to it when I have one
	local lic = rp("HasGunlicense")
	local licW = 0
	if lic then
		surface.SetFont("Praetor.Tiny")
		licW = surface.GetTextSize(P.L("sb_license")) + S(36) + S(6)
	end
	local jw = pill(tx, ty + nameH + S(4), UI.Fit(job, "Praetor.Tiny", tw - S(20) - licW), "Praetor.Tiny", jc)
	if lic then pill(tx + jw + S(6), ty + nameH + S(4), P.L("sb_license"), "Praetor.Tiny", C.sky, "permit") end

	-- bars
	local ry = hy + headH + S(12)
	UI.Rect(ix, ry, iw, 1, C.line)
	ry = ry + 1 + S(10)
	local valW = S(46)
	local bx = ix + S(26)
	local bw = iw - S(26) - valW - S(8)
	local function row(icon, iconCol, frac, ghost, col, value)
		local cy = ry + rowH / 2
		UI.Icon(icon, ix, cy - 9, 18, iconCol)
		bar(bx, cy - barH / 2, bw, barH, frac, ghost, col)
		shadowText(value, "Praetor.SmallB", ix + iw, cy, C.ivory, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		ry = ry + rowH + S(4)
	end
	local hpCol = low and P.LerpColor((math.sin(RealTime() * 8) + 1) / 2, C.crimson, C.crimsonL) or C.crimson
	row("heart", nil, hp / mhp, show.ghostHp / mhp, hpCol, tostring(math.max(0, me:Health())))
	local ma = math.max(1, me.GetMaxArmor and me:GetMaxArmor() or 100)
	row("shield", nil, show.ar / ma, 0, C.sky, tostring(math.max(0, me:Armor())))
	if hasHunger then
		local en = tonumber(rp("Energy")) or 100
		row("leaf", nil, show.en / 100, 0, en <= 20 and C.crimsonL or C.amber, math.floor(en) .. "%")
	end
	ry = ry - S(4) + S(10)

	-- footer: money on the left, salary on the right
	UI.Rect(ix, ry, iw, 1, C.line)
	ry = ry + 1 + S(10)
	local fy = ry + footH / 2
	UI.Icon("coin", ix, fy - 9, 18)
	local moneyTxt = money(math.floor(show.money))
	shadowText(moneyTxt, "Praetor.BodyB", ix + S(26), fy, C.laurel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local sal = tonumber(rp("salary")) or 0
	if sal > 0 then
		local st = P.L("hud_salary", { V = money(sal) })
		surface.SetFont("Praetor.BodyB")
		local mw = surface.GetTextSize(moneyTxt)
		local room = iw - S(26) - mw - S(30)
		st = UI.Fit(st, "Praetor.Tiny", room)
		surface.SetFont("Praetor.Tiny")
		local sw = surface.GetTextSize(st)
		shadowText(st, "Praetor.Tiny", ix + iw, fy, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		UI.Icon("clock", ix + iw - sw - S(20), fy - 8, 16, C.muted)
	end

	-- "+$100" / "-$50" float up over the card
	for i = #floaters, 1, -1 do
		local f = floaters[i]
		local age = RealTime() - f.t
		if age > 1.6 then
			table.remove(floaters, i)
		else
			local a = 255 * math.min(1, (1.6 - age) * 2)
			local fy2 = y - S(6) - age * S(36)
			local txt = (f.v > 0 and "+" or "-") .. money(math.abs(f.v))
			local col = f.v > 0 and C.laurel or C.crimsonL
			draw.SimpleText(txt, "Praetor.H2", x + S(8) + S(2), fy2 + S(2), Color(C.ink.r, C.ink.g, C.ink.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(txt, "Praetor.H2", x + S(8), fy2, Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		end
	end

	-- states over the card: wanted (blinks), arrested, license
	local chips = {}
	if rp("wanted") then chips[#chips + 1] = { P.L("sb_wanted"), C.crimson, "wanted", blink = true } end
	if rp("Arrested") then chips[#chips + 1] = { P.L("hud_arrested"), C.amber, "jail" } end

	local cx = x
	local cy = y - S(10) - pillH
	for _, c in ipairs(chips) do
		surface.SetFont("Praetor.Tiny")
		local cw = surface.GetTextSize(c[1]) + S(36)
		if not c.blink or math.floor(RealTime() * 3) % 2 == 0 then pill(cx, cy, c[1], "Praetor.Tiny", c[2], c[3]) end
		cx = cx + cw + S(6)
	end
	if rp("wanted") and rp("wantedReason") then
		shadowText(UI.Fit(tostring(rp("wantedReason")), "Praetor.Small", W), "Praetor.Small", x + S(2), cy - S(6), C.crimsonL, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end
end

-- ------------------------------------------------------------------ ammo

local ammoShow = 0
local function drawAmmo()
	local me = LocalPlayer()
	local wep = me:GetActiveWeapon()
	if not IsValid(wep) then return end
	local clip, max = wep:Clip1(), wep:GetMaxClip1()
	local reserve = me:GetAmmoCount(wep:GetPrimaryAmmoType())
	if clip < 0 and reserve <= 0 then return end
	local sw, sh = ScrW(), ScrH()
	local W, H = S(230), S(86)
	local x, y = sw - W - S(26), sh - H - S(26)
	UI.Comic(x, y, W, H, S(16), Color(C.panel.r, C.panel.g, C.panel.b, 238), C.lineL, S(5))
	local name = wep.GetPrintName and wep:GetPrintName() or wep:GetClass()
	name = language.GetPhrase(name)
	UI.Icon("gun", x + S(14), y + S(10), 20)
	UI.Text(UI.Fit(name, "Praetor.SmallB", W - S(54)), "Praetor.SmallB", x + S(40), y + S(20), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local main = clip >= 0 and clip or reserve
	-- the clip number gives a little jump on every shot
	if main ~= ammoShow then ammoShow = main HUD.shotAt = RealTime() end
	local jump = math.max(0, 0.12 - (RealTime() - (HUD.shotAt or 0))) / 0.12
	local col = (clip >= 0 and max > 0 and clip <= max * 0.25) and C.crimsonL or C.ivory
	draw.SimpleText(main, "Praetor.Hero", x + S(16) + S(3), y + S(36) + S(3) - jump * S(4), C.ink)
	draw.SimpleText(main, "Praetor.Hero", x + S(16), y + S(36) - jump * S(4), col)
	if clip >= 0 then
		surface.SetFont("Praetor.Hero")
		local tw = surface.GetTextSize(tostring(main))
		draw.SimpleText("/ " .. reserve, "Praetor.H2", x + S(24) + tw, y + S(52), C.muted)
	end
end

-- ------------------------------------------------------------------ agenda and lockdown

local function drawAgenda()
	if P.Setting("hud_agenda") == false then return end
	local me = LocalPlayer()
	local agenda = me.getAgendaTable and me:getAgendaTable()
	if not agenda then return end
	local text = tostring(rp("agenda") or "")
	text = text:gsub("//", "\n"):gsub("\\n", "\n")
	local W = S(340)
	local x, y = S(22), S(22)
	local lines = {}
	for part in (P.Trim(text) == "" and P.L("hud_agenda_empty") or text):gmatch("[^\n]+") do
		for _, l in ipairs(UI.Wrap(part, "Praetor.Small", W - S(28))) do lines[#lines + 1] = l end
	end
	while #lines > 6 do table.remove(lines) end
	local H = S(46) + #lines * S(18) + S(8)
	UI.Comic(x, y, W, H, S(14), Color(C.panel.r, C.panel.g, C.panel.b, 230), C.line, S(4))
	UI.Icon("scroll", x + S(12), y + S(10), 20)
	UI.Text(UI.Fit(tostring(agenda.Title or "Agenda"), "Praetor.BodyB", W - S(60)), "Praetor.BodyB", x + S(40), y + S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Rect(x + S(12), y + S(38), W - S(28), 2, C.line)
	for i, l in ipairs(lines) do
		UI.Text(l, "Praetor.Small", x + S(14), y + S(46) + (i - 1) * S(18), C.text)
	end
end

local function drawLockdown()
	if not GetGlobalBool("DarkRP_LockDown") then return end
	local t = P.L("hud_lockdown")
	surface.SetFont("Praetor.H1")
	local tw = surface.GetTextSize(t)
	local w, h = tw + S(80), S(50)
	local x, y = ScrW() / 2 - w / 2, S(18)
	local wob = math.sin(RealTime() * 5) * 1.5
	-- a red comic banner, slightly tilted, that rocks
	local m = Matrix()
	m:Translate(Vector(ScrW() / 2, y + h / 2, 0))
	m:Rotate(Angle(0, wob, 0))
	m:Translate(Vector(-ScrW() / 2, -(y + h / 2), 0))
	cam.PushModelMatrix(m, true)
	UI.Comic(x, y, w, h, S(10), C.crimson, C.ink, S(5))
	UI.Icon("warn", x + S(14), y + (h - 24) / 2, 24)
	UI.Icon("warn", x + w - S(38), y + (h - 24) / 2, 24)
	draw.SimpleText(t, "Praetor.H1", ScrW() / 2 + S(2), y + h / 2 + S(2), C.ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(t, "Praetor.H1", ScrW() / 2, y + h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cam.PopModelMatrix()
end

hook.Add("HUDPaint", "Praetor.HUD", function()
	if not on() then born = nil return end
	local me = LocalPlayer()
	if not IsValid(me) then return end
	if hook.Run("HUDShouldDraw", "PraetorHUD") == false then return end
	track()
	if me:Alive() then
		drawMain()
		drawAmmo()
	end
	drawAgenda()
	drawLockdown()
end)
