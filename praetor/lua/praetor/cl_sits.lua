-- Praetor: support room on the screen of the people inside it. A bar at the top
-- with the room, who is there (pictures) and the time; staff see how to end it.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

P.MySit = nil
P.ActiveSits = P.ActiveSits or {}

P.On("sit_state", function(d)
	if d.off then
		if P.MySit then UI.Sound("close") end
		P.MySit = nil
		return
	end
	local first = P.MySit == nil
	d.got = first and RealTime() or P.MySit.got
	d.t0 = RealTime() - (tonumber(d.age) or 0)
	P.MySit = d
	if first then UI.Sound("notify") end
end)

P.On("sit_list", function(d)
	P.ActiveSits = istable(d.list) and d.list or {}
	hook.Run("Praetor.SitsChanged")
end)

hook.Add("HUDPaint", "Praetor.SitBar", function()
	local s = P.MySit
	if not s then return end
	local me = LocalPlayer()
	local amStaff = false
	for _, m in ipairs(s.m or {}) do if m.sid == me:SteamID64() and m.st then amStaff = true end end
	local secs = math.max(0, math.floor(RealTime() - (s.t0 or RealTime())))
	local clock = string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
	local title = P.L("sit_bar", { S = s.room or "" })
	local sub = amStaff and P.L("sit_bar_staff") or P.L("sit_bar_player")
	local av = S(26)
	local n = #(s.m or {})
	surface.SetFont("Praetor.BodyB")
	local tw = surface.GetTextSize(title)
	surface.SetFont("Praetor.Tiny")
	local sw = surface.GetTextSize(sub)
	local w = math.max(tw, sw) + S(54) + n * (av + S(4)) + S(80)
	local h = S(50)
	local x, y = math.floor(ScrW() / 2 - w / 2), S(14)
	local a = math.min(1, (RealTime() - (s.got or 0)) * 4)
	UI.Round(x, y, w, h, S(10), Color(14, 15, 20, 232 * a), Color(C.sky.r, C.sky.g, C.sky.b, 160 * a))
	UI.Round(x + S(10), y + (h - S(30)) / 2, S(30), S(30), S(8), Color(C.sky.r, C.sky.g, C.sky.b, 50 * a))
	UI.Icon("headset", x + S(10) + (S(30) - 16) / 2, y + (h - 16) / 2, 16, Color(255, 255, 255, 255 * a))
	UI.Text(title, "Praetor.BodyB", x + S(50), y + S(17), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text(sub, "Praetor.Tiny", x + S(50), y + S(35), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	-- who is in the room
	local ax = x + w - S(70) - n * (av + S(4))
	for _, m in ipairs(s.m or {}) do
		local p = player.GetBySteamID64(m.sid)
		UI.DrawAvatar(m.sid, IsValid(p) and p or nil, ax, y + (h - av) / 2, av, 255 * a, m.st and C.sky or (IsValid(p) and UI.AvatarFrame(p) or nil), m.n)
		ax = ax + av + S(4)
	end
	UI.Text(clock, "Praetor.BodyB", x + w - S(14), y + h / 2, Color(C.sky.r, C.sky.g, C.sky.b, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end)
