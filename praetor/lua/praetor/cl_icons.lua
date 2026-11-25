-- Praetor: custom icons on the client. Draws them (UI.Icon knows the "c_"
-- names), the icon picker with the "Create icon" tile, and the editor.
-- The editor has two modes: pixel (16x16, one pixel at a time) and paint
-- (32x32, round brushes of several sizes, smooth strokes).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local N = 16

P.CustomIcons = P.CustomIcons or {}
local runs = {} -- [id] = { { x, y, len, r, g, b }, ... } horizontal runs of one colour

local function hexColor(h)
	return tonumber(h:sub(1, 2), 16) or 255, tonumber(h:sub(3, 4), 16) or 255, tonumber(h:sub(5, 6), 16) or 255
end

local function sizeOf(icon) return (icon and tonumber(icon.s) == 32) and 32 or 16 end

local function buildRuns(icon)
	local out = {}
	local pal = {}
	local n = sizeOf(icon)
	for i, h in ipairs(icon.pal or {}) do pal[i - 1] = { hexColor(h) } end
	for y = 0, n - 1 do
		local x = 0
		while x < n do
			local ch = icon.px:sub(y * n + x + 1, y * n + x + 1)
			if ch ~= "." then
				local len = 1
				while x + len < n and icon.px:sub(y * n + x + len + 1, y * n + x + len + 1) == ch do len = len + 1 end
				local c = pal[tonumber(ch, 16)]
				if c then out[#out + 1] = { x, y, len, c[1], c[2], c[3] } end
				x = x + len
			else
				x = x + 1
			end
		end
	end
	return out
end

P.On("icons", function(d)
	P.CustomIcons = d
	runs = {}
end)

local savedCallback
P.On("icon_saved", function(d)
	UI.Sound("ok")
	P.Toast(P.L("ic_editor"), P.L("ic_saved"), "ok", 3)
	if savedCallback and isstring(d.id) then
		local cb = savedCallback
		savedCallback = nil
		-- wait a moment for the "icons" update that comes with it
		timer.Simple(0.2, function() cb(d.id) end)
	end
end)

local function drawCustom(name, x, y, size, col)
	local icon = P.CustomIcons[name]
	if not icon or not isstring(icon.px) then return end
	local r = runs[name]
	if not r then
		r = buildRuns(icon)
		runs[name] = r
	end
	x, y = math.floor(x), math.floor(y)
	local k = size / sizeOf(icon)
	local tr, tg, tb, ta = 255, 255, 255, 255
	if col then tr, tg, tb, ta = col.r, col.g, col.b, col.a or 255 end
	for _, run in ipairs(r) do
		local x0 = x + math.floor(run[1] * k)
		local x1 = x + math.floor((run[1] + run[3]) * k)
		local y0 = y + math.floor(run[2] * k)
		local y1 = y + math.floor((run[2] + 1) * k)
		if x1 > x0 and y1 > y0 then
			surface.SetDrawColor(run[4] * tr / 255, run[5] * tg / 255, run[6] * tb / 255, ta)
			surface.DrawRect(x0, y0, x1 - x0, y1 - y0)
		end
	end
end

-- UI.Icon draws the custom ones too
local baseIcon = UI.BaseIcon or UI.Icon
UI.BaseIcon = baseIcon
function UI.Icon(name, x, y, size, col)
	if isstring(name) and name:sub(1, 2) == "c_" then return drawCustom(name, x, y, size, col) end
	return baseIcon(name, x, y, size, col)
end

local function canCreate() return P.MyHas("manage_ranks") or P.MyHas("manage_tags") or P.MyHas("manage_announce") end

-- ------------------------------------------------------------------ reading pixels

-- n x n grid (index y * n + x + 1 -> Color or nil) from any icon
local function readIcon(name, n)
	n = n or N
	local grid = {}
	if name:sub(1, 2) == "c_" then
		local icon = P.CustomIcons[name]
		if not icon then return grid end
		local src = sizeOf(icon)
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				local sx, sy = math.floor(x * src / n), math.floor(y * src / n)
				local i = sy * src + sx + 1
				local ch = icon.px:sub(i, i)
				local h = ch ~= "." and icon.pal[(tonumber(ch, 16) or 0) + 1]
				if h then grid[y * n + x + 1] = Color(hexColor(h)) end
			end
		end
		return grid
	end
	-- built-in PNG: sample the middle of every cell
	local mat = UI.Mat("praetor/icons/" .. name .. ".png")
	if mat:IsError() then return grid end
	local tex = mat:GetTexture("$basetexture")
	if not tex then return grid end
	local step = tex:Width() / n
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local ok, c = pcall(tex.GetColor, tex, math.floor(x * step + step / 2), math.floor(y * step + step / 2))
			if ok and c and c.a > 127 then grid[y * n + x + 1] = Color(c.r, c.g, c.b) end
		end
	end
	return grid
end

-- the same drawing at another size (16 <-> 32)
local function resample(grid, from, to)
	local out = {}
	for y = 0, to - 1 do
		for x = 0, to - 1 do
			local sx, sy = math.floor(x * from / to), math.floor(y * from / to)
			out[y * to + x + 1] = grid[sy * from + sx + 1]
		end
	end
	return out
end

-- ------------------------------------------------------------------ editor

local PALETTE = {
	"000000", "3b3b4a", "7c7f8f", "c6cad6", "ffffff",
	"6b2e1f", "b5482b", "e8763a", "f5b041", "f7e26b",
	"2d6a3e", "4cb860", "a3e05a", "1f4e8c", "3d8fe0",
	"7fd1f2", "4a2a7a", "8c5ad8", "d46bc9", "ff8fa8",
	"8a5a2b", "c98a4b", "e0c097", "b3263a",
}

local function hexOf(c) return string.format("%02x%02x%02x", c.r, c.g, c.b) end

-- an icon keeps at most 16 colours: the closest ones are merged until it fits
local function reduceColours(grid, total)
	local count = {}
	for i = 1, total do
		local c = grid[i]
		if c then local h = hexOf(c) count[h] = (count[h] or 0) + 1 end
	end
	local keys = table.GetKeys(count)
	local merged = 0
	while #keys > 16 do
		local best, ba, bb = math.huge
		for i = 1, #keys do
			local r1, g1, b1 = hexColor(keys[i])
			for j = i + 1, #keys do
				local r2, g2, b2 = hexColor(keys[j])
				local d = (r1 - r2) ^ 2 + (g1 - g2) ^ 2 + (b1 - b2) ^ 2
				if d < best then best, ba, bb = d, i, j end
			end
		end
		-- the less used colour takes the other one
		local keep, drop = keys[ba], keys[bb]
		if count[drop] > count[keep] then keep, drop = drop, keep end
		local kc = Color(hexColor(keep))
		for i = 1, total do
			if grid[i] and hexOf(grid[i]) == drop then grid[i] = kc end
		end
		count[keep] = count[keep] + count[drop]
		count[drop] = nil
		keys = table.GetKeys(count)
		merged = merged + 1
	end
	return merged
end

function UI.IconEditor(editId, onSaved)
	if not canCreate() then return end
	local m = UI.Modal(P.L("ic_editor"), S(760), S(600))
	local startIcon = editId and P.CustomIcons[editId]
	local n = sizeOf(startIcon)
	local mode = n == 32 and "paint" or "pixel"
	local grid = editId and readIcon(editId, n) or {}
	local undo, redo = {}, {}
	local tool = mode == "paint" and "brush" or "pencil"
	local brush = 2
	local mirror = false
	local color = Color(hexColor("e8763a"))
	local recent = {}

	local function copyGrid()
		local c = {}
		for i = 1, n * n do c[i] = grid[i] end
		return c
	end
	local function snapshot()
		undo[#undo + 1] = { n = n, g = copyGrid() }
		if #undo > 60 then table.remove(undo, 1) end
		redo = {}
	end
	local function restore(st)
		n = st.n
		grid = st.g
		mode = n == 32 and "paint" or "pixel"
	end

	-- ---------------------------------------------------------------- canvas
	local CANVAS = math.min(S(448), m:GetTall() - S(150))
	local left = vgui.Create("DPanel", m.body)
	left:Dock(LEFT)
	left:SetWide(CANVAS + S(8))
	left.Paint = nil

	-- mode switch above the canvas: Pixel 16x16 / Paint 32x32
	local modes = vgui.Create("DPanel", left)
	modes:Dock(TOP)
	modes:SetTall(S(40))
	modes:DockMargin(0, 0, 0, S(8))
	modes.Paint = nil
	local function modeBtn(id, label, icon)
		local b = UI.Button(modes, label, "ghost", icon, function()
			if mode == id then return end
			snapshot()
			local to = id == "paint" and 32 or 16
			grid = resample(grid, n, to)
			n = to
			mode = id
			if mode == "paint" and tool == "pencil" then tool = "brush" end
			if mode == "pixel" and tool == "brush" then tool = "pencil" end
			UI.Sound("toggle")
		end)
		b:Dock(LEFT)
		b:SetWide(math.floor(CANVAS / 2) - S(4))
		b:DockMargin(0, 0, S(8), 0)
		b.Think = function(s) s.kind = mode == id and "active" or "ghost" end
		return b
	end
	modeBtn("pixel", P.L("ic_mode_pixel"), "image")
	modeBtn("paint", P.L("ic_mode_paint"), "pen")

	local canvas = vgui.Create("DPanel", left)
	canvas:SetSize(CANVAS + S(8), CANVAS + S(8))
	canvas:Dock(TOP)
	canvas:SetCursor("crosshair")

	local function cellSize() return math.floor(CANVAS / n) end
	local function cellAt(mx, my)
		local cs = cellSize()
		return math.floor((mx - S(4)) / cs), math.floor((my - S(4)) / cs)
	end

	canvas.Paint = function(s, w, h)
		local cs = cellSize()
		local size = cs * n
		UI.Round(S(4), S(4), size + S(4), size + S(4), S(10), C.ink)
		UI.Round(0, 0, size + S(4), size + S(4), S(10), C.panel3, C.ink)
		local ox, oy = S(2), S(2)
		-- checkerboard so empty pixels are visible
		local check = mode == "paint" and 2 or 1
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				local c = grid[y * n + x + 1]
				if c then
					UI.Rect(ox + x * cs, oy + y * cs, cs, cs, c)
				else
					local dark = (math.floor(x / check) + math.floor(y / check)) % 2 == 0
					UI.Rect(ox + x * cs, oy + y * cs, cs, cs, dark and Color(34, 30, 52) or Color(44, 38, 66))
				end
			end
		end
		-- a faint grid in pixel mode
		if mode == "pixel" then
			surface.SetDrawColor(255, 255, 255, 10)
			for i = 1, n - 1 do
				surface.DrawRect(ox + i * cs, oy, 1, size)
				surface.DrawRect(ox, oy + i * cs, size, 1)
			end
		end
		if mirror then UI.Rect(ox + n / 2 * cs, oy, 2, size, Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, 120)) end
		-- the brush under the cursor
		if s:IsHovered() then
			local cx, cy = cellAt(s:CursorPos())
			if cx >= 0 and cy >= 0 and cx < n and cy < n then
				local r = (mode == "paint" and (tool == "brush" or tool == "eraser")) and brush or 0
				local col = tool == "eraser" and C.crimsonL or color_white
				for yy = cy - r, cy + r do
					for xx = cx - r, cx + r do
						if xx >= 0 and yy >= 0 and xx < n and yy < n and (xx - cx) ^ 2 + (yy - cy) ^ 2 <= r * r + r * 0.8 then
							surface.SetDrawColor(col.r, col.g, col.b, 70)
							surface.DrawRect(ox + xx * cs, oy + yy * cs, cs, cs)
						end
					end
				end
			end
		end
	end

	local function put(x, y, c)
		if x < 0 or y < 0 or x >= n or y >= n then return end
		grid[y * n + x + 1] = c
		if mirror then grid[y * n + (n - 1 - x) + 1] = c end
	end

	-- a round stamp of radius r (0 = one pixel)
	local function stamp(x, y, c, r)
		if r <= 0 then put(x, y, c) return end
		for yy = y - r, y + r do
			for xx = x - r, x + r do
				if (xx - x) ^ 2 + (yy - y) ^ 2 <= r * r + r * 0.8 then put(xx, yy, c) end
			end
		end
	end

	-- stamps along the way from the last point, so fast strokes have no holes
	local function stroke(x0, y0, x1, y1, c, r)
		local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
		for i = 0, steps do
			local t = i / steps
			stamp(math.Round(x0 + (x1 - x0) * t), math.Round(y0 + (y1 - y0) * t), c, r)
		end
	end

	local function fill(x, y, c)
		local target = grid[y * n + x + 1]
		local key = function(v) return v and hexOf(v) or "" end
		local tk = key(target)
		if tk == key(c) then return end
		local stack = { { x, y } }
		while #stack > 0 do
			local p = table.remove(stack)
			local px, py = p[1], p[2]
			if px >= 0 and py >= 0 and px < n and py < n and key(grid[py * n + px + 1]) == tk then
				grid[py * n + px + 1] = c
				stack[#stack + 1] = { px + 1, py }
				stack[#stack + 1] = { px - 1, py }
				stack[#stack + 1] = { px, py + 1 }
				stack[#stack + 1] = { px, py - 1 }
			end
		end
	end

	local function useColor(c)
		color = Color(c.r, c.g, c.b)
		local h = hexOf(color)
		for i, v in ipairs(recent) do if v == h then table.remove(recent, i) break end end
		table.insert(recent, 1, h)
		while #recent > 8 do table.remove(recent) end
	end

	local function apply(btn, first)
		local x, y = cellAt(canvas:CursorPos())
		local t = btn == MOUSE_RIGHT and "eraser" or tool
		local r = mode == "paint" and brush or 0
		if t == "pencil" then r = 0 end
		local px, py = canvas.lastX or x, canvas.lastY or y
		if first then px, py = x, y end
		if t == "pencil" or t == "brush" then
			stroke(px, py, x, y, Color(color.r, color.g, color.b), r)
		elseif t == "eraser" then
			stroke(px, py, x, y, nil, r)
		elseif first and t == "fill" then
			if x >= 0 and y >= 0 and x < n and y < n then fill(x, y, Color(color.r, color.g, color.b)) end
		elseif first and t == "picker" then
			local c = x >= 0 and y >= 0 and x < n and y < n and grid[y * n + x + 1]
			if c then useColor(c) end
			tool = mode == "paint" and "brush" or "pencil"
		end
		canvas.lastX, canvas.lastY = x, y
	end

	canvas.OnMousePressed = function(s, btn)
		snapshot()
		s.down = btn
		s.lastX, s.lastY = nil, nil
		s:MouseCapture(true)
		apply(btn, true)
	end
	canvas.OnMouseReleased = function(s)
		s.down = nil
		s:MouseCapture(false)
	end
	canvas.Think = function(s)
		if s.down and (s.down == MOUSE_RIGHT or tool == "pencil" or tool == "brush" or tool == "eraser") then
			if not input.IsMouseDown(s.down) then s.down = nil s:MouseCapture(false) return end
			apply(s.down)
		end
	end
	canvas.OnMouseWheeled = function(_, d)
		if mode ~= "paint" then return end
		brush = math.Clamp(brush + (d > 0 and 1 or -1), 0, 5)
		return true
	end

	-- ---------------------------------------------------------------- right column
	local side = UI.Scroll(m.body)
	side:Dock(FILL)
	side:DockMargin(S(16), 0, 0, 0)

	local function sectionLabel(text)
		local l = vgui.Create("DPanel", side)
		l:Dock(TOP)
		l:SetTall(S(20))
		l:DockMargin(0, S(6), S(6), S(4))
		l.Paint = function(_, w, h)
			UI.Text(P.Upper(text), "Praetor.Tiny", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetFont("Praetor.Tiny")
			local tw = surface.GetTextSize(P.Upper(text)) + S(8)
			UI.Rect(tw, h / 2, w - tw, 2, Color(C.line.r, C.line.g, C.line.b, 140))
		end
	end

	-- tools
	sectionLabel(P.L("ic_tools"))
	local tools = vgui.Create("DIconLayout", side)
	tools:Dock(TOP)
	tools:DockMargin(0, 0, S(6), 0)
	tools:SetSpaceX(S(6))
	tools:SetSpaceY(S(6))
	local toolList = {
		{ "brush", "ic_brush", "broom", paint = true }, { "pencil", "ic_pencil", "pen" },
		{ "eraser", "ic_eraser", "eraser" }, { "fill", "ic_fill", "drop" }, { "picker", "ic_picker", "eye" },
	}
	for _, t in ipairs(toolList) do
		local b = tools:Add("PraetorButton")
		b:Setup(P.L(t[2]), "ghost", t[3])
		b:SetFont("Praetor.Small")
		b:SetSize(S(118), S(34))
		b.Think = function(s)
			s.kind = tool == t[1] and "active" or "ghost"
			local want = not t.paint or mode == "paint"
			if s:IsVisible() ~= want then s:SetVisible(want) tools:InvalidateLayout() end
		end
		b.DoClick = function() tool = t[1] end
	end

	-- brush size (paint mode): little dots of growing size
	local sizes = vgui.Create("DPanel", side)
	sizes:Dock(TOP)
	sizes:SetTall(S(46))
	sizes:DockMargin(0, S(8), S(6), 0)
	sizes.Paint = function(s, w, h)
		if mode ~= "paint" then
			UI.Text(P.L("ic_size_hint"), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return
		end
		UI.Text(P.L("ic_size"), "Praetor.SmallB", 0, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	for i = 0, 5 do
		local b = vgui.Create("DButton", sizes)
		b:SetText("")
		b:SetSize(S(36), S(36))
		b:SetPos(S(64) + i * S(40), S(5))
		b:SetTooltip(P.L("ic_size") .. " " .. (i * 2 + 1))
		b.Paint = function(s, w, h)
			if mode ~= "paint" then return end
			local on = brush == i
			UI.Round(0, 0, w, h, h / 2, on and C.bronze or (s:IsHovered() and C.hover or C.panel2), on and C.ink or C.line)
			local d = math.max(S(3), math.floor(S(4) + i * S(3.4)))
			UI.Round(w / 2 - d / 2, h / 2 - d / 2, d, d, d / 2, on and color_white or C.text)
		end
		b.DoClick = function() if mode == "paint" then brush = i UI.Sound("click") end end
	end

	-- mirror, undo, redo
	local acts = vgui.Create("DPanel", side)
	acts:Dock(TOP)
	acts:SetTall(S(34))
	acts:DockMargin(0, S(8), S(6), 0)
	acts.Paint = nil
	local mir = UI.Button(acts, P.L("ic_mirror"), "ghost", "reply", function() mirror = not mirror end)
	mir:SetFont("Praetor.Small")
	mir:Dock(LEFT)
	mir:SetWide(S(118))
	mir.Think = function(s) s.kind = mirror and "active" or "ghost" end
	local und = UI.Button(acts, P.L("ic_undo"), "ghost", "undo", function()
		local last = table.remove(undo)
		if last then
			redo[#redo + 1] = { n = n, g = copyGrid() }
			restore(last)
		end
	end)
	und:SetFont("Praetor.Small")
	und:Dock(LEFT)
	und:SetWide(S(96))
	und:DockMargin(S(6), 0, 0, 0)
	local red = UI.Button(acts, P.L("ic_redo"), "ghost", "reload", function()
		local nxt = table.remove(redo)
		if nxt then
			undo[#undo + 1] = { n = n, g = copyGrid() }
			restore(nxt)
		end
	end)
	red:SetFont("Praetor.Small")
	red:Dock(FILL)
	red:DockMargin(S(6), 0, 0, 0)

	-- Ctrl+Z / Ctrl+Y
	local bg = m:GetParent()
	local oldKey = bg.OnKeyCodePressed
	bg.OnKeyCodePressed = function(s, key)
		if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
			if key == KEY_Z then und:DoClick() return end
			if key == KEY_Y then red:DoClick() return end
		end
		if oldKey then return oldKey(s, key) end
	end

	-- colours
	sectionLabel(P.L("ic_color"))
	local pal = vgui.Create("DIconLayout", side)
	pal:Dock(TOP)
	pal:DockMargin(0, 0, S(6), 0)
	pal:SetSpaceX(S(5))
	pal:SetSpaceY(S(5))
	local sw = S(28)
	local function swatch(parent, getHex)
		local b = parent:Add("DButton")
		b:SetText("")
		b:SetSize(sw, sw)
		b.Paint = function(s, w, h)
			local hx = getHex()
			if not hx then UI.Round(0, 0, w, h, h / 2, C.panel2, C.line) return end
			local r, g, bl = hexColor(hx)
			local cur = hexOf(color) == hx
			local grow = (cur or s:IsHovered()) and 0 or S(2)
			UI.Round(grow, grow, w - grow * 2, h - grow * 2, (h - grow * 2) / 2, Color(r, g, bl), cur and color_white or C.ink)
		end
		b.DoClick = function()
			local hx = getHex()
			if hx then
				useColor(Color(hexColor(hx)))
				if tool == "eraser" or tool == "picker" then tool = mode == "paint" and "brush" or "pencil" end
				UI.Sound("click")
			end
		end
		return b
	end
	for _, hx in ipairs(PALETTE) do swatch(pal, function() return hx end) end

	-- current colour (opens the colour picker) + recent colours
	local cur = vgui.Create("DPanel", side)
	cur:Dock(TOP)
	cur:SetTall(S(38))
	cur:DockMargin(0, S(8), S(6), 0)
	cur.Paint = nil
	local pickSwatch = vgui.Create("DButton", cur)
	pickSwatch:SetText("")
	pickSwatch:Dock(LEFT)
	pickSwatch:SetWide(S(38))
	pickSwatch.Paint = function(s, w, h)
		UI.Round(S(2), S(2), w - S(2), h - S(2), S(10), C.ink)
		UI.Round(0, 0, w - S(2), h - S(2), S(10), color, s:IsHovered() and color_white or C.ink)
	end
	pickSwatch.DoClick = function() UI.PickColor(color, function(c) useColor(c) tool = mode == "paint" and "brush" or "pencil" end) end
	pickSwatch:SetTooltip(P.L("ui_pick_color"))
	local rec = vgui.Create("DIconLayout", cur)
	rec:Dock(FILL)
	rec:DockMargin(S(8), S(5), 0, 0)
	rec:SetSpaceX(S(5))
	for i = 1, 8 do swatch(rec, function() return recent[i] end) end

	-- start from another icon / clear
	sectionLabel(P.L("ic_start"))
	local row = vgui.Create("DPanel", side)
	row:Dock(TOP)
	row:SetTall(S(34))
	row:DockMargin(0, 0, S(6), 0)
	row.Paint = nil
	local imp = UI.Button(row, P.L("ic_import"), "ghost", "copy", function()
		UI.PickIcon(nil, function(name)
			snapshot()
			grid = readIcon(name, n)
		end, { noCreate = true })
	end)
	imp:SetFont("Praetor.Small")
	imp:Dock(FILL)
	local clr = UI.Button(row, P.L("ic_clear"), "ghost", "trash", function() snapshot() grid = {} end)
	clr:SetFont("Praetor.Small")
	clr:Dock(RIGHT)
	clr:SetWide(S(100))
	clr:DockMargin(S(6), 0, 0, 0)

	-- name
	sectionLabel(P.L("ic_name"))
	local name = UI.Entry(side, P.L("ic_name"), startIcon and startIcon.n or "")
	name:Dock(TOP)
	name:DockMargin(0, 0, S(6), 0)

	-- preview at the sizes it is used, and how many colours it has
	local prev = vgui.Create("DPanel", side)
	prev:Dock(TOP)
	prev:SetTall(S(96))
	prev:DockMargin(0, S(10), S(6), 0)
	prev.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(12), C.bg, C.line)
		local x = S(12)
		for _, sz in ipairs({ 16, 32, 64 }) do
			local y = math.floor((h - S(22) - sz) / 2) + S(2)
			local k = sz / n
			for i = 1, n * n do
				local c = grid[i]
				if c then
					local px, py = (i - 1) % n, math.floor((i - 1) / n)
					local x0, y0 = x + math.floor(px * k), y + math.floor(py * k)
					local x1, y1 = x + math.floor((px + 1) * k), y + math.floor((py + 1) * k)
					if x1 > x0 and y1 > y0 then UI.Rect(x0, y0, x1 - x0, y1 - y0, c) end
				end
			end
			x = x + sz + S(16)
		end
		local used = {}
		local cnt = 0
		for i = 1, n * n do
			local c = grid[i]
			if c then local hx = hexOf(c) if not used[hx] then used[hx] = true cnt = cnt + 1 end end
		end
		local over = cnt > 16
		UI.Text(P.L("ic_colors_used", { V = cnt }), "Praetor.Tiny", S(12), h - S(12), over and C.amber or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.L(mode == "paint" and "ic_hint_paint" or "ic_hint"), "Praetor.Tiny", w - S(12), h - S(12), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	-- footer
	local saveBtn = UI.Button(m.foot, P.L("ic_save"), "primary", "check", function()
		local total = n * n
		local work = copyGrid()
		local merged = reduceColours(work, total)
		local palette, index, px = {}, {}, {}
		for i = 1, total do
			local c = work[i]
			if c then
				local h = hexOf(c)
				if not index[h] then
					palette[#palette + 1] = h
					index[h] = #palette - 1
				end
				px[i] = string.format("%x", index[h] % 16)
			else
				px[i] = "."
			end
		end
		if #palette == 0 then P.Toast(P.L("ic_editor"), P.L("ic_empty"), "warn", 4) return end
		if merged > 0 then P.Toast(P.L("ic_editor"), P.L("ic_merged", { V = merged }), "info", 5) end
		savedCallback = function(id)
			if onSaved then onSaved(id) end
		end
		P.Request("icon_save", { id = editId, n = name:GetValue(), px = table.concat(px), pal = palette, s = n })
		m:Close()
	end)
	saveBtn:Dock(RIGHT)
	saveBtn:SetWide(S(150))
	local cancel = UI.Button(m.foot, P.L("ui_cancel"), "ghost", nil, function() m:Close() end)
	cancel:Dock(RIGHT)
	cancel:SetWide(S(110))
	cancel:DockMargin(0, 0, S(8), 0)
	return m
end

-- ------------------------------------------------------------------ picker

-- opts: { noCreate = true } hides the "Create icon" tile (used by the editor itself)
function UI.PickIcon(cur, onDone, opts)
	opts = opts or {}
	local m = UI.Modal(P.L("ui_pick_icon"), S(470), S(430))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)

	local function head(text)
		local l = vgui.Create("DPanel", sc)
		l:Dock(TOP)
		l:SetTall(S(20))
		l:DockMargin(0, S(2), 0, S(4))
		l.Paint = function(_, w, h) UI.Text(P.Upper(text), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end

	local function tile(grid, name, onRight)
		local b = grid:Add("DButton")
		b:SetText("")
		b:SetSize(S(48), S(48))
		b.Paint = function(s, w, h)
			UI.Round(0, 0, w, h, S(12), (s:IsHovered() or name == cur) and C.panel3 or C.panel2, name == cur and C.bronze or (s:IsHovered() and C.lineL or C.line))
			UI.Icon(name, (w - 32) / 2, (h - 32) / 2, 32)
		end
		b.DoClick = function() onDone(name) m:Close() end
		if onRight then b.DoRightClick = onRight end
		local ic = P.CustomIcons[name]
		if ic and ic.n and ic.n ~= "" then b:SetTooltip(ic.n) end
		return b
	end

	local function newGrid()
		local g = vgui.Create("DIconLayout", sc)
		g:Dock(TOP)
		g:SetSpaceX(S(6))
		g:SetSpaceY(S(6))
		g:DockMargin(0, 0, 0, S(8))
		return g
	end

	head(P.L("ic_builtin"))
	local g1 = newGrid()
	for _, name in ipairs(UI.RankIcons) do tile(g1, name) end

	local ids = table.GetKeys(P.CustomIcons)
	table.sort(ids, function(a, b) return (tonumber(a:sub(3)) or 0) < (tonumber(b:sub(3)) or 0) end)
	local create = canCreate() and not opts.noCreate
	if #ids > 0 or create then
		head(P.L("ic_custom") .. "  (" .. #ids .. "/" .. (P.MaxCustomIcons or 64) .. ")")
		local g2 = newGrid()
		for _, id in ipairs(ids) do
			tile(g2, id, canCreate() and not opts.noCreate and function()
				UI.Popup({
					{ P.L("ic_edit"), "wrench", function()
						m:Close()
						UI.IconEditor(id, function(newId) onDone(newId) end)
					end },
					{ P.L("ic_delete"), "skull", function()
						UI.Confirm(P.L("ic_delete"), P.L("ic_delete_q"), function()
							P.Request("icon_delete", { id = id })
							m:Close()
						end, true)
					end, true },
				})
			end or nil)
		end
		if create then
			local b = g2:Add("DButton")
			b:SetText("")
			b:SetSize(S(48), S(48))
			b:SetTooltip(P.L("ic_create"))
			b.Paint = function(s, w, h)
				UI.Round(0, 0, w, h, S(12), s:IsHovered() and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or C.panel2, s:IsHovered() and C.bronze or C.lineL)
				local c = s:IsHovered() and C.bronzeL or C.muted
				UI.Rect(w / 2 - S(8), h / 2 - 1, S(16), 2, c)
				UI.Rect(w / 2 - 1, h / 2 - S(8), 2, S(16), c)
			end
			b.DoClick = function()
				m:Close()
				UI.IconEditor(nil, function(id) onDone(id) end)
			end
		end
	end

	local hint = vgui.Create("DPanel", m.foot)
	hint:Dock(FILL)
	hint.Paint = function(_, w, h)
		if create then UI.Text(P.L("ic_picker_hint"), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	return m
end
