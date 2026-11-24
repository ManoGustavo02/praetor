-- Praetor menu: Votes. Build a poll (question, options, time), or the map vote:
-- every map of the server with its picture, which ones go in the draw, keep
-- the current map, timers. On the right: the vote running now and the history.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local KEEP = "__keep"

local function chip(parent, label, icon, isOn, fn)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	surface.SetFont("Praetor.Small")
	b:SetWide(surface.GetTextSize(label) + (icon and S(40) or S(20)))
	b.Paint = function(s, w, h)
		local on = isOn()
		UI.Round(0, 0, w, h, S(6), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
		local x = S(10)
		if icon then UI.Icon(icon, S(8), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 170)) x = S(30) end
		UI.Text(label, "Praetor.Small", x, h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function() UI.Sound("click") fn() end
	return b
end

local function section(parent, text, sub)
	local h = UI.Header(parent, text, sub)
	h:Dock(TOP)
	h:DockMargin(0, 0, 0, S(6))
	return h
end

local function ago(t)
	local d = os.time() - (t or os.time())
	if d < 60 then return P.L("vt_now") end
	if d < 3600 then return P.L("vt_min", { V = math.floor(d / 60) }) end
	if d < 86400 then return P.L("vt_hour", { V = math.floor(d / 3600) }) end
	return os.date("%d/%m %H:%M", t)
end

-- ------------------------------------------------------------------ poll builder

local function buildPoll(body, state)
	local sc = UI.Scroll(body)
	sc:Dock(FILL)
	section(sc, P.L("vt_new"), P.L("vt_new_sub"))

	local qL = UI.Label(sc, P.L("vt_question"), "Praetor.BodyB", C.ivory)
	qL:Dock(TOP)
	qL:DockMargin(S(2), 0, 0, S(4))
	local q = UI.Entry(sc, P.L("vt_question_ph"), state.q or "", function(v) state.q = v end)
	q:Dock(TOP)
	q:SetTall(S(40))
	q:SetFont("Praetor.BodyB")

	local optHead = vgui.Create("DPanel", sc)
	optHead:Dock(TOP)
	optHead:SetTall(S(32))
	optHead:DockMargin(0, S(12), 0, S(4))
	optHead.Paint = function(_, w, h)
		UI.Text(P.L("vt_options"), "Praetor.BodyB", S(2), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.L("vt_options_hint"), "Praetor.Tiny", S(80), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local list = vgui.Create("DPanel", sc)
	list:Dock(TOP)
	list.Paint = nil
	local fillOpts
	local function preset(opts) state.o = table.Copy(opts) fillOpts() end
	for _, pr in ipairs({
		{ P.L("vt_pre_yn"), { P.L("yes"), P.L("no") } },
		{ P.L("vt_pre_ynm"), { P.L("yes"), P.L("no"), P.L("vt_maybe") } },
		{ P.L("vt_pre_5"), { "1", "2", "3", "4", "5" } },
	}) do
		local b = UI.Button(optHead, pr[1], "ghost")
		b:SetFont("Praetor.Tiny")
		b:SizeToLabel(S(8))
		b:Dock(RIGHT)
		b:DockMargin(S(4), S(3), 0, S(3))
		b.DoClick = function() UI.Sound("click") preset(pr[2]) end
	end

	fillOpts = function()
		list:Clear()
		state.o = state.o or { "", "" }
		for i = 1, #state.o do
			local row = vgui.Create("DPanel", list)
			row:Dock(TOP)
			row:SetTall(S(36))
			row:DockMargin(0, 0, 0, S(4))
			row.Paint = function(_, w, h)
				UI.Round(0, 0, S(32), h, S(6), C.panel2, C.line)
				UI.Text(tostring(i), "Praetor.BodyB", S(16), h / 2, C.bronzeL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			local del = UI.Button(row, "", "ghost", "trash", function()
				table.remove(state.o, i)
				UI.Sound("click")
				fillOpts()
			end)
			del:Dock(RIGHT)
			del:SetWide(S(36))
			del:SetEnabled(#state.o > 2)
			local e = UI.Entry(row, P.L("vt_option_ph", { V = i }), state.o[i], function(v) state.o[i] = v end)
			e:Dock(FILL)
			e:DockMargin(S(38), 0, S(4), 0)
		end
		if #state.o < 8 then
			local add = UI.Button(list, P.L("vt_add_option"), "subtle", "ballot", function()
				state.o[#state.o + 1] = ""
				UI.Sound("click")
				fillOpts()
			end)
			add:Dock(TOP)
			add:SetTall(S(34))
		end
		list:SetTall((#state.o) * S(40) + (#state.o < 8 and S(34) or 0))
	end
	fillOpts()

	local tL = UI.Label(sc, P.L("vt_time"), "Praetor.BodyB", C.ivory)
	tL:Dock(TOP)
	tL:DockMargin(S(2), S(14), 0, S(4))
	local times = vgui.Create("DPanel", sc)
	times:Dock(TOP)
	times:SetTall(S(32))
	times.Paint = nil
	state.d = state.d or 30
	for _, t in ipairs({ 15, 30, 60, 120, 300 }) do
		local label = t < 60 and (t .. "s") or (math.floor(t / 60) .. "min")
		local c = chip(times, label, "clock", function() return state.d == t end, function() state.d = t end)
		c:Dock(LEFT)
		c:DockMargin(0, 0, S(6), 0)
	end

	local note = UI.Label(sc, P.L("vt_note"), "Praetor.Small", C.muted)
	note:Dock(TOP)
	note:SetWrap(true)
	note:SetAutoStretchVertical(true)
	note:DockMargin(S(2), S(12), 0, S(8))

	local go = UI.Button(body, P.L("vt_start"), "primary", "ballot", function()
		local opts = {}
		for _, o in ipairs(state.o or {}) do
			o = P.Trim(o or "")
			if o ~= "" then opts[#opts + 1] = o end
		end
		if P.Trim(state.q or "") == "" then UI.Sound("error") q:RequestFocus() return end
		P.Request("vote_start", { q = state.q, o = opts, d = state.d })
	end)
	go:Dock(BOTTOM)
	go:SetTall(S(42))
	go:DockMargin(0, S(8), 0, 0)
	go.Think = function(s) s:SetEnabled(not P.CurrentVote() or P.CurrentVote().done ~= nil) end
end

-- ------------------------------------------------------------------ map vote builder

local function buildMaps(body, state)
	local info = P.VoteInfo
	if not info then
		local w = vgui.Create("DPanel", body)
		w:Dock(FILL)
		w.Paint = function(_, pw, ph) UI.Text(P.L("ui_loading"), "Praetor.Body", pw / 2, ph / 2, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
		return
	end
	state.cfg = state.cfg or table.Copy(info.cfg or {})
	local cfg = state.cfg
	cfg.pool = cfg.pool or {}
	local inPool = {}
	for _, m in ipairs(cfg.pool) do inPool[m] = true end
	local function syncPool()
		cfg.pool = {}
		for m in pairs(inPool) do cfg.pool[#cfg.pool + 1] = m end
		table.sort(cfg.pool)
	end

	-- bottom: the buttons on a line of their own, and the options card above them
	-- (before, the buttons sat inside the card, on top of the options)
	local btns = vgui.Create("DPanel", body)
	btns:Dock(BOTTOM)
	btns:SetTall(S(38))
	btns:DockMargin(0, S(8), 0, 0)
	btns.Paint = nil
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(S(138))
	foot:DockMargin(0, S(8), 0, 0)
	foot.Paint = function(_, w, h) UI.Round(0, 0, w, h, S(8), C.panel, C.line) end
	local keep = UI.Switch(foot, P.L("mv_keep_opt"), P.L("mv_keep_opt_d"), cfg.keep ~= false, function(v) cfg.keep = v end)
	keep:Dock(TOP)
	keep:DockMargin(S(10), S(6), S(10), 0)
	local row = vgui.Create("DPanel", foot)
	row:Dock(TOP)
	row:SetTall(S(52))
	row:DockMargin(S(10), S(4), S(10), 0)
	row.Paint = nil
	local function combo(label, opts, val, key)
		local p = vgui.Create("DPanel", row)
		p:Dock(LEFT)
		p:SetWide(S(150))
		p:DockMargin(0, 0, S(10), 0)
		p.Paint = function(_, w, h) UI.Text(label, "Praetor.Tiny", S(2), S(8), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		local c = UI.Combo(p, opts, val, function(v) cfg[key] = v end)
		c:Dock(BOTTOM)
		c:SetTall(S(32))
		return p
	end
	combo(P.L("mv_dur"), { { 20, "20s" }, { 30, "30s" }, { 45, "45s" }, { 60, "1min" }, { 90, "1min 30s" }, { 120, "2min" } }, cfg.dur or 30, "dur")
	combo(P.L("mv_delay"), { { 5, "5s" }, { 10, "10s" }, { 15, "15s" }, { 30, "30s" } }, cfg.delay or 10, "delay")
	local maxOpts = {}
	for i = 2, 9 do maxOpts[#maxOpts + 1] = { i, P.L("mv_n_cards", { V = i }) } end
	combo(P.L("mv_max"), maxOpts, cfg.max or 6, "max")
	local start = UI.Button(btns, P.L("mv_start"), "primary", "map", function()
		syncPool()
		P.Request("mapvote_cfg", cfg)
		timer.Simple(0.3, function() P.Request("mapvote_start", {}) end)
	end)
	start:Dock(RIGHT)
	start:SetWide(S(220))
	start.Think = function(s) s:SetEnabled(P.MyHas("mapvote") and (not P.CurrentVote() or P.CurrentVote().done ~= nil)) end
	local save = UI.Button(btns, P.L("ui_save"), "ghost", "check", function()
		syncPool()
		P.Request("mapvote_cfg", cfg)
	end)
	save:Dock(RIGHT)
	save:SetWide(S(130))
	save:DockMargin(0, 0, S(8), 0)

	-- top: search and pool buttons
	local bar = vgui.Create("DPanel", body)
	bar:Dock(TOP)
	bar:SetTall(S(34))
	bar:DockMargin(0, 0, 0, S(8))
	bar.Paint = function(_, w, h)
		local n = table.Count(inPool)
		local t = n == 0 and P.L("mv_pool_all", { V = #(info.maps or {}) }) or P.L("mv_pool_n", { V = n, M = #(info.maps or {}) })
		UI.Icon("map", 0, (h - 16) / 2, 16)
		UI.Text(t, "Praetor.SmallB", S(22), h / 2, n == 0 and C.muted or C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local search = UI.Entry(bar, P.L("mv_search"))
	search:Dock(RIGHT)
	search:SetWide(S(200))
	local grid
	local none = UI.Button(bar, P.L("mv_none"), "ghost", "cross", function() inPool = {} syncPool() end)
	none:SetFont("Praetor.Small")
	none:SizeToLabel(S(10))
	none:Dock(RIGHT)
	none:DockMargin(0, 0, S(6), 0)
	local all = UI.Button(bar, P.L("mv_all"), "ghost", "check", function()
		for _, m in ipairs(info.maps or {}) do inPool[m] = true end
		syncPool()
	end)
	all:SetFont("Praetor.Small")
	all:SizeToLabel(S(10))
	all:Dock(RIGHT)
	all:DockMargin(0, 0, S(6), 0)

	local sc = UI.Scroll(body)
	sc:Dock(FILL)
	grid = vgui.Create("DIconLayout", sc)
	grid:Dock(TOP)
	grid:SetSpaceX(S(8))
	grid:SetSpaceY(S(8))
	local function fill()
		grid:Clear()
		local q = P.Trim(search:GetValue()):lower()
		local tw = S(158)
		local th = S(128)
		for _, m in ipairs(info.maps or {}) do
			local pretty, tag = P.MapPretty(m)
			if q == "" or m:find(q, 1, true) or pretty:lower():find(q, 1, true) then
				local b = grid:Add("DButton")
				b:SetText("")
				b:SetSize(tw, th)
				b.hov = 0
				b.Paint = function(s, w, h)
					s.hov = UI.Lerp(s.hov, s:IsHovered() and 1 or 0, 14)
					local on = inPool[m]
					local isCur = m == info.cur
					UI.Round(0, 0, w, h, S(8), C.panel2, on and C.bronzeL or P.LerpColor(s.hov, C.line, C.lineL))
					local ph = h - S(34)
					P.DrawMapPicture(m, 2, 2, w - 4, ph, (on or table.Count(inPool) == 0) and 255 or 150)
					if tag then
						surface.SetFont("Praetor.Tiny")
						local tgw = surface.GetTextSize(tag) + S(10)
						UI.Round(S(6), S(6), tgw, S(18), S(9), Color(0, 0, 0, 170), C.lineL)
						UI.Text(tag, "Praetor.Tiny", S(6) + tgw / 2, S(15), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					if isCur then
						surface.SetFont("Praetor.Tiny")
						local cl = P.L("mv_current")
						local cw2 = surface.GetTextSize(cl) + S(12)
						UI.Round(w - cw2 - S(6), S(6), cw2, S(18), S(9), Color(C.sky.r, C.sky.g, C.sky.b, 70), C.sky)
						UI.Text(cl, "Praetor.Tiny", w - S(6) - cw2 / 2, S(15), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					-- pool check
					UI.Round(w - S(28), ph - S(24), S(22), S(22), S(6), on and C.bronze or Color(0, 0, 0, 150), on and C.bronzeL or C.lineL)
					if on then UI.Icon("check", w - S(28) + (S(22) - 16) / 2, ph - S(24) + (S(22) - 16) / 2, 16) end
					UI.Text(UI.Fit(pretty, "Praetor.SmallB", w - S(16)), "Praetor.SmallB", S(8), ph + S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(UI.Fit(m, "Praetor.Tiny", w - S(16)), "Praetor.Tiny", S(8), ph + S(25), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				b.DoClick = function()
					UI.Sound("click")
					inPool[m] = not inPool[m] or nil
					syncPool()
				end
			end
		end
		grid:InvalidateLayout(true)
	end
	search.OnChange = fill
	fill()
end

-- ------------------------------------------------------------------ right column

local function buildSide(side)
	-- vote running now
	local now = vgui.Create("DPanel", side)
	now:Dock(TOP)
	now:SetTall(S(220))
	now:DockMargin(0, 0, 0, S(10))
	now.Paint = function(s, w, h)
		UI.Round(0, 0, w, h, S(8), C.panel, C.line)
		UI.Text(P.L("vt_live"), "Praetor.H3", S(12), S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local v = P.CurrentVote()
		local info = P.VoteInfo
		if not v or v.done then
			local pend = info and info.pend
			UI.Icon(pend and "map" or "ballot", w / 2 - 16, h / 2 - S(40), 32, Color(255, 255, 255, 120))
			UI.Text(pend and P.L("mv_pending", { S = P.MapPretty(pend) }) or P.L("vt_none"), "Praetor.BodyB", w / 2, h / 2 + S(10), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if not pend then UI.Text(P.L("vt_none_d"), "Praetor.Tiny", w / 2, h / 2 + S(32), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			return
		end
		-- live dot
		local pulse = (math.sin(RealTime() * 5) + 1) / 2
		UI.Round(w - S(70), S(11), S(8), S(8), S(4), Color(C.crimsonL.r, C.crimsonL.g, C.crimsonL.b, 150 + pulse * 105))
		UI.Text(math.max(0, math.ceil(v.ends - RealTime())) .. "s", "Praetor.SmallB", w - S(12), S(16), C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		local q = P.VoteTitle and P.VoteTitle(v) or (v.kind == "map" and P.L("mv_title") or v.q)
		UI.Text(UI.Fit(q, "Praetor.BodyB", w - S(24)), "Praetor.BodyB", S(12), S(44), C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local tot = 0
		for _, n in ipairs(v.c or {}) do tot = tot + n end
		local y = S(62)
		for i = 1, math.min(#v.o, 6) do
			local n = v.c[i] or 0
			local pct = tot > 0 and n / tot or 0
			UI.Round(S(12), y, w - S(24), S(18), S(4), C.panel2)
			if pct > 0 then UI.Round(S(12), y, (w - S(24)) * pct, S(18), S(4), Color(C.bronze.r, C.bronze.g, C.bronze.b, 120)) end
			UI.Text(UI.Fit(P.VoteOptionLabel(v, i), "Praetor.Tiny", w - S(90)), "Praetor.Tiny", S(18), y + S(9), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(n .. "  " .. math.Round(pct * 100) .. "%", "Praetor.Tiny", w - S(18), y + S(9), C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			y = y + S(21)
		end
	end
	local nowBtns = vgui.Create("DPanel", now)
	nowBtns:Dock(BOTTOM)
	nowBtns:SetTall(S(32))
	nowBtns:DockMargin(S(10), 0, S(10), S(10))
	nowBtns.Paint = nil
	local stop = UI.Button(nowBtns, P.L("vt_stop"), "danger", "stop", function()
		local v = P.CurrentVote()
		local pend = P.VoteInfo and P.VoteInfo.pend
		if (v and not v.done) or pend then
			UI.Confirm(P.L("vt_stop"), P.L((v and not v.done) and "vt_stop_q" or "mv_abort_q"), function()
				P.Request("vote_cancel", {})
				timer.Simple(0.5, function() P.Request("vote_info", {}) end)
			end, true)
		end
	end)
	stop:Dock(FILL)
	stop.Think = function(s)
		local v = P.CurrentVote()
		local pend = P.VoteInfo and P.VoteInfo.pend
		s:SetVisible((v and not v.done) or pend ~= nil)
	end
	local reopen = UI.Button(nowBtns, "", "ghost", "eye", function() P.ReopenMapVote() if IsValid(P.Menu) then P.Menu:Remove() end end)
	reopen:Dock(RIGHT)
	reopen:SetWide(S(36))
	reopen:DockMargin(S(6), 0, 0, 0)
	reopen.Think = function(s) local v = P.CurrentVote() s:SetVisible(v ~= nil and v.kind == "map" and not v.done) end

	-- history
	section(side, P.L("vt_history"), nil)
	local sc = UI.Scroll(side)
	sc:Dock(FILL)
	local function fill()
		sc:Clear()
		local hist = P.VoteInfo and P.VoteInfo.hist or {}
		if #hist == 0 then
			local e = vgui.Create("DPanel", sc)
			e:Dock(TOP)
			e:SetTall(S(60))
			e.Paint = function(_, w, h) UI.Text(P.L("vt_hist_none"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			return
		end
		for _, it in ipairs(hist) do
			local r = vgui.Create("DPanel", sc)
			r:Dock(TOP)
			r:SetTall(S(58))
			r:DockMargin(0, 0, S(4), S(4))
			local fake = { kind = it.kind, o = it.o or {}, yn = it.yn, cur = it.cur }
			local tot = 0
			for _, n in ipairs(it.c or {}) do tot = tot + n end
			r.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(6), C.panel2, C.line)
				if it.kind == "map" and it.w then
					local m = it.o[it.w] == KEEP and it.cur or it.o[it.w]
					P.DrawMapPicture(m, S(6), S(6), S(46), S(46))
				else
					UI.Round(S(6), S(6), S(46), S(46), S(6), Color(C.bronze.r, C.bronze.g, C.bronze.b, 40))
					UI.Icon("ballot", S(6) + (S(46) - 32) / 2, S(6) + (S(46) - 32) / 2, 32)
				end
				local x = S(60)
				local title = it.kind == "map" and P.L("mv_short") or (it.act and P.VoteTitle and P.VoteTitle(it) or tostring(it.q))
				UI.Text(UI.Fit(title, "Praetor.SmallB", w - x - S(70)), "Praetor.SmallB", x, S(16), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(ago(it.t), "Praetor.Tiny", w - S(8), S(16), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				local res = it.w and (P.VoteOptionLabel(fake, it.w) .. "  ·  " .. (it.c[it.w] or 0) .. "/" .. tot) or P.L("vote_nowin")
				UI.Icon(it.w and "crown" or "cross", x, S(32), 16, Color(255, 255, 255, 200))
				UI.Text(UI.Fit(res, "Praetor.Small", w - x - S(30)), "Praetor.Small", x + 22, S(40), it.w and C.laurel or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
	end
	fill()
	return fill
end

-- ------------------------------------------------------------------ tab

P.AddTab("votes", {
	cat = "server", icon = "ballot", order = 1.6,
	can = function() return P.MyHas("vote") or P.MyHas("mapvote") end,
	build = function(panel)
		local state = { mode = P.MyHas("vote") and "poll" or "map" }
		local side = vgui.Create("DPanel", panel)
		side:Dock(RIGHT)
		side:SetWide(S(320))
		side:DockMargin(S(12), 0, 0, 0)
		side.Paint = nil
		local fillHist = buildSide(side)

		local top = vgui.Create("DPanel", panel)
		top:Dock(TOP)
		top:SetTall(S(40))
		top:DockMargin(0, 0, 0, S(10))
		top.Paint = nil
		local body = vgui.Create("DPanel", panel)
		body:Dock(FILL)
		body.Paint = nil
		local function show()
			body:Clear()
			if state.mode == "poll" then buildPoll(body, state) else buildMaps(body, state) end
		end
		for _, m in ipairs({ { "poll", "ballot", "vt_poll", "vote" }, { "map", "map", "mv_short", "mapvote" } }) do
			if P.MyHas(m[4]) then
				local b = vgui.Create("DButton", top)
				b:SetText("")
				b:Dock(LEFT)
				b:SetWide(S(200))
				b:DockMargin(0, 0, S(8), 0)
				b.Paint = function(s, w, h)
					local on = state.mode == m[1]
					UI.Round(0, 0, w, h, S(8), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 45) or (s:IsHovered() and C.hover or C.panel), on and C.bronze or C.line)
					UI.Icon(m[2], S(12), (h - 16) / 2, 16)
					UI.Text(P.L(m[3]), "Praetor.BodyB", S(36), h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				b.DoClick = function()
					if state.mode == m[1] then return end
					UI.Sound("tab")
					state.mode = m[1]
					show()
				end
			end
		end
		show()
		hook.Add("Praetor.VoteInfo", panel, function()
			if state.mode == "map" and not state.cfg then show() end
			fillHist()
		end)
		hook.Add("Praetor.VoteChanged", panel, function() timer.Simple(0.3, function() P.Request("vote_info", {}) end) end)
		P.Request("vote_info", {})
	end,
})
