-- Praetor: automod. Blocks chat messages (and GIF / image links) that contain
-- a listed word, logs it, tells the staff and optionally punishes.
local P = Praetor

local actionWait = {}
local hintWait = {}

-- Called first thing by the chat hook. Returns true when the message is blocked.
function P.AutoModBlock(ply, text)
	if not P.Setting("automod") or not IsValid(ply) or ply:IsBot() then return false end
	local bypass = P.AutoModSkips(ply)
	local word, kind, url = P.AutoModScan(text)
	if not word then return false end
	-- owners and automod_bypass are not blocked, but they learn that the filter
	-- caught it (otherwise testing the AutoMod as staff looks like it is broken)
	if bypass then
		if (hintWait[ply] or 0) < CurTime() then
			hintWait[ply] = CurTime() + 20
			P.Notify(ply, "n_automod_bypass", { V = word }, "info")
		end
		return false
	end
	local isImg = kind == "image"

	local custom = P.Setting("automod_message")
	if custom ~= "" then
		P.ChatTo(ply, P.Col.crimson, "[AutoMod] ", P.Col.ivory, custom)
	else
		P.Notify(ply, isImg and "n_automod_img" or "n_automod", nil, "warn")
	end

	P.Log("automod", isImg and "l_automod_img" or "l_automod", {
		A = P.LogPly(ply), V = word, V2 = P.Str(isImg and url or text, 250),
	}, { ply })

	if P.Setting("automod_alert") then
		local staff = P.WithPerm("logs")
		if #staff > 0 then P.Send(staff, "notify", { k = "n_automod_staff", a = { S = ply:Nick(), V = word } }) end
	end

	-- the punishment runs at most once every 8 seconds per player
	if (actionWait[ply] or 0) > CurTime() then return true end
	actionWait[ply] = CurTime() + 8
	local act = P.Setting("automod_action")
	if act == "mute" then
		P.SetMute(ply, math.max(1, P.Setting("automod_mute_min")), nil)
	elseif act == "warn" then
		P.AddWarn(ply:SteamID64(), ply:Nick(), "AutoMod: " .. word, 1, nil)
	elseif act == "kick" then
		local why = "AutoMod: " .. word
		timer.Simple(0, function() if IsValid(ply) then ply:Kick(why) end end)
	end
	hook.Run("Praetor.AutoModBlocked", ply, text, word, kind)
	return true
end

hook.Add("PlayerDisconnected", "Praetor.AutoMod", function(ply) actionWait[ply] = nil hintWait[ply] = nil end)

-- In GMod the first PlayerSay hook that returns something wins, in no fixed
-- order: a chat / tag addon that answers first would skip Praetor's hook and
-- the word would go through. So the AutoMod also runs inside hook.Call, before
-- every PlayerSay hook and the gamemode. If another addon (ULib...) replaces
-- hook.Call later, the check is put back on top of it.
local wrapped
local function installChatGuard()
	if hook.Call == wrapped then return end
	local orig = hook.Call
	wrapped = function(name, gm, ...)
		if name == "PlayerSay" then
			local ply, text = ...
			-- a banned player looking at the ban screen can't talk
			if IsValid(ply) and ply.PraetorBanned then return "" end
			if isstring(text) and IsValid(ply) and P.AutoModBlock(ply, P.Trim(text)) then return "" end
		end
		return orig(name, gm, ...)
	end
	hook.Call = wrapped
end
installChatGuard()
hook.Add("Initialize", "Praetor.AutoModGuard", installChatGuard)
hook.Add("InitPostEntity", "Praetor.AutoModGuard", installChatGuard)
timer.Create("Praetor.AutoModGuard", 30, 0, installChatGuard)

-- the automod tab saves only automod_* settings, so it has its own permission
P.Receive("automod_set", { perm = "automod", rate = 2 }, function(ply, data)
	if not istable(data.v) then return end
	local changed = {}
	for k, v in pairs(data.v) do
		if isstring(k) and (k == "automod" or k:sub(1, 8) == "automod_") and P.Defaults[k] ~= nil then
			local val = P.CleanSetting(k, v)
			if val ~= nil then
				P.Settings[k] = val
				changed[#changed + 1] = k
			end
		end
	end
	if #changed == 0 then return end
	P.SaveSettings()
	P.Log("settings", "l_settings", { A = P.LogPly(ply), V = table.concat(changed, ", ") }, { ply })
	P.SyncSettings()
	P.Notify(ply, "ok_saved", nil, "ok")
end)
