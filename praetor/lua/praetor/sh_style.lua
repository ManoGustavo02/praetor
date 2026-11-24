-- Praetor: colour maths for styled tags (gradient + effects).
-- Used by the chat (static colours per letter) and by the animated painters.
local P = Praetor

local function lerpC(f, a, b)
	local aa, ba = a.a or 255, b.a or 255
	return Color(
		a.r + (b.r - a.r) * f,
		a.g + (b.g - a.g) * f,
		a.b + (b.b - a.b) * f,
		aa + (ba - aa) * f)
end
P.LerpColor = lerpC

local function lighten(c, k)
	return Color(c.r + (255 - c.r) * k, c.g + (255 - c.g) * k, c.b + (255 - c.b) * k)
end
P.Lighten = lighten

local cache = setmetatable({}, { __mode = "k" })

local function colors(style)
	local c = cache[style]
	if c then return c[1], c[2] end
	local c1 = P.ReadColor(style.c1, Color(237, 228, 211))
	local c2 = style.c2 and P.ReadColor(style.c2, nil) or nil
	cache[style] = { c1, c2 }
	return c1, c2
end

-- Colour of letter i (1-based) out of n. t = time in seconds, or nil for a still frame.
function P.StyleColorAt(style, i, n, t)
	local c1, c2 = colors(style)
	local fx = style.fx or "none"
	local f = n > 1 and (i - 1) / (n - 1) or 0

	if fx == "rainbow" then
		local hue = (f * 300 + (t or 0) * 140) % 360
		return HSVToColor(hue, 0.62, 1)
	end

	local base
	if fx == "flow" and t then
		local b = c2 or lighten(c1, 0.55)
		local k = 0.5 + 0.5 * math.sin(f * math.pi * 2 - t * 3.2)
		base = lerpC(k, c1, b)
	elseif c2 then
		base = lerpC(f, c1, c2)
	else
		base = Color(c1.r, c1.g, c1.b)
	end

	if not t then return base end

	if fx == "shine" then
		local pos = (t * 0.75) % 1.8 - 0.4
		local d = math.abs(f - pos)
		if d < 0.18 then base = lighten(base, (1 - d / 0.18) * 0.8) end
	elseif fx == "pulse" then
		local k = 0.5 + 0.5 * math.sin(t * 4)
		base = lighten(base, k * 0.45)
	end
	return base
end

-- Vertical offset of letter i for the "wave" effect.
function P.StyleOffsetAt(style, i, t, amp)
	if style.fx ~= "wave" or not t then return 0 end
	return math.sin(t * 6 - i * 0.55) * (amp or 2)
end

-- Builds chat.AddText arguments: one colour per letter.
function P.StyleChatParts(style, out, wrapL, wrapR)
	out = out or {}
	local chars = P.Chars(style.text or "")
	local n = #chars
	if wrapL then
		out[#out + 1] = P.StyleColorAt(style, 1, n)
		out[#out + 1] = wrapL
	end
	-- group letters with the same colour to keep the message small
	local last, buf = nil, {}
	for i, ch in ipairs(chars) do
		local c = P.StyleColorAt(style, i, n)
		if last and (c.r ~= last.r or c.g ~= last.g or c.b ~= last.b) then
			out[#out + 1] = last
			out[#out + 1] = table.concat(buf)
			buf = {}
		end
		last = c
		buf[#buf + 1] = ch
	end
	if last then
		out[#out + 1] = last
		out[#out + 1] = table.concat(buf)
	end
	if wrapR then
		out[#out + 1] = P.StyleColorAt(style, n, n)
		out[#out + 1] = wrapR
	end
	return out
end
