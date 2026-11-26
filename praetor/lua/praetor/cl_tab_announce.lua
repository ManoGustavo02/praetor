-- Praetor menu: Announcements. Saved messages (every X minutes, when a player
-- joins, or by hand) shown in the chat, as a pop-up in a corner, as a bar at the
-- top or in the middle of the screen. Colour, icon (pick or draw one), link,
-- time on screen, who sees it, and a live preview of the real look.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local WHERE = {
	{ id = "popup", icon = "pin", label = "an_w_popup", d = "an_w_popup_d" },
	{ id = "chat", icon = "bubble", label = "an_w_chat", d = "an_w_chat_d" },
	{ id = "banner", icon = "megaphone", label = "an_w_banner", d = "an_w_banner_d" },
	{ id = "center", icon = "star", label = "an_w_center", d = "an_w_center_d" },
}
local COLORS = {
	{ r = 88, g = 101, b = 242 }, -- discord
	{ r = 92, g = 132, b = 255 },
	{ r = 64, g = 190, b = 200 },
	{ r = 96, g = 190, b = 110 },
	{ r = 240, g = 190, b = 70 },
	{ r = 240, g = 130, b = 50 },
	{ r = 225, g = 70, b = 80 },
	{ r = 200, g = 100, b = 230 },
	{ r = 226, g = 178, b = 96 },
	{ r = 220, g = 222, b = 230 },
}

local function blank()
	return { title = "", text = "", link = "", where = "popup", corner = "br", when = "timer", every = 10, life = 10, who = "all",
		col = table.Copy(COLORS[1]), icon = "megaphone", snd = true, on = true }
end

local function whenText(it)
	if it.when == "join" then return P.L("an_when_join") end
	if it.when == "manual" then return P.L("an_when_manual") end
	return P.L("an_every_n", { V = it.every or 10 })
end

local function chipRow(parent, tall)
	local r = vgui.Create("DPanel", parent)
	r:Dock(TOP)
	r:SetTall(tall or S(32))
	r:DockMargin(0, 0, 0, S(6))
	r.Paint = nil
	return r
end

local function chip(parent, label, icon, isOn, fn)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	surface.SetFont("Praetor.Small")
	b:SetWide(surface.GetTextSize(label) + (icon and S(40) or S(22)))
	b:Dock(LEFT)
	b:DockMargin(0, 0, S(6), 0)
	b.Paint = function(s, w, h)
		local on = isOn()
		UI.Round(0, 0, w, h, S(6), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
		local x = S(11)
		if icon then UI.Icon(icon, S(9), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 170)) x = S(31) end
		UI.Text(label, "Praetor.Small", x, h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function() UI.Sound("click") fn() end
	return b
end

local function label(parent, text, top)
	local l = UI.Label(parent, text, "Praetor.BodyB", C.ivory)
	l:Dock(TOP)
	l:DockMargin(S(2), top or S(10), 0, S(4))
	return l
end

-- ------------------------------------------------------------------ preview

local grid = Material("gui/gradient_down")
local function drawPreview(it, w, h)
	-- a dark "game screen" with a soft light from the top
	UI.Round(0, 0, w, h, S(8), Color(24, 27, 34), C.line)
	surface.SetMaterial(grid)
	surface.SetDrawColor(70, 80, 100, 60)
	surface.DrawTexturedRect(1, 1, w - 2, h * 0.6)
	surface.SetDrawColor(255, 255, 255, 6)
	for x = S(20), w - S(10), S(24) do surface.DrawRect(x, S(8), 1, h - S(16)) end
	UI.Text(P.Upper(P.L("an_preview")), "Praetor.Tiny", S(10), S(12), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local D = P.AnnDraw
	local view = table.Copy(it)
	view.link = P.Trim(it.link or "") ~= "" and it.link or nil
	if view.title == "" and view.text == "" then view.text = P.L("an_text_ph") end
	if it.where == "popup" then
		local pw = math.min(S(340), w - S(40))
		local ph = D.popup(view, 0, 0, pw, 1, nil, true)
		local right = it.corner == "tr" or it.corner == "br"
		local bottom = it.corner == "br" or it.corner == "bl"
		local x = right and (w - pw - S(14)) or S(14)
		local y = bottom and (h - ph - S(14)) or S(26)
		D.popup(view, x, y, pw, 1, 0.65)
	elseif it.where == "banner" then
		local bw = w - S(40)
		D.banner(view, S(20), S(26), bw, 1, 0.65)
	elseif it.where == "center" then
		local ch = D.center(view, 0, 0, w, 1, nil, true, true)
		D.center(view, 1, (h - ch) / 2 + S(6), w - 2, 1, 0.65, false, true)
	else
		-- a fake chat with the line at the bottom
		local col = Color(it.col.r, it.col.g, it.col.b)
		local x, y = S(16), h - S(36)
		UI.Round(S(10), h - S(120), math.min(w - S(20), S(520)), S(110), S(6), Color(0, 0, 0, 110))
		UI.Text("Player: gg", "Praetor.Chat", x + S(26), y - S(56), Color(220, 220, 220, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text("Player2: o/", "Praetor.Chat", x + S(26), y - S(30), Color(220, 220, 220, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local sz = S(20)
		UI.Round(x, y - sz / 2, sz, sz, S(4), Color(col.r, col.g, col.b, 70), col)
		UI.Icon(it.icon, x + (sz - 16) / 2, y - 8, 16)
		local tx = x + sz + S(6)
		local title = (it.title or "") ~= "" and (it.title .. "  ") or ""
		surface.SetFont("Praetor.Chat")
		UI.Text("| ", "Praetor.Chat", tx, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		tx = tx + surface.GetTextSize("| ")
		UI.Text(title, "Praetor.Chat", tx, y, Color(math.min(255, col.r + 70), math.min(255, col.g + 70), math.min(255, col.b + 70)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		tx = tx + surface.GetTextSize(title)
		local rest = w - tx - S(16)
		local body = view.text .. (view.link and ("  " .. view.link) or "")
		UI.Text(UI.Fit(body, "Praetor.Chat", rest), "Praetor.Chat", tx, y, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.L("an_chat_life", { V = it.life }), "Praetor.Tiny", w - S(12), S(12), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

-- ------------------------------------------------------------------ editor

local function buildEditor(right, it, canManage, onDeleted)
	right:Clear()
	local foot = vgui.Create("DPanel", right)
	foot:Dock(BOTTOM)
	foot:SetTall(S(38))
	foot:DockMargin(0, S(8), 0, 0)
	foot.Paint = nil

	local prev = vgui.Create("DPanel", right)
	prev:Dock(TOP)
	prev:SetTall(S(190))
	prev:DockMargin(0, 0, 0, S(8))
	prev.Paint = function(_, w, h) drawPreview(it, w, h) end

	local sc = UI.Scroll(right)
	sc:Dock(FILL)

	-- where
	label(sc, P.L("an_where"), 0)
	local wr = vgui.Create("DPanel", sc)
	wr:Dock(TOP)
	wr:SetTall(S(62))
	wr.Paint = nil
	local cornerRow
	for _, wd in ipairs(WHERE) do
		local b = vgui.Create("DButton", wr)
		b:SetText("")
		b.Paint = function(s, w, h)
			local on = it.where == wd.id
			UI.Round(0, 0, w, h, S(8), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 45) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
			UI.Icon(wd.icon, S(10), S(10), 16, Color(255, 255, 255, on and 255 or 170))
			UI.Text(UI.Fit(P.L(wd.label), "Praetor.SmallB", w - S(36)), "Praetor.SmallB", S(32), S(18), on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(UI.Fit(P.L(wd.d), "Praetor.Tiny", w - S(18)), "Praetor.Tiny", S(10), S(43), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function()
			UI.Sound("click")
			it.where = wd.id
			if IsValid(cornerRow) then cornerRow:SetVisible(it.where == "popup") sc:InvalidateLayout() end
		end
	end
	wr.PerformLayout = function(s, w, h)
		local gap = S(6)
		local bw = (w - gap * 3) / 4
		local i = 0
		for _, c in ipairs(s:GetChildren()) do
			c:SetPos(i * (bw + gap), 0)
			c:SetSize(bw, h)
			i = i + 1
		end
	end

	cornerRow = chipRow(sc)
	cornerRow:DockMargin(0, S(6), 0, 0)
	for _, cn in ipairs({ { "tl", "an_c_tl" }, { "tr", "an_c_tr" }, { "bl", "an_c_bl" }, { "br", "an_c_br" } }) do
		chip(cornerRow, P.L(cn[2]), nil, function() return it.corner == cn[1] end, function() it.corner = cn[1] end)
	end
	cornerRow:SetVisible(it.where == "popup")

	-- texts
	label(sc, P.L("an_title"))
	local title = UI.Entry(sc, P.L("an_title_ph"), it.title, function(v) it.title = v end)
	title:Dock(TOP)
	label(sc, P.L("an_text"))
	local text = UI.Entry(sc, P.L("an_text_ph"), it.text, function(v) it.text = v:gsub("[\r\n]+", " ") end)
	text:SetMultiline(true)
	text:Dock(TOP)
	text:SetTall(S(70))
	label(sc, P.L("an_link"))
	local link = UI.Entry(sc, "https://discord.gg/...", it.link or "", function(v) it.link = v end)
	link:Dock(TOP)

	-- colour and icon
	label(sc, P.L("an_look"))
	local look = chipRow(sc, S(36))
	local iconBtn = vgui.Create("DButton", look)
	iconBtn:SetText("")
	iconBtn:Dock(LEFT)
	iconBtn:SetWide(S(150))
	iconBtn:DockMargin(0, 0, S(10), 0)
	iconBtn.Paint = function(s, w, h)
		local col = Color(it.col.r, it.col.g, it.col.b)
		UI.Round(0, 0, w, h, S(6), s:IsHovered() and C.hover or C.panel2, C.line)
		UI.Round(S(4), S(4), h - S(8), h - S(8), S(5), Color(col.r, col.g, col.b, 60), col)
		UI.Icon(it.icon, S(4) + (h - S(8) - 16) / 2, (h - 16) / 2, 16)
		UI.Text(P.L("an_icon"), "Praetor.Small", h + S(4), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Icon("pen", w - S(24), (h - 16) / 2, 16, Color(255, 255, 255, 140))
	end
	iconBtn.DoClick = function() UI.PickIcon(it.icon, function(name) it.icon = name end) end
	iconBtn:SetTooltip(P.L("an_icon_tip"))
	for _, c in ipairs(COLORS) do
		local b = vgui.Create("DButton", look)
		b:SetText("")
		b:Dock(LEFT)
		b:SetWide(S(28))
		b:DockMargin(0, S(4), S(4), S(4))
		b.Paint = function(s, w, h)
			local on = it.col.r == c.r and it.col.g == c.g and it.col.b == c.b
			UI.Round(0, 0, w, h, h / 2, Color(c.r, c.g, c.b), on and color_white or (s:IsHovered() and C.lineL or Color(0, 0, 0, 0)))
			if on then UI.Round(S(3), S(3), w - S(6), h - S(6), (h - S(6)) / 2, Color(c.r, c.g, c.b), Color(0, 0, 0, 160)) end
		end
		b.DoClick = function() UI.Sound("click") it.col = table.Copy(c) end
	end
	local custom = UI.Swatch(look, Color(it.col.r, it.col.g, it.col.b), function(c) it.col = { r = c.r, g = c.g, b = c.b } end)
	custom:Dock(LEFT)
	custom:SetWide(S(36))
	custom:SetTooltip(P.L("an_custom_col"))

	-- when, time on screen, who
	if canManage then
		label(sc, P.L("an_when"))
		local wh = chipRow(sc)
		local every
		for _, wn in ipairs({ { "timer", "clock", "an_when_timer" }, { "join", "door", "an_when_join" }, { "manual", "hand", "an_when_manual" } }) do
			chip(wh, P.L(wn[3]), wn[2], function() return it.when == wn[1] end, function()
				it.when = wn[1]
				if IsValid(every) then every:SetVisible(it.when == "timer") end
			end)
		end
		local opts = {}
		for _, m in ipairs({ 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240 }) do opts[#opts + 1] = { m, P.L("an_every_n", { V = m }) } end
		every = UI.Combo(wh, opts, it.every, function(v) it.every = v end)
		every:Dock(LEFT)
		every:SetWide(S(170))
		every:SetVisible(it.when == "timer")
	end

	label(sc, P.L("an_life"))
	local lr = chipRow(sc)
	for _, t in ipairs({ 5, 8, 10, 15, 20, 30, 45, 60 }) do
		chip(lr, t .. "s", nil, function() return it.life == t end, function() it.life = t end)
	end

	label(sc, P.L("an_who"))
	local wo = chipRow(sc)
	for _, wv in ipairs({ { "all", "players", "an_who_all" }, { "users", "user", "an_who_users" }, { "staff", "shield", "an_who_staff" } }) do
		chip(wo, P.L(wv[3]), wv[2], function() return it.who == wv[1] end, function() it.who = wv[1] end)
	end

	local snd = UI.Switch(sc, P.L("an_sound"), nil, it.snd ~= false, function(v) it.snd = v end)
	snd:Dock(TOP)
	snd:DockMargin(0, S(6), 0, 0)
	if canManage then
		local on = UI.Switch(sc, P.L("an_on"), P.L("an_on_d"), it.on ~= false, function(v) it.on = v end)
		on:Dock(TOP)
	end

	-- buttons
	-- it needs a title, a text or a link (a valid one): otherwise say what is missing
	local function empty()
		local link = P.Trim(it.link or "")
		if P.Trim(it.title or "") ~= "" or P.Trim(it.text or "") ~= "" or link:match("^https?://%S+$") then return false end
		UI.Sound("error")
		P.Toast(P.L("an_empty_t"), P.L("an_empty"), "warn", 4)
		title:RequestFocus()
		return true
	end
	local function cleanCopy()
		local c = table.Copy(it)
		c.link = P.Trim(c.link or "") ~= "" and P.Trim(c.link) or nil
		return c
	end
	if canManage then
		local save = UI.Button(foot, P.L("ui_save"), "primary", "check", function()
			if empty() then return end
			P.Request("ann_save", { it = cleanCopy() })
		end)
		save:Dock(RIGHT)
		save:SetWide(S(130))
	end
	local send = UI.Button(foot, P.L("an_send"), "ghost", "send", function()
		if empty() then return end
		UI.Confirm(P.L("an_send"), P.L("an_send_q"), function() P.Request("ann_send", { it = cleanCopy() }) end)
	end)
	send:Dock(RIGHT)
	send:SetWide(S(150))
	send:DockMargin(0, 0, S(8), 0)
	local test = UI.Button(foot, P.L("an_test"), "ghost", "eye", function()
		local c = cleanCopy()
		c.snd = c.snd and 1 or nil
		P.ShowAnn(c)
	end)
	test:Dock(RIGHT)
	test:SetWide(S(150))
	test:DockMargin(0, 0, S(8), 0)
	if canManage and it.id then
		local del = UI.Button(foot, "", "danger", "trash", function()
			UI.Confirm(P.L("an_delete"), P.L("an_delete_q"), function()
				P.Request("ann_del", { id = it.id })
				onDeleted()
			end, true)
		end)
		del:Dock(LEFT)
		del:SetWide(S(40))
		del:SetTooltip(P.L("an_delete"))
	end
end

-- ------------------------------------------------------------------ tab

P.AddTab("announce", {
	cat = "server", icon = "megaphone", order = 1.7,
	can = function() return P.MyHas("manage_announce") or P.MyHas("announce") end,
	build = function(panel)
		local canManage = P.MyHas("manage_announce")
		local list = {}
		local selId
		local right = vgui.Create("DPanel", panel)
		right.Paint = nil

		if not canManage then
			right:Dock(FILL)
			buildEditor(right, blank(), false, function() end)
			return
		end

		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:SetWide(S(300))
		left:DockMargin(0, 0, S(12), 0)
		left.Paint = nil
		right:Dock(FILL)

		local head = vgui.Create("DPanel", left)
		head:Dock(TOP)
		head:SetTall(S(34))
		head:DockMargin(0, 0, 0, S(8))
		head.Paint = function(_, w, h)
			UI.Text(P.L("an_saved_list"), "Praetor.H3", 0, h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local sc = UI.Scroll(left)
		sc:Dock(FILL)
		local fill
		local function open(it)
			selId = it.id
			buildEditor(right, it, true, function() selId = nil buildEditor(right, blank(), true, function() end) end)
		end
		local new = UI.Button(head, P.L("an_new"), "primary", "megaphone", function() selId = nil UI.Sound("click") buildEditor(right, blank(), true, function() end) fill() end)
		new:Dock(RIGHT)
		new:SetWide(S(110))

		fill = function()
			sc:Clear()
			if #list == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(130))
				e.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(8), C.panel, C.line)
					UI.Icon("megaphone", w / 2 - 16, S(20), 32, Color(255, 255, 255, 120))
					UI.Text(P.L("an_none"), "Praetor.BodyB", w / 2, S(72), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("an_none_d"), "Praetor.Tiny", w / 2, S(94), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			for i, it in ipairs(list) do
				local b = vgui.Create("DButton", sc)
				b:SetText("")
				b:Dock(TOP)
				b:SetTall(S(66))
				b:DockMargin(0, 0, S(4), S(6))
				b.hov = 0
				b.Paint = function(s, w, h)
					s.hov = UI.Lerp(s.hov, s:IsHovered() and 1 or 0, 14)
					local col = Color(it.col.r, it.col.g, it.col.b)
					local sel = selId == it.id
					UI.Round(0, 0, w, h, S(8), sel and Color(C.bronze.r, C.bronze.g, C.bronze.b, 35) or P.LerpColor(s.hov, C.panel2, C.hover), sel and C.bronze or C.line)
					UI.Round(0, S(10), S(3), h - S(20), S(1), col)
					UI.Round(S(10), (h - S(40)) / 2, S(40), S(40), S(8), Color(col.r, col.g, col.b, it.on and 60 or 20), Color(col.r, col.g, col.b, it.on and 220 or 80))
					UI.Icon(it.icon, S(10) + (S(40) - 32) / 2, (h - 32) / 2, 32, Color(255, 255, 255, it.on and 255 or 110))
					local x = S(60)
					local t = it.title ~= "" and it.title or it.text
					UI.Text(UI.Fit(t, "Praetor.BodyB", w - x - S(30)), "Praetor.BodyB", x, S(17), it.on and C.ivory or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local wd
					for _, x2 in ipairs(WHERE) do if x2.id == it.where then wd = x2 end end
					UI.Icon(wd and wd.icon or "pin", x, S(32), 16, Color(255, 255, 255, 150))
					UI.Text(UI.Fit(P.L(wd and wd.label or "an_w_popup") .. "  ·  " .. whenText(it), "Praetor.Tiny", w - x - S(30)), "Praetor.Tiny", x + 20, S(40), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					-- on / off dot
					UI.Round(w - S(18), S(12), S(8), S(8), S(4), it.on and C.laurel or C.dim)
				end
				b.DoClick = function() UI.Sound("click") open(table.Copy(it)) fill() end
				b.DoRightClick = function()
					UI.Popup({
						{ P.L("an_send"), "send", function() P.Request("ann_send", { it = it }) end },
						{ P.L(it.on and "an_turn_off" or "an_turn_on"), it.on and "eye_no" or "eye", function()
							local c = table.Copy(it)
							c.on = not it.on
							P.Request("ann_save", { it = c })
						end },
						{ P.L("an_duplicate"), "copy", function()
							local c = table.Copy(it)
							c.id = nil
							c.title = (c.title ~= "" and c.title or "") .. " (2)"
							P.Request("ann_save", { it = c })
						end },
						false,
						{ P.L("cu_move_up"), "chevdown", function() P.Request("ann_move", { i = i, d = -1 }) end },
						{ P.L("cu_move_down"), "chevdown", function() P.Request("ann_move", { i = i, d = 1 }) end },
						false,
						{ P.L("an_delete"), "trash", function()
							UI.Confirm(P.L("an_delete"), P.L("an_delete_q"), function()
								P.Request("ann_del", { id = it.id })
								if selId == it.id then selId = nil buildEditor(right, blank(), true, function() end) end
							end, true)
						end, true },
					})
				end
			end
		end

		buildEditor(right, blank(), true, function() end)
		fill()
		P.On("ann_list", function(d)
			list = d.list or {}
			if IsValid(sc) then fill() end
		end)
		P.On("ann_saved", function(d)
			if not IsValid(right) then return end
			for _, it in ipairs(list) do if it.id == d.id then open(table.Copy(it)) end end
			if IsValid(sc) then fill() end
		end)
		P.Request("ann_list", {})
	end,
})
