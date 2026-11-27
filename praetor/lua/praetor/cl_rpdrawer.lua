-- Praetor: the RP commands drawer (DarkRP).
-- A small tab with an arrow on the right edge of the screen. Clicking it (hold C
-- for the mouse, type /comandos or /rpcmds in the chat, or bind a key to
-- praetor_rpcmds) slides out a panel with the RP commands of your job and the
-- ones everyone has: name, what it does and the chat command in your language.
-- Click one to use it. The list follows your job (police, mayor, agenda...).
-- Server: Settings > DarkRP > rp_drawer. Each player: praetor_rpdrawer 0 hides it.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local drawerVar = CreateClientConVar("praetor_rpdrawer", "1", true, false, "Praetor: the RP commands drawer at the right edge (0 = hidden)", 0, 1)

local D = P.RPDrawer or {}
P.RPDrawer = D

local function on()
	return P.IsDarkRP() and P.Setting("rp_drawer") ~= false and drawerVar:GetBool() and P.F4 and P.F4.VisibleCommands ~= nil
end

local function fontH(f)
	surface.SetFont(f)
	local _, h = surface.GetTextSize("ÁgjM")
	return h
end

local TAB_W, TAB_H = 26, 84

-- the signature of everything that changes the list
local function sig()
	local me = LocalPlayer()
	if not IsValid(me) then return "" end
	return me:Team() .. ":" .. tostring(me.isMayor and me:isMayor()) .. ":" .. tostring(GetGlobalBool("DarkRP_LockDown"))
		.. ":" .. tostring(me.getDarkRPVar and me:getDarkRPVar("HasGunlicense")) .. ":" .. P.CurrentLang()
end

-- one row: icon, name, chat command, what it does (wrapped)
local function row(parent, c, tint)
	local r = vgui.Create("DButton", parent)
	r:SetText("")
	r:Dock(TOP)
	r:DockMargin(0, 0, S(4), S(6))
	r.anim = 0
	r.OnCursorEntered = function() UI.Sound("hover") end
	r.PerformLayout = function(s, w)
		local tw = w - S(62) - S(10)
		s.lines = UI.Wrap(P.L("f4cd_" .. c[1]), "Praetor.Small", tw)
		while #s.lines > 3 do table.remove(s.lines) end
		local h = S(10) + fontH("Praetor.BodyB") + S(2) + fontH("Praetor.Tiny") + S(4) + #s.lines * fontH("Praetor.Small") + S(10)
		if s:GetTall() ~= h then s:SetTall(h) end
	end
	r.Paint = function(s, w, h)
		s.anim = UI.Lerp(s.anim, s:IsHovered() and 1 or 0, 14)
		UI.Round(0, 0, w, h, S(12), P.LerpColor(s.anim, C.panel2, C.hover), P.LerpColor(s.anim, C.line, tint))
		local dsz = S(36)
		UI.Round(S(12), S(10), dsz, dsz, dsz / 2, tint, C.ink)
		UI.Icon(c[2], S(12) + (dsz - 22) / 2, S(10) + (dsz - 22) / 2, 22)
		local x, tw = S(62), w - S(62) - S(10)
		local y = S(10)
		UI.Text(UI.Fit(P.L("f4c_" .. c[1]), "Praetor.BodyB", tw), "Praetor.BodyB", x, y, C.ivory)
		y = y + fontH("Praetor.BodyB") + S(2)
		-- the chat command: my language first, the other one after it
		local lang = P.CurrentLang()
		local main = P.F4.ChatLine(c, lang) or ""
		local other = P.F4.ChatLine(c, lang == "pt" and "en" or "pt")
		local otherName = other and other:match("^(%S+)")
		local line = main .. ((otherName and otherName ~= main:match("^(%S+)")) and ("   ·   " .. otherName) or "")
		UI.Text(UI.Fit(line, "Praetor.Tiny", tw), "Praetor.Tiny", x, y, Color(tint.r, tint.g, tint.b, 240))
		y = y + fontH("Praetor.Tiny") + S(4)
		local lh = fontH("Praetor.Small")
		for i, l in ipairs(s.lines or {}) do UI.Text(l, "Praetor.Small", x, y + (i - 1) * lh, C.muted) end
	end
	r.DoClick = function()
		UI.Sound("click")
		D.Close()
		P.F4.RunCommand(c)
	end
	return r
end

local function build(panel)
	panel.list:Clear()
	local vis = P.F4.VisibleCommands()
	for _, g in ipairs(P.F4.CommandGroups) do
		local cmds = {}
		for _, c in ipairs(vis) do if g[3](c) then cmds[#cmds + 1] = c end end
		if #cmds > 0 then
			local tint = P.F4.GroupColor(g[2])
			local head = vgui.Create("DPanel", panel.list)
			head:Dock(TOP)
			head:SetTall(fontH("Praetor.Tiny") + S(10))
			head:DockMargin(S(2), S(4), S(4), S(4))
			head.Paint = function(_, w, h)
				local t = P.Upper(P.L(g[1]))
				surface.SetFont("Praetor.Tiny")
				local tw = surface.GetTextSize(t)
				UI.Text(t, "Praetor.Tiny", 0, h / 2, tint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Rect(tw + S(10), math.floor(h / 2), w - tw - S(10), 1, Color(C.line.r, C.line.g, C.line.b, 160))
			end
			for _, c in ipairs(cmds) do row(panel.list, c, tint) end
		end
	end
	panel.sig = sig()
end

-- ------------------------------------------------------------------ the panel and the tab

local clicker = false
local function setClicker(want)
	if want == clicker then return end
	clicker = want
	gui.EnableScreenClicker(want)
end

function D.IsOpen() return IsValid(D.panel) and D.panel.open end

function D.Close()
	if not IsValid(D.panel) or not D.panel.open then return end
	D.panel.open = false
	D.panel:SetKeyboardInputEnabled(false)
	setClicker(false)
	UI.Sound("close")
end

local function create()
	local p = vgui.Create("EditablePanel")
	D.panel = p
	p.k = 0
	p.open = false
	p:SetMouseInputEnabled(true)
	p:SetKeyboardInputEnabled(false)
	p:ParentToHUD()

	local head = vgui.Create("DPanel", p)
	head:Dock(TOP)
	head.PerformLayout = function(s)
		local h = S(14) + fontH("Praetor.H2") + S(4) + fontH("Praetor.Tiny") + S(12)
		if s:GetTall() ~= h then s:SetTall(h) end
	end
	head.Paint = function(_, w, h)
		local me = LocalPlayer()
		if not IsValid(me) then return end
		local x = S(16)
		local y = S(14)
		UI.Icon("terminal", x, y + (fontH("Praetor.H2") - 22) / 2, 22)
		draw.SimpleText(P.L("rpd_title"), "Praetor.H2", x + S(30), y, C.ivory)
		y = y + fontH("Praetor.H2") + S(4)
		UI.Text(UI.Fit(P.L("rpd_hint"), "Praetor.Tiny", w - S(32)), "Praetor.Tiny", x, y, C.muted)
		UI.Rect(S(14), h - 2, w - S(28), 2, Color(C.line.r, C.line.g, C.line.b, 160))
	end

	local list = UI.Scroll(p)
	list:Dock(FILL)
	list:DockMargin(S(12), S(10), S(8), S(12))
	p.list = list

	-- the tab with the arrow, glued to the panel's left side
	local tab = vgui.Create("DButton")
	tab:SetText("")
	tab:ParentToHUD()
	tab:SetTooltip(P.L("rpd_tab_tip"))
	tab.anim = 0
	tab.OnCursorEntered = function() UI.Sound("hover") end
	tab.DoClick = function() D.Toggle() end
	tab.Paint = function(s, w, h)
		s.anim = UI.Lerp(s.anim, (s:IsHovered() or p.open) and 1 or 0, 12)
		local a = 150 + 105 * s.anim
		draw.RoundedBoxEx(S(10), 0, 0, w + S(10), h, Color(C.ink.r, C.ink.g, C.ink.b, a), true, false, true, false)
		draw.RoundedBoxEx(S(8), S(2), S(2), w + S(10), h - S(4), Color(C.panel.r, C.panel.g, C.panel.b, a), true, false, true, false)
		surface.SetDrawColor(C.bronze.r, C.bronze.g, C.bronze.b, a)
		surface.DrawRect(S(2), S(10), S(3), h - S(20))
		-- the arrow points where the panel goes
		draw.NoTexture()
		surface.SetDrawColor(255, 255, 255, a)
		local cx, cy, z = w / 2 + S(1), h / 2, S(5)
		if p.open then
			surface.DrawPoly({ { x = cx - z / 2, y = cy - z }, { x = cx + z, y = cy }, { x = cx - z / 2, y = cy + z } })
		else
			surface.DrawPoly({ { x = cx + z / 2, y = cy - z }, { x = cx + z / 2, y = cy + z }, { x = cx - z, y = cy } })
		end
	end
	p.tab = tab

	p.Paint = function(_, w, h)
		UI.Round(0, 0, w + S(16), h, S(14), Color(C.panel.r, C.panel.g, C.panel.b, 246), C.lineL)
	end

	p.Think = function(s)
		local show = on() and IsValid(LocalPlayer()) and LocalPlayer():Alive()
		if not show and s.open then D.Close() end
		s.k = math.Approach(s.k, s.open and 1 or 0, FrameTime() * 6)
		local e = 1 - (1 - s.k) ^ 3
		local W = math.min(S(380), math.floor(ScrW() * 0.32))
		local H = math.min(math.floor(ScrH() * 0.72), S(720))
		local y = math.floor((ScrH() - H) / 2)
		s:SetSize(W, H)
		s:SetPos(ScrW() - math.floor(W * e), y)
		s:SetVisible(show and s.k > 0)
		local tw, th = S(TAB_W), S(TAB_H)
		tab:SetSize(tw, th)
		tab:SetPos(ScrW() - math.floor(W * e) - tw, y + math.floor((H - th) / 2))
		-- the tab only when it can be used: a mouse on screen, or the drawer open
		tab:SetVisible(show and (vgui.CursorVisible() or s.open))
		if s.open then
			if s.sig ~= sig() then build(s) end
			if input.IsKeyDown(KEY_ESCAPE) then
				if gui.IsGameUIVisible() then gui.HideGameUI() end
				D.Close()
			end
		end
	end
	return p
end

function D.Open()
	if not on() then return end
	if not IsValid(D.panel) then create() end
	local p = D.panel
	if p.open then return end
	p.open = true
	build(p)
	setClicker(true)
	UI.Sound("open")
end

function D.Toggle()
	if D.IsOpen() then D.Close() else D.Open() end
end

concommand.Add("praetor_rpcmds", function() D.Toggle() end, nil, "Opens / closes the Praetor RP commands drawer")

-- /comandos, /rpcmds in the chat
P.On("rp_drawer", function() D.Open() end)

hook.Add("InitPostEntity", "Praetor.RPDrawer", function()
	timer.Simple(2, function() if on() and not IsValid(D.panel) then create() end end)
end)
-- the context menu (C) shows the mouse: make sure the tab exists then
hook.Add("OnContextMenuOpen", "Praetor.RPDrawer", function()
	if on() and not IsValid(D.panel) then create() end
end)
if IsValid(LocalPlayer()) then timer.Simple(0, function() if on() and not IsValid(D.panel) then create() end end) end
