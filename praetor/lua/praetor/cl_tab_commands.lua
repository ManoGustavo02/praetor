-- Praetor menu: every command you can run, and your key shortcuts.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

-- colour of each command category (icon squares and section headers)
local CAT_TINT = { moderation = "crimson", teleport = "sky", player = "laurel", fun = "amber", chat = "bronze",
	users = "amber", server = "muted", darkrp = "laurel", custom = "bronze", addons = "muted" }
function P.CatTint(cat) return C[CAT_TINT[cat or ""] or "bronze"] or C.bronze end

local function usage(c)
	local parts = { "!" .. c.id }
	for _, a in ipairs(c.args or {}) do
		local h = P.L("arg_" .. (a.h or a.t), nil, a.h or a.t)
		parts[#parts + 1] = a.o and ("[" .. h .. "]") or ("<" .. h .. ">")
	end
	return table.concat(parts, " ")
end
P.UsageText = usage
UI.Usage = usage

P.AddTab("commands", {
	cat = "overview", icon = "sword", order = 2,
	can = function() return P.MyHas("menu") end,
	build = function(panel)
		local bar = UI.Toolbar(panel)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("ui_search")), nil, FILL)
		search:DockMargin(0, 0, 0, 0)
		local hint = UI.Label(panel, P.L("cmd_hint"), "Praetor.Small", C.muted)
		hint:Dock(TOP)
		hint:DockMargin(0, 0, 0, S(6))

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		local inner = math.max(S(300), panel:GetParent():GetWide() - S(20))
		local per = math.max(1, math.floor((inner + S(6)) / (S(268) + S(6))))
		local bw = math.floor((inner - (per - 1) * S(6)) / per)

		local function fill()
			sc:Clear()
			local q = search:GetValue():lower()
			local byCat = {}
			for id, c in pairs(P.ServerCmds) do
				if P.CanRunId(id) and not c.hid then
					local help = P.L("h_" .. id, nil, c.help or "")
					if q == "" or id:find(q, 1, true) or help:lower():find(q, 1, true) then
						local cat = c.cat or "addons"
						byCat[cat] = byCat[cat] or {}
						table.insert(byCat[cat], c)
					end
				end
			end
			local cats = {}
			for _, cat in ipairs(P.Categories) do if byCat[cat] then cats[#cats + 1] = cat end end
			for cat in pairs(byCat) do if not table.HasValue(cats, cat) then cats[#cats + 1] = cat end end
			if #cats == 0 then
				local e = UI.Label(sc, P.L("ui_empty"), "Praetor.Small", C.dim)
				e:Dock(TOP)
				return
			end
			for _, cat in ipairs(cats) do
				local tint = P.CatTint(cat)
				local catLabel = P.Upper(P.L("cat_" .. cat, nil, cat))
				local n = #byCat[cat]
				local hd = vgui.Create("DPanel", sc)
				hd:Dock(TOP)
				hd:SetTall(S(30))
				hd:DockMargin(0, S(6), 0, S(6))
				hd.Paint = function(_, w, h)
					UI.Round(0, (h - S(26)) / 2, S(26), S(26), S(5), Color(tint.r, tint.g, tint.b, 50))
					UI.Icon(P.CatIcons[cat] or "box", (S(26) - 16) / 2, (h - 16) / 2, 16)
					UI.Text(catLabel, "Praetor.BodyB", S(36), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					surface.SetFont("Praetor.BodyB")
					local tw = surface.GetTextSize(catLabel)
					local cnt = tostring(n)
					surface.SetFont("Praetor.Tiny")
					local cw = surface.GetTextSize(cnt) + S(12)
					UI.Round(S(36) + tw + S(8), (h - S(18)) / 2, cw, S(18), S(9), C.panel3)
					UI.Text(cnt, "Praetor.Tiny", S(36) + tw + S(8) + cw / 2, h / 2, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Rect(S(36) + tw + cw + S(16), math.floor(h / 2), w - (S(36) + tw + cw + S(16)), 1, C.line)
				end
				local grid = vgui.Create("DIconLayout", sc)
				grid:Dock(TOP)
				grid:SetSpaceX(S(6))
				grid:SetSpaceY(S(6))
				table.sort(byCat[cat], function(a, b) return a.id < b.id end)
				for _, c in ipairs(byCat[cat]) do
					local b = grid:Add("DButton")
					b:SetText("")
					b:SetSize(bw, S(62))
					local help = P.L("h_" .. c.id, nil, c.help or "")
					local u = usage(c)
					local icon = P.CmdIcon(c.id)
					b.hov = 0
					b.Paint = function(s, w, h)
						s.hov = UI.Lerp(s.hov, s:IsHovered() and 1 or 0, 14)
						UI.Round(0, 0, w, h, S(6), P.LerpColor(s.hov, C.panel2, C.hover), P.LerpColor(s.hov, C.line, tint))
						local box = h - S(14)
						UI.Round(S(7), S(7), box, box, S(6), Color(tint.r, tint.g, tint.b, 40 + 30 * s.hov))
						local isz = UI.IconSize(box - S(10))
						if isz > box then isz = 16 end
						UI.Icon(icon, S(7) + math.floor((box - isz) / 2), S(7) + math.floor((box - isz) / 2), isz)
						local x = S(7) + box + S(10)
						UI.Text(UI.Fit(u, "Praetor.BodyB", w - x - S(8)), "Praetor.BodyB", x, S(10), C.ivory)
						UI.Text(UI.Fit(help ~= "" and help or "-", "Praetor.Tiny", w - x - S(8)), "Praetor.Tiny", x, S(35), C.muted)
					end
					b.DoClick = function() UI.Sound("click") P.RunDialog(c.id) end
					b.DoRightClick = function()
						UI.Popup({
							{ P.L("cmd_copy_console"), nil, function() SetClipboardText("pr " .. c.id) end },
							{ P.L("cmd_make_bind"), nil, function() P.OpenMenu("shortcuts", { line = c.id }) end },
						})
					end
					b:SetTooltip(table.concat(c.al or {}, ", ") ~= "" and (P.L("cmd_aliases") .. ": " .. table.concat(c.al, ", ")) or nil)
				end
			end
		end
		search.OnChange = fill
		fill()
	end,
})

-- ------------------------------------------------------------------ shortcuts

P.AddTab("shortcuts", {
	cat = "overview", icon = "bolt", order = 3,
	can = function() return P.MyHas("menu") end,
	build = function(panel, data)
		local intro = UI.Label(panel, P.L("bind_intro"), "Praetor.Small", C.muted)
		intro:SetWrap(true)
		intro:SetAutoStretchVertical(true)
		intro:Dock(TOP)
		intro:DockMargin(0, 0, 0, S(8))

		local bar = UI.Toolbar(panel, S(40))
		local binder = vgui.Create("DBinder", bar)
		UI.Tool(bar, binder, S(130))
		binder:SetValue(KEY_NONE)
		binder.Paint = function(s, w, h)
			UI.Round(0, 0, w, h, S(5), C.bg, s:IsHovered() and C.bronze or C.line)
		end
		binder:SetFont("Praetor.BodyB")
		binder:SetTextColor(C.bronzeL)
		local line = UI.Tool(bar, UI.Entry(bar, P.L("bind_line_hint"), data.line or ""), nil, FILL)
		-- short on/off button (the long "run silently" text didn't fit the bar)
		local silent
		if P.MyHas("silent") then
			silent = UI.Toggle(bar, P.L("bind_silent"), "eye", false)
			silent:SetTooltip(P.L("run_silent"))
			silent:SetFont("Praetor.Small")
			silent.GetChecked = function(s) return s:GetValue() end
			silent:SizeToLabel(S(12))
			UI.Tool(bar, silent, silent:GetWide(), RIGHT)
		end
		local tbl
		local add = UI.Button(bar, P.L("bind_add"), "primary", "bolt", function()
			local key = binder:GetValue()
			local l = P.Trim(line:GetValue()):gsub("^[!/]", "")
			if not key or key == KEY_NONE or l == "" then
				P.Toast(P.L("toast_error"), P.L("bind_need"), "warn", 4)
				return
			end
			table.insert(P.Binds, { key = key, line = l, silent = silent and silent:GetChecked() or nil })
			P.SaveBinds()
			line:SetValue("")
			binder:SetValue(KEY_NONE)
			UI.Sound("ok")
			tbl:Fill()
		end)
		UI.Tool(bar, add, S(140), RIGHT)

		tbl = UI.Table(panel, { { P.L("bind_key"), 120 }, { P.L("bind_cmd"), 1 }, { "", 120, TEXT_ALIGN_RIGHT } })
		tbl:Dock(FILL)
		function tbl:Fill()
			self:Clear()
			if #P.Binds == 0 then self:Empty(P.L("bind_empty"), "bolt", P.L("bind_empty_hint")) return end
			for i, b in ipairs(P.Binds) do
				self:AddRow({
					{ string.upper(input.GetKeyName(tonumber(b.key) or 0) or "?"), C.bronzeL },
					"pr " .. b.line .. (b.silent and ("   (" .. P.L("silent") .. ")") or ""),
					{ P.L("ui_remove"), C.crimsonL },
				}, { onClick = function()
					table.remove(P.Binds, i)
					P.SaveBinds()
					tbl:Fill()
				end })
			end
		end
		tbl:Fill()

		local foot = UI.Label(panel, P.L("bind_console"), "Praetor.Tiny", C.dim)
		foot:Dock(BOTTOM)
		foot:DockMargin(0, S(6), 0, 0)
	end,
})
