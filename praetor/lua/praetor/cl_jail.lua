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
-- drawn in 3D2D (big fonts, small scale); centred on x = 0, bottom at y = 0
function P.DrawJailSign(ply, info)
	local pad, maxW = 34, 980
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
	surface.SetFont("Praetor.OH.Small")
	local reasonW = math.min(maxW, surface.GetTextSize(info.reason))
	local w = math.max(tagW, nameW, timeW, reasonW) + pad * 2
	local h = pad + 60 + 14 + 70 + 52 + 50 + pad
	local x, y = -w / 2, -h

	UI.Round(x + 10, y + 12, w, h, 26, Color(C.ink.r, C.ink.g, C.ink.b, 200))
	UI.Round(x, y, w, h, 26, Color(C.panel.r, C.panel.g, C.panel.b, 252), C.ink, 6)
	UI.Round(x + 6, y + 6, w - 12, 8, 4, C.crimson)

	-- red pill with the cuffs: PRESO / JAILED
	local cy = y + pad + 30
	UI.Round(-tagW / 2, cy - 30, tagW, 60, 30, C.crimson, C.ink, 4)
	UI.Icon("jail", -tagW / 2 + 22, cy - 24, 48)
	draw.SimpleText(tag, "Praetor.OH.Tag", -tagW / 2 + 22 + 48 + 14, cy, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	cy = cy + 30 + 14 + 35
	UI.Name(name, "Praetor.OH.Name", 0, cy, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, maxW)
	cy = cy + 35 + 26
	draw.SimpleText(time, "Praetor.OH.Rank", 0, cy, info.perm and C.amber or C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cy = cy + 26 + 25
	draw.SimpleText(UI.Fit(info.reason, "Praetor.OH.Small", maxW), "Praetor.OH.Small", 0, cy, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
	if #reasonLines > 2 then
		reasonLines = { reasonLines[1], UI.Fit(table.concat(reasonLines, " ", 2), "Praetor.Body", inner) }
	end
	local headH, barH, infoH = S(36), S(26), S(46)
	local reasonH = S(16) + #reasonLines * S(19)
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
	UI.Text(P.L("jail_by"):upper(), "Praetor.Tiny", x + pad, iy + S(8), A(C.dim))
	UI.Name(info.by, "Praetor.BodyB", x + pad, iy + S(22), A(C.ivory), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, colW)
	local cx = x + pad + colW + S(12)
	UI.Text(P.L("jail_total"):upper(), "Praetor.Tiny", cx, iy + S(8), A(C.dim))
	local total = info.perm and P.L("jail_perm") or P.FormatDuration(math.max(1, math.ceil(info.len / 60)), P.L("jail_perm"))
	UI.Text(UI.Fit(total, "Praetor.BodyB", colW), "Praetor.BodyB", cx, iy + S(22), A(C.ivory))

	-- reason
	local ry = iy + infoH
	UI.Text(P.L("jail_reason"):upper(), "Praetor.Tiny", x + pad, ry + S(2), A(C.dim))
	for i, l in ipairs(reasonLines) do
		UI.Text(l, "Praetor.Body", x + pad, ry + S(16) + (i - 1) * S(19), A(C.text))
	end
end)
