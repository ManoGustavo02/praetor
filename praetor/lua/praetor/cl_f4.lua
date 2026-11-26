-- Praetor: DarkRP F4 menu. Jobs with a preview (model you can turn, description,
-- weapons, salary, slots and what the job needs), the shop (entities, weapons,
-- shipments, ammo, food, vehicles), the laws and a bar of RP commands.
-- Everything is read from DarkRP's own tables (RPExtraTeams, DarkRPEntities,
-- CustomShipments...): Praetor has no job system of its own.
-- Server: Settings > DarkRP (f4, f4_commands).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local F4 = P.F4 or {}
P.F4 = F4

local function on() return P.IsDarkRP() and P.Setting("f4") ~= false end
F4.On = on

local function me() return LocalPlayer() end
local function rp(var) return IsValid(me()) and me().getDarkRPVar and me():getDarkRPVar(var) or nil end

local function money(v)
	v = tonumber(v) or 0
	if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(v) end
	return "$" .. string.Comma(v)
end

local function inkOn(c)
	return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 150 and C.ink or color_white
end

local function darkrp(...) RunConsoleCommand("darkrp", ...) end

-- ------------------------------------------------------------------ DarkRP data

local function jobModels(job)
	if istable(job.model) then return job.model end
	return { job.model }
end

local function jobModel(job)
	local ms = jobModels(job)
	local pref = DarkRP.getPreferredJobModel and DarkRP.getPreferredJobModel(job.team)
	if pref and table.HasValue(ms, pref) then return pref end
	return ms[1]
end

local function jobMax(job)
	local m = tonumber(job.max) or 0
	if m > 0 and m < 1 then m = math.ceil(player.GetCount() * m) end
	return m
end

local HL2_MODELS = {
	weapon_physcannon = "models/weapons/w_physics.mdl", weapon_physgun = "models/weapons/w_physics.mdl",
	weapon_stunstick = "models/weapons/w_stunbaton.mdl", weapon_crowbar = "models/weapons/w_crowbar.mdl",
	weapon_pistol = "models/weapons/w_pistol.mdl", weapon_357 = "models/weapons/w_357.mdl",
	weapon_smg1 = "models/weapons/w_smg1.mdl", weapon_ar2 = "models/weapons/w_irifle.mdl",
	weapon_shotgun = "models/weapons/w_shotgun.mdl", weapon_crossbow = "models/weapons/w_crossbow.mdl",
	weapon_rpg = "models/weapons/w_rocket_launcher.mdl", weapon_frag = "models/weapons/w_grenade.mdl",
	gmod_tool = "models/weapons/w_toolgun.mdl", gmod_camera = "models/maxofs2d/camera.mdl",
}

local function wepName(class)
	local w = weapons.GetStored(class)
	if w and w.PrintName then return language.GetPhrase(w.PrintName) end
	local l = list.Get("Weapon")[class]
	if l and l.PrintName then return language.GetPhrase(l.PrintName) end
	return language.GetPhrase(class)
end

local function wepModel(class)
	local w = weapons.GetStored(class)
	if w and isstring(w.WorldModel) and w.WorldModel ~= "" then return w.WorldModel end
	return HL2_MODELS[class]
end

-- can I buy / take this? -> ok, reason
local function canUse(item)
	local ply = me()
	if istable(item.allowed) and #item.allowed > 0 and not table.HasValue(item.allowed, ply:Team()) then
		return false, P.L("f4_not_your_job")
	end
	if isfunction(item.customCheck) then
		local ok, res = pcall(item.customCheck, ply)
		if ok and res == false then
			local msg = item.CustomCheckFailMsg
			if isfunction(msg) then local ok2, m2 = pcall(msg, ply, item) msg = ok2 and m2 or nil end
			return false, isstring(msg) and msg or P.L("f4_locked")
		end
	end
	return true
end

local function jobAvailable(job)
	local ply = me()
	if ply:Team() == job.team then return false, P.L("f4_you_are") end
	local max = jobMax(job)
	if max > 0 and team.NumPlayers(job.team) >= max then return false, P.L("f4_full") end
	if (job.admin or 0) == 1 and not ply:IsAdmin() then return false, P.L("f4_admin_only") end
	if (job.admin or 0) >= 2 and not ply:IsSuperAdmin() then return false, P.L("f4_superadmin_only") end
	if job.NeedToChangeFrom then
		local from = istable(job.NeedToChangeFrom) and job.NeedToChangeFrom or { job.NeedToChangeFrom }
		if not table.HasValue(from, ply:Team()) then
			local names = {}
			for _, t in ipairs(from) do names[#names + 1] = team.GetName(t) end
			return false, P.L("f4_need_from", { S = table.concat(names, ", ") })
		end
	end
	return canUse(job)
end

-- categories of a kind ("jobs", "entities", "shipments", "weapons", "ammo", "vehicles")
-- as { { name, color, items } }, or one plain list when DarkRP has none
local function grouped(kind, flat)
	local out = {}
	local cats = DarkRP.getCategories and DarkRP.getCategories()
	if cats and cats[kind] then
		for _, c in ipairs(cats[kind]) do
			local okSee = true
			if isfunction(c.canSee) then local ok, r = pcall(c.canSee, me()) okSee = not ok or r ~= false end
			if okSee and c.members and #c.members > 0 then
				out[#out + 1] = { name = c.name, col = c.color, items = c.members }
			end
		end
		if #out > 0 then return out end
	end
	if flat and #flat > 0 then out[1] = { name = "", items = flat } end
	return out
end

local function shopKinds()
	local kinds = {}
	kinds[#kinds + 1] = { id = "entities", key = "f4_tab_entities", icon = "box", items = function() return grouped("entities", DarkRPEntities) end }
	local seps, ships = {}, {}
	for _, s in ipairs(CustomShipments or {}) do
		if s.separate then seps[#seps + 1] = s end
		if not s.noship then ships[#ships + 1] = s end
	end
	kinds[#kinds + 1] = { id = "weapons", key = "f4_tab_weapons", icon = "gun", items = function()
		local g = grouped("weapons", nil)
		if #g > 0 then return g end
		return #seps > 0 and { { name = "", items = seps } } or {}
	end, empty = #seps == 0 }
	kinds[#kinds + 1] = { id = "shipments", key = "f4_tab_shipments", icon = "brief", items = function() return grouped("shipments", ships) end, empty = #ships == 0 }
	local ammo = GAMEMODE and GAMEMODE.AmmoTypes or {}
	kinds[#kinds + 1] = { id = "ammo", key = "f4_tab_ammo", icon = "bolt", items = function() return grouped("ammo", ammo) end, empty = #ammo == 0 }
	if FoodItems and table.Count(FoodItems) > 0 then
		kinds[#kinds + 1] = { id = "food", key = "f4_tab_food", icon = "leaf", items = function()
			local list = {}
			for _, f in pairs(FoodItems) do list[#list + 1] = f end
			table.sort(list, function(a, b) return (a.price or 0) < (b.price or 0) end)
			return { { name = "", items = list } }
		end }
	end
	if CustomVehicles and #CustomVehicles > 0 then
		kinds[#kinds + 1] = { id = "vehicles", key = "f4_tab_vehicles", icon = "car", items = function() return grouped("vehicles", CustomVehicles) end }
	end
	return kinds
end

-- price and buy command of a shop item
local function itemInfo(kind, it, idx)
	if kind == "entities" then return it.price, function() darkrp(it.cmd) end end
	if kind == "weapons" then return it.pricesep or it.price, function() darkrp("buy", it.name) end end
	if kind == "shipments" then return it.price, function() darkrp("buyshipment", it.name) end end
	if kind == "ammo" then return it.price, function() darkrp("buyammo", tostring(it.id or idx)) end end
	if kind == "food" then return it.price, function() darkrp("buyfood", it.name) end end
	if kind == "vehicles" then return it.price, function() darkrp("buyvehicle", it.name) end end
	return it.price, function() end
end

-- ------------------------------------------------------------------ RP commands

local function amount(key) return { { "v", "number", P.L(key or "f4_amount"), "" } } end
F4.Commands = {
	{ "dropmoney", "coin", ask = amount(), run = function(v) darkrp("dropmoney", tostring(v.v)) end },
	{ "give", "coin_plus", ask = amount(), hint = "f4c_give_hint", run = function(v) darkrp("give", tostring(v.v)) end },
	{ "drop", "gun", run = function() darkrp("drop") end },
	{ "selldoors", "door", confirm = true, run = function() darkrp("unownalldoors") end },
	{ "demote", "brief_minus", ask = { { "ply", "player", P.L("arg_player"), "" }, { "reason", "text", P.L("arg_reason"), "" } },
		run = function(v) darkrp("demote", v.ply, v.reason) end },
	{ "advert", "megaphone", ask = { { "text", "text", P.L("f4_text"), "" } }, run = function(v) darkrp("advert", v.text) end },
	{ "jobname", "tag", ask = { { "text", "text", P.L("f4_jobname"), "" } }, run = function(v) darkrp("job", v.text) end },
	{ "license", "license", run = function() darkrp("requestlicense") end, can = function() return not rp("HasGunlicense") end },
	-- police
	{ "wanted", "flag", cp = true, ask = { { "ply", "player", P.L("arg_player"), "" }, { "reason", "text", P.L("arg_reason"), "" } },
		run = function(v) darkrp("wanted", v.ply, v.reason) end },
	{ "unwanted", "flag", cp = true, ask = { { "ply", "player", P.L("arg_player"), "" } }, run = function(v) darkrp("unwanted", v.ply) end },
	{ "warrant", "scroll", cp = true, ask = { { "ply", "player", P.L("arg_player"), "" }, { "reason", "text", P.L("arg_reason"), "" } },
		run = function(v) darkrp("warrant", v.ply, v.reason) end },
	-- mayor
	{ "lockdown", "warn", mayor = true, run = function() darkrp("lockdown") end, can = function() return not GetGlobalBool("DarkRP_LockDown") end },
	{ "unlockdown", "check", mayor = true, run = function() darkrp("unlockdown") end, can = function() return GetGlobalBool("DarkRP_LockDown") end },
	{ "addlaw", "scale", mayor = true, ask = { { "text", "text", P.L("f4_law"), "" } }, run = function(v) darkrp("addlaw", v.text) end },
	{ "removelaw", "trash", mayor = true, ask = amount("f4_lawnum"), run = function(v) darkrp("removelaw", tostring(v.v)) end },
	{ "placelaws", "clipboard", mayor = true, run = function() darkrp("placelaws") end },
}

function F4.VisibleCommands()
	local out = {}
	local ply = me()
	for _, c in ipairs(F4.Commands) do
		local ok = true
		if c.cp and not (ply.isCP and ply:isCP()) then ok = false end
		if c.mayor and not (ply.isMayor and ply:isMayor()) then ok = false end
		if ok and c.can and not c.can() then ok = false end
		if ok then out[#out + 1] = c end
	end
	return out
end

function F4.RunCommand(c)
	local label = P.L("f4c_" .. c[1])
	if c.ask then
		local fields = table.Copy(c.ask)
		UI.Form(label, fields, function(v)
			for _, f in ipairs(c.ask) do
				local val = v[f[1]]
				if f[2] ~= "text" or f[1] ~= "reason" then
					if val == nil or P.Trim(tostring(val)) == "" then return false end
				end
			end
			c.run(v)
			UI.Sound("ok")
		end, label, S(440))
	elseif c.confirm then
		UI.Confirm(label, P.L("f4c_" .. c[1] .. "_q"), function() c.run() UI.Sound("ok") end, true)
	else
		c.run()
		UI.Sound("ok")
	end
end

-- ------------------------------------------------------------------ model framing (whole body, any size)

local function frameModel(mdl)
	local ent = mdl.Entity
	if not IsValid(ent) then return end
	local mn, mx = ent:GetRenderBounds()
	local height = math.Clamp(mx.z - mn.z, 20, 120)
	local midZ = mn.z + height / 2
	local w, h = mdl:GetSize()
	local fov = 28
	mdl:SetFOV(fov)
	local vt = math.tan(math.rad(fov / 2)) * math.min(h / math.max(1, w), 0.9)
	local dist = (height / 2 * 1.14) / math.max(0.05, vt)
	mdl:SetLookAt(Vector(0, 0, midZ))
	mdl:SetCamPos(Vector(dist, 0, midZ + height * 0.05))
end

-- a turning model on a comic stage; drag it with the mouse to turn it yourself
local function stage(parent, tint)
	local st = vgui.Create("DPanel", parent)
	st.tint = tint or C.bronze
	st.Paint = function(s, w, h)
		local t = s.tint
		UI.Round(0, 0, w, h, S(14), C.bg, C.line)
		-- halftone dots, stronger in the middle
		local step = S(13)
		for gy = S(10), h - S(10), step do
			for gx = S(10) + ((gy / step) % 2) * step / 2, w - S(10), step do
				local k = 1 - math.min(1, math.abs(gx - w / 2) / (w * 0.55))
				local r = math.max(1, math.floor(S(3) * k))
				surface.SetDrawColor(t.r, t.g, t.b, 26 * k)
				surface.DrawRect(gx - r / 2, gy - r / 2, r, r)
			end
		end
		for i = 0, 6 do
			local rw = w * (0.6 - i * 0.07)
			UI.Round(w / 2 - rw / 2, h - S(38) + i * 2, rw, S(18), S(9), Color(t.r, t.g, t.b, 14))
		end
	end
	local mdl = vgui.Create("DModelPanel", st)
	mdl:Dock(FILL)
	mdl:DockMargin(S(4), S(6), S(4), S(6))
	mdl:SetAmbientLight(Color(80, 70, 110))
	mdl:SetDirectionalLight(BOX_TOP, Color(255, 250, 240))
	mdl:SetDirectionalLight(BOX_FRONT, Color(170, 160, 210))
	mdl.yaw = 25
	mdl.spin = 22
	mdl.LayoutEntity = function(s, e)
		if s.drag then
			local mx = gui.MouseX()
			s.yaw = s.yaw + (mx - s.drag) * 0.6
			s.drag = mx
		else
			s.yaw = s.yaw + FrameTime() * s.spin
		end
		e:SetAngles(Angle(0, s.yaw, 0))
		if s.anim then s:RunAnimation() end
	end
	mdl.OnMousePressed = function(s, code) if code == MOUSE_LEFT then s.drag = gui.MouseX() s:MouseCapture(true) end end
	mdl.OnMouseReleased = function(s) s.drag = nil s:MouseCapture(false) end
	mdl:SetCursor("sizewe")
	mdl.PerformLayout = function(s) frameModel(s) end
	function st:SetModel(path, skin, anim)
		mdl:SetModel(path or "models/error.mdl")
		local ent = mdl.Entity
		if IsValid(ent) then
			ent:SetSkin(skin or 0)
			if anim then
				local seq = ent:LookupSequence("idle_all_01")
				if seq and seq > 0 then ent:ResetSequence(seq) end
				mdl.anim = true
			else
				mdl.anim = false
			end
		end
		frameModel(mdl)
	end
	st.mdl = mdl
	return st
end

-- ------------------------------------------------------------------ small drawing helpers

local function chip(x, y, text, font, fill, icon, h)
	surface.SetFont(font)
	local tw = surface.GetTextSize(text)
	h = h or S(24)
	local w = tw + S(18) + (icon and S(22) or 0)
	UI.Round(x + S(2), y + S(2), w, h, h / 2, C.ink)
	UI.Round(x, y, w, h, h / 2, fill, C.ink)
	local tx = x + S(9)
	if icon then UI.Icon(icon, tx, y + (h - 16) / 2, 16) tx = tx + S(22) end
	draw.SimpleText(text, font, tx, y + h / 2, inkOn(fill), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return w + S(2)
end

-- a header for a category: a coloured pill + a rule
local function catHead(parent, name, col, count)
	local head = vgui.Create("DPanel", parent)
	head:Dock(TOP)
	head:SetTall(S(34))
	head:DockMargin(0, S(8), S(6), S(6))
	head.Paint = function(_, w, h)
		col = col or C.bronze
		local t = P.Upper(name ~= "" and name or P.L("f4_all"))
		surface.SetFont("Praetor.SmallB")
		local tw = surface.GetTextSize(t) + S(24)
		UI.Comic(0, S(2), tw, h - S(8), (h - S(8)) / 2, col, C.ink, S(3))
		draw.SimpleText(t, "Praetor.SmallB", S(12), S(2) + (h - S(8)) / 2, inkOn(col), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local x = tw + S(10)
		if count then
			local n = tostring(count)
			surface.SetFont("Praetor.Tiny")
			local nw = surface.GetTextSize(n) + S(14)
			UI.Round(x, (h - S(4) - S(18)) / 2, nw, S(18), S(9), C.panel3, C.line)
			UI.Text(n, "Praetor.Tiny", x + nw / 2, (h - S(4)) / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			x = x + nw + S(8)
		end
		UI.Rect(x, (h - S(4)) / 2, w - x, 2, Color(C.line.r, C.line.g, C.line.b, 150))
	end
	return head
end

-- staggered fade-in for freshly built cards
local function appear(pnl, i)
	pnl:SetAlpha(0)
	pnl:AlphaTo(255, 0.18, math.min(i, 24) * 0.02)
end

-- ------------------------------------------------------------------ jobs tab

local function buildJobs(panel, f)
	local right = vgui.Create("DPanel", panel)
	right:Dock(RIGHT)
	right:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.42), S(330), S(440)))
	right:DockMargin(S(12), 0, 0, 0)
	right.Paint = function(_, w, h) UI.Tablet(0, 0, w, h, C.panel, C.line) end

	local list = UI.Scroll(panel)
	list:Dock(FILL)

	local selected
	local preview

	local function showJob(job)
		selected = job
		right:Clear()
		if not job then return end
		local pad = S(12)
		local col = job.color or C.bronze
		local inner = vgui.Create("DPanel", right)
		inner:Dock(FILL)
		inner:DockMargin(pad, pad, pad + S(4), pad + S(4))
		inner.Paint = nil
		inner:SetAlpha(0)
		inner:AlphaTo(255, 0.18)

		-- model, with arrows when the job has more than one
		local st = stage(inner, col)
		st:Dock(TOP)
		st:SetTall(math.Clamp(math.floor(panel:GetParent():GetTall() * 0.4), S(190), S(300)))
		local models = jobModels(job)
		local mi = 1
		for i, m in ipairs(models) do if m == jobModel(job) then mi = i end end
		st:SetModel(models[mi], 0, true)
		if #models > 1 then
			local function arrow(dir)
				local b = UI.Button(st, "", "ghost", nil, function()
					mi = (mi - 1 + dir) % #models + 1
					st:SetModel(models[mi], 0, true)
					if DarkRP.setPreferredJobModel then DarkRP.setPreferredJobModel(job.team, models[mi]) end
				end)
				b:SetSize(S(36), S(36))
				b.PaintOver = function(s, w, h)
					draw.NoTexture()
					surface.SetDrawColor(C.ivory)
					local cx, cy, z = w / 2 - S(1), (h - S(3)) / 2, S(6)
					if dir < 0 then
						surface.DrawPoly({ { x = cx + z / 2, y = cy - z }, { x = cx + z / 2, y = cy + z }, { x = cx - z, y = cy } })
					else
						surface.DrawPoly({ { x = cx - z / 2, y = cy - z }, { x = cx + z, y = cy }, { x = cx - z / 2, y = cy + z } })
					end
				end
				return b
			end
			local l, r = arrow(-1), arrow(1)
			st.PerformLayout = function(s, w, h)
				l:SetPos(S(8), h / 2 - S(18))
				r:SetPos(w - S(44), h / 2 - S(18))
			end
			local count = vgui.Create("DPanel", st)
			count:SetSize(S(60), S(22))
			count.Paint = function(_, w, h)
				local t = mi .. " / " .. #models
				UI.Round(0, 0, w, h, h / 2, C.panel2, C.line)
				UI.Text(t, "Praetor.Tiny", w / 2, h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			local oldLayout = st.PerformLayout
			st.PerformLayout = function(s, w, h)
				oldLayout(s, w, h)
				count:SetPos(w / 2 - S(30), h - S(30))
			end
		end

		-- name, chips
		local head = vgui.Create("DPanel", inner)
		head:Dock(TOP)
		head:SetTall(S(84))
		head:DockMargin(0, S(10), 0, 0)
		head.Paint = function(_, w, h)
			local name = UI.Fit(job.name or "?", "Praetor.H1", w)
			draw.SimpleText(name, "Praetor.H1", S(3), S(3), C.ink)
			draw.SimpleText(name, "Praetor.H1", 0, 0, col)
			local x = 0
			local y = S(34)
			x = x + chip(x, y, money(job.salary or 0) .. P.L("f4_per_pay"), "Praetor.Tiny", C.laurel, "coin")
			local max = jobMax(job)
			x = x + S(4) + chip(x, y, team.NumPlayers(job.team) .. (max > 0 and (" / " .. max) or "") .. " " .. P.L("f4_slots"), "Praetor.Tiny", C.panel3, "players")
			local y2 = y + S(28)
			x = 0
			local flags = {}
			if job.vote then flags[#flags + 1] = { P.L("f4_vote"), C.amber, "ballot" } end
			if job.hasLicense then flags[#flags + 1] = { P.L("sb_license"), C.sky, "license" } end
			if (job.admin or 0) == 1 then flags[#flags + 1] = { P.L("f4_admin_only"), C.crimson, "shield" } end
			if (job.admin or 0) >= 2 then flags[#flags + 1] = { P.L("f4_superadmin_only"), C.crimson, "crown" } end
			for _, fl in ipairs(flags) do
				x = x + S(4) + chip(x, y2, fl[1], "Praetor.Tiny", fl[2], fl[3], S(22))
			end
		end

		-- the button at the bottom
		local okJob, why = jobAvailable(job)
		local label = okJob and (job.vote and P.L("f4_ask_vote") or P.L("f4_become", { S = job.name })) or why
		local btn = UI.Button(inner, label, okJob and "primary" or "subtle", okJob and (job.vote and "ballot" or "check") or "lock", function()
			if not jobAvailable(job) then UI.Sound("error") return end
			local needsVote = job.vote or (isfunction(job.RequiresVote) and job.RequiresVote(me(), job.team))
			if needsVote then darkrp("vote" .. job.command) else darkrp(job.command) end
			UI.Sound("ok")
			F4.Close()
		end)
		btn:Dock(BOTTOM)
		btn:SetTall(S(44))
		btn:DockMargin(0, S(8), 0, 0)
		if not okJob then btn:SetEnabled(false) end

		-- description and weapons (scrolls when long)
		local sc = UI.Scroll(inner)
		sc:Dock(FILL)
		sc:DockMargin(0, S(6), 0, 0)
		local desc = vgui.Create("DPanel", sc)
		desc:Dock(TOP)
		local text = P.Trim((tostring(job.description or ""):gsub("\t", "")))
		desc.PerformLayout = function(s, w)
			s.lines = {}
			for part in (text ~= "" and text or P.L("f4_no_desc")):gmatch("[^\n]+") do
				for _, l in ipairs(UI.Wrap(P.Trim(part), "Praetor.Small", w - S(28))) do s.lines[#s.lines + 1] = l end
			end
			local h = S(40) + #s.lines * S(18) + S(10)
			if s:GetTall() ~= h then s:SetTall(h) end
		end
		desc.Paint = function(s, w, h)
			UI.Round(0, 0, w - S(6), h, S(12), C.panel2, C.line)
			UI.Icon("scroll", S(12), S(9), 20)
			UI.Text(P.L("f4_about"), "Praetor.SmallB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			for i, l in ipairs(s.lines or {}) do
				UI.Text(l, "Praetor.Small", S(14), S(36) + (i - 1) * S(18), C.text)
			end
		end
		local wl = vgui.Create("DPanel", sc)
		wl:Dock(TOP)
		wl:DockMargin(0, S(8), 0, 0)
		local weps = job.weapons or {}
		local per = 3
		local rows = math.max(1, math.ceil(#weps / per))
		wl:SetTall(S(38) + (#weps > 0 and rows * S(92) or S(30)))
		wl.Paint = function(_, w, h)
			UI.Round(0, 0, w - S(6), h, S(12), C.panel2, C.line)
			UI.Icon("gun", S(12), S(9), 20)
			UI.Text(P.L("f4_weapons") .. "  (" .. #weps .. ")", "Praetor.SmallB", S(38), S(19), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if #weps == 0 then UI.Text(P.L("f4_no_weapons"), "Praetor.Small", S(14), S(46), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		-- one tile per weapon: its world model and its name
		wl.PerformLayout = function(s, w)
			local tw = math.floor((w - S(6) - S(16) - (per - 1) * S(6)) / per)
			for i, t in ipairs(s.tiles or {}) do
				local cx = (i - 1) % per
				local cy = math.floor((i - 1) / per)
				t:SetPos(S(8) + cx * (tw + S(6)), S(36) + cy * S(92))
				t:SetSize(tw, S(86))
			end
		end
		wl.tiles = {}
		for i, class in ipairs(weps) do
			local t = vgui.Create("DPanel", wl)
			t.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(10), C.bg, C.line)
				UI.Text(UI.Fit(wepName(class), "Praetor.Tiny", w - S(8)), "Praetor.Tiny", w / 2, h - S(12), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			local mdl = wepModel(class)
			if mdl then
				local ic = vgui.Create("SpawnIcon", t)
				ic:SetModel(mdl)
				ic:SetSize(S(56), S(56))
				ic:SetMouseInputEnabled(false)
				t.PerformLayout = function(s2, w) ic:SetPos((w - S(56)) / 2, S(4)) end
			else
				t.PaintOver = function(_, w) UI.Icon("gun", (w - 32) / 2, S(14), 32) end
			end
			t:SetTooltip(class)
			appear(t, i)
			wl.tiles[i] = t
		end
	end

	local function fill()
		list:Clear()
		local n = 0
		local groups = grouped("jobs", RPExtraTeams)
		for _, g in ipairs(groups) do
			local jobs = {}
			for _, job in ipairs(g.items) do
				local okSee = true
				if isfunction(job.customCheck) and job.hideOnCheckFail then okSee = select(1, canUse(job)) end
				if okSee then jobs[#jobs + 1] = job end
			end
			if #jobs > 0 then
				catHead(list, g.name or "", g.col, #jobs)
				for _, job in ipairs(jobs) do
					n = n + 1
					local row = vgui.Create("DButton", list)
					row:SetText("")
					row:Dock(TOP)
					row:SetTall(S(66))
					row:DockMargin(0, 0, S(6), S(4))
					row.anim = 0
					local ic = vgui.Create("SpawnIcon", row)
					ic:SetModel(jobModel(job) or "models/player/kleiner.mdl")
					ic:SetSize(S(52), S(52))
					ic:SetPos(S(14), S(5))
					ic:SetMouseInputEnabled(false)
					local col = job.color or C.bronze
					row.OnCursorEntered = function() UI.Sound("hover") end
					row.Paint = function(s, w, h)
						local sel = selected == job
						local mine = me():Team() == job.team
						local okJob = jobAvailable(job)
						s.anim = UI.Lerp(s.anim, (s:IsHovered() or sel) and 1 or 0, 14)
						local off = S(3)
						w, h = w - off, h - off
						if s.anim > 0.02 then UI.Round(off, off, w, h, S(12), Color(C.ink.r, C.ink.g, C.ink.b, 210 * s.anim)) end
						UI.Round(0, 0, w, h, S(12), sel and Color(48, 36, 88) or P.LerpColor(s.anim, C.panel2, C.hover), sel and C.bronze or P.LerpColor(s.anim, C.line, C.lineL))
						UI.Round(S(5), S(8), S(4), h - S(16), S(2), col)
						local x = S(76)
						local name = UI.Fit(job.name or "?", "Praetor.BodyB", w - x - S(190))
						UI.Text(name, "Praetor.BodyB", x, S(20), (okJob or mine) and C.ivory or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Text(money(job.salary or 0) .. P.L("f4_per_pay"), "Praetor.Small", x, S(42), C.laurel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						-- right side: slots, and "you" / a lock
						local max = jobMax(job)
						local t = team.NumPlayers(job.team) .. (max > 0 and (" / " .. max) or "")
						surface.SetFont("Praetor.SmallB")
						local tw = surface.GetTextSize(t) + S(36)
						local full = max > 0 and team.NumPlayers(job.team) >= max
						UI.Round(w - tw - S(12), h / 2 - S(13), tw, S(26), S(13), full and C.crimson or C.panel3, full and C.ink or C.line)
						UI.Icon("players", w - tw - S(6), h / 2 - 8, 16)
						UI.Text(t, "Praetor.SmallB", w - S(12) - (tw - S(24)) / 2, h / 2, full and color_white or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						if mine then
							chip(w - tw - S(80), h / 2 - S(11), P.L("f4_you"), "Praetor.Tiny", C.bronze, nil, S(22))
						elseif not okJob then
							UI.Icon("lock", w - tw - S(36), h / 2 - 8, 16, Color(255, 255, 255, 150))
						end
					end
					row.DoClick = function()
						if selected ~= job then UI.Sound("tab") showJob(job) end
					end
					appear(row, n)
				end
			end
		end
		if n == 0 then
			local l = UI.Label(list, P.L("f4_no_jobs"), "Praetor.Body", C.muted)
			l:Dock(TOP)
		end
	end
	fill()
	-- start on my own job
	local mine
	for _, job in ipairs(RPExtraTeams or {}) do if job.team == me():Team() then mine = job end end
	timer.Simple(0, function() if IsValid(right) then showJob(mine or (RPExtraTeams or {})[1]) end end)
	panel.Refresh = function() fill() if selected then showJob(selected) end end
end

-- ------------------------------------------------------------------ shop tabs

local function buildShop(panel, kind)
	local bar = UI.Toolbar(panel, S(38))
	local search = UI.Tool(bar, UI.Entry(bar, P.L("f4_search"), ""), nil, FILL)
	local list = UI.Scroll(panel)
	list:Dock(FILL)
	local function fill()
		list:Clear()
		local q = P.Trim(search:GetValue()):lower()
		local n = 0
		local idx = 0
		for _, g in ipairs(kind.items()) do
			local items = {}
			for _, it in ipairs(g.items) do
				idx = idx + 1
				it.__idx = it.__idx or idx
				if q == "" or tostring(it.name or ""):lower():find(q, 1, true) then items[#items + 1] = it end
			end
			if #items > 0 then
				catHead(list, g.name or "", g.col, #items)
				local grid = vgui.Create("DIconLayout", list)
				grid:Dock(TOP)
				grid:DockMargin(0, 0, S(6), S(4))
				grid:SetSpaceX(S(8))
				grid:SetSpaceY(S(8))
				for _, it in ipairs(items) do
					n = n + 1
					local price, buy = itemInfo(kind.id, it, it.__idx)
					local card = grid:Add("DPanel")
					card:SetSize(S(168), S(214))
					card.anim = 0
					local ok, why = canUse(it)
					local mdl = it.model or (kind.id == "weapons" and wepModel(it.entity))
					local ic = vgui.Create("SpawnIcon", card)
					ic:SetModel(mdl or "models/props_junk/cardboard_box004a.mdl")
					ic:SetSize(S(92), S(92))
					ic:SetPos((S(168) - S(3) - S(92)) / 2, S(12))
					ic:SetMouseInputEnabled(false)
					card.Paint = function(s, w, h)
						s.anim = UI.Lerp(s.anim, (s:IsHovered() or s:IsChildHovered()) and 1 or 0, 14)
						local off = S(3)
						w, h = w - off, h - off
						UI.Round(off, off, w, h, S(14), Color(C.ink.r, C.ink.g, C.ink.b, 160 + 60 * s.anim))
						UI.Round(0, 0, w, h, S(14), P.LerpColor(s.anim, C.panel2, C.hover), P.LerpColor(s.anim, C.line, C.lineL))
						-- floor glow under the model
						UI.Round(w / 2 - S(40), S(96), S(80), S(10), S(5), Color(C.bronze.r, C.bronze.g, C.bronze.b, 30 + 30 * s.anim))
						UI.Text(UI.Fit(tostring(it.name or "?"), "Praetor.BodyB", w - S(16)), "Praetor.BodyB", w / 2, S(122), ok and C.ivory or C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						local extra
						if kind.id == "shipments" and it.amount then extra = "x" .. it.amount end
						if kind.id == "ammo" and it.amountGiven then extra = "x" .. it.amountGiven end
						if kind.id == "food" and it.energy then extra = "+" .. it.energy .. "%" end
						local pt = money(price or 0)
						surface.SetFont("Praetor.SmallB")
						local pw = surface.GetTextSize(pt) + S(18)
						local px = extra and (w / 2 - pw - S(2)) or (w / 2 - pw / 2)
						UI.Round(px, S(136), pw, S(22), S(11), C.laurel, C.ink)
						UI.Text(pt, "Praetor.SmallB", px + pw / 2, S(147), C.ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						if extra then
							surface.SetFont("Praetor.SmallB")
							local ew = surface.GetTextSize(extra) + S(16)
							UI.Round(w / 2 + S(2), S(136), ew, S(22), S(11), C.panel3, C.line)
							UI.Text(extra, "Praetor.SmallB", w / 2 + S(2) + ew / 2, S(147), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						end
					end
					local b = UI.Button(card, ok and P.L("f4_buy") or P.L("f4_locked_short"), ok and "primary" or "subtle", ok and "coin" or "lock", function()
						local can = canUse(it)
						if not can then UI.Sound("error") return end
						if (tonumber(rp("money")) or 0) < (tonumber(price) or 0) then
							UI.Sound("error")
							P.Toast(P.L("f4_no_money"), money(price), "warn", 3)
							return
						end
						buy()
						UI.Sound("ok")
					end)
					b:SetSize(S(168) - S(3) - S(20), S(34))
					b:SetPos(S(10), S(214) - S(3) - S(44))
					if not ok then b:SetEnabled(false) b:SetTooltip(why) card:SetTooltip(why) end
					appear(card, n)
				end
			end
		end
		if n == 0 then
			local l = UI.Label(list, P.L("f4_nothing"), "Praetor.Body", C.muted)
			l:Dock(TOP)
			l:DockMargin(S(4), S(10), 0, 0)
		end
	end
	search.OnChange = fill
	fill()
	panel.Refresh = fill
end

-- ------------------------------------------------------------------ city tab: laws + every command

local function buildCity(panel)
	local laws = vgui.Create("DPanel", panel)
	laws:Dock(RIGHT)
	laws:SetWide(math.Clamp(math.floor(panel:GetParent():GetWide() * 0.42), S(320), S(440)))
	laws:DockMargin(S(12), 0, 0, 0)
	laws.Paint = function(_, w, h)
		UI.Tablet(0, 0, w, h, C.panel, C.line)
		w, h = w - S(4), h - S(4)
		UI.Icon("scale", S(14), S(12), 24)
		draw.SimpleText(P.L("f4_laws"), "Praetor.H1", S(46) + S(2), S(10) + S(2), C.ink)
		draw.SimpleText(P.L("f4_laws"), "Praetor.H1", S(46), S(10), C.ivory)
		local list = DarkRP.getLaws and DarkRP.getLaws() or {}
		local y = S(50)
		for i, law in ipairs(list) do
			local lines = UI.Wrap(tostring(law), "Praetor.Small", w - S(66))
			if y + #lines * S(18) > h - S(10) then break end
			UI.Round(S(14), y, S(26), S(26), S(13), C.bronze, C.ink)
			UI.Text(i, "Praetor.SmallB", S(27), y + S(13), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			for li, l in ipairs(lines) do UI.Text(l, "Praetor.Small", S(50), y + S(4) + (li - 1) * S(18), C.text) end
			y = y + math.max(S(30), #lines * S(18) + S(10))
		end
		if #list == 0 then UI.Text(P.L("f4_no_laws"), "Praetor.Small", S(14), S(56), C.muted) end
	end

	local sc = UI.Scroll(panel)
	sc:Dock(FILL)
	local function fill()
		sc:Clear()
		local groups = {
			{ P.L("f4_cmd_all"), C.bronze, function(c) return not c.cp and not c.mayor end },
			{ P.L("f4_cmd_police"), C.sky, function(c) return c.cp end },
			{ P.L("f4_cmd_mayor"), C.amber, function(c) return c.mayor end },
		}
		local vis = F4.VisibleCommands()
		local n = 0
		for _, g in ipairs(groups) do
			local cmds = {}
			for _, c in ipairs(vis) do if g[3](c) then cmds[#cmds + 1] = c end end
			if #cmds > 0 then
				catHead(sc, g[1], g[2], #cmds)
				local grid = vgui.Create("DIconLayout", sc)
				grid:Dock(TOP)
				grid:DockMargin(0, 0, S(6), S(4))
				grid:SetSpaceX(S(8))
				grid:SetSpaceY(S(8))
				for _, c in ipairs(cmds) do
					n = n + 1
					local t = grid:Add("DButton")
					t:SetText("")
					t:SetSize(S(200), S(74))
					t.anim = 0
					t.OnCursorEntered = function() UI.Sound("hover") end
					t.Paint = function(s, w, h)
						s.anim = UI.Lerp(s.anim, s:IsHovered() and 1 or 0, 14)
						local off = S(3)
						local press = s:IsDown() and off or 0
						w, h = w - off, h - off
						UI.Round(off, off, w, h, S(14), C.ink)
						UI.Round(press, press, w, h, S(14), P.LerpColor(s.anim, C.panel2, C.hover), P.LerpColor(s.anim, C.line, g[2]))
						UI.Round(press + S(10), press + (h - S(40)) / 2, S(40), S(40), S(20), g[2], C.ink)
						UI.Icon(c[2], press + S(10) + 4, press + (h - 32) / 2, 32)
						UI.Text(UI.Fit(P.L("f4c_" .. c[1]), "Praetor.BodyB", w - S(66)), "Praetor.BodyB", press + S(58), press + S(24), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Text(UI.Fit(P.L("f4cd_" .. c[1]), "Praetor.Tiny", w - S(66)), "Praetor.Tiny", press + S(58), press + S(46), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
					t.DoClick = function() UI.Sound("click") F4.RunCommand(c) end
					appear(t, n)
				end
			end
		end
	end
	fill()
	panel.Refresh = fill
end

-- ------------------------------------------------------------------ the window

function F4.Close()
	local f = F4.frame
	F4.frame = nil
	if not IsValid(f) then return end
	UI.Sound("close")
	f:SetMouseInputEnabled(false)
	f:SetKeyboardInputEnabled(false)
	f:AlphaTo(0, 0.12, 0, function() if IsValid(f) then f:Remove() end end)
	if P.Music then P.Music("f4", false) end
end

function F4.Open(tabId)
	if not on() then return end
	if IsValid(F4.frame) then F4.frame:Remove() end
	local w = math.min(ScrW() - S(30), S(1260))
	local h = math.min(ScrH() - S(30), S(800))
	local OFF = S(6)
	local f = vgui.Create("EditablePanel")
	F4.frame = f
	f:SetSize(w, h)
	f:Center()
	f:MakePopup()
	UI.Sound("open")
	UI.PopIn(f, 0.34)
	if P.Music then P.Music("f4", true) end
	local side = S(236)
	local showBar = P.Setting("f4_commands") ~= false

	f.Paint = function(_, pw, ph)
		pw, ph = pw - OFF, ph - OFF
		UI.Window(0, 0, pw, ph, Color(C.bg.r, C.bg.g, C.bg.b, 250))
		local bw = UI.BW()
		draw.RoundedBoxEx(S(14), bw, bw, side - bw, ph - bw * 2, C.panel, true, false, true, false)
		UI.Rect(side, bw, bw, ph - bw * 2, C.line)
		UI.Rect(side + S(18), S(61), pw - side - S(36), 2, Color(C.line.r, C.line.g, C.line.b, 160))
	end
	f.OnKeyCodePressed = function(_, key)
		if key == KEY_F4 or key == KEY_ESCAPE then F4.Close() end
	end
	f.Think = function(s)
		if input.IsKeyDown(KEY_ESCAPE) and gui.IsGameUIVisible() then gui.HideGameUI() F4.Close() return end
		-- job / money / police changes refresh the open tab
		if RealTime() < (s.nextSig or 0) then return end
		s.nextSig = RealTime() + 0.5
		local sig = me():Team() .. ":" .. tostring(rp("money")) .. ":" .. tostring(me().isMayor and me():isMayor()) .. ":" .. tostring(GetGlobalBool("DarkRP_LockDown")) .. ":" .. tostring(rp("HasGunlicense"))
		if s.sig and sig ~= s.sig and IsValid(s.tab) and s.tab.Refresh and s.current ~= "jobs" then s.tab.Refresh() end
		if s.sig and sig ~= s.sig and IsValid(s.cmdBar) then s.cmdBar:Build() end
		s.sig = sig
	end

	-- me: avatar, name, job and money at the top of the sidebar
	local card = vgui.Create("DPanel", f)
	card:SetPos(S(12), S(12))
	card:SetSize(side - S(24), S(112))
	local av = UI.FramedAvatar(card, S(48), me())
	av:SetPos(S(10), S(10))
	card.Paint = function(_, cw, ch)
		cw, ch = cw - S(4), ch - S(4)
		UI.Comic(0, 0, cw, ch, S(14), C.panel2, C.line, S(4))
		local ply = me()
		UI.Text(UI.Fit(ply:Nick(), "Praetor.BodyB", cw - S(72)), "Praetor.BodyB", S(66), S(18), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local job = rp("job") or team.GetName(ply:Team())
		local jc = team.GetColor(ply:Team())
		chip(S(66), S(30), UI.Fit(job, "Praetor.Tiny", cw - S(100)), "Praetor.Tiny", jc, nil, S(20))
		UI.Round(S(10), S(68), cw - S(20), S(32), S(16), C.bg, C.line)
		UI.Icon("coin", S(16), S(68) + 8, 16)
		UI.Text(money(rp("money") or 0), "Praetor.BodyB", S(38), S(84), C.laurel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local sal = tonumber(rp("salary")) or 0
		if sal > 0 then UI.Text("+" .. money(sal), "Praetor.Tiny", cw - S(18), S(84), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
	end

	local nav = UI.Scroll(f)
	nav:SetPos(S(10), S(134))
	nav:SetSize(side - S(18), h - OFF - S(134) - S(46))

	-- hint at the bottom of the sidebar
	local hint = vgui.Create("DPanel", f)
	hint:SetPos(S(12), h - OFF - S(40))
	hint:SetSize(side - S(24), S(30))
	hint.Paint = function(_, hw, hh)
		chip(0, S(3), "F4", "Praetor.Tiny", C.panel3, nil, S(22))
		UI.Text(P.L("f4_close_hint"), "Praetor.Tiny", S(44), hh / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local tabs = {
		{ id = "jobs", key = "f4_tab_jobs", icon = "brief", build = function(p) buildJobs(p, f) end },
	}
	for _, k in ipairs(shopKinds()) do
		if not k.empty then tabs[#tabs + 1] = { id = k.id, key = k.key, icon = k.icon, build = function(p) buildShop(p, k) end } end
	end
	tabs[#tabs + 1] = { id = "city", key = "f4_tab_city", icon = "scale", build = buildCity }

	local titleBar = vgui.Create("DPanel", f)
	titleBar:SetPos(side + S(18), S(12))
	titleBar:SetSize(w - OFF - side - S(70), S(48))
	titleBar.Paint = function(_, tw, th)
		local t
		for _, x in ipairs(tabs) do if x.id == f.current then t = x end end
		if not t then return end
		local k = math.min(1, (RealTime() - (f.tabAt or 0)) / 0.35)
		local hop = math.floor(math.sin(k * math.pi) * S(6))
		UI.Icon(t.icon, 0, S(4) - hop, 36)
		UI.Text(P.L(t.key), "Praetor.H1", S(46), S(1), C.ivory)
		UI.Text(UI.Fit(P.L(t.key .. "_sub"), "Praetor.Small", tw - S(46)), "Praetor.Small", S(46), S(30), C.muted)
	end

	local close = vgui.Create("DButton", f)
	close:SetText("")
	close:SetSize(S(32), S(32))
	close:SetPos(w - OFF - S(48), S(14))
	close.OnCursorEntered = function() UI.Sound("hover") end
	close.Paint = function(s, cw, ch)
		s.h = UI.Lerp(s.h or 0, s:IsHovered() and 1 or 0, 16)
		UI.Round(0, 0, cw, ch, ch / 2, P.LerpColor(s.h, C.panel2, C.crimson), P.LerpColor(s.h, C.line, C.ink))
		draw.NoTexture()
		surface.SetDrawColor(s:IsHovered() and color_white or C.muted)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(14), 2, 45)
		surface.DrawTexturedRectRotated(cw / 2, ch / 2, S(14), 2, -45)
	end
	close.DoClick = F4.Close

	local barH = showBar and S(58) or 0
	local content = vgui.Create("DPanel", f)
	content:SetPos(side + S(18), S(70))
	content:SetSize(w - OFF - side - S(36), h - OFF - S(84) - barH)
	content.Paint = nil

	-- the RP command bar under the content
	if showBar then
		local cb = vgui.Create("DPanel", f)
		cb:SetPos(side + S(18), h - OFF - barH - S(4))
		cb:SetSize(w - OFF - side - S(36), barH)
		cb.Paint = function(_, bw2, bh2)
			UI.Round(0, S(6), bw2, bh2 - S(6), S(14), C.panel, C.line)
		end
		function cb:Build()
			self:Clear()
			local cmds = F4.VisibleCommands()
			local avail = self:GetWide() - S(16)
			local each = math.floor((avail - (#cmds - 1) * S(6)) / math.max(1, #cmds))
			local iconOnly = each < S(104)
			each = math.min(each, S(150))
			local x = S(8)
			for _, c in ipairs(cmds) do
				local b = vgui.Create("DButton", self)
				b:SetText("")
				b:SetPos(x, S(12))
				b:SetSize(each, barH - S(18))
				b:SetTooltip(P.L("f4cd_" .. c[1]))
				b.anim = 0
				b.OnCursorEntered = function() UI.Sound("hover") end
				b.Paint = function(s, bw3, bh3)
					s.anim = UI.Lerp(s.anim, s:IsHovered() and 1 or 0, 14)
					local off = S(3)
					local press = s:IsDown() and off or 0
					bw3, bh3 = bw3 - off, bh3 - off
					UI.Round(off, off, bw3, bh3, bh3 / 2, C.ink)
					local tint = c.cp and C.sky or (c.mayor and C.amber or C.bronze)
					UI.Round(press, press - math.floor(s.anim * S(1)), bw3, bh3, bh3 / 2, P.LerpColor(s.anim, C.panel2, tint), P.LerpColor(s.anim, C.line, C.ink))
					if iconOnly then
						UI.Icon(c[2], press + (bw3 - 20) / 2, press + (bh3 - 20) / 2, 20)
					else
						UI.Icon(c[2], press + S(10), press + (bh3 - 20) / 2, 20)
						UI.Text(UI.Fit(P.L("f4c_" .. c[1]), "Praetor.SmallB", bw3 - S(42)), "Praetor.SmallB", press + S(36), press + bh3 / 2, s.anim > 0.5 and inkOn(tint) or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
				end
				b.DoClick = function() UI.Sound("click") F4.RunCommand(c) end
				x = x + each + S(6)
			end
		end
		cb:Build()
		f.cmdBar = cb
	end

	function f:SelectTab(id)
		local t
		for _, x in ipairs(tabs) do if x.id == id then t = x end end
		t = t or tabs[1]
		if self.current ~= t.id then self.tabAt = RealTime() end
		self.current = t.id
		F4.last = t.id
		content:Clear()
		local p = vgui.Create("DPanel", content)
		p:Dock(FILL)
		p.Paint = nil
		self.tab = p
		local ok, err = pcall(t.build, p)
		if not ok then
			ErrorNoHalt("[Praetor] F4 '" .. t.id .. "': " .. tostring(err) .. "\n")
			UI.Label(p, "Error: " .. tostring(err), "Praetor.Small", C.crimsonL):Dock(TOP)
		end
		-- slide in from the right
		p:SetAlpha(0)
		p:DockMargin(S(24), 0, 0, 0)
		UI.Tween(p, 0.22, function(s2, k)
			local e = 1 - (1 - k) ^ 3
			s2:SetAlpha(255 * math.min(1, k * 1.6))
			s2:DockMargin(math.max(0, math.floor((1 - e) * S(24))), 0, 0, 0)
		end, function(s2)
			s2:SetAlpha(255)
			s2:DockMargin(0, 0, 0, 0)
			if IsValid(content) then content:InvalidateLayout(true) end
		end)
	end

	for _, t in ipairs(tabs) do
		local b = vgui.Create("DButton", nav)
		b:SetText("")
		b:Dock(TOP)
		b:SetTall(S(40))
		b:DockMargin(0, 0, 0, S(2))
		b.anim, b.sel = 0, 0
		b.OnCursorEntered = function() UI.Sound("hover") end
		b.Paint = function(s, bw, bh)
			local isOn = f.current == t.id
			s.anim = UI.Lerp(s.anim, s:IsHovered() and 1 or 0, 14)
			s.sel = UI.Lerp(s.sel, isOn and 1 or 0, 12)
			bw, bh = bw - S(4), bh - S(3)
			if s.sel > 0.02 then
				local grow = math.floor((1 - s.sel) * S(14))
				UI.Round(grow + S(3), S(3), bw - grow * 2, bh, bh / 2, Color(C.ink.r, C.ink.g, C.ink.b, 200 * s.sel))
				UI.Round(grow, 0, bw - grow * 2, bh, bh / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 255 * s.sel), Color(C.ink.r, C.ink.g, C.ink.b, 255 * s.sel))
			end
			if s.anim > 0.01 and not isOn then UI.Round(0, 0, bw, bh, bh / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 46 * s.anim)) end
			local nudge = math.floor(s.anim * S(3))
			UI.Icon(t.icon, S(12) + nudge, (bh - 20) / 2, 20)
			UI.Text(P.L(t.key), isOn and "Praetor.BodyB" or "Praetor.Body", S(40) + nudge, bh / 2, isOn and color_white or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() if f.current ~= t.id then UI.Sound("tab") f:SelectTab(t.id) end end
	end

	f:SelectTab(tabId or F4.last or "jobs")
	return f
end

function F4.Toggle()
	if IsValid(F4.frame) then F4.Close() else F4.Open() end
end

-- ------------------------------------------------------------------ taking over DarkRP's F4

hook.Add("PlayerBindPress", "Praetor.F4", function(_, bind, pressed)
	if not pressed or not on() then return end
	if bind:lower():find("gm_showspare2", 1, true) then
		F4.Toggle()
		return true
	end
end)

-- DarkRP opens its menu from the server (ShowSpare2) through these functions:
-- while Praetor's F4 is on they open this one instead
local function wrap()
	if not DarkRP or DarkRP.__praetorF4 then return end
	local open, close, toggle = DarkRP.openF4Menu, DarkRP.closeF4Menu, DarkRP.toggleF4Menu
	if not open and not toggle then return end
	DarkRP.__praetorF4 = true
	DarkRP.openF4Menu = function(...) if on() then return F4.Open() end if open then return open(...) end end
	DarkRP.closeF4Menu = function(...) if on() then return F4.Close() end if close then return close(...) end end
	DarkRP.toggleF4Menu = function(...) if on() then return F4.Toggle() end if toggle then return toggle(...) end end
end
hook.Add("InitPostEntity", "Praetor.F4", function() timer.Simple(1, wrap) end)
hook.Add("DarkRPFinishedLoading", "Praetor.F4", function() timer.Simple(0, wrap) end)
if IsValid(LocalPlayer()) then wrap() end

concommand.Add("praetor_f4", function() F4.Toggle() end)
