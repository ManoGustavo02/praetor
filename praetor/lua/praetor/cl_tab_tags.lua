-- Praetor menu: custom tags ("Rei do Macete") and titles, given by SteamID so
-- they also work for players who are offline.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local DEFAULT = { text = "Rei do Macete", c1 = { r = 255, g = 196, b = 80 }, c2 = { r = 230, g = 90, b = 60 }, fx = "flow" }

local SAMPLE_TAG = { text = "VIP", c1 = { r = 255, g = 196, b = 80 }, c2 = { r = 230, g = 90, b = 60 }, fx = "shine", icon = "star" }
local function sampleTitle() return { text = P.L("tg_sample_title"), c1 = { r = 150, g = 200, b = 255 }, c2 = { r = 190, g = 140, b = 255 }, fx = "flow" } end

-- "what is what": a chat tag and a title side by side, with where each one shows
local function explainCard(sc)
	local card = vgui.Create("DPanel", sc)
	card:Dock(TOP)
	card:DockMargin(0, 0, 0, S(4))
	card.l1, card.l2 = {}, {}
	card.PerformLayout = function(s, w)
		local colW = math.floor((w - S(12)) / 2) - S(24)
		s.l1 = UI.Wrap(P.L("tg_tag_where"), "Praetor.Small", colW)
		s.l2 = UI.Wrap(P.L("tg_title_where"), "Praetor.Small", colW)
		local h = S(46) + math.max(#s.l1, #s.l2) * S(17) + S(10)
		if s:GetTall() ~= h then s:SetTall(h) end
	end
	card.Paint = function(s, w, h)
		local colW = math.floor((w - S(12)) / 2)
		for i = 1, 2 do
			local x = (i - 1) * (colW + S(12))
			UI.Round(x, 0, colW, h, S(8), C.panel, C.line)
			UI.Text(P.L(i == 1 and "tg_kind_tag" or "tg_kind_title"), "Praetor.BodyB", x + S(12), S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if i == 1 then
				local bw = UI.BadgeWidth(SAMPLE_TAG, SAMPLE_TAG.icon, "Praetor.Tag", S(22))
				UI.Badge(SAMPLE_TAG, SAMPLE_TAG.icon, "Praetor.Tag", x + colW - S(12) - bw, S(9), S(22))
			else
				UI.DrawStyle(sampleTitle(), "Praetor.SmallB", x + colW - S(12), S(20), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			UI.Rect(x + S(12), S(38), colW - S(24), 1, C.line)
			for j, l in ipairs(i == 1 and s.l1 or s.l2) do
				UI.Text(l, "Praetor.Small", x + S(12), S(46) + (j - 1) * S(17), C.muted)
			end
		end
	end
	return card
end

-- a text that wraps and grows with the panel
local function wrapLabel(sc, getText, col)
	local l = vgui.Create("DPanel", sc)
	l:Dock(TOP)
	l.lines = {}
	l.PerformLayout = function(s, w)
		s.lines = UI.Wrap(getText(), "Praetor.Small", w - S(4))
		local h = #s.lines * S(17) + S(4)
		if s:GetTall() ~= h then s:SetTall(h) end
	end
	l.Paint = function(s)
		for i, line in ipairs(s.lines) do UI.Text(line, "Praetor.Small", S(2), S(2) + (i - 1) * S(17), col or C.muted) end
	end
	return l
end

local function giveBlock(sc, data)
	explainCard(sc)

	-- 1. who
	UI.Section(sc, P.L("tg_step1"), P.L("tg_give_sub"))
	local who = UI.PlayerPick(sc, data.sid or "")
	who:Dock(TOP)

	-- 2. tag or title (and where it will show)
	UI.Section(sc, P.L("tg_step2"), P.L("tg_step2_sub"))
	local kindOpts = {}
	if P.MyHas("manage_tags") then kindOpts[#kindOpts + 1] = { "tag", P.L("tg_kind_tag") } end
	if P.MyHas("manage_titles") then kindOpts[#kindOpts + 1] = { "title", P.L("tg_kind_title") } end
	local curKind = kindOpts[1] and kindOpts[1][1]
	local kind = UI.Combo(sc, kindOpts, curKind)
	kind:Dock(TOP)
	local desc = wrapLabel(sc, function() return P.L(curKind == "title" and "tg_kind_title_d" or "tg_kind_tag_d") end)
	desc:DockMargin(0, S(6), 0, 0)

	-- ready titles, only when giving a title
	local presets = P.TitlePresets or {}
	local presetRow
	local style
	if #presets > 0 then
		local opts = {}
		for i, st in ipairs(presets) do opts[#opts + 1] = { i, tostring(st.text or "?") } end
		presetRow = UI.Combo(sc, opts, nil, function(i)
			if presets[i] and IsValid(style) then style:Setup(table.Copy(presets[i]), { icon = true, maxLen = 24 }) end
		end)
		presetRow:Dock(TOP)
		presetRow:DockMargin(0, S(6), 0, 0)
		presetRow:SetValue(P.L("tg_from_preset"))
	end
	local function kindChanged()
		desc:InvalidateLayout(true)
		if IsValid(presetRow) then
			presetRow:SetVisible(curKind == "title")
			presetRow:GetParent():InvalidateLayout()
		end
	end
	kind.OnSelect = function(_, _, _, v) curKind = v kindChanged() end
	kindChanged()

	-- 3. the look
	UI.Section(sc, P.L("tg_step3"), P.L("tg_step3_sub"))
	style = UI.StyleEdit(sc, data.style or DEFAULT, { icon = true, maxLen = 24 })
	style:Dock(TOP)
	style:SetTall(S(170))

	-- preview: the chat line (tag) or the name over the head (title)
	local preview = vgui.Create("DPanel", sc)
	preview:Dock(TOP)
	preview:SetTall(S(64))
	preview:DockMargin(0, S(8), 0, 0)
	preview.Paint = function(_, w, h)
		UI.Round(0, 0, w, h, S(8), C.bg, C.line)
		local st = style:GetStyle()
		local pl = who.GetPlayer and who:GetPlayer()
		local name = IsValid(pl) and pl:Nick() or P.L("tg_sample_name")
		local label = P.L(curKind == "title" and "tg_preview_head" or "tg_preview_chat")
		surface.SetFont("Praetor.Tiny")
		local lw = surface.GetTextSize(label)
		UI.Text(label, "Praetor.Tiny", w - S(10), S(12), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		if curKind == "title" then
			local cx = math.floor((w - lw - S(20)) / 2)
			UI.Text(UI.Fit(name, "Praetor.BodyB", w - lw - S(40)), "Praetor.BodyB", cx, h / 2 - S(9), C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			UI.DrawStyle(st, "Praetor.Small", cx, h / 2 + S(11), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			local x = S(12)
			local bh = S(20)
			if st and st.text and st.text ~= "" then
				x = x + UI.BadgeWidth(st, st.icon, "Praetor.Tag", bh) + S(6)
				UI.Badge(st, st.icon, "Praetor.Tag", S(12), (h - bh) / 2 + S(4), bh)
			end
			surface.SetFont("Praetor.Chat")
			local nm = UI.Fit(name, "Praetor.ChatB", math.max(S(40), (w - x) * 0.4))
			surface.SetFont("Praetor.ChatB")
			local nw = surface.GetTextSize(nm .. ": ")
			UI.Text(nm .. ": ", "Praetor.ChatB", x, h / 2 + S(4), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Text(UI.Fit(P.L("tg_sample_msg"), "Praetor.Chat", math.max(0, w - x - nw - S(12))), "Praetor.Chat", x + nw, h / 2 + S(4), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local btns = vgui.Create("DPanel", sc)
	btns:Dock(TOP)
	btns:SetTall(S(36))
	btns:DockMargin(0, S(8), 0, 0)
	btns.Paint = nil
	local function send(clear)
		local sid = who:GetValue()
		if P.Trim(sid) == "" or not curKind then P.Toast(P.L("toast_error"), P.L("err_steamid"), "warn", 4) return end
		P.Request(curKind == "title" and "title_set" or "tag_set", { sid = sid, style = (not clear) and style:GetStyle() or nil })
		timer.Simple(0.4, function() if IsValid(P.Menu) and P.Menu.current == "tags" then P.Request("tags_list") end end)
	end
	local give = UI.Button(btns, P.L("tg_apply"), "primary", "star", function() send(false) end)
	give:Dock(LEFT)
	give:SetWide(S(150))
	local clr = UI.Button(btns, P.L("tg_clear"), "ghost", nil, function() send(true) end)
	clr:Dock(LEFT)
	clr:SetWide(S(130))
	clr:DockMargin(S(6), 0, 0, 0)
	return who, style
end

local function presetsBlock(sc)
	UI.Section(sc, P.L("tg_presets"), P.L("tg_presets_sub"))
	local list = table.Copy(P.TitlePresets or {})
	local holder = vgui.Create("DPanel", sc)
	holder:Dock(TOP)
	holder.Paint = nil
	local function rebuild()
		holder:Clear()
		holder:SetTall(math.max(1, #list) * S(34) + S(42))
		for i, st in ipairs(list) do
			local row = vgui.Create("DPanel", holder)
			row:Dock(TOP)
			row:SetTall(S(32))
			row:DockMargin(0, 0, 0, S(2))
			row.Paint = function(_, w, h)
				UI.Rect(0, 0, w, h, C.panel2)
				UI.DrawStyle(st, "Praetor.BodyB", S(10), h / 2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local del = UI.Button(row, "x", "ghost", nil, function() table.remove(list, i) rebuild() end)
			del:Dock(RIGHT)
			del:SetWide(S(30))
			local ed = UI.Button(row, P.L("ui_edit"), "ghost", nil, function()
				UI.Form(P.L("ui_edit"), { { "s", "style", P.L("rk_style"), st, { maxLen = 32 } } }, function(v) list[i] = v.s rebuild() end)
			end)
			ed:Dock(RIGHT)
			ed:SetWide(S(80))
		end
		local bar = vgui.Create("DPanel", holder)
		bar:Dock(TOP)
		bar:SetTall(S(34))
		bar:DockMargin(0, S(6), 0, 0)
		bar.Paint = nil
		local add = UI.Button(bar, P.L("tg_preset_add"), "ghost", "star", function()
			UI.Form(P.L("tg_preset_add"), { { "s", "style", P.L("rk_style"), { text = "Veteran", c1 = { r = 150, g = 200, b = 255 }, fx = "none" }, { maxLen = 32 } } }, function(v)
				if #list < 40 then list[#list + 1] = v.s rebuild() end
			end)
		end)
		add:Dock(LEFT)
		add:SetWide(S(170))
		local save = UI.Button(bar, P.L("ui_save"), "primary", nil, function() P.Request("titles_save", { list = list }) end)
		save:Dock(LEFT)
		save:SetWide(S(120))
		save:DockMargin(S(6), 0, 0, 0)
	end
	rebuild()
end

P.AddTab("tags", {
	cat = "management", icon = "star", order = 3,
	can = function() return P.MyHas("manage_tags") or P.MyHas("manage_titles") or P.MyHas("self_tag") end,
	build = function(panel, data)
		local right = vgui.Create("DPanel", panel)
		right:Dock(RIGHT)
		right:SetWide(math.floor(panel:GetParent():GetWide() * 0.42))
		right:DockMargin(S(12), 0, 0, 0)
		right.Paint = nil
		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		local who, styleEd
		if P.MyHas("manage_tags") or P.MyHas("manage_titles") then who, styleEd = giveBlock(sc, data) end

		if P.MyHas("self_tag") then
			UI.Section(sc, P.L("tg_mine"), P.L("tg_mine_sub"))
			local mine = LocalPlayer():GetPraetorTag()
			local ed = UI.StyleEdit(sc, mine or { text = "Boss", c1 = { r = 232, g = 194, b = 122 }, fx = "shine" }, { icon = true, maxLen = 20 })
			ed:Dock(TOP)
			ed:SetTall(S(170))
			local row = vgui.Create("DPanel", sc)
			row:Dock(TOP)
			row:SetTall(S(36))
			row:DockMargin(0, S(6), 0, 0)
			row.Paint = nil
			local sv = UI.Button(row, P.L("ui_save"), "primary", nil, function() P.Request("self_tag", { style = ed:GetStyle() }) end)
			sv:Dock(LEFT)
			sv:SetWide(S(120))
			local cl = UI.Button(row, P.L("tg_clear"), "ghost", nil, function() P.Request("self_tag", {}) end)
			cl:Dock(LEFT)
			cl:SetWide(S(120))
			cl:DockMargin(S(6), 0, 0, 0)
		end

		if P.MyHas("manage_titles") then presetsBlock(sc) end

		-- who has tags / titles
		if P.MyHas("manage_tags") or P.MyHas("manage_titles") then
			UI.Header(right, P.L("tg_list")):Dock(TOP)
			local tbl = UI.Table(right, { { P.L("col_name"), 0.4 }, { P.L("tg_kind_tag"), 0.3 }, { P.L("tg_kind_title"), 0.3 } })
			tbl:Dock(FILL)
			tbl:DockMargin(0, S(6), 0, 0)
			P.On("tags_list", function(d)
				if not IsValid(tbl) then return end
				tbl:Clear()
				if #d.rows == 0 then tbl:Empty(P.L("tg_none"), "star") return end
				for _, r in ipairs(d.rows) do
					local tag = util.JSONToTable(r.tag or "")
					local title = util.JSONToTable(r.title or "")
					tbl:AddRow({
						r.name,
						function(x, _, w, h) if istable(tag) and tag.text then UI.Badge(tag, tag.icon, "Praetor.Tiny", x, (h - S(20)) / 2, S(20)) end end,
						function(x, _, w, h) if istable(title) and title.text then UI.DrawStyle(title, "Praetor.Small", x, h / 2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end end,
					}, { onClick = function()
						if who then who:SetValue(r.sid) end
						if styleEd and istable(tag) and tag.text then styleEd:Setup(tag, { icon = true, maxLen = 24 }) end
					end })
				end
			end)
			P.Request("tags_list")
		else
			right:SetWide(0)
		end
	end,
})
