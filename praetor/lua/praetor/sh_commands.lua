-- Praetor: command registry and argument types.
--
-- Creating a command from another addon:
--
--   Praetor.AddCommand({
--       id = "heal", cat = "player", def = "admin",
--       args = { { type = "player" }, { type = "number", min = 1, max = 1000, default = 100, optional = true } },
--       run = function(caller, targets, amount)
--           for _, t in ipairs(targets) do t:SetHealth(amount) end
--           Praetor.Echo(caller, "e_hp", { T = targets, V = amount })
--       end,
--   })
--
-- `run` only matters on the server; define the command in a shared file so the
-- menu and the autocomplete know about it.
local P = Praetor

P.Commands = P.Commands or {}
P.Aliases = P.Aliases or {}
P.Categories = { "moderation", "teleport", "player", "fun", "chat", "users", "server", "darkrp", "custom", "addons" }

-- One pixel icon per built-in command (materials/praetor/icons). The "_ok",
-- "_no", "_plus", "_minus", "_id" and "_snow" versions carry a small seal in the
-- corner, so "unban" is the gavel with a green tick. Other addons can pass
-- `icon = "name"` to Praetor.AddCommand.
P.CmdIcons = {
	kick = "door", ban = "hammer", banid = "hammer_id", unban = "hammer_ok", warn = "warn",
	mute = "bubble_no", unmute = "bubble_ok", gag = "mic_no", ungag = "mic_ok", jail = "jail", unjail = "jail_ok",
	freeze = "snow", unfreeze = "snow_ok", slay = "skull", strip = "gun_no", clearprops = "box_no", spectate = "eye",
	["goto"] = "pin", bring = "magnet", ["return"] = "undo", tp = "portal", send = "jump",
	hp = "heart", armor = "vest", god = "halo", ungod = "halo_no", cloak = "ghost", uncloak = "ghost_no",
	noclip = "feather", respawn = "heart_plus", give = "gun", model = "user", speed = "speed", scale = "scale",
	slap = "hand", launch = "rocket", ignite = "flame", extinguish = "drop", blind = "eye_no", unblind = "eye_ok",
	map = "map", restart = "reload", restartin = "clock", cancelrestart = "stop", cleanup = "broom", freezeprops = "box_snow", stopsound = "music_no",
	rcon = "terminal", announce = "megaphone", tsay = "bubble", pm = "envelope", asay = "headset",
	clearchat = "eraser", vote = "ballot", mapvote = "map", stopvote = "stop",
	screengrab = "image",
	votekick = "ballot", voteban = "ballot", votemute = "ballot", voteclearprops = "ballot", votecleanup = "broom", votefreeze = "snow",
	sit = "headset", endsit = "undo", setsit = "pin",
	setrank = "crown", setrankid = "crown_id", removerank = "crown_minus", settitle = "title", cleartitle = "title_no",
	settag = "tag", cleartag = "tag_no", duty = "helm", who = "players", playtime = "clock", warns = "clipboard",
	sheet = "scroll",
	setjob = "brief", jobban = "brief_no", unjobban = "brief_ok", whitelist = "brief_plus", unwhitelist = "brief_minus",
	rpdemote = "chevdown", setmoney = "coin", addmoney = "coin_plus", rpname = "pen", arrest = "cuffs",
	unarrest = "cuffs_ok", wanted = "target", unwanted = "target_no", license = "license", unlicense = "license_no",
}

-- fallback by category (commands from other addons without an icon)
P.CatIcons = {
	moderation = "hammer", teleport = "portal", player = "user", fun = "rocket", chat = "bubble",
	users = "crown", server = "gear", darkrp = "brief", custom = "wrench", addons = "box",
}

function P.CmdIcon(id)
	if not id then return "bolt" end
	local c = (CLIENT and P.ServerCmds and P.ServerCmds[id]) or P.Commands[id]
	local own = c and (c.ic or c.icon)
	if isstring(own) and own ~= "" then return own end
	return P.CmdIcons[id] or (c and P.CatIcons[c.cat or ""]) or "bolt"
end

function P.AddCommand(def)
	assert(istable(def) and isstring(def.id), "Praetor.AddCommand needs a table with an id")
	def.id = def.id:lower()
	def.cat = def.cat or "addons"
	def.perm = def.perm or def.id
	def.args = def.args or {}
	P.RegisterPerm(def.perm, def.cat, def.def or "superadmin")
	P.Commands[def.id] = def
	for _, a in ipairs(def.aliases or {}) do P.Aliases[a:lower()] = def.id end
	if SERVER and P.QueuePermSync then P.QueuePermSync() end
	hook.Run("Praetor.CommandAdded", def)
	return def
end

function P.RemoveCommand(id)
	local def = P.Commands[id]
	if not def then return end
	P.Commands[id] = nil
	for a, target in pairs(P.Aliases) do
		if target == id then P.Aliases[a] = nil end
	end
	if SERVER and P.QueuePermSync then P.QueuePermSync() end
end

function P.FindCommand(name)
	if not name then return nil end
	name = name:lower()
	local id = P.Commands[name] and name or P.Aliases[name]
	return id and P.Commands[id] or nil
end

function P.CanRun(ply, def)
	if not def then return false end
	if def.owner_only and IsValid(ply) and not P.IsOwner(ply) then return false end
	return P.Has(ply, def.perm)
end

-- ------------------------------------------------------------------ argument types

P.ArgTypes = P.ArgTypes or {}

local function addType(name, t) P.ArgTypes[name] = t end
P.AddArgType = addType

-- "João [VIP]" -> "joaovip": no accents, symbols or spaces, so "joao" finds "João"
local FOLD = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
	["é"] = "e", ["ê"] = "e", ["è"] = "e", ["ë"] = "e", ["É"] = "e", ["Ê"] = "e", ["È"] = "e",
	["í"] = "i", ["î"] = "i", ["ì"] = "i", ["ï"] = "i", ["Í"] = "i", ["Î"] = "i",
	["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ò"] = "o", ["ö"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
	["ú"] = "u", ["ü"] = "u", ["ù"] = "u", ["û"] = "u", ["Ú"] = "u", ["Ü"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}
local function fold(s)
	s = tostring(s or ""):gsub("[\192-\223][\128-\191]", FOLD):lower()
	return (s:gsub("[^%w]", ""))
end
P.FoldName = fold

if SERVER then

	-- Half a name is enough: exact name, then names that start with it, then
	-- names that contain it. Returns the players and, when the best match is
	-- still more than one player, true (ambiguous).
	local function matchName(str)
		local low, f = str:lower(), fold(str)
		local tiers = { {}, {}, {}, {} }
		for _, p in ipairs(player.GetAll()) do
			local n = p:Nick()
			local fn = fold(n)
			if n:lower() == low then table.insert(tiers[1], p)
			elseif f ~= "" and fn == f then table.insert(tiers[2], p)
			elseif f ~= "" and fn:sub(1, #f) == f then table.insert(tiers[3], p)
			elseif (f ~= "" and fn:find(f, 1, true)) or n:lower():find(low, 1, true) then table.insert(tiers[4], p) end
		end
		for i, t in ipairs(tiers) do
			if #t > 0 then return t, #t > 1 and i > 1 end
		end
		return {}, false
	end

	local MASS = { ["*"] = true, all = true, everyone = true, ["@all"] = true, todos = true }

	-- true when the selector can hit many players at once (needs "target_all")
	function P.IsMassSelector(str)
		str = tostring(str or ""):lower()
		for part in str:gmatch("[^,]+") do
			part = P.Trim(part)
			if MASS[part] or part:sub(1, 1) == "#" or (part:sub(1, 1) == "!" and #part > 1) then return true end
		end
		return false
	end

	local function resolveOne(caller, str)
		local neg = false
		local amb
		if #str > 1 and str:sub(1, 1) == "!" then neg = true str = str:sub(2) end
		local found
		local low = str:lower()
		if str == "^" or low == "me" or low == "eu" then
			found = IsValid(caller) and { caller } or {}
		elseif MASS[low] then
			found = player.GetAll()
		elseif str == "@" then
			local tr = IsValid(caller) and caller:GetEyeTrace()
			local e = tr and tr.Entity
			found = (IsValid(e) and e:IsPlayer()) and { e } or {}
		elseif str:sub(1, 1) == "#" and #str > 1 then
			local rank = low:sub(2)
			found = {}
			for _, p in ipairs(player.GetAll()) do
				if p:GetUserGroup():lower() == rank then found[#found + 1] = p end
			end
		elseif str:sub(1, 1) == "$" and tonumber(str:sub(2)) then
			local p = Player(tonumber(str:sub(2)))
			found = IsValid(p) and { p } or {}
		else
			local sid = P.ToSID64(str)
			if sid then
				local p = P.BySID(sid)
				found = IsValid(p) and { p } or {}
			else
				found, amb = matchName(str)
			end
		end
		if not neg then return found, amb end
		local skip, out = {}, {}
		for _, p in ipairs(found) do skip[p] = true end
		for _, p in ipairs(player.GetAll()) do
			if not skip[p] then out[#out + 1] = p end
		end
		return out
	end

	-- Resolves "bob", "bob,alice", "*", "#vip", "!bob", "@", "^", SteamIDs...
	-- into a list of players (without permission checks). The second value is
	-- the part of a name that matched more than one player ("jo": João, Jonas).
	function P.ResolveTargets(caller, str)
		if not str or str == "" then return {} end
		local seen, out, ambPart = {}, {}, nil
		for part in tostring(str):gmatch("[^,]+") do
			part = P.Trim(part)
			if part ~= "" then
				local found, amb = resolveOne(caller, part)
				if amb and not ambPart then ambPart = { part = part, list = found } end
				for _, p in ipairs(found) do
					if not seen[p] then seen[p] = true out[#out + 1] = p end
				end
			end
		end
		return out, ambPart
	end

	-- "jo" matched João and Jonas: say who, so the caller types a bit more
	local function ambiguous(amb)
		local names = {}
		for i, p in ipairs(amb.list) do
			if i > 5 then names[#names + 1] = "..." break end
			names[#names + 1] = p:Nick()
		end
		return nil, "err_target_which", { S = amb.part, V = table.concat(names, ", ") }
	end

	addType("player", {
		parse = function(caller, str, arg)
			if not arg.single and P.IsMassSelector(str) and not P.Has(caller, "target_all") then
				return nil, "err_target_all"
			end
			local list, amb = P.ResolveTargets(caller, str)
			if amb then return ambiguous(amb) end
			if #list == 0 then return nil, "err_no_target", { S = str } end
			local ok = {}
			for _, p in ipairs(list) do
				if arg.notself and p == caller then
					-- skip silently, reported below if nothing is left
				elseif arg.higher or P.CanTarget(caller, p) then
					ok[#ok + 1] = p
				end
			end
			if #ok == 0 then
				if #list == 1 and list[1] == caller then return nil, "err_self" end
				if #list == 1 then return nil, "err_authority", { S = list[1]:Nick() } end
				return nil, "err_no_target", { S = str }
			end
			if arg.single and #ok > 1 then return nil, "err_many_targets", { S = str } end
			return ok
		end,
	})

	-- Online or offline player (SteamID). Returns { sid, name, ply }.
	addType("offline", {
		parse = function(caller, str, arg)
			local sid = P.ToSID64(str)
			if sid then
				local ply = P.BySID(sid)
				if IsValid(ply) and not arg.higher and not P.CanTarget(caller, ply) then
					return nil, "err_authority", { S = ply:Nick() }
				end
				if not IsValid(ply) and P.CanTargetSID and not arg.higher and not P.CanTargetSID(caller, sid) then
					return nil, "err_authority", { S = P.SID32(sid) }
				end
				return { sid = sid, ply = ply, name = IsValid(ply) and ply:Nick() or (P.KnownName and P.KnownName(sid)) or P.SID32(sid) }
			end
			local list, amb = P.ResolveTargets(caller, str)
			if amb then return ambiguous(amb) end
			if #list == 0 then return nil, "err_no_target", { S = str } end
			if #list > 1 then return nil, "err_many_targets", { S = str } end
			local ply = list[1]
			if not arg.higher and not P.CanTarget(caller, ply) then return nil, "err_authority", { S = ply:Nick() } end
			if ply:IsBot() then return nil, "err_bot" end
			return { sid = ply:SteamID64(), ply = ply, name = ply:Nick() }
		end,
	})

	addType("number", {
		parse = function(_, str, arg)
			local n = tonumber(str)
			if not n then return nil, "err_number", { S = str } end
			if arg.round ~= false then n = math.Round(n) end
			if arg.min then n = math.max(arg.min, n) end
			if arg.max then n = math.min(arg.max, n) end
			return n
		end,
	})

	addType("duration", {
		parse = function(_, str)
			local m = P.ParseDuration(str)
			if not m then return nil, "err_duration", { S = str } end
			return m
		end,
	})

	addType("text", {
		parse = function(_, str, arg)
			str = P.Str(str, arg.max or 250)
			if str == "" and not arg.optional then return nil, "err_missing", { S = arg.hint or "text" } end
			return str
		end,
	})

	addType("rank", {
		parse = function(_, str)
			local low = str:lower()
			if P.Ranks[low] then return low end
			for name, r in pairs(P.Ranks) do
				if (r.display or ""):lower() == low then return name end
			end
			return nil, "err_rank", { S = str }
		end,
	})

	addType("job", {
		parse = function(_, str)
			if not P.IsDarkRP() then return nil, "err_no_darkrp" end
			local job = P.JobByCommand(str)
			if not job then return nil, "err_job", { S = str } end
			return job.command
		end,
	})

	addType("choice", {
		parse = function(_, str, arg)
			local low = str:lower()
			for _, o in ipairs(arg.options or {}) do
				if o:lower() == low then return o end
			end
			return nil, "err_choice", { S = str, V = table.concat(arg.options or {}, ", ") }
		end,
	})

	addType("map", {
		parse = function(_, str)
			str = str:lower():gsub("%.bsp$", "")
			if not str:match("^[%w_%-%.]+$") or not file.Exists("maps/" .. str .. ".bsp", "GAME") then
				return nil, "err_map", { S = str }
			end
			return str
		end,
	})

	addType("bool", {
		parse = function(_, str)
			local low = str:lower()
			if low == "1" or low == "true" or low == "on" or low == "yes" or low == "sim" then return true end
			if low == "0" or low == "false" or low == "off" or low == "no" or low == "nao" or low == "não" then return false end
			return nil, "err_bool", { S = str }
		end,
	})

	addType("class", {
		parse = function(_, str)
			if not str:match("^[%w_%-%.]+$") or #str > 64 then return nil, "err_class", { S = str } end
			return str:lower()
		end,
	})

	addType("model", {
		parse = function(_, str)
			str = str:lower():gsub("\\", "/")
			if not str:match("^[%w_%-%./]+%.mdl$") or str:find("..", 1, true) then return nil, "err_model", { S = str } end
			return str
		end,
	})

	-- argv: list of strings typed by the caller. Returns the values or nil + error.
	-- A player argument left out is you (except where it makes no sense, like
	-- kicking or banning yourself: those say what is missing). "!jail 5m" also
	-- means you: the first word is not a player but fits the next argument.
	-- (an offline player / SteamID argument only when the command asks for it:
	-- !settitle, !settag... but never !jobban or !removerank on yourself by mistake)
	local function selfDefault(caller, arg)
		if not IsValid(caller) or arg.notself or arg.noself then return false end
		if arg.type == "player" then return arg.self_default ~= false end
		return arg.type == "offline" and arg.self_default == true
	end
	local function selfValue(caller, arg)
		if arg.type == "offline" then return { sid = caller:SteamID64(), ply = caller, name = caller:Nick() } end
		return { caller }
	end
	function P.ParseArgs(caller, def, argv)
		local out = {}
		local n = #def.args
		local k = 1 -- the next typed word
		for i, arg in ipairs(def.args) do
			local raw = argv[k]
			local rest = arg.type == "text" and i == n and arg.rest ~= false and #argv > k
			if rest then raw = table.concat(argv, " ", k) end
			if raw == nil or raw == "" then
				if selfDefault(caller, arg) then
					out[i] = selfValue(caller, arg)
				elseif arg.optional then
					if istable(arg.default) then out[i] = table.Copy(arg.default) else out[i] = arg.default end
				else
					return nil, "err_missing_arg", { S = "@arg_" .. P.ArgHint(arg), V = i, U = def.id }
				end
			else
				local t = P.ArgTypes[arg.type]
				if not t then return nil, "err_internal" end
				local v, err, eargs = t.parse(caller, raw, arg)
				local shifted = false
				if v == nil and err == "err_no_target" and selfDefault(caller, arg) then
					local nxt = def.args[i + 1]
					local nt = nxt and P.ArgTypes[nxt.type]
					-- a text next (a title, a name) only where the command asked for it
					local okType = nxt and nxt.type ~= "player" and nxt.type ~= "offline" and (nxt.type ~= "text" or arg.self_default == true)
					if nt and okType and nt.parse(caller, raw, nxt) ~= nil then
						out[i] = selfValue(caller, arg)
						shifted = true
					end
				end
				if not shifted then
					if v == nil then
						eargs = istable(eargs) and eargs or {}
						eargs.U = def.id
						return nil, err, eargs
					end
					out[i] = v
					k = rest and #argv + 1 or k + 1
				end
			end
		end
		return out
	end
end

function P.ArgHint(arg)
	return arg.hint or arg.type
end

-- "kick <player> [reason]" for help texts
function P.Usage(def)
	local parts = { def.id }
	for _, a in ipairs(def.args) do
		local h = P.ArgHint(a)
		parts[#parts + 1] = a.optional and ("[" .. h .. "]") or ("<" .. h .. ">")
	end
	return table.concat(parts, " ")
end
