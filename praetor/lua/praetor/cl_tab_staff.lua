-- Praetor menu: Staff panel. Who is working: hours online and on duty,
-- commands, punishments, reports and Blackbox cases closed, support rooms and
-- the stars players gave. Today, 7 days, 30 days or everything; sortable; the
-- ones that have not played for a while get an "Inactive" mark.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local state = { days = 7, sort = "online", sel = nil }
local data

local function hours(sec)
	sec = tonumber(sec) or 0
	if sec < 60 then return "0m" end
	return P.FormatHours(sec)
end

local function rating(e)
	if (e.rated or 0) <= 0 then return nil end
	return e.stars / e.rated
end

local function actionsOf(e) return (e.kicks or 0) + (e.bans or 0) + (e.warns or 0) + (e.pun or 0) end
local function supportOf(e) return (e.reports or 0) + (e.cases or 0) + (e.sits or 0) end

local SORTS = {
	online = function(e) return e.online or 0 end,
	duty = function(e) return e.duty or 0 end,
	cmds = function(e) return e.cmds or 0 end,
	pun = actionsOf,
	support = supportOf,
	stars = function(e) return rating(e) or -1 end,
	last = function(e) return e.on and math.huge or (e.last or 0) end,
}

local function inactive(e)
	if e.on then return false end
	local days = (data and data.inactive) or 7
	return days > 0 and (e.last or 0) > 0 and os.time() - e.last > days * 86400 or (e.last or 0) == 0
end

local function drawStars(x, y, size, v, a)
	for i = 1, 5 do
		local full = v >= i - 0.25
		local half = not full and v >= i - 0.75
		local cx = x + (i - 1) * (size + S(2))
		UI.Icon("star", cx, y, size, full and Color(255, 255, 255, a or 255) or Color(255, 255, 255, (half and 120 or 35) * (a or 255) / 255))
	end
end

local function buildDetail(detail, e)
	detail:Clear()
	if not e then
		detail.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(8), C.panel, C.line)
			UI.Icon("shield", w / 2 - 16, h / 2 - S(40), 32, Color(255, 255, 255, 80))
			UI.Text(P.L("st_pick"), "Praetor.SmallB", w / 2, h / 2 + S(4), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			UI.Text(P.L("st_pick_d"), "Praetor.Tiny", w / 2, h / 2 + S(24), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return
	end
	local online = player.GetBySteamID64(e.sid)
	detail.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(8), C.panel, C.line)
		local av = S(52)
		UI.DrawAvatar(e.sid, IsValid(online) and online or nil, S(14), S(14), av, 255, IsValid(online) and UI.AvatarFrame(online) or nil, e.name)
		local x = S(14) + av + S(12)
		UI.Name(e.name, "Praetor.H2", x, S(16), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, w - x - S(10))
		local style, icon = UI.RankStyle(e.rank)
		UI.Badge(style, icon, "Praetor.Tiny", x, S(44), S(20))
		local st = e.on and (e.dutyNow and P.L("st_on_duty") or P.L("online")) or (inactive(e) and P.L("st_inactive") or P.L("st_last", { V = P.Date(e.last) }))
		UI.Text(st, "Praetor.Tiny", w - S(14), S(54), e.on and C.laurel or (inactive(e) and C.crimsonL or C.muted), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		-- 14 days of play time
		local gy = S(86)
		UI.Text(P.L("st_last14"), "Praetor.SmallB", S(14), gy, C.ivory)
		local gx, gw, gh = S(14), w - S(28), S(90)
		local top = gy + S(24)
		UI.Round(gx, top, gw, gh, S(6), Color(12, 13, 17), C.line)
		local maxv = 1
		for _, v in ipairs(e.spark or {}) do maxv = math.max(maxv, v) end
		local n = #(e.spark or {})
		if n > 0 then
			local bw = (gw - S(16)) / n
			for i, v in ipairs(e.spark) do
				local bh = math.floor((gh - S(26)) * v / maxv)
				local bx = gx + S(8) + (i - 1) * bw
				if v > 0 then UI.Round(bx + S(2), top + gh - S(16) - bh, bw - S(4), bh, S(2), i == n and C.bronzeL or C.bronze) end
				if i == 1 or i == n or i == math.ceil(n / 2) then
					local d = os.date("%d/%m", os.time() - (n - i) * 86400)
					UI.Text(d, "Praetor.Tiny", bx + bw / 2, top + gh - S(7), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
			UI.Text(P.L("st_max_min", { V = maxv }), "Praetor.Tiny", gx + gw - S(6), top - S(8), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end

		-- numbers
		local rows = {
			{ "clock", P.L("st_c_online"), hours(e.online) },
			{ "shield", P.L("st_c_duty"), hours(e.duty) },
			{ "bolt", P.L("st_c_cmds"), tostring(e.cmds) },
			{ "door", P.L("st_c_kicks"), tostring(e.kicks) },
			{ "hammer", P.L("st_c_bans"), tostring(e.bans) },
			{ "warn", P.L("st_c_warns"), tostring(e.warns) },
			{ "jail", P.L("st_c_pun"), tostring(e.pun) },
			{ "flag", P.L("st_c_reports"), tostring(e.reports) },
			{ "scroll", P.L("st_c_cases"), tostring(e.cases) },
			{ "headset", P.L("st_c_sits"), tostring(e.sits) },
		}
		local ry = top + gh + S(14)
		local colW = (w - S(28) - S(10)) / 2
		for i, r in ipairs(rows) do
			local cx = S(14) + ((i - 1) % 2) * (colW + S(10))
			local cy = ry + math.floor((i - 1) / 2) * S(30)
			UI.Round(cx, cy, colW, S(26), S(5), C.panel2)
			UI.Icon(r[1], cx + S(6), cy + (S(26) - 16) / 2, 16)
			surface.SetFont("Praetor.SmallB")
			local vw = surface.GetTextSize(r[3])
			UI.Text(UI.Fit(r[2], "Praetor.Tiny", colW - S(28) - vw - S(16)), "Praetor.Tiny", cx + S(28), cy + S(13), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(r[3], "Praetor.SmallB", cx + colW - S(8), cy + S(13), C.ivory, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		local sy = ry + math.ceil(#rows / 2) * S(30) + S(8)
		UI.Text(P.L("st_c_stars"), "Praetor.SmallB", S(14), sy + S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local rt = rating(e)
		if rt then
			drawStars(w - S(14) - 5 * 18, sy + S(2), 16, rt)
			UI.Text(string.format("%.1f  (%d)", rt, e.rated), "Praetor.Tiny", w - S(14) - 5 * 18 - S(8), sy + S(10), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		else
			UI.Text(P.L("st_no_stars"), "Praetor.Tiny", w - S(14), sy + S(10), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	local open = UI.Button(detail, P.L("st_open_sheet"), "ghost", "badge", function() P.OpenMenu("users", { sid = e.sid }) end)
	open:Dock(BOTTOM)
	open:SetTall(S(34))
	open:DockMargin(S(12), 0, S(12), S(12))
end

P.AddTab("staff", {
	cat = "management", icon = "shield", order = 1.5,
	can = function() return P.MyHas("staff_stats") end,
	build = function(panel)
		local bar = UI.Toolbar(panel)
		local chips = {}
		for _, d in ipairs({ { 1, "st_today" }, { 7, "st_7" }, { 30, "st_30" }, { 0, "st_all" } }) do
			local b = vgui.Create("DButton", bar)
			b:SetText("")
			surface.SetFont("Praetor.Small")
			b:SetWide(surface.GetTextSize(P.L(d[2])) + S(28))
			b:Dock(LEFT)
			b:DockMargin(0, 0, S(6), 0)
			b.Paint = function(s, w, h)
				local on = state.days == d[1]
				UI.Round(0, 0, w, h, S(6), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
				UI.Text(P.L(d[2]), "Praetor.Small", w / 2, h / 2, on and C.ivory or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			b.DoClick = function() UI.Sound("click") state.days = d[1] P.Request("staff_stats", { days = d[1] }) end
			chips[#chips + 1] = b
		end
		local refresh = UI.Button(bar, P.L("ui_refresh"), "ghost", "reload", function() P.Request("staff_stats", { days = state.days }) end)
		refresh:Dock(RIGHT)
		refresh:SetWide(S(130))

		-- summary
		local tiles = vgui.Create("DPanel", panel)
		tiles:Dock(TOP)
		tiles:SetTall(S(62))
		tiles:DockMargin(0, 0, 0, S(8))
		tiles.Paint = function(_, w, h)
			local list = data and data.list or {}
			local on, tot, pun, sup, st, rt = 0, 0, 0, 0, 0, 0
			for _, e in ipairs(list) do
				if e.on then on = on + 1 end
				tot = tot + (e.online or 0)
				pun = pun + actionsOf(e)
				sup = sup + supportOf(e)
				st, rt = st + (e.stars or 0), rt + (e.rated or 0)
			end
			local t = {
				{ "players", C.laurel, on .. " / " .. #list, P.L("st_t_online") },
				{ "clock", C.sky, hours(tot), P.L("st_t_hours") },
				{ "hammer", C.crimson, tostring(pun), P.L("st_t_pun") },
				{ "flag", C.amber, tostring(sup), P.L("st_t_support") },
				{ "star", C.bronze, rt > 0 and string.format("%.1f", st / rt) or "-", P.L("st_t_stars", { V = rt }) },
			}
			local gap = S(8)
			local tw = math.floor((w - gap * (#t - 1)) / #t)
			for i, it in ipairs(t) do
				local x = (i - 1) * (tw + gap)
				UI.Round(x, 0, tw, h, S(8), C.panel, C.line)
				UI.Round(x + S(10), S(11), S(40), S(40), S(8), Color(it[2].r, it[2].g, it[2].b, 45))
				UI.Icon(it[1], x + S(10) + (S(40) - 32) / 2, S(11) + (S(40) - 32) / 2, 32)
				UI.Text(UI.Fit(it[3], "Praetor.H2", tw - S(70)), "Praetor.H2", x + S(62), S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(it[4], "Praetor.Tiny", tw - S(70)), "Praetor.Tiny", x + S(62), S(44), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end

		local detail = vgui.Create("DPanel", panel)
		detail:Dock(RIGHT)
		detail:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.34), S(280), S(340)))
		detail:DockMargin(S(8), 0, 0, 0)
		buildDetail(detail, nil)

		-- table head (click to sort)
		local COLS = {
			{ "name", P.L("st_h_name"), 1 }, { "online", P.L("st_h_online"), S(80) }, { "duty", P.L("st_h_duty"), S(80) },
			{ "cmds", P.L("st_h_cmds"), S(70) }, { "pun", P.L("st_h_pun"), S(80) }, { "support", P.L("st_h_support"), S(84) },
			{ "stars", P.L("st_h_stars"), S(96) }, { "last", P.L("st_h_last"), S(96) },
		}
		-- columns that don't fit (narrow screens, detail card open) are left out,
		-- least important first, so nothing is cut at the right edge
		local DROP = { 8, 7, 3, 6 }
		local function colX(w)
			local hidden = {}
			local function fixedW()
				local f = 0
				for i, c in ipairs(COLS) do if c[3] > 1 and not hidden[i] then f = f + c[3] end end
				return f
			end
			for _, i in ipairs(DROP) do
				if w - fixedW() - S(16) >= S(170) then break end
				hidden[i] = true
			end
			local fixed = fixedW()
			local xs, x = {}, S(8)
			for i, c in ipairs(COLS) do
				if hidden[i] then
					xs[i] = { w + S(600), 0 } -- off the panel: drawn nowhere, never clicked
				else
					local cw = c[3] > 1 and c[3] or math.max(S(140), w - fixed - S(16))
					xs[i] = { x, cw }
					x = x + cw
				end
			end
			return xs
		end
		local head = vgui.Create("DPanel", panel)
		head:Dock(TOP)
		head:SetTall(S(26))
		head.Paint = function(s, w, h)
			local xs = colX(w)
			for i, c in ipairs(COLS) do
				local on = state.sort == c[1]
				UI.Text(c[2] .. (on and "  v" or ""), "Praetor.Tiny", xs[i][1] + (i == 1 and S(40) or 0), h / 2, on and C.bronzeL or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			UI.Rect(0, h - 1, w, 1, C.line)
		end
		head.OnMousePressed = function(s)
			local mx = s:CursorPos()
			local xs = colX(s:GetWide())
			for i, c in ipairs(COLS) do
				if c[1] ~= "name" and mx >= xs[i][1] and mx < xs[i][1] + xs[i][2] then state.sort = c[1] UI.Sound("click") s:GetParent().fill() end
			end
		end
		head:SetCursor("hand")

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)
		sc:DockMargin(0, S(4), 0, 0)

		local function fill()
			if not IsValid(sc) then return end
			sc:Clear()
			local list = data and data.list or {}
			if #list == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(160))
				e.Paint = function(_, w, h)
					UI.Text(data and P.L("st_none") or P.L("ui_loading"), "Praetor.SmallB", w / 2, h / 2, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			local key = SORTS[state.sort] or SORTS.online
			table.sort(list, function(a, b)
				local va, vb = key(a), key(b)
				if va ~= vb then return va > vb end
				return (a.name or "") < (b.name or "")
			end)
			local maxOn = 1
			for _, e in ipairs(list) do maxOn = math.max(maxOn, e.online or 0) end
			for i, e in ipairs(list) do
				local row = vgui.Create("DButton", sc)
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(44))
				row:DockMargin(0, 0, S(4), S(4))
				row.Paint = function(s, w, h)
					local sel = state.sel == e.sid
					UI.Round(0, 0, w, h, S(6), sel and Color(C.bronze.r, C.bronze.g, C.bronze.b, 40) or (s:IsHovered() and C.hover or C.panel), sel and C.bronze or C.line)
					local xs = colX(w)
					local online = player.GetBySteamID64(e.sid)
					local av = h - S(14)
					UI.DrawAvatar(e.sid, IsValid(online) and online or nil, xs[1][1], S(7), av, 255, IsValid(online) and UI.AvatarFrame(online) or nil, e.name)
					local nx = xs[1][1] + av + S(10)
					local style, icon = UI.RankStyle(e.rank)
					local bw = UI.BadgeWidth(style, icon, "Praetor.Tiny", S(18))
					UI.Name(e.name, "Praetor.SmallB", nx, S(14), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, xs[1][2] - av - S(20))
					if bw < xs[1][2] - av - S(16) then UI.Badge(style, icon, "Praetor.Tiny", nx, h - S(24), S(18)) end
					-- hours with a small bar against the top one
					UI.Text(hours(e.online), "Praetor.SmallB", xs[2][1], S(16), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local bw2 = xs[2][2] - S(14)
					UI.Round(xs[2][1], h - S(13), bw2, S(3), S(1), Color(255, 255, 255, 16))
					UI.Round(xs[2][1], h - S(13), math.max(S(2), bw2 * (e.online or 0) / maxOn), S(3), S(1), C.sky)
					UI.Text(hours(e.duty), "Praetor.Small", xs[3][1], h / 2, e.duty > 0 and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(tostring(e.cmds), "Praetor.Small", xs[4][1], h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local pun = actionsOf(e)
					UI.Text(tostring(pun), "Praetor.Small", xs[5][1], S(16), pun > 0 and C.crimsonL or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(e.kicks .. "k  " .. e.bans .. "b  " .. e.warns .. "w", "Praetor.Tiny", xs[5][1], h - S(13), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(tostring(supportOf(e)), "Praetor.Small", xs[6][1], h / 2, supportOf(e) > 0 and C.amber or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local rt = rating(e)
					if rt then drawStars(xs[7][1], (h - 14) / 2, 14, rt) else UI.Text("-", "Praetor.Small", xs[7][1], h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
					if e.on then
						UI.Text(e.dutyNow and P.L("st_on_duty") or P.L("online"), "Praetor.Tiny", xs[8][1], h / 2, C.laurel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					elseif inactive(e) then
						surface.SetFont("Praetor.Tiny")
						local tw = surface.GetTextSize(P.L("st_inactive")) + S(14)
						UI.Round(xs[8][1], (h - S(20)) / 2, tw, S(20), S(10), Color(C.crimson.r, C.crimson.g, C.crimson.b, 50), C.crimson)
						UI.Text(P.L("st_inactive"), "Praetor.Tiny", xs[8][1] + tw / 2, h / 2, C.crimsonL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					else
						UI.Text(P.Date(e.last), "Praetor.Tiny", xs[8][1], h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
				end
				row.DoClick = function()
					UI.Sound("click")
					state.sel = e.sid
					buildDetail(detail, e)
				end
				if state.sel == e.sid then buildDetail(detail, e) end
			end
		end
		panel.fill = fill
		fill()

		P.On("staff_stats", function(d)
			data = d
			if IsValid(sc) then fill() end
		end)
		P.Request("staff_stats", { days = state.days })
	end,
})
