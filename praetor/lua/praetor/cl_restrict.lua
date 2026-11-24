-- Praetor: restrictions on the client. Keeps the rules, knows the name / icon /
-- model of every item, adds "Praetor" to the right click menu of the spawn
-- menu (Q) and draws a seal on restricted icons: red lock = blacklist,
-- amber shield = admin only, rank icon in the rank colour = from that rank up.
-- Players who can't use an item see it dimmed with a lock. Hovering shows a
-- card that follows the mouse; a refused spawn shows a card at the icon.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

P.Restrict = P.Restrict or {}
P.RestrictKinds = { "weapon", "entity", "npc", "vehicle", "prop", "tool" }
P.RestrictKindIcon = { weapon = "gun", entity = "box", npc = "npc", vehicle = "car", prop = "box", tool = "wrench" }

local function key(kind, class) return kind .. ":" .. tostring(class or ""):lower():gsub("\\", "/") end
P.RestrictKey = key

P.On("rs_list", function(d)
	P.Restrict = istable(d.list) and d.list or {}
	hook.Run("Praetor.RestrictChanged")
end)

function P.RestrictRule(kind, class) return P.Restrict[key(kind, class)] end

-- same answer the server gives, for the local player
function P.RestrictAllowsMe(kind, class)
	local rule = P.RestrictRule(kind, class)
	if not rule then return true end
	local me = LocalPlayer()
	if not IsValid(me) or P.IsOwner(me) then return true end
	if rule.m == "block" then return false end
	if rule.m == "staff" then return P.IsStaff(me) or P.Inherits(me:GetUserGroup(), "admin") end
	if rule.m == "rank" then
		local rk = P.Ranks[rule.r or ""]
		if not rk then return true end
		return P.Inherits(me:GetUserGroup(), rk.name) or P.Authority(me) >= (rk.immunity or 0)
	end
	return true
end

-- colour, icon and label of a rule
function P.RestrictStyle(rule)
	if not rule then return C.laurel, "check", P.L("rs_m_free") end
	if rule.m == "block" then return C.crimson, "lock", P.L("rs_m_block") end
	if rule.m == "staff" then return C.amber, "shield", P.L("rs_m_staff") end
	local rk = P.Ranks[rule.r or ""]
	local style, icon = UI.RankStyle(rule.r or "user")
	local col = style and style.c1 and Color(style.c1.r, style.c1.g, style.c1.b) or C.bronzeL
	return col, icon or "crown", P.L("rs_m_rank", { S = rk and (rk.display or rk.name) or tostring(rule.r) })
end

-- ------------------------------------------------------------------ item info

local function nice(s)
	s = tostring(s or "")
	if s:sub(1, 1) == "#" then s = language.GetPhrase(s:sub(2)) end
	return s
end

local function iconPath(class, override)
	if isstring(override) and override ~= "" then return override end
	for _, p in ipairs({ "entities/" .. class .. ".png", "vgui/entities/" .. class .. ".png" }) do
		if file.Exists("materials/" .. p, "GAME") then return p end
	end
	return nil
end

-- every item of a kind that can be restricted: { c, name, cat, icon, mdl }
local function buildCatalog(kind)
	local out = {}
	if kind == "weapon" then
		for class, w in pairs(list.Get("Weapon")) do
			if w.Spawnable ~= false then
				local stored = weapons.GetStored(class)
				out[#out + 1] = { c = class:lower(), name = nice(w.PrintName or class), cat = nice(w.Category or ""), icon = iconPath(class, w.IconOverride), mdl = stored and stored.WorldModel or nil }
			end
		end
	elseif kind == "entity" then
		for class, e in pairs(list.Get("SpawnableEntities")) do
			local stored = scripted_ents.GetStored(class)
			out[#out + 1] = { c = class:lower(), name = nice(e.PrintName or class), cat = nice(e.Category or ""), icon = iconPath(class, e.IconOverride), mdl = stored and stored.t and stored.t.Model or nil }
		end
	elseif kind == "npc" then
		for class, n in pairs(list.Get("NPC")) do
			out[#out + 1] = { c = class:lower(), name = nice(n.Name or class), cat = nice(n.Category or ""), icon = iconPath(class, n.IconOverride), mdl = n.Model }
		end
	elseif kind == "vehicle" then
		for class, v in pairs(list.Get("Vehicles")) do
			out[#out + 1] = { c = class:lower(), name = nice(v.Name or class), cat = nice(v.Category or ""), icon = iconPath(class, v.IconOverride), mdl = v.Model }
		end
	elseif kind == "prop" then
		-- props of the spawn lists (Q menu > Spawnlists), without repeats
		local seen = {}
		local ok, lists = pcall(spawnmenu.GetPropTable)
		for _, sl in pairs(ok and istable(lists) and lists or {}) do
			for _, it in ipairs(istable(sl) and sl.contents or {}) do
				local mdl = istable(it) and it.type == "model" and isstring(it.model) and it.model:lower():gsub("\\", "/")
				if mdl and not seen[mdl] then
					seen[mdl] = true
					out[#out + 1] = { c = mdl, name = mdl:match("([^/]+)%.mdl$") or mdl, cat = tostring(sl.name or ""), mdl = mdl }
				end
			end
		end
	elseif kind == "tool" then
		local tool = weapons.GetStored("gmod_tool")
		for mode, t in pairs(tool and tool.Tool or {}) do
			if t.AddToMenu ~= false then
				out[#out + 1] = { c = mode:lower(), name = nice(t.Name or mode), cat = nice(t.Category or ""), icon = nil }
			end
		end
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

-- the lists change only when addons load, so they are kept for a minute
local catCache = {}
function P.RestrictCatalog(kind)
	local c = catCache[kind]
	if c and c.t > RealTime() then return c.list end
	local list = buildCatalog(kind)
	catCache[kind] = { t = RealTime() + 60, list = list }
	return list
end

local infoCache = {}
hook.Add("Praetor.RestrictChanged", "Praetor.RestrictInfo", function() infoCache = {} end)

-- name, icon and model of one item (props: the model itself)
function P.RestrictInfo(kind, class)
	local k = key(kind, class)
	if infoCache[k] then return infoCache[k] end
	local info = { c = class, name = class, cat = "" }
	if kind == "prop" then
		info.name = tostring(class):match("([^/]+)%.mdl$") or class
		info.mdl = class
	else
		for _, it in ipairs(P.RestrictCatalog(kind)) do
			if it.c == class then info = it break end
		end
	end
	infoCache[k] = info
	return info
end

local mats = {}
function P.RestrictMat(path)
	if not path then return nil end
	if mats[path] == nil then
		local m = Material(path, "smooth")
		mats[path] = (m and not m:IsError()) and m or false
	end
	return mats[path] or nil
end

-- ------------------------------------------------------------------ actions

function P.RestrictSet(kind, class, mode, rank, pk)
	if mode == "free" then
		P.Request("rs_del", { k = kind, c = class })
	else
		local cur = P.RestrictRule(kind, class)
		if pk == nil and cur then pk = cur.pk end
		P.Request("rs_set", { k = kind, c = class, m = mode, r = rank, pk = pk })
	end
	UI.Sound("click")
end

-- items for a right click menu (UI.FillMenu format)
function P.RestrictMenuItems(kind, class, name)
	local rule = P.RestrictRule(kind, class)
	local items = {}
	local col, icon, label = P.RestrictStyle(rule)
	items[#items + 1] = { P.L("rs_now", { S = label }), kind = "title" }
	if not P.MyHas("manage_restrict") then return items end
	local function mark(on, t) return (on and "> " or "") .. t end
	items[#items + 1] = { mark(not rule, P.L("rs_m_free")), "check", function() P.RestrictSet(kind, class, "free") end }
	items[#items + 1] = { mark(rule and rule.m == "block", P.L("rs_m_block")), "lock", function() P.RestrictSet(kind, class, "block") end, true }
	items[#items + 1] = { mark(rule and rule.m == "staff", P.L("rs_m_staff")), "shield", function() P.RestrictSet(kind, class, "staff") end }
	local ranks = P.SortedRanks()
	table.sort(ranks, function(a, b) return (a.immunity or 0) < (b.immunity or 0) end)
	local sub = {}
	for _, r in ipairs(ranks) do
		if r.name ~= "user" then
			local _, ricon = UI.RankStyle(r)
			sub[#sub + 1] = { mark(rule and rule.m == "rank" and rule.r == r.name, P.L("rs_m_rank", { S = r.display or r.name })), ricon or "crown", function() P.RestrictSet(kind, class, "rank", r.name) end }
		end
	end
	items[#items + 1] = { P.L("rs_from_rank"), "crown", nil, nil, sub }
	if kind == "weapon" and rule then
		items[#items + 1] = { rule.pk == false and P.L("rs_pk_on") or P.L("rs_pk_off"), "hand", function() P.RestrictSet(kind, class, rule.m, rule.r, rule.pk == false) end }
	end
	items[#items + 1] = false
	if kind == "weapon" then
		items[#items + 1] = { P.L("rs_strip"), "gun_no", function() P.Request("rs_strip", { c = class }) end }
		if P.MyHas("give") then
			items[#items + 1] = { P.L("rs_give"), "gun_ok", function()
				UI.PlayerPicker(function(pl)
					if IsValid(pl) then P.Request("rs_give", { c = class, sid = pl:IsBot() and ("$" .. pl:UserID()) or pl:SteamID64() }) end
				end, { title = P.L("rs_give") .. ": " .. tostring(name or class) })
			end }
		end
	elseif kind ~= "tool" then
		items[#items + 1] = { P.L("rs_clear"), "broom", function()
			UI.Confirm(P.L("rs_clear"), P.L("rs_clear_q", { S = name or class }), function() P.Request("rs_clear", { k = kind, c = class }) end, true)
		end, true }
	end
	items[#items + 1] = { P.L("rs_open"), "lock", function() P.OpenMenu("restrict", { kind = kind, class = class }) end }
	items[#items + 1] = { P.L("rs_copy"), "copy", function() SetClipboardText(class) end }
	return items
end

function P.RestrictPopup(kind, class, name)
	local m = UI.Popup(P.RestrictMenuItems(kind, class, name))
	return m
end

-- ------------------------------------------------------------------ spawn menu (Q)

local CT_KIND = { weapon = "weapon", entity = "entity", npc = "npc", vehicle = "vehicle", model = "prop" }

hook.Add("SpawnmenuIconMenuOpen", "Praetor.Restrict", function(menu, icon, ctype)
	local kind = CT_KIND[ctype or ""]
	if not kind or not IsValid(icon) then return end
	local class
	if kind == "prop" then class = icon.GetModelName and icon:GetModelName() else class = icon.GetSpawnName and icon:GetSpawnName() end
	if not isstring(class) or class == "" then return end
	class = class:lower():gsub("\\", "/")
	local rule = P.RestrictRule(kind, class)
	if not rule and not P.MyHas("manage_restrict") then return end
	menu:AddSpacer()
	local sub, opt = menu:AddSubMenu(P.MyHas("manage_restrict") and P.L("rs_menu") or "Praetor")
	opt:SetIcon("praetor/icons/" .. (rule and (rule.m == "block" and "lock_no" or "lock") or "lock_ok") .. ".png")
	local name = icon.GetToolTip and icon:GetToolTip() or nil
	UI.FillMenu(sub, P.RestrictMenuItems(kind, class, name))
	UI.ThemePopup(sub)
end)

-- ------------------------------------------------------------------ badge
-- A round seal in the top left corner of the icon: lock (blacklist), shield
-- (admin only) or the rank icon in the rank colour. Players who can't use the
-- item see it dimmed with thin stripes and a lock in the middle. The words are
-- in the card that follows the mouse, so the icon stays clean.

local function circle(x, y, r, fill, ring)
	if ring then UI.Round(x - r - 1, y - r - 1, r * 2 + 2, r * 2 + 2, r + 1, ring) end
	UI.Round(x - r, y - r, r * 2, r * 2, r, fill)
end

local function drawBadge(pnl, kind, class, w, h)
	local rule = P.RestrictRule(kind, class)
	if not rule then return end
	local col = P.RestrictStyle(rule)
	local _, icon = P.RestrictStyle(rule)
	local allowed = P.RestrictAllowsMe(kind, class)
	local hov = pnl:IsHovered()
	if not allowed then
		surface.SetDrawColor(8, 9, 12, hov and 120 or 170)
		surface.DrawRect(2, 2, w - 4, h - 4)
		surface.SetDrawColor(col.r, col.g, col.b, 26)
		for x = -h, w, 9 do surface.DrawLine(x, h, x + h, 0) end
		local r = math.floor(math.min(w, h) * 0.17)
		circle(w / 2, h / 2 - 4, r, Color(14, 15, 20, 235), Color(col.r, col.g, col.b, 230))
		UI.Icon("lock", w / 2 - 8, h / 2 - 4 - 8, 16, Color(col.r, col.g, col.b))
	end
	-- seal
	local r = 11
	local cx, cy = r + 5, r + 5
	circle(cx, cy, r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 240), Color(col.r, col.g, col.b, 255))
	UI.Icon(icon or "lock", cx - 8, cy - 8, 16, color_white)
	-- thin coloured line under the icon: the rule at a glance, even when small
	surface.SetDrawColor(col.r, col.g, col.b, allowed and 160 or 230)
	surface.DrawRect(3, h - 4, w - 6, 2)
end

local function patchPanel(pnl)
	if pnl.praetorBadge then return end
	local kind
	local ct = pnl.GetContentType and pnl:GetContentType()
	if ct and CT_KIND[ct] and ct ~= "model" then kind = CT_KIND[ct]
	elseif pnl.GetModelName and pnl.ClassName == "SpawnIcon" then kind = "prop" end
	if not kind then return end
	pnl.praetorBadge = kind
	local old = pnl.PaintOver
	pnl.PaintOver = function(s, w, h)
		if old then old(s, w, h) end
		local class
		if kind == "prop" then class = s:GetModelName() else class = s.GetSpawnName and s:GetSpawnName() end
		if isstring(class) and class ~= "" then
			class = class:lower():gsub("\\", "/")
			s.praetorClass = class
			if next(P.Restrict) then drawBadge(s, kind, class, w, h) end
		end
		-- shake when the server just refused this item
		local d = P.RestrictDenied
		if d and d.pnl == s and RealTime() - d.t < 0.6 then
			local a = 1 - (RealTime() - d.t) / 0.6
			surface.SetDrawColor(C.crimson.r, C.crimson.g, C.crimson.b, 200 * a)
			surface.DrawOutlinedRect(0, 0, w, h, 2)
		end
	end
end

-- new icons get the badge through the control table, the ones that already
-- exist when the spawn menu first opens are walked once
local patched = false
local function patchTables()
	for _, name in ipairs({ "ContentIcon", "SpawnIcon" }) do
		local t = vgui.GetControlTable(name)
		if t and not t.praetorPatched then
			t.praetorPatched = true
			local init = t.Init
			t.Init = function(s, ...)
				if init then init(s, ...) end
				timer.Simple(0, function() if IsValid(s) then patchPanel(s) end end)
			end
		end
	end
end

local function walk(pnl, depth)
	if depth > 40 or not IsValid(pnl) then return end
	patchPanel(pnl)
	for _, c in ipairs(pnl:GetChildren()) do walk(c, depth + 1) end
end

hook.Add("OnSpawnMenuOpen", "Praetor.Restrict", function()
	patchTables()
	if not patched and IsValid(g_SpawnMenu) then
		patched = true
		walk(g_SpawnMenu, 0)
	end
end)
hook.Add("PostGamemodeLoaded", "Praetor.Restrict", patchTables)

-- the icon the player clicked last (the refusal card points at it)
local function iconOf(pnl)
	local n = 0
	while IsValid(pnl) and n < 6 do
		if pnl.praetorBadge then return pnl end
		pnl = pnl:GetParent()
		n = n + 1
	end
end
hook.Add("VGUIMousePressed", "Praetor.RestrictClick", function(pnl)
	local ic = iconOf(pnl)
	if ic then P.RestrictClicked = { pnl = ic, t = RealTime() } end
end)

-- ------------------------------------------------------------------ cards

local function itemMat(kind, class)
	local info = P.RestrictInfo(kind, class)
	local m = info and info.icon and P.RestrictMat(info.icon)
	if m then return m end
	if kind == "prop" and class:sub(-4) == ".mdl" then return P.RestrictMat("spawnicons/" .. class:sub(1, -5) .. ".png") end
end

-- card with the item, the rule and what it means for the local player
local function drawCard(x, y, w, kind, class, rule, denied, alpha, pointAt)
	local col = P.RestrictStyle(rule)
	local _, icon, label = P.RestrictStyle(rule)
	local info = P.RestrictInfo(kind, class) or {}
	local allowed = P.RestrictAllowsMe(kind, class)
	local h = S(88)
	local a = alpha or 1
	local function A(c, mul) return Color(c.r, c.g, c.b, (c.a or 255) * a * (mul or 1)) end
	-- little arrow pointing at the icon
	if pointAt then
		draw.NoTexture()
		surface.SetDrawColor(A(col))
		local ax = math.Clamp(pointAt, x + S(16), x + w - S(16))
		surface.DrawPoly({ { x = ax - S(8), y = y }, { x = ax, y = y - S(8) }, { x = ax + S(8), y = y } })
	end
	UI.Round(x, y, w, h, S(10), A(Color(16, 17, 22), 0.97), A(col))
	UI.Round(x + 1, y + S(10), S(3), h - S(20), S(1), A(col))
	-- picture
	local ps = h - S(20)
	UI.Round(x + S(12), y + S(10), ps, ps, S(8), A(C.bg))
	local m = itemMat(kind, class)
	if m then
		surface.SetMaterial(m)
		surface.SetDrawColor(255, 255, 255, 255 * a)
		surface.DrawTexturedRect(x + S(14), y + S(12), ps - S(4), ps - S(4))
	else
		UI.Icon(P.RestrictKindIcon[kind] or "box", x + S(12) + ps / 2 - 16, y + S(10) + ps / 2 - 16, 32, A(color_white, 0.6))
	end
	-- seal on the picture
	local r = S(11)
	circle(x + S(12) + ps - r + S(2), y + S(10) + ps - r + S(2), r, A(Color(col.r * 0.25, col.g * 0.25, col.b * 0.25)), A(col))
	UI.Icon(icon or "lock", x + S(12) + ps - r + S(2) - 8, y + S(10) + ps - r + S(2) - 8, 16, A(color_white))
	local tx = x + S(12) + ps + S(12)
	local tw = w - (tx - x) - S(12)
	local title = denied and P.L("rs_card_denied") or (allowed and P.L("rs_card_ok") or P.L("rs_card_no"))
	UI.Text(UI.Fit(P.Upper(title), "Praetor.Tiny", tw), "Praetor.Tiny", tx, y + S(14), A(denied and C.crimsonL or (allowed and C.laurel or C.crimsonL)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(UI.Fit(info.name or class, "Praetor.BodyB", tw), "Praetor.BodyB", tx, y + S(34), A(C.ivory), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(UI.Fit(label, "Praetor.Small", tw), "Praetor.Small", tx, y + S(54), A(col), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local sub
	if rule.m == "rank" then sub = P.L("rs_card_rank", { S = denied and denied.rn or label })
	elseif rule.m == "staff" then sub = P.L("rs_card_staff")
	else sub = P.L("rs_card_block") end
	if denied and denied.pk then sub = P.L("rs_card_pickup") end
	UI.Text(UI.Fit(sub, "Praetor.Tiny", tw), "Praetor.Tiny", tx, y + S(72), A(C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return h
end

-- refusal from the server
P.On("rs_denied", function(d)
	if not isstring(d.k) or not isstring(d.c) then return end
	local clicked = P.RestrictClicked
	local pnl = clicked and IsValid(clicked.pnl) and RealTime() - clicked.t < 2 and clicked.pnl.praetorClass == d.c:lower() and clicked.pnl or nil
	P.RestrictDenied = { k = d.k, c = d.c:lower(), m = d.m, rn = d.rn, pk = d.pk, t = RealTime(), pnl = pnl }
	UI.Sound("error")
end)

hook.Add("DrawOverlay", "Praetor.RestrictCards", function()
	-- refusal card: next to the icon that was clicked (it follows the icon if
	-- the list scrolls), or low in the middle of the screen
	local d = P.RestrictDenied
	if d then
		local age = RealTime() - d.t
		local life = d.pk and 3 or 3.6
		if age > life then P.RestrictDenied = nil
		else
			local a = math.min(1, age * 6, (life - age) * 3)
			local rule = P.RestrictRule(d.k, d.c) or { m = d.m or "block", r = nil }
			local w = S(330)
			local shake = age < 0.35 and math.sin(age * 60) * (0.35 - age) * S(18) or 0
			local pnl = d.pnl
			if IsValid(pnl) and pnl:IsVisible() and IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then
				local px, py = pnl:LocalToScreen(0, 0)
				local pw, ph = pnl:GetSize()
				local x = math.Clamp(px + pw / 2 - w / 2, S(8), ScrW() - w - S(8))
				local y = py + ph + S(10)
				if y + S(90) > ScrH() then y = py - S(98) end
				drawCard(x + shake, y, w, d.k, d.c, rule, d, a, px + pw / 2 + shake)
			else
				local x = ScrW() / 2 - w / 2
				local y = ScrH() * 0.68
				drawCard(x + shake, y, w, d.k, d.c, rule, d, a)
			end
		end
	end
	-- hover card that follows the mouse over restricted icons
	if not IsValid(g_SpawnMenu) or not g_SpawnMenu:IsVisible() then return end
	local hv = vgui.GetHoveredPanel()
	local ic = iconOf(hv)
	if not ic or not ic.praetorClass then return end
	local rule = P.RestrictRule(ic.praetorBadge, ic.praetorClass)
	if not rule then return end
	if d and d.pnl == ic then return end
	local mx, my = input.GetCursorPos()
	local w = S(300)
	local x = mx + S(18)
	local y = my + S(18)
	if x + w > ScrW() - S(6) then x = mx - w - S(12) end
	if y + S(90) > ScrH() - S(6) then y = my - S(96) end
	drawCard(x, y, w, ic.praetorBadge, ic.praetorClass, rule, nil, 1)
end)
