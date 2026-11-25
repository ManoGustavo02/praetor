-- Praetor: votes on screen. A card on the left for polls (live bars, vote with
-- 1-9 or a click) and a full screen map vote with the pictures of the maps, the
-- "keep this map" card and who voted on each. A vote is final: the window
-- closes into a small bar with the time left and the result comes back at the end.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local KEEP = "__keep"
local V -- the vote on screen
local card, overlay
local changing -- { map, at } after a map vote

-- ------------------------------------------------------------------ maps

local thumbs = {}
-- map -> Workshop id: sent by the server (its mounted addons) and filled with
-- the addons this client has mounted itself
P.MapWorkshop = P.MapWorkshop or {}
local clientScanned = false
local function scanClientAddons()
	clientScanned = true
	local ok, addons = pcall(engine.GetAddons)
	for _, a in ipairs(ok and istable(addons) and addons or {}) do
		local id = tostring(a.wsid or "")
		if a.mounted and id:match("^%d+$") and id ~= "0" and isstring(a.title) then
			local fok, found = pcall(file.Find, "maps/*.bsp", a.title)
			for _, f in ipairs(fok and istable(found) and found or {}) do
				local m = f:lower():gsub("%.bsp$", "")
				if not P.MapWorkshop[m] then P.MapWorkshop[m] = id end
			end
		end
	end
end

P.On("map_ws", function(d)
	if not istable(d.m) then return end
	for m, id in pairs(d.m) do
		if isstring(m) and isstring(id) and id:match("^%d+$") then P.MapWorkshop[m:lower()] = id end
	end
	-- maps that had no picture get another chance with the Workshop one
	for m, v in pairs(thumbs) do if v == false then thumbs[m] = nil end end
end)

hook.Add("InitPostEntity", "Praetor.MapWS", function()
	timer.Simple(3, function() P.Request("map_ws") end)
end)

-- A picture inside the game files (maps/thumb/*.png of the base maps sits in
-- the game's .vpk, where Material("../maps/...") does not find it): it is
-- copied once to data/praetor_maps and loaded from there.
local function viaData(path, m)
	local data = file.Read(path, "GAME")
	if not data or #data < 16 then return nil end
	file.CreateDir("praetor_maps")
	local ext = path:match("%.(%a+)$") or "png"
	local out = "praetor_maps/" .. m:gsub("[^%w_%-]", "_") .. "." .. ext
	if not file.Exists(out, "DATA") or file.Size(out, "DATA") ~= #data then file.Write(out, data) end
	local mat = Material("../data/" .. out, "smooth")
	if mat and not mat:IsError() then return mat end
end

local function localThumb(m)
	if file.Exists("materials/maps/thumb/" .. m .. ".png", "GAME") then
		local mat = Material("maps/thumb/" .. m .. ".png", "smooth")
		if mat and not mat:IsError() then return mat end
	end
	for _, path in ipairs({ "maps/thumb/" .. m .. ".png", "maps/" .. m .. ".png", "maps/thumb/" .. m .. ".jpg" }) do
		if file.Exists(path, "GAME") then
			local mat = viaData(path, m)
			if mat then return mat end
		end
	end
	return nil
end

-- picture of a map: the game thumbnail, else the Workshop picture of the
-- addon the map comes from (downloaded once, then cached), or nil
function P.MapThumb(m)
	if not m or m == "" then return nil end
	m = tostring(m):lower()
	local t = thumbs[m]
	if t then return t end
	if t == nil then
		t = localThumb(m)
		thumbs[m] = t or false
		if t then return t end
	end
	if not clientScanned then scanClientAddons() end
	local id = P.MapWorkshop[m]
	if id and P.WorkshopInfo then
		local e = P.WorkshopInfo(id)
		if e.mat then thumbs[m] = e.mat return e.mat end
	end
	return nil
end

-- "rp_downtown_v4c" -> "Downtown V4c", "RP"
local PREFIX = { gm = "GM", rp = "RP", ttt = "TTT", de = "CS", cs = "CS", zs = "ZS", dm = "DM", ph = "PH", mu = "MU", jb = "JB", ba = "JB", bhop = "BHOP", surf = "SURF", kz = "KZ", deathrun = "DR", dr = "DR", sb = "SB", cw = "CW" }
function P.MapPretty(m)
	m = tostring(m or "")
	local pre, rest = m:match("^([%a]+)_(.+)$")
	local tag
	if pre and PREFIX[pre:lower()] then tag = PREFIX[pre:lower()] m = rest end
	local words = {}
	for w in m:gmatch("[^_%-]+") do words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2) end
	return table.concat(words, " "), tag
end

local gradUp = Material("gui/gradient_up")
local function hashCol(m)
	local h = 0
	for i = 1, #m do h = (h * 31 + m:byte(i)) % 360 end
	return HSVToColor(h, 0.45, 0.42)
end

-- the picture part of a map card (cover fit), or a coloured card with the map icon
function P.DrawMapPicture(m, x, y, w, h, alpha)
	alpha = alpha or 255
	local mat = P.MapThumb(m)
	if mat then
		surface.SetMaterial(mat)
		surface.SetDrawColor(255, 255, 255, alpha)
		if w >= h then
			local cut = (1 - h / w) / 2
			surface.DrawTexturedRectUV(x, y, w, h, 0, cut, 1, 1 - cut)
		else
			local cut = (1 - w / h) / 2
			surface.DrawTexturedRectUV(x, y, w, h, cut, 0, 1 - cut, 1)
		end
	else
		local col = hashCol(m)
		surface.SetDrawColor(col.r * 0.55, col.g * 0.55, col.b * 0.55, alpha)
		surface.DrawRect(x, y, w, h)
		surface.SetMaterial(gradUp)
		surface.SetDrawColor(col.r, col.g, col.b, alpha * 0.8)
		surface.DrawTexturedRect(x, y, w, h)
		local isz = h > S(90) and 32 or 16
		UI.Icon("map", x + (w - isz) / 2, y + (h - isz) / 2 - S(8), isz, Color(255, 255, 255, alpha * 0.85))
		local name = P.MapPretty(m)
		UI.Text(UI.Fit(name:upper(), "Praetor.Tiny", w - S(12)), "Praetor.Tiny", x + w / 2, y + h / 2 + S(18), Color(255, 255, 255, alpha * 0.6), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	-- dark fade at the bottom for the name
	surface.SetMaterial(gradUp)
	surface.SetDrawColor(0, 0, 0, alpha * 0.85)
	surface.DrawTexturedRect(x, y + h * 0.45, w, h * 0.55)
end

-- ------------------------------------------------------------------ helpers

local function optLabel(v, i)
	if v.yn then return P.L(i == 1 and "yes" or "no") end
	local o = v.o[i]
	if v.kind == "map" then
		if o == KEEP then return P.L("mv_keep") end
		return (P.MapPretty(o))
	end
	return tostring(o)
end
P.VoteOptionLabel = optLabel

local function total(c)
	local n = 0
	for _, x in ipairs(c or {}) do n = n + x end
	return n
end

local function leader(c)
	local best, bi = 0, nil
	for i, x in ipairs(c or {}) do if x > best then best, bi = x, i end end
	return bi
end

local function timeLeft()
	if not V then return 0 end
	return math.max(0, V.ends - RealTime())
end

-- the player being voted on (!votekick...) does not vote
local function amTarget()
	return V and V.act and V.act.t and IsValid(LocalPlayer()) and V.act.t == LocalPlayer():SteamID64()
end

local closeOverlay
local function sendVote(i)
	if not V or V.done or not V.o[i] or V.my or amTarget() then return end
	V.my = i
	V.myAt = RealTime()
	P.Request("vote_answer", { id = V.id, i = i })
	UI.Sound("ok")
	-- the window closes; the result shows up again when the vote ends
	if closeOverlay then closeOverlay() end
end

-- title of the vote ("Kick Bob? (reason)" for player votes)
local function titleOf(v)
	if v.kind == "map" then return P.L("mv_title") end
	if v.act then
		local t = P.L("pv_q_" .. tostring(v.act.a), { S = v.act.n or "?" })
		if v.act.r then t = t .. "  (" .. v.act.r .. ")" end
		return t
	end
	return tostring(v.q or "")
end
P.VoteTitle = titleOf

local function voterAvatars(list, x, y, size, maxN)
	local n = 0
	for _, sid in ipairs(list or {}) do
		if n >= maxN then break end
		local ply = player.GetBySteamID64 and player.GetBySteamID64(sid) or nil
		UI.DrawAvatar(sid:match("^%d+$") and sid or nil, IsValid(ply) and ply or nil, x - n * (size - S(4)), y, size, 255, C.panel)
		n = n + 1
	end
	return n
end

-- ------------------------------------------------------------------ poll card (left)

local ROW = 38

local function cardLayout(w)
	local lines = UI.Wrap(titleOf(V), "Praetor.H3", w - S(28))
	local h = S(46) + #lines * S(22) + S(8) + #V.o * S(ROW + 4) + S(34)
	return lines, h
end

-- staff can cancel the running vote from the card itself
local function canCancel()
	return P.MyHas("stopvote") or P.MyHas("vote") or P.MyHas("mapvote")
end

local function drawX(self, x, y, sz, a)
	local hov = self.xHover
	UI.Round(x, y, sz, sz, sz / 2, Color(C.crimson.r, C.crimson.g, C.crimson.b, (hov and 90 or 35) * a), Color(C.crimsonL.r, C.crimsonL.g, C.crimsonL.b, (hov and 255 or 140) * a))
	draw.NoTexture()
	surface.SetDrawColor(255, 255, 255, 230 * a)
	surface.DrawTexturedRectRotated(x + sz / 2, y + sz / 2, sz * 0.5, 2, 45)
	surface.DrawTexturedRectRotated(x + sz / 2, y + sz / 2, sz * 0.5, 2, -45)
	self.xRect = { x, y, x + sz, y + sz }
end

-- after voting: a small bar with the choice and the time left
local function paintMini(self, w, h)
	local a = self.alpha or 1
	local col = C.laurel
	UI.Round(S(3), S(3), w - S(3), h - S(3), (h - S(3)) / 2, Color(C.ink.r, C.ink.g, C.ink.b, 200 * a))
	UI.Round(0, 0, w - S(3), h - S(3), (h - S(3)) / 2, Color(C.panel.r, C.panel.g, C.panel.b, 245 * a), Color(col.r, col.g, col.b, 255 * a))
	local frac = math.Clamp(timeLeft() / math.max(1, V.dur), 0, 1)
	UI.Round(h / 2, h - S(3), (w - h) * frac, S(2), S(1), Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, 220 * a))
	UI.Round(S(6), S(6), h - S(12), h - S(12), (h - S(12)) / 2, Color(col.r, col.g, col.b, 40 * a))
	UI.Icon(amTarget() and "eye" or "check", S(6) + (h - S(12)) / 2 - 8, h / 2 - 8, 16, Color(255, 255, 255, 255 * a))
	local txt = amTarget() and P.L("vote_about_you") or P.L("vote_done_mine", { S = optLabel(V, V.my) })
	local t = math.ceil(timeLeft()) .. "s"
	local xw = 0
	self.xRect = nil
	if canCancel() then
		xw = S(26)
		drawX(self, w - S(30), (h - S(22)) / 2, S(22), a)
	end
	UI.Text(UI.Fit(txt, "Praetor.SmallB", w - h - S(56) - xw), "Praetor.SmallB", h + S(2), h / 2 - S(1), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(t, "Praetor.SmallB", w - S(14) - xw, h / 2 - S(1), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

local function paintCard(self, w, h)
	if not V then return end
	if self.mini then return paintMini(self, w, h) end
	local a = self.alpha or 1
	local lines = self.lines
	UI.Round(S(5), S(5), w - S(5), h - S(5), S(16), Color(C.ink.r, C.ink.g, C.ink.b, 200 * a))
	UI.Round(0, 0, w - S(5), h - S(5), S(16), Color(C.panel.r, C.panel.g, C.panel.b, 246 * a), Color(C.lineL.r, C.lineL.g, C.lineL.b, 255 * a))
	-- time bar
	local frac = V.done and 0 or math.Clamp(timeLeft() / math.max(1, V.dur), 0, 1)
	UI.Round(S(14), S(3), (w - S(33)) * frac, S(4), S(2), Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, 255 * a))
	-- header
	UI.Icon(V.kind == "map" and "map" or "ballot", S(14), S(13), 16, Color(255, 255, 255, 255 * a))
	local head = V.done and P.L("vote_result_t") or P.L(V.kind == "map" and "mv_short" or "vote_title")
	UI.Text(P.Upper(head), "Praetor.SmallB", S(38), S(21), Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if not V.done then
		local t = math.ceil(timeLeft()) .. "s"
		surface.SetFont("Praetor.SmallB")
		local tw = surface.GetTextSize(t) + S(34)
		local urgent = timeLeft() < 6
		local pc = urgent and C.crimsonL or C.lineL
		UI.Round(w - tw - S(12), S(9), tw, S(24), S(12), Color(pc.r, pc.g, pc.b, 40 * a), Color(pc.r, pc.g, pc.b, 160 * a))
		UI.Icon("clock", w - tw - S(12) + S(6), S(9) + (S(24) - 16) / 2, 16, Color(255, 255, 255, 255 * a))
		UI.Text(t, "Praetor.SmallB", w - S(12) - S(10), S(21), Color(255, 255, 255, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		self.xRect = nil
		if canCancel() then drawX(self, w - tw - S(12) - S(30), S(9), S(24), a) end
	else
		self.xRect = nil
	end
	local y = S(40)
	for _, l in ipairs(lines) do
		UI.Text(l, "Praetor.H3", S(14), y, Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a))
		y = y + S(22)
	end
	y = y + S(8)
	local tot = total(V.c)
	local lead = leader(V.c)
	local win = V.done and V.done.w
	self.rows = {}
	for i = 1, #V.o do
		local rx, rw, rh = S(10), w - S(20), S(ROW)
		self.rows[i] = { y, y + rh }
		local n = V.c[i] or 0
		local pct = tot > 0 and n / tot or 0
		V.anim = V.anim or {}
		V.anim[i] = UI.Lerp(V.anim[i] or 0, pct, 8)
		local mine = V.my == i
		local hov = not V.done and self.hover == i
		local isWin = win == i
		local base = isWin and C.bronze or (mine and C.laurel or C.lineL)
		local bg = hov and C.hover or C.panel2
		UI.Round(rx, y, rw, rh, S(12), Color(bg.r, bg.g, bg.b, 255 * a), Color(base.r, base.g, base.b, (mine or isWin) and 255 * a or 150 * a))
		-- bar
		local fillCol = isWin and C.bronze or (mine and C.laurel or (i == lead and C.bronzeD or C.lineL))
		if V.anim[i] > 0.004 then
			UI.Round(rx + S(2), y + S(2), math.max(S(10), (rw - S(4)) * V.anim[i]), rh - S(4), S(10), Color(fillCol.r, fillCol.g, fillCol.b, 80 * a))
		end
		-- key
		UI.Round(rx + S(7), y + (rh - S(22)) / 2, S(22), S(22), S(11), Color(base.r, base.g, base.b, 255 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
		UI.Text(tostring(i), "Praetor.SmallB", rx + S(18), y + rh / 2, Color(255, 255, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local right = string.format("%d%%  ·  %d", math.Round(pct * 100), n)
		surface.SetFont("Praetor.SmallB")
		local rtw = surface.GetTextSize(right)
		UI.Text(right, "Praetor.SmallB", rx + rw - S(10), y + rh / 2, Color(C.text.r, C.text.g, C.text.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		local icon = isWin and "crown" or (mine and "check" or nil)
		local lx = rx + S(38)
		if icon then
			UI.Icon(icon, lx, y + (rh - 16) / 2, 16, Color(255, 255, 255, 255 * a))
			lx = lx + 22
		end
		local avW = 0
		if V.v and V.v[i] and #V.v[i] > 0 then
			local sz = S(18)
			local shown = voterAvatars(V.v[i], rx + rw - S(14) - rtw - sz, y + (rh - sz) / 2, sz, 3)
			avW = shown > 0 and (sz + (shown - 1) * (sz - S(4)) + S(6)) or 0
		end
		UI.Text(UI.Fit(optLabel(V, i), "Praetor.BodyB", rx + rw - lx - rtw - avW - S(20)), "Praetor.BodyB", lx, y + rh / 2, Color(255, 255, 255, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + rh + S(4)
	end
	-- footer
	local foot
	if V.done then
		if V.done.x then foot = P.L("vote_cancelled", { S = V.done.x })
		elseif not win then foot = P.L("vote_nowin")
		else foot = P.L("vote_votes", { V = tot }) end
	else
		foot = P.L(V.kind == "map" and "mv_keys" or "vote_keys")
	end
	UI.Text(UI.Fit(foot, "Praetor.Tiny", w * 0.62), "Praetor.Tiny", S(14), h - S(16), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(UI.Fit(P.L("vote_by", { S = V.n or "?" }), "Praetor.Tiny", w * 0.36), "Praetor.Tiny", w - S(14), h - S(16), Color(C.dim.r, C.dim.g, C.dim.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

local function openCard()
	if IsValid(card) then card:Remove() end
	card = vgui.Create("DPanel")
	card:SetMouseInputEnabled(true)
	card:SetKeyboardInputEnabled(false)
	card.born = RealTime()
	card.Think = function(s)
		if not V then s:Remove() return end
		local w = math.min(S(360), ScrW() * 0.32)
		local lines, h = cardLayout(w)
		s.lines = lines
		-- voted (or being voted on): small bar, no clicks, until the result
		s.mini = (V.my ~= nil or amTarget()) and not V.done
		if s.mini then
			w, h = math.min(S(300), ScrW() * 0.3), S(40)
			s:SetMouseInputEnabled(canCancel())
		else
			s:SetMouseInputEnabled(true)
		end
		-- slides in from the left, fades out after the result
		local age = RealTime() - s.born
		local slide = math.min(1, age * 4)
		s.alpha = 1
		if V.done then
			local d = RealTime() - V.done.at
			s.alpha = math.Clamp((9 - d) / 1, 0, 1)
			if d > 9 then V = nil s:Remove() return end
		end
		s:SetSize(w, h)
		s:SetPos(S(16) - (1 - slide) * (w + S(20)), math.floor(ScrH() * 0.5 - h / 2))
		s:SetVisible(not IsValid(overlay) or not overlay:IsVisible())
		-- which row is under the mouse
		s.hover = nil
		s.xHover = false
		if s:IsHovered() then
			local mx, my = s:CursorPos()
			local r = s.xRect
			if r and mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then
				s.xHover = true
			elseif s.rows and not s.mini then
				for i, rr in ipairs(s.rows) do if my >= rr[1] and my <= rr[2] then s.hover = i end end
			end
		end
	end
	card.Paint = paintCard
	card.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		if s.xHover then
			UI.Confirm(P.L("vt_stop"), P.L("vt_stop_q"), function() P.Request("vote_cancel", {}) end, true)
			return
		end
		if s.hover then sendVote(s.hover) end
	end
	card:SetCursor("hand")
end

-- ------------------------------------------------------------------ map overlay (full screen)

function closeOverlay()
	if IsValid(overlay) then overlay:Remove() end
	gui.EnableScreenClicker(false)
end

local function openOverlay()
	closeOverlay()
	if not V or V.kind ~= "map" then return end
	if V.my and not V.done then return end
	overlay = vgui.Create("DPanel")
	overlay:SetSize(ScrW(), ScrH())
	overlay:SetPos(0, 0)
	overlay:SetKeyboardInputEnabled(false)
	overlay.born = RealTime()
	gui.EnableScreenClicker(true)
	local n = #V.o
	local cols = n <= 4 and n or math.ceil(n / 2)
	cols = math.min(cols, 5)
	local rows = math.ceil(n / cols)
	local gap = S(14)
	local cw = math.min(S(250), math.floor((ScrW() - S(80) - gap * (cols - 1)) / cols))
	local ch = math.floor(cw * 0.78)
	local gridW = cols * cw + (cols - 1) * gap
	local gridH = rows * ch + (rows - 1) * gap
	local gx = math.floor((ScrW() - gridW) / 2)
	local gy = math.floor(ScrH() / 2 - gridH / 2 + S(20))
	overlay.Paint = function(s, w, h)
		local a = math.min(1, (RealTime() - s.born) * 4)
		surface.SetDrawColor(8, 6, 16, 220 * a)
		surface.DrawRect(0, 0, w, h)
		if not V then return end
		local ty = gy - S(96)
		local title = P.L("mv_title")
		if V.done then
			local wl = V.done.w and optLabel(V, V.done.w)
			title = V.done.x and P.L("vote_cancelled", { S = V.done.x }) or (V.done.w and (V.o[V.done.w] == KEEP and P.L("mv_stays") or P.L("mv_won", { S = wl })) or P.L("vote_nowin"))
		end
		surface.SetFont("Praetor.Logo")
		local tw = surface.GetTextSize(title)
		UI.Icon("map", w / 2 - tw / 2 - 40, ty + 2, 32)
		UI.TextShadow(title, "Praetor.Logo", w / 2 + 2, ty + 18, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local sub
		if V.done then
			sub = V.done.go and P.L("mv_changing", { V = math.max(0, math.ceil(V.done.go - (RealTime() - V.done.at))) }) or ""
		else
			sub = P.L("mv_sub", { V = math.ceil(timeLeft()), S = P.MapPretty(V.cur or game.GetMap()) })
		end
		UI.Text(sub, "Praetor.Body", w / 2, ty + S(52), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- time bar
		local bw = math.min(gridW, S(520))
		local frac = V.done and 0 or math.Clamp(timeLeft() / math.max(1, V.dur), 0, 1)
		UI.Round(w / 2 - bw / 2, ty + S(70), bw, S(4), S(2), Color(255, 255, 255, 25))
		UI.Round(w / 2 - bw / 2, ty + S(70), bw * frac, S(4), S(2), timeLeft() < 6 and C.crimsonL or C.bronzeL)
		UI.Text(V.done and "" or P.L("mv_hint"), "Praetor.Small", w / 2, gy + gridH + S(28), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	overlay.Think = function(s)
		if not V or V.kind ~= "map" then closeOverlay() return end
		if V.done and RealTime() - V.done.at > 7 then closeOverlay() end
	end
	for i = 1, n do
		local b = vgui.Create("DButton", overlay)
		b:SetText("")
		b:SetSize(cw, ch)
		local c0 = (i - 1) % cols
		local r0 = math.floor((i - 1) / cols)
		-- the last row is centred when it is not full
		local inRow = (r0 == rows - 1) and (n - r0 * cols) or cols
		local rowW = inRow * cw + (inRow - 1) * gap
		b:SetPos(math.floor((ScrW() - rowW) / 2) + c0 * (cw + gap), gy + r0 * (ch + gap))
		b.hov = 0
		b.Paint = function(s, w, h)
			if not V then return end
			s.hov = UI.Lerp(s.hov, s:IsHovered() and not V.done and 1 or 0, 12)
			local o = V.o[i]
			local isKeep = o == KEEP
			local mapName = isKeep and (V.cur or game.GetMap()) or o
			local tot = total(V.c)
			local cnt = V.c[i] or 0
			local pct = tot > 0 and cnt / tot or 0
			local mine = V.my == i
			local win = V.done and V.done.w == i
			local lose = V.done and V.done.w and not win
			local border = win and C.bronzeL or (mine and C.laurel or P.LerpColor(s.hov, C.line, C.lineL))
			local lift = math.floor(s.hov * S(3))
			local alpha = lose and 110 or 255
			UI.Round(0, 0, w, h, S(14), C.panel, border)
			local ph = h - S(56)
			P.DrawMapPicture(mapName, 2, 2 - lift, w - 4, ph, alpha)
			if isKeep then
				surface.SetDrawColor(10, 12, 18, 150)
				surface.DrawRect(2, 2 - lift, w - 4, ph)
				UI.Icon("reload", w / 2 - 16, ph / 2 - 24 - lift, 32)
				UI.TextShadow(P.L("mv_keep"), "Praetor.H2", w / 2, ph / 2 + S(16) - lift, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			-- key and tag
			UI.Round(S(8), S(8) - lift, S(26), S(26), S(13), C.bronze, C.ink)
			UI.Text(tostring(i), "Praetor.BodyB", S(8) + S(13), S(21) - lift, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local pretty, tag = P.MapPretty(mapName)
			if tag then
				surface.SetFont("Praetor.Tiny")
				local tgw = surface.GetTextSize(tag) + S(12)
				UI.Round(w - tgw - S(8), S(10) - lift, tgw, S(20), S(10), Color(0, 0, 0, 160), C.lineL)
				UI.Text(tag, "Praetor.Tiny", w - S(8) - tgw / 2, S(20) - lift, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			if win then UI.Icon("crown", w / 2 - 16, S(8) - lift, 32) end
			-- name on the picture
			UI.TextShadow(UI.Fit(isKeep and pretty or pretty, "Praetor.H3", w - S(20)), "Praetor.H3", S(10), ph - S(16) - lift, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			-- votes
			local by = ph + S(10)
			UI.Round(S(10), by + S(26), w - S(20), S(6), S(3), Color(255, 255, 255, 18))
			V.manim = V.manim or {}
			V.manim[i] = UI.Lerp(V.manim[i] or 0, pct, 8)
			local fc = win and C.bronzeL or (mine and C.laurel or C.bronze)
			if V.manim[i] > 0.004 then UI.Round(S(10), by + S(26), (w - S(20)) * V.manim[i], S(6), S(3), fc) end
			UI.Text(P.L("mv_votes", { V = cnt }) .. "  ·  " .. math.Round(pct * 100) .. "%", "Praetor.SmallB", S(10), by + S(10), mine and C.laurel or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if V.v and V.v[i] then voterAvatars(V.v[i], w - S(10) - S(20), by, S(20), 5) end
			if mine then UI.Icon("check", w - S(30), S(10) - lift + (tag and S(24) or 0), 16) end
		end
		b.DoClick = function() sendVote(i) end
	end
	-- hide button (keys 1-9 still work, the card stays on the left)
	local hide = UI.Button(overlay, P.L("mv_hide"), "ghost", "eye_no", function() closeOverlay() end)
	hide:SetSize(S(150), S(34))
	hide:SetPos(ScrW() / 2 - S(75), gy + gridH + S(48))
end

-- ------------------------------------------------------------------ net

P.On("vote", function(d)
	V = {
		id = d.id, kind = d.kind or "poll", q = d.q, o = d.o or {}, yn = d.yn, n = d.n, act = d.act,
		dur = d.dur or 30, ends = RealTime() + (d.d or 30), c = d.c or {}, v = d.v or {}, cur = d.cur,
	}
	changing = nil
	UI.Sound("notify")
	openCard()
	if V.kind == "map" then openOverlay() end
end)

P.On("vote_upd", function(d)
	if not V or V.id ~= d.id or V.done then return end
	V.c, V.v = d.c or V.c, d.v or V.v
end)

P.On("vote_end", function(d)
	if not V or V.id ~= d.id then
		-- joined late or the card was closed: rebuild it to show the result
		V = { id = d.id, kind = d.kind or "poll", q = d.q, o = d.o or {}, yn = d.yn, dur = 1, ends = RealTime(), c = {}, v = {}, cur = d.cur, act = d.act }
		openCard()
	end
	V.c = d.c or V.c
	V.done = { w = d.w, x = d.x, go = d.go, at = RealTime(), tie = d.tie }
	UI.Sound(d.x and "close" or "ok")
	if d.go and d.w then changing = { map = d.o[d.w], at = RealTime() + d.go } end
	if V.kind == "map" and not IsValid(overlay) and not d.x then openOverlay() end
	-- one line in the chat
	local tot = total(d.c)
	local out = { C.bronzeD, "| ", C.bronzeL, P.L(V.kind == "map" and "mv_short" or "vote_title") .. ": " }
	if V.kind ~= "map" then
		out[#out + 1] = C.ivory
		out[#out + 1] = titleOf(V) .. "  "
	end
	if d.x then
		out[#out + 1] = C.muted
		out[#out + 1] = P.L("vote_cancelled", { S = d.x })
	elseif d.w then
		out[#out + 1] = C.laurel
		out[#out + 1] = optLabel(V, d.w)
		out[#out + 1] = C.muted
		out[#out + 1] = string.format("  (%d/%d, %d%%)", d.c[d.w] or 0, tot, tot > 0 and math.Round((d.c[d.w] or 0) / tot * 100) or 0)
	else
		out[#out + 1] = C.muted
		out[#out + 1] = P.L("vote_nowin")
	end
	chat.AddText(unpack(out))
	hook.Run("Praetor.VoteChanged")
end)

P.On("vote_abort", function(d)
	changing = nil
	chat.AddText(C.bronzeD, "| ", C.amber, P.L("mv_aborted", { S = d.n or "?" }))
end)

P.On("vote_info", function(d)
	P.VoteInfo = d
	hook.Run("Praetor.VoteInfo", d)
end)

hook.Add("PlayerBindPress", "Praetor.Vote", function(_, bind, pressed)
	if not V or V.done or not pressed or V.my or amTarget() then return end
	local n = tonumber(bind:match("^slot(%d)$"))
	if n and n >= 1 and n <= #V.o then
		sendVote(n)
		return true
	end
end)

-- countdown at the top while the server changes the map
hook.Add("HUDPaint", "Praetor.MapChange", function()
	if not changing then return end
	local left = changing.at - RealTime()
	if left < -15 then changing = nil return end
	if IsValid(overlay) then return end
	local text = P.L("mv_changing_to", { S = P.MapPretty(changing.map), V = math.max(0, math.ceil(left)) })
	surface.SetFont("Praetor.BodyB")
	local tw = surface.GetTextSize(text) + S(60)
	local x, y = ScrW() / 2 - tw / 2, S(18)
	UI.Comic(x, y, tw, S(38), S(19), Color(C.panel.r, C.panel.g, C.panel.b, 245), C.bronze, S(4))
	UI.Icon("map", x + S(14), y + (S(38) - 16) / 2, 16)
	UI.Text(text, "Praetor.BodyB", x + S(40), y + S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-- the overlay comes back with this command (or !mapvote players can't start)
concommand.Add("praetor_vote", function()
	if V and V.kind == "map" and not V.done then openOverlay() end
end)

function P.CurrentVote() return V end
function P.ReopenMapVote() if V and V.kind == "map" and not V.done then openOverlay() end end
