-- Praetor: loading screen. Garry's Mod shows a web page while a player joins
-- (sv_loadingurl). Praetor's page lives on GitHub Pages and reads its look from
-- the link, so the server only builds the link from the settings menu.
local P = Praetor

local original      -- sv_loadingurl as it was before Praetor touched it
local MAX_URL = 1500

local function enc(s)
	return (tostring(s or ""):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function txt(k) return P.Trim(tostring(P.Setting(k) or "")) end

function P.LoadingURL()
	local base = txt("loading_base")
	if base == "" then base = P.Defaults.loading_base end
	-- empty = the server name; the page also takes the live name Garry's Mod gives it
	local name = txt("loading_name")
	local fixed = name ~= ""
	if not fixed then name = GetHostName() end
	local acc = txt("loading_accent"):gsub("[^%x]", "")
	if #acc ~= 6 then acc = "8e62ff" end

	local q = { "name=" .. enc(P.Str(name, 60)), "accent=" .. acc, "map=%m" }
	if fixed then q[#q + 1] = "fixed=1" end
	local sub = txt("loading_sub")
	if sub ~= "" then q[#q + 1] = "sub=" .. enc(P.Str(sub, 80)) end
	for _, k in ipairs({ "bg", "logo" }) do
		local v = txt("loading_" .. k)
		if v:find("^https?://") then q[#q + 1] = k .. "=" .. enc(v) end
	end
	local disc = txt("loading_discord")
	if disc == "" then disc = txt("ban_discord") end
	if disc ~= "" then q[#q + 1] = "discord=" .. enc(P.Str((disc:gsub("^https?://", "")), 60)) end

	if not P.Setting("loading_music") then
		q[#q + 1] = "music=0"
	else
		local mu = txt("loading_music_url")
		q[#q + 1] = "music=" .. (mu:find("^https?://") and enc(mu) or "1")
		q[#q + 1] = "vol=" .. math.Clamp(math.floor(tonumber(P.Setting("loading_vol")) or 40), 0, 100)
	end

	local url = base .. (base:find("?", 1, true) and "&" or "?") .. table.concat(q, "&")
	-- tips last: they are cut so the link never gets too long
	local tips = {}
	for line in (txt("loading_tips") .. "\n"):gmatch("([^\n]*)\n") do
		line = P.Trim((line:gsub("|", "/")))
		if line ~= "" then
			local part = enc(P.Str(line, 140))
			local nextLen = #url + #"&tips=" + #table.concat(tips, "%7C") + 3 + #part
			if nextLen > MAX_URL then break end
			tips[#tips + 1] = part
		end
	end
	if #tips > 0 then url = url .. "&tips=" .. table.concat(tips, "%7C") end
	return url
end

local function isOurs(u) return isstring(u) and u:find("praetor", 1, true) ~= nil and u:find("loading", 1, true) ~= nil end

function P.ApplyLoading()
	local cur = GetConVarString("sv_loadingurl")
	if original == nil and not isOurs(cur) then original = cur end
	local on = P.Setting("loading_on")
	-- a server that already had its own loading screen keeps it until the owner turns ours on
	if P.Settings.loading_on == nil and original and original ~= "" then on = false end
	if on then
		local url = P.LoadingURL()
		if cur ~= url then RunConsoleCommand("sv_loadingurl", url) end
	elseif isOurs(cur) then
		RunConsoleCommand("sv_loadingurl", original or "")
	end
end

hook.Add("InitPostEntity", "Praetor.Loading", function() timer.Simple(1, P.ApplyLoading) end)
timer.Simple(2, P.ApplyLoading)
hook.Add("Praetor.SettingsChanged", "Praetor.Loading", function(changed)
	for _, k in ipairs(changed or {}) do
		if k:find("^loading_") or k == "ban_discord" then P.ApplyLoading() return end
	end
end)
