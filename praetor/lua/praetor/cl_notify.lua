-- Praetor: chat messages, action broadcasts, toasts, announcements,
-- staff chat, private messages and a few screen effects (blind).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local TAG = Color(142, 98, 255)

local function prefix(out)
	out[#out + 1] = C.bronzeD
	out[#out + 1] = "| "
	return out
end

-- Turns a translated template ("{A} kicked {T} ({V})") into chat.AddText parts.
function P.TemplateParts(template, a, base)
	local out = {}
	base = base or C.text
	local pos = 1
	while true do
		local s, e, key = template:find("{(%w+)}", pos)
		local before = template:sub(pos, (s or 0) - 1)
		if s == nil then before = template:sub(pos) end
		if before ~= "" then out[#out + 1] = base out[#out + 1] = before end
		if not s then break end
		local v = a and a[key]
		if istable(v) and v.n then
			local me = v.sid and IsValid(LocalPlayer()) and v.sid == LocalPlayer():SteamID64()
			out[#out + 1] = v.c and P.ReadColor(v.c, C.ivory) or C.ivory
			out[#out + 1] = me and P.L("you") or v.n
		elseif istable(v) then
			for i, x in ipairs(v) do
				if i > 1 then out[#out + 1] = base out[#out + 1] = ", " end
				if istable(x) and x.all then
					out[#out + 1] = C.bronzeL
					out[#out + 1] = P.L("everyone")
				elseif istable(x) then
					local me = x.sid and IsValid(LocalPlayer()) and x.sid == LocalPlayer():SteamID64()
					out[#out + 1] = x.c and P.ReadColor(x.c, C.ivory) or C.ivory
					out[#out + 1] = me and P.L("you") or tostring(x.n)
				else
					out[#out + 1] = C.ivory
					out[#out + 1] = tostring(x)
				end
			end
		elseif v ~= nil and v ~= "" then
			out[#out + 1] = C.bronzeL
			out[#out + 1] = tostring(v)
		end
		pos = e + 1
	end
	return out
end

local function addParts(parts)
	chat.AddText(unpack(parts))
end

P.On("echo", function(d)
	local out = prefix({})
	if d.s then
		out[#out + 1] = C.dim
		out[#out + 1] = "(" .. P.L("silent") .. ") "
	end
	for _, p in ipairs(P.TemplateParts(P.L(d.k), P.LocalArgs(d.a))) do out[#out + 1] = p end
	addParts(out)
end)

-- values the server can't translate: "@arg_player" is a word to translate, and
-- U = a command id becomes its usage line ("!jail <player> [time] [reason]")
local function localArgs(a)
	if not istable(a) then return a end
	local out = {}
	for k, v in pairs(a) do
		if isstring(v) and v:sub(1, 1) == "@" and #v > 1 then out[k] = P.L(v:sub(2), nil, v:sub(2)) else out[k] = v end
	end
	if isstring(out.U) then
		local c = P.ServerCmds and P.ServerCmds[out.U]
		out.U = (c and P.UsageText) and P.UsageText(c) or ("!" .. out.U)
	end
	return out
end
P.LocalArgs = localArgs

P.On("notify", function(d)
	d.a = localArgs(d.a)
	local col = d.kind == "ok" and C.laurel or (d.kind == "warn" and C.amber or (tostring(d.k):sub(1, 4) == "err_" and C.crimsonL or C.text))
	local out = prefix({})
	for _, p in ipairs(P.TemplateParts(P.L(d.k), d.a, col)) do out[#out + 1] = p end
	addParts(out)
	if d.kind == "ok" then UI.Sound("ok")
	elseif tostring(d.k):sub(1, 4) == "err_" then UI.Sound("error")
	else UI.Sound("notify") end
	if d.kind == "warn" then P.Toast(P.L("toast_warning"), P.EchoText(d.k, d.a), "warn") end
end)

-- plain text version of a template (toasts)
function P.EchoText(key, a)
	local parts = P.TemplateParts(P.L(key), a)
	local s = {}
	for _, v in ipairs(parts) do if isstring(v) then s[#s + 1] = v end end
	return table.concat(s)
end

P.On("chat", function(parts)
	local out = {}
	for _, v in ipairs(parts) do
		if istable(v) and v.c then out[#out + 1] = Color(v.c[1] or 255, v.c[2] or 255, v.c[3] or 255)
		elseif isstring(v) then out[#out + 1] = v end
	end
	if #out > 0 then addParts(out) end
end)

P.On("adminchat", function(d)
	local from = isstring(d.sid) and player.GetBySteamID64(d.sid)
	if d.staff and IsValid(from) and P.ChatPlayerLine and P.ChatMode() ~= "off" then
		P.ChatPlayerLine(from, d.m, false, false, nil, nil, nil, "staff")
		if from ~= LocalPlayer() then UI.Sound("chat") end
		return
	end
	if d.staff then
		chat.AddText(C.crimson, "[" .. P.L("staff_chat") .. "] ", C.bronzeL, d.n, C.muted, ": ", C.ivory, d.m)
	else
		chat.AddText(C.amber, "[" .. P.L("help_request") .. "] ", C.bronzeL, d.n, C.muted, ": ", C.ivory, d.m)
		if P.MyHas("adminchat") and d.sid ~= LocalPlayer():SteamID64() then
			P.Toast(P.L("help_request"), d.n .. ": " .. d.m, "report")
		end
	end
	UI.Sound("chat")
end)

P.On("pm", function(d)
	local me = LocalPlayer():SteamID64()
	if d.fsid == me then
		chat.AddText(C.sky, "[PM] ", C.muted, P.L("pm_to") .. " ", C.bronzeL, d.to, C.muted, ": ", C.ivory, d.m)
	else
		chat.AddText(C.sky, "[PM] ", C.bronzeL, d.from, C.muted, ": ", C.ivory, d.m)
		UI.Sound("chat")
		P.LastPM = d.fsid
	end
end)

P.On("clearchat", function()
	if P.ChatBox and P.ChatBox.Clear then P.ChatBox.Clear() end
	for _ = 1, 30 do chat.AddText(" ") end
end)

P.On("open_menu", function(d) if P.OpenMenu then P.OpenMenu(d.tab, d) end end)
P.On("open_report", function(d) if P.OpenReport then P.OpenReport(d.t) end end)

-- ------------------------------------------------------------------ toasts

local toasts = {}

-- kind: info / ok / warn / report / alert
function P.Toast(title, text, kind, time)
	table.insert(toasts, 1, { title = title, text = text or "", kind = kind or "info", t = RealTime(), life = time or 7, a = 0 })
	while #toasts > 5 do table.remove(toasts) end
end

local kindCol = { info = C.bronze, ok = C.laurel, warn = C.amber, report = C.sky, alert = C.crimson }
local kindIcon = { info = "bell", ok = "check", warn = "warn", report = "flag", alert = "shield" }

hook.Add("HUDPaint", "Praetor.Toasts", function()
	if #toasts == 0 then return end
	local w = math.min(S(340), ScrW() * 0.4)
	local x = ScrW() - w - S(16)
	local y = S(16)
	local now = RealTime()
	for i = #toasts, 1, -1 do
		if now - toasts[i].t > toasts[i].life then table.remove(toasts, i) end
	end
	for _, t in ipairs(toasts) do
		local age = now - t.t
		local a = math.min(1, age * 6, (t.life - age) * 3)
		-- comes in from the right with a little spring, leaves to the right
		local inK = UI.EaseBack(math.min(1, age / 0.38))
		local outK = math.max(0, 1 - (t.life - age) / 0.3)
		local slide = (1 - inK) * (w + S(30)) + outK * outK * S(80)
		t.lines = t.lines or UI.Wrap(t.text, "Praetor.Small", w - S(76))
		local nl = math.min(#t.lines, 3)
		local h = S(34) + nl * S(17) + S(14)
		local col = kindCol[t.kind] or C.bronze
		local bx = x + slide
		local off = S(4)
		UI.Round(bx + off, y + off, w, h, S(14), Color(C.ink.r, C.ink.g, C.ink.b, 200 * a))
		UI.Round(bx, y, w, h, S(14), Color(C.panel.r, C.panel.g, C.panel.b, 245 * a), Color(col.r, col.g, col.b, 255 * a))
		-- the icon on a disc of the toast colour; it wobbles once when the toast arrives
		local d = S(40)
		local wob = age < 0.6 and math.sin(age * 30) * (0.6 - age) * 30 or 0
		UI.Round(bx + S(10), y + S(10), d, d, d / 2, Color(col.r, col.g, col.b, 255 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
		UI.IconRot(kindIcon[t.kind] or "scroll", bx + S(10) + (d - 24) / 2, y + S(10) + (d - 24) / 2, 24, wob, Color(255, 255, 255, 255 * a))
		draw.SimpleText(UI.Fit(t.title, "Praetor.BodyB", w - S(76)), "Praetor.BodyB", bx + S(60), y + S(10), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a))
		for li = 1, nl do
			draw.SimpleText(t.lines[li], "Praetor.Small", bx + S(60), y + S(31) + (li - 1) * S(17), Color(C.text.r, C.text.g, C.text.b, 255 * a))
		end
		-- time left: a thin bar that empties along the bottom
		local left = math.Clamp(1 - age / t.life, 0, 1)
		UI.Round(bx + S(12), y + h - S(8), (w - S(24)) * left, S(3), S(1), Color(col.r, col.g, col.b, 200 * a))
		y = y + h + S(10)
	end
end)

-- DarkRP (and other addons) send their notices with notification.AddLegacy:
-- while the Praetor HUD is on they show up as Praetor toasts
local legacyKind = { [0] = "info", [1] = "alert", [2] = "info", [3] = "ok", [4] = "info" }
P.OrigAddLegacy = P.OrigAddLegacy or notification.AddLegacy
function notification.AddLegacy(text, kind, len)
	if P.HUD and P.HUD.On and P.HUD.On() then
		P.Toast(P.L(kind == 1 and "hud_notice_err" or "hud_notice"), tostring(text or ""), legacyKind[kind or 0] or "info", tonumber(len) or 5)
		return
	end
	return P.OrigAddLegacy(text, kind, len)
end

-- ------------------------------------------------------------------ announcements

local announce
P.On("announce", function(d)
	announce = { t = d.t, n = d.n, start = RealTime() }
	UI.Sound("gavel")
end)

hook.Add("HUDPaint", "Praetor.Announce", function()
	if not announce then return end
	local age = RealTime() - announce.start
	local life = math.Clamp(#announce.t * 0.09, 6, 14)
	if age > life then announce = nil return end
	local a = math.min(1, age * 5, (life - age) * 2)
	local w = math.min(ScrW() - S(40), S(780))
	announce.lines = announce.lines or UI.Wrap(announce.t, "Praetor.Big", w - S(70))
	local nl = math.min(#announce.lines, 4)
	local h = S(70) + nl * S(28) + S(20)
	local x = (ScrW() - w) / 2
	local y = S(96)
	-- pops in (grows with a spring from its centre) and rises away at the end
	local pop = 0.6 + 0.4 * UI.EaseBack(math.min(1, age / 0.4))
	y = y - math.max(0, 0.5 - (life - age)) * S(60)
	local m = Matrix()
	local cx, cy = ScrW() / 2, y + h / 2
	m:Translate(Vector(cx, cy, 0))
	m:Scale(Vector(pop, pop, 1))
	m:Translate(Vector(-cx, -cy, 0))
	cam.PushModelMatrix(m, true)
	local off = S(6)
	UI.Round(x + off, y + off, w, h, S(18), Color(C.ink.r, C.ink.g, C.ink.b, 210 * a))
	UI.Round(x, y, w, h, S(18), Color(C.panel.r, C.panel.g, C.panel.b, 248 * a), Color(C.edge.r, C.edge.g, C.edge.b, 255 * a))
	-- a tilted "ANNOUNCEMENT" sticker on the top edge, with the megaphone
	local label = P.Upper(P.L("announcement"))
	surface.SetFont("Praetor.H2")
	local lw = surface.GetTextSize(label) + S(62)
	local lh = S(36)
	local lx, ly = x + w / 2 - lw / 2, y - lh / 2
	local tilt = Matrix()
	tilt:Translate(Vector(lx + lw / 2, ly + lh / 2, 0))
	tilt:Rotate(Angle(0, -2 + math.sin(age * 3) * 1.2, 0))
	tilt:Translate(Vector(-(lx + lw / 2), -(ly + lh / 2), 0))
	cam.PushModelMatrix(tilt, true)
	UI.Round(lx + S(3), ly + S(3), lw, lh, lh / 2, Color(C.ink.r, C.ink.g, C.ink.b, 230 * a))
	UI.Round(lx, ly, lw, lh, lh / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 255 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a))
	UI.Icon("megaphone", lx + S(12), ly + (lh - 24) / 2, 24, Color(255, 255, 255, 255 * a))
	draw.SimpleText(label, "Praetor.H2", lx + S(44), ly + lh / 2, Color(255, 255, 255, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	cam.PopModelMatrix()
	for i = 1, nl do
		local ty = y + S(34) + (i - 1) * S(28)
		draw.SimpleText(announce.lines[i], "Praetor.Big", x + w / 2 + S(2), ty + S(2), Color(C.ink.r, C.ink.g, C.ink.b, 200 * a), TEXT_ALIGN_CENTER)
		draw.SimpleText(announce.lines[i], "Praetor.Big", x + w / 2, ty, Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_CENTER)
	end
	if announce.n then
		draw.SimpleText("- " .. announce.n, "Praetor.SmallB", x + w - S(20), y + h - S(26), Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, 255 * a), TEXT_ALIGN_RIGHT)
	end
	local left = math.Clamp(1 - age / life, 0, 1)
	UI.Round(x + S(20), y + h - S(10), (w - S(40)) * left, S(4), S(2), Color(C.bronze.r, C.bronze.g, C.bronze.b, 220 * a))
	cam.PopModelMatrix()
end)

-- ------------------------------------------------------------------ warnings, reports, security

P.On("warned", function(d)
	UI.Sound("warn")
	P.Toast(P.L("warned_title"), P.L("warned_text", { V = d.r, S = d.by, N = d.pts }), "warn", 12)
	chat.AddText(C.amber, "[" .. P.L("warned_title") .. "] ", C.ivory, d.r, C.muted, " - " .. d.by)
end)

P.On("report_new", function(d)
	UI.Sound("report")
	local cat = d.cat and P.L("reason_" .. d.cat) or d.r
	local hot = (tonumber(d.prio) or 0) >= 40
	P.Toast(P.L("report_new_title", { V = d.open }) .. (hot and ("  ·  " .. P.L("rp_prio_high")) or ""), d.n .. ((d.t or "") ~= "" and (" > " .. d.t) or "") .. ": " .. tostring(cat), hot and "alert" or "report", 9)
	P.OpenReports = d.open
	hook.Run("Praetor.ReportsChanged", d.id)
end)

P.On("report_upd", function(d)
	P.OpenReports = d.open
	hook.Run("Praetor.ReportsChanged", d.id)
end)

-- reports nobody took ring again every 2 minutes
P.On("report_remind", function(d)
	P.OpenReports = d.open
	UI.Sound("report")
	P.Toast(P.L("rp_remind_title"), P.L("rp_remind_text", { V = d.n }), "report", 8)
	hook.Run("Praetor.ReportsChanged")
end)

-- the reporter said if it helped
P.On("report_rated", function(d)
	UI.Sound(d.good and "ok" or "notify")
	P.Toast(P.L("rp_tag", { V = d.id }), P.L(d.good and "rp_rated_good" or "rp_rated_bad", { S = d.n }), d.good and "ok" or "warn", 8)
end)

P.On("alert", function(d)
	UI.Sound("error")
	P.Toast(P.L("security_alert"), P.L("sec_" .. tostring(d.kind)) .. " - " .. tostring(d.name) .. (d.info ~= "" and (" (" .. d.info .. ")") or ""), "alert", 10)
end)

-- ------------------------------------------------------------------ screen effects

hook.Add("HUDPaint", "Praetor.Blind", function()
	local me = LocalPlayer()
	if IsValid(me) and me:GetNW2Bool("pr_blind") then
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, ScrW(), ScrH())
		draw.SimpleText(P.L("blinded"), "Praetor.H1", ScrW() / 2, ScrH() / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

-- (the jail cage is the praetor_jail entity; its sign and the prisoner HUD live in cl_jail.lua)

-- "Admin gave Moderator: Kick, Ban" when someone edits permissions
function P.PermLabel(id)
	local label = P.L("perm_" .. id, nil, "")
	if label ~= "" then return label end
	if P.ServerCmds and P.ServerCmds[id] or P.Commands and P.Commands[id] then return "!" .. id end
	return id
end

P.On("perm_feed", function(d)
	local me = IsValid(LocalPlayer()) and d.as == LocalPlayer():SteamID64()
	local who = me and P.L("you") or tostring(d.a or "?")
	local whoC = d.ac and P.ReadColor(d.ac, C.ivory) or C.ivory
	local tgtC = d.c and P.ReadColor(d.c, C.ivory) or C.ivory
	local tgt = tostring(d.n or "?")
	local function line(list, key, col, mark)
		if not istable(list) or #list == 0 then return end
		local out = prefix({})
		out[#out + 1] = whoC
		out[#out + 1] = who
		out[#out + 1] = C.text
		out[#out + 1] = " " .. P.L(key .. (d.k == "user" and "_u" or "")) .. " "
		out[#out + 1] = tgtC
		out[#out + 1] = tgt
		out[#out + 1] = C.text
		out[#out + 1] = ": "
		local shown = math.min(#list, 6)
		for i = 1, shown do
			if i > 1 then out[#out + 1] = C.dim out[#out + 1] = ", " end
			out[#out + 1] = col
			out[#out + 1] = mark .. P.PermLabel(list[i])
		end
		if #list > shown then
			out[#out + 1] = C.dim
			out[#out + 1] = " " .. P.L("pf_more", { V = #list - shown })
		end
		addParts(out)
	end
	line(d.g, "pf_give", C.laurel, "+ ")
	line(d.t, "pf_take", C.crimsonL, "- ")
	line(d.r, "pf_reset", C.muted, "~ ")
	UI.Sound("notify")
end)

-- dupe refused (or huge but allowed by the rank): card for the player, alert for staff
P.On("dupe_alert", function(d)
	local mine = d.p == nil
	local why = tostring(d.w or "ents")
	local args = { V = tonumber(d.n) or 0, V2 = tonumber(d.m) or 0, S = d.p or "", M = d.md and string.GetFileFromFilename(d.md) or "" }
	local key
	if mine then key = (d.ok and "da_me_ok_" or "da_me_") .. why
	else key = (d.ok and "da_st_ok_" or "da_st_") .. why end
	local title = P.L(mine and (d.ok and "da_title_ok" or "da_title") or "da_title_staff")
	local text = P.EchoText(key, args)
	P.Toast(title, text, d.ok and "warn" or "alert", mine and 9 or 7)
	local out = prefix({})
	for _, p in ipairs(P.TemplateParts(P.L(key), args, d.ok and C.amber or C.crimsonL)) do out[#out + 1] = p end
	addParts(out)
	UI.Sound(d.ok and "warn" or "error")
end)
