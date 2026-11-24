-- Praetor: running commands from the client - console with autocomplete, key
-- shortcuts, the "run command" dialog and the quick actions on player cards.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

-- ------------------------------------------------------------------ console

local function complete(cmd, line)
	local out = {}
	local args = P.SplitArgs(line)
	local endsSpace = line:sub(-1) == " "
	if #args == 0 or (#args == 1 and not endsSpace) then
		local want = (args[1] or ""):lower()
		local ids = {}
		for id in pairs(P.ServerCmds) do
			if id:sub(1, #want) == want and P.CanRunId(id) then ids[#ids + 1] = id end
		end
		table.sort(ids)
		for _, id in ipairs(ids) do out[#out + 1] = cmd .. " " .. id end
		return out
	end
	-- complete player names for player arguments
	local def = P.ServerCmds[(args[1] or ""):lower()]
	if not def then return out end
	local idx = endsSpace and #args or (#args - 1)
	local a = def.args[idx]
	local cur = endsSpace and "" or (args[#args] or ""):lower()
	local base = cmd .. " " .. table.concat(args, " ", 1, endsSpace and #args or (#args - 1))
	if a and (a.t == "player" or a.t == "offline") then
		for _, p in ipairs(player.GetAll()) do
			if p:Nick():lower():find(cur, 1, true) then out[#out + 1] = base .. " \"" .. p:Nick() .. "\"" end
		end
	elseif a and a.t == "rank" then
		for name in pairs(P.Ranks) do if name:find(cur, 1, true) then out[#out + 1] = base .. " " .. name end end
	elseif a then
		out[#out + 1] = base .. " <" .. (a.h or a.t) .. ">"
	end
	return out
end

local function runLine(_, cmd, args, line)
	if #args == 0 then P.OpenMenu() return end
	P.Request("run_line", { line = line, silent = cmd == "praetor_silent" or nil })
end

concommand.Add("praetor", runLine, complete, "Praetor: run a command (praetor kick bob spam)")
concommand.Add("pr", runLine, complete, "Praetor: short alias (bind g \"pr god\")")
concommand.Add("praetor_silent", runLine, complete, "Praetor: run a command without the broadcast")
concommand.Add("praetor_menu", function() P.OpenMenu() end)

-- ------------------------------------------------------------------ key shortcuts

P.Binds = P.Binds or {}
local BIND_FILE = "praetor_binds.json"

function P.LoadBinds()
	local raw = file.Read(BIND_FILE, "DATA")
	P.Binds = raw and util.JSONToTable(raw) or {}
end

function P.SaveBinds()
	file.Write(BIND_FILE, util.TableToJSON(P.Binds, true))
end

P.LoadBinds()

local held = {}
hook.Add("Think", "Praetor.Binds", function()
	if #P.Binds == 0 then return end
	local blocked = vgui.GetKeyboardFocus() ~= nil or gui.IsGameUIVisible() or gui.IsConsoleVisible() or P.ChatIsOpen
	for i, b in ipairs(P.Binds) do
		local key = tonumber(b.key)
		if key then
			local down = input.IsKeyDown(key)
			if down and not held[i] and not blocked then
				P.Request("run_line", { line = b.line, silent = b.silent or nil })
			end
			held[i] = down
		end
	end
end)

-- ------------------------------------------------------------------ run dialog

local function argLabel(a)
	return P.L("arg_" .. (a.h or a.t), nil, a.h or a.t)
end

-- Opens a dialog to fill the arguments of command `id`. `target`: SteamID64 to pre-fill.
function P.RunDialog(id, target, presets)
	local def = P.ServerCmds[id]
	if not def then return end
	presets = presets or {}
	if #def.args == 0 then P.RunCmd(id, {}) return end

	local hgt = S(140)
	for _, a in ipairs(def.args) do hgt = hgt + ((a.t == "duration") and S(100) or S(62)) end
	if P.MyHas("silent") then hgt = hgt + S(48) end
	hgt = hgt + S(24)
	local m = UI.Modal("!" .. id, S(480), hgt)
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)
	-- header: the command's icon, name, category and what it does
	local help = P.L("h_" .. id, nil, def.help or "")
	local tint = P.CatTint and P.CatTint(def.cat) or C.bronze
	local icon = P.CmdIcon(id)
	local catName = P.L("cat_" .. (def.cat or "addons"), nil, def.cat or "addons")
	local hd = vgui.Create("DPanel", sc)
	hd:Dock(TOP)
	hd:DockMargin(0, 0, 0, S(8))
	local lines = help ~= "" and UI.Wrap(help, "Praetor.Small", S(480) - S(110)) or {}
	hd:SetTall(math.max(S(56), S(32) + #lines * S(16)))
	hd.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(6), C.panel2, C.line)
		local box = S(42)
		UI.Round(S(8), S(7), box, box, S(6), Color(tint.r, tint.g, tint.b, 55))
		local isz = UI.IconSize(S(30))
		if isz > box then isz = 16 end
		UI.Icon(icon, S(8) + (box - isz) / 2, S(7) + (box - isz) / 2, isz)
		local x = S(8) + box + S(12)
		local cat = P.Upper(catName)
		surface.SetFont("Praetor.Tiny")
		local cw = surface.GetTextSize(cat)
		local u = UI.Fit(UI.Usage and UI.Usage(def) or ("!" .. id), "Praetor.BodyB", w - x - cw - S(20))
		UI.Text(u, "Praetor.BodyB", x, S(8), C.ivory)
		surface.SetFont("Praetor.BodyB")
		local uw = surface.GetTextSize(u)
		UI.Text(cat, "Praetor.Tiny", x + uw + S(8), S(12), tint)
		for i, l in ipairs(lines) do UI.Text(l, "Praetor.Small", x, S(28) + (i - 1) * S(16), C.muted) end
	end

	local getters = {}
	for i, a in ipairs(def.args) do
		local l = UI.Label(sc, argLabel(a) .. (a.o and ("  (" .. P.L("optional") .. ")") or ""), "Praetor.SmallB", C.muted)
		l:Dock(TOP)
		l:DockMargin(0, S(4), 0, S(3))
		local pre = presets[i]
		if pre == nil and i == 1 and target and (a.t == "player" or a.t == "offline") then pre = target end
		local ctl
		if a.t == "player" or a.t == "offline" then
			ctl = UI.PlayerPick(sc, pre)
			getters[i] = function() return ctl:GetValue() end
		elseif a.t == "duration" then
			ctl = UI.DurationField(sc, pre or (a.d ~= nil and tostring(a.d) or ""))
			getters[i] = function() return ctl:GetValue() end
		elseif a.t == "rank" then
			local opts = {}
			for _, r in ipairs(P.SortedRanks()) do
				if P.CanManageRank(LocalPlayer(), r.name) then opts[#opts + 1] = { r.name, r.display or r.name } end
			end
			ctl = UI.Combo(sc, opts, pre)
			if not pre and opts[1] then ctl:ChooseOptionID(1) end
			getters[i] = function() local _, d = ctl:GetSelected() return d or "" end
		elseif a.t == "job" then
			local opts = {}
			for _, j in pairs(RPExtraTeams or {}) do opts[#opts + 1] = { j.command, j.name } end
			table.sort(opts, function(x, y) return x[2] < y[2] end)
			ctl = UI.Combo(sc, opts, pre)
			if not pre and opts[1] then ctl:ChooseOptionID(1) end
			getters[i] = function() local _, d = ctl:GetSelected() return d or "" end
		elseif a.t == "choice" and a.opt then
			local opts = {}
			for _, o in ipairs(a.opt) do opts[#opts + 1] = { o, o } end
			ctl = UI.Combo(sc, opts, pre or a.opt[1])
			getters[i] = function() local _, d = ctl:GetSelected() return d or "" end
		elseif a.t == "bool" then
			ctl = UI.Combo(sc, { { "1", P.L("yes") }, { "0", P.L("no") } }, pre or "1")
			getters[i] = function() local _, d = ctl:GetSelected() return d or "1" end
		elseif a.t == "map" then
			local opts = {}
			for _, f in ipairs(file.Find("maps/*.bsp", "GAME")) do opts[#opts + 1] = { f:gsub("%.bsp$", ""), (f:gsub("%.bsp$", "")) } end
			ctl = UI.Combo(sc, opts, pre or game.GetMap())
			getters[i] = function() local _, d = ctl:GetSelected() return d or "" end
		else
			ctl = UI.Entry(sc, a.h or "", pre or (a.d ~= nil and tostring(a.d) or ""))
			if a.t == "number" then ctl:SetNumeric(true) end
			getters[i] = function() return ctl:GetValue() end
		end
		ctl:Dock(TOP)
	end

	local silent
	if P.MyHas("silent") then
		silent = UI.Switch(sc, P.L("run_silent"), nil, false)
		silent:Dock(TOP)
		silent:DockMargin(0, S(8), 0, 0)
	end

	local run = UI.Button(m.foot, P.L("run"), "primary", "bolt", function()
		local args = {}
		for i = 1, #def.args do args[i] = P.Trim(getters[i]() or "") end
		-- drop trailing empty optional values so the server uses its defaults
		for i = #args, 1, -1 do
			if args[i] == "" and def.args[i].o then args[i] = nil else break end
		end
		P.RunCmd(id, args, silent and silent:GetValue())
		m:Close()
	end)
	run:Dock(RIGHT)
	run:SetWide(S(140))
	local cancel = UI.Button(m.foot, P.L("ui_cancel"), "ghost", nil, function() m:Close() end)
	cancel:Dock(RIGHT)
	cancel:SetWide(S(110))
	cancel:DockMargin(0, 0, S(8), 0)
	return m
end

-- ------------------------------------------------------------------ quick actions

local function can(id) return P.CanRunId(id) end

-- Ban with quick lengths
function P.BanDialog(ply, sid, name)
	sid = sid or (IsValid(ply) and ply:SteamID64())
	name = name or (IsValid(ply) and ply:Nick()) or sid
	UI.Form(P.L("qa_ban") .. ": " .. tostring(name), {
		{ "min", "duration", P.L("arg_time"), "1d" },
		{ "reason", "text", P.L("arg_reason"), "", P.L("arg_reason") },
	}, function(v)
		if v.min == nil then P.Toast(P.L("toast_error"), P.L("err_duration", { S = "?" }), "warn") return false end
		if IsValid(ply) then
			P.RunCmd("ban", { sid, v.min == 0 and "0" or (v.min .. ""), v.reason })
		else
			P.Request("ban_add", { sid = sid, min = v.min, reason = v.reason, name = name })
		end
	end, P.L("qa_ban"))
end

-- List of actions for a player, used by the players tab, scoreboard and right-click menus.
-- Each action has a group (grp) so the players tab can show them in sections,
-- and toggles carry their current state (on) so their button lights up.
P.QuickGroups = { "move", "state", "life", "punish", "manage" }

-- the networked states the quick actions depend on (the players tab rebuilds its
-- buttons when this string changes)
local STATE_KEYS = { "pr_frozen", "pr_muted", "pr_gagged", "pr_jailed", "pr_god", "pr_cloak" }
function P.QuickState(ply)
	if not IsValid(ply) then return "" end
	local out = {}
	for i, k in ipairs(STATE_KEYS) do out[i] = ply:GetNW2Bool(k) and "1" or "0" end
	return table.concat(out)
end

function P.QuickActions(ply)
	if not IsValid(ply) then return {} end
	local sid = ply:SteamID64() or ("$" .. ply:UserID())
	local t = ply:IsBot() and ("$" .. ply:UserID()) or sid
	local me = ply == LocalPlayer()
	local list = {}
	local grp = "move"
	local function add(id, label, icon, fn, danger, on)
		if can(id) then
			list[#list + 1] = { label = label, icon = P.CmdIcon(id) or icon, fn = fn or function() P.RunCmd(id, { t }) end, danger = danger, id = id, grp = grp, on = on }
		end
	end
	-- on/off pair: the label says what the click does, `on` says the current state
	local function toggle(key, onId, offId, onLabel, offLabel, icon, fnOff)
		if ply:GetNW2Bool(key) then add(offId, P.L(offLabel), icon, nil, false, true)
		else add(onId, P.L(onLabel), icon, fnOff, false, false) end
	end

	if not me then
		add("goto", P.L("qa_goto"), "flag")
		add("bring", P.L("qa_bring"), "anchor")
		add("spectate", P.L("qa_spectate"), "eye")
	end
	add("return", P.L("qa_return"), "anchor")

	grp = "state"
	toggle("pr_god", "god", "ungod", "qa_god", "qa_ungod", "shield")
	toggle("pr_frozen", "freeze", "unfreeze", "qa_freeze", "qa_unfreeze", "gear")
	toggle("pr_muted", "mute", "unmute", "qa_mute", "qa_unmute", "music")
	toggle("pr_gagged", "gag", "ungag", "qa_gag", "qa_ungag", "mic")
	toggle("pr_jailed", "jail", "unjail", "qa_jail", "qa_unjail", "key", function()
		UI.Form(P.L("qa_jail") .. ": " .. ply:Nick(), {
			{ "min", "duration", P.L("arg_time"), "10m" },
			{ "reason", "text", P.L("arg_reason"), "" },
		}, function(v) P.RunCmd("jail", { t, tostring(v.min or 5), v.reason }) end)
	end)

	grp = "life"
	add("respawn", P.L("qa_respawn"), "heart")
	add("hp", P.L("qa_heal"), "heart", function() P.RunCmd("hp", { t, "100" }) end)
	add("strip", P.L("qa_strip"), "wrench", nil, true)
	add("clearprops", P.L("qa_clearprops"), "hammer", nil, true)

	grp = "punish"
	add("slay", P.L("qa_slay"), "skull", nil, true)
	if not ply:IsBot() then
		add("warn", P.L("qa_warn"), "bolt", function()
			UI.Form(P.L("qa_warn") .. ": " .. ply:Nick(), { { "reason", "text", P.L("arg_reason"), "" } }, function(v)
				if P.Trim(v.reason) == "" then return false end
				P.RunCmd("warn", { t, v.reason })
			end)
		end, true)
	end
	add("kick", P.L("qa_kick"), "flag", function()
		UI.Form(P.L("qa_kick") .. ": " .. ply:Nick(), { { "reason", "text", P.L("arg_reason"), "" } }, function(v) P.RunCmd("kick", { t, v.reason }) end)
	end, true)
	if not ply:IsBot() then add("ban", P.L("qa_ban"), "skull", function() P.BanDialog(ply) end, true) end
	if P.IsDarkRP() then
		add("rpdemote", P.L("qa_demote"), "badge", nil, true)
		add("jobban", P.L("qa_jobban"), "badge", function()
			UI.Form(P.L("qa_jobban") .. ": " .. ply:Nick(), {
				{ "job", "job", P.L("arg_job"), nil, nil, true },
				{ "min", "duration", P.L("arg_time"), "1d" },
				{ "reason", "text", P.L("arg_reason"), "" },
			}, function(v) P.RunCmd("jobban", { sid, v.job or "", tostring(v.min or 0), v.reason }) end)
		end, true)
	end

	grp = "manage"
	if not ply:IsBot() then
		add("setrank", P.L("qa_setrank"), "crown", function() P.RunDialog("setrank", sid) end)
		if not me then add("screengrab", P.L("qa_screen"), "image") end
		if P.MyHas("view_sheet") then
			list[#list + 1] = { label = P.L("qa_sheet"), icon = "scroll", grp = grp, fn = function() P.OpenMenu("users", { sid = sid }) end }
		end
	end
	return list
end

-- ------------------------------------------------------------------ action tiles
-- A quick action drawn as a tile: the command's own icon in a tinted square
-- (colour of its section), the label next to it. Used by the players tab, the
-- scoreboard card and the user sheet.
P.QuickGroupStyle = {
	move = { col = "sky", icon = "portal" },
	state = { col = "bronze", icon = "gear" },
	life = { col = "laurel", icon = "heart" },
	punish = { col = "crimson", icon = "hammer" },
	manage = { col = "amber", icon = "crown" },
}

do
	local PANEL = {}

	function PANEL:Init()
		self:SetText("")
		self.hov = 0
	end

	function PANEL:Setup(a, tint)
		self.a = a
		self.tint = tint or C.bronze
		self:SetTooltip(a.label)
		return self
	end

	function PANEL:OnCursorEntered() UI.Sound("click") end

	function PANEL:DoClick()
		UI.Sound("ok")
		if self.a and self.a.fn then self.a.fn() end
	end

	function PANEL:Paint(w, h)
		local a = self.a
		if not a then return true end
		self.hov = UI.Lerp(self.hov, self:IsHovered() and 1 or 0, 14)
		local down = self:IsDown() and 1 or 0
		local t = self.tint
		local border = a.danger and P.LerpColor(self.hov, C.line, C.crimson) or P.LerpColor(self.hov, C.line, t)
		local fill = P.LerpColor(self.hov, C.panel2, C.hover)
		if a.on then
			fill = P.LerpColor(self.hov, Color(t.r, t.g, t.b, 34), Color(t.r, t.g, t.b, 58))
			border = t
		end
		UI.Round(0, down, w, h - down, S(6), fill, border)
		-- icon square
		local box = h - S(10)
		local bx, by = S(5), S(5) + down
		UI.Round(bx, by, box, box, S(5), Color(t.r, t.g, t.b, 38 + 30 * self.hov))
		local isz = UI.IconSize(box - S(6))
		if isz > box then isz = 16 end
		UI.Icon(a.icon, bx + math.floor((box - isz) / 2), by + math.floor((box - isz) / 2), isz)
		-- label
		local x = bx + box + S(8)
		local col = a.danger and C.crimsonL or (a.on and C.ivory or C.text)
		UI.Text(UI.Fit(a.label, "Praetor.SmallB", w - x - S(14)), "Praetor.SmallB", x, h / 2 + down, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- active state: small lit dot
		if a.on then UI.Round(w - S(11), S(6) + down, S(6), S(6), S(3), C.laurel) end
		return true
	end

	vgui.Register("PraetorActionTile", PANEL, "DButton")
end

-- Fills a scroll panel with the quick actions of `ply`, in sections.
-- opts: { cols = 3, tall = 44, gap = 6, right = 0 }
function P.FillQuickActions(sc, ply, opts)
	opts = opts or {}
	sc:Clear()
	local groups = {}
	for _, a in ipairs(P.QuickActions(ply)) do
		local g = a.grp or "manage"
		groups[g] = groups[g] or {}
		table.insert(groups[g], a)
	end
	local gap = S(opts.gap or 6)
	for _, g in ipairs(P.QuickGroups) do
		local list = groups[g]
		if list then
			local st = P.QuickGroupStyle[g] or {}
			local tint = C[st.col or "bronze"] or C.bronze
			local hd = vgui.Create("DPanel", sc)
			hd:Dock(TOP)
			hd:SetTall(S(22))
			hd:DockMargin(0, S(4), S(opts.right or 0), S(3))
			local label = P.Upper(P.L("qa_g_" .. g))
			hd.Paint = function(_, w, h)
				UI.Round(0, h / 2 - S(5), S(3), S(10), 1, tint)
				UI.Text(label, "Praetor.Tiny", S(9), h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				surface.SetFont("Praetor.Tiny")
				local tw = surface.GetTextSize(label)
				UI.Text(#list, "Praetor.Tiny", S(9) + tw + S(6), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Rect(S(9) + tw + S(22), math.floor(h / 2), w - tw - S(31), 1, C.line)
			end
			local grid = vgui.Create("DIconLayout", sc)
			grid:Dock(TOP)
			grid:SetSpaceX(gap)
			grid:SetSpaceY(gap)
			grid:DockMargin(0, 0, S(opts.right or 0), S(4))
			for _, a in ipairs(list) do
				local b = grid:Add("PraetorActionTile")
				b:Setup(a, tint)
				b:SetTall(S(opts.tall or 44))
			end
			grid.PerformLayout = function(s2, w, h)
				local cols = opts.cols or 3
				while cols > 1 and (w - gap * (cols - 1)) / cols < S(130) do cols = cols - 1 end
				local bw = math.floor((w - gap * (cols - 1)) / cols)
				for _, c in ipairs(s2:GetChildren()) do c:SetWide(bw) end
				baseclass.Get("DIconLayout").PerformLayout(s2, w, h)
			end
		end
	end
end

-- Right-click menu with every quick action.
function P.PlayerMenu(ply)
	local items = {}
	for _, a in ipairs(P.QuickActions(ply)) do items[#items + 1] = { a.label, a.icon, a.fn, a.danger } end
	if IsValid(ply) and not ply:IsBot() then
		items[#items + 1] = false
		items[#items + 1] = { P.L("copy_steamid"), nil, function() SetClipboardText(ply:SteamID()) P.Toast(P.L("copied"), ply:SteamID(), "ok", 3) end }
		items[#items + 1] = { P.L("copy_steamid64"), nil, function() SetClipboardText(ply:SteamID64()) P.Toast(P.L("copied"), ply:SteamID64(), "ok", 3) end }
		items[#items + 1] = { P.L("open_profile"), nil, function() ply:ShowProfile() end }
	end
	if #items > 0 then UI.Popup(items) end
end
