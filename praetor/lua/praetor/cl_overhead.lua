-- Praetor: the tag above every player's head. A small card with the Steam
-- avatar, name, rank badge, custom tag, title, DarkRP job, hours played and the
-- "on duty" pill.
-- Everything can be switched in Settings; each player can hide it with
-- praetor_overhead 0.
local P = Praetor
local UI = P.UI
local C = UI.C

local enabled = CreateClientConVar("praetor_overhead", "1", true, false, "Show Praetor tags above players")

local SCALE = 0.055
local visible = {}
local nextVis = {}
local seenAt, lastDrawn = {}, {}

-- Steam avatars over the head. An AvatarImage can't be painted inside 3D2D (its
-- clipping is worked out in screen space, so it was cut away and the card had
-- no picture). Each avatar is painted into a small render target in 2D and the
-- card draws that texture, with round corners made by a stencil.
local AV_RT = 128
local avs = {}

local function avatarKey(ply) return ply:SteamID64() or ("e" .. ply:EntIndex()) end

local function avatarFor(ply)
	local key = avatarKey(ply)
	local a = avs[key]
	if a and IsValid(a.panel) then
		a.want = true
		return a
	end
	local name = "praetor_ohav_" .. key
	local rt = GetRenderTargetEx(name, AV_RT, AV_RT, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 2, 0, IMAGE_FORMAT_RGBA8888)
	local mat = CreateMaterial(name .. "_mat", "UnlitGeneric", {
		["$basetexture"] = rt:GetName(), ["$translucent"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1",
	})
	local panel = vgui.Create("AvatarImage")
	panel:SetSize(AV_RT, AV_RT)
	panel:SetPlayer(ply, 184)
	panel:SetPaintedManually(true)
	a = { rt = rt, mat = mat, panel = panel, born = RealTime(), nextDraw = 0, want = true, ready = false }
	avs[key] = a
	return a
end

-- the picture is downloaded by Steam in the background: redraw often at first
hook.Add("HUDPaint", "Praetor.OverheadAvatars", function()
	local now = RealTime()
	for key, a in pairs(avs) do
		if not IsValid(a.panel) then
			avs[key] = nil
		elseif a.want and now >= a.nextDraw then
			a.nextDraw = now + ((now - a.born < 15) and 0.5 or 30)
			render.PushRenderTarget(a.rt)
			render.OverrideAlphaWriteEnable(true, true)
			render.ClearDepth()
			render.Clear(0, 0, 0, 0)
			cam.Start2D()
				a.panel:SetPos(0, 0)
				a.panel:PaintManual()
			cam.End2D()
			render.OverrideAlphaWriteEnable(false)
			render.PopRenderTarget()
			a.ready = true
		end
		a.want = false
	end
end)

local function roundPoly(x, y, s, r)
	local pts = {}
	local corners = { { x + s - r, y + r, -90 }, { x + s - r, y + s - r, 0 }, { x + r, y + s - r, 90 }, { x + r, y + r, 180 } }
	for _, c in ipairs(corners) do
		for i = 0, 6 do
			local ang = math.rad(c[3] + 90 * i / 6)
			pts[#pts + 1] = { x = c[1] + math.cos(ang) * r, y = c[2] + math.sin(ang) * r }
		end
	end
	return pts
end

local function drawAvatar(a, x, y, size, alpha)
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_REPLACE)
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 1)
	surface.DrawPoly(roundPoly(x, y, size, 18))
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	surface.SetMaterial(a.mat)
	surface.SetDrawColor(255, 255, 255, 255 * alpha)
	surface.DrawTexturedRect(x, y, size, size)
	render.SetStencilEnable(false)
end

hook.Add("EntityRemoved", "Praetor.Overhead", function(ent)
	if ent:IsPlayer() then
		local a = avs[avatarKey(ent)]
		if a and IsValid(a.panel) then a.panel:Remove() end
		avs[avatarKey(ent)] = nil
	end
	visible[ent], nextVis[ent] = nil, nil
	seenAt[ent], lastDrawn[ent] = nil, nil
end)

local function jobInfo(ply)
	if not P.IsDarkRP() then return nil end
	local name = ply.getDarkRPVar and ply:getDarkRPVar("job") or team.GetName(ply:Team())
	return name, team.GetColor(ply:Team())
end

local function canSee(ply, eye)
	local now = RealTime()
	if (nextVis[ply] or 0) > now then return visible[ply] end
	nextVis[ply] = now + 0.15
	local tr = util.TraceLine({ start = eye, endpos = ply:EyePos(), filter = { LocalPlayer(), ply }, mask = MASK_SOLID_BRUSHONLY })
	visible[ply] = not tr.Hit
	return visible[ply]
end

local function headPos(ply)
	local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
	if bone then
		local m = ply:GetBoneMatrix(bone)
		if m then return m:GetTranslation() + Vector(0, 0, 13) end
	end
	return ply:GetPos() + Vector(0, 0, ply:OBBMaxs().z + 6)
end

-- Bots and players whose Steam avatar can't load get their initial on a colour
-- picked from the name, instead of the blank default picture.
local function initialAvatar(ply, x, y, size, alpha)
	local name = ply:Nick()
	local hash = tonumber(util.CRC(name)) or 0
	local c = HSVToColor(hash % 360, 0.45, 0.62)
	UI.Round(x, y, size, size, 14, Color(c.r, c.g, c.b, 255 * alpha))
	local first = string.upper(P.Chars(name)[1] or "?")
	draw.SimpleText(first, "Praetor.OH.Name", x + size / 2, y + size / 2, Color(255, 255, 255, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function lighten(col, k)
	return Color(math.min(255, col.r + k), math.min(255, col.g + k), math.min(255, col.b + k))
end

-- One compact card: avatar on the left; name, badges and a small info line on
-- the right; title and the "on duty" pill above it; health as a thin bar inside.
local NAME_H, BADGE_H, INFO_H, AV, PAD, GAP = 66, 50, 44, 112, 22, 20
local SEP = "  " .. utf8.char(183) .. "  "
local NAME_MAX = 760

local function drawPlayer(ply, alpha)
	local s = P.Setting
	local A = 255 * alpha
	local title = s("overhead_title") and ply:GetPraetorTitle()
	local tag = s("overhead_tag") and ply:GetPraetorTag()

	-- badges: the rank (not for plain players, a "Player" pill on everyone is just
	-- noise) and the custom tag
	local parts = {}
	if s("overhead_rank") then
		if ply:GetUserGroup() ~= "user" or P.IsOwner(ply) then
			local style, icon = UI.PlayerRankStyle(ply)
			parts[#parts + 1] = { style, icon }
		end
	end
	if tag then parts[#parts + 1] = { tag, tag.icon } end

	-- small info line (hours only from 1h on: "0m" over a newcomer says nothing)
	local info = {}
	if s("overhead_job") then
		local job, jobCol = jobInfo(ply)
		if job and job ~= "" then info[#info + 1] = { job, jobCol, pill = true } end
	end
	if s("overhead_hours") then
		local secs = P.PlayTime(ply)
		if secs >= 3600 then info[#info + 1] = { P.FormatHours(secs), C.muted } end
	end

	-- measure
	local name = ply:Nick()
	local nameFont = UI.FontFor("" .. name, "Praetor.OH.Name")
	-- very long names are cut, so the card keeps a sane size and the rank badge
	-- under the name is always readable
	name = UI.Fit(name, nameFont, NAME_MAX)
	surface.SetFont(nameFont)
	local nameW = surface.GetTextSize(name)
	local badgeW, bsum = {}, 0
	for i, pt in ipairs(parts) do
		badgeW[i] = UI.BadgeWidth(pt[1], pt[2], "Praetor.OH.Tag", BADGE_H)
		bsum = bsum + badgeW[i] + (i > 1 and 12 or 0)
	end
	surface.SetFont("Praetor.OH.Small")
	local sepW = surface.GetTextSize(SEP)
	local infoW = 0
	for i, it in ipairs(info) do infoW = infoW + surface.GetTextSize(it[1]) + (it.pill and 28 or 0) + (i > 1 and sepW or 0) end

	local contentH = NAME_H + (#parts > 0 and (BADGE_H + 10) or 0) + (#info > 0 and INFO_H or 0)
	local showAv = s("overhead_avatar")
	local innerH = math.max(showAv and AV or 0, contentH)
	local showHP = s("overhead_health")
	local contentW = math.max(nameW, bsum, infoW)
	local w = PAD * 2 + (showAv and (AV + GAP) or 0) + contentW
	local h = PAD * 2 + innerH + (showHP and 14 or 0)
	local x0, y0 = -w / 2, -h

	-- above the card: the "on duty" pill, then the title
	local above = y0 - 10
	-- pills above the card: "on duty" and "AFK 5m", side by side
	local pills = {}
	if s("overhead_staff") and P.OnDuty(ply) then pills[#pills + 1] = { P.L("on_duty"), "shield", Color(C.bronze.r, C.bronze.g, C.bronze.b, 230 * alpha), Color(255, 255, 255, A) } end
	if P.IsAFK(ply) then pills[#pills + 1] = { P.AFKLabel(ply), "afk", Color(C.amber.r, C.amber.g, C.amber.b, 235 * alpha), Color(C.ink.r, C.ink.g, C.ink.b, A) } end
	if #pills > 0 then
		surface.SetFont("Praetor.OH.Small")
		local ph, gap = 48, 12
		local widths, total = {}, 0
		for i, pl in ipairs(pills) do
			widths[i] = surface.GetTextSize(pl[1]) + 74
			total = total + widths[i] + (i > 1 and gap or 0)
		end
		above = above - ph
		local px = -total / 2
		for i, pl in ipairs(pills) do
			local pw = widths[i]
			UI.Round(px + 6, above + 6, pw, ph, 24, Color(C.ink.r, C.ink.g, C.ink.b, 200 * alpha))
			UI.Round(px, above, pw, ph, 24, pl[3], Color(C.ink.r, C.ink.g, C.ink.b, A), 5)
			UI.Icon(pl[2], px + 16, above + (ph - 32) / 2, 32, Color(255, 255, 255, A))
			draw.SimpleText(pl[1], "Praetor.OH.Small", px + 56, above + ph / 2, pl[4], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			px = px + pw + gap
		end
		above = above - 10
	end
	if title then
		UI.DrawStyle(title, "Praetor.OH.Small", 0, above - 24, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, A)
	end

	-- card (green edge while the player talks)
	local talking = s("overhead_voice") and ply:IsSpeaking()
	local vol = talking and math.Clamp(ply:VoiceVolume() * 3, 0, 1) or 0
	local edge = talking and Color(C.laurel.r, C.laurel.g, C.laurel.b, (150 + 105 * vol) * alpha) or Color(C.lineL.r, C.lineL.g, C.lineL.b, 230 * alpha)
	UI.Round(x0 + 12, y0 + 12, w, h, 26, Color(C.ink.r, C.ink.g, C.ink.b, 170 * alpha))
	UI.Round(x0, y0, w, h, 26, Color(C.panel.r, C.panel.g, C.panel.b, 225 * alpha), edge, 7)
	if P.IsAFK(ply) then alpha = alpha * 0.6 A = 255 * alpha end
	if talking then
		-- microphone bubble on the top right corner, its ring follows the voice volume
		local r = 34
		local cx2, cy2 = x0 + w - 8, y0 + 4
		local ring = r + 4 + vol * 14
		UI.Round(cx2 - ring, cy2 - ring, ring * 2, ring * 2, ring, Color(C.laurel.r, C.laurel.g, C.laurel.b, (40 + 60 * vol) * alpha))
		UI.Round(cx2 - r, cy2 - r, r * 2, r * 2, r, Color(C.laurel.r, C.laurel.g, C.laurel.b, 245 * alpha), Color(C.ink.r, C.ink.g, C.ink.b, A), 6)
		UI.Icon("mic", cx2 - 24, cy2 - 24, 48, Color(255, 255, 255, A))
	end

	local cx = x0 + PAD
	if showAv then
		local ay = y0 + PAD + (innerH - AV) / 2
		if ply:IsBot() then
			initialAvatar(ply, cx, ay, AV, alpha)
		else
			local av = avatarFor(ply)
			if av.ready then drawAvatar(av, cx, ay, AV, alpha) else initialAvatar(ply, cx, ay, AV, alpha) end
		end
		cx = cx + AV + GAP
	end

	local cy = y0 + PAD + (innerH - contentH) / 2
	local nameCol = lighten(ply:GetRankColor(), 40)
	draw.SimpleText(name, nameFont, cx + 5, cy + NAME_H / 2 + 5, Color(C.ink.r, C.ink.g, C.ink.b, 220 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(name, nameFont, cx, cy + NAME_H / 2, Color(nameCol.r, nameCol.g, nameCol.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	cy = cy + NAME_H

	if #parts > 0 then
		cy = cy + 6
		local bx = cx
		for i, pt in ipairs(parts) do
			UI.Badge(pt[1], pt[2], "Praetor.OH.Tag", bx, cy, BADGE_H, A, TEXT_ALIGN_LEFT)
			bx = bx + badgeW[i] + 12
		end
		cy = cy + BADGE_H + 4
	end

	if #info > 0 then
		local ix = cx
		surface.SetFont("Praetor.OH.Small")
		for i, it in ipairs(info) do
			if i > 1 then
				draw.SimpleText(SEP, "Praetor.OH.Small", ix, cy + INFO_H / 2, Color(C.dim.r, C.dim.g, C.dim.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				ix = ix + sepW
			end
			local c = it[2] or C.text
			surface.SetFont("Praetor.OH.Small")
			local tw = surface.GetTextSize(it[1])
			if it.pill then
				UI.Round(ix, cy + 2, tw + 28, INFO_H - 4, (INFO_H - 4) / 2, Color(c.r, c.g, c.b, 235 * alpha), Color(C.ink.r, C.ink.g, C.ink.b, A), 4)
				local lum = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				local tc = lum > 150 and C.ink or color_white
				draw.SimpleText(it[1], "Praetor.OH.Small", ix + 14, cy + INFO_H / 2, Color(tc.r, tc.g, tc.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				ix = ix + tw + 28
			else
				draw.SimpleText(it[1], "Praetor.OH.Small", ix, cy + INFO_H / 2, Color(c.r, c.g, c.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				ix = ix + tw
			end
		end
	end

	if showHP then
		local frac = math.Clamp(ply:Health() / math.max(1, ply:GetMaxHealth()), 0, 1)
		local bw = w - PAD * 2
		local by = y0 + h - PAD - 6
		UI.Round(x0 + PAD, by - 4, bw, 14, 7, Color(C.bg.r, C.bg.g, C.bg.b, 230 * alpha), Color(C.ink.r, C.ink.g, C.ink.b, A), 3)
		if frac > 0 then
			local hc = frac > 0.5 and C.laurel or (frac > 0.25 and C.amber or C.crimson)
			UI.Round(x0 + PAD + 3, by - 1, math.max(8, (bw - 6) * frac), 8, 4, Color(hc.r, hc.g, hc.b, A))
		end
	end
end

-- gamemodes where names over heads would give away a secret (TTT disguiser,
-- Murder's bystander names, hidden Prop Hunt / Guess Who players)
local HIDDEN = { terrortown = true, murder = true, prop_hunt = true, prophunters = true, guesswho = true }
function P.HiddenIdentityMode() return HIDDEN[engine.ActiveGamemode()] == true end

hook.Add("PostDrawTranslucentRenderables", "Praetor.Overhead", function(depth, sky)
	if depth or sky then return end
	if not enabled:GetBool() or not P.Setting("overhead") or P.HiddenIdentityMode() then return end
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local eye = EyePos()
	local maxDist = math.max(100, P.Setting("overhead_dist") or 700)
	local maxSqr = maxDist * maxDist
	local ang = Angle(0, EyeAngles().y - 90, 90)
	local now = RealTime()
	for _, ply in ipairs(player.GetAll()) do
		if ply ~= me or me:ShouldDrawLocalPlayer() then
			if ply:Alive() and not ply:GetNoDraw() and not ply:GetNW2Bool("pr_cloak") and ply:GetColor().a > 30 then
				local pos = headPos(ply)
				local d = eye:DistToSqr(pos)
				if d < maxSqr and (ply == me or canSee(ply, eye)) then
					local frac = math.sqrt(d) / maxDist
					local alpha = frac > 0.75 and (1 - (frac - 0.75) / 0.25) or 1
					-- not drawn for a moment = it pops in again
					if now - (lastDrawn[ply] or 0) > 0.4 then seenAt[ply] = now end
					lastDrawn[ply] = now
					local k = math.min(1, (now - (seenAt[ply] or now)) / 0.32)
					local pop = 0.55 + 0.45 * UI.EaseBack(k)
					alpha = alpha * math.min(1, k * 3)
					-- a slow float, each player at its own pace
					pos = pos + Vector(0, 0, math.sin(now * 1.6 + ply:EntIndex()) * 0.7)
					cam.Start3D2D(pos, ang, SCALE * pop)
						drawPlayer(ply, alpha)
					cam.End3D2D()
				end
			end
		end
	end
end)

-- ------------------------------------------------------------------ aiming at a player
-- A small card under the crosshair with the name, health and armor. Numbers are
-- shortened (1.5K, 2M) and the bars stop at full, so a player with a million
-- health doesn't push anything out of the card.
local function shortNum(n)
	n = math.floor(tonumber(n) or 0)
	local a, sign = math.abs(n), n < 0 and "-" or ""
	if a < 10000 then return tostring(n) end
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if a >= u[1] then
			local v = a / u[1]
			local str = v >= 100 and string.format("%d", math.floor(v)) or string.format("%.1f", math.floor(v * 10) / 10):gsub("%.0$", "")
			return sign .. str .. u[2]
		end
	end
	return tostring(n)
end
P.ShortNum = shortNum

local target, targetAt, targetFade = nil, 0, 0
hook.Add("HUDPaint", "Praetor.TargetInfo", function()
	if not enabled:GetBool() or not P.Setting("overhead") or P.Setting("overhead_target") == false or P.HiddenIdentityMode() then return end
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local tr = me:GetEyeTrace()
	local ent = tr.Entity
	local maxDist = math.max(100, P.Setting("overhead_dist") or 700)
	if IsValid(ent) and ent:IsPlayer() and ent:Alive() and not ent:GetNoDraw() and not ent:GetNW2Bool("pr_cloak") and ent:GetColor().a > 30
		and tr.HitPos:DistToSqr(EyePos()) < maxDist * maxDist then
		target, targetAt = ent, RealTime()
	end
	-- stays a moment after you look away, then fades
	local want = IsValid(target) and target:Alive() and RealTime() - targetAt < 0.6
	targetFade = math.Approach(targetFade, want and 1 or 0, FrameTime() * 6)
	if targetFade <= 0 or not IsValid(target) then return end
	local a = targetFade

	local S = P.S
	local w, pad = S(250), S(10)
	local hp, maxHp = target:Health(), math.max(1, target:GetMaxHealth())
	local ar = target:Armor()
	local maxAr = math.max(1, target.GetMaxArmor and target:GetMaxArmor() or 100)
	local rows = { { "heart", hp, maxHp, C.crimson } }
	if ar > 0 then rows[2] = { "vest", ar, maxAr, C.sky } end
	local rowH = S(20)
	local h = pad * 2 + S(22) + #rows * (rowH + S(4))
	local x = math.floor(ScrW() / 2 - w / 2)
	local y = math.floor(ScrH() / 2 + S(34) + (1 - a) * S(8))

	UI.Comic(x, y, w, h, S(12), Color(C.panel.r, C.panel.g, C.panel.b, 225 * a), Color(C.lineL.r, C.lineL.g, C.lineL.b, 230 * a), S(3), 180 * a)
	local nameCol = lighten(target:GetRankColor(), 40)
	UI.Name(target:Nick(), "Praetor.SmallB", x + pad, y + pad + S(9), Color(nameCol.r, nameCol.g, nameCol.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - pad * 2)
	local ry = y + pad + S(22)
	surface.SetFont("Praetor.SmallB")
	-- the number column is as wide as "999.9K / 999.9K" would be, so it never runs into the bar
	local numW = surface.GetTextSize("88888 / 88888")
	for _, r in ipairs(rows) do
		UI.Icon(r[1], x + pad, ry + (rowH - 16) / 2, 16, Color(255, 255, 255, 255 * a))
		local bx = x + pad + S(22)
		local bw = w - pad * 2 - S(22) - numW - S(8)
		local frac = math.Clamp(r[2] / r[3], 0, 1)
		UI.Round(bx, ry + S(5), bw, rowH - S(10), (rowH - S(10)) / 2, Color(C.bg.r, C.bg.g, C.bg.b, 230 * a), Color(C.ink.r, C.ink.g, C.ink.b, 255 * a), 2)
		if frac > 0 then
			UI.Round(bx + 2, ry + S(5) + 2, math.max(4, (bw - 4) * frac), rowH - S(10) - 4, (rowH - S(10) - 4) / 2, Color(r[4].r, r[4].g, r[4].b, 255 * a))
		end
		-- more than the maximum (admin gave 1 million): a small "+" at the end of the bar
		if r[2] > r[3] then UI.Text("+", "Praetor.SmallB", bx + bw - S(2), ry + rowH / 2, Color(255, 255, 255, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
		local label = shortNum(r[2]) .. " / " .. shortNum(r[3])
		UI.Text(UI.Fit(label, "Praetor.SmallB", numW), "Praetor.SmallB", x + w - pad, ry + rowH / 2, Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		ry = ry + rowH + S(4)
	end
end)

-- hide the default name hints (sandbox target id and DarkRP's info box)
hook.Add("HUDDrawTargetID", "Praetor.Overhead", function()
	if enabled:GetBool() and P.Setting("overhead") and not P.HiddenIdentityMode() then return false end
end)

hook.Add("HUDShouldDraw", "Praetor.Overhead", function(name)
	if name == "DarkRP_EntityDisplay" and enabled:GetBool() and P.Setting("overhead") then return false end
end)
