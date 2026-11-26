-- Praetor: rank storage and the rank editor requests.
local P = Praetor

local function cleanList(t, max)
	local out = {}
	if not istable(t) then return out end
	for _, v in ipairs(t) do
		if isstring(v) and v:match("^[%w_%-%./]+$") and #v <= 96 then out[#out + 1] = v:lower() end
		if #out >= (max or 200) then break end
	end
	return out
end

function P.CleanRank(r, name)
	if not istable(r) then return nil end
	name = tostring(name or r.name or ""):lower()
	if not name:match("^[%w_]+$") or #name > 24 then return nil end
	local out = {
		name = name,
		display = P.Trim(P.Str(r.display or name, 24)),
		immunity = math.Clamp(math.floor(tonumber(r.immunity) or 0), 0, 100),
		inherit = isstring(r.inherit) and r.inherit:lower() or nil,
		icon = isstring(r.icon) and r.icon:match("^[%w_]+$") and r.icon or "leaf",
		style = P.CleanStyle(r.style, 24) or { text = P.Str(r.display or name, 24), c1 = { r = 200, g = 200, b = 200 }, fx = "none" },
		perms = {},
		limits = {},
		block = { tools = cleanList(r.block and r.block.tools), ents = cleanList(r.block and r.block.ents), weps = cleanList(r.block and r.block.weps) },
		ban_limit = math.Clamp(math.floor(tonumber(r.ban_limit) or 0), 0, 5256000),
		chat_color = r.chat_color and P.ColorTable(P.ReadColor(r.chat_color, color_white)) or nil,
		group = isstring(r.group) and #r.group <= 24 and r.group:match("^[%w_]+$") and r.group:lower() or nil,
	}
	if out.display == "" then out.display = name end
	if out.inherit == name then out.inherit = nil end
	if istable(r.perms) then
		local n = 0
		for k, v in pairs(r.perms) do
			if isstring(k) and #k <= 64 and isbool(v) then
				out.perms[k] = v
				n = n + 1
				if n > 2000 then break end
			end
		end
	end
	if istable(r.limits) then
		for _, k in ipairs(P.LimitKeys) do
			local v = tonumber(r.limits[k])
			if v then out.limits[k] = math.Clamp(math.floor(v), -1, 100000) end
		end
	end
	if istable(r.promote) and isstring(r.promote.from) and tonumber(r.promote.hours) then
		out.promote = { from = r.promote.from:lower(), hours = math.Clamp(math.floor(tonumber(r.promote.hours) * 60 + 0.5) / 60, 1 / 60, 100000), off = r.promote.off == true or nil }
	end
	local goal = tonumber(r.goal)
	if goal and goal > 0 then out.goal = math.Clamp(math.floor(goal * 4 + 0.5) / 4, 0.25, 168) end
	if name == "user" then out.inherit = nil out.immunity = 0 end
	return out
end

function P.EnsureBaseRanks()
	for name in pairs(P.ProtectedRanks) do
		if not P.Ranks[name] then P.Ranks[name] = P.CleanRank(P.DefaultRanks[name], name) end
	end
	-- fix dangling inheritance
	for name, r in pairs(P.Ranks) do
		if r.inherit and not P.Ranks[r.inherit] then r.inherit = name ~= "user" and "user" or nil end
	end
end

function P.LoadRanks()
	local saved = P.DB.Get("ranks", nil)
	P.Ranks = {}
	if not saved then
		for name, r in pairs(P.DefaultRanks) do P.Ranks[name] = P.CleanRank(r, name) end
		P.SaveRanks()
	else
		for name, r in pairs(saved) do
			local c = P.CleanRank(r, name)
			if c then P.Ranks[c.name] = c end
		end
	end
	P.EnsureBaseRanks()
	P.LoadRankGroups()
	P.CAMIRegisterRanks()
end

function P.SaveRanks()
	P.DB.Set("ranks", P.Ranks)
end

local function hasLoop(name)
	local seen = {}
	local r = P.Ranks[name]
	while r do
		if seen[r.name] then return true end
		seen[r.name] = true
		r = r.inherit and P.Ranks[r.inherit]
	end
	return false
end

local function commit(ply, reason, logKey, args)
	P.SaveRanks()
	P.CAMIRegisterRanks()
	P.SyncAll()
	if logKey then
		args = args or {}
		args.A = P.LogPly(ply)
		P.Log("rank", logKey, args, { ply })
	end
end

-- Chat line "X gave rank Y: kick, ban" when someone edits permissions.
-- changes = { [perm] = true (allow) / false (deny) / "inherit" }
function P.PermFeed(ply, kind, name, col, changes)
	local mode = P.Setting("perm_announce")
	if mode == "none" or not istable(changes) then return end
	local give, take, reset = {}, {}, {}
	for perm, v in pairs(changes) do
		if v == true then give[#give + 1] = perm
		elseif v == false then take[#take + 1] = perm
		else reset[#reset + 1] = perm end
	end
	if #give + #take + #reset == 0 then return end
	table.sort(give) table.sort(take) table.sort(reset)
	local data = {
		a = IsValid(ply) and ply:Nick() or "Console", as = IsValid(ply) and ply:SteamID64() or nil,
		ac = IsValid(ply) and P.RankOf(ply) and P.RankOf(ply).style and P.RankOf(ply).style.c1 or nil,
		k = kind, n = name, c = col, g = give, t = take, r = reset,
	}
	local to = mode == "all" and player.GetHumans() or P.WithPerm("see_silent")
	if IsValid(ply) and not table.HasValue(to, ply) then to[#to + 1] = ply end
	if #to > 0 then P.Send(to, "perm_feed", data) end
end

-- Used by the ULX/SAM bridge and by custom code.
function P.SetRankPerm(name, perm, value)
	local r = P.Ranks[name]
	if not r then return end
	r.perms[perm] = value
	P.SaveRanks()
	P.QueuePermSync()
end

-- ------------------------------------------------------------------ requests

P.Receive("rank_create", { perm = "manage_ranks", rate = 1 }, function(ply, data)
	local name = tostring(data.name or ""):lower():gsub("[^%w_]", "")
	if name == "" or #name > 24 then P.Notify(ply, "err_rank_name") return end
	if P.Ranks[name] then P.Notify(ply, "err_rank_exists", { S = name }) return end
	local count = table.Count(P.Ranks)
	if count >= 60 then P.Notify(ply, "err_rank_max") return end
	local imm = math.Clamp(math.floor(tonumber(data.immunity) or 5), 0, 100)
	if not P.IsOwner(ply) and imm >= P.Authority(ply) then P.Notify(ply, "err_rank_authority") return end
	local inherit = isstring(data.inherit) and P.Ranks[data.inherit] and data.inherit or "user"
	if not P.CanManageRank(ply, inherit) and inherit ~= "user" then P.Notify(ply, "err_rank_authority") return end
	P.BackupRanks("create " .. name)
	local base = P.Ranks[inherit]
	P.Ranks[name] = P.CleanRank({
		name = name, display = data.display or name, immunity = imm, inherit = inherit, icon = base and base.icon,
		group = isstring(data.group) and P.RankGroups[data.group] and data.group or (base and base.group) or nil,
		style = { text = data.display or name, c1 = base and base.style and base.style.c1 or { r = 200, g = 200, b = 200 }, fx = "none" },
	}, name)
	commit(ply, "create", "l_rank_create", { V = name })
	P.Notify(ply, "ok_rank_created", { V = name }, "ok")
end)

P.Receive("rank_update", { perm = "manage_ranks", rate = 3, max = 262144 }, function(ply, data)
	local name = isstring(data.name) and data.name or ""
	local r = P.Ranks[name]
	if not r then return end
	if not P.CanManageRank(ply, name) then P.Notify(ply, "err_rank_authority") return end
	local owner = P.IsOwner(ply)
	local auth = P.Authority(ply)
	local f = istable(data.r) and data.r or {}
	P.BackupRanks("update " .. name)

	local new = table.Copy(r)
	if f.display ~= nil then new.display = f.display end
	if f.style ~= nil then new.style = f.style end
	if f.icon ~= nil then new.icon = f.icon end
	if f.chat_color ~= nil then new.chat_color = f.chat_color ~= false and f.chat_color or nil end
	if f.immunity ~= nil then
		local imm = math.Clamp(math.floor(tonumber(f.immunity) or r.immunity), 0, 100)
		if not owner and imm >= auth then P.Notify(ply, "err_rank_authority") return end
		new.immunity = imm
	end
	if f.inherit ~= nil and name ~= "user" then
		local inh = isstring(f.inherit) and f.inherit or "user"
		if not P.Ranks[inh] or inh == name then P.Notify(ply, "err_rank_inherit") return end
		new.inherit = inh
	end
	if f.ban_limit ~= nil then new.ban_limit = f.ban_limit end
	if f.goal ~= nil then new.goal = (tonumber(f.goal) or 0) > 0 and f.goal or nil end
	if f.limits ~= nil then new.limits = f.limits end
	if f.block ~= nil then new.block = f.block end
	if f.promote ~= nil then new.promote = f.promote ~= false and f.promote or nil end
	if f.group ~= nil then new.group = (isstring(f.group) and P.RankGroups[f.group]) and f.group or nil end
	if istable(f.perms) then
		-- nobody can hand out (or take away) a permission they do not have themselves
		for perm, v in pairs(f.perms) do
			if isstring(perm) and (owner or P.Has(ply, perm)) then
				if v == "inherit" or v == nil then new.perms[perm] = nil
				elseif isbool(v) then new.perms[perm] = v end
			end
		end
	end

	local clean = P.CleanRank(new, name)
	if not clean then return end
	local old = P.Ranks[name]
	P.Ranks[name] = clean
	if hasLoop(name) then P.Ranks[name] = old P.Notify(ply, "err_rank_inherit") return end
	-- what changed in the permissions (for the chat line)
	local diff = {}
	local before, after = old.perms or {}, clean.perms or {}
	for perm, v in pairs(after) do if before[perm] ~= v then diff[perm] = v end end
	for perm in pairs(before) do if after[perm] == nil then diff[perm] = "inherit" end end
	commit(ply, "update", "l_rank_update", { V = name })
	P.PermFeed(ply, "rank", clean.display or name, clean.style and clean.style.c1 or nil, diff)
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("rank_delete", { perm = "manage_ranks", rate = 1 }, function(ply, data)
	local name = isstring(data.name) and data.name or ""
	local r = P.Ranks[name]
	if not r or P.ProtectedRanks[name] then return end
	if not P.CanManageRank(ply, name) then P.Notify(ply, "err_rank_authority") return end
	P.BackupRanks("delete " .. name)
	local fallback = r.inherit and P.Ranks[r.inherit] and r.inherit or "user"
	P.Ranks[name] = nil
	for _, other in pairs(P.Ranks) do
		if other.inherit == name then other.inherit = fallback end
	end
	P.DB.Query("UPDATE praetor_users SET rank = ? WHERE rank = ?", fallback, name)
	for _, p in ipairs(player.GetHumans()) do
		if p:GetUserGroup() == name then P.ApplyRank(p, fallback, 0) end
	end
	if CAMI then CAMI.UnregisterUsergroup(name, "Praetor") end
	commit(ply, "delete", "l_rank_delete", { V = name })
end)

P.Receive("rank_rename", { perm = "manage_ranks", rate = 1 }, function(ply, data)
	local old = isstring(data.old) and data.old or ""
	local new = tostring(data.new or ""):lower():gsub("[^%w_]", "")
	if not P.Ranks[old] or P.ProtectedRanks[old] or new == "" or #new > 24 or P.Ranks[new] then P.Notify(ply, "err_rank_name") return end
	if not P.CanManageRank(ply, old) then P.Notify(ply, "err_rank_authority") return end
	P.BackupRanks("rename " .. old)
	local r = P.Ranks[old]
	r.name = new
	P.Ranks[new] = r
	P.Ranks[old] = nil
	for _, other in pairs(P.Ranks) do
		if other.inherit == old then other.inherit = new end
		if other.promote and other.promote.from == old then other.promote.from = new end
	end
	P.DB.Query("UPDATE praetor_users SET rank = ? WHERE rank = ?", new, old)
	for _, p in ipairs(player.GetHumans()) do
		if p:GetUserGroup() == old then P.ApplyUserGroup(p, new) end
	end
	if CAMI then CAMI.UnregisterUsergroup(old, "Praetor") end
	commit(ply, "rename", "l_rank_rename", { V = old, V2 = new })
end)

-- ------------------------------------------------------------------ rank groups
-- Groups put ranks together: "Staff" holds moderator, admin and superadmin,
-- "VIP" the paid ranks... The scoreboard shows one block per group and
-- `staff = true` marks the groups that count as staff (staff online, P.IsStaff).
-- A group is ordered by the highest authority among its ranks.

local MAX_GROUPS = 20

local function cleanGroup(g, id)
	if not istable(g) then return nil end
	id = tostring(id or g.id or ""):lower()
	if not id:match("^[%w_]+$") or #id > 24 then return nil end
	local name = P.Trim(P.Str(g.name or id, 24))
	if name == "" then name = id end
	return {
		id = id,
		name = name,
		col = P.ColorTable(P.ReadColor(g.col, Color(188, 160, 255))),
		icon = isstring(g.icon) and g.icon:match("^[%w_]+$") and g.icon or "shield",
		staff = g.staff == true,
	}
end

function P.SaveRankGroups() P.DB.Set("rank_groups", P.RankGroups) end

function P.LoadRankGroups()
	local saved = P.DB.Get("rank_groups", nil)
	P.RankGroups = {}
	if not saved then
		-- first start with 1.2.0: a Staff group and a VIP group with the default ranks
		P.RankGroups.staff = cleanGroup({ name = "Staff", col = { r = 92, g = 132, b = 255 }, icon = "shield", staff = true }, "staff")
		P.RankGroups.vip = cleanGroup({ name = "VIP", col = { r = 240, g = 200, b = 90 }, icon = "gem" }, "vip")
		for name, g in pairs({ moderator = "staff", admin = "staff", superadmin = "staff", vip = "vip" }) do
			if P.Ranks[name] and not P.Ranks[name].group then P.Ranks[name].group = g end
		end
		P.SaveRankGroups()
		P.SaveRanks()
	else
		for id, g in pairs(saved) do
			local c = cleanGroup(g, id)
			if c then P.RankGroups[c.id] = c end
		end
	end
	for _, r in pairs(P.Ranks) do
		if r.group and not P.RankGroups[r.group] then r.group = nil end
	end
end

P.Receive("rgroup_save", { perm = "manage_ranks", rate = 2 }, function(ply, data)
	local id = isstring(data.id) and P.RankGroups[data.id] and data.id or nil
	if not id then
		if table.Count(P.RankGroups) >= MAX_GROUPS then P.Notify(ply, "err_rgroup_max", { V = MAX_GROUPS }, "warn") return end
		local base = tostring(data.name or ""):lower():gsub("[^%w_]", "_"):gsub("_+", "_"):sub(1, 18)
		if base == "" or base == "_" then base = "group" end
		id = base
		local n = 2
		while P.RankGroups[id] do id = base .. n n = n + 1 end
	end
	local g = cleanGroup(data, id)
	if not g then P.Notify(ply, "err_rgroup_name") return end
	P.RankGroups[id] = g
	-- ranks picked in the group window
	if istable(data.ranks) then
		local want = {}
		for _, name in ipairs(data.ranks) do if isstring(name) then want[name] = true end end
		for name, r in pairs(P.Ranks) do
			if P.CanManageRank(ply, name) or P.IsOwner(ply) then
				if want[name] then r.group = id elseif r.group == id then r.group = nil end
			end
		end
		P.SaveRanks()
	end
	P.SaveRankGroups()
	commit(ply, "group", "l_rgroup_save", { V = g.name })
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("rgroup_delete", { perm = "manage_ranks", rate = 1 }, function(ply, data)
	local id = isstring(data.id) and data.id or ""
	local g = P.RankGroups[id]
	if not g then return end
	P.RankGroups[id] = nil
	for _, r in pairs(P.Ranks) do if r.group == id then r.group = nil end end
	P.SaveRankGroups()
	commit(ply, "group", "l_rgroup_delete", { V = g.name })
end)
