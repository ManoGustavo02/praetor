-- Praetor: staff mode on screen.
--  * While on duty a small card on the left shows the time of this shift (live),
--    whether you are invisible / hidden from chips, and the weekly goal of your
--    rank when the server uses goals. The staff baton lists its modes under it.
--  * When the shift ends, the same spot shows a summary of the shift for a while.
--  * Taking a report off duty asks "Start staff mode?"; yes starts it and takes it.
-- Left side, between the DarkRP agenda (top left) and the HUD card (bottom left);
-- the right side belongs to the toasts.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local W, H = 250, 52
local fade = 0

local function top() return math.max(S(200), math.floor(ScrH() * 0.30)) end

local function shown(me)
	return IsValid(me) and me:GetNW2Bool("pr_duty", false) and not me:GetNW2Bool("pr_specon", false)
		and not me:GetNW2Bool("pr_jailed", false)
end

-- weekly goal (hours) of my rank, nil without one
local function myGoal(me)
	if P.Setting("duty_goal") ~= true then return nil end
	local r = P.Ranks and P.Ranks[me:GetUserGroup()]
	local g = r and tonumber(r.goal) or 0
	return g > 0 and g or nil
end

local function cardH(me) return S(H) + (myGoal(me) and S(12) or 0) end

-- where the baton list starts (under the card)
function P.DutyCardBottom()
	local me = LocalPlayer()
	if shown(me) then return top() + cardH(me) end
	return top() - S(10)
end

local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
end

hook.Add("HUDPaint", "Praetor.DutyCard", function()
	local me = LocalPlayer()
	fade = math.Approach(fade, shown(me) and 1 or 0, FrameTime() * 5)
	if fade <= 0 or not IsValid(me) then return end
	local a = fade
	local function A(c, k) return Color(c.r, c.g, c.b, (c.a or 255) * a * (k or 1)) end

	local goal = myGoal(me)
	local w, h = S(W), cardH(me)
	local x = math.floor(S(22) - (1 - a) * S(30))
	local y = top()
	UI.Comic(x, y, w, h, S(12), A(C.panel, 0.92), A(C.bronze), S(4), 190 * a)

	-- shield on a disc of the accent colour
	local d = S(32)
	local by = y + (S(H) - d) / 2
	UI.Round(x + S(10), by, d, d, d / 2, A(C.bronze), A(C.ink), 2)
	UI.Icon("shield", x + S(10) + (d - 20) / 2, by + (d - 20) / 2, 20, Color(255, 255, 255, 255 * a))

	local tx = x + S(10) + d + S(10)
	local since = me:GetNW2Float("pr_dutysince", CurTime())
	local secs = CurTime() - since
	local time = clock(secs)
	surface.SetFont("Praetor.Num")
	local timeW = surface.GetTextSize(time)
	UI.Text(time, "Praetor.Num", x + w - S(12), y + S(18), A(C.ivory), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	UI.Text(UI.Fit(P.L("on_duty"), "Praetor.BodyB", x + w - S(12) - timeW - S(8) - tx), "Praetor.BodyB", tx, y + S(18), A(C.bronzeL), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- what is on: invisible / ESP / hidden from chips
	local tags = {}
	if me:GetNW2Bool("pr_cloak", false) then tags[#tags + 1] = P.L("duty_cloaked") end
	if me:GetNW2Bool("pr_esp", false) then tags[#tags + 1] = "ESP" end
	if P.Setting("esp_block") ~= false then tags[#tags + 1] = P.L("duty_esp") end
	local sub = #tags > 0 and table.concat(tags, "  ·  ") or P.L("duty_shift")
	UI.Text(UI.Fit(sub, "Praetor.Tiny", x + w - S(12) - tx), "Praetor.Tiny", tx, y + S(37), A(C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- weekly goal: a thin bar along the bottom of the card
	if goal then
		local week = me:GetNW2Int("pr_weekbase", 0) + secs
		local need = goal * 3600
		local frac = math.Clamp(week / need, 0, 1)
		local gy = y + S(H) + S(1)
		local label = P.L("duty_goal_short", { V = P.FormatHours(week), V2 = P.FormatHours(need) })
		surface.SetFont("Praetor.Tiny")
		local lw = math.min(surface.GetTextSize(label), w * 0.6)
		local bw = w - S(24) - lw - S(8)
		UI.Round(x + S(12), gy + S(2), bw, S(5), S(2), A(C.bg), A(C.line), 1)
		if frac > 0 then UI.Round(x + S(12), gy + S(2), math.max(S(4), bw * frac), S(5), S(2), A(frac >= 1 and C.laurel or C.amber)) end
		UI.Text(UI.Fit(label, "Praetor.Tiny", lw), "Praetor.Tiny", x + w - S(12), gy + S(4), A(frac >= 1 and C.laurel or C.muted), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end)

-- ------------------------------------------------------------------ summary of the shift
local sum, sumAt = nil, 0
local SUM_LIFE = 14

P.On("duty_summary", function(d)
	sum, sumAt = d, RealTime()
	UI.Sound("seal")
end)

hook.Add("HUDPaint", "Praetor.DutySummary", function()
	if not sum then return end
	local age = RealTime() - sumAt
	if age > SUM_LIFE then sum = nil return end
	local me = LocalPlayer()
	if not IsValid(me) or shown(me) then sum = nil return end -- back on duty: the live card takes the spot
	local a = math.min(1, age * 4, (SUM_LIFE - age) * 2)
	local function A(c, k) return Color(c.r, c.g, c.b, (c.a or 255) * a * (k or 1)) end

	local w, pad = S(280), S(12)
	local stats = {
		{ "bolt", P.L("ds_cmds"), sum.cmds },
		{ "hammer", P.L("ds_pun"), sum.pun },
		{ "flag", P.L("ds_rep"), sum.rep },
		{ "headset", P.L("ds_sits"), sum.sits },
		{ "wrench", P.L("ds_baton"), sum.baton },
	}
	local rows = math.ceil(#stats / 2)
	local goalH = sum.goal and S(34) or 0
	local h = pad + S(22) + S(36) + rows * S(30) + goalH + pad
	local x = math.floor(S(22) - (1 - a) * S(30))
	local y = top()
	UI.Comic(x, y, w, h, S(12), A(C.panel, 0.94), A(sum.why == "afk" and C.amber or C.edge), S(4), 190 * a)

	UI.Text(UI.Fit(P.L(sum.why == "afk" and "ds_title_afk" or "ds_title"):upper(), "Praetor.Tiny", w - pad * 2), "Praetor.Tiny", x + pad, y + pad + S(6), A(sum.why == "afk" and C.amber or C.dim), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local ty = y + pad + S(22)
	UI.Icon("clock", x + pad, ty + (S(30) - 24) / 2, 24, Color(255, 255, 255, 255 * a))
	UI.Text(P.FormatHours(sum.secs), "Praetor.H2", x + pad + S(32), ty + S(15), A(C.ivory), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(P.L("ds_time"), "Praetor.Tiny", x + w - pad, ty + S(15), A(C.muted), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	local gy = ty + S(36)
	local colW = math.floor((w - pad * 2 - S(8)) / 2)
	for i, st in ipairs(stats) do
		local cx = x + pad + ((i - 1) % 2) * (colW + S(8))
		local cy = gy + math.floor((i - 1) / 2) * S(30)
		UI.Round(cx, cy, colW, S(26), S(5), A(C.panel2))
		UI.Icon(st[1], cx + S(6), cy + (S(26) - 16) / 2, 16, Color(255, 255, 255, 255 * a))
		local v = tostring(st[3] or 0)
		surface.SetFont("Praetor.SmallB")
		local vw = surface.GetTextSize(v)
		UI.Text(UI.Fit(st[2], "Praetor.Tiny", colW - S(32) - vw - S(8)), "Praetor.Tiny", cx + S(28), cy + S(13), A(C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(v, "Praetor.SmallB", cx + colW - S(8), cy + S(13), A(C.ivory), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	if sum.goal then
		local need = sum.goal * 3600
		local frac = math.Clamp((sum.week or 0) / need, 0, 1)
		local ok = frac >= 1
		local ry = gy + rows * S(30) + S(4)
		UI.Text(P.L("st_goal"), "Praetor.SmallB", x + pad, ry + S(7), A(C.ivory), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.FormatHours(sum.week or 0) .. " / " .. P.FormatHours(need), "Praetor.Tiny", x + w - pad, ry + S(7), A(ok and C.laurel or C.amber), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		UI.Round(x + pad, ry + S(18), w - pad * 2, S(8), S(4), A(C.bg), A(C.line), 1)
		if frac > 0 then UI.Round(x + pad + 1, ry + S(19), math.max(S(6), (w - pad * 2 - 2) * frac), S(6), S(3), A(ok and C.laurel or C.amber)) end
	end
	-- time left: a thin bar that empties along the bottom
	UI.Round(x + S(12), y + h - S(6), (w - S(24)) * math.Clamp(1 - age / SUM_LIFE, 0, 1), S(2), S(1), A(C.bronze, 0.8))
end)

-- ------------------------------------------------------------------ "start staff mode?"
P.On("duty_ask", function(d)
	UI.Sound("notify")
	UI.Confirm(P.L("duty_ask_t"), P.L(d.op and "duty_ask_op" or "duty_ask"), function()
		P.Request("duty_join", { op = d.op, d = d.d })
	end)
end)
