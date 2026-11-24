-- Praetor: automod word matching (shared, so the menu can test a message
-- before the rules are saved).
--
-- List format, one entry per line (commas also work):
--   word      whole word only ("ass" does not hit "class")
--   word*     words that start with it
--   *word     words that end with it
--   *word*    anywhere inside a word
--   two words a phrase
-- Every entry also catches the usual tricks: accents, upper case, numbers in
-- place of letters (p0rn, s3x), repeated letters (puuuta) and spaced letters
-- (p u t a, p.u.t.a).
local P = Praetor

local ACCENT = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n", ["ý"] = "y", ["Ý"] = "y",
}
local LEET = { ["4"] = "a", ["@"] = "a", ["3"] = "e", ["1"] = "i", ["!"] = "i", ["|"] = "i", ["0"] = "o", ["5"] = "s", ["$"] = "s", ["7"] = "t" }

local function norm(s)
	s = tostring(s or "")
	s = s:gsub("[\192-\223][\128-\191]", ACCENT)
	s = s:lower()
	s = s:gsub("[%d@!|%$]", LEET)
	return s
end

-- "puuuta" -> "puta" (letters only, so numbers keep their digits)
local function collapse(s)
	local out, last = {}, nil
	for i = 1, #s do
		local c = s:sub(i, i)
		if c ~= last or not c:match("%a") then out[#out + 1] = c end
		last = c
	end
	return table.concat(out)
end

local cache = {}

-- Turns a list (text) into match entries. Cached by the text itself.
function P.AutoModCompile(list)
	list = tostring(list or "")
	if cache[list] then return cache[list] end
	local out = {}
	for raw in list:gmatch("[^\n,;]+") do
		raw = P.Trim(raw)
		if raw ~= "" and #out < 800 then
			local pre = raw:sub(1, 1) == "*"
			local suf = #raw > 1 and raw:sub(-1) == "*"
			local core = raw:gsub("^%*+", ""):gsub("%*+$", "")
			core = norm(core):gsub("[^%w ]", ""):gsub("%s+", " ")
			core = collapse(P.Trim(core))
			if #core >= 2 then
				out[#out + 1] = { raw = raw, w = core, pre = pre, suf = suf, phrase = core:find(" ", 1, true) ~= nil }
			end
		end
	end
	if table.Count(cache) > 12 then cache = {} end
	cache[list] = out
	return out
end

local function hit(e, tok, contains, link)
	if e.phrase then return false end
	-- "*word*" entries of the main list would hit folder names inside links (/assets/)
	if e.pre and e.suf then return not link and tok:find(e.w, 1, true) ~= nil end
	if e.suf then return tok:sub(1, #e.w) == e.w end
	if e.pre then return tok:sub(-#e.w) == e.w end
	if tok == e.w then return true end
	-- inside links even plain entries match as part of a word (sexy-girl.gif, nsfw_clip),
	-- but only when they are long enough not to hit innocent words
	return contains and #e.w >= 4 and tok:find(e.w, 1, true) ~= nil
end

-- Returns the list entry that matched, or nil.
function P.AutoModFind(text, block, allow, contains, link)
	if #block == 0 then return nil end
	local toks = {}
	for w in norm(text):gmatch("%w+") do toks[#toks + 1] = collapse(w) end
	local line = " " .. table.concat(toks, " ") .. " "
	-- "p u t a" / "p.u.t.a": runs of single letters are also read as one word
	local run, n = {}, #toks
	for i = 1, n + 1 do
		local t = toks[i]
		if t and #t == 1 then run[#run + 1] = t
		else
			if #run >= 3 then toks[#toks + 1] = collapse(table.concat(run)) end
			run = {}
		end
	end
	for _, tok in ipairs(toks) do
		local allowed = false
		for _, a in ipairs(allow) do
			if hit(a, tok, false) then allowed = true break end
		end
		if not allowed then
			for _, e in ipairs(block) do
				if hit(e, tok, contains, link) then return e.raw end
			end
		end
	end
	for _, e in ipairs(block) do
		if e.phrase and line:find(" " .. e.w .. " ", 1, true) then return e.raw end
	end
	return nil
end

local function unescape(url)
	return (url:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Checks a chat line. Returns: matched entry, "text" or "image", the link.
-- opts: { words, allow, images, image_words } (defaults to the server settings)
function P.AutoModScan(text, opts)
	opts = opts or {}
	local get = function(k, def) if opts[k] ~= nil then return opts[k] end return P.Setting and P.Setting("automod_" .. k) or def end
	local block = P.AutoModCompile(get("words", ""))
	local allow = P.AutoModCompile(get("allow", ""))
	text = tostring(text or "")

	local plain = text:gsub("%a[%w+.-]*://%S+", " ")
	local w = P.AutoModFind(plain, block, allow, false)
	if w then return w, "text" end

	if get("images", true) then
		local img = P.AutoModCompile(get("image_words", ""))
		for url in text:gmatch("%a[%w+.-]*://%S+") do
			local u = unescape(url)
			local x = P.AutoModFind(u, img, allow, true) or P.AutoModFind(u, block, allow, false, true)
			if x then return x, "image", url end
		end
	end
	return nil
end

-- True when this player is not checked by the AutoMod: owners and the
-- automod_bypass permission, but only while "check staff too" is off.
function P.AutoModSkips(ply)
	if P.Setting("automod_staff") then return false end
	if not IsValid(ply) then return false end
	if P.IsOwner(ply) then return true end
	if SERVER then return P.Has(ply, "automod_bypass") end
	return ply == LocalPlayer() and P.MyHas("automod_bypass") or false
end
