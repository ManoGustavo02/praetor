-- Praetor: the main menu. A sidebar split in categories and one tab at a time.
-- Tabs live in cl_tab_*.lua and register themselves with P.AddTab.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

P.Tabs = P.Tabs or {}
P.TabCats = {
	{ id = "overview", label = "cat_overview" },
	{ id = "moderation", label = "cat_moderation" },
	{ id = "management", label = "cat_management" },
	{ id = "server", label = "cat_server" },
}

-- def: { cat, icon, order, can = function() return bool end, build = function(panel, data) end }
function P.AddTab(id, def)
	def.id = id
	def.order = def.order or 50
	P.Tabs[id] = def
end

local function visibleTabs(cat)
	local out = {}
	for _, t in pairs(P.Tabs) do
		if t.cat == cat and (not t.can or t.can()) then out[#out + 1] = t end
	end
	table.sort(out, function(a, b) return a.order < b.order end)
	return out
end

-- ------------------------------------------------------------------ helpers for tabs

-- horizontal bar of controls docked at the top of a tab
function UI.Toolbar(parent, h)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(h or S(34))
	p:DockMargin(0, 0, 0, S(8))
	p.Paint = nil
	return p
end

-- adds a control to a toolbar (left by default)
function UI.Tool(bar, ctl, w, side)
	ctl:SetParent(bar)
	ctl:Dock(side or LEFT)
	if w then ctl:SetWide(w) end
	ctl:DockMargin(side == RIGHT and S(6) or 0, 0, side == RIGHT and 0 or S(6), 0)
	return ctl
end

-- Simple table. cols: { { title, width, align } } ; width <= 1 is a fraction of the free space.
function UI.Table(parent, cols)
	local t = vgui.Create("DPanel", parent)
	t.cols = cols
	t.Paint = nil
	local head = vgui.Create("DPanel", t)
	head:Dock(TOP)
	head:SetTall(S(24))
	t.scroll = UI.Scroll(t)
	t.scroll:Dock(FILL)

	function t:ColX(w)
		local fixed, frac = 0, 0
		for _, c in ipairs(self.cols) do
			if c[2] > 1 then fixed = fixed + S(c[2]) else frac = frac + c[2] end
		end
		local free = math.max(0, w - fixed - S(16))
		local xs, x = {}, S(8)
		for i, c in ipairs(self.cols) do
			local cw = c[2] > 1 and S(c[2]) or math.floor(free * c[2] / math.max(frac, 0.0001))
			xs[i] = { x = x, w = cw }
			x = x + cw
		end
		return xs
	end

	head.Paint = function(_, w, h)
		local xs = t:ColX(w)
		for i, c in ipairs(t.cols) do
			local a = c[3] or TEXT_ALIGN_LEFT
			local x = a == TEXT_ALIGN_RIGHT and (xs[i].x + xs[i].w - S(6)) or xs[i].x
			UI.Text(c[1], "Praetor.Tiny", x, h / 2, C.dim, a, TEXT_ALIGN_CENTER)
		end
		UI.Rect(0, h - 1, w, 1, C.line)
	end

	function t:Clear()
		self.scroll:Clear()
		self.count = 0
	end

	-- cells: strings, { text, color }, or function(x, y, w, h, row)
	function t:AddRow(cells, opts)
		opts = opts or {}
		self.count = (self.count or 0) + 1
		local row = vgui.Create("DButton", self.scroll)
		row:SetText("")
		row:Dock(TOP)
		row:SetTall(opts.h or S(34))
		row:DockMargin(0, 0, 0, S(2))
		row.data = opts.data
		local odd = self.count % 2 == 0
		row.Paint = function(s, w, h)
			UI.Round(0, 0, w, h, S(5), s:IsHovered() and C.hover or (odd and C.panel2 or C.panel))
			if opts.accent then UI.Round(0, S(4), S(3), h - S(8), S(1), opts.accent) end
			local xs = t:ColX(w)
			for i, cell in ipairs(cells) do
				local col = xs[i]
				if col then
					local a = t.cols[i][3] or TEXT_ALIGN_LEFT
					if isfunction(cell) then
						cell(col.x, 0, col.w, h, s)
					else
						local text, c = cell, C.text
						if istable(cell) then text, c = cell[1], cell[2] or C.text end
						text = UI.Fit(tostring(text or ""), "Praetor.Small", col.w - S(8))
						local x = a == TEXT_ALIGN_RIGHT and (col.x + col.w - S(6)) or col.x
						UI.Text(text, "Praetor.Small", x, h / 2, c, a, TEXT_ALIGN_CENTER)
					end
				end
			end
		end
		if opts.onClick then row.DoClick = function() UI.Sound("click") opts.onClick(row) end end
		if opts.onRight then row.DoRightClick = function() opts.onRight(row) end end
		return row
	end

	-- empty list: a big faded icon, the message and an optional hint below
	function t:Empty(text, icon, hint)
		local l = vgui.Create("DPanel", self.scroll)
		l:Dock(TOP)
		l:SetTall(S(hint and 190 or 170))
		l.Paint = function(_, w, h)
			local cy = S(40)
			UI.Round(w / 2 - S(36), cy - S(10), S(72), S(72), S(36), C.panel2)
			UI.Icon(icon or "scroll", w / 2 - 24, cy + S(26) - 24, 48, Color(255, 255, 255, 110))
			UI.Text(text or P.L("ui_empty"), "Praetor.BodyB", w / 2, cy + S(84), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if hint then UI.Text(UI.Fit(hint, "Praetor.Small", w - S(40)), "Praetor.Small", w / 2, cy + S(106), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
		end
	end

	return t
end

-- page buttons docked at the bottom of a tab, centred: "<  Page 2  >".
-- pager:SetPage(n, hasNext) ; onChange(newPage)
function UI.Pager(parent, onChange)
	local bar = vgui.Create("DPanel", parent)
	bar:Dock(BOTTOM)
	bar:SetTall(S(32))
	bar:DockMargin(0, S(6), 0, 0)
	bar.Paint = nil
	bar.page = 0
	bar.hasNext = true
	local mid = vgui.Create("DPanel", bar)
	mid:SetSize(S(210), S(32))
	mid.Paint = function(_, w, h)
		UI.Round(S(40), 0, w - S(80), h, S(6), C.panel)
		UI.Text(P.L("ui_page") .. " " .. (bar.page + 1), "Praetor.SmallB", w / 2, h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local prev = UI.Button(mid, "", "ghost", nil, function()
		if bar.page > 0 then onChange(bar.page - 1) end
	end)
	prev:SetPos(0, 0)
	prev:SetSize(S(36), S(32))
	local nxt = UI.Button(mid, "", "ghost", nil, function()
		if bar.hasNext then onChange(bar.page + 1) end
	end)
	nxt:SetPos(S(210) - S(36), 0)
	nxt:SetSize(S(36), S(32))
	local function arrow(dir)
		return function(s, w, h)
			surface.SetDrawColor(s:IsEnabled() and C.ivory or C.dim)
			local cx, cy = w / 2, h / 2
			for i = 0, 4 do
				local x = dir < 0 and (cx - 2 + i) or (cx + 2 - i)
				surface.DrawRect(x, cy - i, 1, i * 2 + 1)
			end
		end
	end
	prev.PaintOver = arrow(-1)
	nxt.PaintOver = arrow(1)
	bar.PerformLayout = function(s, w, h) mid:SetPos(math.floor((w - mid:GetWide()) / 2), 0) end
	function bar:SetPage(n, hasNext)
		self.page = n or 0
		self.hasNext = hasNext ~= false
		prev:SetEnabled(self.page > 0)
		nxt:SetEnabled(self.hasNext)
	end
	bar:SetPage(0, true)
	return bar
end

-- a framed block with a title, used to group settings and details
function UI.Section(parent, title, sub)
	local h = UI.Header(parent, title, sub)
	h:Dock(TOP)
	h:DockMargin(0, S(10), 0, S(6))
	return h
end

-- small stat tile
function UI.Stat(parent, label, valueFn, icon)
	local p = vgui.Create("DPanel", parent)
	p.Paint = function(_, w, h)
		UI.Tablet(0, 0, w, h, C.panel2, C.line)
		if icon then UI.Icon(icon, S(12), (h - 32) / 2, 32) end
		local x = icon and S(54) or S(12)
		UI.Text(label, "Praetor.Tiny", x, S(10), C.muted)
		UI.Text(tostring(valueFn()), "Praetor.Big", x, S(26), C.ivory)
	end
	return p
end

-- ------------------------------------------------------------------ frame

local function tabTitle(t) return P.L("tab_" .. t.id) end

function P.OpenMenu(tabId, data)
	if not P.MyHas("menu") and not P.IsOwner(LocalPlayer()) then
		P.Toast(P.L("toast_error"), P.L("err_no_perm", { S = "menu" }), "warn")
		return
	end
	local f = P.Menu
	if not IsValid(f) then
		f = P.BuildMenu()
	end
	f:Show()
	f:MakePopup()
	local id = tabId
	if not id or not P.Tabs[id] or (P.Tabs[id].can and not P.Tabs[id].can()) then id = f.current or "players" end
	f:SelectTab(id, data)
end

function P.CloseMenu()
	if IsValid(P.Menu) then
		UI.Sound("close")
		P.Menu:Remove()
	end
	P.Request("logs_watch", { on = false })
end

function P.BuildMenu()
	local w = math.min(ScrW() - S(30), S(1220))
	local h = math.min(ScrH() - S(30), S(790))
	local f = vgui.Create("EditablePanel")
	P.Menu = f
	f:SetSize(w, h)
	f:Center()
	f:SetAlpha(0)
	f:AlphaTo(255, 0.15)
	UI.Sound("open")
	local side = w < S(1000) and S(196) or S(232)

	f.Paint = function(_, pw, ph)
		UI.Tablet(0, 0, pw, ph, C.bg, C.line)
		-- sidebar
		draw.RoundedBoxEx(S(7), 1, 1, side, ph - 2, C.panel, true, false, true, false)
		UI.Rect(side, 0, 1, ph, C.line)
		UI.Text("PRAETOR", "Praetor.Logo", side / 2, S(12), C.ivory, TEXT_ALIGN_CENTER)
		UI.Round(side / 2 - S(14), S(46), S(28), S(3), S(1), C.bronze)
		UI.Text("Admin System  v" .. (P.Version or "1.0.0"), "Praetor.Tiny", side / 2, S(53), C.dim, TEXT_ALIGN_CENTER)
		UI.Rule(S(12), S(72), side - S(24), C.line)
		-- line under the tab title, all the way to the close button
		UI.Rect(side + S(18), S(59), pw - side - S(36), 1, C.line)
	end
	f.OnKeyCodePressed = function(_, key)
		if key == KEY_ESCAPE then P.CloseMenu() end
	end
	f.Think = function(s)
		if input.IsKeyDown(KEY_ESCAPE) and gui.IsGameUIVisible() and not IsValid(vgui.GetKeyboardFocus()) then
			gui.HideGameUI()
			P.CloseMenu()
		end
	end

	local nav = UI.Scroll(f)
	nav:SetPos(S(8), S(80))
	nav:SetSize(side - S(16), h - S(80) - S(70))

	-- me, at the bottom of the sidebar
	local me = vgui.Create("DPanel", f)
	me:SetPos(S(8), h - S(64))
	me:SetSize(side - S(16), S(56))
	local av = UI.FramedAvatar(me, S(40), LocalPlayer())
	av:SetPos(S(6), S(8))
	me.Paint = function(_, mw, mh)
		UI.Notch(0, 0, mw, mh, S(4), C.panel2, C.line)
		local lp = LocalPlayer()
		UI.Text(UI.Fit(lp:Nick(), "Praetor.BodyB", mw - S(60)), "Praetor.BodyB", S(54), S(6), C.ivory)
		local style, icon = UI.PlayerRankStyle(lp)
		UI.Badge(style, icon, "Praetor.Tiny", S(54), S(28), S(20))
	end

	local content = vgui.Create("DPanel", f)
	content:SetPos(side + S(18), S(66))
	content:SetSize(w - side - S(36), h - S(80))
	content.Paint = nil
	f.content = content

	local titleBar = vgui.Create("DPanel", f)
	titleBar:SetPos(side + S(18), S(12))
	titleBar:SetSize(w - side - S(64), S(48))
	titleBar.Paint = function(_, tw, th)
		local t = P.Tabs[f.current or ""]
		if not t then return end
		if t.icon then UI.Icon(t.icon, 0, S(6), 32) end
		UI.Text(tabTitle(t), "Praetor.H1", S(42), S(2), C.ivory)
		UI.Text(UI.Fit(P.L("tabsub_" .. t.id), "Praetor.Small", tw - S(42)), "Praetor.Small", S(42), S(30), C.muted)
	end

	local close = vgui.Create("DButton", f)
	close:SetText("")
	close:SetSize(S(30), S(30))
	close:SetPos(w - S(42), S(14))
	close.Paint = function(s, cw, ch)
		if s:IsHovered() then UI.Round(0, 0, cw, ch, S(6), Color(C.crimson.r, C.crimson.g, C.crimson.b, 60)) end
		local col = s:IsHovered() and C.crimsonL or C.muted
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(14), 2, 45)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(14), 2, -45)
	end
	close.DoClick = function() P.CloseMenu() end

	function f:BuildNav()
		nav:Clear()
		for _, cat in ipairs(P.TabCats) do
			local tabs = visibleTabs(cat.id)
			if #tabs > 0 then
				local head = vgui.Create("DPanel", nav)
				head:Dock(TOP)
				head:SetTall(S(26))
				head:DockMargin(0, S(6), 0, S(2))
				head.Paint = function(_, hw, hh)
					UI.Text(P.Upper(P.L(cat.label)), "Praetor.Tiny", S(6), hh - S(4), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				end
				for _, t in ipairs(tabs) do
					local b = vgui.Create("DButton", nav)
					b:SetText("")
					b:Dock(TOP)
					b:SetTall(S(36))
					b:DockMargin(0, 0, 0, S(2))
					b.anim = 0
					b.Paint = function(s, bw, bh)
						local on = f.current == t.id
						s.anim = UI.Lerp(s.anim, s:IsHovered() and 1 or 0, 14)
						if on then
							UI.Round(0, 0, bw, bh, S(6), Color(C.bronze.r, C.bronze.g, C.bronze.b, 38))
							UI.Round(0, S(8), S(3), bh - S(16), S(1), C.bronze)
						elseif s.anim > 0.01 then
							UI.Round(0, 0, bw, bh, S(6), Color(255, 255, 255, 10 * s.anim))
						end
						UI.Icon(t.icon, S(12), (bh - 16) / 2, 16, on and color_white or Color(255, 255, 255, 170))
						UI.Text(tabTitle(t), on and "Praetor.BodyB" or "Praetor.Body", S(36), bh / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						local badge = t.badge and t.badge()
						if badge and badge > 0 then
							local txt = tostring(badge)
							surface.SetFont("Praetor.Tiny")
							local tw2 = surface.GetTextSize(txt) + S(12)
							UI.Round(bw - tw2 - S(8), (bh - S(20)) / 2, tw2, S(20), S(10), C.crimson)
							UI.Text(txt, "Praetor.Tiny", bw - S(8) - tw2 / 2, bh / 2, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						end
					end
					b.DoClick = function()
						if f.current ~= t.id then UI.Sound("tab") f:SelectTab(t.id) end
					end
				end
			end
		end
	end

	function f:SelectTab(id, data)
		local t = P.Tabs[id]
		if not t then return end
		if self.current == "logs" and id ~= "logs" then P.Request("logs_watch", { on = false }) end
		self.current = id
		content:Clear()
		local panel = vgui.Create("DPanel", content)
		panel:Dock(FILL)
		panel.Paint = nil
		self.tab = panel
		local ok, err = pcall(t.build, panel, data or {})
		if not ok then
			ErrorNoHalt("[Praetor] tab '" .. id .. "': " .. tostring(err) .. "\n")
			local l = UI.Label(panel, "Error: " .. tostring(err), "Praetor.Small", C.crimsonL)
			l:Dock(TOP)
		end
	end

	-- rebuild the visible tab (after a sync, for example)
	function f:Refresh()
		self:BuildNav()
		if self.current then
			local t = P.Tabs[self.current]
			if t and (not t.can or t.can()) and not t.noAutoRefresh then self:SelectTab(self.current) end
		end
	end

	f:BuildNav()
	return f
end

hook.Add("Praetor.Synced", "Praetor.Menu", function()
	if IsValid(P.Menu) then P.Menu:BuildNav() end
end)

concommand.Add("praetor_menu_close", function() P.CloseMenu() end)
