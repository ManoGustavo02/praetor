-- Praetor menu: users (online and offline) and the full player sheet.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local state = { q = "", rank = "" }

-- ------------------------------------------------------------------ permission overrides

-- Overrides for one player. Each row has three buttons: allow (tick), from the
-- rank (shows what the rank gives) and deny (cross). One click sets it.
local function permEditor(sid, name, current, rank)
	local m = UI.Modal(P.L("usr_perms") .. ": " .. name, S(620), S(640))
	local intro = UI.Label(m.body, P.L("usr_perms_intro"), "Praetor.Small", C.muted)
	intro:SetWrap(true)
	intro:SetAutoStretchVertical(true)
	intro:Dock(TOP)
	intro:DockMargin(0, 0, 0, S(6))
	local val = {}
	for p in pairs(current.allow or {}) do val[p] = "allow" end
	for p in pairs(current.deny or {}) do val[p] = "deny" end
	local byCat = {}
	for id, p in pairs(P.Perms) do
		if P.MyHas(id) or P.IsOwner(LocalPlayer()) then
			byCat[p.cat or "addons"] = byCat[p.cat or "addons"] or {}
			table.insert(byCat[p.cat or "addons"], id)
		end
	end
	local cats = table.GetKeys(byCat)
	table.sort(cats)
	local function labelOf(id)
		local label = P.L("perm_" .. id, nil, "")
		if label == "" then
			local help = P.L("h_" .. id, nil, "")
			label = help ~= "" and ("!" .. id .. "  -  " .. help) or id
		end
		return label
	end

	local search = UI.Entry(m.body, P.L("rk_perm_search"))
	search:Dock(TOP)
	search:DockMargin(0, 0, 0, S(6))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)

	local SEG = S(36)
	local function segBtn(row, kind, x)
		local b = vgui.Create("DButton", row)
		b:SetText("")
		b.hov = 0
		b.slot = x
		b:SetSize(SEG - S(2), row:GetTall() - S(8))
		local tips = { allow = P.L("perm_allow"), inherit = P.L("perm_inherit"), deny = P.L("perm_deny") }
		b:SetTooltip(tips[kind])
		b.Paint = function(s2, w, h)
			s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 16)
			local cur = val[row.id] or "inherit"
			local on = cur == kind
			local tint = kind == "allow" and C.laurel or (kind == "deny" and C.crimson or C.lineL)
			local fill = on and Color(tint.r, tint.g, tint.b, kind == "inherit" and 120 or 90) or P.LerpColor(s2.hov, C.panel3, C.hover)
			UI.Round(0, 0, w, h, S(5), fill, on and tint or nil)
			local icon = kind == "allow" and "check" or (kind == "deny" and "cross" or "undo")
			UI.Icon(icon, (w - 16) / 2, (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 90 + 100 * s2.hov))
		end
		b.DoClick = function()
			UI.Sound("click")
			val[row.id] = kind ~= "inherit" and kind or nil
		end
		return b
	end

	local function fill()
		sc:Clear()
		local q = P.Trim(search:GetValue()):lower()
		local any = false
		for _, cat in ipairs(cats) do
			table.sort(byCat[cat])
			local ids = {}
			for _, id in ipairs(byCat[cat]) do
				if q == "" or id:find(q, 1, true) or labelOf(id):lower():find(q, 1, true) then ids[#ids + 1] = id end
			end
			if #ids > 0 then
				any = true
				local tint = P.CatTint and P.CatTint(cat) or C.bronze
				local catName = P.Upper(P.L("cat_" .. cat, nil, cat))
				local head = vgui.Create("DPanel", sc)
				head:Dock(TOP)
				head:SetTall(S(30))
				head:DockMargin(0, S(6), S(4), S(2))
				head.Paint = function(_, w, h)
					UI.Round(0, (h - S(22)) / 2, S(22), S(22), S(5), Color(tint.r, tint.g, tint.b, 50))
					UI.Icon(P.CatIcons[cat] or "key", (S(22) - 16) / 2, (h - 16) / 2, 16)
					UI.Text(catName, "Praetor.SmallB", S(30), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					-- column titles over the three buttons
					for i, k in ipairs({ "check", "undo", "cross" }) do
						UI.Icon(k, w - S(6) - SEG * (4 - i) + (SEG - S(2) - 16) / 2, (h - 16) / 2, 16, Color(255, 255, 255, 60))
					end
				end
				for _, id in ipairs(ids) do
					local row = vgui.Create("DPanel", sc)
					row.id = id
					row:Dock(TOP)
					row:SetTall(S(34))
					row:DockMargin(0, 0, S(4), S(2))
					local label = labelOf(id)
					local icon = (P.ServerCmds[id] or P.CmdIcons[id]) and P.CmdIcon(id) or (P.CatIcons[cat] or "key")
					row.Paint = function(_, w, h)
						local cur = val[id]
						local eff
						if cur == "allow" then eff = true elseif cur == "deny" then eff = false else eff = P.RankHas(rank, id) end
						local t = eff and C.laurel or C.crimson
						UI.Round(0, 0, w, h, S(5), C.panel2, cur and Color(t.r, t.g, t.b, 110) or nil)
						UI.Round(0, S(6), S(3), h - S(12), S(1), Color(t.r, t.g, t.b, cur and 255 or 110))
						UI.Icon(icon, S(10), (h - 16) / 2, 16)
						local right = SEG * 3 + S(16)
						local sub = cur and P.L(cur == "allow" and "perm_allow" or "perm_deny") or (P.L("perm_inherit") .. ": " .. (eff and P.L("perm_allow") or P.L("perm_deny")))
						surface.SetFont("Praetor.Tiny")
						local sw = surface.GetTextSize(sub)
						UI.Text(sub, "Praetor.Tiny", w - right, h / 2, cur and t or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
						UI.Text(UI.Fit(label, "Praetor.Small", w - S(34) - right - sw - S(10)), "Praetor.Small", S(34), h / 2, eff and C.ivory or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
					row:SetTooltip(id)
					row.PerformLayout = function(s2, w)
						for _, b in ipairs(s2:GetChildren()) do
							if b.slot then b:SetPos(w - S(6) - SEG * (4 - b.slot), S(4)) end
						end
					end
					segBtn(row, "allow", 1)
					segBtn(row, "inherit", 2)
					segBtn(row, "deny", 3)
				end
			end
		end
		if not any then
			local l = UI.Label(sc, P.L("ui_empty"), "Praetor.Small", C.dim)
			l:Dock(TOP)
		end
	end
	search.OnChange = fill
	fill()

	local save = UI.Button(m.foot, P.L("ui_save"), "primary", "check", function()
		local allow, deny = {}, {}
		for id, v in pairs(val) do
			if v == "allow" then allow[#allow + 1] = id elseif v == "deny" then deny[#deny + 1] = id end
		end
		P.Request("user_perms", { sid = sid, allow = allow, deny = deny })
		m:Close()
	end)
	save:Dock(RIGHT)
	save:SetWide(S(130))
	local reset = UI.Button(m.foot, P.L("perm_inherit"), "subtle", "undo", function()
		UI.Sound("click")
		val = {}
	end)
	reset:SetTooltip(P.L("usr_perms_reset"))
	reset:Dock(LEFT)
	reset:SetWide(S(150))
end
-- ------------------------------------------------------------------ sheet

-- a card with a header (icon, title, count) and two-line rows; empty cards stay
-- small (one muted line) so the sheet has no big empty gaps
local function card(parent, title, icon, tint, rows, empty, rowFn)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:DockMargin(0, 0, S(4), S(8))
	local n = #rows
	local ROW = S(40)
	p:SetTall(S(38) + (n == 0 and S(26) or n * (ROW + S(4))) + S(6))
	p:DockPadding(S(8), S(38), S(8), S(6))
	p.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(6), C.panel, C.line)
		UI.Round(S(8), S(8), S(22), S(22), S(5), Color(tint.r, tint.g, tint.b, 50))
		UI.Icon(icon, S(8) + (S(22) - 16) / 2, S(8) + (S(22) - 16) / 2, 16)
		UI.Text(title, "Praetor.BodyB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetFont("Praetor.BodyB")
		local tw = surface.GetTextSize(title)
		local cnt = tostring(n)
		surface.SetFont("Praetor.Tiny")
		local cw = surface.GetTextSize(cnt) + S(12)
		UI.Round(S(38) + tw + S(8), S(11), cw, S(16), S(8), n > 0 and Color(tint.r, tint.g, tint.b, 60) or C.panel3)
		UI.Text(cnt, "Praetor.Tiny", S(38) + tw + S(8) + cw / 2, S(19), n > 0 and C.ivory or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if n == 0 then UI.Text(empty, "Praetor.Small", S(12), S(38) + S(11), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	for _, r in ipairs(rows) do rowFn(p, r) end
	return p
end

-- two-line row: text on top, who / when below, coloured bar on the left
local function entry(parent, text, meta, col, onDelete)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(S(40))
	p:DockMargin(0, 0, 0, S(4))
	p.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(4), C.panel2)
		UI.Round(0, 0, S(3), h, 1, col or C.line)
		local maxW = w - S(14) - (onDelete and S(30) or 0)
		local t = UI.Fit(text, "Praetor.Small", maxW)
		UI.Text(t, UI.FontFor(t, "Praetor.Small"), S(10), S(12), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(UI.Fit(meta or "", "Praetor.Tiny", maxW), "Praetor.Tiny", S(10), S(29), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	p:SetTooltip(text)
	if onDelete then
		local x = UI.Button(p, "", "subtle", "trash", onDelete)
		x:Dock(RIGHT)
		x:SetWide(S(30))
		x:DockMargin(0, S(5), S(4), S(5))
	end
	return p
end

local function showSheet(panel, d)
	panel:Clear()
	local row = d.row or {}
	local name = row.name or "?"
	local online = P.BySID(d.sid)
	local rankStyle, rankIcon = UI.RankStyle(row.rank or "user")
	local frame = rankStyle and rankStyle.c1 and Color(rankStyle.c1.r, rankStyle.c1.g, rankStyle.c1.b) or C.lineL
	if d.owner then frame = C.amber end

	-- ---------------------------------------------------------- header
	local head = vgui.Create("DPanel", panel)
	head:Dock(TOP)
	head:SetTall(S(112))
	head:DockMargin(0, 0, 0, S(8))
	local AV = S(80)
	head.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(8), C.panel, C.line)
		-- strip in the rank colour on the left edge
		UI.Round(0, 0, S(5), h, S(2), Color(frame.r, frame.g, frame.b, 170))
		UI.DrawAvatar(d.sid, online, S(18), (h - AV) / 2, AV, 255, frame, name)
		if d.online then
			UI.Round(S(18) + AV - S(12), (h - AV) / 2 + AV - S(12), S(16), S(16), S(8), C.panel)
			UI.Round(S(18) + AV - S(9), (h - AV) / 2 + AV - S(9), S(10), S(10), S(5), C.laurel)
		end
		local x = S(18) + AV + S(18)
		UI.Name(name, "Praetor.H1", x, S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, w - x - S(230), true)
		local bx = x + UI.Badge(rankStyle, rankIcon, "Praetor.Tag", x, S(46), S(22)) + S(6)
		if d.owner then bx = bx + UI.Badge({ text = P.L("owner"), c1 = { r = 240, g = 176, b = 64 }, c2 = { r = 255, g = 222, b = 140 }, fx = "shine" }, "crown", "Praetor.Tag", bx, S(46), S(22)) + S(6) end
		local tag = util.JSONToTable(row.tag or "") or nil
		if istable(tag) and tag.text then UI.Badge(tag, tag.icon, "Praetor.Tag", bx, S(46), S(22)) end
		-- right side: status pill and dates
		local rx = w - S(16)
		local st = d.online and P.L("usr_online") or P.L("usr_offline")
		surface.SetFont("Praetor.SmallB")
		local sw = surface.GetTextSize(st) + S(30)
		local scol = d.online and C.laurel or C.dim
		UI.Round(rx - sw, S(12), sw, S(22), S(11), Color(scol.r, scol.g, scol.b, 40), Color(scol.r, scol.g, scol.b, 120))
		UI.Round(rx - sw + S(10), S(12) + S(8), S(6), S(6), S(3), scol)
		UI.Text(st, "Praetor.SmallB", rx - S(10), S(23), scol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		UI.Text(P.L("usr_first") .. "  " .. P.Date(tonumber(row.first)), "Praetor.Tiny", rx, S(48), C.muted, TEXT_ALIGN_RIGHT)
		UI.Text(P.L("usr_last") .. "  " .. P.Date(tonumber(row.last)), "Praetor.Tiny", rx, S(64), C.muted, TEXT_ALIGN_RIGHT)
		if (tonumber(row.rank_exp) or 0) > 0 then
			UI.Text(P.L("usr_rank_until", { V = P.Date(tonumber(row.rank_exp)) }), "Praetor.Tiny", rx, S(84), C.amber, TEXT_ALIGN_RIGHT)
		end
	end
	-- SteamIDs: click to copy
	local x0 = S(18) + AV + S(14)
	for _, v in ipairs({ P.SID32(d.sid), d.sid }) do
		local b = vgui.Create("DButton", head)
		b:SetText("")
		surface.SetFont("Praetor.Mono")
		local tw = surface.GetTextSize(v)
		b:SetSize(tw + S(30), S(22))
		b:SetPos(x0, S(78))
		x0 = x0 + tw + S(38)
		b:SetTooltip(P.L("usr_copy_tip"))
		b.Paint = function(s2, w, h)
			local hov = s2:IsHovered()
			if hov then UI.Round(0, 0, w, h, S(4), C.panel3) end
			UI.Icon("copy", S(4), (h - 16) / 2, 16, Color(255, 255, 255, hov and 255 or 120))
			UI.Text(v, "Praetor.Mono", S(24), h / 2, hov and C.ivory or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() SetClipboardText(v) UI.Sound("ok") P.Toast(P.L("copied"), v, "ok", 3) end
	end

	-- ---------------------------------------------------------- numbers
	local activeBans = 0
	for _, b in ipairs(d.bans or {}) do
		local exp = tonumber(b.expires) or 0
		if tonumber(b.lifted) ~= 1 and (exp == 0 or exp > os.time()) then activeBans = activeBans + 1 end
	end
	-- next automatic promotion: the play time tile shows how far it is
	local played = tonumber(row.playtime) or 0
	local promo = (tonumber(row.rank_exp) or 0) == 0 and P.NextPromotion and P.NextPromotion(row.rank or "user") or nil
	local promoLabel, promoFrac
	if promo then
		local need = promo.hours * 3600
		local pr = P.Ranks[promo.rank]
		promoFrac = math.Clamp(played / need, 0, 1)
		promoLabel = P.L("usr_next_promo", { V = pr and pr.display or promo.rank, V2 = P.FormatHours(math.max(0, need - played)) })
	end
	local tiles = {
		{ "clock", C.sky, P.FormatHours(played), promoLabel or P.L("usr_playtime"), promoFrac },
		{ "warn", C.amber, tostring(d.warnpts or 0), P.L("usr_warn_pts") },
		{ "hammer", C.crimson, tostring(#(d.bans or {})), activeBans > 0 and P.L("usr_bans_active", { V = activeBans }) or P.L("usr_bans") },
		{ "pen", C.laurel, tostring(#(d.notes or {})), P.L("usr_notes") },
	}
	local nums = vgui.Create("DPanel", panel)
	nums:Dock(TOP)
	nums:SetTall(S(56))
	nums:DockMargin(0, 0, 0, S(8))
	nums.Paint = function(_, w, h)
		local gap = S(8)
		local tw = math.floor((w - gap * 3) / 4)
		for i, t in ipairs(tiles) do
			local x = (i - 1) * (tw + gap)
			UI.Round(x, 0, tw, h, S(6), C.panel, C.line)
			local box = h - S(16)
			UI.Round(x + S(8), S(8), box, box, S(6), Color(t[2].r, t[2].g, t[2].b, 45))
			local isz = UI.IconSize(box - S(8))
			if isz > box then isz = 16 end
			UI.Icon(t[1], x + S(8) + (box - isz) / 2, S(8) + (box - isz) / 2, isz)
			local tx = x + S(8) + box + S(10)
			UI.Text(UI.Fit(t[3], "Praetor.H2", tw - (tx - x) - S(6)), "Praetor.H2", tx, S(6), C.ivory)
			UI.Text(UI.Fit(t[4], "Praetor.Tiny", tw - (tx - x) - S(6)), "Praetor.Tiny", tx, h - S(10), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			if t[5] then
				local bw = tw - (tx - x) - S(10)
				UI.Round(tx, h - S(7), bw, S(3), S(1), Color(255, 255, 255, 18))
				if t[5] > 0 then UI.Round(tx, h - S(7), math.max(S(3), bw * t[5]), S(3), S(1), t[2]) end
			end
		end
	end

	-- ---------------------------------------------------------- actions
	local acts = vgui.Create("DIconLayout", panel)
	acts:Dock(TOP)
	acts:DockMargin(0, 0, 0, S(8))
	acts:SetSpaceX(S(6))
	acts:SetSpaceY(S(6))
	local function act(label, icon, kind, fn)
		local b = acts:Add("PraetorButton")
		b:Setup(label, kind or "ghost", icon)
		b:SetFont("Praetor.Small")
		b:SizeToLabel(S(12))
		b:SetTall(S(34))
		b.DoClick = fn
	end
	local reload = function() timer.Simple(0.4, function() if IsValid(P.Menu) and P.Menu.current == "users" then P.Menu:SelectTab("users", { sid = d.sid }) end end) end
	act(P.L("ui_back"), "undo", "subtle", function() P.Menu:SelectTab("users") end)
	if P.CanRunId("setrank") or P.MyHas("manage_users") then
		act(P.L("qa_setrank"), P.CmdIcon("setrank"), "primary", function()
			UI.Form(P.L("qa_setrank") .. ": " .. name, {
				{ "rank", "rank", P.L("arg_rank"), row.rank },
				{ "min", "duration", P.L("usr_rank_time"), "" },
			}, function(v)
				P.Request("user_setrank", { sid = d.sid, rank = v.rank, min = v.min or 0 })
				reload()
			end)
		end)
	end
	if P.MyHas("manage_tags") then act(P.L("usr_tag"), "tag", nil, function() P.OpenMenu("tags", { sid = d.sid, name = name }) end) end
	if P.CanRunId("warn") then
		act(P.L("qa_warn"), P.CmdIcon("warn"), nil, function()
			UI.Form(P.L("qa_warn") .. ": " .. name, {
				{ "reason", "text", P.L("arg_reason"), "" },
				{ "pts", "number", P.L("usr_points"), 1 },
			}, function(v)
				if P.Trim(v.reason or "") == "" then return false end
				P.Request("warn_add", { sid = d.sid, reason = v.reason, pts = v.pts })
				reload()
			end)
		end)
	end
	if P.MyHas("user_notes") then
		act(P.L("usr_note"), "pen", nil, function()
			UI.Form(P.L("usr_note") .. ": " .. name, { { "text", "multiline", P.L("usr_note"), "" } }, function(v)
				if P.Trim(v.text or "") == "" then return false end
				P.Request("user_note", { sid = d.sid, text = v.text })
				reload()
			end)
		end)
	end
	if P.MyHas("manage_users") then act(P.L("usr_perms"), "key", nil, function() permEditor(d.sid, name, d.perms or {}, row.rank or "user") end) end
	if P.MyHas("manage_jobs") and P.IsDarkRP() then act(P.L("tab_jobs"), "brief", nil, function() P.OpenMenu("jobs", { sid = d.sid }) end) end
	if IsValid(online) then act(P.L("rep_actions"), "gear", nil, function() P.PlayerMenu(online) end) end
	if P.CanRunId("banid") or P.CanRunId("ban") then act(P.L("qa_ban"), P.CmdIcon("ban"), "danger", function() P.BanDialog(online, d.sid, name) reload() end) end

	-- ---------------------------------------------------------- body: history | cards
	local side = vgui.Create("DPanel", panel)
	side:Dock(RIGHT)
	side:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.4), S(280), S(380)))
	side:DockMargin(S(8), 0, 0, 0)
	side.Paint = nil
	local sc = UI.Scroll(side)
	sc:Dock(FILL)

	card(sc, P.L("usr_warns"), "warn", C.amber, d.warns or {}, P.L("usr_no_warns"), function(p, w)
		entry(p, w.reason .. "   +" .. (w.points or 1), (w.admin or "?") .. "  -  " .. P.Date(tonumber(w.created)), C.amber,
			P.MyHas("manage_users") and function() P.Request("warn_delete", { id = w.id }) reload() end or nil)
	end)
	card(sc, P.L("usr_bans"), "hammer", C.crimson, d.bans or {}, P.L("usr_no_bans"), function(p, b)
		local exp = tonumber(b.expires) or 0
		local len = exp == 0 and P.L("ui_perm") or P.FormatDuration(math.floor((exp - (tonumber(b.created) or 0)) / 60))
		local lifted = tonumber(b.lifted) == 1
		entry(p, b.reason .. "  (" .. len .. ")" .. (lifted and ("  - " .. P.L("ban_lifted")) or ""), (b.admin or "?") .. "  -  " .. P.Date(tonumber(b.created)), lifted and C.laurel or C.crimsonL)
	end)
	card(sc, P.L("usr_notes"), "pen", C.laurel, d.notes or {}, P.L("usr_no_notes"), function(p, n)
		entry(p, n.text, (n.admin or "?") .. "  -  " .. P.Date(tonumber(n.created)), C.sky,
			P.MyHas("manage_users") and function() P.Request("note_delete", { id = n.id }) reload() end or nil)
	end)
	if P.IsDarkRP() or #(d.jobs or {}) > 0 then
		card(sc, P.L("usr_jobs"), "brief", C.sky, d.jobs or {}, P.L("usr_no_jobs"), function(p, j)
			local kind = j.kind == "wl" and P.L("job_wl") or P.L("job_bl")
			local exp = tonumber(j.expires) or 0
			entry(p, kind .. ": " .. (j.job == "*" and P.L("ui_all_jobs") or j.job) .. ((j.reason or "") ~= "" and ("  - " .. j.reason) or ""),
				(exp > 0 and (P.L("ban_expires") .. " " .. P.Date(exp)) or P.L("ui_perm")), j.kind == "wl" and C.laurel or C.crimsonL)
		end)
	end
	if istable(d.names) and #d.names > 0 then
		local names = table.concat(d.names, ", ")
		local nb = vgui.Create("DPanel", sc)
		nb:Dock(TOP)
		nb:DockMargin(0, 0, S(4), S(8))
		nb:SetTall(S(60))
		local wrapped
		nb.PerformLayout = function(s2, w)
			wrapped = UI.Wrap(names, "Praetor.Small", w - S(20))
			local want = S(42) + #wrapped * S(17)
			if s2:GetTall() ~= want then s2:SetTall(want) end
		end
		nb.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(6), C.panel, C.line)
			UI.Round(S(8), S(8), S(22), S(22), S(5), Color(C.muted.r, C.muted.g, C.muted.b, 45))
			UI.Icon("user", S(8) + (S(22) - 16) / 2, S(8) + (S(22) - 16) / 2, 16)
			UI.Text(P.L("usr_names"), "Praetor.BodyB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			for i, l in ipairs(wrapped or {}) do UI.Text(l, UI.FontFor(l, "Praetor.Small"), S(10), S(36) + (i - 1) * S(17), C.text) end
		end
	end

	-- accounts that joined from the same connection (alt detector)
	if istable(d.alts) then
		local ab = vgui.Create("DPanel", sc)
		ab:Dock(TOP)
		ab:DockMargin(0, 0, S(4), S(8))
		ab:DockPadding(S(8), S(40), S(8), S(8))
		local alts = d.alts
		local anyBan = false
		for _, a in ipairs(alts) do if a.ban then anyBan = true end end
		ab.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(6), C.panel, anyBan and Color(C.crimson.r, C.crimson.g, C.crimson.b, 150) or C.line)
			local col = anyBan and C.crimson or C.sky
			UI.Round(S(8), S(8), S(22), S(22), S(5), Color(col.r, col.g, col.b, 45))
			UI.Icon("players", S(8) + (S(22) - 16) / 2, S(8) + (S(22) - 16) / 2, 16)
			UI.Text(P.L("alt_title"), "Praetor.BodyB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(tostring(#alts), "Praetor.SmallB", w - S(12), S(19), anyBan and C.crimsonL or C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			if #alts == 0 then UI.Text(P.L("alt_none"), "Praetor.Small", S(10), S(46), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		local rows = 0
		for _, a in ipairs(alts) do
			rows = rows + 1
			local r = vgui.Create("DButton", ab)
			r:SetText("")
			r:Dock(TOP)
			r:SetTall(S(38))
			r:DockMargin(0, 0, 0, S(4))
			r:SetTooltip(P.L("alt_open"))
			r.Paint = function(s2, w, h)
				UI.Round(0, 0, w, h, S(5), s2:IsHovered() and C.hover or C.panel2, a.ban and Color(C.crimson.r, C.crimson.g, C.crimson.b, 120) or nil)
				local online = player.GetBySteamID64(a.sid)
				UI.DrawAvatar(a.sid, IsValid(online) and online or nil, S(6), S(5), h - S(10), 255, nil, a.name)
				local x = S(6) + h - S(10) + S(8)
				local right = a.ban and P.L("alt_banned") or (a.on and P.L("online") or P.Date(a.last))
				surface.SetFont("Praetor.Tiny")
				local rw = surface.GetTextSize(right) + S(16)
				UI.Text(UI.Fit(a.name or "?", "Praetor.SmallB", w - x - rw - S(8)), UI.FontFor(a.name or "?", "Praetor.SmallB"), x, S(12), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(util.SteamIDFrom64(a.sid), "Praetor.Tiny", x, h - S(11), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if a.ban then
					UI.Round(w - rw - S(6), (h - S(20)) / 2, rw, S(20), S(10), Color(C.crimson.r, C.crimson.g, C.crimson.b, 60), C.crimson)
					UI.Text(right, "Praetor.Tiny", w - S(6) - rw / 2, h / 2, C.crimsonL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					UI.Text(right, "Praetor.Tiny", w - S(10), h / 2, a.on and C.laurel or C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				end
			end
			r.DoClick = function() UI.Sound("click") P.Request("user_sheet", { sid = a.sid }) end
		end
		ab:SetTall(S(48) + math.max(rows, 1) * S(42) - (rows == 0 and S(16) or 0))
		local note = vgui.Create("DPanel", sc)
		note:Dock(TOP)
		note:DockMargin(S(4), -S(4), S(4), S(8))
		note:SetTall(S(16))
		note.Paint = function(_, w, h) UI.Text(UI.Fit(P.L("alt_note"), "Praetor.Tiny", w), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end

	-- history (left, fills the rest), grouped by day
	local hist = vgui.Create("DPanel", panel)
	hist:Dock(FILL)
	hist:DockPadding(S(10), S(42), S(6), S(8))
	local logs = d.logs or {}
	hist.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(6), C.panel, C.line)
		UI.Round(S(8), S(8), S(22), S(22), S(5), Color(C.bronze.r, C.bronze.g, C.bronze.b, 50))
		UI.Icon("clock", S(8) + (S(22) - 16) / 2, S(8) + (S(22) - 16) / 2, 16)
		UI.Text(P.L("usr_logs"), "Praetor.BodyB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Rect(S(8), S(36), w - S(16), 1, C.line)
		if #logs == 0 then UI.Text(P.L("log_none"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	end
	local hs = UI.Scroll(hist)
	hs:Dock(FILL)
	local lastDay
	for _, r in ipairs(logs) do
		local t = tonumber(r.t) or 0
		local day = os.date("%d/%m/%Y", t)
		if day ~= lastDay then
			lastDay = day
			local dh = vgui.Create("DPanel", hs)
			dh:Dock(TOP)
			dh:SetTall(S(22))
			dh.Paint = function(_, w, h)
				UI.Text(day, "Praetor.Tiny", 0, h / 2, C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				surface.SetFont("Praetor.Tiny")
				local dw = surface.GetTextSize(day)
				UI.Rect(dw + S(8), math.floor(h / 2), w - dw - S(12), 1, C.line)
			end
		end
		local list = P.TemplateParts(P.L(r.k), util.JSONToTable(r.a or "") or {})
		local p = vgui.Create("DPanel", hs)
		p:Dock(TOP)
		p:SetTall(S(24))
		p.Paint = function(s2, w, h)
			if s2:IsHovered() then UI.Round(0, 0, w - S(4), h, S(4), C.panel2) end
			UI.Text(os.date("%H:%M", t), "Praetor.Tiny", S(4), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			P.DrawParts(list, S(50), h / 2, w - S(56), "Praetor.Small")
		end
	end
end

P.AddTab("users", {
	cat = "management", icon = "badge", order = 1,
	can = function() return P.MyHas("manage_users") or P.MyHas("view_sheet") end,
	build = function(panel, data)
		P.On("user_sheet", function(d)
			if IsValid(panel) then showSheet(panel, d) end
		end)
		if data.sid then
			local l = UI.Label(panel, P.L("ui_loading"), "Praetor.Small", C.muted)
			l:Dock(TOP)
			P.Request("user_sheet", { sid = data.sid })
			return
		end

		local bar = UI.Toolbar(panel)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("usr_search"), state.q), nil, FILL)
		local ropts = { { "", P.L("usr_all_ranks") } }
		for _, r in ipairs(P.SortedRanks()) do ropts[#ropts + 1] = { r.name, r.display or r.name } end
		local rank = UI.Tool(bar, UI.Combo(bar, ropts, state.rank), S(180), RIGHT)
		local open = UI.Tool(bar, UI.Button(bar, P.L("usr_open_sid"), "primary", "scroll"), S(170), RIGHT)

		local tbl = UI.Table(panel, { { P.L("col_name"), 0.35 }, { "SteamID", 0.25 }, { P.L("col_rank"), 0.2 }, { P.L("sb_hours"), 90, TEXT_ALIGN_RIGHT }, { P.L("usr_last"), 130, TEXT_ALIGN_RIGHT } })
		tbl:Dock(FILL)

		local function ask() P.Request("user_search", { q = state.q, rank = state.rank }) end
		search.OnEnter = function(s) state.q = s:GetValue() ask() end
		rank.OnSelect = function(_, _, _, v) state.rank = v ask() end
		open.DoClick = function()
			local sid = P.ToSID64(P.Trim(search:GetValue()))
			if sid then P.Request("user_sheet", { sid = sid })
			else P.Toast(P.L("toast_error"), P.L("err_steamid"), "warn", 4) end
		end

		P.On("user_search", function(d)
			if not IsValid(tbl) then return end
			tbl:Clear()
			if #d.rows == 0 then tbl:Empty(P.L("usr_none"), "players") return end
			for _, r in ipairs(d.rows) do
				local online = IsValid(P.BySID(r.sid))
				tbl:AddRow({
					{ r.name, online and C.laurel or C.ivory }, { P.SID32(r.sid), C.muted },
					function(x, _, w, h)
						local style, icon = UI.RankStyle(r.rank)
						UI.Badge(style, icon, "Praetor.Tiny", x, (h - S(20)) / 2, S(20))
					end,
					{ P.FormatHours(tonumber(r.playtime) or 0), C.text },
					{ online and P.L("usr_online") or P.Date(tonumber(r.last)), online and C.laurel or C.muted },
				}, { onClick = function() P.Request("user_sheet", { sid = r.sid }) end })
			end
		end)
		ask()
	end,
})
