-- Praetor: CAMI (Common Admin Mod Interface).
-- CAMI is the shared contract most addons (DarkRP, FAdmin, prop protections,
-- shops...) use to ask an admin mod "does this player have access to X?".
-- If another addon already loaded a recent CAMI we reuse it, otherwise this file
-- provides a compatible implementation of the same API.

local VERSION = 20211019

if CAMI and (CAMI.Version or 0) >= VERSION then return end

local old = CAMI
CAMI = {}
CAMI.Version = VERSION

local usergroups = (old and old.GetUsergroups and old.GetUsergroups()) or {}
local privileges = (old and old.GetPrivileges and old.GetPrivileges()) or {}

usergroups.user = usergroups.user or { Name = "user", Inherits = "user", CAMI_Source = "Garry's Mod" }
usergroups.admin = usergroups.admin or { Name = "admin", Inherits = "user", CAMI_Source = "Garry's Mod" }
usergroups.superadmin = usergroups.superadmin or { Name = "superadmin", Inherits = "admin", CAMI_Source = "Garry's Mod" }

function CAMI.RegisterUsergroup(group, source)
	if source then group.CAMI_Source = tostring(source) end
	usergroups[group.Name] = group
	hook.Call("CAMI.OnUsergroupRegistered", nil, group, source)
	return group
end

function CAMI.UnregisterUsergroup(name, source)
	if not usergroups[name] then return false end
	local group = usergroups[name]
	usergroups[name] = nil
	hook.Call("CAMI.OnUsergroupUnregistered", nil, group, source)
	return true
end

function CAMI.GetUsergroups() return usergroups end
function CAMI.GetUsergroup(name) return usergroups[name] end

function CAMI.UsergroupInherits(name, ancestor)
	local seen = {}
	repeat
		if name == ancestor then return true end
		if seen[name] then return false end
		seen[name] = true
		local g = usergroups[name]
		if not g then return false end
		if g.Inherits == name then return name == ancestor end
		name = g.Inherits
	until not name
	return false
end

function CAMI.InheritanceRoot(name)
	local seen = {}
	local g = usergroups[name]
	while g and g.Inherits and g.Inherits ~= g.Name and not seen[g.Name] do
		seen[g.Name] = true
		local nxt = usergroups[g.Inherits]
		if not nxt then break end
		g = nxt
	end
	return g and g.Name or name
end

function CAMI.RegisterPrivilege(priv)
	privileges[priv.Name] = priv
	hook.Call("CAMI.OnPrivilegeRegistered", nil, priv)
	return priv
end

function CAMI.UnregisterPrivilege(name)
	if not privileges[name] then return false end
	local priv = privileges[name]
	privileges[name] = nil
	hook.Call("CAMI.OnPrivilegeUnregistered", nil, priv)
	return true
end

function CAMI.GetPrivileges() return privileges end
function CAMI.GetPrivilege(name) return privileges[name] end

-- Fallback used when no admin mod answers the CAMI.PlayerHasAccess hook.
local fallback = {
	["CAMI.PlayerHasAccess"] = function(_, actor, privName, callback)
		if not IsValid(actor) then callback(true, "Fallback.") return end
		local priv = privileges[privName]
		local min = priv and priv.MinAccess or "user"
		callback(CAMI.UsergroupInherits(actor:GetUserGroup(), min), "Fallback.")
	end,
	["CAMI.SteamIDHasAccess"] = function(_, _, _, callback)
		callback(false, "No information available.")
	end,
}

function CAMI.PlayerHasAccess(actor, privName, callback, target, extra)
	local hasAccess, reason
	local cb = callback or function(h, r) hasAccess, reason = h, r end
	hook.Call("CAMI.PlayerHasAccess", fallback, actor, privName, cb, target, extra)
	if callback ~= nil then return end
	if hasAccess == nil then
		ErrorNoHalt("CAMI.PlayerHasAccess was called without a callback and the admin mod answered asynchronously.\n")
		return false
	end
	return hasAccess, reason
end

function CAMI.GetPlayersWithAccess(privName, callback, target, extra)
	local allowed, count, total = {}, 0, player.GetCount()
	if total == 0 then callback(allowed) return end
	for _, p in ipairs(player.GetAll()) do
		CAMI.PlayerHasAccess(p, privName, function(ok)
			count = count + 1
			if ok then allowed[#allowed + 1] = p end
			if count == total then callback(allowed) end
		end, target, extra)
	end
end

function CAMI.SteamIDHasAccess(sid, privName, callback, targetSid, extra)
	hook.Call("CAMI.SteamIDHasAccess", fallback, sid, privName, callback, targetSid, extra)
end

function CAMI.SignalUserGroupChanged(ply, old, new, source)
	hook.Call("CAMI.PlayerUsergroupChanged", nil, ply, old, new, source)
end

function CAMI.SignalSteamIDUserGroupChanged(sid, old, new, source)
	hook.Call("CAMI.SteamIDUsergroupChanged", nil, sid, old, new, source)
end

-- older name some addons still call
CAMI.PlayerUsergroupChanged = CAMI.SignalUserGroupChanged
