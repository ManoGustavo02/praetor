-- Praetor menu: Promotions. "After 10 hours played, Player becomes Member."
-- A ladder of rules (from rank -> to rank after X hours), each one on / off,
-- and on the right the players closest to their next step.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local function rules()
	local list = {}
	for name, r in pairs(P.Ranks) do
		if r.promote and P.Ranks[r.promote.from] then
			list[#list + 1] = { to = name, from = r.promote.from, hours = r.promote.hours, off = r.promote.off == true }
		end
	end
	-- the ladder reads from the bottom rank up
	table.sort(list, function(a, b)
		local ia, ib = P.Ranks[a.from].immunity or 0, P.Ranks[b.from].immunity or 0
		if ia ~= ib then return ia < ib end
		return a.hours < b.hours
	end)
	return list
end

local function editRule(rule)
	local fields = {
		{ "from", "rank", P.L("pm_from"), rule and rule.from or "user" },
		{ "to", "rank", P.L("pm_to_rank"), rule and rule.to or nil },
		{ "hours", "duration", P.L("pm_hours"), rule and (math.floor(rule.hours * 60 + 0.5) .. "m") or "10h" },
	}
	UI.Form(rule and P.L("pm_edit") or P.L("pm_new"), fields, function(v)
		local hours = (tonumber(v.hours) or 0) / 60
		if not v.to or not v.from or v.to == v.from then P.Toast(P.L("tab_promote"), P.L("err_promo_from"), "warn") return false end
		if hours * 60 < 1 then P.Toast(P.L("tab_promote"), P.L("err_promo_hours"), "warn") return false end
		-- the rule moved to another rank: take it off the old one
		if rule and rule.to ~= v.to then P.Request("promote_set", { rank = rule.to, del = true }) end
		P.Request("promote_set", { rank = v.to, from = v.from, hours = hours, off = rule and rule.off or nil })
	end, P.L("ui_save"))
end

P.AddTab("promote", {
	cat = "management", icon = "laurel", order = 2.5,
	can = function() return P.MyHas("manage_promote") or P.MyHas("manage_ranks") end,
	build = function(panel)
		local near = {}

		-- right: who is closest to the next rank
		local side = vgui.Create("DPanel", panel)
		side:Dock(RIGHT)
		side:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.36), S(260), S(360)))
		side:DockMargin(S(10), 0, 0, 0)
		side:DockPadding(S(10), S(54), S(10), S(10))
		side.Paint = function(_, w, h)
			UI.Round(0, 0, w, h, S(8), C.panel, C.line)
			UI.Text(P.L("pm_near"), "Praetor.BodyB", S(12), S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(UI.Fit(P.L("pm_near_d"), "Praetor.Tiny", w - S(24)), "Praetor.Tiny", S(12), S(40), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local nsc = UI.Scroll(side)
		nsc:Dock(FILL)
		local function fillNear()
			if not IsValid(nsc) then return end
			nsc:Clear()
			if #near == 0 then
				local e = vgui.Create("DPanel", nsc)
				e:Dock(TOP)
				e:SetTall(S(80))
				e.Paint = function(_, w, h) UI.Text(P.L("pm_near_none"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
				return
			end
			for _, n in ipairs(near) do
				local row = vgui.Create("DButton", nsc)
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(58))
				row:DockMargin(0, 0, S(4), S(4))
				row:SetTooltip(P.L("alt_open"))
				row.Paint = function(s, w, h)
					UI.Round(0, 0, w, h, S(6), s:IsHovered() and C.hover or C.panel2, C.line)
					local ply = player.GetBySteamID64(n.sid)
					local av = S(34)
					UI.DrawAvatar(n.sid, IsValid(ply) and ply or nil, S(8), (h - av) / 2, av, 255, IsValid(ply) and UI.AvatarFrame(ply) or nil, n.name)
					local x = S(8) + av + S(10)
					local style, icon = UI.RankStyle(n.rank)
					local bw = UI.BadgeWidth(style, icon, "Praetor.Tiny", S(18))
					UI.Name(n.name, "Praetor.SmallB", x, S(15), n.off and C.text or C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - x - bw - S(16))
					UI.Badge(style, icon, "Praetor.Tiny", w - S(8), S(6), S(18), 255, TEXT_ALIGN_RIGHT)
					local frac = math.Clamp(n.have / math.max(1, n.need), 0, 1)
					local bw2 = w - x - S(10)
					UI.Round(x, h - S(12), bw2, S(5), S(2), Color(255, 255, 255, 16))
					UI.Round(x, h - S(12), math.max(S(4), bw2 * frac), S(5), S(2), frac >= 1 and C.laurel or C.bronze)
					local left = math.max(0, n.need - n.have)
					UI.Text(left > 0 and P.L("pm_left", { V = P.FormatHours(left) }) or P.L("pm_ready"), "Praetor.Tiny", w - S(10), h - S(23), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					if n.off then UI.Text(P.L("pm_offline"), "Praetor.Tiny", x, h - S(23), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
				end
				row.DoClick = function() P.OpenMenu("users", { sid = n.sid }) end
			end
		end

		-- left: the ladder
		local bar = UI.Toolbar(panel, S(36))
		local add = UI.Button(bar, P.L("pm_new"), "primary", "laurel", function() editRule(nil) end)
		add:Dock(LEFT)
		add:SetWide(S(190))
		local note = vgui.Create("DPanel", bar)
		note:Dock(FILL)
		note:DockMargin(S(12), 0, 0, 0)
		note.Paint = function(_, w, h)
			local lines = UI.Wrap(P.L("pm_intro"), "Praetor.Tiny", w)
			for i, l in ipairs(lines) do
				if i > 2 then break end
				UI.Text(l, "Praetor.Tiny", 0, h / 2 + (i - (math.min(#lines, 2) + 1) / 2) * S(14), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		local function fill()
			if not IsValid(sc) then return end
			sc:Clear()
			local list = rules()
			if #list == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(200))
				e.Paint = function(_, w, h)
					UI.Round(w / 2 - S(32), h / 2 - S(70), S(64), S(64), S(32), C.panel2)
					UI.Icon("laurel", w / 2 - 16, h / 2 - S(38) - 16, 32)
					UI.Text(P.L("pm_none"), "Praetor.BodyB", w / 2, h / 2 + S(16), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("pm_none_d"), "Praetor.Tiny", w / 2, h / 2 + S(38), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			for i, rule in ipairs(list) do
				local can = P.CanManageRank(LocalPlayer(), rule.to) and P.CanManageRank(LocalPlayer(), rule.from)
				local card = vgui.Create("DPanel", sc)
				card:Dock(TOP)
				card:SetTall(S(64))
				card:DockMargin(0, 0, S(4), S(4))
				card.Paint = function(s, w, h)
					local a = rule.off and 120 or 255
					UI.Round(0, 0, w, h, S(8), C.panel, rule.off and C.line or Color(C.laurel.r, C.laurel.g, C.laurel.b, 90))
					-- step number
					UI.Round(S(12), (h - S(30)) / 2, S(30), S(30), S(15), rule.off and C.panel2 or Color(C.laurel.r, C.laurel.g, C.laurel.b, 50))
					UI.Text(tostring(i), "Praetor.SmallB", S(27), h / 2, rule.off and C.dim or C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					local x = S(56)
					local fs, fi = UI.RankStyle(rule.from)
					x = x + UI.Badge(fs, fi, "Praetor.Small", x, (h - S(24)) / 2, S(24), a) + S(12)
					-- arrow with the hours on it
					local txt = P.L("pm_after", { V = P.FormatDuration(rule.hours * 60) })
					surface.SetFont("Praetor.Tiny")
					local tw = surface.GetTextSize(txt)
					local aw = math.max(S(90), tw + S(24))
					UI.Text(txt, "Praetor.Tiny", x + aw / 2, h / 2 - S(9), Color(C.muted.r, C.muted.g, C.muted.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Rect(x, h / 2 + S(2), aw - S(8), S(2), Color(C.lineL.r, C.lineL.g, C.lineL.b, a))
					draw.NoTexture()
					surface.SetDrawColor(C.lineL.r, C.lineL.g, C.lineL.b, a)
					surface.DrawPoly({ { x = x + aw - S(10), y = h / 2 - S(3) }, { x = x + aw, y = h / 2 + S(3) }, { x = x + aw - S(10), y = h / 2 + S(9) } })
					x = x + aw + S(10)
					local ts, ti = UI.RankStyle(rule.to)
					UI.Badge(ts, ti, "Praetor.Small", x, (h - S(24)) / 2, S(24), a)
				end
				if can then
					local del = UI.Button(card, "", "subtle", "trash", function()
						UI.Confirm(P.L("pm_delete"), P.L("pm_delete_q"), function() P.Request("promote_set", { rank = rule.to, del = true }) end)
					end)
					del:SetTooltip(P.L("ui_delete"))
					local edit = UI.Button(card, "", "ghost", "pen", function() editRule(rule) end)
					edit:SetTooltip(P.L("pm_edit"))
					local tog = UI.Toggle(card, rule.off and P.L("pm_off") or P.L("pm_on"), nil, not rule.off, function(v)
						P.Request("promote_set", { rank = rule.to, from = rule.from, hours = rule.hours, off = not v })
					end)
					tog:SetFont("Praetor.Small")
					card.PerformLayout = function(s, w, h)
						del:SetSize(S(34), S(32))
						del:SetPos(w - S(46), (h - S(32)) / 2)
						edit:SetSize(S(34), S(32))
						edit:SetPos(w - S(86), (h - S(32)) / 2)
						tog:SetSize(S(120), S(32))
						tog:SetPos(w - S(214), (h - S(32)) / 2)
					end
				end
			end
		end
		fill()
		fillNear()

		hook.Add("Praetor.RanksUpdated", panel, function()
			fill()
			P.Request("promote_near")
		end)
		P.On("promote_near", function(d)
			near = istable(d.list) and d.list or {}
			fillNear()
		end)
		P.Request("promote_near")
	end,
})
