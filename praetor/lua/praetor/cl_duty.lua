-- Praetor: staff mode card. While on duty a small card on the left of the screen
-- shows the time of this shift (live), and whether you are invisible and hidden
-- from E2 / Starfall chips. The staff baton lists its modes right under it.
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

-- where the baton list starts (under the card)
function P.DutyCardBottom()
	local me = LocalPlayer()
	if shown(me) then return top() + S(H) end
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

	local w, h = S(W), S(H)
	local x = math.floor(S(22) - (1 - a) * S(30))
	local y = top()
	UI.Comic(x, y, w, h, S(12), A(C.panel, 0.92), A(C.bronze), S(4), 190 * a)

	-- shield on a disc of the accent colour
	local d = S(32)
	UI.Round(x + S(10), y + (h - d) / 2, d, d, d / 2, A(C.bronze), A(C.ink), 2)
	UI.Icon("shield", x + S(10) + (d - 20) / 2, y + (h - 20) / 2, 20, Color(255, 255, 255, 255 * a))

	local tx = x + S(10) + d + S(10)
	local since = me:GetNW2Float("pr_dutysince", CurTime())
	local time = clock(CurTime() - since)
	surface.SetFont("Praetor.Num")
	local timeW = surface.GetTextSize(time)
	UI.Text(time, "Praetor.Num", x + w - S(12), y + S(18), A(C.ivory), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	UI.Text(UI.Fit(P.L("on_duty"), "Praetor.BodyB", x + w - S(12) - timeW - S(8) - tx), "Praetor.BodyB", tx, y + S(18), A(C.bronzeL), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- what is on: invisible / hidden from chips
	local tags = {}
	if me:GetNW2Bool("pr_cloak", false) then tags[#tags + 1] = P.L("duty_cloaked") end
	if P.Setting("esp_block") ~= false then tags[#tags + 1] = P.L("duty_esp") end
	local sub = #tags > 0 and table.concat(tags, "  ·  ") or P.L("duty_shift")
	UI.Text(UI.Fit(sub, "Praetor.Tiny", x + w - S(12) - tx), "Praetor.Tiny", tx, y + S(37), A(C.muted), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
