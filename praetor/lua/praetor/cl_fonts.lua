-- Praetor: fonts and UI scale.
-- Barlow Semi Condensed ships in resource/fonts (SIL OFL).
local P = Praetor
P.UI = P.UI or {}

local SANS = "Barlow Semi Condensed Medium"
local SANS_SEMI = "Barlow Semi Condensed SemiBold"
local SANS_BOLD = "Barlow Semi Condensed"

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

-- Barlow only has Latin letters. Names with Cyrillic, Greek, Japanese, Chinese,
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
	font("Praetor.Logo", SANS_BOLD, 30, 800, 22)
	font("Praetor.H1", SANS_BOLD, 25, 700, 19)
	font("Praetor.H2", SANS_BOLD, 20, 700, 16)
	font("Praetor.H3", SANS_SEMI, 17, 600, 14)
	font("Praetor.Body", SANS, 18, 500, 15)
	font("Praetor.BodyB", SANS_SEMI, 18, 600, 15)
	font("Praetor.Big", SANS_BOLD, 22, 700, 17)
	font("Praetor.Small", SANS, 15, 500, 13)
	font("Praetor.SmallB", SANS_SEMI, 15, 600, 13)
	font("Praetor.Tiny", SANS_SEMI, 13, 600, 12)
	font("Praetor.Tag", SANS_BOLD, 15, 700, 13)
	font("Praetor.Mono", "Consolas", 15, 500, 13)

	-- fixed sizes for 3D2D (scaled in the world, not on screen)
	surface.CreateFont("Praetor.OH.Name", { font = SANS_BOLD, size = 64, weight = 700, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Rank", { font = SANS_SEMI, size = 44, weight = 600, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Small", { font = SANS_SEMI, size = 40, weight = 600, antialias = true, extended = true })
	surface.CreateFont("Praetor.OH.Tag", { font = SANS_BOLD, size = 42, weight = 700, antialias = true, extended = true })
	defs["Praetor.OH.Name"] = { size = 64, weight = 700 }
	defs["Praetor.OH.Small"] = { size = 40, weight = 600 }

	P.UI.BuildChatFonts()
	hook.Run("Praetor.FontsBuilt")
end

local chatScale = CreateClientConVar("praetor_chat_scale", "1", true, false, "Praetor chat text size (0.8 - 1.5)", 0.8, 1.5)
P.ChatScaleVar = chatScale

function P.UI.BuildChatFonts()
	local k = math.Clamp(chatScale:GetFloat(), 0.8, 1.5)
	local size = math.max(15, math.Round(P.S(19) * k))
	surface.CreateFont("Praetor.Chat", { font = SANS_SEMI, size = size, weight = 600, antialias = true, extended = true, shadow = false })
	surface.CreateFont("Praetor.ChatB", { font = SANS_BOLD, size = size, weight = 700, antialias = true, extended = true })
	surface.CreateFont("Praetor.ChatTag", { font = SANS_BOLD, size = math.max(13, size - 3), weight = 700, antialias = true, extended = true })
	surface.CreateFont("Praetor.ChatSmall", { font = SANS, size = math.max(12, size - 5), weight = 500, antialias = true, extended = true })
	defs["Praetor.Chat"] = { size = size, weight = 600 }
	defs["Praetor.ChatB"] = { size = size, weight = 700 }
	for k in pairs(wideMade) do if k:find("^Praetor%.Chat") then wideMade[k] = nil end end
end

cvars.AddChangeCallback("praetor_chat_scale", function() P.UI.BuildChatFonts() hook.Run("Praetor.FontsBuilt") end, "Praetor")

P.UI.BuildFonts()
hook.Add("OnScreenSizeChanged", "Praetor.Fonts", function() P.UI.BuildFonts() end)
