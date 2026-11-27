-- Praetor: scoreboard (TAB). Can be turned off in Settings to keep another
-- scoreboard; those can read Praetor's data through ply:GetRankDisplay(),
-- ply:GetRankColor(), ply:GetPraetorTag(), ply:GetPraetorTitle() and CAMI.
--
-- It changes with the gamemode:
--   standard  rank groups (Staff, VIP...), K/D, hours played
--   DarkRP    jobs, salary, wanted / arrested / gun license, money (staff only)
--   TTT       alive / missing / confirmed dead / spectators, karma, score;
--             roles are only shown when this client already knows them
--
-- Layout of a row (left to right, every part has its own fixed space so a very
-- long name never pushes the rest): avatar | name (+ title below) | badges |
-- state icons | columns.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local SB = P.Scoreboard or {}
P.Scoreboard = SB

function SB.Mode()
	if engine.ActiveGamemode() == "terrortown" and ScoreGroup then return "ttt" end
	-- the DarkRP TAB (jobs, police, wanted...) can be turned off in Settings
	if P.IsDarkRP() and P.Setting("scoreboard_darkrp") ~= false then return "darkrp" end
	return "standard"
end

-- dark text on light colours, white on dark ones
local function inkOn(c)
	return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 150 and C.ink or color_white
end

-- DarkRP: is this player police? / the job table of a team
local function isCP(ply) return ply.isCP and ply:isCP() or false end
local function jobOf(t) return RPExtraTeams and RPExtraTeams[t] or nil end

local function rp(ply, var)
	return ply.getDarkRPVar and ply:getDarkRPVar(var) or nil
end

local function money(v)
	v = tonumber(v) or 0
	if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(v) end
	return tostring(v)
end

local function lighten(c, k)
	return Color(math.min(255, c.r + k), math.min(255, c.g + k), math.min(255, c.b + k))
end

-- ------------------------------------------------------------------ TTT helpers

local TTT_GROUPS = {
	[1] = { key = "sb_ttt_terror", col = Color(122, 168, 98), order = 4 },
	[2] = { key = "sb_ttt_mia", col = Color(214, 160, 70), order = 3 },
	[3] = { key = "sb_ttt_dead", col = Color(200, 80, 80), order = 2 },
	[4] = { key = "sb_ttt_spec", col = Color(140, 130, 120), order = 1 },
}

-- the role this client is allowed to know
local function tttRole(ply)
	if not ply.GetRole then return nil end
	if ply.IsDetective and ply:IsDetective() then return "detective", Color(70, 120, 220) end
	if ply.IsTraitor and ply:IsTraitor() then return "traitor", Color(200, 60, 60) end
	if ply.search_result or (ply.GetNWBool and ply:GetNWBool("body_found", false)) then
		if ply.GetRole and ROLE_INNOCENT and ply:GetRole() == ROLE_INNOCENT then return "innocent", Color(90, 170, 80) end
	end
	return nil
end

local function tttKarma() return GetGlobalBool("ttt_karma", false) end

-- health and money of others are only shown where it gives nothing away
local function canSeeDetails(ply)
	if ply == LocalPlayer() then return true end
	if SB.Mode() == "ttt" then
		local me = LocalPlayer()
		return P.MyHas("view_sheet") and (not me.IsTerror or not me:IsTerror())
	end
	return true
end

-- ------------------------------------------------------------------ groups

local function groupKey(ply, mode, grouping)
	if mode == "ttt" then return "t" .. (ScoreGroup(ply) or 4) end
	if grouping == "job" and mode == "darkrp" then return "j" .. ply:Team() end
	if grouping == "group" then
		local g = P.RankGroupOf(ply:GetUserGroup())
		return "g" .. (g and g.id or "")
	end
	if grouping == "rank" then return "r" .. ply:GetUserGroup() end
	return "all"
end

local function buildGroups()
	local mode = SB.Mode()
	local grouping = P.Setting("scoreboard_group") or "group"
	if mode == "darkrp" then grouping = "job" end
	local gOrder = {}
	for i, g in ipairs(P.SortedRankGroups()) do gOrder[g.id] = 1000 - i end
	local groups, byKey = {}, {}
	-- a banned player looking at the ban screen is not on the board
	local everyone = {}
	for _, p in ipairs(player.GetAll()) do if not p:GetNW2Bool("pr_banscreen") then everyone[#everyone + 1] = p end end
	for _, ply in ipairs(everyone) do
		local key = groupKey(ply, mode, grouping)
		local g = byKey[key]
		if not g then
			g = { key = key, players = {} }
			local kind, rest = key:sub(1, 1), key:sub(2)
			if kind == "t" then
				local info = TTT_GROUPS[tonumber(rest)] or TTT_GROUPS[4]
				g.title, g.col, g.order = P.L(info.key), info.col, info.order
			elseif kind == "j" then
				g.title = team.GetName(ply:Team())
				g.col = team.GetColor(ply:Team())
				g.order = -ply:Team()
				g.team = ply:Team()
			elseif kind == "g" then
				local rg = P.RankGroups[rest]
				if rg then
					g.title, g.col, g.icon, g.order, g.staff = rg.name, P.ReadColor(rg.col, C.bronzeL), rg.icon, gOrder[rest] or 0, rg.staff
				else
					g.title, g.col, g.order = P.L("sb_players"), C.muted, -1
				end
			elseif kind == "r" then
				local r = P.RankOf(ply)
				g.style, g.icon = UI.RankStyle(ply:GetUserGroup())
				g.order = (r and r.immunity or 0) + (P.IsOwner(ply) and 1000 or 0)
			else
				g.title = P.L("sb_players")
				g.col = C.bronzeL
				g.order = 0
			end
			byKey[key] = g
			groups[#groups + 1] = g
		end
		g.players[#g.players + 1] = ply
	end
	table.sort(groups, function(a, b) return a.order > b.order end)
	for _, g in ipairs(groups) do
		table.sort(g.players, function(a, b)
			if mode == "ttt" then
				if a:Frags() ~= b:Frags() then return a:Frags() > b:Frags() end
			else
				local aa, bb = P.Authority(a), P.Authority(b)
				if aa ~= bb then return aa > bb end
			end
			return a:Nick():lower() < b:Nick():lower()
		end)
	end
	return groups
end

-- ------------------------------------------------------------------ columns (right to left)

local function columns()
	local mode = SB.Mode()
	local cols = {
		{ "sb_ping", S(56), function(p) return p:Ping(), p:Ping() > 150 and C.crimsonL or C.text end },
	}
	if mode == "ttt" then
		cols[#cols + 1] = { "sb_deaths", S(64), function(p) return p:Deaths() end }
		cols[#cols + 1] = { "sb_score", S(64), function(p) return p:Frags() end }
		if tttKarma() then
			cols[#cols + 1] = { "sb_karma", S(70), function(p) return p.GetBaseKarma and math.Round(p:GetBaseKarma()) or "-" end }
		end
	else
		cols[#cols + 1] = { "sb_kd", S(76), function(p) return p:Frags() .. " / " .. p:Deaths() end }
		cols[#cols + 1] = { "sb_hours", S(76), function(p) return P.FormatHours(P.PlayTime(p)), C.muted, "Praetor.Small" end }
		if mode == "darkrp" then
			-- the job is the group title, so the column shows the salary
			cols[#cols + 1] = { "sb_salary_col", S(96), function(p)
				return money(rp(p, "salary") or 0), C.laurel, "Praetor.SmallB"
			end }
		end
	end
	return cols
end

-- the same measures for the column titles and the rows, so they line up
local STATE_W = 92
local function layout(w)
	local L = { cols = {} }
	local cx = w - S(14)
	for i, c in ipairs(SB.cols or {}) do
		L.cols[i] = cx
		cx = cx - c[2]
	end
	L.stateR = cx - S(4)
	L.stateL = L.stateR - S(STATE_W)
	L.nameX = S(50)
	L.nameW = math.Clamp(math.floor(w * 0.30), S(130), S(250))
	L.badgeX = L.nameX + L.nameW + S(10)
	L.badgeW = math.max(0, L.stateL - L.badgeX - S(6))
	return L
end

-- ------------------------------------------------------------------ row

local ROW_H = 46

local function makeRow(parent, ply, onSelect)
	local row = vgui.Create("DButton", parent)
	row:SetText("")
	row:SetTall(S(ROW_H))
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(4))
	row.ply = ply
	row.anim = 0
	local av = UI.FramedAvatar(row, S(34), ply)
	av:SetPos(S(14), (S(ROW_H) - S(3) - S(34)) / 2)
	av:SetMouseInputEnabled(false)
	row:SetTooltip(ply:Nick())
	row.OnCursorEntered = function() UI.Sound("hover") end
	row.Paint = function(s, w, h)
		if not IsValid(ply) then return end
		local mode = SB.Mode()
		local sel = SB.selected == ply
		s.anim = UI.Lerp(s.anim, (s:IsHovered() or sel) and 1 or 0, 14)
		-- comic row: hard shadow shows on hover / selection, the row lifts a little
		local off = S(3)
		w, h = w - off, h - off
		if s.anim > 0.02 then UI.Round(off, off, w, h, S(12), Color(C.ink.r, C.ink.g, C.ink.b, 210 * s.anim)) end
		local fill = sel and Color(48, 36, 88, 235) or P.LerpColor(s.anim, Color(C.panel2.r, C.panel2.g, C.panel2.b, 205), Color(C.hover.r, C.hover.g, C.hover.b, 230))
		UI.Round(0, 0, w, h, S(12), fill, sel and C.bronze or P.LerpColor(s.anim, C.line, C.lineL))
		local roleName, roleCol
		if mode == "ttt" then roleName, roleCol = tttRole(ply) end
		local stripe = roleCol or (mode == "darkrp" and team.GetColor(ply:Team())) or (ply == LocalPlayer() and C.bronzeL) or nil
		if stripe then UI.Round(S(5), S(8), S(4), h - S(16), S(2), stripe) end

		local L = layout(w)
		-- name and, below it, the title
		local nameCol = lighten(roleCol or ply:GetRankColor(), 30)
		local title = ply:GetPraetorTitle()
		if title then
			UI.Name(ply:Nick(), "Praetor.BodyB", L.nameX, h / 2 - S(9), nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, L.nameW)
			if UI.StyleWidth(title, "Praetor.Tiny") <= L.nameW then
				UI.DrawStyle(title, "Praetor.Tiny", L.nameX, h / 2 + S(11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		else
			UI.Name(ply:Nick(), "Praetor.BodyB", L.nameX, h / 2, nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, L.nameW)
		end

		-- badges: rank (owner badge for owners) then the custom tag, only what fits
		local bh = S(22)
		local bx = L.badgeX
		local style, icon = UI.PlayerRankStyle(ply)
		local bw = UI.BadgeWidth(style, icon, "Praetor.Tag", bh)
		if bw <= L.badgeW then
			UI.Badge(style, icon, "Praetor.Tag", bx, (h - bh) / 2, bh)
			bx = bx + bw + S(6)
		end
		local tag = ply:GetPraetorTag()
		if tag then
			local tw = UI.BadgeWidth(tag, tag.icon, "Praetor.Tag", bh)
			if bx + tw <= L.badgeX + L.badgeW then UI.Badge(tag, tag.icon, "Praetor.Tag", bx, (h - bh) / 2, bh) end
		end

		-- state icons, right aligned in their own slot
		local ix = L.stateR
		local isz = 16
		local iy = (h - isz) / 2
		local function icon(name, colr)
			if ix - isz < L.stateL then return end
			UI.Icon(name, ix - isz, iy, isz, colr)
			ix = ix - isz - S(6)
		end
		if mode == "darkrp" then
			if rp(ply, "Arrested") then icon("jail") end
			-- wanted: the flag blinks
			if rp(ply, "wanted") and math.floor(RealTime() * 3) % 2 == 0 then icon("wanted") elseif rp(ply, "wanted") then ix = ix - isz - S(6) end
			if rp(ply, "HasGunlicense") then icon("permit") end
			if isCP(ply) then icon("police") end
		end
		if P.OnDuty(ply) then icon("shield") end
		if ply:IsSpeaking() then icon("mic", C.laurel) end
		if ply ~= LocalPlayer() and ply:IsMuted() then icon("mic", C.crimsonL) end
		if P.IsAFK(ply) then icon("afk") end

		-- columns
		for i, c in ipairs(SB.cols or {}) do
			local val, vcol, font = c[3](ply)
			font = font or "Praetor.BodyB"
			-- centred in the column, like its title
			UI.Text(UI.Fit(tostring(val), font, c[2] - S(8)), font, L.cols[i] - c[2] / 2, h / 2, vcol or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	row.DoClick = function() onSelect(ply) UI.Sound("click") end
	row.DoRightClick = function() if P.PlayerMenu then P.PlayerMenu(ply) end end
	return row
end

-- ------------------------------------------------------------------ player card

local function bar(x, y, w, h, frac, col)
	UI.Round(x, y, w, h, h / 2, C.bg, C.line)
	frac = math.Clamp(frac, 0, 1)
	local bw = UI.BW()
	if frac > 0 then UI.Round(x + bw, y + bw, math.max(h - bw * 2, (w - bw * 2) * frac), h - bw * 2, (h - bw * 2) / 2, col) end
end

-- 4 small tiles under the name: { label, value, colour }
local function cardTiles(ply)
	local mode = SB.Mode()
	if mode == "darkrp" then
		local mine = ply == LocalPlayer() or P.MyHas("view_sheet")
		local m = rp(ply, "money")
		return {
			{ P.L("sb_job"), rp(ply, "job") or team.GetName(ply:Team()), team.GetColor(ply:Team()) },
			{ P.L("sb_salary"), money(rp(ply, "salary") or 0), C.laurel },
			mine and m and { P.L("sb_money"), money(m), C.bronzeL } or { P.L("sb_kd"), ply:Frags() .. " / " .. ply:Deaths() },
			{ P.L("sb_hours"), P.FormatHours(P.PlayTime(ply)) },
		}
	elseif mode == "ttt" then
		local r, rc = tttRole(ply)
		return {
			{ P.L("sb_role"), r and P.L("role_" .. r) or P.L("sb_role_unknown"), rc or C.muted },
			{ P.L("sb_karma"), (tttKarma() and ply.GetBaseKarma) and math.Round(ply:GetBaseKarma()) or "-" },
			{ P.L("sb_score"), ply:Frags() },
			{ P.L("sb_ping"), ply:Ping() },
		}
	end
	return {
		{ P.L("sb_hours"), P.FormatHours(P.PlayTime(ply)) },
		{ P.L("sb_kd"), ply:Frags() .. " / " .. ply:Deaths() },
		{ P.L("sb_ping"), ply:Ping(), ply:Ping() > 150 and C.crimsonL or nil },
		{ P.L("pl_authority"), P.IsOwner(ply) and P.L("owner") or P.Authority(ply), P.IsOwner(ply) and C.amber or nil },
	}
end

-- small chips for DarkRP states
local function cardChips(ply)
	local out = {}
	if SB.Mode() == "darkrp" then
		if rp(ply, "wanted") then out[#out + 1] = { P.L("sb_wanted"), C.crimsonL } end
		if rp(ply, "Arrested") then out[#out + 1] = { P.L("sb_arrested"), C.amber } end
		if rp(ply, "HasGunlicense") then out[#out + 1] = { P.L("sb_license"), C.laurel } end
	end
	if P.OnDuty(ply) then out[#out + 1] = { P.L("on_duty"), C.bronzeL, "shield" } end
	if P.IsAFK(ply) then out[#out + 1] = { P.AFKLabel(ply), C.amber, "afk" } end
	return out
end

-- puts the whole body in the picture: the camera distance comes from the model
-- height and the panel's real vertical field of view
local function frameModel(mdl)
	local ent = mdl.Entity
	if not IsValid(ent) then return end
	local mn, mx = ent:GetRenderBounds()
	local height = math.Clamp(mx.z - mn.z, 30, 110)
	local midZ = mn.z + height / 2
	local w, h = mdl:GetSize()
	local fov = 30
	mdl:SetFOV(fov)
	local vt = math.tan(math.rad(fov / 2)) * math.min(h / math.max(1, w), 0.75)
	local dist = (height / 2 * 1.16) / math.max(0.05, vt)
	mdl:SetLookAt(Vector(0, 0, midZ))
	mdl:SetCamPos(Vector(dist, 0, midZ + height * 0.06))
end

local function buildCard(card, ply)
	card:Clear()
	card.Think = nil
	if not IsValid(ply) then
		card.Paint = function(_, w, h)
			UI.Tablet(0, 0, w, h, Color(C.panel.r, C.panel.g, C.panel.b, 215), C.line)
			UI.Text(P.L("sb_pick"), "Praetor.Small", w / 2, h / 2, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return
	end
	card.Paint = function(_, w, h) UI.Tablet(0, 0, w, h, Color(C.panel.r, C.panel.g, C.panel.b, 215), C.line) end
	-- a new player in the card: it pops in
	card:SetAlpha(0)
	card:AlphaTo(255, 0.16)

	local cw, ch = card:GetWide() - S(4), card:GetTall() - S(4)
	local pad = S(12)
	local iw = cw - pad * 2

	-- model with a soft floor
	local mdlH = math.Clamp(math.floor(ch * 0.38), S(190), S(290))
	local stage = vgui.Create("DPanel", card)
	stage:SetPos(pad, pad)
	stage:SetSize(iw, mdlH)
	stage.Paint = function(_, w, h)
		-- a little comic stage: dark backdrop, halftone dots and a spotlight on the floor
		local tint = SB.Mode() == "darkrp" and IsValid(ply) and team.GetColor(ply:Team()) or C.bronze
		UI.Round(0, 0, w, h, S(12), C.bg, C.line)
		local step = S(12)
		for gy = S(10), h - S(10), step do
			for gx = S(10) + ((gy / step) % 2) * step / 2, w - S(10), step do
				local k = 1 - math.min(1, math.abs(gx - w / 2) / (w * 0.6))
				local r = math.max(1, math.floor(S(2) * k))
				surface.SetDrawColor(tint.r, tint.g, tint.b, 22 * k)
				surface.DrawRect(gx - r / 2, gy - r / 2, r, r)
			end
		end
		for i = 0, 6 do
			local rw = w * (0.62 - i * 0.07)
			UI.Round(w / 2 - rw / 2, h - S(34) + i * 2, rw, S(16), S(8), Color(tint.r, tint.g, tint.b, 12))
		end
	end
	local mdl = vgui.Create("DModelPanel", stage)
	mdl:Dock(FILL)
	mdl:DockMargin(0, S(4), 0, S(4))
	mdl:SetModel(ply:GetModel())
	mdl:SetMouseInputEnabled(false)
	mdl:SetAmbientLight(Color(70, 74, 90))
	mdl:SetDirectionalLight(BOX_TOP, Color(255, 250, 240))
	mdl:SetDirectionalLight(BOX_FRONT, Color(150, 160, 190))
	local ent = mdl.Entity
	if IsValid(ent) then
		ent:SetSkin(ply:GetSkin())
		for _, bg in ipairs(ply:GetBodyGroups() or {}) do ent:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
		local pc = ply:GetPlayerColor()
		ent.GetPlayerColor = function() return pc end
		local seq = ent:LookupSequence("idle_all_01")
		if seq and seq > 0 then ent:ResetSequence(seq) end
	end
	mdl.PerformLayout = function(s) frameModel(s) end
	local yaw = 20
	mdl.LayoutEntity = function(s, e)
		yaw = yaw + FrameTime() * 22
		e:SetAngles(Angle(0, yaw, 0))
		s:RunAnimation()
	end

	-- name, badges, title, SteamID
	-- each line is placed from the real height of the line above, so a long or
	-- non-Latin name never touches the rank and the SteamID has its own line
	local y = pad + mdlH + S(8)
	local nameH = math.max(UI.FontH("Praetor.H2"), UI.NameH(ply:Nick(), "Praetor.H2"))
	local badgeY = nameH + S(6)
	local lineY = badgeY + S(22) + S(8)
	local lineH = math.max(UI.FontH("Praetor.Small"), UI.FontH("Praetor.Mono"))
	local headH = lineY + lineH + S(4)
	local head = vgui.Create("DPanel", card)
	head:SetPos(pad, y)
	head:SetSize(iw, headH)
	head.Paint = function(_, w, h)
		if not IsValid(ply) then return end
		UI.Name(ply:Nick(), "Praetor.H2", 0, 0, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, w)
		local style, icon = UI.PlayerRankStyle(ply)
		local x = UI.Badge(style, icon, "Praetor.Tag", 0, badgeY, S(22)) + S(6)
		local tag = ply:GetPraetorTag()
		if tag and x + UI.BadgeWidth(tag, tag.icon, "Praetor.Tag", S(22)) <= w then UI.Badge(tag, tag.icon, "Praetor.Tag", x, badgeY, S(22)) end
		local title = ply:GetPraetorTitle()
		local sid = ply:IsBot() and "BOT" or ply:SteamID()
		local cy = lineY + lineH / 2
		if title then
			surface.SetFont("Praetor.Tiny")
			local sw = surface.GetTextSize(sid)
			if UI.StyleWidth(title, "Praetor.Small") <= w - sw - S(14) then
				UI.DrawStyle(title, "Praetor.Small", 0, cy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			UI.Text(sid, "Praetor.Tiny", w, cy, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		else
			UI.Text(sid, "Praetor.Mono", 0, cy, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	y = y + headH

	-- 2 x 2 tiles
	local tiles = vgui.Create("DPanel", card)
	tiles:SetPos(pad, y)
	tiles:SetSize(iw, S(98))
	tiles.Paint = function(_, w, h)
		if not IsValid(ply) then return end
		local tw = (w - S(6)) / 2
		local th = S(46)
		for i, t in ipairs(cardTiles(ply)) do
			local tx = ((i - 1) % 2) * (tw + S(6))
			local ty = math.floor((i - 1) / 2) * (th + S(6))
			UI.Round(tx, ty, tw, th, S(10), C.panel2, C.line)
			UI.Text(P.Upper(t[1]), "Praetor.Tiny", tx + S(10), ty + S(8), C.dim)
			UI.Text(UI.Fit(tostring(t[2]), "Praetor.BodyB", tw - S(20)), "Praetor.BodyB", tx + S(10), ty + S(22), t[3] or C.ivory)
		end
	end
	y = y + S(104)

	-- health / armour and state chips
	local life = vgui.Create("DPanel", card)
	life:SetPos(pad, y)
	life:SetSize(iw, S(40))
	life.Paint = function(_, w, h)
		if not IsValid(ply) then return end
		if canSeeDetails(ply) then
			local hp, mhp = ply:Health(), math.max(1, ply:GetMaxHealth())
			local ar = ply:Armor()
			UI.Icon("heart", 0, 0, 16, C.crimsonL)
			bar(S(22), S(3), w - S(84), S(11), hp / mhp, C.crimsonL)
			UI.Text(hp .. " HP", "Praetor.Tiny", w, S(8), C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			UI.Icon("shield", 0, S(20), 16, C.sky)
			bar(S(22), S(23), w - S(84), S(11), ar / math.max(1, ply.GetMaxArmor and ply:GetMaxArmor() or 100), C.sky)
			UI.Text(ar .. " AR", "Praetor.Tiny", w, S(28), C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	y = y + S(44)
	local chips = cardChips(ply)
	if #chips > 0 then
		local cp = vgui.Create("DPanel", card)
		cp:SetPos(pad, y)
		cp:SetSize(iw, S(22))
		cp.Paint = function(_, w, h)
			local x = 0
			for _, c in ipairs(cardChips(ply)) do
				surface.SetFont("Praetor.Tiny")
				local iw = c[3] and S(18) or 0
				local tw = surface.GetTextSize(c[1]) + S(14) + iw
				if x + tw > w then break end
				UI.Round(x, 0, tw, h, h / 2, c[2], C.ink)
				if c[3] then UI.Icon(c[3], x + S(6), (h - 16) / 2, 16) end
				UI.Text(c[1], "Praetor.Tiny", x + iw + (tw - iw) / 2, h / 2, inkOn(c[2]), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				x = x + tw + S(4)
			end
		end
		y = y + S(28)
	end

	-- copy / profile / mute
	local btns = vgui.Create("DPanel", card)
	btns:SetPos(pad, y)
	btns:SetSize(iw, S(30))
	btns.Paint = nil
	if ply ~= LocalPlayer() then
		local mute = UI.Button(btns, "", ply:IsMuted() and "action_on" or "ghost", "mic", function(b)
			ply:SetMuted(not ply:IsMuted())
			b:Setup("", ply:IsMuted() and "action_on" or "ghost", "mic")
		end)
		mute:Dock(RIGHT)
		mute:SetWide(S(36))
		mute:DockMargin(S(6), 0, 0, 0)
		mute:SetTooltip(P.L("sb_mute_voice"))
	end
	if not ply:IsBot() then
		local copy = UI.Button(btns, P.L("copy_steamid"), "ghost", nil, function()
			SetClipboardText(ply:SteamID())
			P.Toast(P.L("copied"), ply:SteamID(), "ok", 3)
		end)
		copy:SetFont("Praetor.Small")
		copy:Dock(LEFT)
		copy:SetWide(math.floor((iw - (ply ~= LocalPlayer() and S(42) or 0) - S(6)) / 2))
		local prof = UI.Button(btns, P.L("open_profile"), "ghost", nil, function() ply:ShowProfile() end)
		prof:SetFont("Praetor.Small")
		prof:Dock(FILL)
		prof:DockMargin(S(6), 0, 0, 0)
	end
	y = y + S(38)

	-- quick actions, in sections, 2 per line
	local acts = P.QuickActions and P.QuickActions(ply) or {}
	if #acts > 0 and ch - y > S(60) then
		local sc = UI.Scroll(card)
		sc:SetPos(pad, y)
		sc:SetSize(iw, ch - y - pad)
		local function fillActions()
			P.FillQuickActions(sc, ply, { cols = 2, tall = 38, gap = 4, right = 10 })
		end
		fillActions()
		-- god, freeze, mute... change the buttons as soon as the state changes
		local state = P.QuickState(ply)
		card.Think = function()
			if not IsValid(ply) then return end
			local now = P.QuickState(ply)
			if now ~= state then state = now fillActions() end
		end
	end
end

-- ------------------------------------------------------------------ frame

local function fmtTime(secs)
	secs = math.max(0, math.floor(secs))
	local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

function SB.Open()
	if IsValid(SB.frame) then SB.frame:Remove() end
	local w = math.min(ScrW() - S(40), S(1120))
	local h = math.min(ScrH() - S(60), S(720))
	local cardW = math.Clamp(math.floor(w * 0.30), S(290), S(340))
	local f = vgui.Create("DPanel")
	SB.frame = f
	f:SetSize(w, h)
	f:Center()
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	UI.PopIn(f, 0.3)
	SB.cols = columns()
	local HEAD = S(76)
	local OFF = S(6)
	f.Paint = function(_, pw, ph)
		pw, ph = pw - OFF, ph - OFF
		local mode = SB.Mode()
		UI.Window(0, 0, pw, ph, Color(C.bg.r, C.bg.g, C.bg.b, 205))
		local bw = UI.BW()
		draw.RoundedBoxEx(S(14), bw, bw, pw - bw * 2, HEAD - bw, Color(C.panel.r, C.panel.g, C.panel.b, 200), true, true, false, false)
		UI.Rect(bw, HEAD, pw - bw * 2, bw, C.line)
		-- left: server name in the display font with a purple drop
		local name = UI.Fit(GetHostName(), "Praetor.H1", pw * 0.5)
		draw.SimpleText(name, "Praetor.H1", S(22) + S(3), S(12) + S(3), C.bronzeD)
		draw.SimpleText(name, "Praetor.H1", S(22), S(12), C.ivory)
		-- under it: a "DarkRP" / "TTT" pill and the map or the custom line
		local sub = P.Setting("scoreboard_title")
		if not sub or sub == "" then sub = game.GetMap() end
		local sx = S(22)
		if mode ~= "standard" then
			local tag = mode == "darkrp" and "DarkRP" or "TTT"
			surface.SetFont("Praetor.Tiny")
			local tw = surface.GetTextSize(tag) + S(16)
			UI.Round(sx, S(47), tw, S(20), S(10), C.bronze, C.ink)
			UI.Text(tag, "Praetor.Tiny", sx + tw / 2, S(57), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			sx = sx + tw + S(8)
		end
		UI.Text(UI.Fit(sub, "Praetor.Small", pw * 0.45), "Praetor.Small", sx, S(57), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- right: chips
		local staff, police, wanted = 0, 0, 0
		for _, p in ipairs(player.GetAll()) do
			if P.IsStaff(p) then staff = staff + 1 end
			if mode == "darkrp" then
				if isCP(p) then police = police + 1 end
				if rp(p, "wanted") then wanted = wanted + 1 end
			end
		end
		local chips = {
			{ "players", #player.GetAll() .. " / " .. game.MaxPlayers() },
			{ "shield", staff .. " " .. P.L("sb_staff_on") },
		}
		if mode == "darkrp" then
			chips[#chips + 1] = { "helm", police .. " " .. P.L("sb_police_on") }
			if wanted > 0 then chips[#chips + 1] = { "flag", wanted .. " " .. P.L("sb_wanted_on"), C.crimson } end
		else
			chips[#chips + 1] = { "clock", fmtTime(CurTime()) }
		end
		if SB.Mode() == "ttt" and GetGlobalInt then
			local left = GetGlobalInt("ttt_rounds_left", -1)
			if left >= 0 then chips[#chips + 1] = { "bolt", P.L("sb_rounds_left", { V = left }) } end
		end
		local x = pw - S(20)
		surface.SetFont("Praetor.SmallB")
		for i, c in ipairs(chips) do
			local tw = surface.GetTextSize(c[2]) + S(44)
			x = x - tw
			-- each chip bobs a little, one after the other
			local bob = math.floor(math.max(0, math.sin(RealTime() * 2.2 - i * 0.7)) * S(2))
			local cy = S(22) - bob
			UI.Comic(x, cy, tw, S(32), S(16), c[3] or C.panel2, c[3] and C.ink or C.line, S(3))
			UI.Icon(c[1], x + S(10), cy + (S(32) - 20) / 2, 20)
			UI.Text(c[2], "Praetor.SmallB", x + S(34), cy + S(16), c[3] and color_white or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			x = x - S(10)
		end
	end

	local listX = S(16)
	local listW = w - OFF - cardW - S(16) * 2 - S(12)

	-- column titles, measured like the rows
	local list
	local colHead = vgui.Create("DPanel", f)
	colHead:SetPos(listX, HEAD + S(10))
	colHead:SetSize(listW, S(20))
	colHead.Paint = function(_, cw2, chh)
		local rw = (IsValid(list) and list:GetCanvas():GetWide() or cw2) - S(3)
		local L = layout(rw)
		UI.Text(P.Upper(P.L("col_name")), "Praetor.Tiny", L.nameX, chh / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.Upper(P.L("col_rank")), "Praetor.Tiny", L.badgeX, chh / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		for i, c in ipairs(SB.cols or {}) do
			UI.Text(UI.Fit(P.Upper(P.L(c[1])), "Praetor.Tiny", c[2] - S(4)), "Praetor.Tiny", L.cols[i] - c[2] / 2, chh / 2, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	list = UI.Scroll(f)
	list:SetPos(listX, HEAD + S(34))
	list:SetSize(listW, h - OFF - HEAD - S(34) - S(16))

	local card = vgui.Create("DPanel", f)
	card:SetPos(w - OFF - cardW - S(16), HEAD + S(12))
	card:SetSize(cardW, h - OFF - HEAD - S(28))

	local function pick(ply)
		SB.selected = ply
		buildCard(card, ply)
	end

	local signature
	local first = true
	local function rebuild()
		SB.cols = columns()
		list:Clear()
		local n = 0
		for gi, g in ipairs(buildGroups()) do
			local head = vgui.Create("DPanel", list)
			head:Dock(TOP)
			head:SetTall(S(30))
			head:DockMargin(0, gi == 1 and 0 or S(10), 0, S(4))
			head.Paint = function(_, hw, hh)
				local x = 0
				if g.style then
					x = UI.Badge(g.style, g.icon, "Praetor.Tag", 0, (hh - S(22)) / 2, S(22)) + S(8)
				else
					local col = g.col or C.bronzeL
					local t = P.Upper(g.title or "")
					surface.SetFont("Praetor.SmallB")
					local pw2 = surface.GetTextSize(t) + S(20) + (g.icon and S(22) or 0)
					local ph2 = hh - S(4)
					UI.Comic(0, 0, pw2, ph2, ph2 / 2, col, C.ink, S(2))
					x = S(10)
					if g.icon then UI.Icon(g.icon, x, (ph2 - 16) / 2, 16) x = x + S(22) end
					UI.Text(t, "Praetor.SmallB", x, ph2 / 2, inkOn(col), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					x = pw2 + S(8)
				end
				-- count; DarkRP jobs with a limit show "2 / 4"
				local n = tostring(#g.players)
				local job = g.team and jobOf(g.team)
				if job and (tonumber(job.max) or 0) > 0 then n = n .. " / " .. job.max end
				surface.SetFont("Praetor.Tiny")
				local nw = surface.GetTextSize(n) + S(14)
				UI.Round(x, (hh - S(4) - S(18)) / 2, nw, S(18), S(9), C.panel3, C.line)
				UI.Text(n, "Praetor.Tiny", x + nw / 2, (hh - S(4)) / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				UI.Rect(x + nw + S(8), (hh - S(4)) / 2, hw - x - nw - S(8), 2, Color(C.line.r, C.line.g, C.line.b, 150))
			end
			for _, ply in ipairs(g.players) do
				local r = makeRow(list, ply, pick)
				-- the first time the TAB opens, the rows drop in one after another
				n = n + 1
				if first and n <= 18 then
					r:SetAlpha(0)
					r:AlphaTo(255, 0.16, n * 0.025)
				end
			end
		end
		first = false
	end

	-- the list is rebuilt when someone joins, leaves, changes rank / job or (TTT) group
	local function sig()
		local mode = SB.Mode()
		local t = {}
		for _, p in ipairs(player.GetAll()) do
			local extra = mode == "ttt" and (ScoreGroup(p) or 0) or ""
			t[#t + 1] = p:EntIndex() .. ":" .. p:GetUserGroup() .. ":" .. p:Team() .. ":" .. extra .. (p:GetNW2Bool("pr_banscreen") and ":b" or "")
		end
		return table.concat(t, ",")
	end

	local nextCheck = 0
	f.Think = function()
		if RealTime() < nextCheck then return end
		nextCheck = RealTime() + 0.25
		local s = sig()
		if s ~= signature then
			signature = s
			rebuild()
			if SB.selected and not IsValid(SB.selected) then pick(LocalPlayer()) end
		end
	end
	-- never an empty card: the last player picked, or yourself
	pick(IsValid(SB.selected) and SB.selected or LocalPlayer())
	UI.Sound("open")
	SB.MusicPlay()
end

function SB.Close()
	-- quick fade out (the cursor goes away at once)
	local f = SB.frame
	SB.frame = nil
	if IsValid(f) then
		f:SetMouseInputEnabled(false)
		f:SetKeyboardInputEnabled(false)
		f.Think = nil
		f:AlphaTo(0, 0.1, 0, function() if IsValid(f) then f:Remove() end end)
	end
	CloseDermaMenus()
	SB.MusicPause()
end

-- ------------------------------------------------------------------ music (TAB, menu, F4)
-- One music for the three screens: it fades in when one of them opens, keeps
-- playing while you go from one to another and fades out when the last closes.
-- It starts where it stopped last time.
local musicVar = CreateClientConVar("praetor_tab_music", "1", true, false, "Music while the Praetor TAB is open (0 = off)", 0, 1)
CreateClientConVar("praetor_menu_music", "1", true, false, "Music while the Praetor menu is open (0 = off)", 0, 1)
CreateClientConVar("praetor_f4_music", "1", true, false, "Music while the Praetor F4 menu is open (0 = off)", 0, 1)
local station, stationSrc, fade, want = nil, nil, 0, false
local owners = {}
-- screen -> server setting + player option
local MUSIC = {
	tab = { "tab_music", "praetor_tab_music" },
	menu = { "menu_music", "praetor_menu_music" },
	f4 = { "f4_music", "praetor_f4_music" },
}

local function musicSrc()
	local u = P.Trim(tostring(P.Setting("tab_music_url") or ""))
	if u:find("^https?://") then return u end
	return "sound/praetor/music/tab.mp3"
end

local function musicVol() return math.Clamp((tonumber(P.Setting("tab_music_vol")) or 30) / 100, 0, 1) end

local function allowed(who)
	local m = MUSIC[who]
	if not m or not P.Setting(m[1]) then return false end
	local cv = GetConVar(m[2])
	return not cv or cv:GetBool()
end

local function update()
	want = false
	for who in pairs(owners) do
		if allowed(who) then want = true break end
	end
	if not want then return end
	local src = musicSrc()
	if IsValid(station) and stationSrc == src then
		if station:GetState() ~= GMOD_CHANNEL_PLAYING then station:Play() end
		return
	end
	if stationSrc == src and not IsValid(station) then return end -- still loading
	if IsValid(station) then station:Stop() end
	station, stationSrc = nil, src
	local cb = function(ch)
		if not IsValid(ch) then stationSrc = nil return end
		if stationSrc ~= src then ch:Stop() return end
		station = ch
		ch:EnableLooping(true)
		ch:SetVolume(0)
		if want then ch:Play() else ch:Pause() end
	end
	if src:find("^https?://") then sound.PlayURL(src, "noblock noplay", cb) else sound.PlayFile(src, "noplay", cb) end
end

-- P.Music("menu", true) when a screen opens, P.Music("menu", false) when it closes
function P.Music(who, on)
	owners[who] = on and true or nil
	update()
end

function SB.MusicPlay() P.Music("tab", true) end
function SB.MusicPause() P.Music("tab", false) end

hook.Add("Think", "Praetor.TabMusic", function()
	-- a screen that went away without saying so (removed by another addon)
	if owners.menu and not IsValid(P.Menu) then P.Music("menu", false) end
	if owners.f4 and not (P.F4 and IsValid(P.F4.frame)) then P.Music("f4", false) end
	if not IsValid(station) then return end
	local target = want and musicVol() or 0
	fade = math.Approach(fade, target, FrameTime() * 1.2)
	station:SetVolume(fade)
	if not want and fade <= 0 and station:GetState() == GMOD_CHANNEL_PLAYING then station:Pause() end
end)

for _, m in pairs(MUSIC) do
	cvars.AddChangeCallback(m[2], function() update() end, "Praetor.Music")
end

-- DarkRP comes with FAdmin, whose scoreboard hook also answers TAB; hooks run in
-- no fixed order, so sometimes FAdmin's board opened instead of this one. While
-- Praetor's scoreboard is on, TAB is answered here before any other hook.
local guarded
local function installTabGuard()
	if hook.Call == guarded then return end
	local orig = hook.Call
	guarded = function(name, gm, ...)
		if (name == "ScoreboardShow" or name == "ScoreboardHide") and P.Setting and P.Setting("scoreboard") then
			local ok, err = pcall(name == "ScoreboardShow" and SB.Open or SB.Close)
			if ok then return true end
			ErrorNoHalt("[Praetor] scoreboard: " .. tostring(err) .. "\n")
		end
		return orig(name, gm, ...)
	end
	hook.Call = guarded
end
installTabGuard()
hook.Add("InitPostEntity", "Praetor.TabGuard", installTabGuard)
timer.Create("Praetor.TabGuard", 30, 0, installTabGuard)

hook.Add("ScoreboardShow", "Praetor.Scoreboard", function()
	if not P.Setting("scoreboard") then return end
	SB.Open()
	return true
end)

hook.Add("ScoreboardHide", "Praetor.Scoreboard", function()
	if not P.Setting("scoreboard") then return end
	SB.Close()
	return true
end)
