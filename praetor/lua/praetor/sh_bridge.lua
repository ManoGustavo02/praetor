-- Praetor: compatibility bridge for addons written for ULX/ULib or SAM.
--
-- When ULX or SAM is NOT installed, this file creates the functions other addons
-- usually call on them (ULib.ucl.query, ulx.command, sam.command.new,
-- sam.permissions.add, ply:query, ply:HasPermission...) and answers them with
-- Praetor's ranks. When the real ULX/SAM is installed nothing here is created.
local P = Praetor

P.Bridge = P.Bridge or {}
P.Bridge.hasULX = file.Exists("autorun/ulib_init.lua", "LUA") or ULib ~= nil
P.Bridge.hasSAM = file.Exists("autorun/sam.lua", "LUA") or sam ~= nil

local PLAYER = FindMetaTable("Player")

-- Tables for the fake ULib/ulx/sam. Unknown keys return nil, like the real
-- libraries: other addons test things such as "if ULib.ucl then" or
-- "sam.permissions and sam.permissions.add", and a catch-all function here would
-- make those checks pass with the wrong type (that broke Blackbox, Doodle Arsenal,
-- Spawn Sanctuary and Truco Night in 1.0.0). Only HOOK_* names get a default.
local function softTable(name, t)
	return setmetatable(t or {}, {
		__index = function(_, k)
			if isstring(k) and k:match("^HOOK_") then return name .. k end
		end,
	})
end

-- Builder objects (sam.command.new_argument():...:End()) accept any chained call.
local function chainTable()
	local obj = {}
	return setmetatable(obj, { __index = function() return function() return obj end end })
end

local function rankAccessName(access)
	if access == nil then return "user" end
	if istable(access) then access = access[1] end
	access = tostring(access or "user")
	if access == "operator" then return P.Ranks.moderator and "moderator" or "admin" end
	return access
end

local function sid32(ply) return IsValid(ply) and ply:SteamID() or "CONSOLE" end

-- ==================================================================== ULib / ULX
if not P.Bridge.hasULX then
	ULib = softTable("ULib", ULib)
	ULib.ACCESS_ALL = "user"
	ULib.ACCESS_OPERATOR = "operator"
	ULib.ACCESS_ADMIN = "admin"
	ULib.ACCESS_SUPERADMIN = "superadmin"
	ULib.DEFAULT_ACCESS = "user"
	ULib.DEFAULT_GRANT_ACCESS = { allow = {}, deny = {}, guest = true }
	ULib.HOOK_USER_GROUP_CHANGE = "ULibUserGroupChange"
	ULib.HOOK_UCLCHANGED = "UCLChanged"
	ULib.HOOK_UCLAUTH = "UCLAuthed"
	ULib.HOOK_USER_BANNED = "ULibPlayerBanned"
	ULib.HOOK_USER_UNBANNED = "ULibPlayerUnBanned"
	ULib.HOOK_USER_KICKED = "ULibPlayerKicked"
	ULib.HOOK_COMMAND_CALLED = "ULibCommandCalled"
	ULib.HOOK_POST_TRANSLATED_COMMAND = "ULibPostTranslatedCommand"
	ULib.Praetor = true

	-- Chat commands of ULib (DarkRP's FSpectate and others call these when ULib exists).
	ULib.sayCmds = ULib.sayCmds or {}
	function ULib.addSayCommand(cmd, fn, _, hide)
		if not isstring(cmd) or not isfunction(fn) then return end
		ULib.sayCmds[cmd:lower()] = { fn = fn, hide = hide, __cmd = cmd }
	end
	function ULib.removeSayCommand(cmd)
		if isstring(cmd) then ULib.sayCmds[cmd:lower()] = nil end
	end
	if SERVER then
		hook.Add("PlayerSay", "Praetor.ULibSayCmds", function(ply, text)
			if not next(ULib.sayCmds) then return end
			local first, rest = text:match("^(%S+)%s*(.*)$")
			local c = first and ULib.sayCmds[first:lower()]
			if not c then return end
			local argv = string.Explode("%s+", rest or "", true)
			if argv[1] == "" then argv = {} end
			local ok, err = pcall(c.fn, ply, c.__cmd, argv, rest or "")
			if not ok then ErrorNoHalt("[Praetor] ULib say command " .. c.__cmd .. ": " .. tostring(err) .. "\n") end
			if c.hide then return "" end
		end)
	end

	local ucl = softTable("ULib.ucl", ULib.ucl)
	ULib.ucl = ucl

	-- ULib.ucl.groups / users / authed are plain tables rebuilt whenever ranks change
	-- (LuaJIT has no __pairs, so addons that loop over them need real tables).
	ucl.groups = ucl.groups or {}
	ucl.users = ucl.users or {}
	ucl.authed = ucl.authed or {}

	function P.Bridge.RefreshULib()
		for k in pairs(ucl.groups) do ucl.groups[k] = nil end
		for name, r in pairs(P.Ranks) do
			local allow = {}
			for perm, v in pairs(r.perms or {}) do if v then allow[#allow + 1] = perm end end
			ucl.groups[name] = { allow = allow, inherit_from = r.inherit, can_target = nil }
		end
		for k in pairs(ucl.users) do ucl.users[k] = nil end
		for k in pairs(ucl.authed) do ucl.authed[k] = nil end
		for _, p in ipairs(player.GetHumans()) do
			local info = { group = p:GetUserGroup(), name = p:Nick(), allow = {}, deny = {} }
			ucl.users[p:SteamID()] = info
			ucl.authed[p:UniqueID()] = info
		end
	end
	hook.Add("Praetor.RanksUpdated", "Praetor.ULib", P.Bridge.RefreshULib)
	hook.Add("Praetor.RankChanged", "Praetor.ULib", function() timer.Simple(0, P.Bridge.RefreshULib) end)
	hook.Add("PlayerInitialSpawn", "Praetor.ULib", function() timer.Simple(1, P.Bridge.RefreshULib) end)
	hook.Add("PlayerDisconnected", "Praetor.ULib", function() timer.Simple(0, P.Bridge.RefreshULib) end)

	function ucl.query(ply, access, hide)
		if not IsValid(ply) then return true end
		if access == nil then return true end
		access = tostring(access):lower()
		if not P.Perms[access] then
			P.RegisterPerm(access, "addons", "superadmin", true)
		end
		return P.Has(ply, access)
	end

	function ucl.registerAccess(access, groups, comment, category)
		if not isstring(access) then return end
		access = access:lower()
		local min = rankAccessName(groups)
		P.RegisterPerm(access, "addons", min, true)
		if SERVER and P.QueuePermSync then P.QueuePermSync() end
	end

	function ucl.groupInheritsFrom(group)
		local r = P.Ranks[group]
		return r and r.inherit or nil
	end

	function ucl.getInheritanceTree()
		local tree = {}
		for name, r in pairs(P.Ranks) do
			if not r.inherit then tree[name] = {} end
		end
		return tree
	end

	function ucl.getGroupCanTarget() return nil end

	function ucl.getUserRegisteredID(ply) return IsValid(ply) and ply:SteamID() or nil end

	function ucl.getUserInfoFromID(id)
		return ucl.users[id]
	end

	if SERVER then
		-- addUser("STEAM_0:1:23", allows, denies, "admin")
		function ucl.addUser(id, allows, denies, group)
			local sid = P.ToSID64(id)
			if not sid or not group then return end
			if P.SetRankSID then P.SetRankSID(nil, sid, group, 0, "ULib bridge") end
		end

		function ucl.removeUser(id)
			local sid = P.ToSID64(id)
			if sid and P.SetRankSID then P.SetRankSID(nil, sid, "user", 0, "ULib bridge") end
		end

		function ucl.groupAllow(name, access, revoke)
			if not P.Ranks[name] or not P.SetRankPerm then return end
			if istable(access) then
				for _, a in ipairs(access) do P.SetRankPerm(name, tostring(a):lower(), not revoke) end
			else
				P.SetRankPerm(name, tostring(access):lower(), not revoke)
			end
		end

		function ucl.userAllow() end
		function ucl.probe() end
		function ucl.saveUsers() end
		function ucl.saveGroups() end
	end

	function ULib.getUniqueIDForPlayer(ply) return IsValid(ply) and ply:SteamID() or nil end

	function ULib.getUsers(target, enableKeywords, ply)
		if SERVER and P.ResolveTargets then
			local list = P.ResolveTargets(ply, target)
			if #list == 0 then return false, "No target found" end
			return list
		end
		local out = {}
		for _, p in ipairs(player.GetAll()) do
			if p:Nick():lower():find(tostring(target):lower(), 1, true) then out[#out + 1] = p end
		end
		if #out == 0 then return false, "No target found" end
		return out
	end

	function ULib.getUser(target, enableKeywords, ply)
		local list, err = ULib.getUsers(target, enableKeywords, ply)
		if not list then return false, err end
		if #list > 1 then return false, "Found multiple targets" end
		return list[1]
	end

	if SERVER then
		local function say(ply, ...)
			if P.ChatTo then P.ChatTo(ply, ...) end
		end

		function ULib.tsay(ply, msg) say(ply, P.Col.ivory, tostring(msg)) end
		function ULib.tsayError(ply, msg) say(ply, P.Col.crimson, tostring(msg)) end
		function ULib.tsayColor(ply, wait, ...) say(ply, ...) end
		function ULib.csay(ply, msg) if P.Announce then P.Announce(ply, tostring(msg)) end end

		function ULib.kick(ply, reason, caller)
			if not IsValid(ply) then return end
			hook.Call(ULib.HOOK_USER_KICKED, nil, ply:SteamID(), reason, caller)
			ply:Kick(reason or "Kicked")
		end

		function ULib.ban(ply, time, reason, admin)
			if not IsValid(ply) or not P.AddBan then return end
			P.AddBan(ply:SteamID64(), ply:Nick(), tonumber(time) or 0, reason or "", admin)
		end

		function ULib.kickban(ply, time, reason, admin) ULib.ban(ply, time, reason, admin) end

		function ULib.addBan(steamid, time, reason, name, admin)
			local sid = P.ToSID64(steamid)
			if not sid or not P.AddBan then return end
			P.AddBan(sid, name or "", tonumber(time) or 0, reason or "", admin)
		end

		function ULib.unban(steamid, admin)
			local sid = P.ToSID64(steamid)
			if sid and P.LiftBan then P.LiftBan(sid, admin) end
		end

		ULib.bans = setmetatable({}, {
			__index = function(_, id)
				local sid = P.ToSID64(id)
				local b = sid and P.BanCache and P.BanCache[sid]
				if not b then return nil end
				return { reason = b.reason, admin = b.admin, unban = b.expires, time = b.created, name = b.name }
			end,
		})
	end

	-- ULib.cmds argument types used by ulx.command():addParam{ type = ... }
	ULib.cmds = softTable("ULib.cmds", ULib.cmds)
	ULib.cmds.PlayersArg = { praetor = "players" }
	ULib.cmds.PlayerArg = { praetor = "player" }
	ULib.cmds.NumArg = { praetor = "number" }
	ULib.cmds.StringArg = { praetor = "text" }
	ULib.cmds.BoolArg = { praetor = "bool" }
	ULib.cmds.CallingPlayerArg = { praetor = "caller" }
	ULib.cmds.optional = "optional"
	ULib.cmds.round = "round"
	ULib.cmds.takeRestOfLine = "takeRestOfLine"
	ULib.cmds.ignoreCanTarget = "ignoreCanTarget"
	ULib.cmds.allowTimeString = "allowTimeString"

	ulx = softTable("ulx", ulx)
	ulx.Praetor = true

	local function hasFlag(t, flag)
		for _, v in ipairs(t) do if v == flag then return true end end
		return false
	end

	-- ulx.command("Fun", "ulx slap", ulx.slap, "!slap") -> object with addParam/defaultAccess/help
	function ulx.command(category, command, fn, sayCmd)
		local name = tostring(command):gsub("^ulx%s+", ""):lower():gsub("%s+", "_")
		local id = name
		if P.Commands[id] and not P.Commands[id].ulx then id = "x_" .. id end

		local params = {}
		local def = {
			id = id, cat = "addons", def = "superadmin", perm = tostring(command):lower(), args = {}, ulx = true,
			aliases = {},
		}
		if isstring(sayCmd) then
			local s = sayCmd:gsub("^[!/]", ""):lower()
			if s ~= id and not P.Commands[s] then def.aliases[1] = s end
		end

		def.run = function(caller, ...)
			local vals, out, vi = { ... }, {}, 1
			for _, prm in ipairs(params) do
				if prm.kind == "caller" then
					out[#out + 1] = caller
				else
					local v = vals[vi]
					vi = vi + 1
					if prm.kind == "player" and istable(v) then v = v[1] end
					out[#out + 1] = v
				end
			end
			if fn then fn(caller, unpack(out, 1, #params)) end
		end

		local obj = {}
		function obj:addParam(t)
			local kind = t.type and t.type.praetor or "text"
			params[#params + 1] = { kind = kind }
			if kind == "caller" then return self end
			local arg = { hint = t.hint, optional = hasFlag(t, "optional") or t.default ~= nil, default = t.default }
			if kind == "players" then arg.type = "player"
			elseif kind == "player" then arg.type = "player" arg.single = true
			elseif kind == "number" then
				arg.type = hasFlag(t, "allowTimeString") and "duration" or "number"
				arg.min, arg.max = t.min, t.max
			elseif kind == "bool" then arg.type = "bool"
			else
				arg.type = "text"
				if t.completes and #t.completes > 0 and not hasFlag(t, "takeRestOfLine") then
					arg.rest = false
				end
			end
			if hasFlag(t, "ignoreCanTarget") then arg.higher = true end
			def.args[#def.args + 1] = arg
			return self
		end
		function obj:defaultAccess(access)
			def.def = rankAccessName(access)
			local perm = P.RegisterPerm(def.perm, "addons", def.def, true)
			if perm then perm.def = def.def end
			return self
		end
		function obj:help(str) def.helpText = tostring(str) return self end
		function obj:setOpposite(cmd2, args)
			local oid = tostring(cmd2):gsub("^ulx%s+", ""):lower():gsub("%s+", "_")
			if P.Commands[oid] then return self end
			P.AddCommand({
				id = oid, cat = "addons", perm = def.perm, def = def.def, args = def.args, ulx = true,
				run = function(caller, ...)
					local vals, out, vi = { ... }, {}, 1
					for i, prm in ipairs(params) do
						local fixed = args and args[i + 1]
						if prm.kind == "caller" then out[#out + 1] = caller
						elseif fixed ~= nil and fixed ~= ULib.cmds.PlayersArg and fixed ~= ULib.cmds.PlayerArg then
							out[#out + 1] = fixed
							vi = vi + 1
						else
							local v = vals[vi]
							vi = vi + 1
							if prm.kind == "player" and istable(v) then v = v[1] end
							out[#out + 1] = v
						end
					end
					if fn then fn(caller, unpack(out, 1, #params)) end
				end,
			})
			return self
		end
		function obj:getUsage() return P.Usage(def) end

		P.AddCommand(def)
		return obj
	end

	if SERVER then
		local function fancy(caller, fmt, ...)
			local args, ai = { ... }, 1
			fmt = tostring(fmt or "")
			local out = fmt:gsub("#(%a)", function(c)
				if c == "A" then return P.NameOf(caller) end
				local v = args[ai]
				ai = ai + 1
				if istable(v) and not IsValid(v) then
					local names = {}
					for _, p in ipairs(v) do if IsValid(p) then names[#names + 1] = p:Nick() end end
					return table.concat(names, ", ")
				end
				if IsValid(v) and v.Nick then return v:Nick() end
				return tostring(v)
			end)
			if P.EchoRaw then P.EchoRaw(caller, out) end
		end
		function ulx.fancyLogAdmin(caller, fmt, ...)
			if isbool(fmt) then fancy(caller, ...) return end -- (caller, hide_echo, format, ...)
			fancy(caller, fmt, ...)
		end
		function ulx.fancyLog(fmt, ...) fancy(nil, fmt, ...) end
		function ulx.logString(str) if P.Log then P.Log("addon", "l_raw", { V = tostring(str) }) end end
		function ulx.logUserAct(caller, target, action) ulx.logString(P.NameOf(caller) .. ": " .. tostring(action)) end
		function ulx.logServAct(caller, action) ulx.logString(P.NameOf(caller) .. ": " .. tostring(action)) end
		function ulx.getExclusive() return nil end
		function ulx.setExclusive() end
		function ulx.clearExclusive() end
		function ulx.addKickReason() end
	end

	function ulx.getVersion() return "Praetor " .. P.Version, P.Version, false end

	function PLAYER:query(access, hide) return ULib.ucl.query(self, access, hide) end
	function PLAYER:CheckGroup(group) return P.Inherits(self:GetUserGroup(), group) end
end

-- ==================================================================== SAM
if not P.Bridge.hasSAM then
	sam = softTable("sam", sam)
	sam.Praetor = true
	sam.permissions = softTable("sam.permissions", sam.permissions)
	sam.command = softTable("sam.command", sam.command)
	sam.player = softTable("sam.player", sam.player)
	sam.ranks = softTable("sam.ranks", sam.ranks)
	sam.language = softTable("sam.language", sam.language)

	function sam.permissions.add(perm, category, rank)
		if not isstring(perm) then return end
		P.RegisterPerm(perm, "addons", rank or "superadmin", true)
		if SERVER and P.QueuePermSync then P.QueuePermSync() end
	end
	function sam.permissions.exists(perm) return P.Perms[perm] ~= nil end
	function sam.permissions.remove() end
	function sam.permissions.get() return P.Perms end

	function sam.ranks.get_ranks() return P.Ranks end
	function sam.ranks.get_rank(name) return P.Ranks[name] end
	function sam.ranks.is_rank(name) return P.Ranks[name] ~= nil end
	function sam.ranks.is_default_rank(name) return P.ProtectedRanks[name] == true end
	function sam.ranks.inherits_from(a, b) return P.Inherits(a, b) end
	function sam.ranks.has_permission(name, perm) return P.RankHas(name, perm) end
	function sam.ranks.get_immunity(name) local r = P.Ranks[name] return r and r.immunity or 0 end
	function sam.ranks.can_target(a, b) return sam.ranks.get_immunity(a) >= sam.ranks.get_immunity(b) end
	function sam.ranks.get_ban_limit(name) local r = P.Ranks[name] return r and r.ban_limit or 0 end
	function sam.ranks.get_limit(name, key)
		local r = P.Ranks[name]
		return r and r.limits and r.limits[key] or -1
	end
	if SERVER then
		function sam.ranks.give_permission(name, perm) if P.SetRankPerm then P.SetRankPerm(name, perm, true) end end
		function sam.ranks.take_permission(name, perm) if P.SetRankPerm then P.SetRankPerm(name, perm, false) end end
	end

	function sam.format_length(min) return P.FormatDuration(min) end
	function sam.is_command_silent() return false end
	function sam.player.find_by_name(name)
		local out = {}
		for _, p in ipairs(player.GetAll()) do
			if p:Nick():lower():find(tostring(name):lower(), 1, true) then out[#out + 1] = p end
		end
		return out
	end

	if SERVER then
		function sam.player.send_message(ply, msg, tbl)
			msg = tostring(msg or "")
			if tbl then
				msg = msg:gsub("{(%w+)}", function(k)
					local v = tbl[k]
					if istable(v) then
						local n = {}
						for _, p in ipairs(v) do if IsValid(p) then n[#n + 1] = p:Nick() end end
						return table.concat(n, ", ")
					end
					if IsValid(v) and v.Nick then return v:Nick() end
					return v ~= nil and tostring(v) or ""
				end)
			end
			if P.ChatTo then P.ChatTo(ply, P.Col.ivory, msg) end
		end
		function sam.player.ban(ply, length, reason, adminSid)
			if not IsValid(ply) or not P.AddBan then return end
			P.AddBan(ply:SteamID64(), ply:Nick(), tonumber(length) or 0, reason or "", P.BySID(P.ToSID64(adminSid or "") or ""))
		end
		function sam.player.ban_id(steamid, length, reason, adminSid)
			local sid = P.ToSID64(steamid)
			if sid and P.AddBan then P.AddBan(sid, "", tonumber(length) or 0, reason or "", P.BySID(P.ToSID64(adminSid or "") or "")) end
		end
		function sam.player.unban(steamid, admin)
			local sid = P.ToSID64(steamid)
			if sid and P.LiftBan then P.LiftBan(sid, admin) end
		end
		function sam.player.set_rank(ply, rank, length)
			if IsValid(ply) and P.SetRankSID then P.SetRankSID(nil, ply:SteamID64(), rank, tonumber(length) or 0, "SAM bridge") end
		end
		function sam.player.set_rank_id(steamid, rank, length)
			local sid = P.ToSID64(steamid)
			if sid and P.SetRankSID then P.SetRankSID(nil, sid, rank, tonumber(length) or 0, "SAM bridge") end
		end
		function sam.player.kick_id(steamid, reason)
			local p = P.BySID(P.ToSID64(steamid) or "")
			if IsValid(p) then p:Kick(reason or "Kicked") end
		end
		function sam.player.is_banned(steamid, cb)
			local sid = P.ToSID64(steamid)
			local b = sid and P.BanCache and P.BanCache[sid]
			if cb then cb(b ~= nil) end
			return b ~= nil
		end

		function PLAYER:sam_ban(length, reason, admin) sam.player.ban(self, length, reason, admin) end
		function PLAYER:sam_set_rank(rank, length) sam.player.set_rank(self, rank, length) end
		function PLAYER:sam_send_message(msg, tbl) sam.player.send_message(self, msg, tbl) end
	end

	function PLAYER:sam_get_nwvar(key, def)
		if key == "is_authed" then return true end
		return def
	end
	function PLAYER:sam_get_play_time() return P.PlayTime(self) end
	function PLAYER:sam_get_session_time() return CurTime() - self:GetNW2Float("pr_join", CurTime()) end
	function PLAYER:HasPermission(perm) return P.Has(self, perm) end
	function PLAYER:CanTarget(t) return P.CanTarget(self, t) end
	function PLAYER:CanTargetRank(rank) return P.CanManageRank(self, rank) end
	function PLAYER:GetBanLimit() return P.RankOf(self).ban_limit or 0 end
	if not PLAYER.CheckGroup then
		function PLAYER:CheckGroup(group) return P.Inherits(self:GetUserGroup(), group) end
	end

	-- sam.command.new("name"):SetPermission(...):AddArg(...):OnExecute(fn):End()
	local samArg = {
		player = "player", number = "number", text = "text", length = "duration",
		rank = "rank", steamid = "offline", map = "map", dropdown = "choice",
	}
	local category = "addons"
	function sam.command.set_category(cat) category = cat end
	function sam.command.get_commands() return P.Commands end
	function sam.command.get_command(name) return P.Commands[tostring(name):lower()] end
	function sam.command.remove_command(name) P.RemoveCommand(tostring(name):lower()) end
	function sam.command.new_argument() return chainTable() end

	function sam.command.new(name)
		local id = tostring(name):lower()
		if P.Commands[id] and not P.Commands[id].sam then id = "s_" .. id end
		local def = { id = id, cat = "addons", perm = id, def = "superadmin", args = {}, aliases = {}, sam = true, samCat = category }
		local fn
		local obj = {}
		function obj:Aliases(...) for _, a in ipairs({ ... }) do def.aliases[#def.aliases + 1] = tostring(a):lower() end return self end
		function obj:AddArg(kind, data)
			data = data or {}
			local arg = {
				type = samArg[kind] or "text", optional = data.optional, default = data.default, hint = data.hint,
				min = data.min, max = data.max, single = data.single_target, notself = data.cant_target_self,
				higher = data.allow_higher_target, options = data.options,
			}
			if kind == "player" and data.optional and data.default == nil then arg.self_default = true end
			def.args[#def.args + 1] = arg
			return self
		end
		function obj:SetPermission(perm, rank)
			def.perm = tostring(perm)
			def.def = rank or "superadmin"
			return self
		end
		function obj:SetCategory(cat) def.samCat = cat return self end
		function obj:Help(h) def.helpText = tostring(h) return self end
		function obj:OnExecute(f) fn = f return self end
		function obj:DisallowConsole() def.noconsole = true return self end
		function obj:GetRestArgs() return self end
		function obj:MenuHide() def.hidden = true return self end
		function obj:DisableNotify() return self end
		function obj:End()
			def.run = function(caller, ...)
				if not fn then return end
				local vals = { ... }
				for i, a in ipairs(def.args) do
					if a.type == "offline" and istable(vals[i]) then
						-- SAM passes a promise for steamid arguments
						local info = vals[i]
						vals[i] = {
							done = function(_, cb) cb({ util.SteamIDFrom64(info.sid), info.ply }) end,
						}
					end
				end
				fn(caller, unpack(vals, 1, #def.args))
			end
			P.AddCommand(def)
			return def
		end
		return obj
	end
end

-- Fire the hooks ULX/SAM addons listen to whenever Praetor changes a rank.
hook.Add("Praetor.RankChanged", "Praetor.Bridge", function(ply, new, old, expires)
	if not P.Bridge.hasULX and IsValid(ply) then
		hook.Run("ULibUserGroupChange", ply:SteamID(), {}, {}, new, old)
		hook.Run("UCLChanged")
	end
	if not P.Bridge.hasSAM and IsValid(ply) then
		hook.Run("SAM.ChangedPlayerRank", ply, new, old, expires or 0)
	end
end)
