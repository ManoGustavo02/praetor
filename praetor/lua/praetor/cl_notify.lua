-- Praetor: chat messages, action broadcasts, toasts, announcements,
-- staff chat, private messages and a few screen effects (blind, jail cage).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local TAG = Color(92, 132, 255)

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
	for _, p in ipairs(P.TemplateParts(P.L(d.k), d.a)) do out[#out + 1] = p end
	addParts(out)
end)

P.On("notify", function(d)
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
local kindIcon = { info = "scroll", ok = "laurel", warn = "bolt", report = "flag", alert = "shield" }

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
		local a = math.min(1, age * 5, (t.life - age) * 2)
		local slide = (1 - math.min(1, age * 4)) * S(40)
		t.lines = t.lines or UI.Wrap(t.text, "Praetor.Small", w - S(58))
		local nl = math.min(#t.lines, 3)
		local h = S(30) + nl * S(17) + S(10)
		local col = kindCol[t.kind] or C.bronze
		local bx = x + slide
		UI.Notch(bx, y, w, h, S(6), Color(22, 18, 27, 235 * a), Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 255 * a))
		UI.Rect(bx + 1, y + S(6), S(3), h - S(12), Color(col.r, col.g, col.b, 255 * a))
		UI.Icon(kindIcon[t.kind] or "scroll", bx + S(12), y + S(10), 32 > S(40) and 32 or 16, Color(255, 255, 255, 255 * a))
		draw.SimpleText(UI.Fit(t.title, "Praetor.BodyB", w - S(58)), "Praetor.BodyB", bx + S(40), y + S(7), Color(col.r, col.g, col.b, 255 * a))
		for li = 1, nl do
			draw.SimpleText(t.lines[li], "Praetor.Small", bx + S(40), y + S(28) + (li - 1) * S(17), Color(222, 212, 196, 255 * a))
		end
		y = y + h + S(8)
	end
end)

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
	local a = math.min(1, age * 4, (life - age) * 2)
	local w = math.min(ScrW() - S(40), S(760))
	announce.lines = announce.lines or UI.Wrap(announce.t, "Praetor.Big", w - S(60))
	local nl = math.min(#announce.lines, 4)
	local h = S(58) + nl * S(26) + S(16)
	local x = (ScrW() - w) / 2
	local y = S(90) - (1 - math.min(1, age * 3)) * S(30)
	UI.Round(x, y, w, h, S(8), Color(18, 19, 24, 238 * a), Color(50, 53, 63, 255 * a))
	UI.Round(x, y, w, S(4), S(2), Color(92, 132, 255, 255 * a))
	draw.SimpleText(P.Upper(P.L("announcement")), "Praetor.SmallB", x + w / 2, y + S(16), Color(146, 172, 255, 255 * a), TEXT_ALIGN_CENTER)
	for i = 1, nl do
		draw.SimpleText(announce.lines[i], "Praetor.Big", x + w / 2, y + S(46) + (i - 1) * S(26), Color(238, 240, 245, 255 * a), TEXT_ALIGN_CENTER)
	end
	if announce.n then
		draw.SimpleText("- " .. announce.n, "Praetor.Small", x + w - S(16), y + h - S(22), Color(142, 147, 160, 255 * a), TEXT_ALIGN_RIGHT)
	end
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

-- bronze cage around jailed players
local barMat = Material("color")
hook.Add("PostDrawTranslucentRenderables", "Praetor.Jail", function(depth, sky)
	if sky then return end
	for _, p in ipairs(player.GetAll()) do
		if p:GetNW2Bool("pr_jailed") then
			local c = p:GetNW2Vector("pr_jailpos")
			if c and c ~= vector_origin and c:DistToSqr(EyePos()) < 2500 * 2500 then
				render.SetColorMaterial()
				local r, hgt = 56, 96
				local col = Color(92, 132, 255, 230)
				for i = 0, 15 do
					local ang = i / 16 * math.pi * 2
					local x, y = math.cos(ang) * r, math.sin(ang) * r
					render.DrawBox(c + Vector(x, y, 0), Angle(0, 0, 0), Vector(-1, -1, 0), Vector(1, 1, hgt), col)
				end
				for _, z in ipairs({ 2, hgt / 2, hgt }) do
					for i = 0, 15 do
						local a1, a2 = i / 16 * math.pi * 2, (i + 1) / 16 * math.pi * 2
						render.DrawBeam(c + Vector(math.cos(a1) * r, math.sin(a1) * r, z), c + Vector(math.cos(a2) * r, math.sin(a2) * r, z), 2.5, 0, 1, col)
					end
				end
			end
		end
	end
end)

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
