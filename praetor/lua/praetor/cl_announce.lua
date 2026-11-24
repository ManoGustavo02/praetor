-- Praetor: announcements and pop-ups on screen. Four looks: a line in the chat
-- (stays the chosen time), a pop-up card in a corner, a bar at the top and big
-- text in the middle of the screen. The same drawing is used by the preview in
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

-- pop-up card. Returns its height. frac = time left (0-1)
function D.popup(it, x, y, w, a, frac, measureOnly)
	local col = colOf(it)
	local tx = x + S(66)
	local tw = w - S(66) - S(12)
	it._pl = it._pl or {}
	local key = tw .. (it.text or "")
	if it._pl.key ~= key then it._pl = { key = key, lines = UI.Wrap(it.text or "", "Praetor.Small", tw) } end
	local lines = it._pl.lines
	local nl = math.min(#lines, 5)
	local hasTitle = (it.title or "") ~= ""
	local h = S(14) + (hasTitle and S(22) or 0) + nl * S(17) + (it.link and S(22) or 0) + S(14)
	h = math.max(h, S(70))
	if measureOnly then return h end
	UI.Round(x, y, w, h, S(10), Color(15, 16, 21, 242 * a), Color(col.r, col.g, col.b, 150 * a))
	-- soft glow of the colour on the left
	UI.Round(x + 1, y + 1, S(58), h - 2, S(9), Color(col.r, col.g, col.b, 26 * a))
	UI.Round(x + S(10), y + (h - S(44)) / 2, S(44), S(44), S(10), Color(col.r, col.g, col.b, 60 * a), Color(col.r, col.g, col.b, 200 * a))
	UI.Icon(it.icon or "megaphone", x + S(10) + (S(44) - 32) / 2, y + (h - 32) / 2, 32, Color(255, 255, 255, 255 * a))
	local cy = y + S(14)
	if hasTitle then
		UI.Text(UI.Fit(it.title, "Praetor.BodyB", tw), "Praetor.BodyB", tx, cy, Color(light(col, 0.35).r, light(col, 0.35).g, light(col, 0.35).b, 255 * a))
		cy = cy + S(22)
	end
	for i = 1, nl do
		UI.Text(lines[i], "Praetor.Small", tx, cy, Color(226, 228, 235, 255 * a))
		cy = cy + S(17)
	end
	if it.link then
		UI.Icon("send", tx, cy + S(3), 16, Color(255, 255, 255, 200 * a))
		UI.Text(UI.Fit(shortLink(it.link), "Praetor.SmallB", tw - 22), "Praetor.SmallB", tx + 22, cy + S(3), Color(110, 170, 255, 255 * a))
	end
	if frac then
		UI.Round(x + S(10), y + h - S(4), (w - S(20)) * math.Clamp(frac, 0, 1), S(2), S(1), Color(col.r, col.g, col.b, 200 * a))
	end
	return h
end

-- bar at the top of the screen
function D.banner(it, x, y, w, a, frac, measureOnly)
	local col = colOf(it)
	local tw = w - S(110)
	it._bl = it._bl or {}
	local key = tw .. (it.text or "")
	if it._bl.key ~= key then it._bl = { key = key, lines = UI.Wrap(it.text or "", "Praetor.Big", tw) } end
	local lines = it._bl.lines
	local nl = math.min(#lines, 4)
	local hasTitle = (it.title or "") ~= ""
	local h = S(20) + (hasTitle and S(24) or 0) + nl * S(27) + (it.link and S(24) or 0) + S(16)
	h = math.max(h, S(84))
	if measureOnly then return h end
	UI.Round(x, y, w, h, S(10), Color(14, 15, 20, 245 * a), Color(col.r, col.g, col.b, 140 * a))
	UI.Round(x, y, w, S(4), S(2), Color(col.r, col.g, col.b, 255 * a))
	UI.Round(x + S(18), y + (h - S(60)) / 2, S(60), S(60), S(12), Color(col.r, col.g, col.b, 55 * a), Color(col.r, col.g, col.b, 210 * a))
	UI.Icon(it.icon or "megaphone", x + S(18) + (S(60) - 32) / 2, y + (h - 32) / 2, 32, Color(255, 255, 255, 255 * a))
	local tx = x + S(94)
	local cy = y + S(18)
	if hasTitle then
		local lc = light(col, 0.4)
		UI.Text(P.Upper(UI.Fit(it.title, "Praetor.SmallB", tw)), "Praetor.SmallB", tx, cy, Color(lc.r, lc.g, lc.b, 255 * a))
		cy = cy + S(24)
	end
	for i = 1, nl do
		UI.Text(lines[i], "Praetor.Big", tx, cy, Color(240, 241, 246, 255 * a))
		cy = cy + S(27)
	end
	if it.link then
		UI.Icon("send", tx, cy + S(4), 16, Color(255, 255, 255, 200 * a))
		UI.Text(UI.Fit(shortLink(it.link), "Praetor.BodyB", tw - 22), "Praetor.BodyB", tx + 22, cy + S(3), Color(110, 170, 255, 255 * a))
	end
	if it.by then UI.Text("- " .. it.by, "Praetor.Tiny", x + w - S(14), y + h - S(14), Color(140, 145, 158, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
	if frac then UI.Round(x + S(12), y + h - S(4), (w - S(24)) * math.Clamp(frac, 0, 1), S(2), S(1), Color(col.r, col.g, col.b, 160 * a)) end
	return h
end

-- big text in the middle of the screen (w = width of the area)
local gradU = Material("gui/gradient_up")
local gradD = Material("gui/gradient_down")
function D.center(it, x, y, w, a, frac, measureOnly, small)
	local col = colOf(it)
	local titleFont = small and "Praetor.H2" or "Praetor.Logo"
	local textFont = small and "Praetor.Body" or "Praetor.Big"
	local lh = small and S(20) or S(28)
	it._cl = it._cl or {}
	local key = w .. textFont .. (it.text or "")
	if it._cl.key ~= key then it._cl = { key = key, lines = UI.Wrap(it.text or "", textFont, w - S(80)) } end
	local lines = it._cl.lines
	local nl = math.min(#lines, 4)
	local isz = small and 32 or 64
	local hasTitle = (it.title or "") ~= ""
	local h = S(24) + isz + S(12) + (hasTitle and S(40) or 0) + nl * lh + (it.link and S(28) or 0) + S(24)
	if measureOnly then return h end
	-- dark band across the area, fading at the top and bottom
	local band = Color(6, 7, 10, 200 * a)
	surface.SetDrawColor(band)
	surface.DrawRect(x, y + h * 0.2, w, h * 0.6)
	surface.SetMaterial(gradU)
	surface.DrawTexturedRect(x, y, w, h * 0.2)
	surface.SetMaterial(gradD)
	surface.DrawTexturedRect(x, y + h * 0.8, w, h * 0.2)
	local cx = x + w / 2
	local cy = y + S(24)
	UI.Icon(it.icon or "megaphone", cx - isz / 2, cy, isz, Color(255, 255, 255, 255 * a))
	cy = cy + isz + S(12)
	if hasTitle then
		UI.TextShadow(it.title, titleFont, cx, cy + S(16), Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cy = cy + S(40)
	end
	for i = 1, nl do
		UI.TextShadow(lines[i], textFont, cx, cy + lh / 2, Color(240, 241, 246, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cy = cy + lh
	end
	if it.link then UI.TextShadow(shortLink(it.link), small and "Praetor.SmallB" or "Praetor.BodyB", cx, cy + S(14), Color(110, 170, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	if frac then UI.Round(cx - S(80), y + h - S(10), S(160) * math.Clamp(frac, 0, 1), S(3), S(1), Color(col.r, col.g, col.b, 200 * a)) end
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
			D.center(center, 0, ScrH() * 0.42 - h / 2, ScrW(), a, 1 - age / center.life)
		end
	end
end)
