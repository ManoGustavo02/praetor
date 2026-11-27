-- Praetor: what a jailed player sees. A card at the bottom of the screen with the
-- time left (live) or "Permanent", who jailed them and the reason; and the sign
-- that floats over the cell (drawn by the praetor_jail entity) for everyone else.
local P = Praetor
local UI = P.UI
local C = UI.C

-- time left, length, who and why, from the values the server sets on the player
function P.JailInfo(ply)
	local endT = ply:GetNW2Float("pr_jailend", 0)
	local perm = endT <= 0
	local by = ply:GetNW2String("pr_jailby", "")
	local reason = ply:GetNW2String("pr_jailr", "")
	return {
		perm = perm,
		left = perm and 0 or math.max(0, endT - CurTime()),
		len = ply:GetNW2Float("pr_jaillen", 0),
		by = by ~= "" and by or "?",
		reason = reason ~= "" and reason or P.L("jail_no_reason"),
	}
end

-- 75 -> "01:15", 3725 -> "1:02:05", 90000 -> "1d 01:00:00"
local function clock(sec)
	sec = math.max(0, math.ceil(sec))
	local d = math.floor(sec / 86400)
	local h = math.floor(sec % 86400 / 3600)
	local m = math.floor(sec % 3600 / 60)
	local s = sec % 60
	if d > 0 then return string.format("%dd %02d:%02d:%02d", d, h, m, s) end
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%02d:%02d", m, s)
end
P.JailClock = clock

-- ------------------------------------------------------------------ sign over the cell
-- drawn in 3D2D (big fonts, small scale); centred on x = 0, bottom at y = 0.
-- Every line is placed from the real height of its font and the sign grows with
-- what it holds: a long name is shortened, a long reason wraps in up to 3 lines.
local function fontH(f)
	surface.SetFont(f)
	local _, h = surface.GetTextSize("ÁgjM")
	return h
end

local SIGN_MAXW = 900
function P.DrawJailSign(ply, info)
	local pad, maxW = 36, SIGN_MAXW
	local name = ply:Nick()
	local time = info.perm and P.L("jail_perm") or clock(info.left)
	local tag = P.L("jail_sign")

	surface.SetFont("Praetor.OH.Tag")
	local tagW = surface.GetTextSize(tag) + 72 + 40
	local nameFont = UI.FontFor and UI.FontFor(name, "Praetor.OH.Name") or "Praetor.OH.Name"
	surface.SetFont(nameFont)
	local nameW = math.min(maxW, surface.GetTextSize(name))
	surface.SetFont("Praetor.OH.Rank")
	local timeW = surface.GetTextSize(time)

	local lines = UI.Wrap(info.reason, "Praetor.OH.Small", maxW)
	if #lines > 3 then
		lines = { lines[1], lines[2], UI.Fit(table.concat(lines, " ", 3), "Praetor.OH.Small", maxW) }
	end
	surface.SetFont("Praetor.OH.Small")
	local reasonW = 0
	for _, l in ipairs(lines) do reasonW = math.max(reasonW, surface.GetTextSize(l)) end

	local nameH, timeH, lineH = fontH(nameFont), fontH("Praetor.OH.Rank"), fontH("Praetor.OH.Small")
	local pillH = 60
	local w = math.max(tagW, nameW, timeW, reasonW) + pad * 2
	local h = pad + pillH + 14 + nameH + timeH + 12 + #lines * lineH + pad
	local x, y = -w / 2, -h

	UI.Round(x + 10, y + 12, w, h, 26, Color(C.ink.r, C.ink.g, C.ink.b, 200))
	UI.Round(x, y, w, h, 26, Color(C.panel.r, C.panel.g, C.panel.b, 252), C.ink, 6)
	UI.Round(x + 6, y + 6, w - 12, 8, 4, C.crimson)

	-- red pill with the cuffs: PRESO / JAILED
	local cy = y + pad
	UI.Round(-tagW / 2, cy, tagW, pillH, pillH / 2, C.crimson, C.ink, 4)
	UI.Icon("jail", -tagW / 2 + 22, cy + (pillH - 48) / 2, 48)
	draw.SimpleText(tag, "Praetor.OH.Tag", -tagW / 2 + 22 + 48 + 14, cy + pillH / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	cy = cy + pillH + 14

	UI.Name(name, "Praetor.OH.Name", 0, cy, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, maxW)
	cy = cy + nameH
	draw.SimpleText(time, "Praetor.OH.Rank", 0, cy, info.perm and C.amber or C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	cy = cy + timeH + 12
	for _, l in ipairs(lines) do
		draw.SimpleText(l, "Praetor.OH.Small", 0, cy, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		cy = cy + lineH
	end
end

-- ------------------------------------------------------------------ card for the prisoner
local fade = 0
hook.Add("HUDPaint", "Praetor.JailHUD", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local jailed = me:GetNW2Bool("pr_jailed")
	fade = math.Approach(fade, jailed and 1 or 0, FrameTime() * 4)
	if fade <= 0 then return end
	local a = fade
	local S = P.S
	local info = P.JailInfo(me)

	local w = math.min(ScrW() - S(40), S(440))
	local pad = S(14)
	local inner = w - pad * 2
	local reasonLines = UI.Wrap(info.reason, "Praetor.Body", inner)
	if #reasonLines > 3 then
		reasonLines = { reasonLines[1], reasonLines[2], UI.Fit(table.concat(reasonLines, " ", 3), "Praetor.Body", inner) }
	end
	-- heights from the fonts, so the text never runs out of the card
	local tinyH, boldH, lineH = fontH("Praetor.Tiny"), fontH("Praetor.BodyB"), fontH("Praetor.Body")
	local headH, barH = S(36), S(26)
	local infoH = S(8) + tinyH + S(2) + boldH + S(8)
	local reasonH = tinyH + S(2) + #reasonLines * lineH
	local h = pad + headH + barH + infoH + reasonH + pad
	local x = math.floor((ScrW() - w) / 2)
	local y = math.floor(ScrH() - h - S(96) + (1 - a) * S(24))
	local function A(c, k) return Color(c.r, c.g, c.b, (c.a or 255) * a * (k or 1)) end

	UI.Comic(x, y, w, h, S(12), A(C.panel, 0.92), A(C.edge), S(4), 190 * a)
	UI.Round(x + S(3), y + S(3), w - S(6), S(4), S(2), A(C.crimson))

	-- title and the time left on the right
	local ty = y + pad
	UI.Icon("jail", x + pad, ty + (headH - 32) / 2, 32, Color(255, 255, 255, 255 * a))
	local timeTxt, timeFont, timeCol
	if info.perm then
		timeTxt, timeFont, timeCol = P.L("jail_perm"), "Praetor.H2", C.amber
	else
		timeTxt, timeFont, timeCol = clock(info.left), "Praetor.Num", C.ivory
	end
	surface.SetFont(timeFont)
	local timeW = surface.GetTextSize(timeTxt)
	UI.Text(timeTxt, timeFont, x + w - pad, ty + headH / 2, A(timeCol), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	local titleW = inner - S(42) - timeW - S(12)
	UI.Text(UI.Fit(P.L("jail_hud_title"), "Praetor.H2", titleW), "Praetor.H2", x + pad + S(42), ty + headH / 2, A(C.crimsonL), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- how much of the time has passed, or a line saying only the staff can let you out
	local by = ty + headH + S(6)
	if info.perm then
		UI.Text(UI.Fit(P.L("jail_perm_sub"), "Praetor.Small", inner), "Praetor.Small", x + pad, by + S(6), A(C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	else
		local frac = info.len > 0 and math.Clamp(1 - info.left / info.len, 0, 1) or 0
		local bh = S(10)
		UI.Round(x + pad, by, inner, bh, bh / 2, A(C.bg), A(C.ink), 2)
		if frac > 0 then UI.Round(x + pad + 2, by + 2, math.max(bh - 4, (inner - 4) * frac), bh - 4, (bh - 4) / 2, A(C.bronze)) end
	end

	-- who jailed you | total time
	local iy = ty + headH + barH
	UI.Rect(x + pad, iy, inner, 1, A(C.line))
	local colW = math.floor((inner - S(12)) / 2)
	local vy = iy + S(8) + tinyH + S(2)
	UI.Text(UI.Fit(P.L("jail_by"):upper(), "Praetor.Tiny", colW), "Praetor.Tiny", x + pad, iy + S(8), A(C.dim))
	UI.Name(info.by, "Praetor.BodyB", x + pad, vy, A(C.ivory), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, colW)
	local cx = x + pad + colW + S(12)
	UI.Text(UI.Fit(P.L("jail_total"):upper(), "Praetor.Tiny", colW), "Praetor.Tiny", cx, iy + S(8), A(C.dim))
	local total = info.perm and P.L("jail_perm") or P.FormatDuration(math.max(1, math.ceil(info.len / 60)), P.L("jail_perm"))
	UI.Text(UI.Fit(total, "Praetor.BodyB", colW), "Praetor.BodyB", cx, vy, A(C.ivory))

	-- reason
	local ry = iy + infoH
	UI.Text(P.L("jail_reason"):upper(), "Praetor.Tiny", x + pad, ry, A(C.dim))
	for i, l in ipairs(reasonLines) do
		UI.Text(l, "Praetor.Body", x + pad, ry + tinyH + S(2) + (i - 1) * lineH, A(C.text))
	end
end)
