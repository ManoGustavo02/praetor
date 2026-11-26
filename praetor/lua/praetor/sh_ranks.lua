-- Praetor: ranks, authority and permissions (shared logic).
-- The server owns the data; clients receive a copy so menus can hide what the
-- player is not allowed to touch. Every action is checked again on the server.
local P = Praetor

P.Ranks = P.Ranks or {}
P.Perms = P.Perms or {}
P.Owners = P.Owners or {}
P.RankGroups = P.RankGroups or {}

P.OWNER_AUTHORITY = 1000
P.ProtectedRanks = { user = true, admin = true, superadmin = true }

P.LimitKeys = { "props", "ragdolls", "vehicles", "effects", "npcs", "sents", "balloons", "wheels", "thrusters", "dupe_ents" }

-- Ranks created on the very first start. Everything can be edited later.
P.DefaultRanks = {
	user = {
		name = "user", display = "Player", immunity = 0, inherit = nil, icon = "leaf",
		style = { text = "Player", c1 = { r = 170, g = 160, b = 146 }, fx = "none" },
	},
	vip = {
		name = "vip", display = "VIP", immunity = 10, inherit = "user", icon = "gem",
		style = { text = "VIP", c1 = { r = 240, g = 200, b = 90 }, c2 = { r = 255, g = 120, b = 60 }, fx = "shine" },
	},
	moderator = {
		name = "moderator", display = "Moderator", immunity = 40, inherit = "vip", icon = "shield",
		style = { text = "Moderator", c1 = { r = 110, g = 190, b = 120 }, c2 = { r = 60, g = 150, b = 170 }, fx = "flow" },
	},
	admin = {
		name = "admin", display = "Admin", immunity = 60, inherit = "moderator", icon = "sword",
		style = { text = "Admin", c1 = { r = 225, g = 90, b = 80 }, c2 = { r = 255, g = 170, b = 90 }, fx = "flow" },
	},
	superadmin = {
		name = "superadmin", display = "Superadmin", immunity = 90, inherit = "admin", icon = "crown",
		style = { text = "Superadmin", c1 = { r = 232, g = 194, b = 122 }, c2 = { r = 178, g = 52, b = 66 }, fx = "shine" },
	},
}

-- ------------------------------------------------------------------ permission registry

-- cat: group shown in the rank editor; def: lowest rank that gets it by default.
function P.RegisterPerm(id, cat, def, ext)
	if not isstring(id) or id == "" then return end
	local p = P.Perms[id]
	if p then return p end -- the first registration wins
	p = { id = id, cat = cat or "other", def = def or "superadmin", ext = ext or nil }
	P.Perms[id] = p
	return p
end

local base = {
	{ "menu", "general", "user" },
	{ "silent", "general", "admin" },
	{ "target_all", "general", "admin" },
	{ "see_silent", "general", "admin" },
	{ "adminchat", "chat", "moderator" },
	{ "chat_images", "chat", "vip" },
	{ "automod", "chat", "superadmin" },
	{ "automod_bypass", "chat", "admin" },
	{ "physgun_players", "player", "moderator" },
	{ "esp", "player", "moderator" },
	{ "see_cloaked", "player", "moderator" },
	{ "spray_info", "player", "moderator" },
	{ "chips", "spawn", "moderator" },
	{ "chips_manage", "spawn", "admin" },
	{ "noclip_key", "player", "admin" },
	{ "bypass_limits", "spawn", "superadmin" },
	{ "pp_all", "spawn", "moderator" },
	{ "reports", "reports", "moderator" },
	{ "logs", "logs", "moderator" },
	{ "crash_logs", "logs", "superadmin" },
	{ "view_sheet", "users", "moderator" },
	{ "user_notes", "users", "moderator" },
	{ "manage_users", "users", "admin" },
	{ "manage_bans", "users", "admin" },
	{ "manage_ranks", "ranks", "superadmin" },
	{ "manage_tags", "tags", "admin" },
	{ "manage_titles", "tags", "moderator" },
	{ "self_tag", "tags", "superadmin" },
	{ "manage_jobs", "darkrp", "admin" },
	{ "manage_restrict", "spawn", "superadmin" },
	{ "manage_announce", "chat", "admin" },
	{ "staff_stats", "users", "superadmin" },
	{ "alts", "users", "admin" },
	{ "manage_promote", "ranks", "superadmin" },
	{ "manage_sits", "reports", "admin" },
	{ "manage_restart", "server", "superadmin" },
	{ "manage_commands", "server", "superadmin" },
	{ "settings", "server", "superadmin" },
	{ "security", "server", "superadmin" },
}
for _, b in ipairs(base) do P.RegisterPerm(b[1], b[2], b[3]) end

-- ------------------------------------------------------------------ ranks

function P.GetRank(name) return P.Ranks[name] end

function P.RankOf(ply)
	local g = IsValid(ply) and ply:GetUserGroup() or "user"
	return P.Ranks[g] or P.Ranks.user or P.DefaultRanks.user
end

-- Walks the inheritance chain, guarding against loops.
function P.RankChain(name)
	local chain, seen = {}, {}
	while name and P.Ranks[name] and not seen[name] do
		seen[name] = true
		chain[#chain + 1] = P.Ranks[name]
		name = P.Ranks[name].inherit
	end
	return chain
end

function P.Inherits(name, ancestor)
	if name == ancestor then return true end
	for _, r in ipairs(P.RankChain(name)) do
		if r.name == ancestor then return true end
	end
	-- ranks created by other admin mods only exist in CAMI
	if CAMI and CAMI.UsergroupInherits and not P.Ranks[name] then
		return CAMI.UsergroupInherits(name, ancestor)
	end
	return false
end

function P.RankHas(name, perm)
	for _, r in ipairs(P.RankChain(name)) do
		local v = r.perms and r.perms[perm]
		if v ~= nil then return v == true end
	end
	local p = P.Perms[perm]
	local def = p and p.def or "superadmin"
	if def == "user" then return true end
	-- superadmin (and every rank above it) has everything that was not taken away by hand
	if P.Inherits(name, "superadmin") then return true end
	-- a lowest rank that does not exist here ("owner", "founder" from another admin mod) counts as superadmin
	if not P.Ranks[def] and not (CAMI and CAMI.GetUsergroup and CAMI.GetUsergroup(def)) then return false end
	return P.Inherits(name, def)
end

function P.SortedRanks()
	local t = {}
	for _, r in pairs(P.Ranks) do t[#t + 1] = r end
	table.sort(t, function(a, b)
		if (a.immunity or 0) == (b.immunity or 0) then return a.name < b.name end
		return (a.immunity or 0) > (b.immunity or 0)
	end)
	return t
end

-- ------------------------------------------------------------------ rank groups

-- the group a rank belongs to (Staff, VIP...), or nil
function P.RankGroupOf(name)
	local r = P.Ranks[name or ""]
	return r and r.group and P.RankGroups[r.group] or nil
end

-- groups in display order: the one with the highest rank first
function P.SortedRankGroups()
	local top = {}
	for _, r in pairs(P.Ranks) do
		if r.group and P.RankGroups[r.group] then top[r.group] = math.max(top[r.group] or -1, r.immunity or 0) end
	end
	local t = {}
	for id, g in pairs(P.RankGroups) do t[#t + 1] = g g.top = top[id] or -1 end
	table.sort(t, function(a, b)
		if a.top ~= b.top then return a.top > b.top end
		return a.name < b.name
	end)
	return t
end

-- staff = owner or a rank inside a group marked as staff. Without any staff
-- group (old setups), anyone with authority 40+ counts.
function P.IsStaff(ply)
	if not IsValid(ply) then return false end
	if P.IsOwner(ply) then return true end
	local hasStaffGroup = false
	for _, g in pairs(P.RankGroups) do if g.staff then hasStaffGroup = true break end end
	if hasStaffGroup then
		local g = P.RankGroupOf(ply:GetUserGroup())
		return g ~= nil and g.staff == true
	end
	return P.Authority(ply) >= 40
end

-- ------------------------------------------------------------------ players

function P.IsOwner(ply)
	if not IsValid(ply) then return false end
	if ply.IsListenServerHost and ply:IsListenServerHost() then return true end
	if game.SinglePlayer() then return true end
	-- clients only get the owner list when they can see the security tab, so
	-- they also read the flag the server puts on every owner
	if CLIENT and ply:GetNW2Bool("pr_owner") then return true end
	return P.Owners[ply:SteamID64() or ""] == true
end

function P.Authority(ply)
	if not IsValid(ply) then return P.OWNER_AUTHORITY + 1 end
	if P.IsOwner(ply) then return P.OWNER_AUTHORITY end
	local r = P.RankOf(ply)
	return r and (r.immunity or 0) or 0
end

-- Player overrides set by staff (extra allowed / denied permissions).
P.UserPerms = P.UserPerms or {} -- [sid64] = { allow = {}, deny = {} }

function P.Has(ply, perm)
	if not IsValid(ply) then return true end -- server console
	if P.IsOwner(ply) then return true end
	local up = P.UserPerms[ply:SteamID64() or ""]
	if up then
		if up.deny and up.deny[perm] then return false end
		if up.allow and up.allow[perm] then return true end
	end
	return P.RankHas(ply:GetUserGroup(), perm)
end

-- a acting on b. Owners can't be touched by anyone else; lower authority can't
-- touch higher authority; equal authority only if the setting allows it.
function P.CanTarget(a, b)
	if not IsValid(a) then return true end
	if not IsValid(b) or a == b then return true end
	local ao, bo = P.IsOwner(a), P.IsOwner(b)
	if bo then return false end
	if ao then return true end
	local ia, ib = P.Authority(a), P.Authority(b)
	if ia > ib then return true end
	return ia == ib and P.Setting("equal_target") == true
end

-- Same rule using a rank name / authority value (offline targets).
function P.CanTargetAuthority(a, authority, isOwner)
	if not IsValid(a) then return true end
	if isOwner then return false end
	if P.IsOwner(a) then return true end
	local ia = P.Authority(a)
	if ia > authority then return true end
	return ia == authority and P.Setting("equal_target") == true
end

-- the next automatic promotion from `rank`: name of the rank and the hours needed
function P.NextPromotion(rank)
	local best
	for name, r in pairs(P.Ranks) do
		local pr = r.promote
		if pr and not pr.off and pr.from == rank and name ~= rank then
			if not best or pr.hours < best.hours then best = { rank = name, hours = pr.hours } end
		end
	end
	return best
end

-- Can `ply` give / edit / remove the rank `name`?
function P.CanManageRank(ply, name)
	if not IsValid(ply) or P.IsOwner(ply) then return true end
	local r = P.Ranks[name]
	if not r then return false end
	return P.Authority(ply) > (r.immunity or 0)
end

-- ------------------------------------------------------------------ player meta

local PLAYER = FindMetaTable("Player")

function PLAYER:PraetorHas(perm) return P.Has(self, perm) end
function PLAYER:PraetorAuthority() return P.Authority(self) end
function PLAYER:PraetorCanTarget(t) return P.CanTarget(self, t) end
function PLAYER:PraetorIsOwner() return P.IsOwner(self) end
function PLAYER:PraetorRank() return P.RankOf(self) end

function PLAYER:GetPraetorTitle()
	local t = self:GetNW2String("pr_title", "")
	if t == "" then return nil end
	return util.JSONToTable(t)
end

function PLAYER:GetPraetorTag()
	local t = self:GetNW2String("pr_tag", "")
	if t == "" then return nil end
	return util.JSONToTable(t)
end

function PLAYER:GetRankColor()
	local r = P.RankOf(self)
	return r and r.style and P.ReadColor(r.style.c1, color_white) or color_white
end

function PLAYER:GetRankDisplay()
	local r = P.RankOf(self)
	return r and (r.display or r.name) or self:GetUserGroup()
end

function PLAYER:IsAdmin()
	if P.IsOwner(self) then return true end
	local g = self:GetUserGroup()
	if P.Ranks.admin then return P.Inherits(g, "admin") end
	return g == "admin" or g == "superadmin"
end

function PLAYER:IsSuperAdmin()
	if P.IsOwner(self) then return true end
	local g = self:GetUserGroup()
	if P.Ranks.superadmin then return P.Inherits(g, "superadmin") end
	return g == "superadmin"
end

-- ------------------------------------------------------------------ CAMI glue

local function camiRegisterRanks()
	if not CAMI then return end
	for name, r in pairs(P.Ranks) do
		local g = CAMI.GetUsergroup(name)
		if not g or g.CAMI_Source == "Praetor" or g.CAMI_Source == "Garry's Mod" then
			CAMI.RegisterUsergroup({ Name = name, Inherits = r.inherit or "user" }, "Praetor")
		end
	end
end
P.CAMIRegisterRanks = camiRegisterRanks

-- Answer every CAMI question with Praetor's permission rules.
hook.Add("CAMI.PlayerHasAccess", "Praetor", function(actor, priv, callback, target)
	if not IsValid(actor) then callback(true, "Praetor: console") return true end
	local ok = P.Has(actor, priv)
	if ok and IsValid(target) and target:IsPlayer() and not P.CanTarget(actor, target) then ok = false end
	callback(ok, "Praetor")
	return true
end)

hook.Add("CAMI.OnPrivilegeRegistered", "Praetor", function(priv)
	if not priv or not priv.Name or P.Perms[priv.Name] then return end
	local def = priv.MinAccess or "admin"
	P.RegisterPerm(priv.Name, "addons", def, true)
	if SERVER and P.QueuePermSync then P.QueuePermSync() end
end)

hook.Add("Initialize", "Praetor.CAMI", function()
	if not CAMI then return end
	for name, priv in pairs(CAMI.GetPrivileges()) do
		if not P.Perms[name] then P.RegisterPerm(name, "addons", priv.MinAccess or "admin", true) end
	end
end)
