-- Praetor: interface controls (buttons, fields, switches, dropdowns, style
-- editor, dialogs and forms). Everything is drawn by hand to match the theme.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

-- ==================================================================== button
do
	local PANEL = {}

	function PANEL:Init()
		self:SetText("")
		self.label = ""
		self.kind = "ghost"
		self.hov = 0
		self.font = "Praetor.BodyB"
		self:SetTall(S(34))
	end

	function PANEL:Setup(label, kind, icon)
		self.label = label or ""
		self.kind = kind or "ghost"
		self.icon = icon
		return self
	end

	function PANEL:SetLabel(l) self.label = l end
	function PANEL:SetFont(f) self.font = f end

	function PANEL:SizeToLabel(pad)
		surface.SetFont(self.font)
		local tw = surface.GetTextSize(self.label)
		local iw = (self.icon and (16 + S(6)) or 0) + ((self.kind == "toggle_on" or self.kind == "toggle_off") and S(34) or 0)
		self:SetWide(tw + iw + (pad or S(18)) * 2)
		return self
	end

	function PANEL:OnCursorEntered() if self:IsEnabled() then UI.Sound("click") end end

	-- kinds: primary (accent), danger (red, for confirmations), subtle (no box),
	-- active (selected), ghost (default box), and for the player quick actions:
	-- action, action_danger (same box, red text) and action_on (a toggle that is on)
	function PANEL:Paint(w, h)
		local en = self:IsEnabled()
		self.hov = UI.Lerp(self.hov, (self:IsHovered() and en) and 1 or 0, 14)
		local down = self:IsDown() and 1 or 0
		local k, fill, border, txt = self.kind
		local iconCol = color_white
		if k == "primary" then
			fill = P.LerpColor(self.hov, C.bronze, C.bronzeL)
			border = nil
			txt = color_white
		elseif k == "danger" then
			fill = P.LerpColor(self.hov, C.crimson, C.crimsonL)
			border = nil
			txt = color_white
		elseif k == "subtle" then
			fill = P.LerpColor(self.hov, Color(0, 0, 0, 0), C.panel3)
			border = nil
			txt = P.LerpColor(self.hov, C.muted, C.ivory)
		elseif k == "active" or k == "action_on" then
			fill = P.LerpColor(self.hov, Color(C.bronze.r, C.bronze.g, C.bronze.b, 45), Color(C.bronze.r, C.bronze.g, C.bronze.b, 70))
			border = C.bronze
			txt = C.bronzeL
		elseif k == "action_danger" then
			fill = P.LerpColor(self.hov, C.panel2, Color(C.crimson.r, C.crimson.g, C.crimson.b, 50))
			border = P.LerpColor(self.hov, C.line, C.crimson)
			txt = C.crimsonL
		else -- ghost / action
			fill = P.LerpColor(self.hov, C.panel2, C.hover)
			border = P.LerpColor(self.hov, C.line, C.lineL)
			txt = C.ivory
		end
		if not en then fill = ColorAlpha(fill, 90) txt = ColorAlpha(txt, 90) iconCol = Color(255, 255, 255, 90) end
		-- on / off buttons: a small switch in front of the label says the state
		if k == "toggle_on" or k == "toggle_off" then
			local on = k == "toggle_on"
			self.tog = UI.Lerp(self.tog or (on and 1 or 0), on and 1 or 0, 14)
			local t = self.tog
			UI.Round(0, down, w, h - down, S(5), P.LerpColor(t, P.LerpColor(self.hov, C.panel2, C.hover), Color(C.bronze.r, C.bronze.g, C.bronze.b, 40 + 25 * self.hov)), P.LerpColor(t, C.line, C.bronze))
			surface.SetFont(self.font)
			local sw, sh = S(26), S(14)
			local iw2 = self.icon and (16 + S(6)) or 0
			local tw = surface.GetTextSize(self.label)
			local total = sw + S(8) + iw2 + tw
			local x = math.max(S(8), math.floor((w - total) / 2))
			local sy = math.floor((h - sh) / 2) + down
			UI.Round(x, sy, sw, sh, sh / 2, P.LerpColor(t, C.panel3, C.bronze))
			UI.Round(x + 2 + (sw - sh) * t, sy + 2, sh - 4, sh - 4, (sh - 4) / 2, P.LerpColor(t, C.muted, color_white))
			x = x + sw + S(8)
			if self.icon then
				UI.Icon(self.icon, x, math.floor((h - 16) / 2) + down, 16, on and color_white or Color(255, 255, 255, 150))
				x = x + iw2
			end
			draw.SimpleText(UI.Fit(self.label, self.font, w - x - S(6)), self.font, x, h / 2 + down, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return true
		end
		UI.Round(0, down, w, h - down, S(5), fill, border)
		surface.SetFont(self.font)
		local tw = surface.GetTextSize(self.label)
		local iw = self.icon and (16 + (self.label ~= "" and S(6) or 0)) or 0
		local x = math.floor((w - tw - iw) / 2)
		if self.icon then
			UI.Icon(self.icon, x, math.floor((h - 16) / 2) + down, 16, iconCol)
			x = x + iw
		end
		local label = UI.Fit(self.label, self.font, w - iw - S(10))
		draw.SimpleText(label, self.font, x, h / 2 + down, txt, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- small dot on toggles that are on
		if k == "action_on" then UI.Round(w - S(10), S(5), S(5), S(5), S(2), C.bronzeL) end
		return true
	end

	vgui.Register("PraetorButton", PANEL, "DButton")
end

-- on / off button: UI.Toggle(parent, label, icon, value, function(newValue, button) end)
function UI.Toggle(parent, label, icon, value, onChange)
	local b = vgui.Create("PraetorButton", parent)
	b.value = value == true
	b:Setup(label, b.value and "toggle_on" or "toggle_off", icon)
	b.SetValue = function(s, v) s.value = v == true s:Setup(s.label, s.value and "toggle_on" or "toggle_off", s.icon) end
	b.GetValue = function(s) return s.value end
	b.DoClick = function(s)
		s:SetValue(not s.value)
		if onChange then onChange(s.value, s) end
	end
	return b
end

function UI.Button(parent, label, kind, icon, fn)
	local b = vgui.Create("PraetorButton", parent)
	b:Setup(label, kind, icon)
	if fn then b.DoClick = function(s) fn(s) end end
	return b
end

-- ==================================================================== text entry
do
	local PANEL = {}

	function PANEL:Init()
		self:SetFont("Praetor.Body")
		self:SetTall(S(34))
		self:SetTextColor(C.ivory)
		self:SetCursorColor(C.bronzeL)
		self:SetHighlightColor(Color(92, 132, 255, 90))
		self:SetPlaceholderColor(C.dim)
		self:SetDrawLanguageID(false)
		self.focus = 0
	end

	function PANEL:Paint(w, h)
		self.focus = UI.Lerp(self.focus, self:HasFocus() and 1 or 0, 14)
		UI.Notch(0, 0, w, h, S(4), C.bg, P.LerpColor(self.focus, C.line, C.bronze))
		self:DrawTextEntryText(C.ivory, Color(92, 132, 255, 110), C.bronzeL)
		if self:GetText() == "" and self:GetPlaceholderText() and self:GetPlaceholderText() ~= "" and not self:HasFocus() then
			local x = self:IsMultiline() and S(6) or S(6)
			draw.SimpleText(self:GetPlaceholderText(), self:GetFont(), x, self:IsMultiline() and S(6) or h / 2, C.dim, TEXT_ALIGN_LEFT, self:IsMultiline() and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
		end
	end

	function PANEL:PerformLayout()
		self:SetTextInset(S(6), 0)
	end

	vgui.Register("PraetorEntry", PANEL, "DTextEntry")
end

function UI.Entry(parent, placeholder, value, onChange)
	local e = vgui.Create("PraetorEntry", parent)
	e:SetPlaceholderText(placeholder or "")
	if value then e:SetValue(value) end
	if onChange then e.OnChange = function(s) onChange(s:GetValue(), s) end end
	return e
end

-- ==================================================================== label
function UI.Label(parent, text, font, col)
	local l = vgui.Create("DLabel", parent)
	l:SetFont(font or "Praetor.Body")
	l:SetTextColor(col or C.text)
	l:SetText(text or "")
	l:SizeToContents()
	return l
end

-- Header with engraved title and a bronze rule
do
	local PANEL = {}
	function PANEL:Init() self.text = "" self.sub = nil self:SetTall(S(34)) end
	function PANEL:Setup(text, sub) self.text = text self.sub = sub self:SetTall(sub and S(48) or S(34)) return self end
	function PANEL:Paint(w, h)
		UI.Text(UI.Fit(self.text, "Praetor.H2", w), "Praetor.H2", 0, 0, C.ivory)
		if self.sub then UI.Text(UI.Fit(self.sub, "Praetor.Small", w), "Praetor.Small", 0, S(22), C.muted) end
		UI.Rule(0, h - S(5), w, C.line)
	end
	vgui.Register("PraetorHeader", PANEL, "DPanel")
end

function UI.Header(parent, text, sub)
	local h = vgui.Create("PraetorHeader", parent)
	h:Setup(text, sub)
	return h
end

-- ==================================================================== switch
do
	local PANEL = {}

	function PANEL:Init()
		self.title, self.desc, self.value, self.anim = "", nil, false, 0
		self.lines = {}
		self:SetCursor("hand")
	end

	function PANEL:Setup(title, desc, value, onChange)
		self.title, self.desc, self.value = title or "", desc, value == true
		self.anim = self.value and 1 or 0
		self.onChange = onChange
		self:InvalidateLayout(true)
		return self
	end

	function PANEL:SetValue(v) self.value = v == true end
	function PANEL:GetValue() return self.value end

	function PANEL:PerformLayout(w)
		local tw = w - S(64)
		self.lines = self.desc and UI.Wrap(self.desc, "Praetor.Small", math.max(40, tw)) or {}
		local h = S(22) + #self.lines * S(17) + S(10)
		if self:GetTall() ~= h then self:SetTall(h) end
	end

	function PANEL:OnMousePressed(m)
		if m ~= MOUSE_LEFT or not self:IsEnabled() then return end
		self.value = not self.value
		UI.Sound("click")
		if self.onChange then self.onChange(self.value, self) end
	end

	function PANEL:Paint(w, h)
		self.anim = UI.Lerp(self.anim, self.value and 1 or 0, 16)
		local hov = self:IsHovered()
		if hov then UI.Rect(0, 0, w, h, Color(255, 255, 255, 6)) end
		UI.Text(UI.Fit(self.title, "Praetor.BodyB", w - S(70)), "Praetor.BodyB", S(4), S(4), C.ivory)
		for i, l in ipairs(self.lines) do
			UI.Text(l, "Praetor.Small", S(4), S(4) + S(20) + (i - 1) * S(17), C.muted)
		end
		-- the toggle is centred on the whole text block
		local tw, th = S(44), S(22)
		local tx, ty = w - tw - S(6), math.floor((h - th) / 2)
		local on = self.anim
		UI.Round(tx, ty, tw, th, th / 2, P.LerpColor(on, C.panel3, C.bronze))
		local kx = tx + 3 + (tw - th) * on
		UI.Round(kx, ty + 3, th - 6, th - 6, (th - 6) / 2, P.LerpColor(on, C.muted, color_white))
	end

	vgui.Register("PraetorSwitch", PANEL, "DPanel")
end

function UI.Switch(parent, title, desc, value, onChange)
	local s = vgui.Create("PraetorSwitch", parent)
	s:Setup(title, desc, value, onChange)
	return s
end

-- ==================================================================== dropdown
local function themeMenu(menu)
	menu.Paint = function(_, w, h)
		UI.Rect(0, 0, w, h, C.panel)
		UI.Outline(0, 0, w, h, C.line)
	end
	for _, item in ipairs(menu:GetCanvas():GetChildren()) do
		if item.SetTextColor then
			item:SetTextColor(C.ivory)
			item:SetFont("Praetor.Body")
			item.Paint = function(s, w, h)
				if s:IsHovered() then UI.Rect(1, 0, w - 2, h, C.hover) end
			end
		end
	end
end
UI.ThemeMenu = themeMenu

do
	local PANEL = {}

	function PANEL:Init()
		self:SetFont("Praetor.Body")
		self:SetTextColor(C.ivory)
		self:SetTall(S(34))
		self.DropButton.Paint = function(_, w, h)
			local cx, cy = w / 2, h / 2
			surface.SetDrawColor(C.bronze)
			for i = 0, 3 do surface.DrawRect(cx - 4 + i, cy - 2 + i, 8 - i * 2, 1) end
		end
	end

	function PANEL:Paint(w, h)
		UI.Notch(0, 0, w, h, S(4), self:IsHovered() and C.panel2 or C.bg, self:IsMenuOpen() and C.bronze or C.line)
	end

	function PANEL:PerformLayout(w, h)
		self.DropButton:SetSize(S(20), h)
		self.DropButton:AlignRight(S(4))
		self:SetTextInset(S(8), 0)
	end

	function PANEL:OnMenuOpened(menu) themeMenu(menu) end

	vgui.Register("PraetorCombo", PANEL, "DComboBox")
end

-- options: list of { value, label } or plain strings
function UI.Combo(parent, options, value, onSelect)
	local c = vgui.Create("PraetorCombo", parent)
	c:SetSortItems(false)
	for _, o in ipairs(options or {}) do
		local v, l = o, o
		if istable(o) then v, l = o[1], o[2] end
		c:AddChoice(tostring(l), v, v == value)
	end
	if onSelect then c.OnSelect = function(_, _, _, data) onSelect(data) end end
	return c
end

-- ==================================================================== stable order
-- Docked children are laid out in the order of their z position. Every child
-- gets its own z position when it is added, so a panel that is brought to the
-- front (a text box that gets the keyboard, for example) never jumps to the end
-- of a form any more. Code that sets SetZPos itself still wins.
function UI.PinOrder(pnl)
	local old = pnl.OnChildAdded
	pnl.OnChildAdded = function(s, child)
		s.pinZ = math.min((s.pinZ or 0) + 1, 32000)
		if IsValid(child) and child:GetZPos() == 0 then child:SetZPos(s.pinZ) end
		if old then return old(s, child) end
	end
	return pnl
end

-- ==================================================================== scroll
function UI.Scroll(parent)
	local s = vgui.Create("DScrollPanel", parent)
	UI.PinOrder(s:GetCanvas())
	local bar = s:GetVBar()
	bar:SetWide(S(8))
	bar:SetHideButtons(true)
	bar.Paint = nil
	bar.btnGrip.Paint = function(g, w, h)
		UI.Round(1, 0, w - 2, h, (w - 2) / 2, g:IsHovered() and C.lineL or C.line)
	end
	return s
end

-- ==================================================================== color swatch
function UI.PickColor(start, onDone)
	local m = UI.Modal(P.L("ui_pick_color"), S(330), S(330))
	local mixer = vgui.Create("DColorMixer", m.body)
	mixer:Dock(FILL)
	mixer:SetPalette(true)
	mixer:SetAlphaBar(false)
	mixer:SetWangs(true)
	mixer:SetColor(start or C.bronze)
	local ok = UI.Button(m.foot, P.L("ui_ok"), "primary", nil, function()
		local c = mixer:GetColor()
		onDone(Color(c.r, c.g, c.b))
		m:Close()
	end)
	ok:Dock(RIGHT)
	ok:SetWide(S(110))
	return m
end

function UI.Swatch(parent, col, onChange)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b.col = col or C.ivory
	b:SetSize(S(34), S(34))
	b.Paint = function(s, w, h)
		UI.Notch(0, 0, w, h, S(4), s.col, s:IsHovered() and C.ivory or C.line)
	end
	b.DoClick = function(s)
		UI.PickColor(s.col, function(c) s.col = c if onChange then onChange(c) end end)
	end
	return b
end

-- ==================================================================== icon picker
UI.RankIcons = {
	"crown", "shield", "sword", "star", "gem", "laurel", "hammer", "wrench", "eye", "bolt", "skull", "flag",
	"key", "coin", "scroll", "flame", "leaf", "heart", "music", "gear", "helm", "badge", "anchor", "paw",
	"players", "user", "halo", "ghost", "rocket", "target", "warn", "door", "jail", "cuffs", "snow", "drop",
	"magnet", "portal", "pin", "map", "megaphone", "bubble", "envelope", "headset", "terminal", "clock",
	"clipboard", "brief", "license", "tag", "title", "ballot", "vest", "gun", "hand", "feather", "speed",
	"broom", "box", "pen", "mic", "afk",
}

-- UI.PickIcon (built-in + custom icons and the editor) lives in cl_icons.lua

-- ==================================================================== style editor
-- Edits { text, c1, c2, fx, icon }. opts: { icon = true, maxLen = 24, noText = false }
do
	local PANEL = {}

	function PANEL:Init()
		self.style = { text = "Tag", c1 = { r = 232, g = 194, b = 122 }, fx = "none" }
		self:SetTall(S(150))
	end

	function PANEL:Setup(style, opts, onChange)
		opts = opts or {}
		self.opts = opts
		self.onChange = onChange
		self.style = table.Copy(style or self.style)
		self:Build()
		return self
	end

	function PANEL:Changed()
		if self.onChange then self.onChange(self:GetStyle()) end
	end

	function PANEL:GetStyle()
		local s = table.Copy(self.style)
		if not self.useGrad then s.c2 = nil end
		return s
	end

	function PANEL:Build()
		self:Clear()
		local st = self.style
		self.useGrad = st.c2 ~= nil
		local row1 = vgui.Create("DPanel", self)
		row1:Dock(TOP)
		row1:SetTall(S(34))
		row1.Paint = nil
		if not self.opts.noText then
			local e = UI.Entry(row1, P.L("ui_tag_text"), st.text, function(v)
				st.text = P.Str(v, self.opts.maxLen or 24)
				self:Changed()
			end)
			e:Dock(FILL)
		end
		local sw1 = UI.Swatch(row1, P.ReadColor(st.c1, C.ivory), function(c) st.c1 = P.ColorTable(c) self:Changed() end)
		sw1:Dock(RIGHT)
		sw1:DockMargin(S(6), 0, 0, 0)
		local sw2 = UI.Swatch(row1, P.ReadColor(st.c2 or st.c1, C.bronze), function(c) st.c2 = P.ColorTable(c) self.useGrad = true self:Changed() end)
		sw2:Dock(RIGHT)
		sw2:DockMargin(S(6), 0, 0, 0)
		sw2.PaintOver = function(s, w, h)
			if not self.useGrad then
				surface.SetDrawColor(0, 0, 0, 170)
				surface.DrawRect(2, 2, w - 4, h - 4)
				UI.Text("+", "Praetor.BodyB", w / 2, h / 2, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		if self.opts.icon then
			local ib = vgui.Create("DButton", row1)
			ib:SetText("")
			ib:SetSize(S(34), S(34))
			ib:Dock(RIGHT)
			ib:DockMargin(S(6), 0, 0, 0)
			ib.Paint = function(s, w, h)
				UI.Notch(0, 0, w, h, S(4), s:IsHovered() and C.panel3 or C.panel2, C.line)
				UI.Icon(st.icon or "leaf", (w - 16) / 2, (h - 16) / 2, 16)
			end
			ib.DoClick = function() UI.PickIcon(st.icon, function(n) st.icon = n self:Changed() end) end
		end

		local row2 = vgui.Create("DPanel", self)
		row2:Dock(TOP)
		row2:DockMargin(0, S(6), 0, 0)
		row2:SetTall(S(34))
		row2.Paint = nil
		local grad = UI.Toggle(row2, P.L("ui_gradient"), nil, self.useGrad, function(v)
			self.useGrad = v
			if v and not st.c2 then st.c2 = { r = 178, g = 52, b = 66 } end
			self:Changed()
		end)
		grad:Dock(LEFT)
		grad:SizeToLabel(S(12))
		local opts = {}
		for _, fx in ipairs(P.Effects) do opts[#opts + 1] = { fx, P.L("fx_" .. fx) } end
		local fxc = UI.Combo(row2, opts, st.fx or "none", function(v) st.fx = v self:Changed() end)
		fxc:Dock(FILL)
		fxc:DockMargin(S(6), 0, 0, 0)

		local prev = vgui.Create("DPanel", self)
		prev:Dock(FILL)
		prev:DockMargin(0, S(6), 0, 0)
		prev.Paint = function(_, w, h)
			UI.Notch(0, 0, w, h, S(5), C.bg, C.line)
			local s = self:GetStyle()
			local bh = math.min(h - S(12), S(30))
			UI.Badge(s, self.opts.icon and (s.icon or "leaf") or nil, "Praetor.Tag", w / 2, (h - bh) / 2, bh, 255, TEXT_ALIGN_CENTER)
		end
	end

	function PANEL:Paint() end

	vgui.Register("PraetorStyleEdit", PANEL, "DPanel")
end

function UI.StyleEdit(parent, style, opts, onChange)
	local e = vgui.Create("PraetorStyleEdit", parent)
	e:Setup(style, opts, onChange)
	return e
end

-- ==================================================================== modal
function UI.Modal(title, w, h)
	w = math.min(w, ScrW() - S(20))
	h = math.min(h, ScrH() - S(20))
	-- EditablePanel, not DPanel: text boxes only take the keyboard when the
	-- window they live in is an EditablePanel (with a DPanel nothing could be typed)
	local bg = vgui.Create("EditablePanel")
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg:SetKeyboardInputEnabled(true)
	bg.Paint = function(_, pw, ph) UI.Rect(0, 0, pw, ph, Color(5, 6, 8, 170)) end
	bg.OnMousePressed = function(s) end

	local f = vgui.Create("DPanel", bg)
	f:SetSize(w, h)
	f:Center()
	f.Paint = function(_, fw, fh)
		UI.Tablet(0, 0, fw, fh, C.panel, C.line)
		UI.Text(UI.Fit(title, "Praetor.H2", fw - S(70)), "Praetor.H2", S(16), S(11), C.ivory)
		UI.Rule(S(12), S(40), fw - S(24), C.line)
	end
	local close = vgui.Create("DButton", f)
	close:SetText("")
	close:SetSize(S(28), S(28))
	close:SetPos(w - S(36), S(8))
	close.Paint = function(s, cw, ch)
		if s:IsHovered() then UI.Round(0, 0, cw, ch, S(6), Color(C.crimson.r, C.crimson.g, C.crimson.b, 60)) end
		local col = s:IsHovered() and C.crimsonL or C.muted
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(12), 2, 45)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(12), 2, -45)
	end

	f.body = UI.PinOrder(vgui.Create("DPanel", f))
	f.body:Dock(FILL)
	f.body:DockMargin(S(14), S(50), S(14), S(8))
	f.body.Paint = nil
	f.foot = vgui.Create("DPanel", f)
	f.foot:Dock(BOTTOM)
	f.foot:SetTall(S(34))
	f.foot:DockMargin(S(14), 0, S(14), S(12))
	f.foot.Paint = nil
	f.foot:SetZPos(-1)

	function f:Close()
		if IsValid(bg) then bg:Remove() end
	end
	close.DoClick = function() f:Close() end
	bg.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then f:Close() end end
	UI.Sound("open")
	return f
end

function UI.Confirm(title, text, onYes, danger)
	local m = UI.Modal(title, S(420), S(210))
	local lines = UI.Wrap(text, "Praetor.Body", S(380))
	local lbl = vgui.Create("DPanel", m.body)
	lbl:Dock(FILL)
	lbl.Paint = function()
		for i, l in ipairs(lines) do UI.Text(l, "Praetor.Body", 0, (i - 1) * S(20), C.text) end
	end
	local yes = UI.Button(m.foot, P.L("ui_confirm"), danger and "danger" or "primary", nil, function() m:Close() onYes() end)
	yes:Dock(RIGHT)
	yes:SetWide(S(120))
	local no = UI.Button(m.foot, P.L("ui_cancel"), "ghost", nil, function() m:Close() end)
	no:Dock(RIGHT)
	no:SetWide(S(110))
	no:DockMargin(0, 0, S(8), 0)
	return m
end

-- ==================================================================== quick context menu
-- items: { { label, icon, fn, danger, sub } , ... } ; false = separator ;
-- { label, icon, nil, nil, { ...items } } opens a sub menu; { label, kind = "title" } is a heading
local function fillMenu(menu, items)
	for _, it in ipairs(items) do
		if it == false then
			menu:AddSpacer()
		elseif it.kind == "title" then
			local o = menu:AddOption(it[1])
			o:SetEnabled(false)
			o.praetorTitle = true
		elseif istable(it[5]) then
			local sub, o = menu:AddSubMenu(it[1])
			o.praetorIcon = it[2]
			fillMenu(sub, it[5])
			sub.praetorItems = it[5]
		else
			local o = menu:AddOption(it[1], it[3])
			o.praetorIcon = it[2]
			o.praetorDanger = it[4]
		end
	end
end
UI.FillMenu = fillMenu

local function themePopup(menu)
	menu.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(6), C.panel, C.line)
	end
	for _, item in ipairs(menu:GetCanvas():GetChildren()) do
		if item.SetTextColor then
			item:SetFont(item.praetorTitle and "Praetor.Tiny" or "Praetor.Body")
			item:SetTextColor(item.praetorTitle and C.dim or (item.praetorDanger and C.crimsonL or C.ivory))
			item.Paint = function(s, w, h)
				if s:IsHovered() and not s.praetorTitle then UI.Round(S(3), 1, w - S(6), h - 2, S(4), s.praetorDanger and Color(C.crimson.r, C.crimson.g, C.crimson.b, 50) or C.hover) end
				if s.praetorIcon then UI.Icon(s.praetorIcon, S(9), (h - 16) / 2, 16, s.praetorDanger and C.crimsonL or color_white) end
				if s.SubMenu then
					surface.SetDrawColor(C.muted)
					local cx, cy = w - S(12), h / 2
					for i = 0, 3 do surface.DrawRect(cx - 3 + i, cy - 3 + i, 1, 7 - i * 2) end
				end
			end
			if item.SubMenu then
				local old = item.SubMenu.Open
				item.SubMenu.Open = function(sm, ...)
					local r = old(sm, ...)
					themePopup(sm)
					return r
				end
				themePopup(item.SubMenu)
			end
		end
	end
end
UI.ThemePopup = themePopup

function UI.Popup(items)
	local menu = DermaMenu()
	fillMenu(menu, items)
	menu:Open()
	themePopup(menu)
	return menu
end

-- ==================================================================== player / steamid picker
-- An entry that accepts a SteamID / name, with a button that opens the player
-- list. The chosen player shows inside the field: framed picture, name, rank.
-- opts: { humans = true (no bots), noSelf = true }
local function resolvePlayer(v)
	v = P.Trim(v or "")
	if v == "" then return nil end
	if v:match("^%d+$") then return player.GetBySteamID64(v) or nil end
	local uid = v:match("^%$(%d+)$")
	if uid then return Player(tonumber(uid)) end
	if v:upper():match("^STEAM_") then return player.GetBySteamID(v:upper()) or nil end
	-- half a name is enough, the same way the server reads it: exact name,
	-- then the only name that starts with it, then the only one that has it
	local low, f = v:lower(), P.FoldName(v)
	if f == "" then return nil end
	local starts, has = {}, {}
	for _, pl in ipairs(player.GetAll()) do
		local n = P.FoldName(pl:Nick())
		if pl:Nick():lower() == low or n == f then return pl end
		if n:sub(1, #f) == f then starts[#starts + 1] = pl
		elseif n:find(f, 1, true) then has[#has + 1] = pl end
	end
	if #starts == 1 then return starts[1] end
	if #starts == 0 and #has == 1 then return has[1] end
	return nil
end
UI.ResolvePlayer = resolvePlayer

-- Field for a player: picture on the left (outside the text, so nothing is
-- hidden behind it), the typed text in the middle, name and rank on the right.
-- Picking from the list fills the classic SteamID (STEAM_0:1:...).
function UI.PlayerPick(parent, value, onChange, opts)
	opts = opts or {}
	local p = vgui.Create("DPanel", parent)
	p:SetTall(S(34))
	local b = UI.Button(p, "", "ghost", "players")
	b:Dock(RIGHT)
	b:SetWide(S(38))
	b:DockMargin(S(6), 0, 0, 0)
	b:SetTooltip(P.L("ui_pick_player"))
	local box = vgui.Create("DPanel", p)
	box:Dock(FILL)
	local e = UI.Entry(box, "", value or "")
	e:Dock(FILL)
	e:DockMargin(S(36), 0, 0, 0)
	e.Paint = function(s2, w, h)
		s2:DrawTextEntryText(C.ivory, Color(92, 132, 255, 110), C.bronzeL)
	end
	box.focus = 0
	box.Paint = function(s2, w, h)
		s2.focus = UI.Lerp(s2.focus, e:HasFocus() and 1 or 0, 14)
		UI.Notch(0, 0, w, h, S(4), C.bg, P.LerpColor(s2.focus, C.line, C.bronze))
		local pl = p.ply
		local sz = h - S(10)
		if not IsValid(pl) then
			UI.Round(S(5), S(5), sz, sz, S(5), C.panel3)
			UI.Icon("user", S(5) + (sz - 16) / 2, S(5) + (sz - 16) / 2, 16, Color(255, 255, 255, 90))
			if e:GetText() == "" and not e:HasFocus() then
				UI.Text(P.L("ui_player_or_steamid"), "Praetor.Body", S(40), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			return
		end
		UI.DrawAvatar(pl:SteamID64(), pl, S(5), S(5), sz, 255, UI.AvatarFrame(pl), pl:Nick())
	end
	box.OnMousePressed = function() e:RequestFocus() end
	-- name and rank on the right side of the field (the typed text stays on the left)
	e.PaintOver = function(s2, w, h)
		local pl = p.ply
		if not IsValid(pl) then return end
		surface.SetFont("Praetor.Body")
		local tw = surface.GetTextSize(s2:GetText())
		local room = w - tw - S(20)
		if room < S(60) then return end
		local style, icon = UI.PlayerRankStyle(pl)
		local bw = UI.BadgeWidth and UI.BadgeWidth(style, icon, "Praetor.Tiny", S(18)) or 0
		local right = w - S(8)
		if bw > 0 and room > bw + S(80) then
			UI.Badge(style, icon, "Praetor.Tiny", right - bw, (h - S(18)) / 2, S(18))
			right = right - bw - S(8)
			room = room - bw - S(8)
		end
		local nm = pl:Nick()
		if s2:GetText() ~= nm then
			UI.Name(nm, "Praetor.SmallB", right, h / 2, C.ivory, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, math.min(room, S(180)))
		end
	end
	local function idOf(pl)
		if pl:IsBot() then return "$" .. pl:UserID() end
		local sid = pl:SteamID()
		if not sid or sid == "" or sid == "NULL" then return pl:SteamID64() or "" end
		return sid
	end
	local function pick()
		UI.PlayerPicker(function(pl)
			if not IsValid(pl) then return end
			e:SetValue(idOf(pl))
			p.ply = pl
			if onChange then onChange(e:GetValue()) end
		end, opts)
	end
	b.DoClick = pick
	e.OnChange = function()
		p.ply = resolvePlayer(e:GetValue())
		if onChange then onChange(e:GetValue()) end
	end
	-- a SteamID64 handed in by the caller is shown as the classic SteamID
	if value and value ~= "" then
		p.ply = resolvePlayer(value)
		if IsValid(p.ply) and value:match("^%d+$") then e:SetValue(idOf(p.ply)) end
	end
	function p:GetValue() return P.Trim(e:GetValue()) end
	function p:SetValue(v)
		p.ply = resolvePlayer(v)
		if IsValid(p.ply) and tostring(v or ""):match("^%d+$") then v = idOf(p.ply) end
		e:SetValue(v or "")
	end
	function p:GetPlayer() return IsValid(p.ply) and p.ply or nil end
	p.Paint = nil
	p.entry = e
	p.Pick = pick
	return p
end

-- Window with every online player: picture, name, rank and a search box.
-- opts: { humans = true (no bots), noSelf = true, title = "..." }
function UI.PlayerPicker(onPick, opts)
	opts = opts or {}
	local m = UI.Modal(opts.title or P.L("ui_pick_player"), S(440), S(500))
	local search = UI.Entry(m.body, P.L("ui_search"))
	search:Dock(TOP)
	search:DockMargin(0, 0, 0, S(8))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)
	local function fill()
		sc:Clear()
		m.firstRow = nil
		local q = P.Trim(search:GetValue()):lower()
		local plys = player.GetAll()
		table.sort(plys, function(a, c)
			local aa, cc = P.Authority(a), P.Authority(c)
			if aa ~= cc then return aa > cc end
			return a:Nick():lower() < c:Nick():lower()
		end)
		local n = 0
		for _, pl in ipairs(plys) do
			local okKind = (not opts.humans or not pl:IsBot()) and (not opts.noSelf or pl ~= LocalPlayer())
			if okKind and (q == "" or pl:Nick():lower():find(q, 1, true) or (pl:SteamID() or ""):lower():find(q, 1, true)) then
				n = n + 1
				local row = vgui.Create("DButton", sc)
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(52))
				row:DockMargin(0, 0, S(4), S(4))
				row.hov = 0
				local first = n == 1
				row.Paint = function(s2, w, h)
					if not IsValid(pl) then return end
					s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 14)
					local frame = UI.AvatarFrame(pl)
					UI.Round(0, 0, w, h, S(6), P.LerpColor(s2.hov, C.panel2, C.hover), P.LerpColor(s2.hov, (first and q ~= "") and C.bronze or C.line, frame))
					-- rank colour strip on the left edge
					UI.Round(0, S(8), S(3), h - S(16), S(1), frame)
					local sz = h - S(14)
					UI.DrawAvatar(pl:SteamID64(), pl, S(12), S(7), sz, 255, frame, pl:Nick())
					-- small dot: talking (green) / dead (red)
					local dot = pl:IsSpeaking() and C.laurel or (not pl:Alive() and C.crimson or nil)
					if dot then
						UI.Round(S(12) + sz - S(8), S(7) + sz - S(8), S(10), S(10), S(5), C.panel2)
						UI.Round(S(12) + sz - S(6), S(7) + sz - S(6), S(6), S(6), S(3), dot)
					end
					local style, icon = UI.PlayerRankStyle(pl)
					local bw = UI.BadgeWidth and UI.BadgeWidth(style, icon, "Praetor.Tiny", S(20)) or S(80)
					UI.Badge(style, icon, "Praetor.Tiny", w - bw - S(10), (h - S(20)) / 2, S(20))
					local x = S(12) + sz + S(12)
					UI.Name(pl:Nick(), "Praetor.BodyB", x, S(9), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, w - x - bw - S(20))
					local sub = pl:IsBot() and "BOT" or pl:SteamID()
					if pl == LocalPlayer() then sub = sub .. "  -  " .. P.L("you") end
					UI.Text(sub, "Praetor.Tiny", x, S(31), C.dim)
				end
				row.DoClick = function()
					UI.Sound("click")
					m:Close()
					onPick(pl)
				end
				if first then m.firstRow = row end
			end
		end
		if n == 0 then
			local l = UI.Label(sc, P.L("ui_empty"), "Praetor.Small", C.dim)
			l:Dock(TOP)
		end
	end
	search.OnChange = fill
	-- Enter picks the first player in the list
	search.OnEnter = function() if IsValid(m.firstRow) then m.firstRow:DoClick() end end
	fill()
	search:RequestFocus()
	return m
end

-- ==================================================================== duration field
-- opts: { noLimit = true (last chip empties the field: "no limit"),
--         noPerm = true (no "permanent" chip), chips = { "1h", "1d", ... } }
function UI.DurationField(parent, value, opts)
	opts = opts or {}
	local p = vgui.Create("DPanel", parent)
	p:SetTall(S(34) * 2 + S(6))
	p.Paint = nil
	local e = UI.Entry(p, P.L("ui_duration_hint"), value or "")
	e:Dock(TOP)
	local chips = vgui.Create("DPanel", p)
	chips:Dock(TOP)
	chips:DockMargin(0, S(6), 0, 0)
	chips:SetTall(S(30))
	chips.Paint = nil
	local list = {}
	for _, c in ipairs(opts.chips or { "30m", "2h", "1d", "1w", "1mo" }) do list[#list + 1] = { c, c } end
	if opts.noLimit then list[#list + 1] = { "", P.L("ui_no_limit") }
	elseif not opts.noPerm then list[#list + 1] = { "perm", P.L("ui_perm") } end
	if opts.noLimit then e:SetPlaceholderText(P.L("ui_duration_hint_limit")) end
	for _, c in ipairs(list) do
		local b = UI.Button(chips, c[2], "ghost")
		b:SetFont("Praetor.Small")
		b:SetTall(S(30))
		b:Dock(LEFT)
		b:DockMargin(0, 0, S(4), 0)
		b:SizeToLabel(S(8))
		b.DoClick = function() e:SetValue(c[1]) end
	end
	function p:GetValue() return P.Trim(e:GetValue()) end
	function p:GetMinutes() return P.ParseDuration(e:GetValue()) end
	p.entry = e
	return p
end

-- ==================================================================== generic form
-- fields: { { key, type, label, default, options, placeholder } }
-- types: text, multiline, number, duration, choice, player, check, rank, job, style
function UI.Form(title, fields, onSubmit, submitLabel, width)
	local hgt = S(130)
	for _, f in ipairs(fields) do
		if f[2] == "multiline" then hgt = hgt + S(120)
		elseif f[2] == "duration" then hgt = hgt + S(100)
		elseif f[2] == "style" then hgt = hgt + S(176)
		elseif f[2] == "check" then hgt = hgt + S(44)
		else hgt = hgt + S(62) end
	end
	local m = UI.Modal(title, width or S(460), hgt)
	local scroll = UI.Scroll(m.body)
	scroll:Dock(FILL)
	local getters = {}
	for _, f in ipairs(fields) do
		local key, kind, label, def = f[1], f[2], f[3], f[4]
		if kind ~= "check" then
			local l = UI.Label(scroll, label, "Praetor.SmallB", C.muted)
			l:Dock(TOP)
			l:DockMargin(0, S(4), 0, S(3))
		end
		local ctl
		if kind == "text" or kind == "number" then
			ctl = UI.Entry(scroll, f[5] or "", def ~= nil and tostring(def) or "")
			if kind == "number" then ctl:SetNumeric(true) end
			getters[key] = function() return kind == "number" and tonumber(ctl:GetValue()) or ctl:GetValue() end
		elseif kind == "multiline" then
			ctl = UI.Entry(scroll, f[5] or "", def or "")
			ctl:SetMultiline(true)
			ctl:SetTall(S(110))
			getters[key] = function() return ctl:GetValue() end
		elseif kind == "duration" then
			ctl = UI.DurationField(scroll, def)
			getters[key] = function() return ctl:GetMinutes() end
		elseif kind == "player" then
			ctl = UI.PlayerPick(scroll, def)
			getters[key] = function() return ctl:GetValue() end
		elseif kind == "check" then
			ctl = UI.Switch(scroll, label, f[5], def == true)
			getters[key] = function() return ctl:GetValue() end
		elseif kind == "style" then
			ctl = UI.StyleEdit(scroll, def, f[5] or {})
			ctl:SetTall(S(170))
			getters[key] = function() return ctl:GetStyle() end
		else
			local opts = f[5] or {}
			if kind == "rank" then
				opts = {}
				for _, r in ipairs(P.SortedRanks()) do
					if P.CanManageRank(LocalPlayer(), r.name) then opts[#opts + 1] = { r.name, r.display or r.name } end
				end
			elseif kind == "job" then
				opts = {}
				for _, j in pairs(RPExtraTeams or {}) do opts[#opts + 1] = { j.command, j.name } end
				table.sort(opts, function(a, b) return a[2] < b[2] end)
				if f[6] then table.insert(opts, 1, { "*", P.L("ui_all_jobs") }) end
			end
			ctl = UI.Combo(scroll, opts, def)
			if def == nil and opts[1] then ctl:ChooseOptionID(1) end
			getters[key] = function()
				local _, data = ctl:GetSelected()
				return data
			end
		end
		ctl:Dock(TOP)
	end
	-- the first text box gets the keyboard at once
	timer.Simple(0, function()
		if not IsValid(scroll) then return end
		for _, ch in ipairs(scroll:GetCanvas():GetChildren()) do
			local e = ch.entry or ch
			if IsValid(e) and e.GetClassName and e:GetClassName() == "TextEntry" and e:IsVisible() then e:RequestFocus() break end
		end
	end)
	local okb = UI.Button(m.foot, submitLabel or P.L("ui_ok"), "primary", nil, function()
		local vals = {}
		for k, g in pairs(getters) do vals[k] = g() end
		if onSubmit(vals) ~= false then m:Close() end
	end)
	okb:Dock(RIGHT)
	okb:SetWide(S(130))
	local cancel = UI.Button(m.foot, P.L("ui_cancel"), "ghost", nil, function() m:Close() end)
	cancel:Dock(RIGHT)
	cancel:SetWide(S(110))
	cancel:DockMargin(0, 0, S(8), 0)
	return m
end

-- ==================================================================== avatar
function UI.Avatar(parent, size, ply, sid)
	local a = vgui.Create("AvatarImage", parent)
	a:SetSize(size, size)
	if IsValid(ply) then a:SetPlayer(ply, size > 64 and 184 or (size > 32 and 64 or 32))
	elseif sid then a:SetSteamID(sid, size > 64 and 184 or (size > 32 and 64 or 32)) end
	return a
end

-- framed avatar (bronze frame drawn over it)
function UI.FramedAvatar(parent, size, ply, sid)
	local holder = vgui.Create("DPanel", parent)
	holder:SetSize(size, size)
	-- bots have no Steam picture: show their initial on a colour from the name
	if IsValid(ply) and ply:IsBot() then
		holder.Paint = function(_, w, h)
			if not IsValid(ply) then return end
			local c = HSVToColor((tonumber(util.CRC(ply:Nick())) or 0) % 360, 0.45, 0.62)
			UI.Round(0, 0, w, h, P.S(5), c)
			draw.SimpleText(string.upper(P.Chars(ply:Nick())[1] or "?"), h >= P.S(36) and "Praetor.Big" or "Praetor.SmallB", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return holder
	end
	holder.Paint = function(_, w, h) UI.Round(0, 0, w, h, P.S(5), C.panel3) end
	local a = UI.Avatar(holder, size - 2, ply, sid)
	a:SetPos(1, 1)
	a:SetMouseInputEnabled(false)
	holder.avatar = a
	return holder
end
