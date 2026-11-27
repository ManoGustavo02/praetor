-- Praetor: fonts and UI scale.
-- 1.5.0: titles and numbers use "Praetor Display" (Bagel Fat One) and the text uses
-- "Praetor Body" (Nunito). Both ship in resource/fonts, renamed, under the SIL OFL.
local P = Praetor
P.UI = P.UI or {}

local DISPLAY = "Praetor Display"
local SANS = "Praetor Body"
local SANS_SEMI = "Praetor Body"
local SANS_BOLD = "Praetor Body Heavy"
local SANS_BLACK = "Praetor Body Black"
P.UI.FontFaces = { display = DISPLAY, body = SANS, heavy = SANS_BOLD, black = SANS_BLACK }

-- UI scale: 1 at 1080p, never below 0.8 so small screens stay readable.
function P.UI.Scale()
	return math.Clamp(ScrH() / 1080, 0.8, 1.3)
end

function P.S(v)
	return math.Round(v * P.UI.Scale())
end

P.UI.FontDefs = P.UI.FontDefs or {}
local defs = P.UI.FontDefs

local function font(name, face, size, weight, min)
	local px = math.max(min or 12, P.S(size))
	surface.CreateFont(name, {
		font = face, size = px, weight = weight or 500,
		antialias = true, extended = true,
	})
	defs[name] = { size = px, weight = weight or 500 }
end

-- The fonts only have Latin letters. Names with Cyrillic, Greek, Japanese, Chinese,
-- Arabic... showed empty boxes, so text with those letters is drawn with a
-- system font that has them (Segoe UI links to the Asian fonts on Windows).
local FALLBACK = system.IsWindows() and "Segoe UI" or (system.IsOSX() and "Helvetica" or "DejaVu Sans")
local wideMade, wideCache, wideCount = {}, {}, 0

local function needsWide(text)
	for _, c in utf8.codes(text) do
		if c > 0x24F and not (c >= 0x2000 and c <= 0x206F) and not (c >= 0x20A0 and c <= 0x20CF) then return true end
	end
	return false
end

-- "Fancy" names made of math letters (𝓝𝓪𝓶𝓮, 𝐍𝐚𝐦𝐞, ℕ𝕒𝕞𝕖...) or full-width letters
-- (Ｎａｍｅ): no font in the game has them and they showed as boxes. They are drawn
-- as the plain letters they stand for.
local LETTERLIKE = {
	[0x210E] = "h", [0x212C] = "B", [0x2130] = "E", [0x2131] = "F", [0x210B] = "H", [0x2110] = "I", [0x2112] = "L",
	[0x2133] = "M", [0x211B] = "R", [0x212F] = "e", [0x210A] = "g", [0x2134] = "o", [0x212D] = "C", [0x210C] = "H",
	[0x2111] = "I", [0x211C] = "R", [0x2128] = "Z", [0x2102] = "C", [0x210D] = "H", [0x2115] = "N", [0x2119] = "P",
	[0x211A] = "Q", [0x211D] = "R", [0x2124] = "Z",
}
local plainCache, plainCount = {}, 0
local function plainChar(c)
	if c >= 0x1D400 and c <= 0x1D6A3 then
		local k = (c - 0x1D400) % 52
		return k < 26 and string.char(65 + k) or string.char(97 + k - 26)
	end
	if c >= 0x1D7CE and c <= 0x1D7FF then return string.char(48 + (c - 0x1D7CE) % 10) end
	if c >= 0xFF01 and c <= 0xFF5E then return string.char(c - 0xFEE0) end
	if c >= 0x24B6 and c <= 0x24CF then return string.char(65 + c - 0x24B6) end -- Ⓐ
	if c >= 0x24D0 and c <= 0x24E9 then return string.char(97 + c - 0x24D0) end -- ⓐ
	if c >= 0x1F130 and c <= 0x1F149 then return string.char(65 + c - 0x1F130) end -- 🄰
	if c >= 0x1F150 and c <= 0x1F169 then return string.char(65 + c - 0x1F150) end -- 🅐
	if c >= 0x1F170 and c <= 0x1F189 then return string.char(65 + c - 0x1F170) end -- 🅰
	return LETTERLIKE[c]
end
function P.UI.PlainName(text)
	if not isstring(text) or not text:find("[\240-\244\226\239]") then return text end
	local hit = plainCache[text]
	if hit then return hit end
	local ok, out = pcall(function()
		local parts = {}
		for _, c in utf8.codes(text) do parts[#parts + 1] = plainChar(c) or utf8.char(c) end
		return table.concat(parts)
	end)
	out = ok and out or text
	if plainCount > 2000 then plainCache, plainCount = {}, 0 end
	plainCache[text] = out
	plainCount = plainCount + 1
	return out
end

function P.UI.FontFor(text, name)
	if not isstring(text) or not text:find("[\128-\255]") then return name end
	local need = wideCache[text]
	if need == nil then
		local ok, res = pcall(needsWide, text)
		need = ok and res or false
		if wideCount > 2000 then wideCache, wideCount = {}, 0 end
		wideCache[text] = need
		wideCount = wideCount + 1
	end
	if not need then return name end
	local d = defs[name]
	if not d then return name end
	local wide = name .. ".W"
	if not wideMade[wide] then
		surface.CreateFont(wide, { font = FALLBACK, size = d.size, weight = math.min(d.weight, 600), antialias = true, extended = true })
		wideMade[wide] = true
	end
	return wide
end

function P.UI.BuildFonts()
	wideMade = {}
	font("Praetor.Logo", DISPLAY, 30, 400, 22)
	font("Praetor.H1", DISPLAY, 24, 400, 18)
	font("Praetor.H2", SANS_BLACK, 19, 900, 15)
	font("Praetor.H3", SANS_BOLD, 16, 800, 13)
	font("Praetor.Body", SANS, 16, 700, 14)
	font("Praetor.BodyB", SANS_BOLD, 16, 800, 14)
	font("Praetor.Big", DISPLAY, 21, 400, 16)
	font("Praetor.Small", SANS, 14, 700, 12)
	font("Praetor.SmallB", SANS_BOLD, 14, 800, 12)
	font("Praetor.Tiny", SANS_BOLD, 12, 800, 11)
	font("Praetor.Tag", SANS_BLACK, 13, 900, 12)
	font("Praetor.Num", DISPLAY, 28, 400, 20)
	font("Praetor.Hero", DISPLAY, 46, 400, 30)
	font("Praetor.Mono", "Consolas", 15, 500, 13)

	-- fixed sizes for 3D2D (scaled in the world, not on screen)
	surface.CreateFont("Praetor.OH.Name", { font = DISPLAY, size = 64, weight = 400, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Rank", { font = SANS_SEMI, size = 44, weight = 600, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Small", { font = SANS_SEMI, size = 40, weight = 600, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Tag", { font = SANS_BLACK, size = 42, weight = 900, antialias = true, extended = true })
	defs["Praetor.OH.Name"] = { size = 64, weight = 700 }
	defs["Praetor.OH.Small"] = { size = 40, weight = 600 }

	P.UI.BuildChatFonts()
	hook.Run("Praetor.FontsBuilt")
end

local chatScale = CreateClientConVar("praetor_chat_scale", "1", true, false, "Praetor chat text size (0.8 - 1.5)", 0.8, 1.5)
P.ChatScaleVar = chatScale

function P.UI.BuildChatFonts()
	local k = math.Clamp(chatScale:GetFloat(), 0.8, 1.5)
	local size = math.max(14, math.Round(P.S(18) * k))
	surface.CreateFont("Praetor.Chat", { font = SANS, size = size, weight = 700, antialias = true, extended = true, shadow = false })
	surface.CreateFont("Praetor.ChatB", { font = SANS_BLACK, size = size, weight = 900, antialias = true, extended = true })
	surface.CreateFont("Praetor.ChatTag", { font = SANS_BLACK, size = math.max(12, size - 4), weight = 900, antialias = true, extended = true })
	surface.CreateFont("Praetor.ChatSmall", { font = SANS, size = math.max(12, size - 5), weight = 700, antialias = true, extended = true })
	defs["Praetor.Chat"] = { size = size, weight = 600 }
	defs["Praetor.ChatB"] = { size = size, weight = 700 }
	for k in pairs(wideMade) do if k:find("^Praetor%.Chat") then wideMade[k] = nil end end
end

cvars.AddChangeCallback("praetor_chat_scale", function() P.UI.BuildChatFonts() hook.Run("Praetor.FontsBuilt") end, "Praetor")

P.UI.BuildFonts()
hook.Add("OnScreenSizeChanged", "Praetor.Fonts", function() P.UI.BuildFonts() end)
