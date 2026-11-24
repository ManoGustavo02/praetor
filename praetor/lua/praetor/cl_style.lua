-- Praetor: painting styled tags (gradient + animated effects) on screen and in 3D2D.
local P = Praetor
local UI = P.UI

local widthCache = {}

local function charW(font, ch)
	local fc = widthCache[font]
	if not fc then fc = {} widthCache[font] = fc end
	local w = fc[ch]
	if not w then
		surface.SetFont(font)
		w = surface.GetTextSize(ch)
		fc[ch] = w
	end
	return w
end

hook.Add("Praetor.FontsBuilt", "Praetor.StyleCache", function() widthCache = {} end)

local charsCache = setmetatable({}, { __mode = "k" })
local function chars(style)
	local c = charsCache[style]
	if c and c.text == style.text then return c.list end
	local list = P.Chars(style.text or "")
	charsCache[style] = { text = style.text, list = list }
	return list
end

function UI.StyleWidth(style, font)
	local w = 0
	for _, ch in ipairs(chars(style)) do w = w + charW(font, ch) end
	return w
end

-- Draws the styled text. ax: TEXT_ALIGN_*; returns the width.
function UI.DrawStyle(style, font, x, y, ax, ay, alpha, shadow)
	if not style or not style.text then return 0 end
	local list = chars(style)
	local n = #list
	local w = UI.StyleWidth(style, font)
	surface.SetFont(font)
	local _, h = surface.GetTextSize("Ag")
	if ax == TEXT_ALIGN_CENTER then x = x - w / 2 elseif ax == TEXT_ALIGN_RIGHT then x = x - w end
	if ay == TEXT_ALIGN_CENTER then y = y - h / 2 elseif ay == TEXT_ALIGN_BOTTOM then y = y - h end
	local t = RealTime()
	alpha = alpha or 255
	local amp = math.max(1, h * 0.08)
	local cx = x
	for i, ch in ipairs(list) do
		local col = P.StyleColorAt(style, i, n, t)
		local oy = P.StyleOffsetAt(style, i, t, amp)
		if shadow ~= false then
			surface.SetTextColor(0, 0, 0, alpha * 0.55)
			surface.SetTextPos(cx + 1, y + oy + math.max(1, h * 0.06))
			surface.DrawText(ch)
		end
		surface.SetTextColor(col.r, col.g, col.b, alpha)
		surface.SetTextPos(cx, y + oy)
		surface.DrawText(ch)
		cx = cx + charW(font, ch)
	end
	return w, h
end

-- a created icon that was deleted counts as no icon (no empty gap in the pill)
local function realIcon(icon)
	if isstring(icon) and icon:sub(1, 2) == "c_" and not (P.CustomIcons and P.CustomIcons[icon]) then return nil end
	return icon
end

local function badgeMetrics(style, icon, font, h)
	icon = realIcon(icon)
	local pad = math.floor(h * 0.35)
	local isz = icon and UI.IconSize(h - 6) or 0
	if isz > h - 2 then isz = math.max(16, isz - 16) end
	local tw = UI.StyleWidth(style, font)
	return pad * 2 + tw + (icon and (isz + pad * 0.6) or 0), pad, isz
end

function UI.BadgeWidth(style, icon, font, h)
	if not style then return 0 end
	return (badgeMetrics(style, icon, font, h))
end

-- Pill with optional pixel icon + styled text. Returns the width.
function UI.Badge(style, icon, font, x, y, h, alpha, ax)
	if not style then return 0 end
	alpha = alpha or 255
	icon = realIcon(icon)
	local w, pad, isz = badgeMetrics(style, icon, font, h)
	if ax == TEXT_ALIGN_CENTER then x = x - w / 2 elseif ax == TEXT_ALIGN_RIGHT then x = x - w end
	local c1 = P.ReadColor(style.c1, UI.C.ivory)
	-- dark pill tinted with the rank colour
	local r = math.floor(h * 0.32)
	UI.Round(x, y, w, h, r, Color(18, 19, 24, 230 * alpha / 255))
	UI.Round(x, y, w, h, r, Color(c1.r, c1.g, c1.b, 34 * alpha / 255), Color(c1.r * 0.75, c1.g * 0.75, c1.b * 0.75, alpha * 0.9))
	local cx = x + pad
	if icon then
		UI.Icon(icon, cx, y + (h - isz) / 2, isz, Color(255, 255, 255, alpha))
		cx = cx + isz + pad * 0.6
	end
	UI.DrawStyle(style, font, cx, y + h / 2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, alpha)
	return w
end

-- Static version as chat.AddText parts (colour per letter)
function UI.StyleParts(style, out, l, r)
	return P.StyleChatParts(style, out, l, r)
end
