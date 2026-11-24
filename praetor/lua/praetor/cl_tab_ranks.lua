-- Praetor menu: rank editor. Authority (0-100) decides who can act on whom;
-- nobody can give a rank a permission they do not have themselves.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local current

local function permState(r, id)
	local v = r.perms and r.perms[id]
	if v == true then return "allow" elseif v == false then return "deny" end
	return "inherit"
end

-- minutes -> "1w2d3h5m" (every part, so the field reads back the same value)
local function exactDur(min)
	min = math.floor(tonumber(min) or 0)
	local out = ""
	for _, u in ipairs({ { "w", 10080 }, { "d", 1440 }, { "h", 60 }, { "m", 1 } }) do
		local n = math.floor(min / u[2])
		if n > 0 then out = out .. n .. u[1] min = min - n * u[2] end
	end
	return out
end

local function editor(right, name)
	right:Clear()
	local r = P.Ranks[name]
	if not r then return end
	local can = P.CanManageRank(LocalPlayer(), name)
	local edit = table.Copy(r)
	edit.perms = edit.perms or {}
	edit.limits = edit.limits or {}
	edit.block = edit.block or { tools = {}, ents = {}, weps = {} }
	local permChanges = {}

	local sc = UI.Scroll(right)
	sc:Dock(FILL)
	local foot = vgui.Create("DPanel", right)
	foot:Dock(BOTTOM)
	foot:SetTall(S(46))
	foot:DockMargin(0, S(4), 0, 0)
	-- a line on top: the editor scrolls behind it, so the cut is clear
	foot.Paint = function(_, w) UI.Rect(0, 0, w, 1, C.line) end
	foot:DockPadding(0, S(6), 0, 0)

	if not can then
		local warn = UI.Label(sc, P.L("rk_locked"), "Praetor.SmallB", C.crimsonL)
		warn:Dock(TOP)
		warn:DockMargin(0, 0, 0, S(6))
	end

	-- a title and its control. The control is made first (it is the argument),
	-- so the title takes its place in the order and the control goes right
	-- after it: before, every title showed up under its own field.
	local function field(label, ctl, tall, hint)
		local l = UI.Label(sc, label, "Praetor.SmallB", C.muted)
		l:Dock(TOP)
		l:DockMargin(0, S(10), 0, S(3))
		ctl:SetParent(sc)
		ctl:Dock(TOP)
		local zc, zl = ctl:GetZPos(), l:GetZPos()
		if zc < zl then l:SetZPos(zc) ctl:SetZPos(zl) end
		if tall then ctl:SetTall(tall) end
		if hint then
			local hl = UI.Label(sc, hint, "Praetor.Tiny", C.dim)
			hl:SetWrap(true)
			hl:SetAutoStretchVertical(true)
			hl:Dock(TOP)
			hl:DockMargin(0, S(3), 0, 0)
			hl:SetZPos(math.max(zc, zl) + 1)
			ctl.hintLabel = hl
		end
		return ctl
	end

	UI.Section(sc, P.L("rk_identity"), "rank: " .. name)
	local display = field(P.L("rk_display"), UI.Entry(sc, "", edit.display or name))
	local style = field(P.L("rk_style"), UI.StyleEdit(sc, edit.style, { icon = false, maxLen = 24 }), S(170))
	local iconRow = vgui.Create("DPanel", sc)
	field(P.L("rk_icon"), iconRow, S(40))
	iconRow.Paint = function(_, w, h)
		UI.Notch(0, 0, S(40), h, S(4), C.panel2, C.line)
		UI.Icon(edit.icon or "leaf", (S(40) - 32) / 2, (h - 32) / 2, 32)
		UI.Badge(style:GetStyle() or edit.style, edit.icon, "Praetor.Tag", S(150), (h - S(24)) / 2, S(24))
	end
	local pickIcon = UI.Button(iconRow, P.L("rk_pick_icon"), "ghost", nil, function()
		UI.PickIcon(edit.icon, function(n) edit.icon = n end)
	end)
	pickIcon:SetPos(S(48), 0)
	pickIcon:SetSize(S(94), S(40))

	local chatCol = vgui.Create("DPanel", sc)
	field(P.L("rk_chat_color"), chatCol, S(34))
	chatCol.Paint = nil
	local sw = UI.Swatch(chatCol, edit.chat_color and P.ReadColor(edit.chat_color, color_white) or color_white, function(c) edit.chat_color = { r = c.r, g = c.g, b = c.b } end)
	sw:Dock(LEFT)
	local clearCol = UI.Button(chatCol, P.L("rk_default"), "ghost", nil, function() edit.chat_color = false sw.col = color_white end)
	clearCol:Dock(LEFT)
	clearCol:SetWide(S(110))
	clearCol:DockMargin(S(6), 0, 0, 0)

	UI.Section(sc, P.L("rk_power"), P.L("rk_power_sub"))
	local imm = field(P.L("rk_authority"), UI.Entry(sc, "0-100", tostring(edit.immunity or 0)))
	imm:SetNumeric(true)
	local inh
	if name ~= "user" then
		local opts = {}
		for _, o in ipairs(P.SortedRanks()) do if o.name ~= name then opts[#opts + 1] = { o.name, o.display or o.name } end end
		inh = field(P.L("rk_inherit"), UI.Combo(sc, opts, edit.inherit or "user"))
	end
	local gopts = { { "", P.L("rg_none") } }
	for _, g in ipairs(P.SortedRankGroups()) do gopts[#gopts + 1] = { g.id, g.name .. (g.staff and ("  (" .. P.L("rg_staff_tag") .. ")") or "") } end
	local grp = field(P.L("rg_field"), UI.Combo(sc, gopts, edit.group or ""))

	-- punishments: the longest ban (commands, ban tab and the !voteban this rank starts)
	UI.Section(sc, P.L("rk_pun"), P.L("rk_pun_sub"))
	local banLimit = field(P.L("rk_ban_max"), UI.DurationField(sc, (edit.ban_limit or 0) > 0 and exactDur(edit.ban_limit) or "", { noLimit = true }), nil, P.L("rk_ban_max_d"))

	-- automatic promotion: from which rank, after how much time played
	UI.Section(sc, P.L("rk_promo_sec"), P.L("rk_promo_sec_sub"))
	local popts = { { "", P.L("rk_promote_off") } }
	for _, o in ipairs(P.SortedRanks()) do if o.name ~= name then popts[#popts + 1] = { o.name, o.display or o.name } end end
	local promoFrom = field(P.L("rk_promo_from"), UI.Combo(sc, popts, edit.promote and edit.promote.from or ""))
	local promoMin = edit.promote and math.floor((tonumber(edit.promote.hours) or 0) * 60 + 0.5) or 0
	local promoTime = field(P.L("rk_promo_time"), UI.DurationField(sc, promoMin > 0 and exactDur(promoMin) or "", { chips = { "1h", "5h", "1d", "3d", "1w", "1mo" }, noPerm = true }), nil, P.L("rk_promo_time_d"))

	UI.Section(sc, P.L("rk_limits"), P.L("rk_limits_sub"))
	local limitGrid = vgui.Create("DIconLayout", sc)
	limitGrid:Dock(TOP)
	limitGrid:SetSpaceX(S(6))
	limitGrid:SetSpaceY(S(6))
	local limitEntries = {}
	for _, k in ipairs(P.LimitKeys) do
		local cell = limitGrid:Add("DPanel")
		cell:SetSize(S(150), S(56))
		cell.Paint = function(_, w) UI.Text(P.L("lim_" .. k), "Praetor.Tiny", 0, 0, C.muted) end
		local e = UI.Entry(cell, P.L("rk_default"), edit.limits[k] and tostring(edit.limits[k]) or "")
		e:SetPos(0, S(18))
		e:SetSize(S(150), S(34))
		limitEntries[k] = e
	end
	local function listField(label, list)
		return field(label, UI.Entry(sc, "weapon_rpg, gmod_tool_x ...", table.concat(list or {}, ", ")))
	end
	local blockTools = listField(P.L("rk_block_tools"), edit.block.tools)
	local blockEnts = listField(P.L("rk_block_ents"), edit.block.ents)
	local blockWeps = listField(P.L("rk_block_weps"), edit.block.weps)

	-- permissions: one click switches between allowed (green tick) and denied
	-- (red cross); "inherited" means the value comes from the inherited rank.
	-- Right click: allow / deny / inherit.
	UI.Section(sc, P.L("rk_perms"), P.L("rk_perms_sub"))
	local byCat = {}
	for id, p in pairs(P.Perms) do
		byCat[p.cat or "addons"] = byCat[p.cat or "addons"] or {}
		table.insert(byCat[p.cat or "addons"], id)
	end
	local cats = {}
	for _, c in ipairs({ "general", "moderation", "teleport", "player", "fun", "chat", "users", "ranks", "tags", "reports", "logs", "spawn", "server", "darkrp", "custom", "addons" }) do
		if byCat[c] then cats[#cats + 1] = c end
	end
	for c in pairs(byCat) do if not table.HasValue(cats, c) then cats[#cats + 1] = c end end
	local me = LocalPlayer()

	local function inherited(id)
		if name == "user" then return P.Perms[id] and P.Perms[id].def == "user" or false end
		return P.RankHas(edit.inherit or "user", id)
	end
	local function stateOf(id) return permChanges[id] or permState(edit, id) end
	local function effective(id)
		local st = stateOf(id)
		if st == "allow" then return true elseif st == "deny" then return false end
		return inherited(id)
	end
	-- sets a value; when it matches the inherited one it goes back to "inherit"
	local function setPerm(id, allow)
		if allow == inherited(id) then permChanges[id] = "inherit"
		else permChanges[id] = allow and "allow" or "deny" end
	end
	local function canEdit(id) return can and (P.IsOwner(me) or P.Has(me, id)) end
	local function labelOf(id)
		local label = P.L("perm_" .. id, nil, "")
		if label == "" then
			local help = P.L("h_" .. id, nil, "")
			label = help ~= "" and ("!" .. id .. "  -  " .. help) or id
		end
		return label
	end
	local function iconOf(id, cat)
		if P.ServerCmds[id] or P.CmdIcons[id] then return P.CmdIcon(id) end
		return P.CatIcons[cat] or "key"
	end

	local bar = vgui.Create("DPanel", sc)
	bar:Dock(TOP)
	bar:SetTall(S(34))
	bar:DockMargin(0, 0, 0, S(4))
	bar.Paint = nil
	local search = UI.Entry(bar, P.L("rk_perm_search"))
	search:Dock(FILL)
	local legend = vgui.Create("DPanel", bar)
	legend:Dock(RIGHT)
	legend:SetWide(S(250))
	legend.Paint = function(_, w, h)
		UI.Icon("check", S(10), (h - 16) / 2, 16)
		UI.Text(P.L("perm_allow"), "Praetor.Tiny", S(30), h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Icon("cross", S(96), (h - 16) / 2, 16)
		UI.Text(P.L("perm_deny"), "Praetor.Tiny", S(116), h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.L("rk_perm_rclick"), "Praetor.Tiny", w, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local box = vgui.Create("DPanel", sc)
	box:Dock(TOP)
	box.Paint = nil
	local ROW, HEAD = S(34), S(34)

	local function permRow(id, cat)
		local row = vgui.Create("DButton", box)
		row:SetText("")
		row:Dock(TOP)
		row:SetTall(ROW - S(2))
		row:DockMargin(0, 0, 0, S(2))
		row.hov = 0
		local label = labelOf(id)
		local icon = iconOf(id, cat)
		local editable = canEdit(id)
		row:SetCursor(editable and "hand" or "no")
		row.Paint = function(s2, w, h)
			s2.hov = UI.Lerp(s2.hov, (s2:IsHovered() and editable) and 1 or 0, 16)
			local eff = effective(id)
			local st = stateOf(id)
			local tint = eff and C.laurel or C.crimson
			UI.Round(0, 0, w, h, S(5), P.LerpColor(s2.hov, C.panel2, C.hover), s2.hov > 0.05 and Color(tint.r, tint.g, tint.b, 120 * s2.hov) or nil)
			-- tick / cross box
			local bs = h - S(8)
			UI.Round(S(4), S(4), bs, bs, S(5), Color(tint.r, tint.g, tint.b, editable and 60 or 25), Color(tint.r, tint.g, tint.b, editable and 160 or 60))
			local isz = UI.IconSize(bs)
			if isz > bs + S(4) then isz = 16 end
			UI.Icon(eff and "check" or "cross", S(4) + (bs - isz) / 2, S(4) + (bs - isz) / 2, isz, Color(255, 255, 255, editable and 255 or 110))
			-- command icon + text
			local x = S(4) + bs + S(10)
			UI.Icon(icon, x, (h - 16) / 2, 16, Color(255, 255, 255, editable and 255 or 110))
			x = x + 16 + S(8)
			local right = S(10)
			if st == "inherit" then
				surface.SetFont("Praetor.Tiny")
				local tw = surface.GetTextSize(P.L("rk_inherited")) + S(12)
				UI.Round(w - right - tw, (h - S(16)) / 2, tw, S(16), S(8), C.panel3)
				UI.Text(P.L("rk_inherited"), "Praetor.Tiny", w - right - tw / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				right = right + tw + S(8)
			end
			if not editable then
				UI.Icon("key", w - right - 16, (h - 16) / 2, 16, Color(255, 255, 255, 70))
				right = right + 16 + S(8)
			end
			surface.SetFont("Praetor.Tiny")
			local iw = surface.GetTextSize(id)
			local showId = w - x - right - iw > S(180)
			if showId then UI.Text(id, "Praetor.Tiny", w - right, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) right = right + iw + S(10) end
			UI.Text(UI.Fit(label, "Praetor.Small", w - x - right), "Praetor.Small", x, h / 2, editable and (eff and C.ivory or C.muted) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		row.DoClick = function()
			if not editable then return end
			UI.Sound("click")
			setPerm(id, not effective(id))
		end
		row.DoRightClick = function()
			if not editable then return end
			UI.Popup({
				{ P.L("perm_allow"), "check", function() permChanges[id] = "allow" end },
				{ P.L("perm_deny"), "cross", function() permChanges[id] = "deny" end },
				{ P.L("perm_inherit") .. "  (" .. (inherited(id) and P.L("perm_allow") or P.L("perm_deny")) .. ")", "undo", function() permChanges[id] = "inherit" end },
			})
		end
		row:SetTooltip(id)
	end

	local function catHead(cat, ids)
		local head = vgui.Create("DPanel", box)
		head:Dock(TOP)
		head:SetTall(HEAD - S(4))
		head:DockMargin(0, S(4), 0, 0)
		local catName = P.Upper(P.L("cat_" .. cat, nil, cat))
		local tint = P.CatTint and P.CatTint(cat) or C.bronze
		head.Paint = function(_, w, h)
			local on = 0
			for _, id in ipairs(ids) do if effective(id) then on = on + 1 end end
			UI.Round(0, (h - S(22)) / 2, S(22), S(22), S(5), Color(tint.r, tint.g, tint.b, 50))
			UI.Icon(P.CatIcons[cat] or "key", (S(22) - 16) / 2, (h - 16) / 2, 16)
			UI.Text(catName, "Praetor.SmallB", S(30), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetFont("Praetor.SmallB")
			local tw = surface.GetTextSize(catName)
			UI.Text(on .. " / " .. #ids, "Praetor.Tiny", S(30) + tw + S(8), h / 2, on == #ids and C.laurel or (on == 0 and C.crimsonL or C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		if not can then return end
		local none = UI.Button(head, P.L("rk_deny_all"), "subtle", "cross", function()
			for _, id in ipairs(ids) do if canEdit(id) then setPerm(id, false) end end
		end)
		none:SetFont("Praetor.Tiny")
		none:SizeToLabel(S(8))
		none:Dock(RIGHT)
		none:DockMargin(S(4), S(2), 0, S(2))
		local all = UI.Button(head, P.L("rk_allow_all"), "subtle", "check", function()
			for _, id in ipairs(ids) do if canEdit(id) then setPerm(id, true) end end
		end)
		all:SetFont("Praetor.Tiny")
		all:SizeToLabel(S(8))
		all:Dock(RIGHT)
		all:DockMargin(S(4), S(2), 0, S(2))
	end

	local function fillPerms()
		box:Clear()
		local q = P.Trim(search:GetValue()):lower()
		local total = 0
		for _, cat in ipairs(cats) do
			table.sort(byCat[cat])
			local ids = {}
			for _, id in ipairs(byCat[cat]) do
				if q == "" or id:find(q, 1, true) or labelOf(id):lower():find(q, 1, true) then ids[#ids + 1] = id end
			end
			if #ids > 0 then
				catHead(cat, ids)
				total = total + HEAD
				for _, id in ipairs(ids) do
					permRow(id, cat)
					total = total + ROW
				end
			end
		end
		if total == 0 then
			local l = UI.Label(box, P.L("ui_empty"), "Praetor.Small", C.dim)
			l:Dock(TOP)
			total = S(24)
		end
		box:SetTall(total + S(4))
	end
	search.OnChange = fillPerms
	fillPerms()
	if can then
		local save = UI.Button(foot, P.L("ui_save"), "primary", "laurel", function()
			local out = {
				display = display:GetValue(),
				style = style:GetStyle(),
				icon = edit.icon,
				chat_color = edit.chat_color,
				immunity = tonumber(imm:GetValue()) or edit.immunity,
				ban_limit = banLimit:GetMinutes() or 0,
				limits = {}, block = {}, perms = {},
			}
			if inh then local _, v = inh:GetSelected() out.inherit = v end
			local _, gv = grp:GetSelected()
			out.group = (gv and gv ~= "") and gv or false
			local _, pf = promoFrom:GetSelected()
			local pm = promoTime:GetMinutes()
			if pf and pf ~= "" and (not pm or pm < 1) then P.Toast(P.L("rk_promo_sec"), P.L("err_promo_hours"), "warn") return end
			out.promote = (pf and pf ~= "" and pm) and { from = pf, hours = pm / 60 } or false
			for k, e in pairs(limitEntries) do
				local v = tonumber(e:GetValue())
				if v then out.limits[k] = v end
			end
			local function split(e)
				local t = {}
				for w in e:GetValue():gmatch("[^,%s]+") do t[#t + 1] = w end
				return t
			end
			out.block = { tools = split(blockTools), ents = split(blockEnts), weps = split(blockWeps) }
			for id, v in pairs(permChanges) do
				if v == "allow" then out.perms[id] = true elseif v == "deny" then out.perms[id] = false else out.perms[id] = "inherit" end
			end
			P.Request("rank_update", { name = name, r = out })
		end)
		save:Dock(RIGHT)
		save:SetWide(S(150))
		if not P.ProtectedRanks[name] then
			local del = UI.Button(foot, P.L("ui_delete"), "danger", nil, function()
				UI.Confirm(P.L("rk_delete"), P.L("rk_delete_q", { S = name }), function()
					P.Request("rank_delete", { name = name })
					current = nil
				end, true)
			end)
			del:Dock(LEFT)
			del:SetWide(S(120))
			local ren = UI.Button(foot, P.L("rk_rename"), "ghost", nil, function()
				UI.Form(P.L("rk_rename"), { { "new", "text", P.L("rk_new_id"), name } }, function(v)
					P.Request("rank_rename", { old = name, new = v.new })
					current = v.new:lower()
				end)
			end)
			ren:Dock(LEFT)
			ren:SetWide(S(120))
			ren:DockMargin(S(6), 0, 0, 0)
		end
	end
end

-- window to create / edit a rank group: name, colour, icon, "is staff" and the
-- ranks inside it
local function groupEditor(g)
	local editing = g ~= nil
	g = g or { name = "", col = { r = 146, g = 172, b = 255 }, icon = "shield", staff = false }
	local col = P.ReadColor(g.col, C.bronzeL)
	local icon = g.icon or "shield"
	local m = UI.Modal(editing and P.L("rg_edit") or P.L("rg_new"), S(480), S(600))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)

	local function label(t)
		local l = UI.Label(sc, t, "Praetor.SmallB", C.muted)
		l:Dock(TOP)
		l:DockMargin(0, S(6), 0, S(3))
	end

	label(P.L("rg_name"))
	local name = UI.Entry(sc, "Staff", g.name or "")
	name:Dock(TOP)

	label(P.L("rg_look"))
	local look = vgui.Create("DPanel", sc)
	look:Dock(TOP)
	look:SetTall(S(40))
	look.Paint = function(_, w, h)
		local x = S(98)
		UI.Round(x, (h - S(28)) / 2, S(4), S(28), S(2), col)
		UI.Icon(icon, x + S(12), (h - 16) / 2, 16)
		local n = P.Trim(name:GetValue())
		UI.Text(UI.Fit(P.Upper(n ~= "" and n or "Staff"), "Praetor.SmallB", w - x - S(40)), "Praetor.SmallB", x + S(34), h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local sw = UI.Swatch(look, col, function(c) col = c end)
	sw:SetPos(0, S(3))
	local ib = UI.Button(look, "", "ghost", nil, function()
		UI.PickIcon(icon, function(n) if n then icon = n end end)
	end)
	ib:SetPos(S(40), S(3))
	ib:SetSize(S(46), S(34))
	ib.PaintOver = function(_, w, h) UI.Icon(icon, (w - 16) / 2, (h - 16) / 2, 16) end

	local staff = UI.Switch(sc, P.L("rg_staff"), P.L("rg_staff_d"), g.staff == true)
	staff:Dock(TOP)
	staff:DockMargin(0, S(10), 0, 0)

	label(P.L("rg_ranks"))
	local picked = {}
	for _, r in ipairs(P.SortedRanks()) do
		if r.name ~= "user" or not editing then
			picked[r.name] = editing and r.group == g.id or false
			local row = vgui.Create("DButton", sc)
			row:SetText("")
			row:Dock(TOP)
			row:SetTall(S(34))
			row:DockMargin(0, 0, 0, S(3))
			local can = P.CanManageRank(LocalPlayer(), r.name) or P.IsOwner(LocalPlayer())
			local other = r.group and r.group ~= g.id and P.RankGroups[r.group]
			row.Paint = function(s, w, h)
				local on = picked[r.name]
				UI.Round(0, 0, w, h, S(5), on and Color(col.r, col.g, col.b, 30) or (s:IsHovered() and C.hover or C.panel2), on and Color(col.r, col.g, col.b, 140) or nil)
				-- check box
				UI.Round(S(10), (h - S(16)) / 2, S(16), S(16), S(4), on and col or C.bg, on and nil or C.lineL)
				local style, ic = UI.RankStyle(r)
				UI.Badge(style, ic, "Praetor.Tiny", S(36), (h - S(20)) / 2, S(20))
				if other and not on then
					UI.Text(P.L("rg_in", { S = other.name }), "Praetor.Tiny", w - S(10), h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				end
			end
			if can then
				row.DoClick = function() picked[r.name] = not picked[r.name] UI.Sound("click") end
			else
				row:SetEnabled(false)
			end
		end
	end

	local save = UI.Button(m.foot, P.L("ui_save"), "primary", nil, function()
		local n = P.Trim(name:GetValue())
		if n == "" then name:RequestFocus() return end
		local ranks = {}
		for rn, on in pairs(picked) do if on then ranks[#ranks + 1] = rn end end
		P.Request("rgroup_save", { id = editing and g.id or nil, name = n, col = { r = col.r, g = col.g, b = col.b }, icon = icon, staff = staff:GetValue(), ranks = ranks })
		m:Close()
	end)
	save:Dock(RIGHT)
	save:SetWide(S(130))
	if editing then
		local del = UI.Button(m.foot, P.L("rg_delete"), "danger", nil, function()
			UI.Confirm(P.L("rg_delete"), P.L("rg_delete_q", { S = g.name }), function()
				P.Request("rgroup_delete", { id = g.id })
				m:Close()
			end, true)
		end)
		del:Dock(LEFT)
		del:SetWide(S(130))
	end
end
P.RankGroupEditor = groupEditor

P.AddTab("ranks", {
	cat = "management", icon = "crown", order = 2,
	can = function() return P.MyHas("manage_ranks") end,
	build = function(panel)
		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:SetWide(S(290))
		left:DockMargin(0, 0, S(12), 0)
		left.Paint = nil
		local right = vgui.Create("DPanel", panel)
		right:Dock(FILL)
		right.Paint = nil

		local top = vgui.Create("DPanel", left)
		top:Dock(TOP)
		top:SetTall(S(36))
		top:DockMargin(0, 0, 0, S(8))
		top.Paint = nil
		local new = UI.Button(top, P.L("rk_new"), "primary", "crown", function()
			local gopts = { { "", P.L("rg_none") } }
			for _, g in ipairs(P.SortedRankGroups()) do gopts[#gopts + 1] = { g.id, g.name } end
			UI.Form(P.L("rk_new"), {
				{ "name", "text", P.L("rk_new_id"), "", "vip_plus" },
				{ "display", "text", P.L("rk_display"), "" },
				{ "immunity", "number", P.L("rk_authority"), 10 },
				{ "inherit", "rank", P.L("rk_inherit"), "user" },
				{ "group", "choice", P.L("rg_field"), "", gopts },
			}, function(v)
				P.Request("rank_create", { name = v.name, display = v.display ~= "" and v.display or v.name, immunity = v.immunity, inherit = v.inherit, group = v.group ~= "" and v.group or nil })
				current = tostring(v.name or ""):lower()
			end, P.L("rk_create"))
		end)
		new:Dock(FILL)
		local newGroup = UI.Button(top, P.L("rg_new_short"), "ghost", "players", function() groupEditor(nil) end)
		newGroup:Dock(RIGHT)
		newGroup:SetWide(S(104))
		newGroup:DockMargin(S(6), 0, 0, 0)
		newGroup:SetTooltip(P.L("rg_new"))

		local list = UI.Scroll(left)
		list:Dock(FILL)

		local function rankButton(r, indent)
			local b = vgui.Create("DButton", list)
			b:SetText("")
			b:Dock(TOP)
			b:SetTall(S(42))
			b:DockMargin(indent, 0, 0, S(3))
			b.Paint = function(s, w, h)
				local on = current == r.name
				UI.Round(0, 0, w, h, S(6), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 38) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or nil)
				local style, icon = UI.RankStyle(r)
				UI.Badge(style, icon, "Praetor.Tag", S(10), (h - S(24)) / 2, S(24))
				UI.Text(tostring(r.immunity or 0), "Praetor.BodyB", w - S(10), h / 2 - S(7), C.bronzeL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				UI.Text(r.name, "Praetor.Tiny", w - S(10), h / 2 + S(9), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				if not P.CanManageRank(LocalPlayer(), r.name) then UI.Icon("key", w - S(64), (h - 16) / 2, 16, Color(255, 255, 255, 120)) end
			end
			b.DoClick = function() current = r.name UI.Sound("click") editor(right, r.name) end
		end

		-- group header: coloured bar, icon, name, STAFF pill, count; click = edit
		local function groupHead(g, count)
			local hd = vgui.Create("DButton", list)
			hd:SetText("")
			hd:Dock(TOP)
			hd:SetTall(S(30))
			hd:DockMargin(0, S(8), 0, S(4))
			local col = g and P.ReadColor(g.col, C.bronzeL) or C.dim
			hd.Paint = function(s, w, h)
				if g and s:IsHovered() then UI.Round(0, 0, w, h, S(5), Color(255, 255, 255, 8)) end
				UI.Round(0, S(5), S(3), h - S(10), S(1), col)
				local x = S(10)
				if g then UI.Icon(g.icon, x, (h - 16) / 2, 16) x = x + S(22) end
				local title = P.Upper(g and g.name or P.L("rg_none"))
				UI.Text(UI.Fit(title, "Praetor.SmallB", w - S(140)), "Praetor.SmallB", x, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				surface.SetFont("Praetor.SmallB")
				x = x + math.min(surface.GetTextSize(title), w - S(140)) + S(8)
				if g and g.staff then
					local t = P.L("rg_staff_tag")
					surface.SetFont("Praetor.Tiny")
					local tw = surface.GetTextSize(t) + S(10)
					UI.Round(x, (h - S(16)) / 2, tw, S(16), S(8), Color(C.bronze.r, C.bronze.g, C.bronze.b, 50))
					UI.Text(t, "Praetor.Tiny", x + tw / 2, h / 2, C.bronzeL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				UI.Text(tostring(count), "Praetor.Tiny", w - S(10), h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				if g and s:IsHovered() then UI.Icon("gear", w - S(34), (h - 16) / 2, 16, Color(255, 255, 255, 150)) end
			end
			if g then
				hd.DoClick = function() UI.Sound("click") groupEditor(g) end
				hd.DoRightClick = function()
					UI.Popup({
						{ P.L("rg_edit"), "gear", function() groupEditor(g) end },
						{ P.L("rg_delete"), "skull", function()
							UI.Confirm(P.L("rg_delete"), P.L("rg_delete_q", { S = g.name }), function() P.Request("rgroup_delete", { id = g.id }) end, true)
						end, true },
					})
				end
			else
				hd:SetCursor("arrow")
			end
		end

		local byGroup, loose = {}, {}
		for _, r in ipairs(P.SortedRanks()) do
			if r.group and P.RankGroups[r.group] then
				byGroup[r.group] = byGroup[r.group] or {}
				table.insert(byGroup[r.group], r)
			else
				loose[#loose + 1] = r
			end
		end
		for _, g in ipairs(P.SortedRankGroups()) do
			local rs = byGroup[g.id] or {}
			groupHead(g, #rs)
			for _, r in ipairs(rs) do rankButton(r, S(8)) end
			if #rs == 0 then
				local e = vgui.Create("DPanel", list)
				e:Dock(TOP)
				e:SetTall(S(26))
				e:DockMargin(S(8), 0, 0, S(3))
				e.Paint = function(_, w, h) UI.Text(P.L("rg_empty"), "Praetor.Tiny", S(10), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			end
		end
		if #loose > 0 then
			groupHead(nil, #loose)
			for _, r in ipairs(loose) do rankButton(r, S(8)) end
		end

		local info = UI.Label(left, P.L("rk_info") .. " " .. P.L("rg_info"), "Praetor.Tiny", C.dim)
		info:SetWrap(true)
		info:SetAutoStretchVertical(true)
		info:Dock(BOTTOM)
		info:DockMargin(0, S(6), 0, 0)

		-- no empty right side: open the rank picked before, or the highest one
		if not (current and P.Ranks[current]) then
			local first = P.SortedRanks()[1]
			current = first and first.name or nil
		end
		if current then editor(right, current) end
	end,
})

-- the rank list changes after every save: rebuild the tab when it is open
hook.Add("Praetor.RanksUpdated", "Praetor.RanksTab", function()
	if IsValid(P.Menu) and P.Menu.current == "ranks" then P.Menu:SelectTab("ranks") end
end)
