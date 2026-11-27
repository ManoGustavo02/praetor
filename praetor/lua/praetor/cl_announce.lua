-- Praetor: announcements and pop-ups on screen. Four looks: a line in the chat
-- (stays the chosen time, with a band in the announcement colour), a pop-up card
-- in a corner, a bar at the top and a big card in the middle of the screen. The same drawing is used by the preview in
-- the Announcements tab.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local popups = {}
local banner, center

local function colOf(it)
	local c = it.col or {}
	return Color(c.r or 92, c.g or 132, c.b or 255)
end

local function light(c, f)
	return Color(math.min(255, c.r + (255 - c.r) * f), math.min(255, c.g + (255 - c.g) * f), math.min(255, c.b + (255 - c.b) * f))
end

local function shortLink(url)
	url = tostring(url or ""):gsub("^https?://", ""):gsub("^www%.", "")
	if #url > 42 then url = url:sub(1, 40) .. "..." end
	return url
end

-- ------------------------------------------------------------------ drawing

local D = {}
P.AnnDraw = D

local function fontH(f)
	surface.SetFont(f)
	local _, h = surface.GetTextSize("ÁgjM")
	return h
end

local function wrapCached(it, slot, text, font, w)
	it[slot] = it[slot] or {}
	local key = w .. font .. (text or "")
	if it[slot].key ~= key then it[slot] = { key = key, lines = UI.Wrap(text or "", font, w) } end
	return it[slot].lines
end

local function ca(c, a) return Color(c.r, c.g, c.b, a) end

-- time left: a thin track with the coloured part going down, inside the card
local function timeBar(x, y, w, frac, col, a)
	local th = math.max(2, S(4))
	UI.Round(x, y, w, th, th / 2, Color(0, 0, 0, 110 * a))
	if frac then
		local fw = math.floor(w * math.Clamp(frac, 0, 1))
		if fw > 0 then UI.Round(x, y, math.max(th, fw), th, th / 2, ca(col, 230 * a)) end
	end
	return th
end

-- "by Name" in small muted text
local function byLine(it)
	if not it.by or it.by == "" then return nil end
	return P.L("ann_by", { S = it.by })
end

-- pop-up card in a corner. Returns its height. frac = time left (0-1)
-- icon tile | title, text (up to 5 lines), link | time bar at the bottom
function D.popup(it, x, y, w, a, frac, measureOnly)
	local col = colOf(it)
	local pad, tile = S(12), S(42)
	local tx = x + pad + tile + S(12)
	local tw = w - (tx - x) - pad
	local lines = wrapCached(it, "_pl", it.text, "Praetor.Small", tw)
	local nl = math.min(#lines, 5)
	local hasTitle = (it.title or "") ~= ""
	local titleH, lh, linkH = fontH("Praetor.BodyB"), fontH("Praetor.Small"), fontH("Praetor.SmallB")
	local bodyH = (hasTitle and (titleH + S(2)) or 0) + nl * lh + (it.link and (S(4) + linkH) or 0)
	local h = pad + math.max(tile, bodyH) + S(10) + S(4) + pad
	if measureOnly then return h end
	UI.Round(x + S(4), y + S(4), w, h, S(12), ca(C.ink, 190 * a))
	UI.Round(x, y, w, h, S(12), ca(C.panel, 242 * a), ca(col, 170 * a))
	local ty = y + pad
	local iy = ty + math.floor((math.max(tile, bodyH) - tile) / 2)
	UI.Round(x + pad, iy, tile, tile, S(10), ca(col, 70 * a), ca(col, 220 * a))
	UI.Icon(it.icon or "megaphone", x + pad + (tile - 28) / 2, iy + (tile - 28) / 2, 28, Color(255, 255, 255, 255 * a))
	local cy = ty + math.floor((math.max(tile, bodyH) - bodyH) / 2)
	if hasTitle then
		UI.Text(UI.Fit(it.title, "Praetor.BodyB", tw), "Praetor.BodyB", tx, cy, ca(light(col, 0.4), 255 * a))
		cy = cy + titleH + S(2)
	end
	for i = 1, nl do
		UI.Text(lines[i], "Praetor.Small", tx, cy, ca(C.ivory, 255 * a))
		cy = cy + lh
	end
	if it.link then
		cy = cy + S(4)
		UI.Icon("send", tx, cy + (linkH - 14) / 2, 14, Color(255, 255, 255, 200 * a))
		UI.Text(UI.Fit(shortLink(it.link), "Praetor.SmallB", tw - S(20)), "Praetor.SmallB", tx + S(20), cy, Color(110, 170, 255, 255 * a))
	end
	timeBar(x + pad, y + h - pad - S(4), w - pad * 2, frac, col, a)
	return h
end

-- bar at the top of the screen
-- icon tile | TITLE ............ by Name | text (up to 4 lines) | link | time bar
function D.banner(it, x, y, w, a, frac, measureOnly)
	local col = colOf(it)
	local pad, tile = S(16), S(56)
	local tx = x + pad + tile + S(16)
	local tw = w - (tx - x) - pad
	local lines = wrapCached(it, "_bl", it.text, "Praetor.Big", tw)
	local nl = math.min(#lines, 4)
	local hasTitle = (it.title or "") ~= ""
	local by = byLine(it)
	local headH, lh, linkH = fontH("Praetor.SmallB"), fontH("Praetor.Big"), fontH("Praetor.BodyB")
	local hasHead = hasTitle or by ~= nil
	local bodyH = (hasHead and (headH + S(4)) or 0) + nl * lh + (it.link and (S(6) + linkH) or 0)
	local inner = math.max(tile, bodyH)
	local h = pad + inner + S(12) + S(4) + pad
	if measureOnly then return h end
	UI.Round(x + S(5), y + S(5), w, h, S(14), ca(C.ink, 200 * a))
	UI.Round(x, y, w, h, S(14), ca(C.panel, 245 * a), ca(col, 190 * a))
	local iy = y + pad + math.floor((inner - tile) / 2)
	UI.Round(x + pad, iy, tile, tile, S(12), ca(col, 70 * a), ca(col, 230 * a))
	UI.Icon(it.icon or "megaphone", x + pad + (tile - 32) / 2, iy + (tile - 32) / 2, 32, Color(255, 255, 255, 255 * a))
	local cy = y + pad + math.floor((inner - bodyH) / 2)
	if hasHead then
		local byW = 0
		if by then
			surface.SetFont("Praetor.Tiny")
			byW = surface.GetTextSize(by)
			UI.Text(by, "Praetor.Tiny", x + w - pad, cy + headH / 2, ca(C.muted, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		if hasTitle then
			UI.Text(P.Upper(UI.Fit(it.title, "Praetor.SmallB", tw - byW - S(16))), "Praetor.SmallB", tx, cy, ca(light(col, 0.45), 255 * a))
		end
		cy = cy + headH + S(4)
	end
	for i = 1, nl do
		UI.Text(lines[i], "Praetor.Big", tx, cy, ca(C.ivory, 255 * a))
		cy = cy + lh
	end
	if it.link then
		cy = cy + S(6)
		UI.Icon("send", tx, cy + (linkH - 16) / 2, 16, Color(255, 255, 255, 200 * a))
		UI.Text(UI.Fit(shortLink(it.link), "Praetor.BodyB", tw - S(22)), "Praetor.BodyB", tx + S(22), cy, Color(110, 170, 255, 255 * a))
	end
	timeBar(tx, y + h - pad - S(4), x + w - pad - tx, frac, col, a)
	return h
end

-- big announcement in the middle of the screen (w = width of the area).
-- A centred card: the icon on a medal half out of the top, the title, a short
-- line in the colour, the text, the link and who sent it, and the time left as a
-- bar at the bottom of the card. Nothing crosses the whole screen.
function D.center(it, x, y, w, a, frac, measureOnly, small)
	local col = colOf(it)
	local titleFont = small and "Praetor.H2" or "Praetor.Logo"
	local textFont = small and "Praetor.Body" or "Praetor.Big"
	local pad = small and S(16) or S(26)
	local maxText = math.min(w - S(80) - pad * 2, small and S(420) or S(640))
	local lines = wrapCached(it, "_cl", it.text, textFont, maxText)
	local nl = math.min(#lines, 5)
	local hasTitle = (it.title or "") ~= ""
	local by = byLine(it)
	local titleH, lh, linkH, byH = fontH(titleFont), fontH(textFont), fontH("Praetor.SmallB"), fontH("Praetor.Tiny")
	-- width from the content, between a minimum and the max
	local cw = small and S(240) or S(380)
	surface.SetFont(textFont)
	for i = 1, nl do cw = math.max(cw, surface.GetTextSize(lines[i]) + pad * 2) end
	if hasTitle then
		surface.SetFont(titleFont)
		cw = math.max(cw, math.min(surface.GetTextSize(it.title), maxText) + pad * 2)
	end
	cw = math.min(cw, maxText + pad * 2)
	local medal = small and S(46) or S(72)
	local ch = medal / 2 + S(10) + (hasTitle and (titleH + S(8) + S(3) + S(10)) or 0) + nl * lh
		+ (it.link and (S(8) + linkH) or 0) + (by and (S(8) + byH) or 0) + S(16) + S(4) + pad
	local h = medal / 2 + ch
	if measureOnly then return h end
	local cx = x + w / 2
	local x0, y0 = math.floor(cx - cw / 2), y + medal / 2
	UI.Round(x0 + S(6), y0 + S(6), cw, ch, S(18), ca(C.ink, 190 * a))
	UI.Round(x0, y0, cw, ch, S(18), ca(C.panel, 240 * a), ca(col, 200 * a))
	-- medal with the icon, half out of the top edge
	local mx, my = math.floor(cx - medal / 2), y
	UI.Round(mx - S(4), my - S(4), medal + S(8), medal + S(8), (medal + S(8)) / 2, ca(C.ink, 235 * a))
	UI.Round(mx, my, medal, medal, medal / 2, ca(col, 255 * a))
	local isz = small and 28 or 44
	UI.Icon(it.icon or "megaphone", cx - isz / 2, my + (medal - isz) / 2, isz, Color(255, 255, 255, 255 * a))
	local cy = y0 + medal / 2 + S(10)
	if hasTitle then
		UI.TextShadow(UI.Fit(it.title, titleFont, cw - pad * 2), titleFont, cx, cy, ca(light(col, 0.3), 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		cy = cy + titleH + S(8)
		UI.Round(cx - S(26), cy, S(52), S(3), S(1), ca(col, 230 * a))
		cy = cy + S(3) + S(10)
	end
	for i = 1, nl do
		UI.TextShadow(lines[i], textFont, cx, cy, ca(C.ivory, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		cy = cy + lh
	end
	if it.link then
		cy = cy + S(8)
		UI.TextShadow(UI.Fit(shortLink(it.link), "Praetor.SmallB", cw - pad * 2), "Praetor.SmallB", cx, cy, Color(110, 170, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		cy = cy + linkH
	end
	if by then
		cy = cy + S(8)
		UI.Text(UI.Fit(by, "Praetor.Tiny", cw - pad * 2), "Praetor.Tiny", cx, cy, ca(C.muted, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
	timeBar(x0 + pad, y0 + ch - pad - S(4), cw - pad * 2, frac, col, a)
	return h
end

-- the chat line (the line stays on screen for it.life seconds)
function D.chat(it)
	local col = colOf(it)
	local parts = { col, "| " }
	if (it.title or "") ~= "" then
		parts[#parts + 1] = light(col, 0.3)
		parts[#parts + 1] = it.title .. "  "
	end
	parts[#parts + 1] = Color(236, 238, 244)
	parts[#parts + 1] = it.text or ""
	if it.link then
		parts[#parts + 1] = Color(110, 170, 255)
		parts[#parts + 1] = "  " .. it.link
	end
	chat.AddText(unpack(parts))
	local CB = P.ChatBox
	local l = CB and CB.lines and CB.lines[#CB.lines]
	-- only the line this call just added (the Praetor chat box may be off)
	if l and l.t == RealTime() and l.plain and l.plain:find(it.text or "", 1, true) then
		l.life = math.max(it.life or 12, 4)
		l.annIcon = it.icon
		l.annCol = col
		l.ann = true
	end
end

-- ------------------------------------------------------------------ showing

function P.ShowAnn(it)
	it = table.Copy(it)
	it.t = RealTime()
	it.life = math.Clamp(tonumber(it.life) or 10, 3, 60)
	if it.snd then UI.Sound("notify") end
	if it.where == "chat" then D.chat(it) return end
	-- the link also goes to the chat, where it can be clicked
	if it.link then
		local col = colOf(it)
		chat.AddText(col, "| ", light(col, 0.3), ((it.title or "") ~= "" and it.title or P.L("announcement")) .. "  ", Color(110, 170, 255), it.link)
	end
	if it.where == "banner" then banner = it
	elseif it.where == "center" then center = it
	else
		table.insert(popups, 1, it)
		while #popups > 4 do table.remove(popups) end
	end
end

P.On("ann_show", function(d) P.ShowAnn(d) end)

local function fade(it, now)
	local age = now - it.t
	return math.Clamp(math.min(age * 4, (it.life - age) * 2), 0, 1), age
end

hook.Add("HUDPaint", "Praetor.Announcements", function()
	local now = RealTime()
	-- corner pop-ups, grouped by corner
	if #popups > 0 then
		for i = #popups, 1, -1 do
			if now - popups[i].t > popups[i].life then table.remove(popups, i) end
		end
		local w = math.min(S(360), ScrW() * 0.36)
		local stackY = { tr = S(16), tl = S(16), br = ScrH() - S(150), bl = ScrH() - S(230) }
		for _, it in ipairs(popups) do
			local corner = it.corner or "br"
			local right = corner == "tr" or corner == "br"
			local bottom = corner == "br" or corner == "bl"
			local a, age = fade(it, now)
			local h = D.popup(it, 0, 0, w, a, nil, true)
			local slide = (1 - math.min(1, age * 4)) * (w + S(30))
			local x = right and (ScrW() - w - S(16) + slide) or (S(16) - slide)
			-- toasts use the top right corner: start below them
			local y
			if bottom then
				y = stackY[corner] - h
				stackY[corner] = y - S(8)
			else
				y = stackY[corner]
				stackY[corner] = y + h + S(8)
			end
			D.popup(it, x, y, w, a, 1 - age / it.life)
		end
	end
	if banner then
		local a, age = fade(banner, now)
		if age > banner.life then banner = nil else
			local w = math.min(ScrW() - S(40), S(820))
			local y = S(70) - (1 - math.min(1, age * 3)) * S(40)
			D.banner(banner, (ScrW() - w) / 2, y, w, a, 1 - age / banner.life)
		end
	end
	if center then
		local a, age = fade(center, now)
		if age > center.life then center = nil else
			local h = D.center(center, 0, 0, ScrW(), a, nil, true)
			local pop = UI.EaseBack(math.min(1, age * 3.2))
			D.center(center, 0, ScrH() * 0.36 - h / 2 + math.floor((1 - pop) * S(30)), ScrW(), a, 1 - age / center.life)
		end
	end
end)
