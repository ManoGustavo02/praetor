-- Praetor: what staff see that players don't.
--  * Staff ESP (on duty, permission esp, Settings > staff_esp): every player through
--    walls with a box, health and armor bars and a card with the avatar, name, rank,
--    distance, weapon and state (invisible, on duty, AFK, jailed...). Chips (E2 /
--    Starfall) and sprays show too. Turned on / off with the baton or praetor_esp.
--  * Invisible players are drawn as see-through ghosts for staff (see_cloaked).
--  * Looking at a spray says whose it is (spray_info).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local espVar = CreateClientConVar("praetor_esp", "1", true, false, "Praetor staff ESP while on duty (0 = off)", 0, 1)
P.EspVar = espVar

local function lighten(col, k)
	return Color(math.min(255, col.r + k), math.min(255, col.g + k), math.min(255, col.b + k), col.a)
end

-- ------------------------------------------------------------------ state
function P.EspActive()
	local me = LocalPlayer()
	return IsValid(me) and espVar:GetBool() and P.Setting("staff_esp") ~= false and me:GetNW2Bool("pr_duty", false)
		and P.MyHas("esp") and not me:GetNW2Bool("pr_specon", false)
end

-- who wants the live chip list (the ESP and the Chips tab); the server sends it
-- only while someone asks
local chipSubs = {}
function P.ChipSub(reason, on)
	local before = next(chipSubs) ~= nil
	chipSubs[reason] = on or nil
	local after = next(chipSubs) ~= nil
	if before ~= after then P.Request("chips_sub", { on = after }) end
end

local lastSent
timer.Create("Praetor.EspSync", 0.5, 0, function()
	if not IsValid(LocalPlayer()) then return end
	local on = P.EspActive()
	if on ~= lastSent then
		lastSent = on
		P.Request("esp_state", { on = on })
		P.ChipSub("esp", on and P.MyHas("chips"))
	end
end)

-- ------------------------------------------------------------------ data from the server
P.Sprays = P.Sprays or {}
P.On("sprays", function(d)
	local out = {}
	for _, s in ipairs(istable(d.list) and d.list or {}) do
		if istable(s.p) and istable(s.nr) then
			out[#out + 1] = { sid = s.s, name = s.n, t = s.t, pos = Vector(s.p[1], s.p[2], s.p[3]), nr = Vector(s.nr[1], s.nr[2], s.nr[3]) }
		end
	end
	P.Sprays = out
end)

P.ChipLive = P.ChipLive or {}
P.On("chips", function(d)
	P.ChipLive = istable(d.list) and d.list or {}
	P.ChipLiveAt = RealTime()
	hook.Run("Praetor.ChipsUpdated")
end)

-- ------------------------------------------------------------------ ghosts of invisible players
local function seesGhosts()
	return P.Setting("ghost_cloaked") ~= false and P.MyHas("see_cloaked")
end

hook.Add("PostDrawTranslucentRenderables", "Praetor.Ghosts", function(depth, sky)
	if depth or sky or not seesGhosts() then return end
	local me = LocalPlayer()
	for _, p in player.Iterator() do
		if p ~= me and p:Alive() and p:GetNW2Bool("pr_cloak", false) and not p:GetNW2Bool("pr_specon", false) then
			local oc, om = p:GetColor(), p:GetRenderMode()
			p:SetRenderMode(RENDERMODE_TRANSALPHA)
			p:SetColor(Color(255, 255, 255, 70))
			render.SetColorModulation(0.75, 0.62, 1)
			p:SetupBones()
			p:DrawModel()
			render.SetColorModulation(1, 1, 1)
			p:SetColor(oc)
			p:SetRenderMode(om)
		end
	end
end)

-- ------------------------------------------------------------------ helpers
local INK = Color(8, 6, 16, 220)

-- corner brackets: lighter than a full box, readable over anything
local function corners(x, y, w, h, col)
	local l = math.max(S(5), math.floor(math.min(w, h) * 0.25))
	local t = math.max(1, math.floor(S(2)))
	for _, pass in ipairs({ { INK, t + 2, -1 }, { col, t, 0 } }) do
		local c, th, o = pass[1], pass[2], pass[3]
		surface.SetDrawColor(c)
		surface.DrawRect(x + o, y + o, l, th) surface.DrawRect(x + o, y + o, th, l)
		surface.DrawRect(x + w - l - o, y + o, l, th) surface.DrawRect(x + w - th - o, y + o, th, l)
		surface.DrawRect(x + o, y + h - th - o, l, th) surface.DrawRect(x + o, y + h - l - o, th, l)
		surface.DrawRect(x + w - l - o, y + h - th - o, l, th) surface.DrawRect(x + w - th - o, y + h - l - o, th, l)
	end
end

local function vbar(x, y, h, frac, col)
	surface.SetDrawColor(INK)
	surface.DrawRect(x - 1, y - 1, S(3) + 2, h + 2)
	local fh = math.floor(h * math.Clamp(frac, 0, 1))
	surface.SetDrawColor(col)
	surface.DrawRect(x, y + h - fh, S(3), fh)
end

local function meters(units) return math.floor(units * 0.01905 + 0.5) .. "m" end

local function weaponName(p)
	local w = p:GetActiveWeapon()
	if not IsValid(w) then return nil end
	local n = w.GetPrintName and w:GetPrintName() or w:GetClass()
	return language.GetPhrase(n or "")
end

local function stateTags(p)
	local t = {}
	if p:GetNW2Bool("pr_cloak", false) then t[#t + 1] = { P.L("esp_cloaked"), C.bronzeL } end
	if p:GetNW2Bool("pr_duty", false) then t[#t + 1] = { P.L("on_duty"), C.bronzeL } end
	if p:GetNW2Bool("pr_jailed", false) then t[#t + 1] = { P.L("esp_jailed"), C.crimsonL } end
	if p:GetNW2Bool("pr_frozen", false) then t[#t + 1] = { P.L("esp_frozen"), C.sky } end
	if p:GetNW2Bool("pr_afk", false) then t[#t + 1] = { "AFK", C.amber } end
	if p:GetNW2Bool("pr_god", false) then t[#t + 1] = { "GOD", C.amber } end
	if p:InVehicle() then t[#t + 1] = { P.L("esp_vehicle"), C.muted } end
	return t
end

-- ------------------------------------------------------------------ the ESP
local function drawPlayer(p, me, eye)
	local pos = p:GetPos()
	local dist = eye:Distance(pos)
	local maxs = p:OBBMaxs()
	local top = (pos + Vector(0, 0, maxs.z + 4)):ToScreen()
	local bot = pos:ToScreen()
	if not top.visible or not bot.visible then return end
	local bh = math.max(S(10), bot.y - top.y)
	local bw = math.max(S(6), bh * 0.5)
	local x, y = math.floor(top.x - bw / 2), math.floor(top.y)
	local far = dist > 3000
	local a = far and 170 or 255
	local rc = lighten(p:GetRankColor(), 40)
	local col = Color(rc.r, rc.g, rc.b, a)
	if p:GetNW2Bool("pr_cloak", false) then col = Color(C.bronzeL.r, C.bronzeL.g, C.bronzeL.b, a) end

	corners(x, y, bw, bh, col)
	-- health and armor bars on the left of the box
	local hp, maxHp = p:Health(), math.max(1, p:GetMaxHealth())
	local hf = hp / maxHp
	vbar(x - S(6), y, bh, hf, Color(255 * (1 - math.min(hf, 1)) + 40, 60 + 180 * math.min(hf, 1), 80, a))
	local ar = p:Armor()
	if ar > 0 then vbar(x - S(11), y, bh, ar / math.max(1, p.GetMaxArmor and p:GetMaxArmor() or 100), Color(C.sky.r, C.sky.g, C.sky.b, a)) end

	-- close and in sight: the tag over the head already shows the name
	local overhead = math.max(100, P.Setting("overhead_dist") or 700)
	if dist < overhead and P.Setting("overhead") ~= false then
		local tr = util.TraceLine({ start = eye, endpos = p:EyePos(), filter = { me, p }, mask = MASK_VISIBLE })
		if not tr.Hit then return end
	end

	-- the card on the right of the box
	local cx = x + bw + S(6)
	local name = p:Nick()
	if far then
		local txt = name .. "  ·  " .. meters(dist)
		surface.SetFont("Praetor.Tiny")
		local tw = surface.GetTextSize(txt)
		UI.Round(cx, y, tw + S(12), S(18), S(5), Color(C.panel.r, C.panel.g, C.panel.b, 190))
		UI.Text(txt, "Praetor.Tiny", cx + S(6), y + S(9), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return
	end
	local av = S(26)
	local style = UI.RankStyle(p:GetUserGroup())
	local rank = style and style.text or p:GetUserGroup()
	local info = rank .. "  ·  " .. meters(dist)
	local wep = weaponName(p)
	local tags = stateTags(p)
	surface.SetFont("Praetor.SmallB")
	local nw = math.min(S(170), surface.GetTextSize(name))
	surface.SetFont("Praetor.Tiny")
	local iw = math.min(S(170), surface.GetTextSize(info))
	local ww = wep and math.min(S(170), surface.GetTextSize(wep)) or 0
	local tagW = 0
	for _, t in ipairs(tags) do tagW = tagW + surface.GetTextSize(t[1]) + S(14) end
	local textW = math.max(nw, iw, ww, math.min(tagW, S(200)))
	local w = av + S(8) + textW + S(12)
	local lines = 2 + (wep and 1 or 0)
	local h = math.max(av + S(8), S(6) + lines * S(14) + S(4)) + (#tags > 0 and S(18) or 0)
	UI.Round(cx, y, w, h, S(6), Color(C.panel.r, C.panel.g, C.panel.b, 205), Color(col.r, col.g, col.b, 120), 1)
	UI.DrawAvatar(p:SteamID64(), p, cx + S(4), y + S(4), av, 255, nil, name)
	local tx = cx + av + S(10)
	UI.Name(name, "Praetor.SmallB", tx, y + S(11), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, textW)
	UI.Text(UI.Fit(info, "Praetor.Tiny", textW), "Praetor.Tiny", tx, y + S(25), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if wep then UI.Text(UI.Fit(wep, "Praetor.Tiny", textW), "Praetor.Tiny", tx, y + S(38), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	if #tags > 0 then
		local tgx, tgy = cx + S(4), y + h - S(18)
		for _, t in ipairs(tags) do
			local tw = surface.GetTextSize(t[1]) + S(10)
			if tgx + tw > cx + w - S(2) then break end
			UI.Round(tgx, tgy, tw, S(14), S(7), Color(t[2].r, t[2].g, t[2].b, 45), t[2], 1)
			UI.Text(t[1], "Praetor.Tiny", tgx + tw / 2, tgy + S(7), t[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			tgx = tgx + tw + S(4)
		end
	end
end

local function drawChips(eye)
	if not P.MyHas("chips") then return end
	for _, c in ipairs(P.ChipLive or {}) do
		local e = Entity(c.e or -1)
		if IsValid(e) and eye:DistToSqr(e:GetPos()) < 3000 * 3000 then
			local sp = (e:GetPos() + Vector(0, 0, 8)):ToScreen()
			if sp.visible then
				local bad = istable(c.f) and next(c.f) ~= nil
				local col = bad and C.crimsonL or (c.err and C.dim or C.sky)
				local l1 = (c.t == "sf" and "SF" or "E2") .. "  ·  " .. tostring(c.n or "?")
				local l2 = tostring(c.on or "?") .. "  ·  CPU " .. math.floor(c.pct or 0) .. "%"
				surface.SetFont("Praetor.Tiny")
				local w = math.min(S(220), math.max(surface.GetTextSize(l1), surface.GetTextSize(l2))) + S(12)
				local x, y = math.floor(sp.x - w / 2), math.floor(sp.y - S(30))
				UI.Round(x, y, w, S(30), S(5), Color(C.panel.r, C.panel.g, C.panel.b, 200), col, 1)
				UI.Text(UI.Fit(l1, "Praetor.Tiny", w - S(12)), "Praetor.Tiny", x + S(6), y + S(8), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				UI.Text(UI.Fit(l2, "Praetor.Tiny", w - S(12)), "Praetor.Tiny", x + S(6), y + S(21), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
	end
end

local function drawSprayMarks(eye)
	if not P.MyHas("spray_info") then return end
	for _, s in ipairs(P.Sprays or {}) do
		if eye:DistToSqr(s.pos) < 1500 * 1500 then
			local sp = s.pos:ToScreen()
			if sp.visible then
				UI.Icon("pen", sp.x - 8, sp.y - 8, 16, Color(255, 255, 255, 200))
				UI.Text(tostring(s.name or "?"), "Praetor.Tiny", sp.x, sp.y + S(12), C.amber, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
end

hook.Add("HUDPaint", "Praetor.StaffESP", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local eye = EyePos()
	if P.EspActive() then
		for _, p in player.Iterator() do
			if p ~= me and p:Alive() then drawPlayer(p, me, eye) end
		end
		drawChips(eye)
		drawSprayMarks(eye)
		return
	end
	-- without the ESP: invisible players near you get a small label (staff only)
	if not seesGhosts() then return end
	for _, p in player.Iterator() do
		if p ~= me and p:Alive() and p:GetNW2Bool("pr_cloak", false) and eye:DistToSqr(p:GetPos()) < 2000 * 2000 then
			local sp = (p:GetPos() + Vector(0, 0, p:OBBMaxs().z + 10)):ToScreen()
			if sp.visible then
				local txt = p:Nick() .. "  ·  " .. P.L("esp_cloaked")
				surface.SetFont("Praetor.Tiny")
				local tw = surface.GetTextSize(txt) + S(12)
				UI.Round(sp.x - tw / 2, sp.y - S(9), tw, S(18), S(9), Color(C.panel.r, C.panel.g, C.panel.b, 180), C.bronze, 1)
				UI.Text(txt, "Praetor.Tiny", sp.x, sp.y, C.bronzeL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
end)

-- ------------------------------------------------------------------ whose spray is this
local sprayShown, sprayFade = nil, 0
hook.Add("HUDPaint", "Praetor.SprayInfo", function()
	local me = LocalPlayer()
	if not IsValid(me) or not P.MyHas("spray_info") or #(P.Sprays or {}) == 0 then sprayFade = 0 return end
	local tr = me:GetEyeTrace()
	local found
	if tr.HitWorld or (IsValid(tr.Entity) and not tr.Entity:IsPlayer()) then
		for _, s in ipairs(P.Sprays) do
			if s.pos:DistToSqr(tr.HitPos) < 40 * 40 and s.nr:Dot(tr.HitNormal) > 0.6 then found = s break end
		end
	end
	if found then sprayShown = found end
	sprayFade = math.Approach(sprayFade, found and 1 or 0, FrameTime() * 6)
	if sprayFade <= 0 or not sprayShown then return end
	local a = sprayFade
	local s = sprayShown
	local w, h = S(250), S(46)
	-- above the crosshair: under it are the health card (players) and the prop owner card
	local x, y = math.floor(ScrW() / 2 - w / 2), math.floor(ScrH() / 2 - S(34) - h)
	UI.Comic(x, y, w, h, S(12), Color(C.panel.r, C.panel.g, C.panel.b, 225 * a), Color(C.amber.r, C.amber.g, C.amber.b, 230 * a), S(3), 180 * a)
	UI.Icon("pen", x + S(10), y + (h - 20) / 2, 20, Color(255, 255, 255, 255 * a))
	UI.Text(UI.Fit(P.L("spray_of", { S = s.name or "?" }), "Praetor.SmallB", w - S(46)), "Praetor.SmallB", x + S(38), y + S(15), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local ago = math.max(0, os.time() - (s.t or os.time()))
	local sub = P.L("spray_ago", { V = P.FormatHours(ago) }) .. "  ·  " .. util.SteamIDFrom64(tostring(s.sid or "0"))
	UI.Text(UI.Fit(sub, "Praetor.Tiny", w - S(46)), "Praetor.Tiny", x + S(38), y + S(32), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
