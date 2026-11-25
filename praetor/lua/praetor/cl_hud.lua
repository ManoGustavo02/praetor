-- Praetor: DarkRP HUD. A comic card at the bottom left (avatar, name, job,
-- health, armor, hunger, money and salary), the ammo at the bottom right, the
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

-- outlined bar with an icon, the value and a ghost part
local function bar(x, y, w, h, icon, frac, ghost, col, label)
	local bw = UI.BW()
	UI.Round(x + S(2), y + S(2), w, h, h / 2, C.ink)
	UI.Round(x, y, w, h, h / 2, C.bg, C.ink)
	local iw = w - bw * 2
	frac, ghost = math.Clamp(frac, 0, 1), math.Clamp(ghost or 0, 0, 1)
	if ghost > frac then UI.Round(x + bw, y + bw, math.max(h - bw * 2, iw * ghost), h - bw * 2, (h - bw * 2) / 2, Color(255, 255, 255, 170)) end
	if frac > 0 then
		UI.Round(x + bw, y + bw, math.max(h - bw * 2, iw * frac), h - bw * 2, (h - bw * 2) / 2, col)
		-- a light line on top, like a shine
		UI.Round(x + bw + S(4), y + bw + S(2), math.max(0, iw * frac - S(8)), S(2), S(1), Color(255, 255, 255, 70))
	end
	-- the icon sits on a disc at the start of the bar
	local d = h + S(10)
	UI.Round(x - d / 2, y + h / 2 - d / 2, d, d, d / 2, col, C.ink)
	UI.Icon(icon, x - 10, y + h / 2 - 10, 20)
	draw.SimpleText(label, "Praetor.Tiny", x + w - S(8) + 1, y + h / 2 + 1, C.ink, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText(label, "Praetor.Tiny", x + w - S(8), y + h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

local function pill(x, y, text, font, fill, icon, fg)
	surface.SetFont(font)
	local tw, th = surface.GetTextSize(text)
	local h = th + S(10)
	local w = tw + S(20) + (icon and S(22) or 0)
	UI.Comic(x, y, w, h, h / 2, fill, C.ink, S(3))
	local tx = x + S(10)
	if icon then UI.Icon(icon, tx, y + (h - 16) / 2, 16) tx = tx + S(22) end
	draw.SimpleText(text, font, tx, y + h / 2, fg or inkOn(fill), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return w, h
end

-- ------------------------------------------------------------------ main card

local born
local function drawMain()
	local me = LocalPlayer()
	local sw, sh = ScrW(), ScrH()
	born = born or RealTime()
	local k = UI.EaseBack(math.min(1, (RealTime() - born) / 0.5))
	local hasHunger = P.Setting("hud_hunger") ~= false and rp("Energy") ~= nil
	local W = S(372)
	local H = hasHunger and S(156) or S(134)
	local x = S(22)
	local y = sh - H - S(22) + math.floor((1 - k) * S(60))

	local hp, mhp = show.hp, math.max(1, me:GetMaxHealth())
	local low = me:Health() / mhp <= 0.25 and me:Alive()
	-- low health: the outline blinks red
	local edge = C.lineL
	if low then edge = P.LerpColor((math.sin(RealTime() * 8) + 1) / 2, C.lineL, C.crimson) end
	-- shake for a moment when hit
	local shake = math.max(0, 0.25 - (RealTime() - hitAt)) * 4
	x = x + math.floor(math.sin(RealTime() * 70) * S(3) * shake)

	UI.Comic(x, y, W, H, S(16), Color(C.panel.r, C.panel.g, C.panel.b, 238), edge, S(5))

	-- avatar with a job-coloured frame
	local job = rp("job") or team.GetName(me:Team())
	local jc = team.GetColor(me:Team())
	local av = S(62)
	local ax, ay = x + S(14), y + S(14)
	UI.Round(ax - S(3) + S(3), ay - S(3) + S(3), av + S(6), av + S(6), S(14), C.ink)
	UI.Round(ax - S(3), ay - S(3), av + S(6), av + S(6), S(14), jc, C.ink)
	drawAvatar(ax, ay, av)

	-- name and job pill
	local tx = ax + av + S(14)
	local nm = UI.Fit(me:Nick(), "Praetor.H2", W - (tx - x) - S(14))
	draw.SimpleText(nm, "Praetor.H2", tx + S(2), ay + S(2), C.ink)
	draw.SimpleText(nm, "Praetor.H2", tx, ay, C.ivory)
	pill(tx, ay + S(32), UI.Fit(job, "Praetor.SmallB", W - (tx - x) - S(40)), "Praetor.SmallB", jc)

	-- bars
	local bx = x + S(40)
	local bw = W - S(56)
	local by = ay + av + S(18)
	local barH = S(16)
	bar(bx, by, bw, barH, "heart", hp / mhp, show.ghostHp / mhp, low and P.LerpColor((math.sin(RealTime() * 8) + 1) / 2, C.crimson, C.crimsonL) or C.crimson, math.max(0, me:Health()) .. "")
	by = by + barH + S(8)
	local ma = math.max(1, me.GetMaxArmor and me:GetMaxArmor() or 100)
	bar(bx, by, bw, barH, "shield", show.ar / ma, 0, C.sky, me:Armor() .. "")
	if hasHunger then
		by = by + barH + S(8)
		local en = tonumber(rp("Energy")) or 100
		bar(bx, by, bw, barH, "leaf", show.en / 100, 0, en <= 20 and C.crimsonL or C.amber, math.floor(en) .. "%")
	end

	-- money and salary pills above the card, floating "+$" over them
	local mx, my = x + S(4), y - S(40)
	local mw = pill(mx, my, money(math.floor(show.money)), "Praetor.BodyB", C.laurel, "coin")
	local sal = tonumber(rp("salary")) or 0
	if sal > 0 then pill(mx + mw + S(8), my + S(4), "+" .. money(sal), "Praetor.Tiny", C.panel3, "clock", C.laurel) end
	for i = #floaters, 1, -1 do
		local f = floaters[i]
		local age = RealTime() - f.t
		if age > 1.6 then
			table.remove(floaters, i)
		else
			local a = 255 * math.min(1, (1.6 - age) * 2)
			local fy = my - S(8) - age * S(36)
			local txt = (f.v > 0 and "+" or "-") .. money(math.abs(f.v))
			local col = f.v > 0 and C.laurel or C.crimsonL
			draw.SimpleText(txt, "Praetor.H2", mx + S(14) + S(2), fy + S(2), Color(C.ink.r, C.ink.g, C.ink.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(txt, "Praetor.H2", mx + S(14), fy, Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		end
	end

	-- states over the money: wanted (blinks), arrested, license
	local chips = {}
	if rp("wanted") then chips[#chips + 1] = { P.L("sb_wanted"), C.crimson, "flag", blink = true } end
	if rp("Arrested") then chips[#chips + 1] = { P.L("hud_arrested"), C.amber, "jail" } end
	if rp("HasGunlicense") then chips[#chips + 1] = { P.L("sb_license"), C.sky, "license" } end
	local cx = x + S(4)
	local cy = my - S(34)
	for _, c in ipairs(chips) do
		if not c.blink or math.floor(RealTime() * 3) % 2 == 0 then
			local w2 = pill(cx, cy, c[1], "Praetor.Tiny", c[2], c[3])
			cx = cx + w2 + S(6)
		else
			surface.SetFont("Praetor.Tiny")
			cx = cx + surface.GetTextSize(c[1]) + S(48)
		end
	end
	if rp("wanted") and rp("wantedReason") then
		draw.SimpleText(UI.Fit(tostring(rp("wantedReason")), "Praetor.Small", S(360)), "Praetor.Small", x + S(6), cy - S(14), C.crimsonL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
