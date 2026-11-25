-- Praetor: the report window players open with !report, and what they see
-- while the staff handles it.
--  * "New report": who (the people you just fought or talked with come first),
--    what happened (category tiles), details, and an optional picture of your
--    own screen from the moment you opened the window;
--  * "My reports": status, queue position, the conversation with the staff,
--    cancel, and "did it help?" when it is closed;
--  * a small card on the side of the screen follows the open report live.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local CATS = {
	{ "rdm", "skull" }, { "cheating", "target" }, { "prop_abuse", "box" }, { "insult", "bubble_no" },
	{ "exploit", "bolt" }, { "rules", "scroll" }, { "help", "headset" }, { "other", "info" },
}
P.ReportCatIcon = {}
for _, c in ipairs(CATS) do P.ReportCatIcon[c[1]] = c[2] end

local STATUS_COL = { open = C.amber, claimed = C.sky or C.bronze, closed = C.laurel }

local function ago(secs)
	secs = math.max(0, math.floor(tonumber(secs) or 0))
	if secs < 60 then return P.L("rp_ago_now") end
	if secs < 3600 then return P.L("rp_ago_min", { V = math.floor(secs / 60) }) end
	if secs < 86400 then return P.L("rp_ago_hour", { V = math.floor(secs / 3600) }) end
	return P.L("rp_ago_day", { V = math.floor(secs / 86400) })
end
P.ReportAgo = ago

local mine = {}          -- my last reports (from the server)
local myState            -- live state of my open report
local unread = {}        -- report id -> true (new staff message)
local win                -- the open window

-- ------------------------------------------------------------------ small helpers

local function sectionTitle(parent, text, sub)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(S(sub and 40 or 26))
	p:DockMargin(0, S(10), 0, S(6))
	p.Paint = function(_, w, h)
		UI.Text(text, "Praetor.BodyB", 0, S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if sub then UI.Text(UI.Fit(sub, "Praetor.Tiny", w), "Praetor.Tiny", 0, S(29), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	return p
end

-- ------------------------------------------------------------------ new report

local function buildNew(body, preset, shotData, onSent)
	local sc = UI.Scroll(body)
	sc:Dock(FILL)
	local state = { tsid = nil, cat = nil, shot = shotData ~= nil }

	if preset and preset ~= "" then
		local pl = UI.ResolvePlayer(preset)
		if IsValid(pl) and pl ~= LocalPlayer() and not pl:IsBot() then state.tsid = pl:SteamID64() end
	end

	-- who
	sectionTitle(sc, P.L("rp_who"), P.L("rp_who_d"))
	local grid = vgui.Create("DIconLayout", sc)
	grid:Dock(TOP)
	grid:SetSpaceX(S(6))
	grid:SetSpaceY(S(6))
	local picker
	local cards = {}

	local function card(sid, why, agoSecs)
		local b = grid:Add("DButton")
		b:SetText("")
		b:SetSize(S(186), S(52))
		b.sid = sid
		b.DoClick = function()
			state.tsid = sid
			if IsValid(picker) then picker:SetValue(sid or "") end
			UI.Sound("click")
		end
		b.Paint = function(s, w, h)
			local on = state.tsid == sid
			UI.Round(0, 0, w, h, S(8), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 40) or (s:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
			if sid then
				local p = player.GetBySteamID64(sid)
				UI.DrawAvatar(sid, p, S(8), S(9), S(34), 255, on and C.bronze or C.line)
				UI.Text(UI.Fit(IsValid(p) and p:Nick() or "?", "Praetor.SmallB", w - S(56)), "Praetor.SmallB", S(50), S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if why then
					UI.Text(UI.Fit(P.L("rp_why_" .. why) .. " · " .. ago(agoSecs), "Praetor.Tiny", w - S(56)), "Praetor.Tiny", S(50), S(35), why == "hurt_you" and C.crimsonL or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
			else
				UI.Icon("headset", S(17), h / 2 - 8, 16, on and C.bronzeL or C.muted)
				UI.Text(P.L("rp_nobody"), "Praetor.SmallB", S(50), S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(P.L("rp_nobody_d"), "Praetor.Tiny", S(50), S(35), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
		cards[#cards + 1] = b
		return b
	end
	card(nil)
	P.On("report_people", function(d)
		if not IsValid(grid) then return end
		for _, e in ipairs(istable(d.list) and d.list or {}) do card(e.sid, e.why, e.ago) end
		grid:InvalidateLayout(true)
		sc:InvalidateLayout()
	end)
	P.Request("report_people")

	local other = vgui.Create("DPanel", sc)
	other:Dock(TOP)
	other:SetTall(S(20))
	other:DockMargin(0, S(8), 0, S(3))
	other.Paint = function(_, w, h) UI.Text(P.L("rp_other_player"), "Praetor.Tiny", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	picker = UI.PlayerPick(sc, state.tsid or "", function()
		local p = picker:GetPlayer()
		state.tsid = (IsValid(p) and p ~= LocalPlayer() and not p:IsBot()) and p:SteamID64() or nil
	end, { humans = true, noSelf = true })
	picker:Dock(TOP)

	-- what
	sectionTitle(sc, P.L("rp_what"))
	local cgrid = vgui.Create("DIconLayout", sc)
	cgrid:Dock(TOP)
	cgrid:SetSpaceX(S(6))
	cgrid:SetSpaceY(S(6))
	for _, c in ipairs(CATS) do
		local id, icon = c[1], c[2]
		local b = cgrid:Add("DButton")
		b:SetText("")
		b:SetSize(S(139), S(58))
		b.DoClick = function() state.cat = id UI.Sound("click") end
		b.Paint = function(s, w, h)
			local on = state.cat == id
			local col = id == "cheating" and C.crimsonL or (id == "help" and C.laurel or C.bronzeL)
			UI.Round(0, 0, w, h, S(8), on and Color(col.r, col.g, col.b, 36) or (s:IsHovered() and C.hover or C.panel2), on and col or C.line)
			UI.Icon(icon, w / 2 - 8, S(12), 16, on and col or C.muted)
			UI.Text(UI.Fit(P.L("reason_" .. id), "Praetor.Tiny", w - S(10)), "Praetor.Tiny", w / 2, S(42), on and C.ivory or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- details
	sectionTitle(sc, P.L("rp_details"), P.L("rp_details_d"))
	local text = UI.Entry(sc, P.L("report_details_hint"), "")
	text:SetMultiline(true)
	text:SetTall(S(110))
	text:Dock(TOP)

	-- picture of my screen
	if shotData then
		local path = "praetor_shots/self_" .. math.floor(SysTime() * 1000) .. ".jpg"
		file.CreateDir("praetor_shots")
		file.Write(path, shotData)
		local mat = Material("../data/" .. path, "smooth")
		local row = vgui.Create("DButton", sc)
		row:SetText("")
		row:Dock(TOP)
		row:SetTall(S(84))
		row:DockMargin(0, S(10), 0, 0)
		row.anim = 1
		row.DoClick = function() state.shot = not state.shot UI.Sound("click") end
		row.Paint = function(s, w, h)
			UI.Round(0, 0, w, h, S(8), s:IsHovered() and C.hover or C.panel2, state.shot and C.bronze or C.line)
			local tw = S(112)
			if mat and not mat:IsError() then
				surface.SetMaterial(mat)
				surface.SetDrawColor(255, 255, 255, state.shot and 255 or 70)
				surface.DrawTexturedRect(S(8), S(8), tw, h - S(16))
			end
			UI.Text(P.L("rp_shot"), "Praetor.SmallB", tw + S(20), S(26), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(UI.Fit(P.L("rp_shot_d"), "Praetor.Tiny", w - tw - S(90)), "Praetor.Tiny", tw + S(20), S(46), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			-- the same switch as the settings
			s.anim = UI.Lerp(s.anim, state.shot and 1 or 0, 16)
			local sw, sh = S(44), S(22)
			local sx, sy = w - sw - S(14), math.floor((h - sh) / 2)
			UI.Round(sx, sy, sw, sh, sh / 2, P.LerpColor(s.anim, C.panel3, C.bronze))
			UI.Round(sx + 3 + (sw - sh) * s.anim, sy + 3, sh - 6, sh - 6, (sh - 6) / 2, P.LerpColor(s.anim, C.muted, color_white))
			return true
		end
	end

	local note = vgui.Create("DPanel", sc)
	note:Dock(TOP)
	note:SetTall(S(26))
	note:DockMargin(0, S(8), 0, 0)
	note.Paint = function(_, w, h)
		UI.Icon("info", 0, h / 2 - 8, 16, C.dim)
		UI.Text(UI.Fit(P.L("rp_auto_note"), "Praetor.Tiny", w - S(24)), "Praetor.Tiny", S(22), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	return function()
		if not state.cat then P.Toast(P.L("report_title"), P.L("err_report_cat"), "warn") return false end
		local t = P.Trim(text:GetValue() or "")
		if not state.tsid and state.cat ~= "help" and state.cat ~= "other" and t == "" then P.Toast(P.L("report_title"), P.L("err_report_who"), "warn") return false end
		P.PendingShot = state.shot and shotData or nil
		P.Request("report_send", { tsid = state.tsid, cat = state.cat, text = t, shot = state.shot and shotData ~= nil or nil })
		onSent()
		return true
	end
end

-- ------------------------------------------------------------------ my reports

local function bubble(parent, m)
	local isStaff = tonumber(m.staff or m.st) == 1
	local lines = UI.Wrap(tostring(m.text or m.m or ""), "Praetor.Small", S(360))
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(S(26) + #lines * S(17))
	p:DockMargin(0, 0, 0, S(5))
	p.Paint = function(_, w, h)
		local bw = math.min(w - S(40), S(390))
		local x = isStaff and 0 or (w - bw)
		local col = isStaff and Color(C.bronze.r, C.bronze.g, C.bronze.b, 30) or C.panel2
		UI.Round(x, 0, bw, h, S(8), col, isStaff and Color(C.bronze.r, C.bronze.g, C.bronze.b, 90) or C.line)
		UI.Text((isStaff and "★ " or "") .. tostring(m.name or m.n or "?") .. "  ·  " .. os.date("%H:%M", tonumber(m.t) or 0), "Praetor.Tiny", x + S(10), S(12), isStaff and C.bronzeL or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		for i, l in ipairs(lines) do UI.Text(l, "Praetor.Small", x + S(10), S(20) + (i - 1) * S(17), C.ivory) end
	end
	return p
end

local function buildMine(body)
	local sc = UI.Scroll(body)
	sc:Dock(FILL)
	local function fill()
		if not IsValid(sc) then return end
		sc:Clear()
		if #mine == 0 then
			local e = vgui.Create("DPanel", sc)
			e:Dock(TOP)
			e:SetTall(S(120))
			e.Paint = function(_, w, h)
				UI.Icon("flag", w / 2 - 16, h / 2 - 34, 32, C.dim)
				UI.Text(P.L("rp_mine_none"), "Praetor.BodyB", w / 2, h / 2 + S(12), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return
		end
		for _, r in ipairs(mine) do
			unread[r.id] = nil
			local st = r.status
			local col = STATUS_COL[st] or C.muted
			local head = vgui.Create("DPanel", sc)
			head:Dock(TOP)
			head:SetTall(S(58))
			head:DockMargin(0, S(6), S(4), S(4))
			head.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(8), C.panel, col)
				UI.Round(1, S(8), S(3), h - S(16), S(1), col)
				UI.Icon(P.ReportCatIcon[r.cat or "other"] or "flag", S(14), S(12), 16, col)
				local title = "#" .. r.id .. "  " .. P.L("reason_" .. (r.cat or "other"), nil, r.reason or "") .. (((r.tname or "") ~= "" and r.tname ~= "NULL") and ("  ·  " .. r.tname) or "")
				UI.Text(UI.Fit(title, "Praetor.BodyB", w - S(200)), "Praetor.BodyB", S(38), S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local sub
				if st == "open" then sub = P.L("rp_st_queue", { V = r.pos or "?" })
				elseif st == "claimed" then sub = P.L("rp_st_claimed", { S = r.staff_name or "?" })
				else sub = P.L("rp_out_" .. (r.outcome ~= "NULL" and r.outcome or "solved"), nil, P.L("rep_st_closed")) .. (((r.staff_name or "") ~= "" and r.staff_name ~= "NULL") and ("  ·  " .. r.staff_name) or "") end
				UI.Text(UI.Fit(sub, "Praetor.Small", w - S(200)), "Praetor.Small", S(38), S(40), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(ago(os.time() - (tonumber(r.created) or 0)), "Praetor.Tiny", w - S(12), S(20), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			if st ~= "closed" then
				local cancel = UI.Button(head, P.L("rp_cancel"), "ghost", nil, function()
					UI.Confirm(P.L("rp_cancel"), P.L("rp_cancel_q"), function() P.Request("report_cancel", { id = r.id }) timer.Simple(0.4, function() P.Request("report_mine") end) end)
				end)
				cancel:SetSize(S(110), S(26))
				head.PerformLayout = function(s, w, h) cancel:SetPos(w - S(122), h - S(32)) end
			end
			if r.note and r.note ~= "" then
				local n = vgui.Create("DPanel", sc)
				local lines = UI.Wrap(r.note, "Praetor.Small", S(520))
				n:Dock(TOP)
				n:SetTall(S(24) + #lines * S(17))
				n:DockMargin(S(12), 0, S(4), S(4))
				n.Paint = function(_, w, h)
					UI.Text(P.L("rp_staff_note"), "Praetor.Tiny", 0, S(10), C.laurel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					for i, l in ipairs(lines) do UI.Text(l, "Praetor.Small", 0, S(18) + (i - 1) * S(17), C.text) end
				end
			end
			local thread = vgui.Create("DPanel", sc)
			thread:Dock(TOP)
			thread:DockMargin(S(12), 0, S(4), 0)
			thread.Paint = nil
			local hh = 0
			for _, m in ipairs(r.msgs or {}) do
				local b = bubble(thread, m)
				hh = hh + b:GetTall() + S(5)
			end
			thread:SetTall(hh)
			if st ~= "closed" then
				local say = vgui.Create("DPanel", sc)
				say:Dock(TOP)
				say:SetTall(S(32))
				say:DockMargin(S(12), S(2), S(4), S(6))
				say.Paint = nil
				local go = UI.Button(say, P.L("rp_send_msg"), "primary", "send")
				go:Dock(RIGHT)
				go:SetWide(S(100))
				local e = UI.Entry(say, P.L("rp_msg_ph"), "")
				e:Dock(FILL)
				e:DockMargin(0, 0, S(6), 0)
				local function send()
					local t = P.Trim(e:GetValue() or "")
					if t == "" then return end
					P.Request("report_say", { id = r.id, m = t })
					r.msgs = r.msgs or {}
					r.msgs[#r.msgs + 1] = { name = LocalPlayer():Nick(), staff = 0, t = os.time(), text = t }
					fill()
				end
				go.DoClick = send
				e.OnEnter = send
			elseif (tonumber(r.rating) or 0) == 0 and r.outcome ~= "cancelled" then
				local rate = vgui.Create("DPanel", sc)
				rate:Dock(TOP)
				rate:SetTall(S(38))
				rate:DockMargin(S(12), S(2), S(4), S(8))
				rate.Paint = function(_, w, h) UI.Text(P.L("rp_helped_q"), "Praetor.SmallB", 0, h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
				local no = UI.Button(rate, P.L("rp_helped_no"), "ghost", "cross", function() P.Request("report_rate", { id = r.id, good = false }) r.rating = -1 fill() end)
				no:Dock(RIGHT)
				no:SetWide(S(110))
				local yes = UI.Button(rate, P.L("rp_helped_yes"), "primary", "check", function() P.Request("report_rate", { id = r.id, good = true }) r.rating = 1 fill() end)
				yes:Dock(RIGHT)
				yes:SetWide(S(110))
				yes:DockMargin(0, 0, S(6), 0)
			end
		end
	end
	P.On("report_mine", function(d)
		mine = istable(d.list) and d.list or {}
		fill()
	end)
	fill()
	P.Request("report_mine")
	return fill
end

-- ------------------------------------------------------------------ window

local function openWindow(preset, shotData, startMine)
	if IsValid(win) then win:Close() end
	local m = UI.Modal(P.L("report_title"), S(640), math.min(S(640), ScrH() - S(40)))
	win = m
	local tabs = vgui.Create("DPanel", m.body)
	tabs:Dock(TOP)
	tabs:SetTall(S(34))
	tabs:DockMargin(0, 0, 0, S(6))
	tabs.Paint = nil
	local page = vgui.Create("DPanel", m.body)
	page:Dock(FILL)
	page.Paint = nil
	local current
	local tNew, tMine
	local sendBtn
	local submit

	local function show(which)
		current = which
		page:Clear()
		if IsValid(sendBtn) then sendBtn:SetVisible(which == "new") end
		if which == "new" then
			submit = buildNew(page, preset, shotData, function() show("mine") end)
		else
			buildMine(page)
		end
		if IsValid(tNew) then tNew:Setup(tNew.label, which == "new" and "active" or "ghost", tNew.icon) end
		if IsValid(tMine) then tMine:Setup(tMine.label, which == "mine" and "active" or "ghost", tMine.icon) end
	end
	tNew = UI.Button(tabs, P.L("rp_tab_new"), "active", "flag", function() show("new") end)
	tNew:Dock(LEFT)
	tNew:SetWide(S(170))
	tMine = UI.Button(tabs, P.L("rp_tab_mine"), "ghost", "scroll", function() show("mine") end)
	tMine:Dock(LEFT)
	tMine:SetWide(S(190))
	tMine:DockMargin(S(6), 0, 0, 0)
	tMine.PaintOver = function(s, w, h)
		if next(unread) then UI.Round(w - S(12), S(6), S(8), S(8), S(4), C.crimsonL) end
	end

	sendBtn = UI.Button(m.foot, P.L("report_send"), "primary", "flag", function() if submit then submit() end end)
	sendBtn:Dock(RIGHT)
	sendBtn:SetWide(S(170))
	local close = UI.Button(m.foot, P.L("ui_close"), "ghost", nil, function() m:Close() end)
	close:Dock(RIGHT)
	close:SetWide(S(110))
	close:DockMargin(0, 0, S(8), 0)
	show(startMine and "mine" or "new")
	P.ReportWindowShow = function(which) if IsValid(m) then show(which) end end
	return m
end

function P.OpenReport(preset)
	-- the picture of the game is taken before the window covers it
	local wantShot = P.Setting("report_shot") ~= false and P.CaptureFrame ~= nil
	-- an unrated closed report or a staff answer: open on "My reports"
	local startMine = next(unread) ~= nil or (myState and myState.st ~= "closed" and (preset == nil or preset == ""))
	if wantShot then
		P.CaptureFrame(function(data) openWindow(preset, data, startMine) end, 65)
	else
		openWindow(preset, nil, startMine)
	end
end

concommand.Add("praetor_report", function() P.OpenReport() end)

-- ------------------------------------------------------------------ live

P.On("report_shot_go", function(d)
	local data = P.PendingShot
	P.PendingShot = nil
	if data and P.SendShot and tonumber(d.job) then P.SendShot(d.job, data) end
end)

P.On("report_state", function(d)
	myState = d
	if IsValid(win) then P.Request("report_mine") end
end)

-- one op for both sides: staff answers go to the reporter, reporter answers to the desk
P.On("report_msg", function(d)
	if d.you then
		unread[d.rid] = true
		UI.Sound("notify")
		chat.AddText(C.bronzeL, "[" .. P.L("rp_tag", { V = d.rid }) .. "] ", C.ivory, d.n .. ": ", C.text, d.m, C.dim, "  (" .. P.L("rp_reply_hint") .. ")")
		P.Toast(P.L("rp_tag", { V = d.rid }), d.n .. ": " .. d.m, "report", 8)
		if IsValid(win) then P.Request("report_mine") end
	else
		-- the desk shows it in the thread; a reporter's answer also rings when the desk is closed
		hook.Run("Praetor.ReportMsg", d)
		if not d.st and not (IsValid(P.Menu) and P.Menu:IsVisible()) then
			UI.Sound("chat")
			P.Toast(P.L("rp_tag", { V = d.rid }), P.L("rp_reporter_said", { S = d.n }) .. " " .. d.m, "report", 7)
		end
	end
end)

P.On("report_done", function(d)
	myState = nil
	unread[d.id or 0] = true
	UI.Sound("ok")
	P.Toast(P.L("report_done_title"), P.L("rp_done_text", { S = d.by, V = P.L("rp_out_" .. tostring(d.out or "solved")) }) .. ((d.v and d.v ~= "") and ("\n" .. d.v) or ""), "ok", 12)
	chat.AddText(C.laurel, "[" .. P.L("rp_tag", { V = d.id or "?" }) .. "] ", C.ivory, P.L("rp_done_text", { S = d.by, V = P.L("rp_out_" .. tostring(d.out or "solved")) }), C.dim, "  (" .. P.L("rp_rate_hint") .. ")")
	if IsValid(win) then P.Request("report_mine") end
end)

-- the card on the side of the screen
hook.Add("HUDPaint", "Praetor.ReportCard", function()
	local s = myState
	if not s or s.st == "closed" then return end
	if IsValid(P.Menu) and P.Menu:IsVisible() then return end
	local w, h = S(230), S(46)
	local x, y = ScrW() - w - S(16), math.floor(ScrH() * 0.30)
	local col = STATUS_COL[s.st] or C.amber
	UI.Round(x + S(4), y + S(4), w, h, math.max(S(8), S(12)), Color(C.ink.r, C.ink.g, C.ink.b, (220) * 0.8)) UI.Round(x, y, w, h, math.max(S(8), S(12)), Color(C.panel.r, C.panel.g, C.panel.b, 220), Color(col.r, col.g, col.b, 160))
	UI.Round(x + 1, y + S(8), S(3), h - S(16), S(1), col)
	UI.Icon("flag", x + S(12), y + S(15) - 8, 16, col)
	UI.Text(P.L("rp_tag", { V = s.id }) .. (s.t and s.t ~= "" and ("  ·  " .. s.t) or ""), "Praetor.SmallB", x + S(34), y + S(15), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local sub = s.st == "open" and P.L("rp_st_queue", { V = s.pos or "?" }) or P.L("rp_st_claimed", { S = s.by or "?" })
	UI.Text(UI.Fit(sub, "Praetor.Tiny", w - S(46)), "Praetor.Tiny", x + S(34), y + S(32), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if unread[s.id] then UI.Round(x + w - S(14), y + S(8), S(8), S(8), S(4), C.crimsonL) end
end)
