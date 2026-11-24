-- Praetor: ban screen.
--  * a player banned while online sees a full screen card (reason, who, when,
--    time left, ban code, the Discord link from the settings) before the kick;
--  * a banned player who tries to join is let in only to see the same screen,
--    then kicked. While on it they are invisible, frozen, can't talk, spawn,
--    use tools or send Praetor requests;
--  * someone who keeps reconnecting (3 tries in 10 minutes) only gets the
--    text message from Steam, so a ban can't hold a slot.
local P = Praetor

local tries = {}       -- sid -> { times }
P.BanJoin = P.BanJoin or {} -- sid -> ban row, for the ones let in to see the screen

local function screenData(b, sid, secs)
	return {
		id = b.id, n = b.name, r = b.reason, a = b.admin, c = tonumber(b.created) or 0, e = tonumber(b.expires) or 0,
		now = os.time(), d = P.Trim(P.Setting("ban_discord") or ""), ap = P.Setting("ban_appeal") or "",
		host = GetHostName(), sid = sid, secs = secs,
	}
end

local function secsOnScreen() return math.Clamp(math.floor(tonumber(P.Setting("ban_screen_time")) or 30), 8, 120) end

-- invisible, frozen and harmless
local function lockBody(ply)
	if not IsValid(ply) or not ply.PraetorBanned then return end
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:StripWeapons()
	ply:Lock()
	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:DrawShadow(false)
	ply:SetMoveType(MOVETYPE_NONE)
	ply:SetNW2Bool("pr_banscreen", true)
end

local function showAndKick(ply, b)
	if not IsValid(ply) then return end
	local secs = secsOnScreen()
	P.Send(ply, "ban_screen", screenData(b, ply:SteamID64(), secs))
	timer.Create("Praetor.BanKick." .. ply:UserID(), secs, 1, function()
		if IsValid(ply) then ply:Kick(P.BanMessage(b)) end
	end)
end

-- called by P.AddBan for a player that is online
function P.BanKick(ply, b)
	if not P.Setting("ban_screen") or ply:IsBot() then ply:Kick(P.BanMessage(b)) return end
	ply.PraetorBanned = b
	ply.PraetorBanShown = true
	lockBody(ply)
	showAndKick(ply, b)
end

-- called by CheckPassword: true = let them in to see the screen
function P.BanLetIn(sid, b)
	if not P.Setting("ban_screen_join") then return false end
	local now = os.time()
	local list = {}
	for _, t in ipairs(tries[sid] or {}) do if now - t < 600 then list[#list + 1] = t end end
	if #list >= 3 then tries[sid] = list return false end
	list[#list + 1] = now
	tries[sid] = list
	P.BanJoin[sid] = b
	return true
end

hook.Add("PlayerInitialSpawn", "Praetor.BanScreen", function(ply)
	local sid = ply:SteamID64()
	local b = sid and P.BanJoin[sid]
	if not b then return end
	P.BanJoin[sid] = nil
	ply.PraetorBanned = b
	timer.Simple(0, function() lockBody(ply) end)
	-- the client never finished loading: out anyway
	timer.Create("Praetor.BanLoad." .. ply:UserID(), 150, 1, function()
		if IsValid(ply) then ply:Kick(P.BanMessage(b)) end
	end)
end)

-- the client says it finished loading (a separate net message, the Praetor
-- requests are closed for banned players): now the screen can be sent
util.AddNetworkString("praetor_bsready")
net.Receive("praetor_bsready", function(_, ply)
	if not IsValid(ply) or not ply.PraetorBanned or ply.PraetorBanShown then return end
	ply.PraetorBanShown = true
	timer.Remove("Praetor.BanLoad." .. ply:UserID())
	lockBody(ply)
	showAndKick(ply, ply.PraetorBanned)
end)

-- the ban was lifted while they look at the screen: they stay
hook.Add("Praetor.Unbanned", "Praetor.BanScreen", function(sid)
	P.BanJoin[sid] = nil
	local ply = P.BySID(sid)
	if not IsValid(ply) or not ply.PraetorBanned then return end
	ply.PraetorBanned = nil
	ply.PraetorBanShown = nil
	timer.Remove("Praetor.BanKick." .. ply:UserID())
	timer.Remove("Praetor.BanLoad." .. ply:UserID())
	ply:SetNW2Bool("pr_banscreen", false)
	ply:UnLock()
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:DrawShadow(true)
	ply:SetMoveType(MOVETYPE_WALK)
	ply:Spawn()
	P.Send(ply, "ban_screen", { off = true })
end)

hook.Add("PlayerSpawn", "Praetor.BanScreen", function(ply)
	if ply.PraetorBanned then timer.Simple(0, function() lockBody(ply) end) end
end)

-- ------------------------------------------------------------------ nothing works while banned

local function no(ply) if IsValid(ply) and ply.PraetorBanned then return false end end
for _, h in ipairs({ "PlayerSpawnObject", "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerGiveSWEP",
	"PlayerSpawnNPC", "PlayerSpawnVehicle", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerNoClip", "PlayerUse",
	"PlayerCanPickupWeapon", "PlayerCanPickupItem", "CanPlayerSuicide", "PhysgunPickup", "GravGunPickupAllowed",
	"CanTool", "CanProperty", "CanDrive", "CanPlayerEnterVehicle", "PlayerShouldTakeDamage" }) do
	hook.Add(h, "Praetor.BanScreen", no)
end

hook.Add("PlayerCanHearPlayersVoice", "Praetor.BanScreen", function(_, talker)
	if IsValid(talker) and talker.PraetorBanned then return false end
end)

hook.Add("StartCommand", "Praetor.BanScreen", function(ply, cmd)
	if ply.PraetorBanned then
		cmd:ClearButtons()
		cmd:ClearMovement()
	end
end)

-- ------------------------------------------------------------------ chat lines

-- the ban commands' own echo is replaced by this line (see P.Echo)
P.BanEchoKeys = { e_ban = true, e_ban_perm = true, e_banid = true }

local function audience(silent, mode)
	if mode == "none" then return false end
	if silent or mode == "staff" then return P.WithPerm("see_silent") end
	return nil -- everyone
end

local function sendTo(to, op, data)
	if to == false then return end
	if to then
		if #to > 0 then P.Send(to, op, data) end
	else
		P.Send(nil, op, data)
	end
end

-- every ban (command, ban tab, vote, linked account, AutoMod...)
hook.Add("Praetor.Banned", "Praetor.BanNews", function(sid, minutes, reason, admin)
	local silent = P.CurrentSilent == true
	local to = audience(silent, P.Setting("ban_announce"))
	sendTo(to, "ban_news", {
		n = P.KnownName(sid) or P.SID32(sid), sid = sid,
		a = IsValid(admin) and admin:Nick() or (isstring(admin) and admin or "Console"),
		r = reason ~= "" and reason or nil, m = math.floor(tonumber(minutes) or 0), s = silent and 1 or nil,
	})
end)

-- a banned player tried to join (once a minute per player)
local tryNote = {}
function P.BanTryNotice(sid, name, b)
	if (tryNote[sid] or 0) > os.time() then return end
	tryNote[sid] = os.time() + 60
	local to = audience(false, P.Setting("ban_try_announce"))
	local e = tonumber(b.expires) or 0
	sendTo(to, "ban_try", {
		n = (isstring(name) and name ~= "") and P.Str(name, 64) or (b.name or P.KnownName(sid) or sid), sid = sid,
		r = (b.reason and b.reason ~= "") and b.reason or nil, a = b.admin, left = e > 0 and math.max(1, math.ceil((e - os.time()) / 60)) or 0, id = b.id,
	})
	P.Log("conn", "l_ban_try", { T = { n = (isstring(name) and name ~= "") and name or (b.name or sid), s = sid }, V = (b.reason and b.reason ~= "") and b.reason or "-" }, { sid })
end
