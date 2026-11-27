-- Praetor menu: Chips. Every Expression 2 and Starfall chip on the map, live: name,
-- owner, CPU, holograms and what made it suspicious. Go to a chip, stop it, remove
-- it or remove every chip of its owner. The list only updates while the tab is open.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local FLAG_COL = { cpu = "crimsonL", esp = "amber", holo = "amber" }

local function flagTags(c)
	local out = {}
	if istable(c.f) then
		for _, k in ipairs({ "cpu", "esp", "holo" }) do
			if c.f[k] then out[#out + 1] = { P.L("chip_f_" .. k), C[FLAG_COL[k]] or C.amber } end
		end
	end
	if c.err then out[#out + 1] = { P.L("chip_f_err"), C.dim } end
	return out
end

local function tagsWidth(tags)
	surface.SetFont("Praetor.Tiny")
	local w = 0
	for _, t in ipairs(tags) do w = w + surface.GetTextSize(t[1]) + S(14) + S(4) end
	return w
end

P.AddTab("chips", {
	cat = "moderation", icon = "terminal", order = 1.7,
	can = function() return P.MyHas("chips") end,
	build = function(panel)
		local canManage = P.MyHas("chips_manage")
		local search, onlyBad = "", false

		local bar = UI.Toolbar(panel, S(36))
		local entry = UI.Tool(bar, UI.Entry(nil, P.L("chip_search")), S(240))
		local badT = UI.Tool(bar, UI.Toggle(nil, P.L("chip_only_bad"), "warn", false), nil)
		badT:SizeToLabel(S(14))
		local count = vgui.Create("DPanel", bar)
		count:Dock(FILL)
		count.Paint = function(_, w, h)
			local list = P.ChipLive or {}
			local bad = 0
			for _, c in ipairs(list) do if istable(c.f) and next(c.f) then bad = bad + 1 end end
			local txt = P.L("chip_count", { V = #list, V2 = bad })
			UI.Text(UI.Fit(txt, "Praetor.Small", w - S(8)), "Praetor.Small", w, h / 2, bad > 0 and C.amber or C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end

		-- what triggers an alert (and where to change it)
		local note = vgui.Create("DPanel", panel)
		note:Dock(TOP)
		note:DockMargin(0, 0, 0, S(8))
		note.lines = {}
		note.PerformLayout = function(s, w)
			local txt = P.L("chip_help", { V = tostring(P.Setting("chip_cpu_alert") or 80) })
			if P.Setting("chip_alerts") == false then txt = P.L("chip_alerts_off") .. "  " .. txt end
			s.lines = UI.Wrap(txt, "Praetor.Tiny", w - S(46))
			local h = math.max(S(36), #s.lines * S(15) + S(14))
			if s:GetTall() ~= h then s:SetTall(h) end
		end
		note.Paint = function(s, w, h)
			UI.Round(0, 0, w, h, S(8), C.panel, C.line)
			UI.Icon("info", S(12), (h - 18) / 2, 18)
			for i, l in ipairs(s.lines) do
				UI.Text(l, "Praetor.Tiny", S(38), S(7) + (i - 1) * S(15), C.muted)
			end
		end

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		local rows, order = {}, ""

		local function visible()
			local out = {}
			local q = P.Trim(search):lower()
			for _, c in ipairs(P.ChipLive or {}) do
				local bad = istable(c.f) and next(c.f) ~= nil
				if (not onlyBad or bad) and (q == "" or tostring(c.n):lower():find(q, 1, true) or tostring(c.on):lower():find(q, 1, true)) then
					out[#out + 1] = c
				end
			end
			return out
		end

		local function makeRow(c)
			local row = vgui.Create("DPanel", sc)
			row:Dock(TOP)
			row:SetTall(S(60))
			row:DockMargin(0, 0, S(4), S(6))
			row.c = c
			local btns = {}
			local function add(label, kind, icon, fn)
				local b = UI.Button(row, label, kind, icon, fn)
				b:SetSize(S(76), S(30))
				btns[#btns + 1] = b
			end
			add(P.L("chip_goto"), "ghost", "portal", function() P.Request("chip_goto", { e = row.c.e }) end)
			if canManage then
				add(P.L("chip_stop"), "ghost", "stop", function() P.Request("chip_stop", { e = row.c.e }) end)
				add(P.L("chip_remove"), "danger", "trash", function()
					local cc = row.c
					UI.Confirm(P.L("chip_remove_t"), P.L("chip_remove_q", { V = cc.n, S = cc.on }), function()
						P.Request("chip_remove", { e = cc.e })
					end, true)
				end)
			end
			row.btnW = #btns * S(80)
			row.PerformLayout = function(_, w, h)
				local x = w - S(10) - row.btnW + S(4)
				for _, b in ipairs(btns) do
					b:SetPos(x, (h - S(30)) / 2)
					x = x + S(80)
				end
			end
			row.OnMousePressed = function(_, code)
				if code ~= MOUSE_RIGHT then return end
				local cc = row.c
				local items = {
					{ P.L("chip_goto"), "portal", function() P.Request("chip_goto", { e = cc.e }) end },
				}
				if cc.os then
					items[#items + 1] = { P.L("chip_copy_sid"), "copy", function() SetClipboardText(util.SteamIDFrom64(cc.os)) end }
				end
				if canManage then
					items[#items + 1] = false
					items[#items + 1] = { P.L("chip_stop"), "stop", function() P.Request("chip_stop", { e = cc.e }) end }
					items[#items + 1] = { P.L("chip_remove"), "trash", function() P.Request("chip_remove", { e = cc.e }) end, true }
					items[#items + 1] = { P.L("chip_remove_all", { S = cc.on }), "trash", function()
						UI.Confirm(P.L("chip_remove_all_t"), P.L("chip_remove_all_q", { S = cc.on }), function()
							P.Request("chip_remove_owner", { e = cc.e })
						end, true)
					end, true }
				end
				UI.Popup(items)
			end
			row.Paint = function(_, w, h)
				local cc = row.c
				local tags = flagTags(cc)
				local bad = istable(cc.f) and next(cc.f) ~= nil
				UI.Round(0, 0, w, h, S(8), C.panel, bad and Color(C.crimsonL.r, C.crimsonL.g, C.crimsonL.b, 150) or C.line)

				-- type badge
				local bc = cc.t == "sf" and C.sky or C.bronze
				UI.Round(S(10), (h - S(36)) / 2, S(36), S(36), S(8), Color(bc.r, bc.g, bc.b, 50), bc, 1)
				UI.Text(cc.t == "sf" and "SF" or "E2", "Praetor.SmallB", S(28), h / 2, bc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

				-- CPU column, just left of the buttons
				local cpuW = S(170)
				local cpuX = w - S(10) - row.btnW - S(14) - cpuW
				local pct = tonumber(cc.pct) or 0
				local limit = tonumber(P.Setting("chip_cpu_alert")) or 80
				local col = cc.err and C.dim or (pct >= limit and C.crimsonL or (pct >= limit * 0.5 and C.amber or C.laurel))
				local us = tonumber(cc.us) or 0
				UI.Text("CPU", "Praetor.Tiny", cpuX, S(15), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(math.floor(pct) .. "%  ·  " .. us .. " µs", "Praetor.SmallB", cpuX + cpuW, S(15), col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				UI.Round(cpuX, S(26), cpuW, S(7), S(3), C.bg, C.line, 1)
				local frac = math.Clamp(pct / 100, 0, 1)
				if frac > 0 then UI.Round(cpuX + 1, S(27), math.max(S(4), (cpuW - 2) * frac), S(5), S(2), col) end
				local sub = {}
				if cc.ops then sub[#sub + 1] = P.L("chip_ops", { V = cc.ops }) end
				sub[#sub + 1] = P.L("chip_holos", { V = cc.holo or 0 })
				UI.Text(UI.Fit(table.concat(sub, "  ·  "), "Praetor.Tiny", cpuW), "Praetor.Tiny", cpuX, S(45), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

				-- name + flags
				local nx = S(56)
				local nw = math.max(S(40), cpuX - S(16) - nx)
				local tw = tagsWidth(tags)
				local showTags = tw <= nw * 0.6
				local nameW = showTags and (nw - tw - S(6)) or nw
				UI.Text(UI.Fit(tostring(cc.n or "?"), "Praetor.BodyB", nameW), "Praetor.BodyB", nx, S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if showTags then
					surface.SetFont("Praetor.BodyB")
					local tx = nx + math.min(surface.GetTextSize(UI.Fit(tostring(cc.n or "?"), "Praetor.BodyB", nameW)), nameW) + S(8)
					for _, t in ipairs(tags) do
						surface.SetFont("Praetor.Tiny")
						local ww = surface.GetTextSize(t[1]) + S(14)
						UI.Round(tx, S(10), ww, S(18), S(9), Color(t[2].r, t[2].g, t[2].b, 40), t[2], 1)
						UI.Text(t[1], "Praetor.Tiny", tx + ww / 2, S(19), t[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						tx = tx + ww + S(4)
					end
				end

				-- owner (and how many players it is reading)
				local owner = cc.os and player.GetBySteamID64(cc.os) or nil
				UI.DrawAvatar(cc.os or "0", IsValid(owner) and owner or nil, nx, S(34), S(18), 255, nil, cc.on)
				local line = tostring(cc.on or "?")
				if cc.seen then line = line .. "  ·  " .. P.L("chip_seen", { V = cc.seen }) end
				if not showTags and #tags > 0 then
					local names = {}
					for _, t in ipairs(tags) do names[#names + 1] = t[1] end
					line = line .. "  ·  " .. table.concat(names, ", ")
				end
				UI.Text(UI.Fit(line, "Praetor.Small", nw - S(24)), "Praetor.Small", nx + S(24), S(44), (not showTags and bad) and C.amber or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			return row
		end

		local empty
		local function refill()
			if not IsValid(sc) then return end
			local list = visible()
			local key = {}
			for _, c in ipairs(list) do key[#key + 1] = c.e end
			key = table.concat(key, ",")
			if key == order then
				-- same chips in the same order: only the numbers change
				local byE = {}
				for _, c in ipairs(list) do byE[c.e] = c end
				for _, r in ipairs(rows) do if IsValid(r) and byE[r.c.e] then r.c = byE[r.c.e] end end
				return
			end
			order = key
			sc:Clear()
			rows = {}
			if #list == 0 then
				empty = vgui.Create("DPanel", sc)
				empty:Dock(TOP)
				empty:SetTall(S(70))
				empty:DockMargin(0, 0, S(4), 0)
				local txt = P.L(P.ChipLiveAt and (onlyBad and "chip_none_bad" or "chip_none") or "chip_loading")
				empty.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(8), C.panel, C.line)
					UI.Text(UI.Fit(txt, "Praetor.Small", w - S(20)), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			for _, c in ipairs(list) do rows[#rows + 1] = makeRow(c) end
		end

		entry.OnChange = function(s) search = s:GetValue() or "" order = "?" refill() end
		badT.DoClick = function(s)
			s:SetValue(not s.value)
			onlyBad = s.value
			order = "?"
			refill()
		end

		local hookId = "Praetor.ChipsTab." .. tostring(panel)
		hook.Add("Praetor.ChipsUpdated", hookId, function()
			if not IsValid(panel) then hook.Remove("Praetor.ChipsUpdated", hookId) return end
			refill()
		end)
		-- a hidden child tells when the tab goes away (the menu owns panel.OnRemove)
		local watch = vgui.Create("DPanel", panel)
		watch:SetSize(0, 0)
		watch:SetVisible(false)
		watch.OnRemove = function()
			hook.Remove("Praetor.ChipsUpdated", hookId)
			P.ChipSub("tab", false)
		end
		P.ChipSub("tab", true)
		order = "?"
		refill()
	end,
})
