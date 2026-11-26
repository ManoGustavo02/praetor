-- Praetor: shared core (helpers, settings, small utilities)
local P = Praetor

P.Settings = P.Settings or {}
P.Hooks = P.Hooks or {}

P.Col = {
	bronze  = Color(142, 98, 255),
	bronzeL = Color(188, 160, 255),
	bronzeD = Color(86, 54, 180),
	ivory   = Color(237, 228, 211),
	muted   = Color(168, 156, 140),
	crimson = Color(178, 52, 66),
	laurel  = Color(122, 168, 98),
	sky     = Color(120, 170, 210),
	ink     = Color(21, 18, 26),
}

-- Default settings. Everything here can be changed from the in-game Settings tab.
P.Defaults = {
	lang              = "auto",     -- auto / en / pt
	prefix_silent     = "~",        -- ~kick runs a command without the broadcast
	echo              = "all",      -- all / staff / none
	equal_target      = false,      -- can a rank act on players with the same authority?
	rank_lock         = true,       -- block ply:SetUserGroup() calls that do not come from Praetor
	rank_lock_max     = 20,         -- external code may still set ranks up to this authority (VIP shops)
	family_ban        = true,       -- Family Sharing account of a banned player = same ban
	family_block      = false,      -- kick every Family Sharing (borrowed) account
	menu_key          = "",         -- optional bind hint shown in the menu
	-- chat
	chat_mode         = "praetor",  -- praetor (own chat box) / tags (keep other chat addons) / off
	chat_avatars      = true,
	chat_images       = true,
	chat_image_hosts  = "i.imgur.com,media.tenor.com,media1.tenor.com,c.tenor.com,media.giphy.com,i.giphy.com,cdn.discordapp.com,media.discordapp.net,i.redd.it",
	chat_image_size   = 160,
	chat_timestamps   = false,
	chat_rank_tag     = true,
	chat_local_dist   = 600,        -- "Nearby" tab of the chat box: how far the message goes (0 = no tab)
	adminchat_prefix  = "@",
	-- scoreboard
	scoreboard        = true,
	scoreboard_group  = "group",    -- group / rank / job / none
	scoreboard_title  = "",
	scoreboard_darkrp = true,       -- DarkRP: the TAB groups by job and shows police / wanted / salary
	-- DarkRP HUD and F4 menu (each one can be turned off to keep another addon's)
	hud               = true,
	hud_hunger        = true,       -- the hunger bar (only when DarkRP's hunger mod is on)
	hud_agenda        = true,       -- the agenda / laws box
	f4                = true,
	f4_commands       = true,       -- the bar of RP commands in the F4
	-- overhead tag
	overhead          = true,
	overhead_dist     = 700,
	overhead_avatar   = true,
	overhead_rank     = true,
	overhead_title    = true,
	overhead_tag      = true,
	overhead_job      = true,
	overhead_health   = false,
	overhead_hours    = true,
	overhead_staff    = true,       -- show the "on duty" seal
	overhead_voice    = true,       -- microphone when the player talks
	overhead_target   = true,       -- aiming at a player shows their health and armor under the crosshair
	-- moderation
	afk_time          = 300,
	warn_decay_days   = 30,
	warn_rules        = { { pts = 3, act = "kick", min = 0 }, { pts = 5, act = "ban", min = 1440 }, { pts = 8, act = "ban", min = 10080 } },
	physgun_players   = true,
	physgun_freeze    = true,       -- right click while holding a player freezes them
	duty_strip        = true,       -- !duty puts away the weapons that hurt (given back after)
	duty_baton        = true,       -- !duty gives the staff baton
	duty_cloak        = false,      -- !duty also makes the staff invisible (taken off when duty ends)
	esp_block         = true,       -- E2 / Starfall chips can't find or follow staff on duty or invisible players
	-- logs & reports
	log_days          = 21,
	log_damage        = true,
	log_props         = true,
	reports           = true,
	reports_cooldown  = 60,
	reports_blackbox  = true,       -- let Blackbox handle !report when it is installed
	report_shot       = true,       -- the report window offers a picture of the player's own screen
	perm_announce     = "staff",    -- chat line when someone edits rank / player permissions: all / staff / none
	-- player votes (!votekick, !voteban, !votemute, !voteclearprops, !votecleanup, !votefreeze)
	pv_enabled        = true,
	pv_ratio          = 60,         -- % of "yes" among who voted
	pv_min_votes      = 3,          -- at least this many "yes"
	pv_min_players    = 4,          -- players online to start one
	pv_cooldown       = 180,        -- seconds between votes of the same player
	pv_time           = 30,         -- how long the vote lasts
	pv_ban_min        = 60,         -- ban length of !voteban (minutes)
	pv_no_staff       = false,      -- only when no staff is online
	-- support rooms
	sit_auto          = true,       -- no room saved on this map: build one up in the sky
	sit_god           = true,       -- nobody takes damage inside a support room
	sit_on_claim      = false,      -- claiming a report / Blackbox case opens a room at once
	-- staff & accounts
	staff_inactive_days = 7,        -- staff panel: days without playing before "inactive"
	alt_check         = true,       -- link accounts that join from the same address
	alt_action        = "ban",      -- linked to a banned account: alert / kick / ban (ban = for the rest of the main ban)
	alt_days          = 60,         -- how long an address keeps linking accounts
	alt_alert_all     = false,      -- also alert staff for linked accounts that are not banned
	-- spawning
	dupe_max_ents     = 250,
	dupe_max_cons     = 400,
	dupe_cooldown     = 6,
	dupe_bypass       = true,       -- ranks with "ignore limits" may paste past the limit (they are still warned)
	prop_blacklist    = "",         -- models a dupe may not carry (the owner adds the paths)
	dupe_announce     = "staff",    -- who sees "X tried to paste a dupe of N entities": all / staff / none
	dupe_message      = "",         -- custom text, {player} {count} {limit}; empty = built-in message
	-- prop protection
	pp_enabled        = true,       -- players only touch their own things (off by itself when FPP / another CPPI runs)
	pp_cleanup_min    = 5,          -- props of who left are removed after this many minutes (0 = never)
	pp_world          = false,      -- players may move / delete map entities
	pp_damage         = true,       -- players can't break the things of others
	pp_use            = false,      -- players can't press E on the things of others
	pp_hud            = true,       -- show the owner of what you aim at
	-- ban screen
	ban_discord       = "",         -- link shown on the ban screen (Discord invite or a site)
	ban_appeal        = "",         -- text under the link (how to ask for a review)
	ban_screen        = true,       -- a player banned while online sees the screen before leaving
	ban_screen_join   = true,       -- a banned player who tries to join sees the screen, then leaves
	ban_screen_time   = 30,         -- seconds on the screen before the kick
	sg_quality        = 70,         -- JPEG quality of !screengrab (20 - 95)
	ban_announce      = "all",      -- chat line "X was banned by Y: reason": all / staff / none
	ban_try_announce  = "all",      -- chat line "X tried to join but is banned": all / staff / none
	-- anti-crash
	ac_enabled        = true,
	ac_spawn_freeze   = true,       -- props spawned inside other props start frozen
	ac_physenv        = true,       -- limit collision checks per tick (piles slow down instead of hanging)
	ac_lag            = true,       -- server lag guard
	ac_lag_ms         = 120,        -- average frame time that counts as lag (ms)
	ac_min_awake      = 25,         -- props awake needed to blame the physics for the lag
	ac_lag_remove     = false,      -- remove (instead of freeze) colliding props when lag keeps going
	ac_crazy          = true,       -- props with broken physics (NaN / absurd speed)
	ac_spam           = true,       -- spawn spam
	ac_spam_count     = 12,         -- spawns allowed ...
	ac_spam_secs      = 3,          -- ... in this many seconds
	-- loading screen (a web page on GitHub Pages, see sv_loading)
	loading_on        = true,       -- use Praetor's loading screen (a server with its own keeps it until this is saved)
	loading_base      = "https://praetor-loading.vercel.app/",
	loading_name      = "",         -- empty = server name
	loading_sub       = "",         -- short line under the name
	loading_tips      = "",         -- one tip per line (empty = Praetor's tips)
	loading_accent    = "8e62ff",   -- colour (hex)
	loading_bg        = "",         -- link to a background picture
	loading_logo      = "",         -- link to a logo picture
	loading_discord   = "",         -- empty = the ban screen link
	loading_music     = true,
	loading_music_url = "",         -- empty = Praetor's music; or a link to an .mp3 / .ogg
	loading_vol       = 40,         -- 0 - 100
	-- scoreboard music
	tab_music         = true,       -- music while the TAB is open (each player can turn it off)
	menu_music        = true,       -- the same music while the Praetor menu is open
	f4_music          = true,       -- and while the DarkRP F4 menu is open
	tab_music_url     = "",         -- empty = Praetor's music; or a link to an .mp3 / .ogg
	tab_music_vol     = 30,         -- 0 - 100
	ac_net            = true,       -- net message flood
	ac_net_limit      = 1500,       -- net messages per second before a kick
	ac_chat           = true,       -- chat flood
	ac_chat_count     = 6,          -- messages allowed ...
	ac_chat_secs      = 4,          -- ... in this many seconds (then a 2 minute mute)
	ac_ent_cap        = 0,          -- hard cap of entities a single player can own (0 = off)
	ac_notify         = true,       -- tell online staff what the anti-crash did
	-- darkrp
	rp_blacklist_kick = true,       -- move players out of a job when they get blacklisted

	-- automod (like Discord's): blocked words, exceptions and a filter for GIF / image links
	automod             = true,
	automod_words       = "",       -- one per line; word = whole word, word* = starts with, *word* = contains
	automod_allow       = "",       -- exceptions that are never blocked
	automod_images      = true,     -- also read GIF / image / link addresses
	automod_image_words = "nsfw\nporn\nporno\npornhub\nxvideos\nxxx\nhentai\nrule34\nr34\nnude\nnudes\nnaked\nlewd\necchi\nonlyfans\nboobs\ntits\npussy\nblowjob\nmilf\nsexy\nsex\nsexo\nputaria\npelada\npelado\nsafada\nbuceta\npiroca\ngore\nbeheading\ndecapitacao\nsuicide\nsuicidio",
	automod_action      = "block",  -- block / warn / mute / kick
	automod_mute_min    = 5,
	automod_message     = "",       -- custom text shown to the player; empty = built in
	automod_alert       = true,     -- tell online staff
	automod_staff       = true,     -- also check owners and automod_bypass (off = staff skips the filter)
	automod_workshop    = true,     -- check Workshop content (Outfitter, Wardrobe, PAC3, any steamworks download) before it downloads

	-- Discord webhook
	webhook_url         = "",       -- never sent to players
	webhook_name        = "Praetor",
	webhook_lang        = "en",
	webhook_cmd         = true,
	webhook_punish      = true,
	webhook_automod     = true,
	webhook_report      = true,
	webhook_rank        = true,
	webhook_security    = true,
	webhook_settings    = false,
	webhook_chat        = false,
	webhook_conn        = false,
	webhook_kill        = false,
	webhook_rp          = false,
	webhook_money       = false,
	webhook_player      = false,
	webhook_round       = false,
}

function P.Setting(k)
	local v = P.Settings[k]
	if v == nil then return P.Defaults[k] end
	return v
end

-- ------------------------------------------------------------------ strings

-- Cuts a string to `max` characters (UTF-8 aware) and removes control chars.
function P.Str(s, max)
	if s == nil then return "" end
	s = tostring(s)
	s = s:gsub("[%z\1-\8\11\12\14-\31\127]", "")
	max = max or 128
	if #s <= max then return s end
	local out, n = {}, 0
	local ok = pcall(function()
		for _, c in utf8.codes(s) do
			n = n + 1
			if n > max then break end
			out[n] = utf8.char(c)
		end
	end)
	if not ok then return s:sub(1, max) end
	return table.concat(out)
end

function P.Chars(s)
	local t = {}
	local ok = pcall(function()
		for _, c in utf8.codes(s) do t[#t + 1] = utf8.char(c) end
	end)
	if not ok then
		t = {}
		for i = 1, #s do t[i] = s:sub(i, i) end
	end
	return t
end

-- string.upper only knows ASCII: "Moderação" became "MODERAçãO" in the menus.
local UPPER = {
	["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["ä"] = "Ä", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
	["í"] = "Í", ["ì"] = "Ì", ["î"] = "Î", ["ï"] = "Ï", ["ó"] = "Ó", ["ò"] = "Ò", ["ô"] = "Ô", ["õ"] = "Õ", ["ö"] = "Ö",
	["ú"] = "Ú", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ç"] = "Ç", ["ñ"] = "Ñ",
}
function P.Upper(s)
	s = string.upper(tostring(s or ""))
	for lo, up in pairs(UPPER) do s = s:gsub(lo, up) end
	return s
end

function P.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Splits a command line, keeping "quoted words" together.
function P.SplitArgs(line)
	local args, cur, inq = {}, {}, false
	for _, ch in ipairs(P.Chars(line or "")) do
		if ch == "\"" then
			inq = not inq
		elseif ch:match("^%s$") and not inq then
			if #cur > 0 then args[#args + 1] = table.concat(cur) cur = {} end
		else
			cur[#cur + 1] = ch
		end
	end
	if #cur > 0 then args[#args + 1] = table.concat(cur) end
	return args
end

-- ------------------------------------------------------------------ steam ids

local function steam32to64(str)
	local s64 = util.SteamIDTo64(str)
	if s64 and s64 ~= "0" then return s64 end
end

-- Accepts STEAM_0:1:123, [U:1:123], 7656119..., or a steamcommunity /profiles/ link.
function P.ToSID64(input)
	if not input then return nil end
	input = P.Trim(input)
	local prof = input:match("steamcommunity%.com/profiles/(%d+)")
	if prof then input = prof end
	if input:match("^7656119%d%d%d%d%d%d%d%d%d%d$") then return input end
	local x, y = input:upper():match("^STEAM_[0-5]:([01]):(%d+)$")
	if x then return steam32to64("STEAM_0:" .. x .. ":" .. y) end
	local acc = input:upper():match("^%[?U:1:(%d+)%]?$")
	if acc then
		local n = tonumber(acc)
		if not n then return nil end
		return steam32to64(string.format("STEAM_0:%d:%d", n % 2, math.floor(n / 2)))
	end
	return nil
end

function P.SID32(sid64)
	if not sid64 then return "" end
	local s = util.SteamIDFrom64(sid64)
	if s == "STEAM_0:0:0" then return sid64 end
	return s
end

function P.BySID(sid64)
	if not sid64 then return nil end
	for _, p in ipairs(player.GetHumans()) do
		if p:SteamID64() == sid64 then return p end
	end
end

function P.SIDOf(ply)
	if not IsValid(ply) then return "CONSOLE" end
	if ply:IsBot() then return "BOT_" .. ply:EntIndex() end
	return ply:SteamID64() or ("BOT_" .. ply:EntIndex())
end

function P.NameOf(ply)
	if not IsValid(ply) then return "Console" end
	return ply:Nick()
end

-- ------------------------------------------------------------------ time

local units = {
	s = 1 / 60, sec = 1 / 60,
	m = 1, min = 1, mi = 1,
	h = 60, hr = 60,
	d = 1440, day = 1440,
	w = 10080, wk = 10080,
	mo = 43200,
	y = 525600, yr = 525600,
}

-- "1d12h", "30", "2w", "perm" -> minutes (0 means permanent). Returns nil when invalid.
function P.ParseDuration(str)
	if str == nil then return nil end
	str = tostring(str):lower():gsub("%s", "")
	if str == "" then return nil end
	if str == "0" or str == "perm" or str == "permanent" or str == "perma" or str == "p" or str == "forever" then return 0 end
	if str:match("^%d+%.?%d*$") then return math.max(0, math.floor(tonumber(str))) end
	local total, any = 0, false
	for num, unit in str:gmatch("(%d+%.?%d*)(%a+)") do
		local mul = units[unit]
		if not mul then return nil end
		total = total + tonumber(num) * mul
		any = true
	end
	if not any then return nil end
	if str:gsub("%d+%.?%d*%a+", "") ~= "" then return nil end
	return math.max(1, math.floor(total + 0.5))
end

-- minutes -> "2d 3h" (short) ; 0 -> permanent word
function P.FormatDuration(min, permWord)
	min = math.floor(tonumber(min) or 0)
	if min <= 0 then return permWord or "permanent" end
	local parts = {}
	local y = math.floor(min / 525600) min = min % 525600
	local w = math.floor(min / 10080) min = min % 10080
	local d = math.floor(min / 1440) min = min % 1440
	local h = math.floor(min / 60) min = min % 60
	if y > 0 then parts[#parts + 1] = y .. "y" end
	if w > 0 then parts[#parts + 1] = w .. "w" end
	if d > 0 then parts[#parts + 1] = d .. "d" end
	if h > 0 then parts[#parts + 1] = h .. "h" end
	if min > 0 and #parts < 2 then parts[#parts + 1] = min .. "m" end
	return table.concat(parts, " ", 1, math.min(#parts, 2))
end

-- seconds of play time -> "12h 30m"
function P.FormatHours(sec)
	sec = math.floor(tonumber(sec) or 0)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	if h >= 1 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

function P.Date(ts)
	if not ts or ts <= 0 then return "-" end
	return os.date("%d/%m/%Y %H:%M", ts)
end

-- ------------------------------------------------------------------ colours

function P.ReadColor(t, fallback)
	if not istable(t) then return fallback end
	local r, g, b = tonumber(t.r or t[1]), tonumber(t.g or t[2]), tonumber(t.b or t[3])
	if not (r and g and b) then return fallback end
	return Color(math.Clamp(math.floor(r), 0, 255), math.Clamp(math.floor(g), 0, 255), math.Clamp(math.floor(b), 0, 255))
end

function P.ColorTable(c)
	return { r = c.r, g = c.g, b = c.b }
end

P.Effects = { "none", "shine", "flow", "wave", "pulse", "rainbow" }
local fxOk = {}
for _, v in ipairs(P.Effects) do fxOk[v] = true end

-- A "style" describes how a tag is painted: text + first colour + optional
-- second colour (gradient) + an animated effect.
function P.CleanStyle(t, maxLen)
	if not istable(t) then return nil end
	local text = P.Trim(P.Str(t.text, maxLen or 24))
	if text == "" then return nil end
	local c1 = P.ReadColor(t.c1, Color(237, 228, 211))
	local c2 = t.c2 and P.ReadColor(t.c2, nil) or nil
	local fx = fxOk[t.fx] and t.fx or "none"
	local out = { text = text, c1 = P.ColorTable(c1), fx = fx }
	if c2 then out.c2 = P.ColorTable(c2) end
	if t.icon and isstring(t.icon) and t.icon:match("^[%w_]+$") and #t.icon <= 24 then out.icon = t.icon end
	return out
end

-- ------------------------------------------------------------------ players

function P.IsDarkRP()
	return DarkRP ~= nil and RPExtraTeams ~= nil
end

function P.JobOf(ply)
	if not IsValid(ply) then return nil end
	if P.IsDarkRP() and RPExtraTeams[ply:Team()] then return RPExtraTeams[ply:Team()] end
end

function P.JobByCommand(cmd)
	if not P.IsDarkRP() or not cmd then return nil end
	cmd = tostring(cmd):lower()
	for i, j in pairs(RPExtraTeams) do
		if (j.command and j.command:lower() == cmd) then return j, i end
	end
	for i, j in pairs(RPExtraTeams) do
		if j.name and j.name:lower() == cmd then return j, i end
	end
	for i, j in pairs(RPExtraTeams) do
		if j.name and j.name:lower():find(cmd, 1, true) then return j, i end
	end
end

function P.PlayTime(ply)
	if not IsValid(ply) then return 0 end
	local base = ply:GetNW2Int("pr_time", 0)
	local since = ply:GetNW2Float("pr_join", 0)
	if since <= 0 then return base end
	return base + math.max(0, CurTime() - since)
end

function P.IsAFK(ply) return IsValid(ply) and ply:GetNW2Bool("pr_afk", false) end
-- seconds without moving (0 when not AFK)
function P.AFKTime(ply)
	if not P.IsAFK(ply) then return 0 end
	return math.max(0, CurTime() - ply:GetNW2Float("pr_afk_since", CurTime()))
end
-- "AFK 5m"
function P.AFKLabel(ply)
	local t = math.floor(P.AFKTime(ply))
	if t < 60 then return "AFK" end
	if t < 3600 then return "AFK " .. math.floor(t / 60) .. "m" end
	return "AFK " .. math.floor(t / 3600) .. "h"
end
function P.OnDuty(ply) return IsValid(ply) and ply:GetNW2Bool("pr_duty", false) end

-- ------------------------------------------------------------------ net

if SERVER then
	util.AddNetworkString("praetor_rq")
	util.AddNetworkString("praetor_rs")
end

function P.Pack(tbl)
	local json = util.TableToJSON(tbl or {}) or "{}"
	return util.Compress(json) or ""
end

function P.Unpack(data, maxSize)
	if not data or #data == 0 then return {} end
	local raw = util.Decompress(data, maxSize or 1048576)
	if not raw then return nil end
	return util.JSONToTable(raw)
end
