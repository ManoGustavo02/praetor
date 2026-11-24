-- Praetor menu: custom tags ("Rei do Macete") and titles, given by SteamID so
-- they also work for players who are offline.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local DEFAULT = { text = "Rei do Macete", c1 = { r = 255, g = 196, b = 80 }, c2 = { r = 230, g = 90, b = 60 }, fx = "flow" }

local function giveBlock(sc, data)
	UI.Section(sc, P.L("tg_give"), P.L("tg_give_sub"))
	local who = UI.PlayerPick(sc, data.sid or "")
	who:Dock(TOP)
	local kindOpts = {}
	if P.MyHas("manage_tags") then kindOpts[#kindOpts + 1] = { "tag", P.L("tg_kind_tag") } end
	if P.MyHas("manage_titles") then kindOpts[#kindOpts + 1] = { "title", P.L("tg_kind_title") } end
	local kind = UI.Combo(sc, kindOpts, kindOpts[1] and kindOpts[1][1])
	kind:Dock(TOP)
	kind:DockMargin(0, S(6), 0, 0)
	local style = UI.StyleEdit(sc, data.style or DEFAULT, { icon = true, maxLen = 24 })
	style:Dock(TOP)
	style:SetTall(S(170))
	style:DockMargin(0, S(6), 0, 0)
	local preview = vgui.Create("DPanel", sc)
	preview:Dock(TOP)
	preview:SetTall(S(44))
	preview:DockMargin(0, S(4), 0, 0)
	preview.Paint = function(_, w, h)
		UI.Notch(0, 0, w, h, S(4), C.bg, C.line)
		local st = style:GetStyle()
		local _, k = kind:GetSelected()
		if k == "title" then
			UI.DrawStyle(st, "Praetor.H3", S(12), h / 2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			UI.Badge(st, st.icon, "Praetor.Tag", S(12), (h - S(24)) / 2, S(24))
		end
		UI.Text(P.L("tg_preview"), "Praetor.Tiny", w - S(10), h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	local btns = vgui.Create("DPanel", sc)
	btns:Dock(TOP)
	btns:SetTall(S(36))
	btns:DockMargin(0, S(6), 0, 0)
	btns.Paint = nil
	local function send(clear)
		local sid = who:GetValue()
		local _, k = kind:GetSelected()
		if P.Trim(sid) == "" or not k then P.Toast(P.L("toast_error"), P.L("err_steamid"), "warn", 4) return end
		P.Request(k == "title" and "title_set" or "tag_set", { sid = sid, style = (not clear) and style:GetStyle() or nil })
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
