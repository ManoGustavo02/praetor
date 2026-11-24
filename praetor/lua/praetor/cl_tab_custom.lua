-- Praetor menu: custom commands built with blocks (no code).
-- Left: the commands. Right: the editor - name, icon and who can use it on top,
-- the block palette on the left and the script on the right. Blocks are dragged
-- from the palette into the script, moved around, and dropped back on the
-- palette to delete them. "If", "for each" and "repeat" hold other blocks.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local MAX_BLOCKS = 80

-- palette sections: colour, icon and the blocks in it
local CATS = {
	{ id = "msg", col = Color(84, 138, 255), icon = "bubble", blocks = { "msg_all", "msg_target", "msg_caller", "announce", "sound" } },
	{ id = "player", col = Color(64, 178, 104), icon = "user", blocks = { "hp", "armor", "give", "strip", "respawn", "god", "cloak", "freeze", "ignite", "extinguish", "launch", "speed", "scale", "model" } },
	{ id = "move", col = Color(36, 172, 190), icon = "portal", blocks = { "bring", "goto", "return", "tp_pos" } },
	{ id = "punish", col = Color(214, 70, 84), icon = "hammer", blocks = { "slay", "kick", "ban", "jail", "mute" } },
	{ id = "darkrp", col = Color(214, 160, 48), icon = "brief", blocks = { "setjob", "money" }, darkrp = true },
	{ id = "control", col = Color(232, 122, 48), icon = "reload", blocks = { "if", "each", "repeat", "wait", "stop" } },
	{ id = "adv", col = Color(150, 104, 226), icon = "terminal", blocks = { "run", "console" } },
}
local CAT_OF = {}
for _, c in ipairs(CATS) do for _, b in ipairs(c.blocks) do CAT_OF[b] = c end end

local ICON = {
	msg_all = "bubble", msg_target = "envelope", msg_caller = "reply", announce = "megaphone", sound = "music",
	hp = "heart", armor = "vest", give = "gun", strip = "gun_no", respawn = "heart_plus", god = "halo", cloak = "ghost",
	freeze = "snow", ignite = "flame", extinguish = "drop", launch = "rocket", speed = "speed", scale = "scale", model = "user",
	bring = "magnet", ["goto"] = "pin", ["return"] = "undo", tp_pos = "portal",
	slay = "skull", kick = "door", ban = "hammer", jail = "jail", mute = "bubble_no",
	setjob = "brief", money = "coin",
	["if"] = "key", each = "players", ["repeat"] = "reload", wait = "clock", stop = "cross",
	run = "bolt", console = "terminal",
}

-- parameters each block asks for (same rules as sv_custom.lua)
local FIELDS = {
	msg_all = { "text", "color" }, msg_target = { "text", "color" }, msg_caller = { "text", "color" },
	announce = { "text" }, hp = { "n" }, armor = { "n" }, give = { "class" }, strip = {}, slay = {}, respawn = {},
	freeze = { "on" }, god = { "on" }, cloak = { "on" }, ignite = { "n" }, extinguish = {},
	bring = {}, ["goto"] = {}, ["return"] = {}, tp_pos = { "pos" }, launch = { "n" }, model = { "mdl" },
	speed = { "n" }, scale = { "n" }, sound = { "path" }, kick = { "text" }, ban = { "min", "text" },
	jail = { "min" }, mute = { "min" }, setjob = { "job" }, money = { "n" }, run = { "text" }, wait = { "n" }, console = { "text" },
	["if"] = { "cond" }, each = {}, ["repeat"] = { "n" }, stop = {},
}

local CONDS = { "alive", "dead", "staff", "is_caller", "rank", "hp_below", "armor_below", "money_atleast", "job", "chance", "arg_set" }
local COND_VALUE = { rank = "rank", hp_below = "n", armor_below = "n", money_atleast = "n", job = "job", chance = "n", arg_set = "i" }

local function newBlock(t)
	local me = IsValid(LocalPlayer()) and LocalPlayer():GetPos() or Vector()
	local d = {
		msg_all = { text = P.L("cuh_text") }, msg_target = { text = P.L("cuh_text") }, msg_caller = { text = P.L("cuh_text") },
		announce = { text = P.L("cuh_text") }, hp = { n = 100 }, armor = { n = 100 }, give = { class = "weapon_crowbar" },
		freeze = { on = true }, god = { on = true }, cloak = { on = true }, ignite = { n = 5 }, launch = { n = 800 },
		speed = { n = 2 }, scale = { n = 1.5 }, model = { mdl = "models/player/kleiner.mdl" }, sound = { path = "buttons/bell1.wav" },
		kick = { text = "" }, ban = { min = 60, text = "" }, jail = { min = 5 }, mute = { min = 5 },
		setjob = { job = "" }, money = { n = 100 }, run = { text = "" }, wait = { n = 1 }, console = { text = "" },
		tp_pos = { pos = { math.floor(me.x), math.floor(me.y), math.floor(me.z) } },
		["if"] = { cond = { k = "alive" }, body = {}, els = {} }, each = { body = {} }, ["repeat"] = { n = 3, body = {} },
	}
	local b = table.Copy(d[t] or {})
	b.t = t
	return b
end

local function countBlocks(list)
	local n = 0
	for _, a in ipairs(list or {}) do n = n + 1 + countBlocks(a.body) + countBlocks(a.els) end
	return n
end

-- true when `list` is the body / else of `block` or of any block inside it
local function contains(block, list)
	if block.body == list or block.els == list then return true end
	for _, a in ipairs(block.body or {}) do if contains(a, list) then return true end end
	for _, a in ipairs(block.els or {}) do if contains(a, list) then return true end end
	return false
end

local function rankName(r)
	local rk = P.Ranks[r or ""]
	return rk and (rk.display or rk.name) or tostring(r or "?")
end

local function condText(c)
	c = c or { k = "alive" }
	local args = { V = c.n or c.i or "", S = c.k == "rank" and rankName(c.rank) or (c.job or "") }
	local t = P.L("cond_" .. c.k, args)
	if c.neg then t = P.L("cond_not") .. " " .. t end
	return t
end

-- what a block shows: its label and its values as pills
local function blockSegs(a)
	local t = a.t
	local pill
	if t == "if" then pill = condText(a.cond)
	elseif t == "repeat" then pill = (a.n or 1) .. "x"
	elseif t == "wait" or t == "ignite" then pill = (a.n or 0) .. " s"
	elseif t == "speed" or t == "scale" then pill = "x" .. (a.n or 1)
	elseif t == "ban" then pill = ((a.min or 0) > 0 and P.FormatDuration(a.min) or P.L("ui_perm")) .. ((a.text or "") ~= "" and ("  -  " .. a.text) or "")
	elseif t == "jail" or t == "mute" then pill = (a.min or 0) > 0 and P.FormatDuration(a.min) or P.L("ui_perm")
	elseif t == "freeze" or t == "god" or t == "cloak" then pill = a.on == false and P.L("off") or P.L("on")
	elseif t == "tp_pos" then pill = table.concat(a.pos or { 0, 0, 0 }, " ")
	elseif t == "run" then pill = "!" .. (a.text or "")
	elseif a.text ~= nil then pill = a.text ~= "" and a.text or "-"
	elseif a.n ~= nil then pill = tostring(a.n)
	elseif a.class then pill = a.class
	elseif a.mdl then pill = a.mdl ~= "" and a.mdl or "-"
	elseif a.path then pill = a.path ~= "" and a.path or "-"
	elseif a.job then pill = a.job ~= "" and a.job or "-"
	end
	return P.L("blk_" .. t), pill
end

-- ------------------------------------------------------------------ block editor (modal)

local function editBlock(a, onDone)
	local fields = FIELDS[a.t] or {}
	if #fields == 0 then return false end
	a = table.Copy(a)
	local m = UI.Modal(P.L("blk_" .. a.t), S(460), S(a.t == "if" and 330 or 360))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)
	local getters = {}
	local function label(t)
		local l = UI.Label(sc, t, "Praetor.SmallB", C.muted)
		l:Dock(TOP)
		l:DockMargin(0, S(6), 0, S(3))
	end
	for _, f in ipairs(fields) do
		if f == "cond" then
			a.cond = a.cond or { k = "alive" }
			label(P.L("cu_cond"))
			local opts = {}
			for _, k in ipairs(CONDS) do opts[#opts + 1] = { k, P.L("condk_" .. k) } end
			local valHolder = vgui.Create("DPanel", sc)
			local valCtl, valKind
			local function valField()
				valHolder:Clear()
				valKind = COND_VALUE[a.cond.k]
				valHolder:SetTall(valKind and S(60) or 1)
				if not valKind then return end
				local l = UI.Label(valHolder, P.L("cuf_" .. valKind), "Praetor.SmallB", C.muted)
				l:Dock(TOP)
				l:DockMargin(0, S(6), 0, S(3))
				if valKind == "rank" then
					local ro = {}
					for _, r in ipairs(P.SortedRanks()) do ro[#ro + 1] = { r.name, r.display or r.name } end
					valCtl = UI.Combo(valHolder, ro, a.cond.rank or "user")
				elseif valKind == "i" then
					valCtl = UI.Combo(valHolder, { { "1", "{1}" }, { "2", "{2}" }, { "3", "{3}" } }, tostring(a.cond.i or 1))
				elseif valKind == "job" then
					valCtl = UI.Entry(valHolder, "medic", a.cond.job or "")
				else
					valCtl = UI.Entry(valHolder, "0", a.cond.n and tostring(a.cond.n) or "")
					valCtl:SetNumeric(true)
				end
				valCtl:Dock(TOP)
			end
			local kind = UI.Combo(sc, opts, a.cond.k, function(v) a.cond = { k = v, neg = a.cond.neg } valField() end)
			kind:Dock(TOP)
			valHolder:Dock(TOP)
			valHolder.Paint = nil
			valField()
			local neg = UI.Switch(sc, P.L("cu_cond_neg"), nil, a.cond.neg == true, function(v) a.cond.neg = v or nil end)
			neg:Dock(TOP)
			neg:DockMargin(0, S(6), 0, 0)
			getters.cond = function()
				if not valKind or not IsValid(valCtl) then return end
				if valKind == "rank" then local _, v = valCtl:GetSelected() a.cond.rank = v
				elseif valKind == "i" then local _, v = valCtl:GetSelected() a.cond.i = tonumber(v) or 1
				elseif valKind == "job" then a.cond.job = valCtl:GetValue()
				else a.cond.n = tonumber(valCtl:GetValue()) end
			end
		else
			label(P.L("cuf_" .. f))
			local ctl
			if f == "color" then
				ctl = UI.Swatch(sc, P.ReadColor(a.c, C.bronzeL), function(c) a.c = { r = c.r, g = c.g, b = c.b } end)
			elseif f == "on" then
				ctl = UI.Combo(sc, { { "1", P.L("on") }, { "0", P.L("off") } }, a.on == false and "0" or "1")
				getters[f] = function() local _, v = ctl:GetSelected() a.on = v ~= "0" end
			elseif f == "min" then
				ctl = UI.DurationField(sc, a.min and a.min > 0 and (a.min .. "m") or "")
				getters[f] = function() a.min = ctl:GetMinutes() or 0 end
			elseif f == "pos" then
				local p = a.pos or { 0, 0, 0 }
				ctl = UI.Entry(sc, "x y z", table.concat(p, " "))
				getters[f] = function()
					local t = {}
					for n in ctl:GetValue():gmatch("%-?[%d%.]+") do t[#t + 1] = tonumber(n) end
					a.pos = { t[1] or 0, t[2] or 0, t[3] or 0 }
				end
				local here = UI.Button(sc, P.L("cu_here"), "ghost", "pin", function()
					local pos = LocalPlayer():GetPos()
					ctl:SetValue(math.floor(pos.x) .. " " .. math.floor(pos.y) .. " " .. math.floor(pos.z))
				end)
				ctl:Dock(TOP)
				here:Dock(TOP)
				here:DockMargin(0, S(4), 0, 0)
				ctl = nil
			elseif f == "n" then
				ctl = UI.Entry(sc, "0", a.n and tostring(a.n) or "")
				getters[f] = function() a.n = tonumber(ctl:GetValue()) or a.n end
			else
				ctl = UI.Entry(sc, P.L("cuh_" .. f, nil, ""), a[f] or "")
				getters[f] = function() a[f] = ctl:GetValue() end
			end
			if ctl then ctl:Dock(TOP) end
		end
	end
	if table.HasValue(fields, "text") then
		local hint = UI.Label(sc, P.L("cu_placeholders"), "Praetor.Tiny", C.dim)
		hint:SetWrap(true)
		hint:SetAutoStretchVertical(true)
		hint:Dock(TOP)
		hint:DockMargin(0, S(8), 0, 0)
	end
	local ok = UI.Button(m.foot, P.L("ui_ok"), "primary", "check", function()
		for _, g in pairs(getters) do g() end
		onDone(a)
		m:Close()
	end)
	ok:Dock(RIGHT)
	ok:SetWide(S(120))
	return true
end

-- arguments of the command (the "when someone types" block)
local function editArgs(d, onDone)
	local m = UI.Modal(P.L("cu_args_title"), S(500), S(300))
	local intro = UI.Label(m.body, P.L("cu_args_sub"), "Praetor.Small", C.muted)
	intro:Dock(TOP)
	intro:DockMargin(0, 0, 0, S(8))
	local ctl = {}
	for i = 1, 3 do
		local a = d.args[i] or {}
		local row = vgui.Create("DPanel", m.body)
		row:Dock(TOP)
		row:SetTall(S(34))
		row:DockMargin(0, 0, 0, S(6))
		row.Paint = function(_, w, h) UI.Text("{" .. i .. "}", "Praetor.BodyB", 0, h / 2, C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		local t = UI.Combo(row, { { "", P.L("cu_arg_none") }, { "player", P.L("arg_player") }, { "number", P.L("arg_number") }, { "text", P.L("arg_text") }, { "duration", P.L("arg_time") } }, a.type or "")
		t:SetPos(S(34), 0)
		t:SetSize(S(140), S(34))
		local hint = UI.Entry(row, P.L("cu_arg_name"), a.hint or "")
		hint:SetPos(S(180), 0)
		hint:SetSize(S(170), S(34))
		local opt = UI.Toggle(row, P.L("optional"), nil, a.optional == true)
		opt:SetFont("Praetor.Small")
		opt:SetPos(S(356), 0)
		opt:SetSize(S(120), S(34))
		ctl[i] = { t = t, hint = hint, opt = opt }
	end
	local ok = UI.Button(m.foot, P.L("ui_ok"), "primary", "check", function()
		local args = {}
		for i = 1, 3 do
			local _, t = ctl[i].t:GetSelected()
			if t and t ~= "" then
				local h = P.Trim(ctl[i].hint:GetValue())
				args[#args + 1] = { type = t, hint = h ~= "" and h or t, optional = ctl[i].opt:GetValue() }
			end
		end
		onDone(args)
		m:Close()
	end)
	ok:Dock(RIGHT)
	ok:SetWide(S(120))
end

-- ------------------------------------------------------------------ drawing

local function drawBlockHead(a, w, h, col, hov, ghost)
	local fill = Color(col.r, col.g, col.b, ghost and 200 or 235)
	if hov > 0 then fill = P.LerpColor(hov * 0.25, fill, Color(255, 255, 255, 255)) end
	UI.Round(0, 0, w, h, S(6), fill, Color(math.floor(col.r * 0.6), math.floor(col.g * 0.6), math.floor(col.b * 0.6)))
	local box = h - S(8)
	UI.Round(S(4), S(4), box, box, S(5), Color(0, 0, 0, 55))
	local isz = box >= 34 and 32 or 16
	UI.Icon(ICON[a.t] or "bolt", S(4) + math.floor((box - isz) / 2), S(4) + math.floor((box - isz) / 2), isz)
	local label, pill = blockSegs(a)
	local x = S(4) + box + S(10)
	UI.TextShadow(label, "Praetor.SmallB", x, h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if pill then
		surface.SetFont("Praetor.SmallB")
		x = x + surface.GetTextSize(label) + S(8)
		local maxW = w - x - S(10)
		if maxW > S(30) then
			local txt = UI.Fit(pill, "Praetor.Small", maxW - S(16))
			local f = UI.FontFor(txt, "Praetor.Small")
			surface.SetFont(f)
			local pw = surface.GetTextSize(txt) + S(16)
			UI.Round(x, (h - S(24)) / 2, pw, S(24), S(12), Color(0, 0, 0, 80))
			UI.Text(txt, f, x + S(8), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
end

-- ------------------------------------------------------------------ editor

local function editor(right, src, onSaved)
	right:Clear()
	local d = table.Copy(src or { id = "", help = "", def = "admin", icon = "wrench", args = {}, actions = {}, silent = false })
	d.args = d.args or {}
	d.actions = d.actions or {}
	d.icon = d.icon or "wrench"
	local was = src and src.id or nil
	local BH, GAP, CAP, MID, IND = S(44), S(4), S(14), S(28), S(20)
	local E = { boxes = {} }
	local rebuild

	-- ---------------------------------------------------------- top: name, icon, who can use
	local top = vgui.Create("DPanel", right)
	top:Dock(TOP)
	top:SetTall(S(112))
	top:DockMargin(0, 0, 0, S(8))
	top.Paint = function(_, w, h) UI.Round(0, 0, w, h, S(8), C.panel, C.line) end
	top:DockPadding(S(10), S(10), S(10), S(10))
	local row1 = vgui.Create("DPanel", top)
	row1:Dock(TOP)
	row1:SetTall(S(40))
	row1.Paint = nil
	local iconBtn = vgui.Create("DButton", row1)
	iconBtn:SetText("")
	iconBtn:Dock(LEFT)
	iconBtn:SetWide(S(40))
	iconBtn:SetTooltip(P.L("cu_icon"))
	iconBtn.Paint = function(s2, w, h)
		UI.Round(0, 0, w, h, S(6), s2:IsHovered() and C.hover or C.panel2, s2:IsHovered() and C.bronze or C.line)
		local isz = w >= 36 and 32 or 16
		UI.Icon(d.icon, (w - isz) / 2, (h - isz) / 2, isz)
	end
	iconBtn.DoClick = function() UI.PickIcon(d.icon, function(n) d.icon = n end) end
	local name = UI.Entry(row1, "", d.id)
	name:Dock(LEFT)
	name:SetWide(S(180))
	name:DockMargin(S(8), 0, 0, 0)
	name:SetTooltip(P.L("cu_id"))
	name.PerformLayout = function(s2) s2:SetTextInset(S(20), 0) end
	name.PaintOver = function(s2, w, h)
		UI.Text("!", "Praetor.BodyB", S(9), h / 2, C.bronzeL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if s2:GetText() == "" and not s2:HasFocus() then
			UI.Text(P.L("cu_name_ph"), "Praetor.Body", S(20), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	name.OnChange = function(s2)
		local v = s2:GetValue():lower():gsub("[^%w_]", "")
		if v ~= s2:GetValue() then s2:SetValue(v) s2:SetCaretPos(#v) end
		d.id = v
		if E.hat then E.hat:InvalidateLayout() end
	end
	local silent = UI.Toggle(row1, P.L("cu_silent"), "eye", d.silent == true, function(v) d.silent = v end)
	silent:SetTooltip(P.L("cu_silent_d"))
	silent:SetFont("Praetor.Small")
	silent:SizeToLabel(S(10))
	silent:Dock(RIGHT)
	silent:DockMargin(S(8), 0, 0, 0)
	local help = UI.Entry(row1, P.L("cu_help"), d.help or "")
	help:Dock(FILL)
	help:DockMargin(S(8), 0, 0, 0)
	help.OnChange = function(s2) d.help = s2:GetValue() end

	-- who can use it: click the lowest rank; every rank that inherits it is ticked
	local row2 = vgui.Create("DPanel", top)
	row2:Dock(FILL)
	row2:DockMargin(0, S(10), 0, 0)
	row2.Paint = function(_, w, h)
		UI.Text(P.L("cu_who"), "Praetor.SmallB", 0, S(4), C.ivory)
		UI.Text(P.L("cu_who_d"), "Praetor.Tiny", 0, S(24), C.dim)
	end
	local ladder = vgui.Create("DPanel", row2)
	ladder:Dock(FILL)
	ladder:DockMargin(S(170), 0, 0, 0)
	ladder.Paint = nil
	local ranks = P.SortedRanks()
	table.sort(ranks, function(a, b) return (a.immunity or 0) < (b.immunity or 0) end)
	for _, r in ipairs(ranks) do
		local b = vgui.Create("DButton", ladder)
		b:SetText("")
		b:Dock(LEFT)
		b:DockMargin(0, 0, S(4), 0)
		local disp = r.display or r.name
		surface.SetFont("Praetor.Small")
		b:SetWide(surface.GetTextSize(disp) + S(40))
		local style = UI.RankStyle(r)
		local rc = style and style.c1 and Color(style.c1.r, style.c1.g, style.c1.b) or C.muted
		local mine = P.CanManageRank(LocalPlayer(), r.name) or r.name == "user"
		b:SetTooltip(P.L("cu_from", { S = disp }))
		b.Paint = function(s2, w, h)
			local on = d.def == "user" or P.Inherits(r.name, d.def)
			local first = d.def == r.name
			local fill = on and Color(C.laurel.r, C.laurel.g, C.laurel.b, first and 70 or 34) or C.panel2
			UI.Round(0, 0, w, h, S(6), s2:IsHovered() and P.LerpColor(0.4, fill, C.hover) or fill, first and C.laurel or (on and Color(C.laurel.r, C.laurel.g, C.laurel.b, 90) or C.line))
			UI.Icon(on and "check" or "cross", S(6), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 90))
			UI.Round(S(26), h / 2 - S(3), S(6), S(6), S(3), rc)
			UI.Text(disp, "Praetor.Small", S(36), h / 2, on and C.ivory or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function()
			if not mine then P.Toast(P.L("toast_error"), P.L("err_rank_authority"), "warn", 3) return end
			UI.Sound("click")
			d.def = r.name
		end
	end

	-- ---------------------------------------------------------- footer
	local foot = vgui.Create("DPanel", right)
	foot:Dock(BOTTOM)
	foot:SetTall(S(40))
	foot:DockMargin(0, S(8), 0, 0)
	foot.Paint = function(_, w, h)
		local n = countBlocks(d.actions)
		UI.Text(P.L("cu_blocks", { V = n, M = MAX_BLOCKS }), "Praetor.Small", w / 2, h / 2, n >= MAX_BLOCKS and C.crimsonL or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local save = UI.Button(foot, P.L("ui_save"), "primary", "check", function()
		if countBlocks(d.actions) == 0 then P.Toast(P.L("toast_error"), P.L("err_cmd_empty"), "warn", 4) return end
		P.Request("custom_save", { d = d, was = was })
		E.pendingSave = d.id
	end)
	save:Dock(RIGHT)
	save:SetWide(S(140))
	if was then
		local try = UI.Button(foot, P.L("cu_try"), "ghost", "bolt", function() P.RunDialog(was) end)
		try:Dock(RIGHT)
		try:SetWide(S(120))
		try:DockMargin(0, 0, S(6), 0)
		local del = UI.Button(foot, P.L("ui_delete"), "danger", "trash", function()
			UI.Confirm(P.L("ui_delete"), P.L("cu_delete_q", { S = was }), function()
				P.Request("custom_delete", { id = was })
				timer.Simple(0.5, function() P.Request("custom_list") end)
				editor(right, nil, onSaved)
			end, true)
		end)
		del:Dock(LEFT)
		del:SetWide(S(120))
	end
	P.On("custom_saved", function(r)
		if not IsValid(right) or not E.pendingSave or r.id ~= E.pendingSave then return end
		E.pendingSave = nil
		if onSaved then onSaved(r.id) end
		-- reopen it as a saved command (shows "try it" and "delete")
		local keep = table.Copy(d)
		keep.id = r.id
		timer.Simple(0, function() if IsValid(right) then editor(right, keep, onSaved) end end)
	end)

	-- ---------------------------------------------------------- palette
	local pal = vgui.Create("DPanel", right)
	pal:Dock(LEFT)
	pal:SetWide(S(196))
	pal:DockMargin(0, 0, S(8), 0)
	pal.Paint = function(_, w, h)
		local trash = E.drag and not E.drag.isNew and E.drop and E.drop.trash
		UI.Round(0, 0, w, h, S(8), trash and Color(C.crimson.r, C.crimson.g, C.crimson.b, 40) or C.panel, trash and C.crimson or C.line)
		UI.Text(P.L("cu_palette"), "Praetor.BodyB", S(10), S(16), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	pal.PaintOver = function(_, w, h)
		if E.drag and not E.drag.isNew then
			UI.Round(S(6), h / 2 - S(30), w - S(12), S(60), S(8), Color(20, 10, 12, 230), C.crimson)
			UI.Icon("trash", w / 2 - 16, h / 2 - S(22), 32)
			UI.Text(P.L("cu_trash"), "Praetor.Tiny", w / 2, h / 2 + S(18), C.crimsonL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	pal:DockPadding(S(8), S(32), S(4), S(8))
	local psc = UI.Scroll(pal)
	psc:Dock(FILL)
	local owner = P.IsOwner(LocalPlayer())
	for _, cat in ipairs(CATS) do
		if not cat.darkrp or P.IsDarkRP() then
			local hd = vgui.Create("DPanel", psc)
			hd:Dock(TOP)
			hd:SetTall(S(22))
			hd:DockMargin(0, S(4), S(6), S(2))
			local title = P.Upper(P.L("cu_cat_" .. cat.id))
			hd.Paint = function(_, w, h)
				UI.Round(0, h / 2 - S(5), S(10), S(10), S(5), cat.col)
				UI.Text(title, "Praetor.Tiny", S(16), h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			for _, t in ipairs(cat.blocks) do
				if t ~= "console" or owner then
					local b = vgui.Create("DButton", psc)
					b:SetText("")
					b:Dock(TOP)
					b:SetTall(S(32))
					b:DockMargin(0, 0, S(6), S(3))
					b:SetTooltip(P.L("cu_palette_hint"))
					b.hov = 0
					local label = P.L("blk_" .. t)
					b.Paint = function(s2, w, h)
						s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 16)
						UI.Round(0, 0, w, h, S(5), P.LerpColor(s2.hov * 0.25, Color(cat.col.r, cat.col.g, cat.col.b, 225), color_white))
						UI.Icon(ICON[t], S(7), (h - 16) / 2, 16)
						UI.TextShadow(UI.Fit(label, "Praetor.Small", w - S(36)), "Praetor.Small", S(29), h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
					b.OnMousePressed = function(_, code)
						if code == MOUSE_LEFT then E.press = { new = t, x = gui.MouseX(), y = gui.MouseY() } end
					end
				end
			end
		end
	end

	-- ---------------------------------------------------------- script area
	local canvasBg = vgui.Create("DPanel", right)
	canvasBg:Dock(FILL)
	canvasBg.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(8), Color(12, 13, 17), C.line)
		-- dotted grid, like a work table
		surface.SetDrawColor(255, 255, 255, 8)
		local step = S(22)
		for x = step, w - 2, step do
			for y = step, h - 2, step do surface.DrawRect(x, y, 2, 2) end
		end
	end
	canvasBg:DockPadding(S(12), S(12), S(6), S(12))
	local canvas = UI.Scroll(canvasBg)
	canvas:Dock(FILL)
	E.canvas = canvas

	local buildList

	local function blockMenu(list, i)
		local a = list[i]
		local items = {}
		if #(FIELDS[a.t] or {}) > 0 then
			items[#items + 1] = { P.L("cu_edit_block"), "pen", function() editBlock(a, function(n) list[i] = n rebuild() end) end }
		end
		items[#items + 1] = { P.L("cu_duplicate"), "copy", function()
			if countBlocks(d.actions) + countBlocks({ a }) > MAX_BLOCKS then P.Toast(P.L("toast_error"), P.L("cu_full", { V = MAX_BLOCKS }), "warn", 3) return end
			table.insert(list, i + 1, table.Copy(a))
			rebuild()
		end }
		if i > 1 then items[#items + 1] = { P.L("cu_move_up"), nil, function() list[i], list[i - 1] = list[i - 1], list[i] rebuild() end } end
		if i < #list then items[#items + 1] = { P.L("cu_move_down"), nil, function() list[i], list[i + 1] = list[i + 1], list[i] rebuild() end } end
		items[#items + 1] = false
		items[#items + 1] = { P.L("cu_delete_block"), "trash", function() table.remove(list, i) rebuild() end, true }
		UI.Popup(items)
	end

	local function buildBlock(box, list, i, depth)
		local a = list[i]
		local cat = CAT_OF[a.t] or CATS[1]
		local col = cat.col
		local p = vgui.Create("DPanel", box)
		p.block, p.list, p.index = a, list, i
		p.hov = 0
		local isC = a.t == "if" or a.t == "each" or a.t == "repeat"
		local h = BH
		local body, els
		if isC then
			a.body = a.body or {}
			body = buildList(p, a.body, depth + 1)
			body:SetPos(IND, BH + S(2))
			h = BH + S(2) + body:GetTall() + S(4)
			if a.t == "if" then
				a.els = a.els or {}
				p.midY = h
				els = buildList(p, a.els, depth + 1)
				els:SetPos(IND, h + MID + S(2))
				h = h + MID + S(2) + els:GetTall() + S(4)
			end
			h = h + CAP
			p.PerformLayout = function(_, w)
				body:SetWide(w - IND)
				if els then els:SetWide(w - IND) end
			end
		end
		p:SetTall(h)
		p.Paint = function(s2, w, hh)
			local dragging = E.drag and E.drag.block == a
			s2.hov = UI.Lerp(s2.hov, (s2:IsHovered() and not E.drag) and 1 or 0, 16)
			if dragging then surface.SetAlphaMultiplier(0.35) end
			if isC then
				local spine = Color(col.r, col.g, col.b, 235)
				UI.Round(0, 0, IND + S(6), hh, S(6), spine)
				UI.Round(0, hh - CAP, w * 0.45, CAP, S(6), spine)
				if p.midY then
					UI.Round(0, p.midY, w * 0.45, MID, S(6), spine)
					UI.TextShadow(P.L("cu_else"), "Praetor.SmallB", IND + S(8), p.midY + MID / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
			end
			drawBlockHead(a, w, BH, col, s2.hov)
			if dragging then surface.SetAlphaMultiplier(1) end
		end
		p.OnMousePressed = function(_, code)
			if code == MOUSE_LEFT then
				E.press = { block = a, list = list, index = i, x = gui.MouseX(), y = gui.MouseY() }
			elseif code == MOUSE_RIGHT then
				blockMenu(list, i)
			end
		end
		p:SetCursor("hand")
		return p
	end

	buildList = function(parent, list, depth)
		local box = vgui.Create("DPanel", parent)
		box.list = list
		box.depth = depth
		E.boxes[#E.boxes + 1] = box
		local y = 0
		for i = 1, #list do
			local b = buildBlock(box, list, i, depth)
			b:SetPos(0, y)
			y = y + b:GetTall() + GAP
		end
		box:SetTall(#list == 0 and S(34) or (y - GAP))
		box.PerformLayout = function(s2, w)
			for _, c in ipairs(s2:GetChildren()) do c:SetWide(w) end
		end
		box.Paint = function(_, w, h)
			if #list == 0 then
				UI.Round(0, 0, w, h, S(6), Color(255, 255, 255, 6), Color(255, 255, 255, 22))
				UI.Text(P.L("cu_drop_here"), "Praetor.Tiny", S(10), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
		box.PaintOver = function(s2, w, h)
			local dp = E.drop
			if E.drag and dp and dp.box == s2 then
				UI.Round(0, math.Clamp(dp.y - S(2), 0, h - S(4)), w, S(4), S(2), C.bronzeL)
			end
		end
		return box
	end

	-- the "when someone types !name" block on top of the script
	local function buildHat()
		local hat = vgui.Create("DButton", canvas)
		hat:SetText("")
		hat:Dock(TOP)
		hat:SetTall(S(52))
		hat:DockMargin(0, 0, S(6), S(4))
		hat:SetTooltip(P.L("cu_hat_hint"))
		hat.Paint = function(s2, w, h)
			local col = Color(C.bronze.r, C.bronze.g, C.bronze.b, 240)
			if s2:IsHovered() then col = P.LerpColor(0.15, col, color_white) end
			UI.Round(0, 0, w * 0.6, S(16), S(8), col)
			UI.Round(0, S(8), w, h - S(8), S(6), col)
			UI.Round(S(6), S(14), S(32), S(32), S(5), Color(0, 0, 0, 55))
			local isz = S(32) >= 32 and 32 or 16
			UI.Icon(d.icon, S(6) + (S(32) - isz) / 2, S(14) + (S(32) - isz) / 2, isz)
			local x = S(48)
			local label = P.L("cu_hat")
			UI.TextShadow(label, "Praetor.SmallB", x, S(30), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetFont("Praetor.SmallB")
			x = x + surface.GetTextSize(label) + S(8)
			local parts = { "!" .. (d.id ~= "" and d.id or "...") }
			for i, a in ipairs(d.args) do parts[#parts + 1] = (a.optional and "[" or "<") .. (a.hint or a.type) .. (a.optional and "]" or ">") .. "{" .. i .. "}" end
			local txt = UI.Fit(table.concat(parts, "  "), "Praetor.Mono", w - x - S(20))
			surface.SetFont("Praetor.Mono")
			local pw = surface.GetTextSize(txt) + S(16)
			UI.Round(x, S(18), pw, S(24), S(12), Color(0, 0, 0, 90))
			UI.Text(txt, "Praetor.Mono", x + S(8), S(30), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		hat.DoClick = function() editArgs(d, function(args) d.args = args end) end
		E.hat = hat
	end

	rebuild = function()
		if not IsValid(canvas) then return end
		local scroll = canvas:GetVBar():GetScroll()
		canvas:Clear()
		E.boxes = {}
		buildHat()
		local root = buildList(canvas, d.actions, 1)
		root:Dock(TOP)
		root:DockMargin(0, 0, S(6), S(40))
		E.root = root
		canvas:InvalidateLayout(true)
		timer.Simple(0, function() if IsValid(canvas) then canvas:GetVBar():SetScroll(scroll) end end)
	end
	rebuild()

	-- ---------------------------------------------------------- drag and drop
	local function inside(pnl, mx, my, padB)
		if not IsValid(pnl) or not pnl:IsVisible() then return false end
		local x, y = pnl:LocalToScreen(0, 0)
		return mx >= x and mx <= x + pnl:GetWide() and my >= y and my <= y + pnl:GetTall() + (padB or 0), x, y
	end

	local function computeDrop()
		local mx, my = gui.MousePos()
		if inside(pal, mx, my) then return { trash = true } end
		if not inside(canvasBg, mx, my) then return nil end
		local best, bestArea
		for _, box in ipairs(E.boxes) do
			if IsValid(box) and not (E.drag.block and contains(E.drag.block, box.list)) then
				local ok = inside(box, mx, my, S(8))
				if ok then
					local area = box:GetWide() * box:GetTall()
					if not best or area < bestArea then best, bestArea = box, area end
				end
			end
		end
		best = best or E.root
		if not IsValid(best) then return nil end
		local _, by = best:LocalToScreen(0, 0)
		local idx, y = #best.list + 1, best:GetTall()
		for _, c in ipairs(best:GetChildren()) do
			if c.index then
				local _, cy = c:LocalToScreen(0, 0)
				if my < cy + math.min(BH, c:GetTall()) / 2 then
					if c.index < idx then idx = c.index y = cy - by - GAP / 2 end
				end
			end
		end
		if #best.list == 0 then y = best:GetTall() / 2 end
		return { box = best, index = idx, y = y }
	end

	local ghost
	local function startDrag(press)
		if press.new then
			if countBlocks(d.actions) >= MAX_BLOCKS then
				P.Toast(P.L("toast_error"), P.L("cu_full", { V = MAX_BLOCKS }), "warn", 3)
				return
			end
			E.drag = { block = newBlock(press.new), isNew = true }
		else
			E.drag = { block = press.block, list = press.list, index = press.index }
		end
		ghost = vgui.Create("DPanel", right)
		ghost:SetMouseInputEnabled(false)
		ghost:SetSize(S(230), BH)
		ghost:SetZPos(32000)
		local gb = E.drag.block
		local gcol = (CAT_OF[gb.t] or CATS[1]).col
		ghost.Paint = function(_, w, h) drawBlockHead(gb, w, h, gcol, 0, true) end
	end

	local function finishDrag()
		local drag, drop = E.drag, E.drop
		E.drag, E.drop = nil, nil
		if IsValid(ghost) then ghost:Remove() end
		if not drop then rebuild() return end
		if drop.trash then
			if not drag.isNew then
				table.remove(drag.list, drag.index)
				UI.Sound("click")
			end
			rebuild()
			return
		end
		local target, idx = drop.box.list, drop.index
		if not drag.isNew then
			if drag.list == target and drag.index < idx then idx = idx - 1 end
			table.remove(drag.list, drag.index)
		end
		table.insert(target, math.Clamp(idx, 1, #target + 1), drag.block)
		UI.Sound("ok")
		rebuild()
	end

	right.Think = function()
		local down = input.IsMouseDown(MOUSE_LEFT)
		if E.press and not E.drag then
			local press = E.press
			if not down then
				-- a click: palette blocks go to the end, script blocks open their editor
				E.press = nil
				if press.new then
					if countBlocks(d.actions) >= MAX_BLOCKS then P.Toast(P.L("toast_error"), P.L("cu_full", { V = MAX_BLOCKS }), "warn", 3) return end
					table.insert(d.actions, newBlock(press.new))
					UI.Sound("ok")
					rebuild()
					timer.Simple(0.05, function() if IsValid(canvas) then canvas:GetVBar():SetScroll(canvas:GetCanvas():GetTall()) end end)
				elseif press.block then
					local list, i = press.list, press.index
					editBlock(press.block, function(n)
						-- keep the blocks inside (the modal edits a copy)
						n.body, n.els = press.block.body, press.block.els
						list[i] = n
						rebuild()
					end)
				end
			elseif math.abs(gui.MouseX() - press.x) + math.abs(gui.MouseY() - press.y) > S(6) then
				E.press = nil
				startDrag(press)
			end
		end
		if E.drag then
			local mx, my = right:ScreenToLocal(gui.MouseX(), gui.MouseY())
			if IsValid(ghost) then ghost:SetPos(mx - S(20), my - BH / 2) end
			E.drop = computeDrop()
			-- scroll while dragging near the edges
			local _, cy = canvasBg:LocalToScreen(0, 0)
			local gy = gui.MouseY() - cy
			local bar = canvas:GetVBar()
			if gy < S(30) then bar:AddScroll(-FrameTime() * 12)
			elseif gy > canvasBg:GetTall() - S(30) then bar:AddScroll(FrameTime() * 12) end
			if not down then finishDrag() end
		end
	end
	right.OnRemove = function() if IsValid(ghost) then ghost:Remove() end end
end

-- ------------------------------------------------------------------ tab

P.AddTab("custom", {
	cat = "server", icon = "wrench", order = 1,
	can = function() return P.MyHas("manage_commands") end,
	build = function(panel)
		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:SetWide(S(220))
		left:DockMargin(0, 0, S(10), 0)
		left.Paint = nil
		local right = vgui.Create("DPanel", panel)
		right:Dock(FILL)
		right.Paint = nil
		local selected
		local new = UI.Button(left, P.L("cu_new"), "primary", "wrench", function() selected = nil editor(right, nil, function(id) selected = id P.Request("custom_list") end) end)
		new:Dock(TOP)
		new:SetTall(S(38))
		new:DockMargin(0, 0, 0, S(8))
		local api = UI.Label(left, P.L("cu_api"), "Praetor.Tiny", C.dim)
		api:SetWrap(true)
		api:SetAutoStretchVertical(true)
		api:Dock(BOTTOM)
		api:DockMargin(0, S(6), 0, 0)
		local list = UI.Scroll(left)
		list:Dock(FILL)
		local function onSaved(id) selected = id P.Request("custom_list") end
		editor(right, nil, onSaved)

		P.On("custom_list", function(d)
			if not IsValid(list) then return end
			list:Clear()
			table.sort(d.list, function(a, b) return a.id < b.id end)
			if #d.list == 0 then
				local e = vgui.Create("DPanel", list)
				e:Dock(TOP)
				e:SetTall(S(110))
				e.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(6), C.panel, C.line)
					UI.Icon("wrench", w / 2 - 16, S(16), 32, Color(255, 255, 255, 90))
					UI.Text(P.L("cu_none"), "Praetor.SmallB", w / 2, S(62), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("cu_none_hint"), "Praetor.Tiny", w / 2, S(82), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			for _, c in ipairs(d.list) do
				local b = vgui.Create("DButton", list)
				b:SetText("")
				b:Dock(TOP)
				b:SetTall(S(54))
				b:DockMargin(0, 0, S(4), S(4))
				b.hov = 0
				local n = countBlocks(c.actions)
				b.Paint = function(s2, w, h)
					s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 14)
					local sel = selected == c.id
					UI.Round(0, 0, w, h, S(6), sel and Color(C.bronze.r, C.bronze.g, C.bronze.b, 40) or P.LerpColor(s2.hov, C.panel2, C.hover), sel and C.bronze or C.line)
					local box = h - S(14)
					UI.Round(S(7), S(7), box, box, S(6), Color(C.bronze.r, C.bronze.g, C.bronze.b, 45))
					local isz = box >= 34 and 32 or 16
					UI.Icon(c.icon or "wrench", S(7) + (box - isz) / 2, S(7) + (box - isz) / 2, isz)
					local x = S(7) + box + S(10)
					UI.Text(UI.Fit("!" .. c.id, "Praetor.BodyB", w - x - S(6)), "Praetor.BodyB", x, S(8), C.ivory)
					UI.Text(UI.Fit(P.L("cu_from", { S = rankName(c.def) }) .. "  -  " .. P.L("cu_n_blocks", { V = n }), "Praetor.Tiny", w - x - S(6)), "Praetor.Tiny", x, S(32), C.muted)
				end
				b.DoClick = function()
					UI.Sound("click")
					selected = c.id
					editor(right, c, onSaved)
				end
			end
		end)
		P.Request("custom_list")
	end,
})
