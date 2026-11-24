-- Praetor: client side of the 1.3.0 staff tools that show outside the menu:
-- the alt account alert for the staff and the promotion celebration.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

-- ------------------------------------------------------------------ alt alert

P.On("alt_alert", function(d)
	if not istable(d) or not istable(d.alts) then return end
	local names = {}
	for i, a in ipairs(d.alts) do if i <= 3 then names[#names + 1] = a.name end end
	local list = table.concat(names, ", ") .. (#d.alts > 3 and " +" .. (#d.alts - 3) or "")
	local banned
	if d.banned then
		for _, a in ipairs(d.alts) do if a.sid == d.banned then banned = a end end
	end
	local title = banned and P.L("alt_alert_ban") or P.L("alt_alert")
	local text
	if banned then
		text = P.L("alt_alert_ban_d", { S = d.name, V = banned.name })
		if d.act == "kick" then text = text .. " " .. P.L("alt_did_kick")
		elseif d.act == "ban" then text = text .. " " .. P.L("alt_did_ban") end
	else
		text = P.L("alt_alert_d", { S = d.name, V = list })
	end
	P.Toast(title, text, banned and "alert" or "warn", 12)
	chat.AddText(banned and C.crimsonL or C.amber, "[" .. P.L("alt_tag") .. "] ", C.ivory, text)
	UI.Sound(banned and "warn" or "notify")
end)

-- ------------------------------------------------------------------ promotion

local party
local confetti = {}

P.On("promo_party", function(d)
	if not istable(d) then return end
	party = { t = RealTime(), display = tostring(d.display or ""), from = tostring(d.from or ""), hours = tonumber(d.hours) or 0,
		c = Color(d.c and d.c.r or 90, d.c and d.c.g or 170, d.c and d.c.b or 255), rank = d.rank }
	confetti = {}
	local cols = { party.c, C.amber, C.laurel, C.sky, C.crimsonL, color_white }
	for i = 1, 90 do
		confetti[i] = {
			x = math.Rand(0, ScrW()), y = math.Rand(-ScrH() * 0.6, -10),
			vx = math.Rand(-40, 40), vy = math.Rand(140, 320),
			r = math.Rand(0, 360), vr = math.Rand(-260, 260),
			w = math.Rand(5, 10), h = math.Rand(8, 16), col = cols[math.random(#cols)],
		}
	end
	UI.Sound("ok")
	timer.Simple(0.35, function() UI.Sound("gavel") end)
end)

hook.Add("HUDPaint", "Praetor.PromoParty", function()
	if not party then return end
	local age = RealTime() - party.t
	local life = 7
	if age > life then party = nil return end
	local a = math.min(1, age * 3, (life - age) * 1.5)
	local dt = RealFrameTime()

	-- confetti
	draw.NoTexture()
	for _, c in ipairs(confetti) do
		c.x = c.x + c.vx * dt
		c.y = c.y + c.vy * dt
		c.r = c.r + c.vr * dt
		c.vx = c.vx + math.sin(age * 3 + c.r * 0.01) * 6 * dt
		if c.y < ScrH() + 20 then
			surface.SetDrawColor(c.col.r, c.col.g, c.col.b, 230 * a)
			surface.DrawTexturedRectRotated(c.x, c.y, c.w, c.h * math.abs(math.cos(math.rad(c.r))), c.r)
		end
	end

	-- the card: pops a little bigger and settles
	local pop = age < 0.35 and (1 + 0.12 * math.sin(age / 0.35 * math.pi)) or 1
	local w, h = S(460) * pop, S(176) * pop
	local x, y = ScrW() / 2 - w / 2, ScrH() * 0.24
	local col = party.c
	UI.Round(x - S(3), y - S(3), w + S(6), h + S(6), S(16), Color(col.r, col.g, col.b, 60 * a))
	UI.Round(x, y, w, h, S(14), Color(14, 15, 20, 240 * a), Color(col.r, col.g, col.b, 200 * a))
	-- light sweeping across the top
	local sweep = (age * 0.6) % 1
	for i = 0, 6 do
		local f = math.Clamp(sweep * (w + S(120)) - S(60) + i * S(6), 0, w - S(4))
		surface.SetDrawColor(255, 255, 255, (18 - i * 2) * a)
		surface.DrawRect(x + f, y + S(2), S(4), S(3))
	end
	UI.Text(P.Upper(P.L("promo_title")), "Praetor.SmallB", ScrW() / 2, y + S(26), Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	UI.Text(P.L("promo_big"), "Praetor.H1", ScrW() / 2, y + S(56), Color(255, 255, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local style, icon = UI.RankStyle(party.rank)
	UI.Badge(style, icon, "Praetor.BodyB", ScrW() / 2, y + S(80), S(34), 255 * a, TEXT_ALIGN_CENTER)
	local sub = P.L("promo_sub", { S = party.from, V = P.FormatDuration(party.hours * 60) })
	UI.Text(UI.Fit(sub, "Praetor.Small", w - S(30)), "Praetor.Small", ScrW() / 2, y + S(138), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local nx = P.NextPromotion and P.NextPromotion(party.rank)
	if nx and P.Ranks[nx.rank] then
		local t = P.L("promo_next", { V = P.Ranks[nx.rank].display, V2 = P.FormatDuration(nx.hours * 60) })
		UI.Text(UI.Fit(t, "Praetor.Tiny", w - S(30)), "Praetor.Tiny", ScrW() / 2, y + S(158), Color(C.dim.r, C.dim.g, C.dim.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

concommand.Add("praetor_promo_test", function()
	local r = P.Ranks[LocalPlayer():GetUserGroup()] or P.Ranks.user
	if not r then return end
	local c = r.style and r.style.c1 or { r = 90, g = 170, b = 255 }
	P.Handlers.promo_party({ rank = r.name, display = r.display, from = "Player", hours = 10, c = c })
end)
