-- Praetor: security.
--  * Owners: SteamIDs added ONLY from the server console (or the listen server
--    host). Owners have every permission, cannot be targeted, demoted, kicked or
--    banned by anyone in game, and are the only ones who can restore backups,
--    use rcon and change the security settings.
--  * Rank lock: ply:SetUserGroup() calls that do not come from Praetor are
--    blocked above a configurable authority (stops backdoors / exploits in other
--    addons from handing out staff ranks or removing them).
--  * Rank backups: the rank table is saved before every change; owners can roll
--    back from the Security tab.
--  * Security log: blocked requests, rate-limit hits, external rank changes.
local P = Praetor

-- ------------------------------------------------------------------ owners

function P.LoadOwners()
	P.Owners = {}
	for sid, v in pairs(P.DB.Get("owners", {})) do
		if v == true and P.ToSID64(sid) == sid then P.Owners[sid] = true end
	end
end

-- Owners always hold at least the superadmin rank. Without it their user group
-- stays "user": the player list and the scoreboard show "Player", and addons that
-- only look at IsSuperAdmin()/GetUserGroup() (not CAMI) don't see them as staff.
function P.PromoteOwner(ply)
	if not IsValid(ply) or ply:IsBot() or not P.IsOwner(ply) then return end
	local top = P.Ranks.superadmin
	if not top then return end
	local cur = P.RankOf(ply)
	if cur and (cur.immunity or 0) >= (top.immunity or 90) then return end
	P.SetRankSID(nil, ply:SteamID64(), "superadmin", 0, "owner")
end

local function saveOwners()
	P.DB.Set("owners", P.Owners)
	for _, p in ipairs(player.GetHumans()) do
		p:SetNW2Bool("pr_owner", P.IsOwner(p))
		P.PromoteOwner(p)
	end
	P.SyncAll()
end

hook.Add("Praetor.UserLoaded", "Praetor.OwnerRank", function(ply)
	timer.Simple(0, function() P.PromoteOwner(ply) end)
end)

concommand.Add("praetor_owner", function(ply, _, args)
	if IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, "[Praetor] praetor_owner only works from the server console / rcon.\n")
		if P.Security then P.Security(ply, "owner_cmd", "praetor_owner from client") end
		return
	end
	local action, who = (args[1] or "list"):lower(), args[2]
	if action == "list" then
		print("[Praetor] owners:")
		for sid in pairs(P.Owners) do print("  " .. sid .. "  " .. P.SID32(sid) .. "  " .. (P.KnownName and P.KnownName(sid) or "")) end
		return
	end
	local sid = P.ToSID64(who or "")
	if not sid then
		-- also accept the name of someone online
		for _, p in ipairs(player.GetHumans()) do
			if who and p:Nick():lower():find(who:lower(), 1, true) then sid = p:SteamID64() break end
		end
	end
	if not sid then print("[Praetor] usage: praetor_owner add|remove|list <SteamID / SteamID64 / name>") return end
	if action == "add" then
		P.Owners[sid] = true
		print("[Praetor] " .. P.SID32(sid) .. " is now an owner.")
	elseif action == "remove" then
		P.Owners[sid] = nil
		print("[Praetor] " .. P.SID32(sid) .. " is no longer an owner.")
	else
		print("[Praetor] usage: praetor_owner add|remove|list <SteamID>")
		return
	end
	saveOwners()
	P.Security(nil, "owner_change", action .. " " .. sid)
end)

-- ------------------------------------------------------------------ security log

local recent = {}

-- quiet: no red alert for the staff (the caller already told them)
function P.Security(ply, kind, info, quiet)
	local sid = IsValid(ply) and P.SIDOf(ply) or "SERVER"
	local key = sid .. kind
	if recent[key] and recent[key] > CurTime() then return end
	recent[key] = CurTime() + 8
	local name = IsValid(ply) and ply:Nick() or "Server"
	info = P.Str(info or "", 240)
	P.DB.Query("INSERT INTO praetor_security (t, sid, name, kind, info) VALUES (?, ?, ?, ?, ?)", os.time(), sid, name, kind, info)
	MsgC(Color(230, 120, 60), "[Praetor security] ", kind, " ", name, " (", sid, ") ", info, "\n")
	hook.Run("Praetor.SecurityEvent", kind, name, sid, info)
	local watchers = {}
	for _, p in ipairs(player.GetHumans()) do
		if P.IsOwner(p) or P.Has(p, "security") then watchers[#watchers + 1] = p end
	end
	if #watchers > 0 and kind ~= "net_rate" and not quiet then
		P.Send(watchers, "alert", { kind = kind, name = name, info = info })
	end
end

local SEC_CATS
-- groups of events for the filter chips (LIKE patterns on the kind)
SEC_CATS = {
	net = { "net%" },
	ranks = { "rank%", "owner%" },
	accounts = { "family%", "alt%" },
	anticrash = { "ac%", "dupe%" },
	backdoor = { "backdoor%" },
}

P.Receive("security_list", { perm = "security", rate = 2 }, function(ply, data)
	local page = math.max(0, math.floor(tonumber(data.page) or 0))
	-- filter by group of events and by text (name, SteamID or details)
	local where, args = {}, {}
	local cat = isstring(data.cat) and SEC_CATS[data.cat]
	if cat then
		local ors = {}
		for _, pat in ipairs(cat) do ors[#ors + 1] = "kind LIKE ?" args[#args + 1] = pat end
		where[#where + 1] = "(" .. table.concat(ors, " OR ") .. ")"
	end
	local q = isstring(data.q) and P.Trim(P.Str(data.q, 60)) or ""
	if q ~= "" then
		local sid = P.ToSID64(q)
		if sid then
			where[#where + 1] = "sid = ?" args[#args + 1] = sid
		else
			where[#where + 1] = "(name LIKE ? OR info LIKE ? OR kind LIKE ?)"
			local like = "%" .. q:gsub("[%%_]", "") .. "%"
			args[#args + 1] = like args[#args + 1] = like args[#args + 1] = like
		end
	end
	local sqlWhere = #where > 0 and (" WHERE " .. table.concat(where, " AND ")) or ""
	args[#args + 1] = page * 60
	local rows = P.DB.Query("SELECT * FROM praetor_security" .. sqlWhere .. " ORDER BY id DESC LIMIT 60 OFFSET ?", unpack(args)) or {}
	-- last 24 hours, hour by hour, and how many of each group in 7 days
	local now = os.time()
	local hist = {}
	for i = 1, 24 do hist[i] = 0 end
	for _, r in ipairs(P.DB.Query("SELECT t FROM praetor_security WHERE t > ?", now - 86400) or {}) do
		local slot = 24 - math.floor((now - (tonumber(r.t) or now)) / 3600)
		if hist[slot] then hist[slot] = hist[slot] + 1 end
	end
	local counts = {}
	for _, r in ipairs(P.DB.Query("SELECT kind, COUNT(*) AS n FROM praetor_security WHERE t > ? GROUP BY kind", now - 7 * 86400) or {}) do
		counts[r.kind] = tonumber(r.n) or 0
	end
	local backups = {}
	for _, f in ipairs(P.ListBackups()) do backups[#backups + 1] = f end
	local owners = {}
	for sid in pairs(P.Owners) do owners[#owners + 1] = { sid = sid, name = P.KnownName and P.KnownName(sid) or "" } end
	-- the host of a listen server (or singleplayer) is an owner without being on the list
	for _, p in ipairs(player.GetHumans()) do
		local sid = p:SteamID64()
		if sid and not P.Owners[sid] and P.IsOwner(p) then owners[#owners + 1] = { sid = sid, name = p:Nick(), host = true } end
	end
	local day = P.DB.Query("SELECT COUNT(*) AS n FROM praetor_security WHERE t > ?", os.time() - 86400) or {}
	local family = {}
	for _, p in ipairs(player.GetHumans()) do
		local o = p:GetNW2String("pr_family", "")
		if o ~= "" then family[#family + 1] = { sid = p:SteamID64(), name = p:Nick(), owner = o } end
	end
	P.Send(ply, "security_list", {
		rows = rows, page = page, backups = backups, owners = owners,
		day = tonumber(day[1] and day[1].n) or 0, scan = P.LastScan, family = family,
		hist = hist, counts = counts, cat = cat and data.cat or nil, q = q ~= "" and q or nil,
	})
end)

-- ------------------------------------------------------------------ rank backups

local BACKUP_DIR = "praetor/backups"

function P.ListBackups()
	local files = file.Find(BACKUP_DIR .. "/ranks_*.json", "DATA", "datedesc") or {}
	local out = {}
	for i = 1, math.min(#files, 30) do out[i] = files[i] end
	return out
end

function P.BackupRanks(reason)
	file.CreateDir(BACKUP_DIR)
	local name = string.format("%s/ranks_%s_%03d.json", BACKUP_DIR, os.date("%Y%m%d_%H%M%S"), math.random(0, 999))
	file.Write(name, util.TableToJSON({ reason = reason, t = os.time(), ranks = P.Ranks }) or "{}")
	local files = file.Find(BACKUP_DIR .. "/ranks_*.json", "DATA", "datedesc") or {}
	for i = 41, #files do file.Delete(BACKUP_DIR .. "/" .. files[i]) end
end

P.Receive("backup_restore", { owner = true, rate = 0.2 }, function(ply, data)
	local f = isstring(data.f) and data.f or ""
	if not f:match("^ranks_[%d_]+%.json$") then return end
	local raw = file.Read(BACKUP_DIR .. "/" .. f, "DATA")
	local t = raw and util.JSONToTable(raw)
	if not t or not istable(t.ranks) then P.Notify(ply, "err_backup") return end
	P.BackupRanks("before restore")
	P.Ranks = {}
	for name, r in pairs(t.ranks) do
		local clean = P.CleanRank and P.CleanRank(r, name)
		if clean then P.Ranks[name] = clean end
	end
	P.EnsureBaseRanks()
	P.SaveRanks()
	P.SyncAll()
	P.Log("security", "l_restore", { A = P.LogPly(ply), V = f }, { ply })
	P.Notify(ply, "ok_restored", { V = f }, "ok")
end)

-- ------------------------------------------------------------------ rank lock

local PLAYER = FindMetaTable("Player")
P._SetUserGroup = P._SetUserGroup or PLAYER.SetUserGroup

-- Internal setter used by Praetor only.
function P.ApplyUserGroup(ply, name)
	P._applying = true
	local ok, err = pcall(P._SetUserGroup, ply, name)
	P._applying = false
	if not ok then ErrorNoHalt("[Praetor] " .. tostring(err) .. "\n") end
end

local function callerSource()
	for lvl = 3, 8 do
		local info = debug.getinfo(lvl, "Sl")
		if not info then break end
		local src = info.short_src or "?"
		if not src:find("praetor", 1, true) then return src .. ":" .. tostring(info.currentline) end
	end
	return "?"
end

function PLAYER:SetUserGroup(name)
	if P._applying or not P.Ready then return P._SetUserGroup(self, name) end
	name = tostring(name or "user"):lower()
	if name == self:GetUserGroup() then return end
	local src = callerSource()
	local newRank = P.Ranks[name]
	local newAuth = newRank and newRank.immunity or 0
	local curAuth = P.Authority(self)
	local max = P.Setting("rank_lock_max")

	if P.Setting("rank_lock") and (P.IsOwner(self) or newAuth > max or curAuth > max) then
		P.Security(self, "rank_external", string.format("%s -> %s blocked (%s)", self:GetUserGroup(), name, src))
		return
	end

	if newRank and P.SetRankSID and self:SteamID64() then
		P.SetRankSID(nil, self:SteamID64(), name, 0, "external: " .. src)
	else
		P.ApplyUserGroup(self, name)
	end
end

-- GMod's own users.txt loader would fight with Praetor over ranks.
hook.Add("Initialize", "Praetor.RemoveAuth", function()
	hook.Remove("PlayerInitialSpawn", "PlayerAuthSpawn")
end)
hook.Remove("PlayerInitialSpawn", "PlayerAuthSpawn")

-- ------------------------------------------------------------------ Family Sharing
-- A banned player can come back on a borrowed copy of the game (Steam Family
-- Sharing): the SteamID is new but OwnerSteamID64() points to the banned one.

local function checkFamily(ply)
	if not IsValid(ply) or ply:IsBot() or not ply.OwnerSteamID64 then return end
	local sid, owner = ply:SteamID64(), ply:OwnerSteamID64()
	if not owner or owner == "0" or owner == sid then return end
	if P.Owners[sid] then return end
	local ban = P.BanCache and P.BanCache[owner]
	if ban and (ban.expires == 0 or ban.expires > os.time()) and P.Setting("family_ban") then
		local left = ban.expires == 0 and 0 or math.max(1, math.ceil((ban.expires - os.time()) / 60))
		P.Security(ply, "family_ban", "owner " .. owner .. " is banned")
		P.AddBan(sid, ply:Nick(), left, P.LText(P.Setting("lang") == "pt" and "pt" or "en", "sec_family_reason", { S = util.SteamIDFrom64(owner) }), "Praetor")
		return
	end
	if P.Setting("family_block") then
		P.Security(ply, "family_block", "owner " .. owner)
		ply:Kick("Family Sharing accounts are not allowed on this server / Contas do Family Sharing não são permitidas neste servidor\n\n[Praetor]")
		return
	end
	ply:SetNW2String("pr_family", owner)
	P.Security(ply, "family_share", "owner " .. owner)
end

hook.Add("PlayerAuthed", "Praetor.Family", function(ply)
	timer.Simple(2, function() checkFamily(ply) end)
end)

-- ------------------------------------------------------------------ backdoor scan
-- Net messages that only known backdoors / exploit menus register. Finding one
-- means some addon on the server is infected (usually a leaked or "free" copy).
local BACKDOOR_NETS = {
	"Sandbox_Armdupe", "Sbox_gm_attackofnullday_key", "ZimbaBackDoor", "Zimba_Backdoor", "memeDoor", "Backdoor",
	"OdiumBackDoor", "backdoor", "blacksmurfBackdoor", "_blacksmurf", "jesuslebg", "zilnix", "disablebackdoor",
	"jeveuttonrconleul", "Fix_Keypads", "fix_keypads", "noclipcloakaesp_chat_text", "_Defqon", "_CAC_ReadMemory",
	"LickMeOut", "MoonMan", "Im_SOCool", "Remove_Exploiters", "NoNerks", "ULX_QUERY2", "ULXQUERY2", "Sandbox_GayParty",
	"_Infinity", "cucked", "NoOdium_ReadPing", "rcivluz", "SENDTEST", "MJkQswHqfZ", "INJ3v4", "_raidrp", "cool_kids_only",
	"nostrip", "enablevac", "killserver", "fuckserver", "cvaraccess", "rconadmin", "Ulogs_Infos", "ITSLIT",
	"HAX_NET", "BackDoor", "_Kekb", "fps_booster", "pjHabrp9EY", "GMOD_NETDBG", "kidsonly", "DevelopmentRunString",
	"RTX_PROFILER", "elfamosabackdoormdr", "thefrenchenculer", "xenoexistscl", "Sandbox_ArmDupe", "c_hack",
}

-- functions that are normally untouched and that backdoors like to replace
local WATCHED = { "RunString", "CompileString", "RunStringEx", "CompileFile" }
local original = P._origFuncs or {}
P._origFuncs = original
for _, n in ipairs(WATCHED) do if original[n] == nil then original[n] = _G[n] or false end end

function P.BackdoorScan()
	local found = {}
	for _, name in ipairs(BACKDOOR_NETS) do
		if util.NetworkStringToID(name) ~= 0 then found[#found + 1] = { kind = "net", name = name } end
	end
	for _, n in ipairs(WATCHED) do
		if original[n] and _G[n] ~= original[n] then
			local info = debug.getinfo(_G[n], "S")
			found[#found + 1] = { kind = "func", name = n, src = info and info.short_src or "?" }
		end
	end
	P.LastScan = { t = os.time(), found = found }
	if #found > 0 then
		local names = {}
		for _, f in ipairs(found) do names[#names + 1] = f.name end
		P.Security(nil, "backdoor", table.concat(names, ", "))
	end
	return P.LastScan
end

hook.Add("InitPostEntity", "Praetor.BackdoorScan", function()
	-- other addons register their net messages while the map loads
	timer.Simple(20, function() P.BackdoorScan() end)
end)

P.Receive("security_scan", { perm = "security", rate = 0.2 }, function(ply)
	P.Send(ply, "security_scan", P.BackdoorScan())
end)
