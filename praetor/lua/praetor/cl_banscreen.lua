-- Praetor: the ban screen and the ban lines in the chat.
--  * full screen card: avatar, reason, who banned, when, time left (live),
--    ban code with a copy button, the Discord link from the settings and a
--    bar until the kick;
--  * chat: "X was banned by Y for Z. Reason: ..." and "X tried to join but is
--    banned (reason, time left)".
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local RED = Color(255, 84, 104)
local screen

local function fmtLeft(secs)
	secs = math.max(0, math.floor(secs))
	local d = math.floor(secs / 86400)
	local h = math.floor(secs % 86400 / 3600)
	local m = math.floor(secs % 3600 / 60)
	local s = secs % 60
	if d > 0 then return string.format("%dd %02dh %02dm", d, h, m) end
	if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
	return string.format("%02dm %02ds", m, s)
end

local function closeScreen()
	if IsValid(screen) then screen:Remove() end
	screen = nil
end

local function openScreen(d)
	closeScreen()
	local lp = LocalPlayer()
	local offset = (tonumber(d.now) or os.time()) - os.time() -- server clock vs this computer
	local opened = RealTime()
	local secs = tonumber(d.secs) or 30

	local f = vgui.Create("EditablePanel")
	screen = f
	f:SetSize(ScrW(), ScrH())
	f:SetPos(0, 0)
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	f:SetZPos(32000)
	UI.Sound("error")

	local cw = math.min(S(620), ScrW() - S(40))
	local hasLink = isstring(d.d) and d.d ~= ""
	local ch = S(hasLink and 470 or 400)
	local card = vgui.Create("DPanel", f)
	card:SetSize(cw + S(6), ch + S(6))
	card:Center()
	card:DockPadding(S(24), S(196), S(24) + S(6), S(20) + S(6))
	-- the card drops in like a stamp
	UI.PopIn(card, 0.42)

	local rows = {
		{ "bs_reason", (d.r and d.r ~= "") and d.r or P.L("bs_no_reason") },
		{ "bs_by", d.a or "Console" },
		{ "bs_when", d.c and d.c > 0 and os.date("%d/%m/%Y %H:%M", d.c) or "-" },
	}

	card.Paint = function(_, w, h)
		local t = RealTime() - opened
		local a = math.min(1, t * 4)
		-- shadow + card
		local off = S(6)
		w, h = w - off, h - off
		UI.Round(off, off, w, h, S(18), Color(C.ink.r, C.ink.g, C.ink.b, 220 * a))
		UI.Round(0, 0, w, h, S(18), Color(C.panel.r, C.panel.g, C.panel.b, 250 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
		-- top band
		local bw = UI.BW()
		draw.RoundedBoxEx(S(16), bw, bw, w - bw * 2, S(64) - bw, Color(RED.r, RED.g, RED.b, 255 * a), true, true, false, false)
		UI.Rect(bw, S(64), w - bw * 2, bw, Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
		for x = -S(64), w, S(18) do
			surface.SetDrawColor(255, 255, 255, 10 * a)
			surface.DrawLine(x, S(64), x + S(64), 0)
		end
		UI.IconRot("lock", S(18), S(32) - 14, 28, math.sin(t * 6) * math.max(0, 1 - t) * 20, Color(255, 255, 255, 255 * a))
		draw.SimpleText(P.Upper(P.L("bs_title")), "Praetor.H1", S(54) + S(3), S(32) + S(3), Color(C.ink.r, C.ink.g, C.ink.b, 230 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.Upper(P.L("bs_title")), "Praetor.H1", S(54), S(32), Color(255, 255, 255, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(UI.Fit(d.host or "", "Praetor.Small", w * 0.45), "Praetor.Small", w - S(22), S(32), Color(255, 255, 255, 190 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		-- who
		local av = S(64)
		UI.DrawAvatar(d.sid, lp, S(24), S(84), av, 255 * a, RED)
		local nx = S(24) + av + S(18)
		UI.Text(UI.Fit(IsValid(lp) and lp:Nick() or (d.n or ""), "Praetor.Big", w - nx - S(24)), "Praetor.Big", nx, S(100), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(util.SteamIDFrom64(d.sid or "0") or "", "Praetor.Small", nx, S(124), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- time left
		local e = tonumber(d.e) or 0
		local left
		if e == 0 then left = P.L("bs_perm") else left = fmtLeft(e - (os.time() + offset)) end
		UI.Text(P.Upper(P.L("bs_left")), "Praetor.Tiny", w - S(24), S(94), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		UI.Text(left, "Praetor.BodyB", w - S(24), S(116), Color(RED.r, RED.g, RED.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		-- details
		local y = S(162)
		UI.Rect(S(24), y - S(10), w - S(48), 1, Color(255, 255, 255, 18 * a))
		for _, r in ipairs(rows) do
			UI.Text(P.L(r[1]), "Praetor.Small", S(24), y, Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			local lines = UI.Wrap(tostring(r[2]), "Praetor.SmallB", w - S(200))
			for i, l in ipairs(lines) do
				if i > 2 then break end
				UI.Text(l, "Praetor.SmallB", S(160), y + (i - 1) * S(18), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
			y = y + S(math.min(#lines, 2) > 1 and 42 or 26)
		end

		-- kick bar
		local frac = math.Clamp(1 - t / secs, 0, 1)
		UI.Round(S(24), h - S(16), w - S(48), S(8), S(4), Color(C.bg.r, C.bg.g, C.bg.b, 255 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
		UI.Round(S(26), h - S(14), (w - S(52)) * frac, S(4), S(2), Color(RED.r, RED.g, RED.b, 255 * a))
	end

	-- footer: code, link, leave
	local foot = vgui.Create("DPanel", card)
	foot:Dock(BOTTOM)
	foot:SetTall(S(hasLink and 126 or 40))
	foot:DockMargin(0, 0, 0, S(8))
	foot.Paint = function(_, w, h)
		if hasLink then
			local ap = (isstring(d.ap) and d.ap ~= "") and d.ap or P.L("bs_appeal_default")
			local lines = UI.Wrap(ap, "Praetor.Small", w)
			for i, l in ipairs(lines) do
				if i > 2 then break end
				UI.Text(l, "Praetor.Small", 0, (i - 1) * S(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		end
		local left = math.max(0, math.ceil(secs - (RealTime() - opened)))
		UI.Text(P.L("bs_kick_in", { V = left }), "Praetor.Tiny", w, h - S(16), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local btns = vgui.Create("DPanel", foot)
	btns:Dock(BOTTOM)
	btns:SetTall(S(32))
	btns.Paint = nil
	local leave = UI.Button(btns, P.L("bs_leave"), "danger", "door", function() RunConsoleCommand("disconnect") end)
	leave:Dock(LEFT)
	leave:SetWide(S(150))
	if d.id then
		local code = UI.Button(btns, P.L("bs_code", { V = d.id }), "subtle", "copy", function()
			SetClipboardText("#" .. tostring(d.id))
			P.Toast(P.L("bs_title"), P.L("bs_copied"), "ok", 3)
		end)
		code:Dock(LEFT)
		code:SetWide(S(170))
		code:DockMargin(S(8), 0, 0, 0)
		code:SetTooltip(P.L("bs_code_tip"))
	end

	if hasLink then
		local linkRow = vgui.Create("DPanel", foot)
		linkRow:Dock(BOTTOM)
		linkRow:SetTall(S(40))
		linkRow:DockMargin(0, 0, 0, S(8))
		linkRow.Paint = nil
		local copy = UI.Button(linkRow, P.L("bs_copy_link"), "ghost", "copy", function()
			SetClipboardText(d.d)
			P.Toast(P.L("bs_title"), P.L("bs_copied"), "ok", 3)
		end)
		copy:Dock(RIGHT)
		copy:SetWide(S(150))
		copy:DockMargin(S(8), 0, 0, 0)
		local open = UI.Button(linkRow, P.L("bs_open_link"), "primary", "send", function() gui.OpenURL(d.d) end)
		open:Dock(FILL)
		open:SetTooltip(d.d)
	end

	f.Paint = function(s, w, h)
		local a = math.min(1, (RealTime() - opened) * 3)
		Derma_DrawBackgroundBlur(s, opened - 1)
		surface.SetDrawColor(8, 6, 16, 235 * a)
		surface.DrawRect(0, 0, w, h)
		-- red glow behind the card
		local cx, cy = w / 2, h / 2
		for i = 1, 6 do
			local r = cw * 0.5 + i * S(26)
			UI.Round(cx - r, cy - r * 0.8, r * 2, r * 1.6, r * 0.8, Color(RED.r, RED.g, RED.b, (7 - i) * 2.2 * a))
		end
	end
	f.OnKeyCodePressed = function() end
end

-- tells the server this game finished loading (a banned player gets the screen then)
hook.Add("InitPostEntity", "Praetor.BanScreen", function()
	timer.Simple(1, function()
		net.Start("praetor_bsready")
		net.SendToServer()
	end)
end)

P.On("ban_screen", function(d)
	if d.off then closeScreen() return end
	openScreen(d)
end)

-- nothing else on screen while the ban card is up
hook.Add("HUDShouldDraw", "Praetor.BanScreen", function(name)
	if IsValid(screen) and name ~= "CHudGMod" then return false end
end)
hook.Add("PlayerBindPress", "Praetor.BanScreen", function()
	if IsValid(screen) then return true end
end)

-- ------------------------------------------------------------------ chat lines

local function timeText(m)
	m = tonumber(m) or 0
	if m <= 0 then return P.L("bs_perm_short") end
	return P.FormatDuration and P.FormatDuration(m) or (m .. " min")
end

P.On("ban_news", function(d)
	local out = { RED, "[BAN] " }
	if d.s then out[#out + 1] = C.dim out[#out + 1] = "(" .. P.L("silent") .. ") " end
	local key = (tonumber(d.m) or 0) <= 0 and "bn_line_perm" or "bn_line"
	for _, p in ipairs(P.TemplateParts(P.L(key), { T = { n = d.n, sid = d.sid }, A = { n = d.a }, V = timeText(d.m) })) do out[#out + 1] = p end
	if d.r then
		out[#out + 1] = C.muted
		out[#out + 1] = "  " .. P.L("bn_reason") .. " "
		out[#out + 1] = C.ivory
		out[#out + 1] = d.r
	end
	chat.AddText(unpack(out))
end)

P.On("ban_try", function(d)
	local out = { RED, "[BAN] " }
	for _, p in ipairs(P.TemplateParts(P.L("bt_line"), { T = { n = d.n }, V = timeText(d.left) })) do out[#out + 1] = p end
	if d.r then
		out[#out + 1] = C.muted
		out[#out + 1] = "  " .. P.L("bn_reason") .. " "
		out[#out + 1] = C.ivory
		out[#out + 1] = d.r
	end
	if d.a then
		out[#out + 1] = C.muted
		out[#out + 1] = "  (" .. P.L("bt_by", { S = d.a }) .. ")"
	end
	chat.AddText(unpack(out))
end)
