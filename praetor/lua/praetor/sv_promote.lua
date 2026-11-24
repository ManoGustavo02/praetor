-- Praetor: automatic promotion by play time. The rule lives in the rank that
-- is given ("Member: from user after 10 h"), so it follows renames and
-- deletes. The "Promotions" tab edits only that part of the rank, with its own
-- permission (manage_promote), so the person who sets it up does not need the
-- full rank editor.
local P = Praetor

local function commit(ply, key, args)
	P.SaveRanks()
	P.SyncAll()
	args = args or {}
	args.A = P.LogPly(ply)
	P.Log("rank", key, args, { ply })
end

P.Receive("promote_set", { perm = { "manage_promote", "manage_ranks" }, rate = 1 }, function(ply, data)
	local rank = isstring(data.rank) and data.rank or ""
	local r = P.Ranks[rank]
	if not r or rank == "user" then return end
	if not P.CanManageRank(ply, rank) then P.Notify(ply, "err_rank_authority") return end

	if data.del then
		if not r.promote then return end
		r.promote = nil
		commit(ply, "l_promo_del", { V = r.display })
		P.Notify(ply, "pm_deleted", nil, "ok")
		return
	end

	local from = isstring(data.from) and data.from or ""
	if not P.Ranks[from] or from == rank then P.Notify(ply, "err_promo_from") return end
	if not P.CanManageRank(ply, from) then P.Notify(ply, "err_rank_authority") return end
	-- hours with minutes (5h30m = 5.5): the rank tab and this tab take any time
	local hours = math.floor((tonumber(data.hours) or 0) * 60 + 0.5) / 60
	if hours < 1 / 60 or hours > 100000 then P.Notify(ply, "err_promo_hours") return end
	-- two rules from the same rank that give the same hours make no sense
	for name, o in pairs(P.Ranks) do
		if name ~= rank and o.promote and o.promote.from == from and o.promote.hours == hours and not o.promote.off then
			P.Notify(ply, "err_promo_same", { V = o.display })
			return
		end
	end
	r.promote = { from = from, hours = hours, off = data.off == true or nil }
	commit(ply, "l_promo_set", { V = r.display, V2 = (P.Ranks[from].display or from) .. " / " .. P.FormatDuration(hours * 60) })
	P.Notify(ply, "pm_saved", nil, "ok")
end)

-- the promoted player gets a big message in the middle of the screen, the rest
-- of the server sees it in the chat (the echo from sv_users)
hook.Add("Praetor.AutoPromoted", "Praetor.Promote", function(ply, rank, from, hours)
	if not IsValid(ply) then return end
	local r = P.Ranks[rank]
	if not r then return end
	local c = r.style and r.style.c1 or { r = 90, g = 170, b = 255 }
	P.Send(ply, "promo_party", { rank = rank, display = r.display, from = P.Ranks[from] and P.Ranks[from].display or from, hours = hours, c = c })
	local nx = P.NextPromotion(rank)
	if nx then
		timer.Simple(9, function()
			if not IsValid(ply) then return end
			local left = nx.hours * 3600 - P.PlayTime(ply)
			if left > 0 then P.Notify(ply, "n_next_promo", { V = P.Ranks[nx.rank] and P.Ranks[nx.rank].display or nx.rank, V2 = P.FormatHours(left) }) end
		end)
	end
end)

-- a staff member can see the people close to their next promotion
P.Receive("promote_near", { perm = { "manage_promote", "manage_ranks" }, rate = 2 }, function(ply)
	local list = {}
	for _, p in ipairs(player.GetHumans()) do
		local nx = P.NextPromotion(p:GetUserGroup())
		if nx and p:GetNW2Int("pr_rexp", 0) == 0 then
			list[#list + 1] = { sid = p:SteamID64(), name = p:Nick(), rank = nx.rank, have = math.floor(P.PlayTime(p)), need = nx.hours * 3600 }
		end
	end
	-- offline players too, by the saved play time
	local rules = {}
	for name, r in pairs(P.Ranks) do
		if r.promote and not r.promote.off then rules[#rules + 1] = { name = name, from = r.promote.from, hours = r.promote.hours } end
	end
	for _, rule in ipairs(rules) do
		local rows = P.DB.Query("SELECT sid, name, playtime FROM praetor_users WHERE rank = ? AND (rank_exp IS NULL OR rank_exp = 0) ORDER BY playtime DESC LIMIT 12", rule.from) or {}
		for _, row in ipairs(rows) do
			if not IsValid(P.BySID(row.sid)) then
				local nx = P.NextPromotion(rule.from)
				if nx and nx.rank == rule.name then
					list[#list + 1] = { sid = row.sid, name = row.name or "?", rank = nx.rank, have = tonumber(row.playtime) or 0, need = nx.hours * 3600, off = true }
				end
			end
		end
	end
	table.sort(list, function(a, b) return (a.have / a.need) > (b.have / b.need) end)
	while #list > 30 do table.remove(list) end
	P.Send(ply, "promote_near", { list = list })
end)
