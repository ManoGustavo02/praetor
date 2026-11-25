-- Praetor: scheduled restart on the screen and the Restart tab.
--  * warnings as a banner + chat line, a small bar at the top in the last
--    minutes and a big countdown in the last 10 seconds
--  * tab: the next restart (live), restart in N minutes, skip / cancel, and the
--    schedule: times of the day, map reload or server restart, warnings,
--    postpone vote
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

P.RestartSt = P.RestartSt or nil
local cancelled

local function clock(secs)
	secs = math.max(0, math.floor(secs))
	local h, m, s = math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end

P.On("rst_state", function(d)
	if d.left then d.until_ = RealTime() + d.left end
	P.RestartSt = d.left and d or nil
	hook.Run("Praetor.RestartChanged")
end)

P.On("rst_warn", function(d)
	local key = d.mode == "server" and "rst_warn_server" or "rst_warn_map"
	local txt = P.L(key, { V = d.m })
	P.ShowAnn({ title = P.L("rst_title"), text = txt, where = "banner", life = 9, snd = true, icon = "reload", col = { r = 226, g = 160, b = 64 } })
	chat.AddText(C.bronzeD, "| ", C.amber, P.L("rst_title") .. ": ", C.ivory, txt)
	UI.Sound("warn")
	if P.RestartSt and d.left then P.RestartSt.until_ = RealTime() + d.left end
end)

P.On("rst_delayed", function(d)
	chat.AddText(C.bronzeD, "| ", C.laurel, P.L("rst_delayed", { V = d.v or 15 }))
	UI.Sound("ok")
end)

P.On("rst_cancel", function(d)
	cancelled = RealTime()
	chat.AddText(C.bronzeD, "| ", C.muted, P.L("rst_cancelled", { S = d.n or "?" }))
end)

-- bar at the top in the last minutes, big numbers in the last 10 seconds
hook.Add("HUDPaint", "Praetor.Restart", function()
	local st = P.RestartSt
	if not st or not st.until_ then return end
	local left = st.until_ - RealTime()
	if left < -20 then return end
	-- the bar shows in the last 5 minutes
	local showFrom = 300
	if left > showFrom then return end
	local txt = P.L(st.mode == "server" and "rst_bar_server" or "rst_bar_map", { V = clock(left) })
	surface.SetFont("Praetor.BodyB")
	local tw = surface.GetTextSize(txt) + S(60)
	local x, y = ScrW() / 2 - tw / 2, S(18)
	if P.MySit then y = y + S(58) end
	local urgent = left < 60
	local col = urgent and C.crimsonL or C.amber
	UI.Round(x + S(4), y + S(4), tw, S(38), math.max(S(19), S(12)), Color(C.ink.r, C.ink.g, C.ink.b, (236) * 0.8)) UI.Round(x, y, tw, S(38), math.max(S(19), S(12)), Color(C.panel.r, C.panel.g, C.panel.b, 236), col)
	local frac = math.Clamp(left / math.max(1, showFrom), 0, 1)
	UI.Round(x + S(19), y + S(34), (tw - S(38)) * frac, S(2), S(1), col)
	UI.Icon("reload", x + S(14), y + (S(38) - 16) / 2, 16, col)
	UI.Text(txt, "Praetor.BodyB", x + S(40), y + S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if left <= 10 and left > 0 then
		local n = math.ceil(left)
		local f = left - math.floor(left)
		local a = 255 * math.Clamp(f * 1.6, 0, 1)
		UI.TextShadow(tostring(n), "Praetor.Logo", ScrW() / 2, ScrH() * 0.3, Color(col.r, col.g, col.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		UI.Text(P.L("rst_now"), "Praetor.BodyB", ScrW() / 2, ScrH() * 0.3 + S(44), Color(C.ivory.r, C.ivory.g, C.ivory.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

-- ------------------------------------------------------------------ tab

local function chip(parent, label, isOn, fn, wide)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	surface.SetFont("Praetor.Small")
	b:SetWide(wide or (surface.GetTextSize(label) + S(28)))
	b:Dock(LEFT)
	b:DockMargin(0, 0, S(6), 0)
	b.Paint = function(s, w, h)
		local on = isOn()
		UI.Round(0, 0, w, h, h / 2, on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
		UI.Text(label, "Praetor.Small", w / 2, h / 2, on and C.ivory or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function() UI.Sound("click") fn() end
	return b
end

local function row(parent, tall, mb)
	local r = vgui.Create("DPanel", parent)
	r:Dock(TOP)
	r:SetTall(tall or S(32))
	r:DockMargin(0, 0, S(8), mb or S(8))
	r.Paint = nil
	return r
end

local function label(parent, text, sub)
	local h = UI.Header(parent, text, sub)
	h:Dock(TOP)
	h:DockMargin(0, S(6), S(8), S(6))
	return h
end

P.AddTab("restart", {
	cat = "server", icon = "reload", order = 3.5,
	can = function() return P.MyHas("manage_restart") end,
	build = function(panel)
		local info
		local cfg = { times = {}, warn = { 15, 10, 5, 1 }, mode = "map", vote = true, delay = 15, maxDelay = 2 }

		-- ---------------------------------------------------------- next restart (left)
		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:DockMargin(0, 0, S(12), 0)
		left.Paint = nil
		panel.PerformLayout = function(_, w) left:SetWide(math.floor(w * 0.46)) end

		local card = vgui.Create("DPanel", left)
		card:Dock(TOP)
		card:SetTall(S(196))
		card:DockMargin(0, 0, 0, S(10))
		card.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(10), C.panel2, C.line)
			local st = P.RestartSt
			UI.Text(P.Upper(P.L("rst_next")), "Praetor.Tiny", S(16), S(18), C.dim)
			if not st or not st.until_ then
				UI.Icon("reload", w / 2 - 16, h / 2 - S(36), 32, Color(255, 255, 255, 90))
				UI.Text(P.L("rst_none"), "Praetor.BodyB", w / 2, h / 2 + S(10), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(P.L("rst_none_d"), "Praetor.Small", w - S(30)), "Praetor.Small", w / 2, h / 2 + S(32), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			local l = st.until_ - RealTime()
			local col = l < 300 and C.amber or C.bronzeL
			UI.Text(clock(l), "Praetor.Logo", S(16), S(56), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local when = st.at and os.date("%H:%M", st.at) or "?"
			UI.Text(P.L("rst_at", { S = when }), "Praetor.BodyB", S(16), S(94), C.ivory)
			local why = st.why == "manual" and P.L("rst_why_manual", { S = st.by or "?" }) or P.L("rst_why_schedule")
			UI.Text(UI.Fit(why, "Praetor.Small", w - S(32)), "Praetor.Small", S(16), S(118), C.muted)
			local mode = st.mode == "server" and P.L("rst_mode_server") or P.L("rst_mode_map")
			local dl = (st.delays or 0) > 0 and ("  -  " .. P.L("rst_delays", { V = st.delays, V2 = st.maxDelay or 0 })) or ""
			UI.Text(UI.Fit(mode .. dl, "Praetor.Small", w - S(32)), "Praetor.Small", S(16), S(138), C.text)
		end
		local btns = vgui.Create("DPanel", card)
		btns:Dock(BOTTOM)
		btns:SetTall(S(32))
		btns:DockMargin(S(14), 0, S(14), S(12))
		btns.Paint = nil
		local skip = UI.Button(btns, P.L("rst_skip"), "danger", "stop", function()
			local st = P.RestartSt
			if not st then return end
			UI.Confirm(P.L("rst_skip"), P.L(st.why == "manual" and "rst_cancel_q" or "rst_skip_q"), function() P.Request("rst_skip") end, true)
		end)
		skip:Dock(RIGHT)
		skip:SetWide(S(170))
		skip.Think = function(s) s:SetVisible(P.RestartSt ~= nil) end

		label(left, P.L("rst_in"), P.L("rst_in_d"))
		local nowRow = row(left, S(32))
		for _, m in ipairs({ 1, 5, 10, 15, 30, 60 }) do
			chip(nowRow, m .. " min", function() return false end, function()
				UI.Confirm(P.L("rst_in"), P.L("rst_in_q", { V = m }), function() P.Request("rst_now", { min = m }) end)
			end)
		end
		local custom = row(left, S(32))
		local minEntry = UI.Entry(custom, P.L("rst_custom_ph"))
		minEntry:SetNumeric(true)
		minEntry:Dock(FILL)
		local go = UI.Button(custom, P.L("rst_go"), "primary", "clock", function()
			local m = tonumber(minEntry:GetValue())
			if not m or m < 0 then UI.Sound("error") minEntry:RequestFocus() return end
			UI.Confirm(P.L("rst_in"), P.L("rst_in_q", { V = math.floor(m) }), function() P.Request("rst_now", { min = math.floor(m) }) end)
		end)
		go:Dock(RIGHT)
		go:SetWide(S(140))
		go:DockMargin(S(6), 0, 0, 0)

		local hint = vgui.Create("DPanel", left)
		hint:Dock(TOP)
		hint:SetTall(S(52))
		hint:DockMargin(0, S(8), S(8), 0)
		hint.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(6), C.bg, C.line)
			UI.Icon("info", S(10), (h - 16) / 2, 16, Color(255, 255, 255, 140))
			local lines = UI.Wrap(P.L("rst_cmd_hint"), "Praetor.Small", w - S(44))
			for i = 1, math.min(#lines, 2) do UI.Text(lines[i], "Praetor.Small", S(34), S(8) + (i - 1) * S(18), C.muted) end
		end

		-- ---------------------------------------------------------- schedule (right)
		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		label(sc, P.L("rst_times"), P.L("rst_times_d"))
		local times = vgui.Create("DIconLayout", sc)
		times:Dock(TOP)
		times:DockMargin(0, 0, S(8), S(8))
		times:SetSpaceX(S(6))
		times:SetSpaceY(S(6))
		local clockNow = UI.Label(sc, "", "Praetor.Tiny", C.dim)
		clockNow:Dock(TOP)
		clockNow:DockMargin(0, 0, S(8), S(6))
		local addRow = row(sc, S(32))
		local tEntry = UI.Entry(addRow, P.L("rst_time_ph"))
		tEntry:Dock(FILL)
		local save
		local function rebuildTimes()
			times:Clear()
			if #cfg.times == 0 then
				local e = times:Add("DLabel")
				e:SetFont("Praetor.Small")
				e:SetTextColor(C.dim)
				e:SetText(P.L("rst_times_none"))
				e:SizeToContents()
				e:SetTall(S(30))
			end
			for i, t in ipairs(cfg.times) do
				local b = times:Add("DButton")
				b:SetText("")
				b:SetSize(S(96), S(32))
				b.Paint = function(s, w, h)
					local hov = s:IsHovered()
					UI.Round(0, 0, w, h, S(8), hov and Color(C.crimson.r, C.crimson.g, C.crimson.b, 40) or C.panel2, hov and C.crimsonL or C.bronze)
					UI.Icon("clock", S(8), (h - 16) / 2, 16, Color(255, 255, 255, 170))
					UI.Text(t, "Praetor.BodyB", S(30), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(hov and "x" or "", "Praetor.BodyB", w - S(12), h / 2 - 1, C.crimsonL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				b:SetTooltip(P.L("rst_time_del"))
				b.DoClick = function()
					UI.Sound("click")
					table.remove(cfg.times, i)
					rebuildTimes()
				end
			end
			times:InvalidateLayout(true)
			times:SizeToChildren(false, true)
		end
		local function addTime()
			local v = P.Trim(tEntry:GetValue()):gsub("[hH%.]", ":")
			if v:match("^%d%d?$") then v = v .. ":00" end
			local h, m = v:match("^(%d%d?):(%d%d)$")
			h, m = tonumber(h), tonumber(m)
			if not h or h > 23 or m > 59 then UI.Sound("error") tEntry:RequestFocus() return end
			local s = string.format("%02d:%02d", h, m)
			for _, t in ipairs(cfg.times) do if t == s then return end end
			if #cfg.times >= 12 then UI.Sound("error") return end
			cfg.times[#cfg.times + 1] = s
			table.sort(cfg.times)
			tEntry:SetValue("")
			rebuildTimes()
		end
		tEntry.OnEnter = addTime
		local add = UI.Button(addRow, P.L("rst_time_add"), "ghost", "pin", addTime)
		add:Dock(RIGHT)
		add:SetWide(S(130))
		add:DockMargin(S(6), 0, 0, 0)

		label(sc, P.L("rst_mode"), P.L("rst_mode_d"))
		local modeRow = row(sc, S(32))
		chip(modeRow, P.L("rst_mode_map"), function() return cfg.mode ~= "server" end, function() cfg.mode = "map" end)
		chip(modeRow, P.L("rst_mode_server"), function() return cfg.mode == "server" end, function() cfg.mode = "server" end)

		label(sc, P.L("rst_warns"), P.L("rst_warns_d"))
		local warnRow = row(sc, S(30))
		local function hasWarn(m) for _, w in ipairs(cfg.warn) do if w == m then return true end end return false end
		for _, m in ipairs({ 30, 15, 10, 5, 3, 1 }) do
			chip(warnRow, m .. " min", function() return hasWarn(m) end, function()
				if hasWarn(m) then
					for i, w in ipairs(cfg.warn) do if w == m then table.remove(cfg.warn, i) break end end
				else cfg.warn[#cfg.warn + 1] = m end
			end, S(64))
		end

		label(sc, P.L("rst_vote"), P.L("rst_vote_d"))
		local voteSw = UI.Switch(sc, P.L("rst_vote_on"), P.L("rst_vote_on_d"), cfg.vote, function(v) cfg.vote = v end)
		voteSw:Dock(TOP)
		voteSw:DockMargin(0, 0, S(8), S(6))
		local nums = row(sc, S(56))
		local function numBox(title, key, w)
			local p = vgui.Create("DPanel", nums)
			p:Dock(LEFT)
			p:SetWide(w)
			p:DockMargin(0, 0, S(10), 0)
			p.Paint = nil
			local l = UI.Label(p, title, "Praetor.SmallB", C.muted)
			l:Dock(TOP)
			l:DockMargin(0, 0, 0, S(4))
			local e = UI.Entry(p, "", tostring(cfg[key]))
			e:SetNumeric(true)
			e:Dock(TOP)
			e.OnChange = function(s) cfg[key] = tonumber(s:GetValue()) or cfg[key] end
			p.entry = e
			return p
		end
		local delayBox = numBox(P.L("rst_delay"), "delay", S(170))
		local maxBox = numBox(P.L("rst_maxdelay"), "maxDelay", S(170))

		save = UI.Button(sc, P.L("rst_save"), "primary", "check", function()
			P.Request("rst_cfg", cfg)
		end)
		save:Dock(TOP)
		save:SetTall(S(36))
		save:DockMargin(0, S(14), S(8), S(10))

		local function fill(d)
			info = d
			cfg = table.Copy(d.cfg or cfg)
			cfg.times = cfg.times or {}
			cfg.warn = cfg.warn or {}
			rebuildTimes()
			voteSw:SetValue(cfg.vote == true)
			delayBox.entry:SetValue(tostring(cfg.delay or 15))
			maxBox.entry:SetValue(tostring(cfg.maxDelay or 2))
			clockNow:SetText(P.L("rst_clock", { S = d.clock or "?" }))
			clockNow:SizeToContents()
			if d.st then
				local st = d.st
				if st.left then st.until_ = RealTime() + st.left end
				P.RestartSt = st.left and st or nil
			end
		end
		P.On("rst_info", function(d) if IsValid(sc) then fill(d) end end)
		rebuildTimes()
		P.Request("rst_info")
	end,
})
