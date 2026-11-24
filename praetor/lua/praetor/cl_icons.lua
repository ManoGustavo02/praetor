-- Praetor: custom pixel-art icons on the client. Draws them (UI.Icon knows the
-- "c_" names), the icon picker with the "Create icon" tile, and the editor.
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

local function buildRuns(icon)
	local out = {}
	local pal = {}
	for i, h in ipairs(icon.pal or {}) do pal[i - 1] = { hexColor(h) } end
	for y = 0, N - 1 do
		local x = 0
		while x < N do
			local ch = icon.px:sub(y * N + x + 1, y * N + x + 1)
			if ch ~= "." then
				local len = 1
				while x + len < N and icon.px:sub(y * N + x + len + 1, y * N + x + len + 1) == ch do len = len + 1 end
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
	local k = size / N
	local tr, tg, tb, ta = 255, 255, 255, 255
	if col then tr, tg, tb, ta = col.r, col.g, col.b, col.a or 255 end
	for _, run in ipairs(r) do
		local x0 = x + math.floor(run[1] * k)
		local x1 = x + math.floor((run[1] + run[3]) * k)
		local y0 = y + math.floor(run[2] * k)
		local y1 = y + math.floor((run[2] + 1) * k)
		surface.SetDrawColor(run[4] * tr / 255, run[5] * tg / 255, run[6] * tb / 255, ta)
		surface.DrawRect(x0, y0, x1 - x0, y1 - y0)
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

-- 16x16 grid (index y * 16 + x + 1 -> Color or nil) from any icon
local function readIcon(name)
	local grid = {}
	if name:sub(1, 2) == "c_" then
		local icon = P.CustomIcons[name]
		if not icon then return grid end
		for i = 1, N * N do
			local ch = icon.px:sub(i, i)
			local h = ch ~= "." and icon.pal[(tonumber(ch, 16) or 0) + 1]
			if h then grid[i] = Color(hexColor(h)) end
		end
		return grid
	end
	-- built-in PNG (16x16 art scaled up): sample the middle of every big pixel
	local mat = UI.Mat("praetor/icons/" .. name .. ".png")
	if mat:IsError() then return grid end
	local tex = mat:GetTexture("$basetexture")
	if not tex then return grid end
	local step = tex:Width() / N
	for y = 0, N - 1 do
		for x = 0, N - 1 do
			local ok, c = pcall(tex.GetColor, tex, math.floor(x * step + step / 2), math.floor(y * step + step / 2))
			if ok and c and c.a > 127 then grid[y * N + x + 1] = Color(c.r, c.g, c.b) end
		end
	end
	return grid
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

function UI.IconEditor(editId, onSaved)
	if not canCreate() then return end
	local m = UI.Modal(P.L("ic_editor"), S(640), S(520))
	local grid = editId and readIcon(editId) or {}
	local undo = {}
	local tool = "pencil"
	local mirror = false
	local color = Color(hexColor("e8763a"))
	local recent = {}

	local function snapshot()
		local copy = {}
		for i = 1, N * N do copy[i] = grid[i] end
		undo[#undo + 1] = copy
		if #undo > 40 then table.remove(undo, 1) end
	end

	-- canvas
	local cell = math.floor(math.min(S(22), (m:GetTall() - S(120)) / N))
	local canvas = vgui.Create("DPanel", m.body)
	canvas:SetSize(cell * N + 2, cell * N + 2)
	canvas:Dock(LEFT)
	canvas:SetCursor("crosshair")
	canvas.Paint = function(s, w, h)
		-- checkerboard so empty pixels are visible
		for y = 0, N - 1 do
			for x = 0, N - 1 do
				local dark = (x + y) % 2 == 0
				UI.Rect(1 + x * cell, 1 + y * cell, cell, cell, dark and Color(34, 36, 43) or Color(42, 44, 52))
				local c = grid[y * N + x + 1]
				if c then UI.Rect(1 + x * cell, 1 + y * cell, cell, cell, c) end
			end
		end
		if mirror then UI.Rect(1 + N / 2 * cell, 1, 1, h - 2, Color(255, 255, 255, 60)) end
		local mx, my = s:CursorPos()
		local cx, cy = math.floor((mx - 1) / cell), math.floor((my - 1) / cell)
		if s:IsHovered() and cx >= 0 and cy >= 0 and cx < N and cy < N then
			UI.Outline(1 + cx * cell, 1 + cy * cell, cell, cell, Color(255, 255, 255, 160))
		end
		UI.Outline(0, 0, w, h, C.line)
	end

	local function set(x, y, c)
		grid[y * N + x + 1] = c
		if mirror then grid[y * N + (N - 1 - x) + 1] = c end
	end

	local function fill(x, y, c)
		local target = grid[y * N + x + 1]
		local key = function(v) return v and hexOf(v) or "" end
		local tk = key(target)
		if tk == key(c) then return end
		local stack = { { x, y } }
		while #stack > 0 do
			local p = table.remove(stack)
			local px, py = p[1], p[2]
			if px >= 0 and py >= 0 and px < N and py < N and key(grid[py * N + px + 1]) == tk then
				grid[py * N + px + 1] = c
				stack[#stack + 1] = { px + 1, py }
				stack[#stack + 1] = { px - 1, py }
				stack[#stack + 1] = { px, py + 1 }
				stack[#stack + 1] = { px, py - 1 }
			end
		end
	end

	local pickSwatch
	local function useColor(c)
		color = Color(c.r, c.g, c.b)
		local h = hexOf(color)
		for i, v in ipairs(recent) do if v == h then table.remove(recent, i) break end end
		table.insert(recent, 1, h)
		while #recent > 8 do table.remove(recent) end
	end

	local function apply(btn)
		local mx, my = canvas:CursorPos()
		local x, y = math.floor((mx - 1) / cell), math.floor((my - 1) / cell)
		if x < 0 or y < 0 or x >= N or y >= N then return end
		local t = btn == MOUSE_RIGHT and "eraser" or tool
		if t == "pencil" then set(x, y, Color(color.r, color.g, color.b))
		elseif t == "eraser" then set(x, y, nil)
		elseif t == "fill" then fill(x, y, Color(color.r, color.g, color.b))
		elseif t == "picker" then
			local c = grid[y * N + x + 1]
			if c then useColor(c) end
			tool = "pencil"
		end
	end

	canvas.OnMousePressed = function(s, btn)
		snapshot()
		s.down = btn
		s:MouseCapture(true)
		apply(btn)
	end
	canvas.OnMouseReleased = function(s)
		s.down = nil
		s:MouseCapture(false)
	end
	canvas.Think = function(s)
		if s.down and (s.down == MOUSE_RIGHT or tool == "pencil" or tool == "eraser") then
			if not input.IsMouseDown(s.down) then s.down = nil s:MouseCapture(false) return end
			apply(s.down)
		end
	end

	-- right column
	local side = vgui.Create("DPanel", m.body)
	side:Dock(FILL)
	side:DockMargin(S(14), 0, 0, 0)
	side.Paint = nil

	local function sectionLabel(text)
		local l = vgui.Create("DPanel", side)
		l:Dock(TOP)
		l:SetTall(S(18))
		l:DockMargin(0, S(4), 0, S(4))
		l.Paint = function(_, w, h) UI.Text(P.Upper(text), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end

	-- tools
	sectionLabel(P.L("ic_tools"))
	local tools = vgui.Create("DIconLayout", side)
	tools:Dock(TOP)
	tools:SetSpaceX(S(4))
	tools:SetSpaceY(S(4))
	local toolList = {
		{ "pencil", "ic_pencil", "wrench" }, { "eraser", "ic_eraser", "leaf" },
		{ "fill", "ic_fill", "scroll" }, { "picker", "ic_picker", "eye" },
	}
	for _, t in ipairs(toolList) do
		local b = tools:Add("PraetorButton")
		b:Setup(P.L(t[2]), "ghost")
		b:SetFont("Praetor.Small")
		b:SetSize(S(84), S(30))
		b.Think = function(s) s.kind = tool == t[1] and "active" or "ghost" end
		b.DoClick = function() tool = t[1] end
	end
	local mir = tools:Add("PraetorButton")
	mir:Setup(P.L("ic_mirror"), "ghost")
	mir:SetFont("Praetor.Small")
	mir:SetSize(S(84), S(30))
	mir.Think = function(s) s.kind = mirror and "active" or "ghost" end
	mir.DoClick = function() mirror = not mirror end
	local und = tools:Add("PraetorButton")
	und:Setup(P.L("ic_undo"), "ghost")
	und:SetFont("Praetor.Small")
	und:SetSize(S(84), S(30))
	und.DoClick = function()
		local last = table.remove(undo)
		if last then grid = last end
	end

	-- colours
	sectionLabel(P.L("ic_color"))
	local pal = vgui.Create("DIconLayout", side)
	pal:Dock(TOP)
	pal:SetSpaceX(S(4))
	pal:SetSpaceY(S(4))
	local sw = S(26)
	local function swatch(parent, getHex)
		local b = parent:Add("DButton")
		b:SetText("")
		b:SetSize(sw, sw)
		b.Paint = function(s, w, h)
			local hx = getHex()
			if not hx then UI.Round(0, 0, w, h, S(4), C.panel2, C.line) return end
			local r, g, bl = hexColor(hx)
			local cur = hexOf(color) == hx
			UI.Round(0, 0, w, h, S(4), Color(r, g, bl), (cur or s:IsHovered()) and color_white or C.line)
		end
		b.DoClick = function()
			local hx = getHex()
			if hx then useColor(Color(hexColor(hx))) if tool == "eraser" or tool == "picker" then tool = "pencil" end end
		end
		return b
	end
	for _, hx in ipairs(PALETTE) do swatch(pal, function() return hx end) end

	-- current colour + custom colour + recent colours
	local cur = vgui.Create("DPanel", side)
	cur:Dock(TOP)
	cur:SetTall(S(34))
	cur:DockMargin(0, S(6), 0, 0)
	cur.Paint = nil
	pickSwatch = vgui.Create("DButton", cur)
	pickSwatch:SetText("")
	pickSwatch:Dock(LEFT)
	pickSwatch:SetWide(S(34))
	pickSwatch.Paint = function(s, w, h) UI.Round(0, 0, w, h, S(5), color, s:IsHovered() and color_white or C.lineL) end
	pickSwatch.DoClick = function() UI.PickColor(color, function(c) useColor(c) tool = "pencil" end) end
	pickSwatch:SetTooltip(P.L("ui_pick_color"))
	local rec = vgui.Create("DIconLayout", cur)
	rec:Dock(FILL)
	rec:DockMargin(S(8), S(4), 0, 0)
	rec:SetSpaceX(S(4))
	for i = 1, 8 do swatch(rec, function() return recent[i] end) end

	-- start from another icon / clear
	sectionLabel(P.L("ic_start"))
	local row = vgui.Create("DPanel", side)
	row:Dock(TOP)
	row:SetTall(S(30))
	row.Paint = nil
	local imp = UI.Button(row, P.L("ic_import"), "ghost", nil, function()
		UI.PickIcon(nil, function(name)
			snapshot()
			grid = readIcon(name)
		end, { noCreate = true })
	end)
	imp:SetFont("Praetor.Small")
	imp:Dock(FILL)
	local clr = UI.Button(row, P.L("ic_clear"), "ghost", nil, function() snapshot() grid = {} end)
	clr:SetFont("Praetor.Small")
	clr:Dock(RIGHT)
	clr:SetWide(S(80))
	clr:DockMargin(S(4), 0, 0, 0)

	-- name + preview
	sectionLabel(P.L("ic_name"))
	local name = UI.Entry(side, P.L("ic_name"), editId and P.CustomIcons[editId] and P.CustomIcons[editId].n or "")
	name:Dock(TOP)
	name:SetTall(S(30))

	local prev = vgui.Create("DPanel", side)
	prev:Dock(FILL)
	prev:DockMargin(0, S(8), 0, 0)
	prev.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(6), C.bg, C.line)
		-- the drawing at the sizes it is used: 16, 32, 64
		local x = S(10)
		for _, sz in ipairs({ 16, 32, 64 }) do
			local y = math.floor((h - sz) / 2)
			local k = sz / N
			for i = 1, N * N do
				local c = grid[i]
				if c then
					local px, py = (i - 1) % N, math.floor((i - 1) / N)
					UI.Rect(x + math.floor(px * k), y + math.floor(py * k), math.max(1, math.floor((px + 1) * k) - math.floor(px * k)), math.max(1, math.floor((py + 1) * k) - math.floor(py * k)), c)
				end
			end
			x = x + sz + S(14)
		end
		UI.Text(P.L("ic_hint"), "Praetor.Tiny", w - S(8), h - S(6), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	-- footer
	local saveBtn = UI.Button(m.foot, P.L("ic_save"), "primary", nil, function()
		local palette, index, px = {}, {}, {}
		for i = 1, N * N do
			local c = grid[i]
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
		if #palette > 16 then P.Toast(P.L("ic_editor"), P.L("ic_colors"), "warn", 5) return end
		savedCallback = function(id)
			if onSaved then onSaved(id) end
		end
		P.Request("icon_save", { id = editId, n = name:GetValue(), px = table.concat(px), pal = palette })
		m:Close()
	end)
	saveBtn:Dock(RIGHT)
	saveBtn:SetWide(S(140))
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
			UI.Round(0, 0, w, h, S(6), (s:IsHovered() or name == cur) and C.panel3 or C.panel2, name == cur and C.bronze or C.line)
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
				UI.Round(0, 0, w, h, S(6), s:IsHovered() and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or C.panel2, s:IsHovered() and C.bronze or C.lineL)
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
