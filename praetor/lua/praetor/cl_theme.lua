-- Praetor: look & feel. Clean dark panels with soft rounded corners, one blue
-- accent and pixel-art icons. (The colour keys keep their old names - bronze is
-- the accent - so every file keeps working.)
local P = Praetor
local UI = P.UI

UI.C = {
	bg      = Color(15, 16, 20),
	panel   = Color(22, 23, 29),
	panel2  = Color(30, 32, 39),
	panel3  = Color(40, 42, 51),
	hover   = Color(48, 51, 61),
	line    = Color(50, 53, 63),
	lineL   = Color(72, 76, 89),
	bronze  = Color(142, 98, 255),
	bronzeL = Color(188, 160, 255),
	bronzeD = Color(86, 54, 180),
	ivory   = Color(238, 240, 245),
	text    = Color(214, 217, 225),
	muted   = Color(142, 147, 160),
	dim     = Color(102, 106, 119),
	crimson = Color(222, 72, 86),
	crimsonL = Color(242, 112, 120),
	laurel  = Color(76, 196, 122),
	sky     = Color(88, 170, 240),
	amber   = Color(240, 176, 64),
	shadow  = Color(0, 0, 0, 120),
}
local C = UI.C

-- ------------------------------------------------------------------ materials

local mats = {}
function UI.Mat(path)
	local m = mats[path]
	if not m then
		m = Material(path, "noclamp")
		mats[path] = m
	end
	return m
end

local iconMissing = {}
function UI.Icon(name, x, y, size, col)
	if not name then return end
	local path = "praetor/icons/" .. name .. ".png"
	local m = UI.Mat(path)
	if m:IsError() then
		if not iconMissing[name] then iconMissing[name] = true end
		return
	end
	surface.SetDrawColor(col or color_white)
	surface.SetMaterial(m)
	surface.DrawTexturedRect(math.floor(x), math.floor(y), size, size)
end

-- pixel icons look best at multiples of 16
function UI.IconSize(want)
	return math.max(16, math.floor(want / 16 + 0.5) * 16)
end

-- (1.0 drew a grain texture here; the new look is flat, so it does nothing now)
function UI.Noise() end

-- ------------------------------------------------------------------ shapes

local function solid(c)
	if c.a == nil then return Color(c.r, c.g, c.b) end
	return c
end

-- rounded rectangle, optionally with a 1px border
function UI.Round(x, y, w, h, r, fill, border)
	x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
	if w <= 0 or h <= 0 then return end
	r = math.max(0, math.floor(math.min(r or 0, h / 2, w / 2)))
	fill = solid(fill)
	if not border then
		draw.RoundedBox(r, x, y, w, h, fill)
		return
	end
	border = solid(border)
	if fill.a >= 255 then
		draw.RoundedBox(r, x, y, w, h, border)
		draw.RoundedBox(math.max(0, r - 1), x + 1, y + 1, w - 2, h - 2, fill)
	else
		-- see-through fill: the border is drawn as four edges so it doesn't show through
		draw.RoundedBox(r, x, y, w, h, fill)
		surface.SetDrawColor(border)
		local c = math.max(r - 1, 0)
		surface.DrawRect(x + c, y, w - c * 2, 1)
		surface.DrawRect(x + c, y + h - 1, w - c * 2, 1)
		surface.DrawRect(x, y + c, 1, h - c * 2)
		surface.DrawRect(x + w - 1, y + c, 1, h - c * 2)
	end
end

-- 1.0 used cut corners; everything that called it now gets soft rounded corners
function UI.Notch(x, y, w, h, cut, fill, border)
	UI.Round(x, y, w, h, math.min(cut or 0, P.S(5)), fill, border)
end

function UI.Rect(x, y, w, h, col)
	surface.SetDrawColor(col)
	surface.DrawRect(x, y, w, h)
end

function UI.Outline(x, y, w, h, col, t)
	surface.SetDrawColor(col)
	surface.DrawOutlinedRect(x, y, w, h, t or 1)
end

-- a card / window background
function UI.Tablet(x, y, w, h, fill, trim)
	UI.Round(x, y, w, h, P.S(8), fill or C.panel, trim or C.line)
end

-- thin divider
function UI.Rule(x, y, w, col)
	surface.SetDrawColor(col or C.line)
	surface.DrawRect(x, y, w, 1)
end

-- (1.0 drew a pixel laurel; kept so old calls don't break, it draws nothing)
function UI.Laurel() return 0 end

function UI.Text(t, font, x, y, col, ax, ay)
	return draw.SimpleText(t, font, x, y, col or C.text, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

function UI.TextShadow(t, font, x, y, col, ax, ay)
	draw.SimpleText(t, font, x + 1, y + 2, C.shadow, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
	return draw.SimpleText(t, font, x, y, col or C.text, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

-- Cuts text with "..." so it fits in `w` pixels.
function UI.Fit(text, font, w)
	text = tostring(text or "")
	surface.SetFont(font)
	if surface.GetTextSize(text) <= w then return text end
	local chars = P.Chars(text)
	local lo, hi = 0, #chars
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if surface.GetTextSize(table.concat(chars, "", 1, mid) .. "...") <= w then lo = mid else hi = mid - 1 end
	end
	return table.concat(chars, "", 1, lo) .. "..."
end

-- Player names: cut with "..." to fit `maxW` and drawn with a font that has the
-- letters (names in Russian, Japanese, Arabic... don't turn into boxes).
function UI.Name(text, font, x, y, col, ax, ay, maxW, shadow)
	text = tostring(text or "")
	local f = UI.FontFor and UI.FontFor(text, font) or font
	if maxW then text = UI.Fit(text, f, maxW) end
	if shadow then draw.SimpleText(text, f, x + 1, y + 1, Color(0, 0, 0, 160), ax, ay) end
	draw.SimpleText(text, f, x, y, col, ax, ay)
	surface.SetFont(f)
	return surface.GetTextSize(text)
end

-- Word wrap: returns a list of lines.
function UI.Wrap(text, font, w)
	surface.SetFont(font)
	local lines = {}
	for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		local cur = ""
		for word in para:gmatch("%S+") do
			local try = cur == "" and word or (cur .. " " .. word)
			if surface.GetTextSize(try) <= w then
				cur = try
			else
				if cur ~= "" then lines[#lines + 1] = cur end
				-- very long words are cut
				while surface.GetTextSize(word) > w and #word > 1 do
					local fit = UI.Fit(word, font, w):gsub("%.%.%.$", "")
					if fit == "" then break end
					lines[#lines + 1] = fit
					word = word:sub(#fit + 1)
				end
				cur = word
			end
		end
		lines[#lines + 1] = cur
	end
	return lines
end

-- ------------------------------------------------------------------ sounds

UI.Sounds = {
	click = "praetor/click.ogg",
	open = "praetor/open.ogg",
	close = "praetor/close.ogg",
	tab = "praetor/tab.ogg",
	notify = "praetor/notify.ogg",
	report = "praetor/report.ogg",
	gavel = "praetor/gavel.ogg",
	warn = "praetor/warn.ogg",
	error = "praetor/error.ogg",
	ok = "praetor/seal.ogg",
	chat = "praetor/chat.ogg",
}

local soundVar = CreateClientConVar("praetor_sounds", "1", true, false, "Praetor interface sounds")
function UI.Sound(name)
	if not soundVar:GetBool() then return end
	local s = UI.Sounds[name]
	if s then surface.PlaySound(s) end
end

-- rank badge helpers
function UI.RankStyle(rank)
	local r = istable(rank) and rank or P.Ranks[rank or "user"]
	if not r then return { text = tostring(rank or "?"), c1 = { r = 200, g = 200, b = 200 }, fx = "none" }, "leaf" end
	local s = r.style or { text = r.display or r.name, c1 = { r = 200, g = 200, b = 200 } }
	return s, r.icon
end

-- the badge shown for a player: owners get the "Owner" badge (gold, crown),
-- everyone else the style of their rank
local ownerStyle = { text = "Owner", c1 = { r = 240, g = 176, b = 64 }, c2 = { r = 255, g = 222, b = 140 }, fx = "shine" }
function UI.PlayerRankStyle(ply)
	if IsValid(ply) and P.IsOwner(ply) then
		ownerStyle.text = P.L("owner")
		return ownerStyle, "crown"
	end
	return UI.RankStyle(IsValid(ply) and ply:GetUserGroup() or "user")
end

-- RealFrameTime: FrameTime stops while the game is paused or slowed down, and
-- hover highlights stayed lit on the menu buttons
function UI.Lerp(cur, target, speed)
	local v = Lerp(math.min(1, RealFrameTime() * (speed or 12)), cur or 0, target)
	if math.abs(v - target) < 0.004 then return target end
	return v
end

-- ------------------------------------------------------------------ avatar textures
-- A Steam avatar copied into a small render target, so the same picture can be
-- drawn any number of times in one frame (one AvatarImage panel can only be in
-- one place: the chat showed the picture on a single line). Drawn with round
-- corners and an optional coloured frame by UI.DrawAvatar.
local AV_SIZE = 64
local avTex = {}

local function avatarTex(sid, ply)
	if not sid then return nil end
	local a = avTex[sid]
	if a and IsValid(a.panel) then
		a.used = RealTime()
		return a
	end
	local name = "praetor_av_" .. sid
	local rt = GetRenderTargetEx(name, AV_SIZE, AV_SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 2, 0, IMAGE_FORMAT_RGBA8888)
	local mat = CreateMaterial(name .. "_m", "UnlitGeneric", {
		["$basetexture"] = rt:GetName(), ["$translucent"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1",
	})
	local panel = vgui.Create("AvatarImage")
	panel:SetSize(AV_SIZE, AV_SIZE)
	if IsValid(ply) then panel:SetPlayer(ply, 64) else panel:SetSteamID(sid, 64) end
	panel:SetPaintedManually(true)
	a = { rt = rt, mat = mat, panel = panel, born = RealTime(), nextDraw = 0, used = RealTime(), ready = false }
	avTex[sid] = a
	return a
end
UI.AvatarTex = avatarTex

-- Steam downloads the picture in the background: copy it often at first, then
-- rarely; pictures nobody drew for 5 minutes are thrown away.
hook.Add("HUDPaint", "Praetor.AvatarTex", function()
	local now = RealTime()
	for sid, a in pairs(avTex) do
		if not IsValid(a.panel) or now - a.used > 300 then
			if IsValid(a.panel) then a.panel:Remove() end
			avTex[sid] = nil
		elseif now >= a.nextDraw then
			a.nextDraw = now + ((now - a.born < 12) and 0.4 or 20)
			render.PushRenderTarget(a.rt)
			render.OverrideAlphaWriteEnable(true, true)
			render.Clear(0, 0, 0, 0)
			cam.Start2D()
				a.panel:SetPos(0, 0)
				a.panel:PaintManual()
			cam.End2D()
			render.OverrideAlphaWriteEnable(false)
			render.PopRenderTarget()
			a.ready = true
		end
	end
end)

local polyCache = {}
local function roundPoly(x, y, s, r)
	local key = s .. ":" .. r
	local base = polyCache[key]
	if not base then
		base = {}
		local corners = { { s - r, r, -90 }, { s - r, s - r, 0 }, { r, s - r, 90 }, { r, r, 180 } }
		for _, c in ipairs(corners) do
			for i = 0, 5 do
				local ang = math.rad(c[3] + 90 * i / 5)
				base[#base + 1] = { c[1] + math.cos(ang) * r, c[2] + math.sin(ang) * r }
			end
		end
		polyCache[key] = base
	end
	local pts = {}
	for i, p in ipairs(base) do pts[i] = { x = x + p[1], y = y + p[2] } end
	return pts
end

-- the initial on a colour taken from the name (bots, or while Steam loads)
local function letterAvatar(name, x, y, size, alpha, r)
	local c = HSVToColor((tonumber(util.CRC(name or "?")) or 0) % 360, 0.45, 0.62)
	UI.Round(x, y, size, size, r, Color(c.r, c.g, c.b, alpha))
	local font = size >= 30 and "Praetor.BodyB" or "Praetor.Tiny"
	draw.SimpleText(string.upper(P.Chars(name or "?")[1] or "?"), font, x + size / 2, y + size / 2, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- UI.DrawAvatar(sid64, ply, x, y, size, alpha 0-255, frameColour or nil, name for the letter)
function UI.DrawAvatar(sid, ply, x, y, size, alpha, frame, name)
	alpha = alpha or 255
	x, y, size = math.floor(x), math.floor(y), math.floor(size)
	local r = math.max(2, math.floor(size * 0.24))
	if frame then
		UI.Round(x - 2, y - 2, size + 4, size + 4, r + 2, Color(frame.r, frame.g, frame.b, alpha))
		UI.Round(x - 1, y - 1, size + 2, size + 2, r + 1, Color(10, 11, 14, alpha))
	end
	local bot = IsValid(ply) and ply:IsBot()
	local a = (not bot) and avatarTex(sid, ply) or nil
	if not a or not a.ready then
		letterAvatar(name or (IsValid(ply) and ply:Nick()) or "?", x, y, size, alpha, r)
		return
	end
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_REPLACE)
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 1)
	surface.DrawPoly(roundPoly(x, y, size, r))
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	surface.SetMaterial(a.mat)
	surface.SetDrawColor(255, 255, 255, alpha)
	surface.DrawTexturedRect(x, y, size, size)
	render.SetStencilEnable(false)
end

-- frame colour of a player: their rank colour (owners gold)
function UI.AvatarFrame(ply)
	local style = UI.PlayerRankStyle(ply)
	local c = style and style.c1
	if not c then return C.lineL end
	return Color(c.r or 200, c.g or 200, c.b or 200)
end
