-- Praetor menu: the report desk (or a pointer to Blackbox when it handles reports).
--  * left: the queue, highest priority first. Each card shows the category,
--    who reported whom, how long it waits, who took it, how many open reports
--    are against the same player, and if a picture of the screen came with it;
--  * right: the report. Both players (online or not), what happened, what the
--    server saw (damage between them, their last chat lines, past reports),
--    the picture, the conversation with the reporter and every action;
--  * closing asks for an outcome (punished, warned, no proof, false report,
--    solved) and a note the reporter reads.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local view = { mode = "open", sel = nil }
local OUTCOMES = { "punished", "warned", "noproof", "false_report", "solved" }
local OUT_COL = { punished = C.crimsonL, warned = C.amber, noproof = C.muted, false_report = C.crimsonL, solved = C.laurel, cancelled = C.dim }
local MACROS = { "rp_macro_onway", "rp_macro_more", "rp_macro_proof", "rp_macro_handled" }

local function statusCol(s)
	if s == "open" then return C.crimsonL end
	if s == "claimed" then return C.amber end
	return C.laurel
end

local function prioCol(p)
	p = tonumber(p) or 0
	if p >= 40 then return C.crimsonL end
	if p >= 20 then return C.amber end
	return C.bronze
end

local function has(v) return v ~= nil and v ~= "" and v ~= "NULL" end
local function catOf(r) return has(r.cat) and r.cat or "other" end
local function catName(r) return has(r.cat) and P.L("reason_" .. r.cat) or tostring(r.reason or "?") end
local function ago(t) return P.ReportAgo and P.ReportAgo(os.time() - (tonumber(t) or 0)) or P.Date(tonumber(t)) end

-- ------------------------------------------------------------------ close with an outcome

local function closeForm(r)
	local m = UI.Modal(P.L("rp_close_title", { V = r.id }), S(520), S(360))
	local pick = nil
	local grid = vgui.Create("DIconLayout", m.body)
	grid:Dock(TOP)
	grid:SetTall(S(80))
	grid:SetSpaceX(S(6))
	grid:SetSpaceY(S(6))
	for _, o in ipairs(OUTCOMES) do
		local b = grid:Add("DButton")
		b:SetText("")
		b:SetSize(S(158), S(36))
		b.DoClick = function() pick = o UI.Sound("click") end
		b.Paint = function(s, w, h)
			local on = pick == o
			local col = OUT_COL[o]
			UI.Round(0, 0, w, h, S(6), on and Color(col.r, col.g, col.b, 40) or (s:IsHovered() and C.hover or C.panel2), on and col or C.line)
			UI.Text(UI.Fit(P.L("rp_out_" .. o), "Praetor.SmallB", w - S(10)), "Praetor.SmallB", w / 2, h / 2, on and C.ivory or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	local lbl = vgui.Create("DPanel", m.body)
	lbl:Dock(TOP)
	lbl:SetTall(S(24))
	lbl:DockMargin(0, S(10), 0, S(4))
	lbl.Paint = function(_, w, h) UI.Text(P.L("rp_note_reporter"), "Praetor.Tiny", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	local note = UI.Entry(m.body, P.L("rep_verdict_hint"), "")
	note:SetMultiline(true)
	note:Dock(FILL)
	local go = UI.Button(m.foot, P.L("rep_close"), "primary", "laurel", function()
		if not pick then P.Toast(P.L("rep_close"), P.L("rp_pick_outcome"), "warn") return end
		P.Request("report_close", { id = r.id, outcome = pick, verdict = P.Trim(note:GetValue() or "") })
		m:Close()
	end)
	go:Dock(RIGHT)
	go:SetWide(S(170))
	local cancel = UI.Button(m.foot, P.L("ui_cancel"), "ghost", nil, function() m:Close() end)
	cancel:Dock(RIGHT)
	cancel:SetWide(S(110))
	cancel:DockMargin(0, 0, S(8), 0)
end

-- ------------------------------------------------------------------ detail

local function msgBubble(parent, m, maxW)
	local isStaff = tonumber(m.staff or m.st) == 1
	local lines = UI.Wrap(tostring(m.text or m.m or ""), "Praetor.Small", maxW - S(24))
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(S(26) + #lines * S(17))
	p:DockMargin(0, 0, 0, S(5))
	p.Paint = function(_, w, h)
		local bw = math.min(w - S(30), maxW)
		local x = isStaff and (w - bw) or 0
		UI.Round(x, 0, bw, h, S(8), isStaff and Color(C.bronze.r, C.bronze.g, C.bronze.b, 30) or C.panel2, isStaff and Color(C.bronze.r, C.bronze.g, C.bronze.b, 90) or C.line)
		UI.Text((isStaff and "★ " or "") .. tostring(m.name or m.n or "?") .. "  ·  " .. os.date("%H:%M", tonumber(m.t) or 0), "Praetor.Tiny", x + S(10), S(12), isStaff and C.bronzeL or C.sky or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		for i, l in ipairs(lines) do UI.Text(l, "Praetor.Small", x + S(10), S(20) + (i - 1) * S(17), C.ivory) end
	end
	return p
end

local function sectionHead(parent, text, icon)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(S(26))
	p:DockMargin(0, S(12), S(6), S(4))
	p.Paint = function(_, w, h)
		if icon then UI.Icon(icon, 0, h / 2 - 8, 16, C.bronze) end
		UI.Text(text, "Praetor.SmallB", icon and S(22) or 0, h / 2, C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Rule(icon and S(22) or 0, h - 1, w - (icon and S(22) or 0), C.line)
	end
	return p
end

local function personCard(parent, label, sid, name, online, col)
	local p = vgui.Create("DPanel", parent)
	p.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(8), C.panel2, C.line)
		UI.Text(label, "Praetor.Tiny", S(10), S(12), col or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if not has(sid) then
			UI.Text(P.L("rp_nobody"), "Praetor.SmallB", S(10), S(38), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return
		end
		local pl = P.BySID(sid)
		UI.DrawAvatar(sid, IsValid(pl) and pl or nil, S(10), S(24), S(34), 255, C.line)
		UI.Text(UI.Fit(IsValid(pl) and pl:Nick() or tostring(name or "?"), "Praetor.SmallB", w - S(60)), "Praetor.SmallB", S(52), S(33), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local on = IsValid(pl)
		UI.Round(S(52), S(47), S(7), S(7), S(3), on and C.laurel or C.dim)
		UI.Text((on and P.L("rp_online") or P.L("rp_offline")) .. "  ·  " .. P.SID32(sid), "Praetor.Tiny", S(64), S(50), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return p
end

local detailId

local function buildDetail(pane, r)
	pane:Clear()
	detailId = r.id
	local tgt = has(r.tsid) and P.BySID(r.tsid) or nil
	local rep = P.BySID(r.sid)
	local closed = r.status == "closed"
	local mine = r.staff_sid == LocalPlayer():SteamID64()

	-- header
	local head = vgui.Create("DPanel", pane)
	head:Dock(TOP)
	head:SetTall(S(54))
	head.Paint = function(_, w, h)
		local col = closed and (OUT_COL[r.outcome] or C.laurel) or prioCol(r.prio)
		UI.Round(0, 0, w, h, S(8), C.panel, C.line)
		UI.Round(1, S(8), S(3), h - S(16), S(1), col)
		UI.Icon(P.ReportCatIcon and P.ReportCatIcon[catOf(r)] or "flag", S(14), h / 2 - 8, 16, col)
		UI.Text("#" .. r.id .. "  " .. catName(r), "Praetor.BodyB", S(38), S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local sub
		if closed then
			sub = P.L("rp_out_" .. (has(r.outcome) and r.outcome or "solved")) .. (has(r.staff_name) and ("  ·  " .. r.staff_name) or "")
		elseif r.status == "claimed" then
			sub = P.L("rp_with", { S = has(r.staff_name) and r.staff_name or "?" })
		else
			sub = P.L("rp_waiting", { V = ago(r.created) })
		end
		UI.Text(UI.Fit(sub, "Praetor.Small", w - S(180)), "Praetor.Small", S(38), S(37), closed and (OUT_COL[r.outcome] or C.laurel) or statusCol(r.status), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.Date(tonumber(r.created)), "Praetor.Tiny", w - S(12), S(18), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		if not closed then UI.Text(P.L("rp_prio", { V = r.prio }), "Praetor.Tiny", w - S(12), S(37), prioCol(r.prio), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
	end

	-- buttons (claim / close) under the header
	local foot = vgui.Create("DPanel", pane)
	foot:Dock(BOTTOM)
	foot:SetTall(S(36))
	foot:DockMargin(0, S(8), 0, 0)
	foot.Paint = nil
	if not closed then
		local closeB = UI.Button(foot, P.L("rep_close"), "primary", "laurel", function() closeForm(r) end)
		closeB:Dock(RIGHT)
		closeB:SetWide(S(150))
		if r.status == "open" then
			local claim = UI.Button(foot, P.L("rep_claim"), "active", "hand", function() P.Request("report_claim", { id = r.id }) end)
			claim:Dock(RIGHT)
			claim:SetWide(S(140))
			claim:DockMargin(0, 0, S(6), 0)
		elseif mine then
			local drop = UI.Button(foot, P.L("rp_drop"), "ghost", "undo", function() P.Request("report_claim", { id = r.id, drop = true }) end)
			drop:Dock(RIGHT)
			drop:SetWide(S(140))
			drop:DockMargin(0, 0, S(6), 0)
		else
			local take = UI.Button(foot, P.L("rp_take"), "ghost", "hand", function()
				UI.Confirm(P.L("rp_take"), P.L("rp_take_q", { S = has(r.staff_name) and r.staff_name or "?" }), function() P.Request("report_claim", { id = r.id, take = true }) end)
			end)
			take:Dock(RIGHT)
			take:SetWide(S(140))
			take:DockMargin(0, 0, S(6), 0)
		end
	end

	local sc = UI.Scroll(pane)
	sc:Dock(FILL)
	sc:DockMargin(0, S(8), 0, 0)

	-- the two players
	local people = vgui.Create("DPanel", sc)
	people:Dock(TOP)
	people:SetTall(S(64))
	people:DockMargin(0, 0, S(6), 0)
	people.Paint = nil
	local a = personCard(people, P.L("rep_from"), r.sid, r.name, r.ron, C.sky)
	local b = personCard(people, P.L("rep_against"), r.tsid, r.tname, r.ton, C.crimsonL)
	people.PerformLayout = function(_, w, h)
		local half = math.floor((w - S(8)) / 2)
		a:SetPos(0, 0) a:SetSize(half, h)
		b:SetPos(half + S(8), 0) b:SetSize(w - half - S(8), h)
	end

	-- what the reporter wrote
	sectionHead(sc, P.L("rep_text"), "pen")
	local txt = has(r.text) and r.text or P.L("rep_no_text")
	local tl = UI.Label(sc, txt, "Praetor.Body", has(r.text) and C.ivory or C.dim)
	tl:SetWrap(true)
	tl:SetAutoStretchVertical(true)
	tl:Dock(TOP)
	tl:DockMargin(0, 0, S(6), 0)

	-- the picture of the reporter's screen
	if (tonumber(r.shot) or 0) > 0 then
		local shot = UI.Button(sc, P.L("rp_open_shot"), "active", "image", function() P.Request("sg_get", { id = r.shot }) end)
		shot:Dock(TOP)
		shot:SetTall(S(32))
		shot:DockMargin(0, S(8), S(6), 0)
	end

	-- what the server saw
	local ctx = istable(r.ctx) and r.ctx or {}
	local facts = {}
	if has(r.tsid) then
		facts[#facts + 1] = { P.L("rp_ctx_before", { V = ctx.before and math.max(0, ctx.before - 1) or "?" }), (ctx.before or 0) > 1 and C.amber or C.muted }
		facts[#facts + 1] = { P.L("rp_ctx_punished", { V = ctx.punished or 0 }), (ctx.punished or 0) > 0 and C.crimsonL or C.muted }
	end
	if (ctx.falses or 0) > 0 then facts[#facts + 1] = { P.L("rp_ctx_falses", { V = ctx.falses }), C.amber } end
	if ctx.dist then facts[#facts + 1] = { P.L("rp_ctx_dist", { V = ctx.dist }), C.muted } end
	if #facts > 0 or istable(ctx.dmg) or istable(ctx.chat) then
		sectionHead(sc, P.L("rp_ctx"), "eye")
		if #facts > 0 then
			local chips = vgui.Create("DIconLayout", sc)
			chips:Dock(TOP)
			chips:SetSpaceX(S(6))
			chips:SetSpaceY(S(6))
			chips:DockMargin(0, 0, S(6), S(4))
			for _, f in ipairs(facts) do
				local c = chips:Add("DPanel")
				surface.SetFont("Praetor.Tiny")
				local tw = surface.GetTextSize(f[1])
				c:SetSize(tw + S(18), S(22))
				c.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, h / 2, Color(f[2].r, f[2].g, f[2].b, 22), Color(f[2].r, f[2].g, f[2].b, 90))
					UI.Text(f[1], "Praetor.Tiny", w / 2, h / 2, f[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
		local function line(t, who, text, col)
			local l = vgui.Create("DPanel", sc)
			l:Dock(TOP)
			l:SetTall(S(19))
			l:DockMargin(0, 0, S(6), 0)
			l.Paint = function(_, w, h)
				UI.Text(os.date("%H:%M:%S", tonumber(t) or 0), "Praetor.Mono", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(who, "Praetor.SmallB", S(130)), "Praetor.SmallB", S(74), h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(text, "Praetor.Small", w - S(214)), "Praetor.Small", S(210), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
		local function nameOf(sid) return sid == r.sid and r.name or (sid == r.tsid and r.tname or "?") end
		local function colOf(sid) return sid == r.sid and (C.sky or C.text) or C.crimsonL end
		if istable(ctx.dmg) and #ctx.dmg > 0 then
			local sub = vgui.Create("DPanel", sc)
			sub:Dock(TOP) sub:SetTall(S(20)) sub.Paint = function(_, w, h) UI.Text(P.L("rep_damage"), "Praetor.Tiny", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			for i = #ctx.dmg, 1, -1 do
				local d = ctx.dmg[i]
				line(d.t, nameOf(d.a), "> " .. nameOf(d.v) .. "   " .. tostring(d.d or d.dmg or "?") .. "  (" .. tostring(d.w or "?") .. ")", colOf(d.a))
			end
		end
		if istable(ctx.chat) and #ctx.chat > 0 then
			local sub = vgui.Create("DPanel", sc)
			sub:Dock(TOP) sub:SetTall(S(24)) sub.Paint = function(_, w, h) UI.Text(P.L("rp_ctx_chat"), "Praetor.Tiny", 0, h - S(8), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			for i = #ctx.chat, 1, -1 do
				local c = ctx.chat[i]
				line(c.t, c.n or nameOf(c.s), c.m or "", colOf(c.s))
			end
		end
	end

	-- the reporter's answer on a closed report
	if closed then
		sectionHead(sc, P.L("rep_verdict"), "laurel")
		local v = UI.Label(sc, has(r.note) and r.note or "-", "Praetor.Body", C.laurel)
		v:SetWrap(true)
		v:SetAutoStretchVertical(true)
		v:Dock(TOP)
		local rt = tonumber(r.rating) or 0
		if rt ~= 0 then
			local rl = UI.Label(sc, P.L(rt > 0 and "rp_rated_good_short" or "rp_rated_bad_short"), "Praetor.SmallB", rt > 0 and C.laurel or C.amber)
			rl:Dock(TOP)
			rl:DockMargin(0, S(4), 0, 0)
		end
	end

	-- actions on the players
	sectionHead(sc, P.L("rp_actions"), "bolt")
	local bar = vgui.Create("DIconLayout", sc)
	bar:Dock(TOP)
	bar:SetSpaceX(S(6))
	bar:SetSpaceY(S(6))
	bar:DockMargin(0, 0, S(6), 0)
	local function btn(label, icon, fn, kind)
		local bt = bar:Add("PraetorButton")
		bt:Setup(label, kind or "subtle", icon)
		bt:SetFont("Praetor.Small")
		bt:SizeToLabel(S(14))
		bt:SetTall(S(30))
		bt.DoClick = fn
	end
	if not closed and P.MyHas("sit") and (IsValid(rep) or IsValid(tgt)) then
		btn(P.L("rep_sit"), "headset", function()
			local sids = {}
			if IsValid(rep) and rep ~= LocalPlayer() then sids[#sids + 1] = rep:SteamID64() end
			if IsValid(tgt) and tgt ~= LocalPlayer() then sids[#sids + 1] = tgt:SteamID64() end
			P.Request("sit_start", { sids = sids, report = r.id })
			P.CloseMenu()
		end, "primary")
	end
	if IsValid(rep) and P.CanRunId("goto") then btn(P.L("rep_goto_from"), "flag", function() P.RunCmd("goto", { rep:SteamID64() }) end) end
	if IsValid(tgt) and P.CanRunId("goto") then btn(P.L("rep_goto_against"), "flag", function() P.RunCmd("goto", { tgt:SteamID64() }) end) end
	if IsValid(rep) and P.CanRunId("bring") then btn(P.L("rep_bring_from"), "anchor", function() P.RunCmd("bring", { rep:SteamID64() }) end) end
	if IsValid(tgt) and P.CanRunId("bring") then btn(P.L("rp_bring_against"), "anchor", function() P.RunCmd("bring", { tgt:SteamID64() }) end) end
	if IsValid(tgt) and P.CanRunId("spectate") then btn(P.L("qa_spectate"), "eye", function() P.RunCmd("spectate", { tgt:SteamID64() }) P.CloseMenu() end) end
	if IsValid(tgt) and P.CanRunId("screengrab") then btn(P.L("qa_screen"), "image", function() P.RunCmd("screengrab", { tgt:SteamID64() }) end) end
	if IsValid(tgt) then btn(P.L("rep_actions"), "gear", function() P.PlayerMenu(tgt) end) end
	if has(r.tsid) and P.MyHas("view_sheet") then btn(P.L("qa_sheet"), "scroll", function() P.OpenMenu("users", { sid = r.tsid }) end) end

	-- conversation with the reporter
	sectionHead(sc, P.L("rp_conversation"), "bubble")
	local thread = vgui.Create("DPanel", sc)
	thread:Dock(TOP)
	thread:DockMargin(0, 0, S(6), 0)
	thread.Paint = nil
	local function relayout()
		local hh = 0
		for _, c in ipairs(thread:GetChildren()) do hh = hh + c:GetTall() + S(5) end
		thread:SetTall(math.max(hh, S(4)))
		sc:InvalidateLayout(true)
	end
	local empty
	if #(r.msgs or {}) == 0 then
		empty = vgui.Create("DPanel", thread)
		empty:Dock(TOP)
		empty:SetTall(S(22))
		empty.Paint = function(_, w, h) UI.Text(P.L(closed and "rp_no_msgs" or "rp_no_msgs_hint"), "Praetor.Tiny", 0, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	for _, m in ipairs(r.msgs or {}) do msgBubble(thread, m, S(420)) end
	relayout()
	pane.AddMsg = function(m)
		if IsValid(empty) then empty:Remove() end
		msgBubble(thread, m, S(420))
		relayout()
		timer.Simple(0, function() if IsValid(sc) then sc:GetVBar():AnimateTo(sc:GetCanvas():GetTall(), 0.2) end end)
	end

	if not closed then
		local say = vgui.Create("DPanel", sc)
		say:Dock(TOP)
		say:SetTall(S(32))
		say:DockMargin(0, S(4), S(6), S(8))
		say.Paint = nil
		local go = UI.Button(say, "", "primary", "send")
		go:Dock(RIGHT)
		go:SetWide(S(42))
		local mac = UI.Button(say, "", "ghost", "reply")
		mac:Dock(RIGHT)
		mac:SetWide(S(38))
		mac:DockMargin(0, 0, S(6), 0)
		mac:SetTooltip(P.L("rp_macros"))
		local e = UI.Entry(say, P.L(has(r.sid) and IsValid(rep) and "rp_msg_staff_ph" or "rp_msg_staff_off"), "")
		e:Dock(FILL)
		e:DockMargin(0, 0, S(6), 0)
		local function send(t)
			t = P.Trim(t or e:GetValue() or "")
			if t == "" then return end
			P.Request("report_say", { id = r.id, m = t })
			e:SetValue("")
			pane.AddMsg({ name = LocalPlayer():Nick(), staff = 1, t = os.time(), text = t })
		end
		go.DoClick = function() send() end
		e.OnEnter = function() send() end
		mac.DoClick = function()
			local items = {}
			for _, k in ipairs(MACROS) do
				local t = P.L(k)
				items[#items + 1] = { t, "reply", function() send(t) end }
			end
			UI.Popup(items)
		end
	end
end

-- ------------------------------------------------------------------ queue card

local function queueCard(parent, r, against, onPick)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b:Dock(TOP)
	b:SetTall(S(66))
	b:DockMargin(0, 0, S(6), S(6))
	b.DoClick = function() onPick(r) end
	b.Paint = function(s, w, h)
		local sel = view.sel == r.id
		local closed = r.status == "closed"
		local col = closed and (OUT_COL[r.outcome] or C.laurel) or prioCol(r.prio)
		UI.Round(0, 0, w, h, S(8), sel and C.hover or (s:IsHovered() and C.panel2 or C.panel), sel and C.bronze or C.line)
		UI.Round(1, S(8), S(3), h - S(16), S(1), col)
		UI.Icon(P.ReportCatIcon and P.ReportCatIcon[catOf(r)] or "flag", S(12), S(11), 16, col)
		UI.Text(UI.Fit("#" .. r.id .. "  " .. catName(r), "Praetor.SmallB", w - S(120)), "Praetor.SmallB", S(34), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(ago(r.created), "Praetor.Tiny", w - S(10), S(19), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		-- reporter > target with their pictures
		local y = S(36)
		UI.DrawAvatar(r.sid, P.BySID(r.sid), S(12), y, S(18), r.ron and 255 or 110, C.line)
		local x = S(36)
		local nm = UI.Fit(tostring(r.name or "?"), "Praetor.Tiny", S(110))
		UI.Text(nm, "Praetor.Tiny", x, y + S(9), r.ron and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetFont("Praetor.Tiny")
		x = x + surface.GetTextSize(nm) + S(6)
		if has(r.tsid) then
			UI.Text(">", "Praetor.Tiny", x, y + S(9), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			x = x + S(12)
			UI.DrawAvatar(r.tsid, P.BySID(r.tsid), x, y, S(18), r.ton and 255 or 110, C.line)
			UI.Text(UI.Fit(tostring(r.tname or "?"), "Praetor.Tiny", w - x - S(100)), "Praetor.Tiny", x + S(24), y + S(9), r.ton and C.crimsonL or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		-- right side: who took it / repeated reports / picture
		local rx = w - S(10)
		local n = has(r.tsid) and against[r.tsid] or 0
		if n > 1 then
			local t = P.L("rp_against_n", { V = n })
			surface.SetFont("Praetor.Tiny")
			local tw = surface.GetTextSize(t) + S(12)
			UI.Round(rx - tw, y, tw, S(18), S(9), Color(C.crimsonL.r, C.crimsonL.g, C.crimsonL.b, 30), C.crimsonL)
			UI.Text(t, "Praetor.Tiny", rx - tw / 2, y + S(9), C.crimsonL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			rx = rx - tw - S(6)
		end
		if (tonumber(r.shot) or 0) > 0 then
			UI.Icon("image", rx - 16, y + 1, 16, C.bronzeL)
			rx = rx - S(22)
		end
		if r.status == "claimed" and has(r.staff_name) then
			UI.Icon("hand", rx - 16, y + 1, 16, C.amber)
		end
	end
	return b
end

-- ------------------------------------------------------------------ tab

P.AddTab("reports", {
	cat = "moderation", icon = "flag", order = 1,
	can = function() return P.MyHas("reports") end,
	badge = function() return P.OpenReports or 0 end,
	build = function(panel)
		if P.BridgeInfo.bbx and P.Setting("reports_blackbox") then
			local bb = vgui.Create("DPanel", panel)
			bb:Dock(TOP)
			bb:SetTall(S(64))
			bb:DockMargin(0, 0, 0, S(10))
			bb.Paint = function(_, w, h)
				UI.Tablet(0, 0, w, h, Color(40, 30, 24), C.bronze)
				UI.Icon("scroll", S(14), (h - 32) / 2, 32)
				UI.Text(P.L("rep_bbx_title"), "Praetor.BodyB", S(58), S(12), C.bronzeL)
				UI.Text(UI.Fit(P.L("rep_bbx_text"), "Praetor.Small", w - S(250)), "Praetor.Small", S(58), S(36), C.text)
			end
			local open = UI.Button(bb, P.L("rep_bbx_open"), "primary", nil, function()
				P.CloseMenu()
				LocalPlayer():ConCommand("blackbox")
			end)
			open:Dock(RIGHT)
			open:DockMargin(0, S(14), S(14), S(14))
			open:SetWide(S(170))
		end

		local bar = UI.Toolbar(panel)
		local chips = {}
		local function chip(mode, label, icon)
			local b = UI.Tool(bar, UI.Button(bar, label, view.mode == mode and "active" or "ghost", icon), S(150))
			b.DoClick = function()
				view.mode = mode
				view.sel = nil
				for m2, c in pairs(chips) do c:Setup(c.label, m2 == mode and "active" or "ghost", c.icon) end
				P.Request("reports_list", { mode = mode })
			end
			chips[mode] = b
		end
		chip("open", P.L("rep_open"), "flag")
		chip("mine", P.L("rp_mine_staff"), "hand")
		chip("closed", P.L("rep_closed"), "laurel")
		local refresh = UI.Tool(bar, UI.Button(bar, P.L("ui_refresh"), "ghost", "reload"), S(130), RIGHT)

		local body = vgui.Create("DPanel", panel)
		body:Dock(FILL)
		body.Paint = nil
		local list = UI.Scroll(body)
		list:Dock(LEFT)
		local pane = vgui.Create("DPanel", body)
		pane:Dock(FILL)
		pane:DockMargin(S(10), 0, 0, 0)
		pane.Paint = function(s, w, h)
			if detailId then return end
			UI.Round(0, 0, w, h, S(8), C.panel, C.line)
			UI.Icon("flag", w / 2 - 16, h / 2 - S(40), 32, C.dim)
			UI.Text(P.L("rp_pick_one"), "Praetor.BodyB", w / 2, h / 2 + S(6), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			UI.Text(P.L("rp_pick_one_d"), "Praetor.Small", w / 2, h / 2 + S(28), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		body.PerformLayout = function(_, w) list:SetWide(math.Clamp(math.floor(w * 0.4), S(290), S(420))) end
		detailId = nil

		local function ask() P.Request("reports_list", { mode = view.mode }) end
		local function pick(r)
			view.sel = r.id
			P.Request("report_get", { id = r.id })
		end
		refresh.DoClick = function() ask() if view.sel then P.Request("report_get", { id = view.sel }) end end

		P.On("reports_list", function(d)
			if not IsValid(list) then return end
			P.OpenReports = d.open
			list:Clear()
			local rows = istable(d.rows) and d.rows or {}
			if #rows == 0 then
				local e = vgui.Create("DPanel", list)
				e:Dock(TOP)
				e:SetTall(S(110))
				e.Paint = function(_, w, h)
					UI.Icon("laurel", w / 2 - 16, S(16), 32, C.dim)
					UI.Text(P.L("rep_none"), "Praetor.BodyB", w / 2, S(66), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(UI.Fit(P.L("rep_none_hint"), "Praetor.Tiny", w - S(20)), "Praetor.Tiny", w / 2, S(88), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
			local against = istable(d.against) and d.against or {}
			local found = false
			for _, r in ipairs(rows) do
				queueCard(list, r, against, pick)
				if r.id == view.sel then found = true end
			end
			-- nothing chosen yet: the first of the queue opens by itself
			if not found then
				if rows[1] then pick(rows[1]) else view.sel = nil detailId = nil pane:Clear() end
			end
		end)
		P.On("report_get", function(r)
			if not IsValid(pane) or r.id ~= view.sel then return end
			buildDetail(pane, r)
		end)
		hook.Add("Praetor.ReportsChanged", "Praetor.ReportsTab", function(id)
			if not IsValid(list) then return end
			ask()
			if id and id == view.sel then P.Request("report_get", { id = id }) end
		end)
		hook.Add("Praetor.ReportMsg", "Praetor.ReportsTab", function(m)
			if IsValid(pane) and pane.AddMsg and m.rid == view.sel then pane.AddMsg(m) end
		end)
		ask()
	end,
})
