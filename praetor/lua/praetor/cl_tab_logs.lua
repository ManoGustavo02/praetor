-- Praetor menu: logs. Each line is stored as a key + arguments, so it is
-- shown in the reader's language. New lines arrive live while the tab is open.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local CATS = { "all", "cmd", "punish", "automod", "chat", "kill", "dmg", "conn", "prop", "tool", "dupe", "rank", "report", "rp", "money", "player", "round", "settings", "security", "addon" }
local CAT_COL = {
	cmd = C.bronzeL, punish = C.crimsonL, automod = C.amber, chat = C.text, kill = C.crimson, dmg = C.amber, conn = C.sky,
	prop = C.muted, tool = C.muted, dupe = C.amber, rank = C.laurel, report = C.amber, rp = C.laurel, money = C.bronze, player = C.sky, round = C.amber,
	settings = C.sky, security = C.crimsonL, addon = C.muted,
}
local state = { cat = "all", q = "", sid = "", page = 0, live = true, sess = nil }

local function parts(k, a)
	local args = isstring(a) and (util.JSONToTable(a) or {}) or (a or {})
	return P.TemplateParts(P.L(k), args)
end

local function drawParts(list, x, y, w, font)
	local cx = x
	local col = C.text
	surface.SetFont(font)
	for _, v in ipairs(list) do
		if IsColor(v) or (istable(v) and v.r) then
			col = v
		elseif isstring(v) then
			local tw = surface.GetTextSize(v)
			if cx + tw > x + w then
				UI.Text(UI.Fit(v, font, x + w - cx), font, cx, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				return
			end
			UI.Text(v, font, cx, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + tw
		end
	end
end
P.DrawParts = drawParts

local function plainText(list)
	local s = {}
	for _, v in ipairs(list) do if isstring(v) then s[#s + 1] = v end end
	return table.concat(s)
end

local function shortModel(m)
	m = tostring(m or "")
	return m:match("([^/]+)%.mdl$") or m
end

-- A window with the model turning slowly (props of prop kill / push lines)
function P.ModelPreview(model)
	local f = UI.Modal(shortModel(model), S(440), S(500))
	local mdl = vgui.Create("DModelPanel", f.body)
	mdl:Dock(FILL)
	mdl:SetModel(model)
	mdl:SetFOV(35)
	local ent = mdl.Entity
	if IsValid(ent) then
		local mn, mx = ent:GetRenderBounds()
		local center = (mn + mx) / 2
		local size = math.max(16, (mx - mn):Length())
		mdl:SetLookAt(center)
		mdl:SetCamPos(center + Vector(size * 1.1, size * 0.4, size * 0.45))
	end
	local yaw = 0
	mdl.LayoutEntity = function(_, e)
		yaw = yaw + FrameTime() * 35
		e:SetAngles(Angle(0, yaw, 0))
	end
	local paintMdl = mdl.Paint
	mdl.Paint = function(s, w, h)
		UI.Rect(0, 0, w, h, Color(14, 11, 17))
		surface.SetDrawColor(142, 98, 255, 16)
		for i = 0, h, S(8) do surface.DrawRect(0, i, w, 1) end
		paintMdl(s, w, h)
		UI.Outline(0, 0, w, h, C.line)
	end
	local path = UI.Label(f.body, model, "Praetor.Mono", C.muted)
	path:Dock(BOTTOM)
	path:DockMargin(0, S(6), 0, 0)
	local copy = UI.Button(f.foot, P.L("log_copy_model"), "ghost", nil, function()
		SetClipboardText(model)
		P.Toast(P.L("copied"), model, "ok", 2)
	end)
	copy:Dock(RIGHT)
	copy:SetWide(S(180))
	return f
end

-- right click on a log line
local function lineMenu(r, list)
	local args = isstring(r.a) and (util.JSONToTable(r.a) or {}) or (r.a or {})
	local m = DermaMenu()
	m:AddOption(P.L("log_copy"), function()
		SetClipboardText(plainText(list))
		P.Toast(P.L("copied"), "", "ok", 2)
	end):SetIcon("icon16/page_copy.png")

	if isstring(args.M) and args.M:find("%.mdl$") then
		local btn = vgui.Create("DButton")
		btn:SetText("")
		btn:SetSize(S(260), S(54))
		local icon = vgui.Create("SpawnIcon", btn)
		icon:SetModel(args.M)
		icon:SetSize(S(46), S(46))
		icon:SetPos(S(4), S(4))
		icon:SetMouseInputEnabled(false)
		btn.Paint = function(s, w, h)
			if s:IsHovered() then UI.Rect(0, 0, w, h, C.hover) end
			UI.Text(UI.Fit(shortModel(args.M), "Praetor.SmallB", w - S(64)), "Praetor.SmallB", S(58), S(9), C.ivory)
			UI.Text(P.L("log_prop_view"), "Praetor.Tiny", S(58), S(30), C.bronzeL)
		end
		btn.DoClick = function()
			CloseDermaMenus()
			P.ModelPreview(args.M)
		end
		m:AddPanel(btn)
	end

	if P.MyHas("view_sheet") then
		local seen = {}
		local function addPly(v)
			if not istable(v) or not v.s or not tostring(v.s):match("^%d+$") or seen[v.s] then return end
			seen[v.s] = true
			m:AddOption(P.L("log_open_sheet", { S = v.n or v.s }), function()
				if IsValid(P.Menu) then P.Menu:SelectTab("users", { sid = v.s }) end
			end):SetIcon("icon16/user.png")
		end
		addPly(args.A)
		if istable(args.T) then
			if args.T.n then addPly(args.T) else for _, x in ipairs(args.T) do addPly(x) end end
		end
	end
	m:Open()
end

P.AddTab("logs", {
	cat = "moderation", icon = "scroll", order = 3,
	can = function() return P.MyHas("logs") end,
	build = function(panel, data)
		if data and isstring(data.cat) then state.cat = data.cat state.page = 0 end
		local bar = UI.Toolbar(panel)
		local opts = {}
		for _, c in ipairs(CATS) do opts[#opts + 1] = { c, P.L("logcat_" .. c) } end
		-- two rows: kind + text + toggles on top, the player filter alone below
		-- (on one row the player box was cut: "Jogador, Steam ID ou link d")
		local bar2 = UI.Toolbar(panel)
		local cat = UI.Tool(bar, UI.Combo(bar, opts, state.cat), S(170))
		local live = UI.Tool(bar, UI.Toggle(bar, P.L("log_live"), nil, state.live), S(124), RIGHT)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("log_search"), state.q), nil, FILL)
		local who = UI.Tool(bar2, UI.PlayerPick(bar2, state.sid), nil, FILL)
		live:SetTooltip(P.L("log_live_tip"))
		local crash = P.MyHas("crash_logs") and UI.Tool(bar, UI.Toggle(bar, P.L("log_crash"), "skull", state.sess ~= nil), S(184), RIGHT) or nil
		if crash then crash:SetTooltip(P.L("log_crash_tip")) end

		-- "before the crash" banner with the list of old sessions
		local banner = vgui.Create("DPanel", panel)
		banner:Dock(TOP)
		banner:SetTall(S(40))
		banner:DockMargin(0, S(6), 0, 0)
		banner.text = ""
		banner.Paint = function(s, w, h)
			UI.Rect(0, 0, w, h, Color(58, 38, 18, 220))
			UI.Rect(0, 0, S(4), h, C.amber)
			UI.Text(UI.Fit(s.text, "Praetor.SmallB", w - s.comboW - S(28)), "Praetor.SmallB", S(14), h / 2, C.amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local sessCombo = UI.Combo(banner, {}, nil)
		sessCombo:Dock(RIGHT)
		sessCombo:SetWide(S(300))
		sessCombo:DockMargin(0, S(4), S(4), S(4))
		banner.comboW = S(300)
		-- small screens: the session list gives room to the text
		banner.PerformLayout = function(s, w)
			s.comboW = math.min(S(300), math.floor(w * 0.42))
			sessCombo:SetWide(s.comboW)
		end
		banner:SetVisible(state.sess ~= nil)
		local sessions = {}

		local tbl = UI.Table(panel, { { P.L("log_time"), 120 }, { P.L("log_cat"), 90 }, { P.L("log_text"), 1 } })
		tbl:Dock(FILL)

		local ask
		local pager = UI.Pager(panel, function(n) state.page = n ask() end)

		local function addRow(r, top)
			local list = parts(r.k, r.a)
			local row = tbl:AddRow({
				{ os.date("%d/%m %H:%M:%S", tonumber(r.t) or 0), C.muted },
				{ P.L("logcat_" .. tostring(r.cat)), CAT_COL[r.cat] or C.text },
				function(x, _, w, h) drawParts(list, x, h / 2, w - S(6), "Praetor.Small") end,
			}, {
				h = S(28),
				onClick = function() SetClipboardText(plainText(list)) P.Toast(P.L("copied"), "", "ok", 2) end,
				onRight = function() lineMenu(r, list) end,
			})
			if top then row:MoveToFront() row:SetZPos(-(tonumber(r.t) or 0)) end
		end

		function ask()
			P.Request("logs_query", { cat = state.cat, q = state.q, sid = state.sid, page = state.page, sess = state.sess })
		end

		local function sessLabel(s)
			local crashed = tonumber(s.ended) == 0
			return os.date("%d/%m %H:%M", tonumber(s.started) or 0) .. " - " .. os.date("%d/%m %H:%M", tonumber(s.last) or 0)
				.. "  " .. tostring(s.map or "") .. (crashed and ("  [" .. P.L("log_crash_tag") .. "]") or "")
		end
		local function updateBanner()
			banner:SetVisible(state.sess ~= nil)
			panel:InvalidateLayout()
			for _, s in ipairs(sessions) do
				if tonumber(s.id) == state.sess then
					local crashed = tonumber(s.ended) == 0
					banner.text = P.L(crashed and "log_crash_on" or "log_session_on", { S = os.date("%d/%m %H:%M:%S", tonumber(s.last) or 0), V = s.map or "" })
				end
			end
			if crash then crash:SetValue(state.sess ~= nil) end
		end
		sessCombo.OnSelect = function(_, _, _, id)
			state.sess = tonumber(id)
			state.page = 0
			updateBanner()
			ask()
		end
		P.On("logs_sessions", function(d)
			if not IsValid(banner) then return end
			sessions = d.rows or {}
			if #sessions == 0 then
				state.sess = nil
				P.Toast(P.L("log_crash"), P.L("log_crash_none"), "info", 4)
				updateBanner()
				return
			end
			local pickId
			for _, s in ipairs(sessions) do
				if tonumber(s.id) == state.sess then pickId = state.sess end
			end
			if not pickId then
				for _, s in ipairs(sessions) do
					if tonumber(s.ended) == 0 then pickId = tonumber(s.id) break end
				end
			end
			pickId = pickId or tonumber(sessions[1].id)
			sessCombo:Clear()
			for _, s in ipairs(sessions) do sessCombo:AddChoice(sessLabel(s), tonumber(s.id), tonumber(s.id) == pickId) end
			state.sess = pickId
			state.page = 0
			updateBanner()
			ask()
		end)
		if crash then
			crash.DoClick = function()
				-- the button shows the state; the click only asks for the change
				if state.sess then
					state.sess = nil
					state.page = 0
					updateBanner()
					ask()
				else
					P.Request("logs_sessions")
				end
			end
		end
		if state.sess then P.Request("logs_sessions") end
		cat.OnSelect = function(_, _, _, d) state.cat = d state.page = 0 ask() end
		search.OnEnter = function(s) state.q = s:GetValue() state.page = 0 ask() end
		who.entry.OnEnter = function() state.sid = who:GetValue() state.page = 0 ask() end
		live.DoClick = function()
			state.live = not state.live
			live:SetValue(state.live)
			P.Request("logs_watch", { on = state.live })
		end

		P.On("logs_query", function(d)
			if not IsValid(tbl) then return end
			tbl:Clear()
			pager:SetPage(d.page or 0, #d.rows > 0)
			if #d.rows == 0 then tbl:Empty(P.L("log_none"), "scroll", P.L("log_none_hint")) return end
			for _, r in ipairs(d.rows) do addRow(r) end
		end)
		P.On("log_live", function(d)
			if not IsValid(tbl) or not state.live or state.page ~= 0 or state.sess then return end
			if state.cat ~= "all" and d.cat ~= state.cat then return end
			if state.q ~= "" or state.sid ~= "" then return end
			-- newest first: rebuild with the new line on top
			tbl.liveRows = tbl.liveRows or {}
			table.insert(tbl.liveRows, 1, { t = d.t, cat = d.cat, k = d.k, a = d.a })
			local canvas = tbl.scroll:GetCanvas()
			local list = parts(d.k, d.a)
			local row = tbl:AddRow({
				{ os.date("%d/%m %H:%M:%S", d.t), C.muted },
				{ P.L("logcat_" .. tostring(d.cat)), CAT_COL[d.cat] or C.text },
				function(x, _, w, h) drawParts(list, x, h / 2, w - S(6), "Praetor.Small") end,
			}, { h = S(28), accent = C.bronze, onRight = function() lineMenu(d, list) end })
			-- move the new row to the top of the list
			local children = canvas:GetChildren()
			for i, ch in ipairs(children) do ch:SetZPos(i) end
			row:SetZPos(-1)
			canvas:InvalidateLayout()
		end)
		P.Request("logs_watch", { on = state.live })
		ask()
	end,
})
