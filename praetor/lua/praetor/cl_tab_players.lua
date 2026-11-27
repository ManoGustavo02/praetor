-- Praetor menu: online players with their quick actions.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local selected

-- info rows of the selected player
local function infoRows(ply)
	local rows = {
		{ P.L("pl_health"), ply:Health() .. " / " .. ply:GetMaxHealth() },
		{ P.L("pl_armor"), tostring(ply:Armor()) },
		{ P.L("sb_hours"), P.FormatHours(P.PlayTime(ply)) },
		{ P.L("sb_ping"), tostring(ply:Ping()) },
		{ P.L("pl_authority"), P.IsOwner(ply) and P.L("owner") or tostring(P.Authority(ply)) },
	}
	if P.IsDarkRP() then rows[#rows + 1] = { P.L("sb_job"), ply.getDarkRPVar and ply:getDarkRPVar("job") or team.GetName(ply:Team()) } end
	local flags = {}
	for _, f in ipairs({ { "pr_jailed", "pl_jailed" }, { "pr_muted", "pl_muted" }, { "pr_gagged", "pl_gagged" }, { "pr_frozen", "pl_frozen" }, { "pr_god", "pl_god" }, { "pr_cloak", "pl_cloaked" }, { "pr_afk", "pl_afk" }, { "pr_duty", "on_duty" } }) do
		if ply:GetNW2Bool(f[1]) then flags[#flags + 1] = P.L(f[2]) end
	end
	if #flags > 0 then rows[#rows + 1] = { P.L("pl_state"), table.concat(flags, ", "), C.bronzeL } end
	return rows
end

local HEAD_H = S(100)
local ROW_H = S(22)

-- the quick action tiles, in sections (move, state, life, punish, manage)
local function buildActions(sc, ply)
	P.FillQuickActions(sc, ply, { cols = 3, tall = 44, gap = 6 })
end

local function detail(panel, ply)
	panel:Clear()
	panel.Think = nil
	if not IsValid(ply) then
		panel.Paint = function(_, w, h)
			UI.Tablet(0, 0, w, h, C.panel, C.line)
			UI.Text(P.L("pl_pick"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return
	end
	local rowCount = #infoRows(ply)
	panel.Paint = function(_, w, h)
		UI.Tablet(0, 0, w, h, C.panel, C.line)
		if not IsValid(ply) then return end
		UI.Name(ply:Nick(), "Praetor.H2", S(84), S(10), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, w - S(96))
		local style, icon = UI.PlayerRankStyle(ply)
		local by = math.min(S(10) + UI.NameH(ply:Nick(), "Praetor.H2") + S(5), HEAD_H - S(22) - UI.FontH("Praetor.Mono") - S(10))
		local x = S(84) + UI.Badge(style, icon, "Praetor.Tag", S(84), by, S(22)) + S(6)
		local tag = ply:GetPraetorTag()
		if tag and x + UI.BadgeWidth(tag, tag.icon, "Praetor.Tag", S(22)) <= w - S(12) then UI.Badge(tag, tag.icon, "Praetor.Tag", x, by, S(22)) end
		UI.Text(ply:IsBot() and "BOT" or ply:SteamID(), "Praetor.Mono", S(84), by + S(22) + S(5), C.dim)
		UI.Rule(S(12), HEAD_H, w - S(24), C.line)
		for i, r in ipairs(infoRows(ply)) do
			local y = HEAD_H + S(8) + (i - 1) * ROW_H
			UI.Text(r[1], "Praetor.Small", S(14), y, C.muted)
			UI.Text(UI.Fit(r[2], "Praetor.SmallB", w - S(140)), "Praetor.SmallB", w - S(14), y, r[3] or C.text, TEXT_ALIGN_RIGHT)
		end
		local ry = HEAD_H + S(14) + rowCount * ROW_H
		UI.Rule(S(12), ry, w - S(24), C.line)
	end
	local av = UI.FramedAvatar(panel, S(60), ply)
	av:SetPos(S(12), S(12))

	local sc = UI.Scroll(panel)
	sc:Dock(FILL)
	local function margin()
		sc:DockMargin(S(12), HEAD_H + S(20) + rowCount * ROW_H, S(12), S(10))
	end
	margin()
	buildActions(sc, ply)

	-- buttons and info follow the player's state live (god, freeze, mute...)
	local state = P.QuickState(ply)
	panel.Think = function()
		if not IsValid(ply) then return end
		local now = P.QuickState(ply)
		if now ~= state then
			state = now
			buildActions(sc, ply)
		end
		local n = #infoRows(ply)
		if n ~= rowCount then
			rowCount = n
			margin()
			panel:InvalidateLayout()
		end
	end
end

P.AddTab("players", {
	cat = "overview", icon = "players", order = 1,
	can = function() return P.MyHas("menu") end,
	build = function(panel)
		local stats = vgui.Create("DPanel", panel)
		stats:Dock(TOP)
		stats:SetTall(S(60))
		stats:DockMargin(0, 0, 0, S(10))
		stats.Paint = nil
		local tiles = {
			{ P.L("st_online"), function() return #player.GetAll() .. " / " .. game.MaxPlayers() end, "players" },
			{ P.L("st_staff"), function()
				local n = 0
				for _, p in ipairs(player.GetAll()) do if P.IsStaff(p) then n = n + 1 end end
				return n
			end, "shield" },
			{ P.L("st_reports"), function() return P.OpenReports or 0 end, "flag" },
			{ P.L("st_map"), function() return game.GetMap() end, "anchor" },
		}
		for _, t in ipairs(tiles) do
			local s = UI.Stat(stats, t[1], t[2], t[3])
			s:Dock(LEFT)
			s:DockMargin(0, 0, S(8), 0)
		end
		stats.PerformLayout = function(_, w)
			local tw = math.floor((w - S(8) * 3) / 4)
			for _, c in ipairs(stats:GetChildren()) do c:SetWide(tw) end
		end

		local right = vgui.Create("DPanel", panel)
		right:Dock(RIGHT)
		right:SetWide(math.max(S(360), math.floor(panel:GetParent():GetWide() * 0.42)))
		right:DockMargin(S(10), 0, 0, 0)

		local left = vgui.Create("DPanel", panel)
		left:Dock(FILL)
		left.Paint = nil
		local bar = UI.Toolbar(left)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("ui_search")), nil, FILL)
		search:DockMargin(0, 0, 0, 0)

		local tbl = UI.Table(left, {
			{ P.L("col_name"), 0.5 }, { P.L("col_rank"), 0.3 }, { P.L("sb_hours"), 70, TEXT_ALIGN_RIGHT }, { P.L("sb_ping"), 50, TEXT_ALIGN_RIGHT },
		})
		tbl:Dock(FILL)

		local function fill()
			tbl:Clear()
			local q = search:GetValue():lower()
			local plys = player.GetAll()
			table.sort(plys, function(a, b)
				local aa, bb = P.Authority(a), P.Authority(b)
				if aa ~= bb then return aa > bb end
				return a:Nick():lower() < b:Nick():lower()
			end)
			for _, p in ipairs(plys) do
				if q == "" or p:Nick():lower():find(q, 1, true) or (p:SteamID() or ""):lower():find(q, 1, true) then
					tbl:AddRow({
						function(x, _, w, h)
							if not IsValid(p) then return end
							UI.Name(p:Nick(), "Praetor.BodyB", x, h / 2, selected == p and C.bronzeL or C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - S(8))
						end,
						function(x, _, w, h)
							if not IsValid(p) then return end
							local style, icon = UI.PlayerRankStyle(p)
							UI.Badge(style, icon, "Praetor.Tiny", x, (h - S(20)) / 2, S(20))
						end,
						function(x, _, w, h) if IsValid(p) then UI.Text(P.FormatHours(P.PlayTime(p)), "Praetor.Small", x + w - S(6), h / 2, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end end,
						function(x, _, w, h) if IsValid(p) then UI.Text(p:Ping(), "Praetor.Small", x + w - S(6), h / 2, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end end,
					}, {
						accent = selected == p and C.bronze or nil,
						onClick = function() selected = p detail(right, p) end,
						onRight = function() P.PlayerMenu(p) end,
					})
				end
			end
		end
		search.OnChange = fill
		fill()
		-- never an empty panel: the player picked before, or yourself
		if not IsValid(selected) then selected = LocalPlayer() end
		detail(right, selected)

		local count = #player.GetAll()
		panel.Think = function()
			if #player.GetAll() ~= count then
				count = #player.GetAll()
				fill()
				if selected and not IsValid(selected) then selected = LocalPlayer() detail(right, selected) end
			end
		end
	end,
})
