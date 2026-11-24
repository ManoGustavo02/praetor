-- Praetor: importers. Brings ranks, users and bans from SAM or ULX so a server
-- can switch without starting over. Only owners can run them.
local P = Praetor

local function tableExists(name)
	return sql.TableExists(name)
end

-- Tiny reader for ULib's key/value files (users.txt / groups.txt).
local function parseULib(text)
	local tokens = {}
	local i, n = 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "/" and text:sub(i + 1, i + 1) == "/" then
			local e = text:find("\n", i, true) or n
			i = e + 1
		elseif c == "\"" then
			local e = text:find("\"", i + 1, true) or n
			tokens[#tokens + 1] = { s = text:sub(i + 1, e - 1) }
			i = e + 1
		elseif c == "{" or c == "}" then
			tokens[#tokens + 1] = { b = c }
			i = i + 1
		elseif c:match("%s") then
			i = i + 1
		else
			local e = i
			while e <= n and not text:sub(e, e):match("[%s{}\"]") do e = e + 1 end
			tokens[#tokens + 1] = { s = text:sub(i, e - 1) }
			i = e
		end
	end
	local pos = 1
	local function block()
		local t, list = {}, {}
		while pos <= #tokens do
			local tk = tokens[pos]
			if tk.b == "}" then pos = pos + 1 return t, list end
			if tk.s then
				local nxt = tokens[pos + 1]
				if nxt and nxt.b == "{" then
					pos = pos + 2
					local sub, sublist = block()
					t[tk.s] = (#sublist > 0 and next(sub) == nil) and sublist or sub
				elseif nxt and nxt.s and not (tokens[pos + 2] and tokens[pos + 2].b == "{") then
					t[tk.s] = nxt.s
					pos = pos + 2
				else
					list[#list + 1] = tk.s
					pos = pos + 1
				end
			else
				pos = pos + 1
			end
		end
		return t, list
	end
	local root = block()
	return root
end

local function importRank(name, inherit, immunity, perms)
	name = tostring(name):lower():gsub("[^%w_]", "")
	if name == "" or #name > 24 then return false end
	local r = P.Ranks[name]
	if not r then
		r = P.CleanRank({ name = name, display = name, immunity = immunity or 10, inherit = inherit or "user" }, name)
		if not r then return false end
		P.Ranks[name] = r
	end
	for _, perm in ipairs(perms or {}) do
		local id = tostring(perm):lower():gsub("^ulx ", "")
		if P.Perms[id] then r.perms[id] = true end
	end
	return true
end

local function importUser(sid, name, rank)
	if not sid or not P.Ranks[rank] then return false end
	P.EnsureUser(sid, name)
	P.DB.Query("UPDATE praetor_users SET rank = ?, name = CASE WHEN name = '' OR name IS NULL THEN ? ELSE name END WHERE sid = ?", rank, P.Str(name or "", 64), sid)
	return true
end

local function importBan(sid, name, reason, admin, created, expires)
	if not sid then return false end
	local exists = P.DB.Value("SELECT COUNT(*) FROM praetor_bans WHERE sid = ? AND lifted = 0", sid)
	if tonumber(exists or 0) > 0 then return false end
	P.DB.Query("INSERT INTO praetor_bans (sid, name, reason, admin, admin_sid, created, expires) VALUES (?, ?, ?, ?, '', ?, ?)",
		sid, P.Str(name or "", 64), P.Str(reason or "", 200), P.Str(admin or "import", 64), tonumber(created) or os.time(), tonumber(expires) or 0)
	return true
end

function P.ImportSAM()
	local res = { ranks = 0, users = 0, bans = 0 }
	if tableExists("sam_ranks") then
		for _, r in ipairs(sql.Query("SELECT name, immunity, ban_limit FROM sam_ranks") or {}) do
			if importRank(r.name, "user", math.Clamp(tonumber(r.immunity) or 10, 0, 100)) then
				res.ranks = res.ranks + 1
				local rk = P.Ranks[tostring(r.name):lower()]
				if rk and tonumber(r.ban_limit) then rk.ban_limit = math.max(0, math.floor(tonumber(r.ban_limit) or 0)) end
			end
		end
	end
	if tableExists("sam_players") then
		for _, u in ipairs(sql.Query("SELECT steamid, name, rank, play_time, first_join FROM sam_players") or {}) do
			local sid = P.ToSID64(u.steamid)
			if sid and importUser(sid, u.name, P.Ranks[u.rank] and u.rank or "user") then
				res.users = res.users + 1
				P.DB.Query("UPDATE praetor_users SET playtime = MAX(playtime, ?), first = CASE WHEN first = 0 THEN ? ELSE first END WHERE sid = ?", tonumber(u.play_time) or 0, tonumber(u.first_join) or 0, sid)
			end
		end
	end
	if tableExists("sam_bans") then
		local now = os.time()
		for _, b in ipairs(sql.Query("SELECT steamid, name, reason, admin, unban_date FROM sam_bans") or {}) do
			local exp = tonumber(b.unban_date) or 0
			if exp == 0 or exp > now then
				if importBan(P.ToSID64(b.steamid), b.name, b.reason, b.admin, now, exp) then res.bans = res.bans + 1 end
			end
		end
	end
	return res
end

function P.ImportULX()
	local res = { ranks = 0, users = 0, bans = 0 }
	local groups = file.Read("ulib/groups.txt", "DATA")
	if groups then
		local t = parseULib(groups)
		-- create in two passes so inheritance points to ranks that exist
		local imm = { user = 0, operator = 30, admin = 60, superadmin = 90 }
		for name, g in pairs(t) do
			if istable(g) then
				if importRank(name, nil, imm[name] or 20, istable(g.allow) and g.allow or {}) then res.ranks = res.ranks + 1 end
			end
		end
		for name, g in pairs(t) do
			local r = P.Ranks[tostring(name):lower()]
			if r and istable(g) and isstring(g.inherit_from) and P.Ranks[g.inherit_from:lower()] and r.name ~= "user" then
				r.inherit = g.inherit_from:lower()
			end
		end
	end
	local users = file.Read("ulib/users.txt", "DATA")
	if users then
		for id, u in pairs(parseULib(users)) do
			local sid = P.ToSID64(id)
			if sid and istable(u) then
				local g = tostring(u.group or "user"):lower()
				if importUser(sid, u.name, P.Ranks[g] and g or "user") then res.users = res.users + 1 end
			end
		end
	end
	if tableExists("ulib_bans") then
		local now = os.time()
		for _, b in ipairs(sql.Query("SELECT steamid, time, unban, reason, name, admin FROM ulib_bans") or {}) do
			local exp = tonumber(b.unban) or 0
			if exp == 0 or exp > now then
				if importBan(P.ToSID64(b.steamid), b.name, b.reason, b.admin, b.time, exp) then res.bans = res.bans + 1 end
			end
		end
	end
	return res
end

P.Receive("import", { owner = true, rate = 0.2 }, function(ply, data)
	local from = data.from
	P.BackupRanks("before import " .. tostring(from))
	local res
	if from == "sam" then res = P.ImportSAM()
	elseif from == "ulx" then res = P.ImportULX()
	else return end
	P.EnsureBaseRanks()
	P.SaveRanks()
	P.CAMIRegisterRanks()
	P.LoadBans()
	P.SyncAll()
	for _, p in ipairs(player.GetHumans()) do P.LoadUser(p) end
	P.Log("security", "l_import", { A = P.LogPly(ply), V = from, V2 = string.format("%d/%d/%d", res.ranks, res.users, res.bans) }, { ply })
	P.Notify(ply, "ok_import", { V = res.ranks, V2 = res.users, S = res.bans }, "ok")
end)

P.Receive("import_check", { owner = true, rate = 1 }, function(ply)
	P.Send(ply, "import_check", {
		sam = tableExists("sam_players") or tableExists("sam_ranks"),
		ulx = file.Exists("ulib/users.txt", "DATA") or file.Exists("ulib/groups.txt", "DATA") or tableExists("ulib_bans"),
	})
end)
