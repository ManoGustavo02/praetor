-- Praetor menu: Restrictions. Every blacklisted / admin only / from-a-rank item
-- in one place, with its picture or a turning 3D preview, filters per kind,
-- a search box, and a browser with every weapon, entity, NPC, vehicle and tool
-- of the server to restrict new ones.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local MODES = {
	{ id = "free", icon = "check", col = function() return C.laurel end, label = "rs_m_free", d = "rs_m_free_d" },
	{ id = "block", icon = "lock", col = function() return C.crimson end, label = "rs_m_block", d = "rs_m_block_d" },
	{ id = "staff", icon = "shield", col = function() return C.amber end, label = "rs_m_staff", d = "rs_m_staff_d" },
	{ id = "rank", icon = "crown", col = function() return C.sky end, label = "rs_from_rank", d = "rs_m_rank_d" },
}

-- picture of an item: icon file, or the kind icon
local function drawItemIcon(info, kind, x, y, size, alpha)
	local m = P.RestrictMat(info and info.icon)
	if m then
		surface.SetMaterial(m)
		surface.SetDrawColor(255, 255, 255, alpha or 255)
		surface.DrawTexturedRect(x, y, size, size)
		return
	end
	local isz = size >= 40 and 32 or 16
	UI.Icon(P.RestrictKindIcon[kind] or "box", x + (size - isz) / 2, y + (size - isz) / 2, isz, Color(255, 255, 255, alpha or 255))
end

-- a model preview that fits the camera to the model and turns slowly
local function modelPreview(parent, mdl)
	local mp = vgui.Create("DModelPanel", parent)
	mp:SetModel(mdl)
	local ent = mp:GetEntity()
	if not IsValid(ent) then mp:Remove() return nil end
	local mn, mx = ent:GetRenderBounds()
	local size = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1)
	local center = (mn + mx) / 2
	mp:SetFOV(40)
	mp:SetCamPos(center + Vector(size * 1.25, size * 1.25, size * 0.6))
	mp:SetLookAt(center)
	mp:SetAmbientLight(Color(80, 80, 90))
	mp:SetDirectionalLight(BOX_TOP, Color(255, 255, 255))
	mp:SetDirectionalLight(BOX_FRONT, Color(170, 170, 190))
	mp.LayoutEntity = function(s2, e) e:SetAngles(Angle(0, RealTime() * 30 % 360, 0)) end
	return mp
end

local function pill(text, icon, col, x, y, h, font)
	font = font or "Praetor.Tiny"
	surface.SetFont(font)
	local tw = surface.GetTextSize(text)
	local w = tw + (icon and 26 or 14)
	UI.Round(x, y, w, h, h / 2, Color(col.r, col.g, col.b, 40), Color(col.r, col.g, col.b, 170))
	local tx = x + 7
	if icon then UI.Icon(icon, x + 5, y + (h - 16) / 2, 16) tx = x + 23 end
	UI.Text(text, font, tx, y + h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return w
end

-- ------------------------------------------------------------------ browser

local function openBrowser(startKind)
	local m = UI.Modal(P.L("rs_browse"), S(780), S(580))
	local kind = startKind ~= "all" and startKind or "weapon"
	local top = vgui.Create("DPanel", m.body)
	top:Dock(TOP)
	top:SetTall(S(34))
	top:DockMargin(0, 0, 0, S(8))
	top.Paint = nil
	local search = UI.Entry(top, P.L("ui_search"))
	search:Dock(RIGHT)
	search:SetWide(S(200))
	local sc = UI.Scroll(m.body)
	sc:Dock(FILL)
	local fill
	local chips = {}
	for _, k in ipairs(P.RestrictKinds) do
		local b = UI.Button(top, P.L("rs_k_" .. k), "ghost", P.RestrictKindIcon[k], function() kind = k UI.Sound("click") fill() end)
		b:SetFont("Praetor.Small")
		b:SizeToLabel(S(8))
		b:Dock(LEFT)
		b:DockMargin(0, 0, S(4), 0)
		chips[k] = b
	end
	fill = function()
		for k, b in pairs(chips) do b.kind = k == kind and "active" or "ghost" end
		sc:Clear()
		local q = P.Trim(search:GetValue()):lower()
		if kind == "prop" then
			-- props: type the model, see it, restrict it
			local row = vgui.Create("DPanel", sc)
			row:Dock(TOP)
			row:SetTall(S(150))
			row.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(8), C.panel2, C.line)
				UI.Text(P.L("rs_prop_hint"), "Praetor.Small", S(150), S(16), C.muted)
			end
			local prev = vgui.Create("SpawnIcon", row)
			prev:SetPos(S(10), S(10))
			prev:SetSize(S(128), S(128))
			prev:SetModel("models/props_c17/oildrum001.mdl")
			local e = UI.Entry(row, "models/props_c17/oildrum001.mdl", q ~= "" and q or "")
			e:SetPos(S(150), S(40))
			e:SetSize(S(420), S(34))
			e.OnChange = function(s2)
				local v = P.Trim(s2:GetValue()):lower():gsub("\\", "/")
				if v:match("%.mdl$") and util.IsValidModel(v) then prev:SetModel(v) end
			end
			local add = UI.Button(row, P.L("rs_choose"), "primary", "lock", function()
				local v = P.Trim(e:GetValue()):lower():gsub("\\", "/")
				if not v:match("^models/.+%.mdl$") then P.Toast(P.L("toast_error"), P.L("rs_bad_model"), "warn", 3) return end
				P.RestrictPopup("prop", v, v)
			end)
			add:SetPos(S(150), S(84))
			add:SetSize(S(200), S(34))
			local tip = UI.Label(sc, P.L("rs_prop_tip"), "Praetor.Tiny", C.dim)
			tip:Dock(TOP)
			tip:DockMargin(S(4), S(8), 0, 0)
			return
		end
		local grid = vgui.Create("DIconLayout", sc)
		grid:Dock(TOP)
		grid:SetSpaceX(S(6))
		grid:SetSpaceY(S(6))
		local n = 0
		for _, it in ipairs(P.RestrictCatalog(kind)) do
			if q == "" or it.name:lower():find(q, 1, true) or it.c:find(q, 1, true) or it.cat:lower():find(q, 1, true) then
				n = n + 1
				if n > 400 then break end
				local t = grid:Add("DButton")
				t:SetText("")
				t:SetSize(S(112), S(124))
				t:SetTooltip(it.name .. "\n" .. it.c .. (it.cat ~= "" and ("\n" .. it.cat) or ""))
				t.hov = 0
				t.Paint = function(s2, w, h)
					s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 14)
					local rule = P.RestrictRule(kind, it.c)
					local col = rule and (P.RestrictStyle(rule)) or C.line
					UI.Round(0, 0, w, h, S(6), P.LerpColor(s2.hov, C.panel2, C.hover), rule and col or P.LerpColor(s2.hov, C.line, C.lineL))
					local isz = S(80)
					drawItemIcon(it, kind, (w - isz) / 2, S(8), isz, rule and rule.m == "block" and 140 or 255)
					UI.Text(UI.Fit(it.name, "Praetor.Tiny", w - S(10)), "Praetor.Tiny", w / 2, h - S(16), C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					if rule then
						local _, icon = P.RestrictStyle(rule)
						UI.Round(w - S(26), S(4), S(22), S(22), S(5), Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 240), col)
						UI.Icon(icon, w - S(26) + (S(22) - 16) / 2, S(4) + (S(22) - 16) / 2, 16)
					end
				end
				t.DoClick = function() P.RestrictPopup(kind, it.c, it.name) end
				t.DoRightClick = t.DoClick
			end
		end
		if n == 0 then
			local l = UI.Label(sc, P.L("ui_empty"), "Praetor.Small", C.dim)
			l:Dock(TOP)
		end
		grid:InvalidateLayout(true)
	end
	search.OnChange = fill
	fill()
	local hint = UI.Label(m.foot, P.L("rs_browse_hint"), "Praetor.Tiny", C.dim)
	hint:Dock(FILL)
	hint:SetContentAlignment(4)
	return m
end

-- ------------------------------------------------------------------ tab

P.AddTab("restrict", {
	cat = "server", icon = "lock", order = 1.5,
	can = function() return P.MyHas("manage_restrict") end,
	build = function(panel, data)
		data = data or {}
		local state = { kind = "all", q = "", only = false, sel = data.kind and data.class and P.RestrictKey(data.kind, data.class) or nil }

		-- ---------------------------------------------------------- numbers
		local stats = vgui.Create("DPanel", panel)
		stats:Dock(TOP)
		stats:SetTall(S(62))
		stats:DockMargin(0, 0, 0, S(8))
		stats.Paint = function(_, w, h)
			local total, block, staff, rank = 0, 0, 0, 0
			for _, r in pairs(P.Restrict) do
				total = total + 1
				if r.m == "block" then block = block + 1 elseif r.m == "staff" then staff = staff + 1 else rank = rank + 1 end
			end
			local tiles = {
				{ "lock", C.bronzeL, total, P.L("rs_total") },
				{ "lock_no", C.crimson, block, P.L("rs_m_block") },
				{ "shield", C.amber, staff, P.L("rs_m_staff") },
				{ "crown", C.sky, rank, P.L("rs_by_rank") },
			}
			local gap = S(8)
			local tw = (w - gap * 3) / 4
			for i, t in ipairs(tiles) do
				local x = (i - 1) * (tw + gap)
				UI.Round(x, 0, tw, h, S(8), C.panel, C.line)
				UI.Round(x + S(10), S(11), S(40), S(40), S(8), Color(t[2].r, t[2].g, t[2].b, 45))
				UI.Icon(t[1], x + S(10) + (S(40) - 32) / 2, S(11) + (S(40) - 32) / 2, 32)
				UI.Text(tostring(t[3]), "Praetor.H2", x + S(62), S(20), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(t[4], "Praetor.Tiny", tw - S(70)), "Praetor.Tiny", x + S(62), S(44), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end

		-- ---------------------------------------------------------- toolbar
		local kindBar = vgui.Create("DPanel", panel)
		kindBar:Dock(TOP)
		kindBar:SetTall(S(32))
		kindBar:DockMargin(0, 0, 0, S(6))
		kindBar.Paint = nil
		local bar = vgui.Create("DPanel", panel)
		bar:Dock(TOP)
		bar:SetTall(S(34))
		bar:DockMargin(0, 0, 0, S(8))
		bar.Paint = nil
		local refresh
		local add = UI.Button(bar, P.L("rs_add"), "primary", "lock_ok", function() openBrowser(state.kind) end)
		add:Dock(RIGHT)
		add:SetWide(S(160))
		local only = UI.Toggle(bar, P.L("rs_only"), "lock", false, function(v) state.only = v refresh() end)
		only:SetFont("Praetor.Small")
		only:SizeToLabel(S(8))
		only:Dock(RIGHT)
		only:DockMargin(S(8), 0, S(8), 0)
		local search = UI.Entry(bar, P.L("rs_search"))
		search:Dock(FILL)
		local chips = {}
		for _, k in ipairs({ "all", "weapon", "entity", "npc", "vehicle", "prop", "tool" }) do
			local b = vgui.Create("DButton", kindBar)
			b:SetText("")
			b:Dock(LEFT)
			b:DockMargin(0, 0, S(6), 0)
			local label = P.L(k == "all" and "rs_k_all" or ("rs_k_" .. k))
			surface.SetFont("Praetor.Small")
			b:SetWide(surface.GetTextSize(label) + S(58))
			b.Paint = function(s2, w, h)
				local on = state.kind == k
				local n = 0
				for _, r in pairs(P.Restrict) do if k == "all" or r.k == k then n = n + 1 end end
				UI.Round(0, 0, w, h, S(6), on and Color(C.bronze.r, C.bronze.g, C.bronze.b, 50) or (s2:IsHovered() and C.hover or C.panel2), on and C.bronze or C.line)
				UI.Icon(k == "all" and "lock" or P.RestrictKindIcon[k], S(7), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 170))
				UI.Text(label, "Praetor.Small", S(28), h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(tostring(n), "Praetor.Tiny", w - S(8), h / 2, n > 0 and C.bronzeL or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			b.DoClick = function() UI.Sound("click") state.kind = k refresh() end
			chips[#chips + 1] = b
		end

		-- ---------------------------------------------------------- detail (right)
		local detail = vgui.Create("DPanel", panel)
		detail:Dock(RIGHT)
		detail:SetWide(S(320))
		detail:DockMargin(S(8), 0, 0, 0)
		detail.Paint = function(_, w, h) UI.Round(0, 0, w, h, S(8), C.panel, C.line) end

		local function showDetail()
			detail:Clear()
			local rule = state.sel and P.Restrict[state.sel]
			local kind, class = tostring(state.sel or ""):match("^(%a+):(.+)$")
			if not kind then
				local e = vgui.Create("DPanel", detail)
				e:Dock(FILL)
				e.Paint = function(_, w, h)
					UI.Icon("lock", w / 2 - 16, h / 2 - S(40), 32, Color(255, 255, 255, 80))
					UI.Text(P.L("rs_pick"), "Praetor.SmallB", w / 2, h / 2 + S(4), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("rs_pick_d"), "Praetor.Tiny", w / 2, h / 2 + S(24), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			local info = P.RestrictInfo(kind, class)
			detail:DockPadding(S(10), S(10), S(10), S(10))

			-- preview: 3D model turning, or the item picture
			local view = vgui.Create("DPanel", detail)
			view:Dock(TOP)
			view:SetTall(S(190))
			view.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(8), Color(12, 13, 17), C.line)
				surface.SetDrawColor(255, 255, 255, 8)
				for x = S(16), w - 2, S(16) do for y = S(16), h - 2, S(16) do surface.DrawRect(x, y, 2, 2) end end
			end
			local mp = info.mdl and (util.IsValidModel(info.mdl) or file.Exists(info.mdl, "GAME")) and modelPreview(view, info.mdl)
			if mp then
				mp:Dock(FILL)
				mp:DockMargin(S(4), S(4), S(4), S(4))
			else
				view.PaintOver = function(_, w, h)
					local sz = math.min(S(150), h - S(20))
					drawItemIcon(info, kind, (w - sz) / 2, (h - sz) / 2, sz)
				end
			end
			local badge = vgui.Create("DPanel", view)
			badge:SetSize(S(300), S(26))
			badge:SetPos(S(8), S(8))
			badge:SetMouseInputEnabled(false)
			badge.Paint = function()
				local col, icon, label = P.RestrictStyle(P.Restrict[state.sel])
				pill(label, icon, col, 0, 0, S(24), "Praetor.SmallB")
			end

			local head = vgui.Create("DPanel", detail)
			head:Dock(TOP)
			head:SetTall(S(64))
			head:DockMargin(0, S(8), 0, 0)
			head.Paint = function(_, w, h)
				UI.Text(UI.Fit(info.name or class, "Praetor.H2", w), "Praetor.H2", 0, S(2), C.ivory)
				UI.Text(UI.Fit(class, "Praetor.Mono", w - S(30)), "Praetor.Mono", 0, S(30), C.muted)
				local sub = P.L("rs_k_" .. kind) .. ((info.cat or "") ~= "" and ("  -  " .. info.cat) or "")
				if rule and rule.t then sub = sub .. "  -  " .. os.date("%d/%m/%Y", rule.t) end
				UI.Text(UI.Fit(sub, "Praetor.Tiny", w), "Praetor.Tiny", 0, S(50), C.dim)
			end
			local copy = UI.Button(head, "", "subtle", "copy", function() SetClipboardText(class) UI.Sound("click") end)
			copy:SetTooltip(P.L("rs_copy"))
			copy:SetSize(S(26), S(22))
			head.PerformLayout = function(s2, w) copy:SetPos(w - S(26), S(28)) end

			-- who can use it: four cards
			local lbl = UI.Label(detail, P.L("rs_who"), "Praetor.SmallB", C.ivory)
			lbl:Dock(TOP)
			lbl:DockMargin(0, S(6), 0, S(4))
			local grid = vgui.Create("DPanel", detail)
			grid:Dock(TOP)
			grid:SetTall(S(104))
			grid.Paint = nil
			local cards = {}
			for i, md in ipairs(MODES) do
				local b = vgui.Create("DButton", grid)
				b:SetText("")
				b:SetTooltip(P.L(md.d))
				b.Paint = function(s2, w, h)
					local cur = P.Restrict[state.sel]
					local on = (cur and cur.m or "free") == md.id
					local col = md.col()
					UI.Round(0, 0, w, h, S(6), on and Color(col.r, col.g, col.b, 55) or (s2:IsHovered() and C.hover or C.panel2), on and col or C.line)
					UI.Icon(md.icon, S(8), (h - 16) / 2, 16, Color(255, 255, 255, on and 255 or 150))
					UI.Text(UI.Fit(P.L(md.label), "Praetor.Small", w - S(34)), "Praetor.Small", S(30), h / 2, on and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				b.DoClick = function()
					if md.id == "rank" then
						local items = {}
						local ranks = P.SortedRanks()
						table.sort(ranks, function(a, c) return (a.immunity or 0) < (c.immunity or 0) end)
						for _, r in ipairs(ranks) do
							if r.name ~= "user" then
								local _, ricon = UI.RankStyle(r)
								items[#items + 1] = { r.display or r.name, ricon or "crown", function() P.RestrictSet(kind, class, "rank", r.name) end }
							end
						end
						UI.Popup(items)
					else
						P.RestrictSet(kind, class, md.id)
					end
				end
				cards[i] = b
			end
			grid.PerformLayout = function(_, w, h)
				local cw, ch = (w - S(6)) / 2, (h - S(6)) / 2
				for i, b in ipairs(cards) do
					b:SetPos(((i - 1) % 2) * (cw + S(6)), math.floor((i - 1) / 2) * (ch + S(6)))
					b:SetSize(cw, ch)
				end
			end

			if kind == "weapon" and rule then
				local sw = UI.Switch(detail, P.L("rs_pk"), P.L("rs_pk_d"), rule.pk ~= false, function(v)
					local cur = P.Restrict[state.sel]
					if cur then P.RestrictSet(kind, class, cur.m, cur.r, v) end
				end)
				sw:Dock(TOP)
				sw:DockMargin(0, S(6), 0, 0)
			end

			-- actions
			local acts = vgui.Create("DPanel", detail)
			acts:Dock(TOP)
			acts:SetTall(S(34))
			acts:DockMargin(0, S(8), 0, 0)
			acts.Paint = nil
			local function act(label, icon, kindBtn, fn)
				local b = UI.Button(acts, label, kindBtn, icon, fn)
				b:SetFont("Praetor.Small")
				b:Dock(LEFT)
				b:DockMargin(0, 0, S(6), 0)
				b:SizeToLabel(S(10))
				return b
			end
			if kind == "weapon" then
				act(P.L("rs_strip"), "gun_no", "ghost", function() P.Request("rs_strip", { c = class }) end)
				if P.MyHas("give") then
					act(P.L("rs_give_short"), "gun_ok", "ghost", function()
						UI.PlayerPicker(function(pl)
							if IsValid(pl) then P.Request("rs_give", { c = class, sid = pl:IsBot() and ("$" .. pl:UserID()) or pl:SteamID64() }) end
						end, { title = P.L("rs_give") .. ": " .. (info.name or class) })
					end)
				end
			elseif kind ~= "tool" then
				act(P.L("rs_clear"), "broom", "ghost", function()
					UI.Confirm(P.L("rs_clear"), P.L("rs_clear_q", { S = info.name or class }), function() P.Request("rs_clear", { k = kind, c = class }) end, true)
				end)
			end

			if rule then
				local free = UI.Button(detail, P.L("rs_remove"), "danger", "trash", function() P.RestrictSet(kind, class, "free") end)
				free:Dock(BOTTOM)
				free:SetTall(S(36))
			end
		end

		-- ---------------------------------------------------------- list
		local listBg = vgui.Create("DPanel", panel)
		listBg:Dock(FILL)
		listBg.Paint = nil
		local sc = UI.Scroll(listBg)
		sc:Dock(FILL)

		local MAX_ROWS = 250
		refresh = function()
			if not IsValid(sc) then return end
			local scroll = sc:GetVBar():GetScroll()
			sc:Clear()
			local q = P.Trim(search:GetValue()):lower()
			local rows, seen = {}, {}
			local function match(info, class)
				return q == "" or class:find(q, 1, true) or tostring(info.name or ""):lower():find(q, 1, true) or tostring(info.cat or ""):lower():find(q, 1, true)
			end
			-- restricted items first (also props / items that are not in any list)
			for k, r in pairs(P.Restrict) do
				if state.kind == "all" or r.k == state.kind then
					local info = P.RestrictInfo(r.k, r.c)
					if match(info, r.c) then
						seen[k] = true
						rows[#rows + 1] = { key = k, k = r.k, c = r.c, info = info }
					end
				end
			end
			-- then every other item of the server
			if not state.only then
				for _, kind in ipairs(P.RestrictKinds) do
					if state.kind == "all" or state.kind == kind then
						for _, it in ipairs(P.RestrictCatalog(kind)) do
							local k = P.RestrictKey(kind, it.c)
							if not seen[k] and match(it, it.c) then
								seen[k] = true
								rows[#rows + 1] = { key = k, k = kind, c = it.c, info = it }
							end
						end
					end
				end
			end
			-- blacklist, admin only, ranks, then the free ones; by name inside
			local order = { block = 1, staff = 2, rank = 3 }
			table.sort(rows, function(a, b)
				local ra, rb = P.Restrict[a.key], P.Restrict[b.key]
				local oa, ob = ra and order[ra.m] or 4, rb and order[rb.m] or 4
				if oa ~= ob then return oa < ob end
				return tostring(a.info.name):lower() < tostring(b.info.name):lower()
			end)
			if #rows == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(150))
				e.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(8), C.panel, C.line)
					UI.Icon("lock_ok", w / 2 - 16, S(26), 32, Color(255, 255, 255, 120))
					UI.Text(P.L(state.only and "rs_none" or "ui_empty"), "Praetor.BodyB", w / 2, S(80), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("rs_none_hint"), "Praetor.Tiny", w / 2, S(104), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
			for i, row in ipairs(rows) do
				if i > MAX_ROWS then
					local more = vgui.Create("DPanel", sc)
					more:Dock(TOP)
					more:SetTall(S(40))
					more.Paint = function(_, w, h)
						UI.Text(P.L("rs_more", { V = MAX_ROWS, M = #rows }), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					break
				end
				local info = row.info
				local b = vgui.Create("DButton", sc)
				b:SetText("")
				b:Dock(TOP)
				b:SetTall(S(62))
				b:DockMargin(0, 0, S(4), S(4))
				b.hov = 0
				local pv = S(50)
				if row.k == "prop" then
					local si = vgui.Create("SpawnIcon", b)
					si:SetModel(row.c)
					si:SetSize(pv, pv)
					si:SetPos(S(10), S(6))
					si:SetMouseInputEnabled(false)
					si.praetorBadge = true
				end
				local catText = (info.cat or "") ~= "" and info.cat or nil
				b.Paint = function(s2, w, h)
					s2.hov = UI.Lerp(s2.hov, s2:IsHovered() and 1 or 0, 14)
					local rule = P.Restrict[row.key]
					local sel = state.sel == row.key
					local col, icon, label = P.RestrictStyle(rule)
					UI.Round(0, 0, w, h, S(6), sel and Color(C.bronze.r, C.bronze.g, C.bronze.b, 35) or P.LerpColor(s2.hov, C.panel2, C.hover), sel and C.bronze or P.LerpColor(s2.hov, C.line, rule and col or C.lineL))
					-- strip in the rule colour (free items: none)
					if rule then UI.Round(0, S(8), S(3), h - S(16), S(1), col) end
					UI.Round(S(10), S(6), pv, pv, S(6), Color(12, 13, 17))
					if row.k ~= "prop" then drawItemIcon(info, row.k, S(10) + S(3), S(6) + S(3), pv - S(6), rule and rule.m == "block" and 150 or 255) end
					local x = S(10) + pv + S(12)
					-- right side: status pill (free items get a quiet one)
					surface.SetFont("Praetor.Small")
					local pw = surface.GetTextSize(label) + S(30)
					if rule then
						pill(label, icon, col, w - pw - S(12), (h - S(24)) / 2, S(24), "Praetor.Small")
					else
						UI.Icon("check", w - S(12) - 16 - S(6), (h - 16) / 2, 16, Color(255, 255, 255, 90))
						UI.Text(label, "Praetor.Small", w - S(12) - 16 - S(12), h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end
					local room = w - x - pw - S(30)
					UI.Text(UI.Fit(tostring(info.name or row.c), "Praetor.BodyB", room), "Praetor.BodyB", x, S(9), rule and C.ivory or C.text)
					surface.SetFont("Praetor.Mono")
					local cls = UI.Fit(row.c, "Praetor.Mono", room * 0.55)
					UI.Text(cls, "Praetor.Mono", x, S(33), C.dim)
					local kx = x + surface.GetTextSize(cls) + S(10)
					-- kind and category / addon
					local kw = pill(P.L("rs_k_" .. row.k), P.RestrictKindIcon[row.k], C.lineL, kx, S(31), S(20))
					if catText and kx + kw + S(60) < x + room then
						UI.Text(UI.Fit(catText, "Praetor.Tiny", x + room - kx - kw - S(8)), "Praetor.Tiny", kx + kw + S(8), S(41), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
				end
				b.DoClick = function()
					UI.Sound("click")
					state.sel = row.key
					showDetail()
				end
				b.DoRightClick = function() P.RestrictPopup(row.k, row.c, info.name) end
			end
			timer.Simple(0, function() if IsValid(sc) then sc:GetVBar():SetScroll(scroll) end end)
		end
		search.OnChange = refresh

		hook.Add("Praetor.RestrictChanged", panel, function()
			if not IsValid(panel) then return end
			refresh()
			if state.sel and not P.Restrict[state.sel] then state.sel = nil end
			showDetail()
		end)
		refresh()
		showDetail()
	end,
})
