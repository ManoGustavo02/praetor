-- Praetor: alt account detector. Two SteamIDs that joined from the same
-- connection are linked. The IP itself is never stored: only a salted hash,
-- so the database can't be used to find out where a player lives.
-- When a linked account is banned the staff gets an alert, and the server can
-- also kick or ban the new account (setting alt_action).
local P = Praetor

P.DB.Query([[CREATE TABLE IF NOT EXISTS praetor_ips (h TEXT, sid TEXT, last INTEGER, PRIMARY KEY (h, sid))]])

local salt
local function getSalt()
	if salt then return salt end
	salt = P.DB.Get("ip_salt", nil)
	if not isstring(salt) or #salt < 16 then
		local t = {}
		for i = 1, 32 do t[i] = string.format("%02x", math.random(0, 255)) end
		salt = table.concat(t) .. tostring(os.time())
		P.DB.Set("ip_salt", salt)
	end
	return salt
end

-- loopback, LAN and listen-server hosts are skipped: everybody there shares one address
local function usableIP(ply)
	if ply:IsBot() or ply:IsListenServerHost() then return nil end
	local ip = (ply:IPAddress() or ""):match("^(%d+%.%d+%.%d+%.%d+)")
	if not ip then return nil end
	local a, b = ip:match("^(%d+)%.(%d+)")
	a, b = tonumber(a), tonumber(b)
	if a == 127 or a == 10 or a == 0 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) or (a == 169 and b == 254) then return nil end
	return ip
end

local function hashIP(ip)
	return util.SHA256(getSalt() .. "|" .. ip)
end

-- other accounts seen on the same connection in the last alt_days days
function P.AltsOf(sid)
	local days = math.max(1, P.Setting("alt_days") or 60)
	local since = os.time() - days * 86400
	local rows = P.DB.Query([[SELECT DISTINCT b.sid AS sid, MAX(b.last) AS last FROM praetor_ips a JOIN praetor_ips b ON a.h = b.h
		WHERE a.sid = ? AND b.sid != ? AND b.last >= ? GROUP BY b.sid ORDER BY last DESC LIMIT 20]], sid, sid, since) or {}
	local out = {}
	for _, r in ipairs(rows) do
		local ban = P.BanCache[r.sid]
		local u = P.UserRow(r.sid) or {}
		out[#out + 1] = {
			sid = r.sid, name = P.KnownName(r.sid) or u.name or "?", last = tonumber(r.last) or 0,
			rank = u.rank or "user", on = IsValid(P.BySID(r.sid)) or nil,
			ban = ban and { r = ban.reason, e = tonumber(ban.expires) or 0 } or nil,
		}
	end
	return out
end

local function banIsActive(b)
	if not b then return false end
	local e = tonumber(b.expires) or 0
	return e == 0 or e > os.time()
end

hook.Add("Praetor.UserLoaded", "Praetor.Alts", function(ply)
	if not P.Setting("alt_check") then return end
	local ip = usableIP(ply)
	if not ip then return end
	local sid = ply:SteamID64()
	local h = hashIP(ip)
	P.DB.Query("INSERT OR REPLACE INTO praetor_ips (h, sid, last) VALUES (?, ?, ?)", h, sid, os.time())

	local alts = P.AltsOf(sid)
	if #alts == 0 then return end
	-- owners and staff are never acted on, only listed
	local staffish = P.IsOwner(ply) or P.IsStaff(ply)

	local banned
	for _, a in ipairs(alts) do
		if banIsActive(P.BanCache[a.sid]) then banned = a break end
	end

	local names = {}
	for i, a in ipairs(alts) do if i <= 4 then names[#names + 1] = a.name end end
	P.Log("security", banned and "l_alt_banned" or "l_alt", { A = P.LogPly(ply), V = table.concat(names, ", "), V2 = banned and banned.name or nil }, { ply, banned and banned.sid or nil })

	local action = P.Setting("alt_action") or "alert"
	local data = { sid = sid, name = ply:Nick(), alts = alts, banned = banned and banned.sid or nil, act = banned and not staffish and action or "alert" }
	local to = P.WithPerm("alts")
	if #to > 0 and (banned or P.Setting("alt_alert_all")) then P.Send(to, "alt_alert", data) end
	-- Security tab (P.Security also fires Praetor.SecurityEvent for the webhook)
	if P.Security and (banned or P.Setting("alt_alert_all")) then P.Security(ply, banned and "alt_banned" or "alt_link", table.concat(names, ", "), true) end

	-- already banned (looking at the ban screen): nothing more to do
	if not banned or staffish or ply.PraetorBanned then return end
	if action == "kick" then
		timer.Simple(2, function()
			if IsValid(ply) then ply:Kick(P.LText(P.Setting("lang") == "pt" and "pt" or "en", "alt_kick_msg", { S = banned.name .. " - " .. (util.SteamIDFrom64(banned.sid) or banned.sid) })) end
		end)
	elseif action == "ban" then
		local b = P.BanCache[banned.sid]
		local e = tonumber(b.expires) or 0
		local minutes = e == 0 and 0 or math.max(1, math.ceil((e - os.time()) / 60))
		timer.Simple(2, function()
			if not IsValid(ply) then return end
			P.AddBan(sid, ply:Nick(), minutes, P.LText(P.Setting("lang") == "pt" and "pt" or "en", "alt_ban_reason", { S = banned.name, V = util.SteamIDFrom64(banned.sid) or banned.sid }), "Praetor AltCheck")
		end)
	end
end)

-- a list for the player sheet
function P.AltsForSheet(viewer, sid)
	if not P.Has(viewer, "alts") then return nil end
	return P.AltsOf(sid)
end

-- old entries are cleaned once a day
timer.Create("Praetor.AltsClean", 86400, 0, function()
	local keep = math.max(30, (P.Setting("alt_days") or 60) * 2)
	P.DB.Query("DELETE FROM praetor_ips WHERE last < ?", os.time() - keep * 86400)
end)
