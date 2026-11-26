-- Praetor menu: Wiki. How to use Praetor, written for server owners, admins and
-- staff (the articles are in cl_wiki.lua). Articles on the left with a search box,
-- the article on the right.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local function article(a)
	return a[P.CurrentLang() == "pt" and "pt" or "en"] or a.en
end

-- plain text of an article, for the search
local function plain(a)
	local t = article(a)
	local out = { t.title, t.sub or "" }
	for _, b in ipairs(t.blocks) do
		if isstring(b[2]) then out[#out + 1] = b[2]
		elseif istable(b[2]) then
			for _, x in ipairs(b[2]) do
				if isstring(x) then out[#out + 1] = x
				elseif istable(x) then out[#out + 1] = (x[1] or "") .. " " .. (x[2] or "") end
			end
		end
	end
	return table.concat(out, " "):lower()
end

local function lineH(font)
	surface.SetFont(font)
	local _, h = surface.GetTextSize("Ag")
	return h
end

-- builds the list of things to draw for an article at width w; returns ops, height
local function layout(a, w)
	local t = article(a)
	local ops, y = {}, 0
	local function text(s, font, x, col)
		ops[#ops + 1] = { "t", s, font, x, y, col }
	end
	local function para(s, font, x, col, width)
		local lh = lineH(font) + S(3)
		for _, l in ipairs(UI.Wrap(s, font, width)) do
			text(l, font, x, col)
			y = y + lh
		end
	end

	-- title
	text(t.title, "Praetor.H1", 0, C.ivory)
	y = y + lineH("Praetor.H1") + S(2)
	if t.sub then
		text(t.sub, "Praetor.Small", 0, C.muted)
		y = y + lineH("Praetor.Small")
	end
	y = y + S(8)
	ops[#ops + 1] = { "rule", 0, y, w }
	y = y + S(12)

	for _, b in ipairs(t.blocks) do
		local kind = b[1]
		if kind == "h" then
			y = y + S(8)
			text(b[2], "Praetor.H3", 0, C.bronzeL)
			y = y + lineH("Praetor.H3") + S(6)
		elseif kind == "p" then
			para(b[2], "Praetor.Body", 0, C.text, w)
			y = y + S(8)
		elseif kind == "b" then
			for _, item in ipairs(b[2]) do
				ops[#ops + 1] = { "dot", S(6), y + lineH("Praetor.Body") / 2 }
				para(item, "Praetor.Body", S(20), C.text, w - S(20))
				y = y + S(3)
			end
			y = y + S(6)
		elseif kind == "n" then
			for i, item in ipairs(b[2]) do
				ops[#ops + 1] = { "num", 0, y, i }
				local y0 = y
				para(item, "Praetor.Body", S(32), C.text, w - S(32))
				y = math.max(y, y0 + S(24)) + S(4)
			end
			y = y + S(6)
		elseif kind == "k" then
			-- key column as wide as the longest key (with a cap)
			surface.SetFont("Praetor.Mono")
			local kw = 0
			for _, row in ipairs(b[2]) do kw = math.max(kw, surface.GetTextSize(row[1])) end
			kw = math.min(kw + S(20), math.floor(w * 0.38))
			for i, row in ipairs(b[2]) do
				local lines = UI.Wrap(row[2], "Praetor.Body", w - kw - S(16))
				local klines = UI.Wrap(row[1], "Praetor.Mono", kw - S(20))
				local lh = lineH("Praetor.Body") + S(3)
				local h = math.max(#lines * lh, #klines * (lineH("Praetor.Mono") + S(2))) + S(12)
				ops[#ops + 1] = { "box", 0, y, w, h, i % 2 == 1 and C.panel or C.panel2 }
				local ky = y + S(6)
				for _, kl in ipairs(klines) do
					ops[#ops + 1] = { "t", kl, "Praetor.Mono", S(10), ky, C.amber }
					ky = ky + lineH("Praetor.Mono") + S(2)
				end
				local ly = y + S(6)
				for _, l in ipairs(lines) do
					ops[#ops + 1] = { "t", l, "Praetor.Body", kw + S(6), ly, C.text }
					ly = ly + lh
				end
				y = y + h
			end
			y = y + S(12)
		elseif kind == "tip" or kind == "warn" then
			local col = kind == "tip" and C.laurel or C.amber
			local lines = UI.Wrap(b[2], "Praetor.Small", w - S(56))
			local lh = lineH("Praetor.Small") + S(3)
			local h = math.max(S(40), #lines * lh + S(18))
			ops[#ops + 1] = { "note", 0, y, w, h, col, kind == "tip" and "info" or "warn" }
			local ly = y + (h - #lines * lh) / 2 + S(1)
			for _, l in ipairs(lines) do
				ops[#ops + 1] = { "t", l, "Praetor.Small", S(42), ly, C.ivory }
				ly = ly + lh
			end
			y = y + h + S(12)
		end
	end
	return ops, y + S(20)
end

local function paintOps(ops)
	for _, o in ipairs(ops) do
		local k = o[1]
		if k == "t" then
			UI.Text(o[2], o[3], o[4], o[5], o[6])
		elseif k == "rule" then
			UI.Rect(o[2], o[3], o[4], 1, C.line)
		elseif k == "dot" then
			UI.Round(o[2] - S(3), o[3] - S(3), S(6), S(6), S(3), C.bronze)
		elseif k == "num" then
			UI.Round(o[2], o[3], S(22), S(22), S(11), Color(C.bronze.r, C.bronze.g, C.bronze.b, 60), C.bronze, 1)
			UI.Text(tostring(o[4]), "Praetor.SmallB", o[2] + S(11), o[3] + S(11), C.bronzeL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif k == "box" then
			UI.Round(o[2], o[3], o[4], o[5], S(4), o[6])
		elseif k == "note" then
			local col = o[6]
			UI.Round(o[2], o[3], o[4], o[5], S(8), Color(col.r, col.g, col.b, 28), Color(col.r, col.g, col.b, 140), 1)
			UI.Icon(o[7], o[2] + S(12), o[3] + (o[5] - 18) / 2, 18)
		end
	end
end

P.AddTab("wiki", {
	cat = "overview", icon = "scroll", order = 9,
	can = function() return true end,
	build = function(panel, data)
		local list = P.Wiki or {}
		local cur = list[1]
		if data and data.article then
			for _, a in ipairs(list) do if a.id == data.article then cur = a end end
		end

		-- ---------------------------------------------------------- left: articles
		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.28), S(200), S(260)))
		left:DockMargin(0, 0, S(12), 0)
		left.Paint = nil
		local search = UI.Entry(left, P.L("wiki_search"))
		search:Dock(TOP)
		search:SetTall(S(32))
		search:DockMargin(0, 0, 0, S(8))
		local lsc = UI.Scroll(left)
		lsc:Dock(FILL)

		-- ---------------------------------------------------------- right: the article
		local right = vgui.Create("DPanel", panel)
		right:Dock(FILL)
		right.Paint = function(_, w, h) UI.Round(0, 0, w, h, S(10), C.panel, C.line) end
		local rsc = UI.Scroll(right)
		rsc:Dock(FILL)
		rsc:DockMargin(S(20), S(16), S(8), S(8))
		local page = vgui.Create("DPanel", rsc)
		page:Dock(TOP)
		page.ops = {}
		page.PerformLayout = function(s, w)
			if not cur then return end
			local ops, h = layout(cur, w - S(14))
			s.ops = ops
			if s:GetTall() ~= h then s:SetTall(h) end
		end
		page.Paint = function(s) paintOps(s.ops) end

		local function open(a)
			cur = a
			page:InvalidateLayout(true)
			if rsc.GetVBar then rsc:GetVBar():SetScroll(0) end
		end

		local function fill()
			lsc:Clear()
			local q = P.Trim(search:GetValue() or ""):lower()
			local n = 0
			for _, a in ipairs(list) do
				if q == "" or plain(a):find(q, 1, true) then
					n = n + 1
					local t = article(a)
					local b = vgui.Create("DButton", lsc)
					b:Dock(TOP)
					b:SetTall(S(46))
					b:DockMargin(0, 0, S(4), S(4))
					b:SetText("")
					b.Paint = function(s, w, h)
						local sel = cur == a
						local hov = s:IsHovered()
						UI.Round(0, 0, w, h, S(8), sel and Color(C.bronze.r, C.bronze.g, C.bronze.b, 55) or (hov and C.panel2 or C.panel), sel and C.bronze or C.line, 1)
						UI.Icon(a.icon or "info", S(10), (h - 18) / 2, 18)
						UI.Text(UI.Fit(t.title, "Praetor.SmallB", w - S(44)), "Praetor.SmallB", S(36), S(15), sel and C.ivory or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Text(UI.Fit(t.sub or "", "Praetor.Tiny", w - S(44)), "Praetor.Tiny", S(36), S(32), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
					b.DoClick = function() UI.Sound("click") open(a) end
				end
			end
			if n == 0 then
				local e = vgui.Create("DPanel", lsc)
				e:Dock(TOP)
				e:SetTall(S(46))
				e.Paint = function(_, w, h)
					UI.Text(UI.Fit(P.L("wiki_none"), "Praetor.Small", w - S(10)), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
		search.OnChange = function() fill() end
		fill()
		open(cur)
	end,
})
