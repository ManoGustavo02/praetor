-- Praetor menu: Support rooms. The rooms of this map (create where you stand,
-- go, move, rename, delete), the rooms running now (join, end) and a quick
-- start with two players. Settings: sky room when none is free, god mode
-- inside, open a room when a report / Blackbox case is claimed.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local info = { list = {}, sits = {}, map = game.GetMap(), max = 10 }

local function cardHead(parent, title, sub, icon, col)
	local h = vgui.Create("DPanel", parent)
	h:Dock(TOP)
	h:SetTall(S(46))
	h.Paint = function(_, w, hh)
		UI.Round(0, S(6), S(30), S(30), S(7), Color(col.r, col.g, col.b, 45))
		UI.Icon(icon, (S(30) - 16) / 2, S(6) + (S(30) - 16) / 2, 16)
		UI.Text(title, "Praetor.BodyB", S(40), S(14), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(UI.Fit(sub, "Praetor.Tiny", w - S(44)), "Praetor.Tiny", S(40), S(32), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Rect(0, hh - 1, w, 1, C.line)
	end
	return h
end

local function sendSetting(k, v) P.Request("settings_set", { v = { [k] = v } }) end

P.AddTab("sits", {
	cat = "moderation", icon = "headset", order = 1.5,
	can = function() return P.MyHas("sit") or P.MyHas("manage_sits") end,
	build = function(panel)
		local canManage = P.MyHas("manage_sits")

		-- ---------------------------------------------------------- right: now + start + options
		local right = vgui.Create("DPanel", panel)
		right:Dock(RIGHT)
		right:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.42), S(300), S(420)))
		right:DockMargin(S(10), 0, 0, 0)
		right.Paint = nil
		local rsc = UI.Scroll(right)
		rsc:Dock(FILL)

		cardHead(rsc, P.L("sit_now"), P.L("sit_now_d"), "headset", C.sky)
		local nowList = vgui.Create("DPanel", rsc)
		nowList:Dock(TOP)
		nowList:DockMargin(0, S(6), S(4), S(10))
		nowList.Paint = nil

		cardHead(rsc, P.L("sit_quick"), P.L("sit_quick_d"), "players", C.bronze)
		local pickA = UI.PlayerPick(rsc, "", nil, { noSelf = true })
		pickA:Dock(TOP)
		pickA:DockMargin(0, S(8), S(4), S(6))
		local pickB = UI.PlayerPick(rsc, "", nil, { noSelf = true })
		pickB:Dock(TOP)
		pickB:DockMargin(0, 0, S(4), S(8))
		local startRow = vgui.Create("DPanel", rsc)
		startRow:Dock(TOP)
		startRow:SetTall(S(36))
		startRow:DockMargin(0, 0, S(4), S(4))
		startRow.Paint = nil
		local roomOpts = { { "", P.L("sit_any_room") } }
		local roomPick = UI.Combo(startRow, roomOpts, "")
		roomPick:Dock(FILL)
		roomPick:DockMargin(0, 0, S(6), 0)
		local start = UI.Button(startRow, P.L("sit_start"), "primary", "headset", function()
			local sids = {}
			for _, pk in ipairs({ pickA, pickB }) do
				local pl = pk:GetPlayer()
				if IsValid(pl) then sids[#sids + 1] = pl:SteamID64() end
			end
			local _, room = roomPick:GetSelected()
			P.Request("sit_start", { sids = sids, room = room or "" })
			timer.Simple(0.5, function() if IsValid(panel) then P.Request("sit_rooms") end end)
		end)
		start:Dock(RIGHT)
		start:SetWide(S(150))
		local tip = UI.Label(rsc, P.L("sit_quick_tip"), "Praetor.Tiny", C.dim)
		tip:SetWrap(true)
		tip:SetAutoStretchVertical(true)
		tip:Dock(TOP)
		tip:DockMargin(S(2), S(2), S(4), S(12))

		if P.MyHas("settings") then
			cardHead(rsc, P.L("sit_opts"), P.L("sit_opts_d"), "gear", C.muted)
			for _, k in ipairs({ "sit_auto", "sit_god", "sit_on_claim" }) do
				local sw = UI.Switch(rsc, P.L("set_" .. k), P.L("setd_" .. k, nil, ""), P.Setting(k) == true, function(v) sendSetting(k, v) end)
				sw:Dock(TOP)
				sw:DockMargin(0, 0, S(4), 0)
			end
		end

		local function fillNow()
			if not IsValid(nowList) then return end
			nowList:Clear()
			local sits = info.sits or {}
			if #sits == 0 then
				nowList:SetTall(S(54))
				local e = vgui.Create("DPanel", nowList)
				e:Dock(FILL)
				e.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(6), C.panel, C.line)
					UI.Text(P.L("sit_none_now"), "Praetor.Small", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			nowList:SetTall(#sits * S(80))
			for _, s in ipairs(sits) do
				local c = vgui.Create("DPanel", nowList)
				c:Dock(TOP)
				c:SetTall(S(74))
				c:DockMargin(0, 0, 0, S(6))
				local t0 = RealTime() - (tonumber(s.age) or 0)
				c.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(8), C.panel, Color(C.sky.r, C.sky.g, C.sky.b, 120))
					UI.Text(UI.Fit(s.room or "?", "Praetor.SmallB", w - S(170)), "Praetor.SmallB", S(12), S(16), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local secs = math.floor(RealTime() - t0)
					local tag = s.case and ("Blackbox #" .. s.case) or (s.rep and (P.L("sit_report") .. " #" .. s.rep) or nil)
					UI.Text(string.format("%02d:%02d", math.floor(secs / 60), secs % 60) .. (tag and ("  ·  " .. tag) or ""), "Praetor.Tiny", S(12), S(34), C.sky, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local ax = S(12)
					for _, m in ipairs(s.m or {}) do
						local p = player.GetBySteamID64(m.sid)
						UI.DrawAvatar(m.sid, IsValid(p) and p or nil, ax, h - S(28), S(22), 255, m.st and C.sky or nil, m.n)
						ax = ax + S(26)
						if ax > w - S(180) then break end
					end
				end
				local endB = UI.Button(c, P.L("sit_end"), "danger", nil, function()
					P.Request("sit_end", { id = s.id })
					timer.Simple(0.4, function() if IsValid(panel) then P.Request("sit_rooms") end end)
				end)
				endB:SetSize(S(80), S(30))
				local join = UI.Button(c, P.L("sit_join"), "ghost", "headset", function() P.Request("sit_join", { id = s.id }) end)
				join:SetSize(S(80), S(30))
				c.PerformLayout = function(_, w, h)
					endB:SetPos(w - S(90), h - S(40))
					join:SetPos(w - S(176), h - S(40))
				end
			end
		end

		-- ---------------------------------------------------------- left: rooms of this map
		local bar = UI.Toolbar(panel, S(36))
		local nameE
		if canManage then
			local save = UI.Button(bar, P.L("sit_save_here"), "primary", "pin", function()
				P.Request("sit_room_add", { name = nameE:GetValue() })
				nameE:SetValue("")
			end)
			save:Dock(RIGHT)
			save:SizeToLabel(S(14))
			save:DockMargin(S(6), 0, 0, 0)
			nameE = UI.Entry(bar, P.L("sit_name_ph"), "")
			nameE:Dock(FILL)
		else
			local l = UI.Label(bar, P.L("sit_need_manage"), "Praetor.Small", C.muted)
			l:Dock(FILL)
		end

		local mapBar = vgui.Create("DPanel", panel)
		mapBar:Dock(TOP)
		mapBar:SetTall(S(26))
		mapBar.Paint = function(_, w, h)
			UI.Icon("map", 0, (h - 16) / 2, 16)
			UI.Text(P.L("sit_map", { S = info.map or game.GetMap(), V = #(info.list or {}), M = info.max or 10 }), "Praetor.SmallB", S(24), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.Rect(0, h - 1, w, 1, C.line)
		end

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)
		sc:DockMargin(0, S(6), 0, 0)

		local function fillRooms()
			if not IsValid(sc) then return end
			sc:Clear()
			-- the start box can pick a room
			roomPick:Clear()
			roomPick:AddChoice(P.L("sit_any_room"), "", true)
			for _, r in ipairs(info.list or {}) do roomPick:AddChoice(r.name, r.id) end
			local list = info.list or {}
			if #list == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(220))
				e.Paint = function(_, w, h)
					UI.Round(w / 2 - S(32), S(20), S(64), S(64), S(32), C.panel2)
					UI.Icon("headset", w / 2 - 16, S(52) - 16, 32)
					UI.Text(P.L("sit_rooms_none"), "Praetor.BodyB", w / 2, S(108), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					local lines = UI.Wrap(P.L(P.Setting("sit_auto") and "sit_rooms_none_auto" or "sit_rooms_none_d"), "Praetor.Tiny", math.min(w - S(40), S(460)))
					for i, l in ipairs(lines) do UI.Text(l, "Praetor.Tiny", w / 2, S(128) + (i - 1) * S(15), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
				end
				return
			end
			for i, r in ipairs(list) do
				local row = vgui.Create("DPanel", sc)
				row:Dock(TOP)
				row:SetTall(S(58))
				row:DockMargin(0, 0, S(4), S(5))
				row.Paint = function(_, w, h)
					UI.Round(0, 0, w, h, S(8), C.panel, r.busy and Color(C.sky.r, C.sky.g, C.sky.b, 120) or C.line)
					UI.Round(S(10), (h - S(34)) / 2, S(34), S(34), S(8), Color(C.bronze.r, C.bronze.g, C.bronze.b, 40))
					UI.Text(tostring(i), "Praetor.BodyB", S(27), h / 2, C.ivory, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(UI.Fit(r.name, "Praetor.BodyB", w - S(330)), "Praetor.BodyB", S(56), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local pos = r.pos or {}
					local sub = string.format("%d  %d  %d", pos[1] or 0, pos[2] or 0, pos[3] or 0) .. (r.by and ("  ·  " .. P.L("sit_by", { S = r.by })) or "")
					UI.Text(UI.Fit(sub, "Praetor.Tiny", w - S(330)), "Praetor.Tiny", S(56), S(39), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					if r.busy then
						surface.SetFont("Praetor.Tiny")
						local tw = surface.GetTextSize(P.L("sit_busy")) + S(16)
						local bx = w - S(310) - tw
						UI.Round(bx, (h - S(20)) / 2, tw, S(20), S(10), Color(C.sky.r, C.sky.g, C.sky.b, 50), C.sky)
						UI.Text(P.L("sit_busy"), "Praetor.Tiny", bx + tw / 2, h / 2, C.sky, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
				end
				local btns = {}
				local function btn(label, icon, kind, fn, tipText)
					local b = UI.Button(row, label, kind, icon, fn)
					b:SetFont("Praetor.Small")
					if tipText then b:SetTooltip(tipText) end
					btns[#btns + 1] = b
					return b
				end
				btn(P.L("sit_go"), "jump", "ghost", function() P.Request("sit_room_go", { id = r.id }) end)
				if canManage then
					btn("", "pin", "ghost", function()
						UI.Confirm(P.L("sit_move"), P.L("sit_move_q", { S = r.name }), function() P.Request("sit_room_edit", { id = r.id, here = true }) end)
					end, P.L("sit_move"))
					btn("", "pen", "ghost", function()
						UI.Form(P.L("sit_rename"), { { "name", "text", P.L("sit_name"), r.name } }, function(v)
							if P.Trim(v.name or "") == "" then return false end
							P.Request("sit_room_edit", { id = r.id, name = v.name })
						end, P.L("ui_save"))
					end, P.L("sit_rename"))
					btn("", "trash", "subtle", function()
						UI.Confirm(P.L("sit_del"), P.L("sit_del_q", { S = r.name }), function() P.Request("sit_room_edit", { id = r.id, del = true }) end, true)
					end, P.L("ui_delete"))
				end
				row.PerformLayout = function(_, w, h)
					local x = w - S(10)
					for bi = #btns, 1, -1 do
						local b = btns[bi]
						local bw = bi == 1 and S(96) or S(36)
						x = x - bw
						b:SetSize(bw, S(32))
						b:SetPos(x, (h - S(32)) / 2)
						x = x - S(6)
					end
				end
			end
		end

		P.On("sit_rooms", function(d)
			info = d
			if IsValid(panel) then fillRooms() fillNow() end
		end)
		hook.Add("Praetor.SitsChanged", panel, function()
			info.sits = P.ActiveSits
			fillNow()
		end)
		fillRooms()
		fillNow()
		P.Request("sit_rooms")
	end,
})
