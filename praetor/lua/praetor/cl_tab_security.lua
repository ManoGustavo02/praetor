-- Praetor menu: security.
--  * tiles: rank lock, events in 24h (with an hour by hour chart), backdoor
--    scan, anti-crash (live tick time) and Family Sharing
--  * event feed: every blocked action, anti-crash step, linked account... with
--    a colour for how serious it is, filter chips, search and a menu per event
--  * right column: live server health (tick chart, who has the most moving
--    props, what the anti-crash did), owners, scan, borrowed accounts, backups
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local page = 0
local last = {}
local filter = { cat = nil, q = "" }

-- how serious each kind is: 3 critical, 2 warning, 1 info
local SEV = {
	backdoor = 3, rank_external = 3, owner_cmd = 3, net_flood = 3, alt_banned = 3, family_ban = 3, ac_remove = 3, dupe_huge = 3,
	net_denied = 2, net_op = 2, net_size = 2, net_bad = 2, ac_freezeall = 2, ac_owner = 2, family_block = 2,
	ac_nan = 2, ac_speed = 2, ac_spam = 2, ac_chat = 2, sg_noanswer = 2,
	net_rate = 1, ac_freeze = 1, family_share = 1, owner_change = 1, alt_link = 1,
}
local ICON = {
	backdoor = "skull", rank_external = "crown", owner_cmd = "crown", owner_change = "crown",
	net_flood = "bolt", net_denied = "lock", net_op = "terminal", net_size = "box", net_bad = "warn", net_rate = "speed",
	alt_banned = "ghost", alt_link = "ghost", family_ban = "players", family_block = "players", family_share = "players", sg_noanswer = "image",
	ac_remove = "trash", ac_freezeall = "snow", ac_freeze = "snow", ac_owner = "snow", ac_nan = "warn", ac_speed = "rocket",
	ac_spam = "box", ac_chat = "bubble", dupe_huge = "copy",
}
local function sevOf(kind) return SEV[kind] or 1 end
local function sevCol(s) return s == 3 and C.crimsonL or (s == 2 and C.amber or C.sky) end

local CATS = {
	{ id = nil, key = "sec_cat_all", icon = "shield" },
	{ id = "net", key = "sec_cat_net", icon = "bolt", pre = { "net" } },
	{ id = "ranks", key = "sec_cat_ranks", icon = "crown", pre = { "rank", "owner" } },
	{ id = "accounts", key = "sec_cat_accounts", icon = "ghost", pre = { "family", "alt" } },
	{ id = "anticrash", key = "sec_cat_anticrash", icon = "snow", pre = { "ac", "dupe" } },
	{ id = "backdoor", key = "sec_cat_backdoor", icon = "skull", pre = { "backdoor" } },
}

local function ago(t)
	local d = os.time() - (tonumber(t) or os.time())
	if d < 60 then return P.L("vt_now") end
	if d < 3600 then return P.L("vt_min", { V = math.floor(d / 60) }) end
	if d < 86400 then return P.L("vt_hour", { V = math.floor(d / 3600) }) end
	return os.date("%d/%m %H:%M", tonumber(t))
end

local function tile(parent, icon, label, valueFn, extra)
	local p = vgui.Create("DPanel", parent)
	p.Paint = function(_, w, h)
		local value, sub, col = valueFn()
		col = col or C.ivory
		UI.Round(0, 0, w, h, S(8), C.panel2, C.line)
		UI.Round(0, S(10), S(3), h - S(20), S(1), col)
		UI.Round(S(12), S(12), S(34), S(34), S(8), Color(col.r, col.g, col.b, 28))
		UI.Icon(icon, S(12) + (S(34) - 16) / 2, S(12) + (S(34) - 16) / 2, 16, col)
		local x = S(56)
		UI.Text(UI.Fit(P.Upper(label), "Praetor.Tiny", w - x - S(8)), "Praetor.Tiny", x, S(12), C.dim)
		UI.Text(UI.Fit(value, "Praetor.BodyB", w - x - S(8)), "Praetor.BodyB", x, S(27), col)
		if sub then UI.Text(UI.Fit(sub, "Praetor.Tiny", w - S(24)), "Praetor.Tiny", S(12), h - S(16), C.muted) end
		if extra then extra(w, h, col) end
	end
	return p
end

local function section(parent, title, sub)
	local h = UI.Header(parent, title, sub)
	h:Dock(TOP)
	h:DockMargin(0, S(4), S(8), S(4))
	return h
end

-- small bar chart (values left to right)
local function bars(x, y, w, h, vals, col, maxV)
	local n = #vals
	if n == 0 then return end
	maxV = maxV or 0
	for _, v in ipairs(vals) do if v > maxV then maxV = v end end
	if maxV <= 0 then maxV = 1 end
	local bw = w / n
	for i, v in ipairs(vals) do
		local bh = math.max(1, math.floor((v / maxV) * h))
		local a = v > 0 and 220 or 60
		surface.SetDrawColor(col.r, col.g, col.b, a)
		surface.DrawRect(math.floor(x + (i - 1) * bw), y + h - bh, math.max(1, math.floor(bw) - 1), bh)
	end
end

P.AddTab("security", {
	cat = "server", icon = "shield", order = 3,
	can = function() return P.MyHas("security") end,
	build = function(panel)
		last.health = nil
		-- ---------------------------------------------------------- tiles
		local top = vgui.Create("DPanel", panel)
		top:Dock(TOP)
		top:SetTall(S(84))
		top:DockMargin(0, 0, 0, S(10))
		top.Paint = nil
		local tiles = {
			tile(top, "key", P.L("sec_t_lock"), function()
				local on = P.Setting("rank_lock")
				return on and P.L("sec_on") or P.L("sec_off"), on and P.L("sec_t_lock_d", { V = P.Setting("rank_lock_max") }) or P.L("sec_t_lock_off"), on and C.laurel or C.crimsonL
			end),
			tile(top, "flag", P.L("sec_t_day"), function()
				local n = last.day or 0
				return tostring(n), P.L("sec_t_day_d"), n > 0 and C.amber or C.laurel
			end, function(w, h, col)
				if last.hist then bars(w - S(96), S(14), S(84), S(30), last.hist, col) end
			end),
			tile(top, "eye", P.L("sec_t_scan"), function()
				local sc = last.scan
				if not sc then return P.L("sec_scan_wait"), P.L("sec_scan_wait_d"), C.muted end
				local n = #(sc.found or {})
				return n == 0 and P.L("sec_scan_ok") or P.L("sec_scan_bad", { V = n }), P.Date and P.Date(tonumber(sc.t)) or "", n == 0 and C.laurel or C.crimsonL
			end),
			tile(top, "snow", P.L("sec_t_ac"), function()
				local hs = last.health
				if not P.Setting("ac_enabled") then return P.L("sec_off"), P.L("sec_t_ac_off"), C.crimsonL end
				if not hs then return P.L("sec_on"), P.L("sec_t_ac_d"), C.laurel end
				local bad = (hs.stage or 0) > 0
				return P.L("sec_ac_ms", { V = hs.avg or 0 }), bad and P.L("sec_ac_acting") or P.L("sec_t_ac_d"), bad and C.amber or C.laurel
			end),
			tile(top, "players", P.L("sec_t_family"), function()
				local on = P.Setting("family_ban")
				return on and P.L("sec_on") or P.L("sec_off"), P.Setting("family_block") and P.L("sec_family_block_on") or P.L("sec_t_family_d"), on and C.laurel or C.muted
			end),
		}
		top.PerformLayout = function(_, w, h)
			local n = #tiles
			local tw = math.floor((w - S(8) * (n - 1)) / n)
			for i, t in ipairs(tiles) do
				t:SetPos((i - 1) * (tw + S(8)), 0)
				t:SetSize(tw, h)
			end
		end

		-- ---------------------------------------------------------- right column
		local right = UI.Scroll(panel)
		right:Dock(RIGHT)
		right:SetWide(S(340))
		right:DockMargin(S(12), 0, 0, 0)

		section(right, P.L("sec_health"), P.L("sec_health_sub"))
		local health = vgui.Create("DPanel", right)
		health:Dock(TOP)
		health:SetTall(S(150))
		health:DockMargin(0, 0, S(8), S(6))
		health.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(8), C.panel2, C.line)
			local hs = last.health
			if not hs then
				UI.Text(P.L("ui_loading"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			local limit = tonumber(hs.limit) or 120
			local col = (hs.avg or 0) >= limit and C.crimsonL or ((hs.avg or 0) >= limit * 0.5 and C.amber or C.laurel)
			UI.Text(P.L("sec_ac_ms", { V = hs.avg or 0 }), "Praetor.H2", S(12), S(10), col)
			UI.Text(P.L("sec_ac_peak", { V = hs.peak or 0, V2 = hs.tick or 15 }), "Praetor.Tiny", S(12), S(36), C.muted)
			local st = tonumber(hs.stage) or 0
			local stTxt = st == 0 and P.L("sec_ac_calm") or P.L("sec_ac_stage" .. math.min(st, 4))
			surface.SetFont("Praetor.Tiny")
			local tw = surface.GetTextSize(stTxt) + S(16)
			UI.Round(w - tw - S(10), S(12), tw, S(20), S(10), Color(col.r, col.g, col.b, 35), col)
			UI.Text(stTxt, "Praetor.Tiny", w - tw / 2 - S(10), S(22), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			-- tick chart (last 60 seconds), limit line
			local cx, cy, cw, ch = S(12), S(56), w - S(24), S(52)
			UI.Round(cx, cy, cw, ch, S(4), C.bg)
			local vals, peaks = {}, {}
			for i, v in ipairs(hs.hist or {}) do vals[i] = v[1] or 0 peaks[i] = v[2] or 0 end
			local maxV = math.max(limit * 1.2, 1)
			for _, v in ipairs(peaks) do if v > maxV then maxV = v end end
			bars(cx + 2, cy + 2, cw - 4, ch - 4, peaks, Color(C.dim.r, C.dim.g, C.dim.b), maxV)
			bars(cx + 2, cy + 2, cw - 4, ch - 4, vals, col, maxV)
			local ly = cy + 2 + (ch - 4) - math.floor(limit / maxV * (ch - 4))
			surface.SetDrawColor(C.crimson.r, C.crimson.g, C.crimson.b, 140)
			for xx = cx + 2, cx + cw - 4, 6 do surface.DrawRect(xx, ly, 3, 1) end
			-- counts
			local y = cy + ch + S(8)
			local items = {
				{ "box", P.L("sec_ac_ents", { V = hs.ents or 0 }) },
				{ "user", P.L("sec_ac_props", { V = hs.props or 0 }) },
				{ "speed", P.L("sec_ac_awake", { V = hs.awake or 0 }) },
			}
			local iw = (w - S(24)) / 3
			for i, it in ipairs(items) do
				local x = S(12) + (i - 1) * iw
				UI.Icon(it[1], x, y, 16, Color(255, 255, 255, 150))
				UI.Text(UI.Fit(it[2], "Praetor.Tiny", iw - S(22)), "Praetor.Tiny", x + S(20), y + 8, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end

		local topBox = vgui.Create("DPanel", right)
		topBox:Dock(TOP)
		topBox:DockMargin(0, 0, S(8), S(6))
		topBox.Paint = nil
		local unfreeze = UI.Button(right, P.L("sec_ac_unfreeze"), "ghost", "snow", function()
			UI.Confirm(P.L("sec_ac_unfreeze"), P.L("sec_ac_unfreeze_q"), function() P.Request("ac_unfreeze") end)
		end)
		unfreeze:Dock(TOP)
		unfreeze:SetTall(S(30))
		unfreeze:DockMargin(0, 0, S(8), S(6))
		-- last resort when someone crashes with vehicles, E2, constraints...
		if P.CanRunId("cleanup") then
			local wipe = UI.Button(right, P.L("sec_ac_wipe"), "danger", "broom", function()
				UI.Confirm(P.L("sec_ac_wipe"), P.L("sec_ac_wipe_q"), function() P.RunCmd("cleanup", {}) end, true)
			end)
			wipe:Dock(TOP)
			wipe:SetTall(S(30))
			wipe:DockMargin(0, 0, S(8), S(12))
		else
			unfreeze:DockMargin(0, 0, S(8), S(12))
		end

		section(right, P.L("sec_owners"), P.L("sec_owners_sub"))
		local owners = vgui.Create("DPanel", right)
		owners:Dock(TOP)
		owners:DockMargin(0, 0, S(8), S(6))
		owners.Paint = nil
		local hint = vgui.Create("DPanel", right)
		hint:Dock(TOP)
		hint:SetTall(S(30))
		hint:DockMargin(0, 0, S(8), S(10))
		hint.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(5), C.bg, C.line)
			UI.Text(UI.Fit(P.L("sec_console_hint"), "Praetor.Mono", w - S(16)), "Praetor.Mono", S(8), h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		section(right, P.L("sec_scan"), P.L("sec_scan_sub"))
		local scanBox = vgui.Create("DPanel", right)
		scanBox:Dock(TOP)
		scanBox:DockMargin(0, 0, S(8), S(4))
		scanBox.Paint = nil
		local scanBtn = UI.Button(right, P.L("sec_scan_now"), "ghost", "eye", function()
			P.Request("security_scan")
		end)
		scanBtn:Dock(TOP)
		scanBtn:SetTall(S(30))
		scanBtn:DockMargin(0, 0, S(8), S(10))

		section(right, P.L("sec_family"), P.L("sec_family_sub"))
		local famBox = vgui.Create("DPanel", right)
		famBox:Dock(TOP)
		famBox:DockMargin(0, 0, S(8), S(10))
		famBox.Paint = nil

		section(right, P.L("sec_backups"), P.L("sec_backups_sub"))
		local backups = vgui.Create("DPanel", right)
		backups:Dock(TOP)
		backups:DockMargin(0, 0, S(8), S(4))
		backups.Paint = nil

		-- ---------------------------------------------------------- filters
		local function ask() P.Request("security_list", { page = page, cat = filter.cat, q = filter.q }) end
		local sbar = vgui.Create("DPanel", panel)
		sbar:Dock(TOP)
		sbar:SetTall(S(32))
		sbar:DockMargin(0, 0, 0, S(6))
		sbar.Paint = nil
		local search = UI.Entry(sbar, P.L("sec_search"), filter.q)
		search:Dock(FILL)
		search.OnEnter = function(s2) filter.q = P.Trim(s2:GetValue()) page = 0 ask() end
		search.OnChange = function(s2)
			if P.Trim(s2:GetValue()) == "" and filter.q ~= "" then filter.q = "" page = 0 ask() end
		end
		local go = UI.Button(sbar, P.L("ui_search"), "ghost", "eye", function() search:OnEnter() end)
		go:Dock(RIGHT)
		go:SetWide(S(110))
		go:DockMargin(S(6), 0, 0, 0)

		local chips = vgui.Create("DPanel", panel)
		chips:Dock(TOP)
		chips:SetTall(S(30))
		chips:DockMargin(0, 0, 0, S(8))
		chips.Paint = nil
		for _, cat in ipairs(CATS) do
			local b = vgui.Create("DButton", chips)
			b:SetText("")
			local function count()
				if not last.counts then return nil end
				local n = 0
				for kind, c in pairs(last.counts) do
					if not cat.pre then n = n + c
					else
						for _, pre in ipairs(cat.pre) do if kind:sub(1, #pre) == pre then n = n + c break end end
					end
				end
				return n
			end
			b.Paint = function(s2, w, h)
				local on = filter.cat == cat.id
				UI.Round(0, 0, w, h, S(15), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s2:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
				local n = count()
				local txt = n and (n > 999 and "999+" or tostring(n)) or ""
				surface.SetFont("Praetor.Tiny")
				local nw = n and (surface.GetTextSize(txt) + S(10)) or 0
				local showIcon = w > S(96)
				local x = showIcon and S(28) or S(10)
				if showIcon then UI.Icon(cat.icon, S(8), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 150)) end
				UI.Text(UI.Fit(P.L(cat.key), "Praetor.Small", w - x - nw - S(4)), "Praetor.Small", x, h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if n then UI.Text(txt, "Praetor.Tiny", w - S(9), h / 2, n > 0 and C.bronzeL or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
			end
			b.DoClick = function()
				UI.Sound("click")
				filter.cat = cat.id
				page = 0
				ask()
			end
		end
		-- the chips share the width evenly
		chips.PerformLayout = function(s2, w, h)
			local kids = s2:GetChildren()
			local gap = S(5)
			local cw = math.floor((w - gap * (#kids - 1)) / #kids)
			for i, k in ipairs(kids) do
				k:SetPos((i - 1) * (cw + gap), 0)
				k:SetSize(cw, h)
			end
		end

		-- ---------------------------------------------------------- feed
		local pager = UI.Pager(panel, function(n) page = n ask() end)
		local feed = UI.Scroll(panel)
		feed:Dock(FILL)

		local function eventMenu(r)
			local items = {}
			local sid = (r.sid or ""):match("^%d+$") and r.sid or nil
			if sid then
				items[#items + 1] = { P.L("copy_steamid"), "copy", function() SetClipboardText(util.SteamIDFrom64(sid)) P.Toast(P.L("copied"), util.SteamIDFrom64(sid), "ok", 2) end }
				if P.MyHas("view_sheet") then items[#items + 1] = { P.L("qa_sheet"), "scroll", function() P.OpenMenu("users", { sid = sid }) end } end
				local online = P.BySID(sid)
				if IsValid(online) and P.CanRunId("goto") then items[#items + 1] = { P.L("rep_goto_from"), "flag", function() P.RunCmd("goto", { sid }) end } end
				if IsValid(online) and P.CanRunId("spectate") then items[#items + 1] = { P.L("qa_spectate"), "eye", function() P.RunCmd("spectate", { sid }) P.CloseMenu() end } end
				items[#items + 1] = { P.L("sec_only_this"), "target", function() filter.q = util.SteamIDFrom64(sid) search:SetValue(filter.q) page = 0 ask() end }
			end
			items[#items + 1] = { P.L("sec_copy_info"), "clipboard", function() SetClipboardText((r.kind or "") .. " " .. (r.name or "") .. " " .. (r.sid or "") .. " " .. (r.info or "")) P.Toast(P.L("copied"), "", "ok", 2) end }
			UI.Popup(items)
		end

		local function addEvent(r)
			local kind = tostring(r.kind or "?")
			local sev = sevOf(kind)
			local col = sevCol(sev)
			local sid = (r.sid or ""):match("^%d+$") and r.sid or nil
			local row = vgui.Create("DButton", feed)
			row:SetText("")
			row:Dock(TOP)
			row:SetTall(S(54))
			row:DockMargin(0, 0, S(6), S(4))
			row.hov = 0
			local title = P.L("sec_" .. kind, nil, kind)
			local who = (r.name and r.name ~= "" and r.name ~= "Server") and r.name or nil
			row.Paint = function(s, w, h)
				s.hov = UI.Lerp(s.hov, s:IsHovered() and 1 or 0, 14)
				UI.Round(0, 0, w, h, S(7), P.LerpColor(s.hov, C.panel2, C.hover), sev == 3 and Color(col.r, col.g, col.b, 120) or C.line)
				UI.Round(0, S(8), S(3), h - S(16), S(1), col)
				UI.Round(S(12), (h - S(34)) / 2, S(34), S(34), S(8), Color(col.r, col.g, col.b, 30))
				UI.Icon(ICON[kind] or "shield", S(12) + (S(34) - 16) / 2, (h - 16) / 2, 16, col)
				local x = S(56)
				local rightW = S(110)
				local avX = w - rightW - (sid and S(40) or 0)
				UI.Text(UI.Fit(title, "Praetor.BodyB", avX - x - S(10)), "Praetor.BodyB", x, S(17), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local sub = r.info or ""
				if who then sub = who .. (sid and ("  " .. P.SID32(sid)) or "") .. (sub ~= "" and ("  -  " .. sub) or "") end
				UI.Text(UI.Fit(sub, "Praetor.Small", avX - x - S(10)), "Praetor.Small", x, S(37), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if sid then UI.DrawAvatar(sid, P.BySID(sid), avX, (h - S(30)) / 2, S(30), 255, nil, who) end
				UI.Text(ago(r.t), "Praetor.SmallB", w - S(12), S(17), sev == 3 and col or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				UI.Text(P.L("sec_sev_" .. sev), "Praetor.Tiny", w - S(12), S(37), col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			row.DoClick = function() eventMenu(r) end
			row.DoRightClick = row.DoClick
			row:SetTooltip(P.Date(tonumber(r.t)) .. (r.info and r.info ~= "" and ("\n" .. r.info) or ""))
		end

		-- ---------------------------------------------------------- side boxes
		local function row(parent, h, paint)
			local r = vgui.Create("DPanel", parent)
			r:Dock(TOP)
			r:SetTall(h)
			r:DockMargin(0, 0, 0, S(3))
			r.Paint = paint
			return r
		end
		local function fit(box)
			local hh = 0
			for _, c in ipairs(box:GetChildren()) do hh = hh + c:GetTall() + S(3) end
			box:SetTall(math.max(1, hh))
		end
		local function note(box, text, col)
			row(box, S(30), function(_, w, h)
				UI.Round(0, 0, w, h, S(5), C.panel)
				UI.Text(UI.Fit(text, "Praetor.Small", w - S(16)), "Praetor.Small", S(10), h / 2, col or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end)
		end

		local function fillTop(hs)
			topBox:Clear()
			local list = hs.top or {}
			if #list == 0 then
				note(topBox, P.L("sec_ac_noprops"))
			else
				local maxA = 1
				for _, o in ipairs(list) do if (o.a or 0) > maxA then maxA = o.a end end
				for _, o in ipairs(list) do
					local r = row(topBox, S(36), function(_, w, h)
						UI.Round(0, 0, w, h, S(6), C.panel2)
						UI.DrawAvatar(o.s, P.BySID(o.s), S(6), S(5), S(26), 255, nil, o.n)
						UI.Name(o.n, "Praetor.SmallB", S(40), S(12), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - S(150))
						-- moving props bar
						local bw = w - S(150)
						UI.Round(S(40), S(26), bw, S(4), S(2), C.bg)
						local f = (o.a or 0) / maxA
						if f > 0 then UI.Round(S(40), S(26), math.max(S(4), bw * f), S(4), S(2), f > 0.6 and C.amber or C.sky) end
						UI.Text(P.L("sec_ac_owner_n", { V = o.c or 0, V2 = o.a or 0 }), "Praetor.Tiny", w - S(8), h / 2, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end)
					r:SetCursor("hand")
					r.OnMousePressed = function()
						local items = {}
						local p = P.BySID(o.s)
						if IsValid(p) and P.CanRunId("goto") then items[#items + 1] = { P.L("rep_goto_from"), "flag", function() P.RunCmd("goto", { o.s }) end } end
						if P.CanRunId("clearprops") then items[#items + 1] = { P.L("sec_ac_cleanup"), "broom", function() P.RunCmd("clearprops", { o.s }) end } end
						if P.MyHas("view_sheet") then items[#items + 1] = { P.L("qa_sheet"), "scroll", function() P.OpenMenu("users", { sid = o.s }) end } end
						if #items > 0 then UI.Popup(items) end
					end
				end
			end
			for _, a in ipairs(hs.acts or {}) do
				if a.k ~= "ok" then
					row(topBox, S(26), function(_, w, h)
						UI.Icon(a.k == "remove" and "trash" or "snow", S(4), (h - 16) / 2, 16, Color(255, 255, 255, 130))
						UI.Text(UI.Fit(P.L("sec_act_" .. a.k, { V = a.n or 0, S = a.w or "" }), "Praetor.Tiny", w - S(80)), "Praetor.Tiny", S(26), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Text(ago(a.t), "Praetor.Tiny", w - S(4), h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end)
				end
			end
			fit(topBox)
			right:InvalidateLayout()
		end

		local function fillScan(sc)
			scanBox:Clear()
			if not sc then
				note(scanBox, P.L("sec_scan_wait_d"))
			elseif #(sc.found or {}) == 0 then
				note(scanBox, P.L("sec_scan_clean"), C.laurel)
			else
				for _, f in ipairs(sc.found) do
					row(scanBox, S(42), function(_, w, h)
						UI.Round(0, 0, w, h, S(5), Color(C.crimson.r, C.crimson.g, C.crimson.b, 30), C.crimson)
						UI.Icon("skull", S(10), (h - 16) / 2, 16, C.crimsonL)
						UI.Text(UI.Fit(f.name, "Praetor.SmallB", w - S(40)), "Praetor.SmallB", S(34), S(5), C.ivory)
						local d = f.kind == "net" and P.L("sec_scan_net") or P.L("sec_scan_func", { S = f.src or "?" })
						UI.Text(UI.Fit(d, "Praetor.Tiny", w - S(40)), "Praetor.Tiny", S(34), S(23), C.crimsonL)
					end)
				end
				note(scanBox, P.L("sec_scan_help"), C.amber)
			end
			fit(scanBox)
			right:InvalidateLayout()
		end

		P.On("ac_status", function(hs)
			if not IsValid(health) then return end
			local stageBefore = last.health and last.health.stage or 0
			last.health = hs
			fillTop(hs)
			if (hs.stage or 0) > 0 and stageBefore == 0 then ask() end
		end)
		local function poll() if IsValid(health) then P.Request("ac_status") end end
		poll()
		timer.Create("Praetor.SecHealth", 2, 0, function()
			if not IsValid(health) then timer.Remove("Praetor.SecHealth") return end
			if IsValid(P.Menu) and P.Menu:IsVisible() then poll() end
		end)

		P.On("security_scan", function(sc)
			if not IsValid(scanBox) then return end
			last.scan = sc
			fillScan(sc)
			P.Toast(P.L("sec_scan"), #(sc.found or {}) == 0 and P.L("sec_scan_clean") or P.L("sec_scan_bad", { V = #sc.found }), #(sc.found or {}) == 0 and "ok" or "warn", 4)
		end)

		P.On("security_list", function(d)
			if not IsValid(feed) then return end
			last.day = d.day
			last.hist = d.hist
			last.counts = d.counts
			last.scan = d.scan or last.scan
			feed:Clear()
			pager:SetPage(d.page or 0, #d.rows >= 60)
			if #d.rows == 0 then
				local e = vgui.Create("DPanel", feed)
				e:Dock(TOP)
				e:SetTall(S(150))
				e.Paint = function(_, w, h)
					UI.Round(0, 0, w - S(6), h, S(8), C.panel2, C.line)
					UI.Round(w / 2 - S(26), S(24), S(46), S(46), S(23), Color(C.laurel.r, C.laurel.g, C.laurel.b, 30))
					UI.Icon("shield", w / 2 - 3 - 8, S(24) + S(23) - 8, 16, C.laurel)
					local txt = (filter.cat or filter.q ~= "") and P.L("sec_none_filter") or P.L("sec_none")
					UI.Text(txt, "Praetor.BodyB", w / 2 - 3, S(92), C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(UI.Fit(P.L("sec_none_hint"), "Praetor.Small", w - S(30)), "Praetor.Small", w / 2 - 3, S(116), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
			-- a line with the day between events of different days
			local lastDay
			for _, r in ipairs(d.rows) do
				local day = os.date("%d/%m/%Y", tonumber(r.t) or 0)
				if day ~= lastDay then
					lastDay = day
					local today = os.date("%d/%m/%Y") == day
					local l = vgui.Create("DPanel", feed)
					l:Dock(TOP)
					l:SetTall(S(22))
					l:DockMargin(0, S(2), S(6), S(2))
					l.Paint = function(_, w, h)
						local txt = today and P.L("sec_today") or day
						surface.SetFont("Praetor.Tiny")
						local tw = surface.GetTextSize(txt)
						UI.Text(txt, "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Rect(tw + S(10), h / 2, w - tw - S(10), 1, C.line)
					end
				end
				addEvent(r)
			end

			owners:Clear()
			if #d.owners == 0 then note(owners, P.L("sec_no_owner"), C.crimsonL) end
			for _, o in ipairs(d.owners) do
				local right2 = o.host and P.L("sec_owner_host") or P.SID32(o.sid)
				local r = row(owners, S(46), function(_, w, h)
					UI.Round(0, 0, w, h, S(6), C.panel2)
					UI.Icon("crown", S(44), S(14) - 8, 16)
					UI.Name(o.name ~= "" and o.name or "?", "Praetor.SmallB", S(64), S(14), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - S(70))
					UI.Text(right2, "Praetor.Tiny", S(44), S(33), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end)
				local av = UI.FramedAvatar(r, S(30), nil, o.sid)
				av:SetPos(S(6), S(8))
			end
			fit(owners)

			fillScan(last.scan)

			famBox:Clear()
			if #(d.family or {}) == 0 then note(famBox, P.L("sec_family_none")) end
			for _, f in ipairs(d.family or {}) do
				local r = row(famBox, S(46), function(_, w, h)
					UI.Round(0, 0, w, h, S(6), C.panel2)
					UI.Name(f.name, "Praetor.SmallB", S(44), S(14), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - S(50))
					UI.Text(UI.Fit(P.L("sec_family_owner", { S = util.SteamIDFrom64(f.owner) }), "Praetor.Tiny", w - S(50)), "Praetor.Tiny", S(44), S(33), C.amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end)
				local av = UI.FramedAvatar(r, S(30), nil, f.sid)
				av:SetPos(S(6), S(8))
				r:SetCursor("hand")
				r.OnMousePressed = function()
					UI.Popup({
						{ P.L("copy_steamid"), "copy", function() SetClipboardText(util.SteamIDFrom64(f.sid)) end },
						{ P.L("sec_family_copy_owner"), "copy", function() SetClipboardText(util.SteamIDFrom64(f.owner)) end },
						{ P.L("open_profile"), "players", function() gui.OpenURL("https://steamcommunity.com/profiles/" .. f.owner) end },
					})
				end
			end
			fit(famBox)

			backups:Clear()
			if #d.backups == 0 then note(backups, P.L("sec_backups_none")) end
			for _, f in ipairs(d.backups) do
				local y, mo, da, hh, mi, ss = f:match("ranks_(%d%d%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)")
				local label = y and (da .. "/" .. mo .. "/" .. y .. "  " .. hh .. ":" .. mi .. ":" .. ss) or f
				local r = row(backups, S(32), function(_, w, h)
					UI.Round(0, 0, w, h, S(5), C.panel2)
					UI.Icon("scroll", S(8), (h - 16) / 2, 16, Color(255, 255, 255, 160))
					UI.Text(label, "Praetor.Small", S(30), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end)
				if P.IsOwner(LocalPlayer()) then
					local b = UI.Button(r, P.L("sec_restore"), "ghost", nil, function()
						UI.Confirm(P.L("sec_restore"), P.L("sec_restore_q", { S = label }), function() P.Request("backup_restore", { f = f }) end, true)
					end)
					b:SetFont("Praetor.Small")
					b:Dock(RIGHT)
					b:SetWide(S(96))
					b:DockMargin(0, S(3), S(3), S(3))
				end
			end
			fit(backups)
			right:InvalidateLayout()
		end)
		ask()
	end,
})
