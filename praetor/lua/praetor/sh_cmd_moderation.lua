-- Praetor: moderation and teleport commands.
local P = Praetor
local C = P.AddCommand

local function reasonArg() return { type = "text", hint = "reason", optional = true, default = "" } end

-- ------------------------------------------------------------------ moderation

C({ id = "kick", cat = "moderation", def = "moderator", preset = true,
	args = { { type = "player", single = true, noself = true }, reasonArg() },
	run = function(caller, t, reason)
		local ply = t[1]
		P.Echo(caller, reason ~= "" and "e_kick_r" or "e_kick", { T = t, V = reason })
		P.Log("punish", "l_kick", { A = P.LogPly(caller), T = P.LogPly(ply), V = reason }, { caller, ply })
		hook.Run("Praetor.Kicked", ply, reason, caller)
		ply:Kick((reason ~= "" and reason or "Kicked") .. " - " .. P.NameOf(caller))
	end })

C({ id = "ban", cat = "moderation", def = "admin", preset = true,
	-- banning yourself would lock you out: never, not even with ^
	args = { { type = "player", single = true, notself = true }, { type = "duration", hint = "time", optional = true, default = 0 }, reasonArg() },
	run = function(caller, t, minutes, reason)
		local ply = t[1]
		if ply:IsBot() then return "err_bot" end
		local ok, limit = P.CheckBanLimit(caller, minutes)
		if not ok then P.Notify(caller, "err_ban_limit", { V = P.FormatDuration(limit) }) return end
		P.Echo(caller, minutes == 0 and "e_ban_perm" or "e_ban", { T = t, V = P.FormatDuration(minutes), V2 = reason })
		P.AddBan(ply:SteamID64(), ply:Nick(), minutes, reason, caller)
	end })

C({ id = "banid", cat = "moderation", def = "admin", aliases = { "bansteamid", "addban" },
	args = { { type = "offline", hint = "steamid" }, { type = "duration", hint = "time", optional = true, default = 0 }, reasonArg() },
	run = function(caller, who, minutes, reason)
		local ok, limit = P.CheckBanLimit(caller, minutes)
		if not ok then P.Notify(caller, "err_ban_limit", { V = P.FormatDuration(limit) }) return end
		if P.Owners[who.sid] then return "err_owner_target" end
		P.Echo(caller, "e_banid", { T = { who.name }, V = P.FormatDuration(minutes), V2 = reason })
		P.AddBan(who.sid, who.name, minutes, reason, caller)
	end })

C({ id = "unban", cat = "moderation", def = "admin",
	args = { { type = "text", hint = "steamid", rest = false } },
	run = function(caller, str)
		local sid = P.ToSID64(str)
		if not sid then return "err_steamid" end
		local row = P.DB.Row("SELECT admin_sid FROM praetor_bans WHERE sid = ? AND lifted = 0 ORDER BY id DESC", sid)
		if IsValid(caller) and row and row.admin_sid and row.admin_sid ~= "" and row.admin_sid ~= "NULL" and not P.IsOwner(caller) then
			local auth, owner = P.AuthorityOfSID(row.admin_sid)
			if owner or auth > P.Authority(caller) then return "err_ban_higher" end
		end
		if not P.LiftBan(sid, caller) then return "err_not_banned" end
		P.Echo(caller, "e_unban", { T = { P.KnownName(sid) or P.SID32(sid) } })
	end })

C({ id = "warn", cat = "moderation", def = "moderator", preset = true,
	args = { { type = "player", single = true, noself = true }, { type = "text", hint = "reason" } },
	run = function(caller, t, reason)
		P.AddWarn(t[1]:SteamID64(), t[1]:Nick(), reason, 1, caller)
		P.Echo(caller, "e_warn", { T = t, V = reason })
	end })

C({ id = "mute", cat = "moderation", def = "moderator", preset = true,
	args = { { type = "player" }, { type = "duration", hint = "time", optional = true, default = 0 } },
	run = function(caller, t, minutes)
		for _, p in ipairs(t) do P.SetMute(p, minutes, caller) end
		P.Echo(caller, minutes > 0 and "e_mute_t" or "e_mute", { T = t, V = P.FormatDuration(minutes) })
	end })

C({ id = "unmute", cat = "moderation", def = "moderator",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetMute(p, -1, caller) end
		P.Echo(caller, "e_unmute", { T = t })
	end })

C({ id = "gag", cat = "moderation", def = "moderator", preset = true,
	args = { { type = "player" }, { type = "duration", hint = "time", optional = true, default = 0 } },
	run = function(caller, t, minutes)
		for _, p in ipairs(t) do P.SetGag(p, minutes, caller) end
		P.Echo(caller, minutes > 0 and "e_gag_t" or "e_gag", { T = t, V = P.FormatDuration(minutes) })
	end })

C({ id = "ungag", cat = "moderation", def = "moderator",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetGag(p, -1, caller) end
		P.Echo(caller, "e_ungag", { T = t })
	end })

C({ id = "sprayban", cat = "moderation", def = "moderator", aliases = { "banspray", "bloquearspray" },
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetSprayBan(p, true, caller) end
		P.Echo(caller, "e_sprayban", { T = t })
	end })

C({ id = "unsprayban", cat = "moderation", def = "moderator", aliases = { "unbanspray", "liberarspray" },
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetSprayBan(p, false, caller) end
		P.Echo(caller, "e_unsprayban", { T = t })
	end })

C({ id = "jail", cat = "moderation", def = "moderator", preset = true,
	-- no time = until someone uses !unjail
	args = { { type = "player" }, { type = "duration", hint = "time", optional = true, default = 0 }, reasonArg() },
	run = function(caller, t, minutes, reason)
		for _, p in ipairs(t) do P.Jail(p, minutes, caller, nil, reason) end
		P.Echo(caller, minutes > 0 and "e_jail_t" or "e_jail", { T = t, V = P.FormatDuration(minutes), V2 = reason ~= "" and reason or "@jail_no_reason" })
	end })

-- jails the players where you are looking (one cell each, side by side)
C({ id = "jailtp", cat = "moderation", def = "admin", aliases = { "tpjail" },
	args = { { type = "player" }, { type = "duration", hint = "time", optional = true, default = 0 }, reasonArg() },
	run = function(caller, t, minutes, reason)
		if not IsValid(caller) then return "err_console" end
		local tr = util.TraceLine({ start = caller:EyePos(), endpos = caller:EyePos() + caller:GetAimVector() * 32768, filter = caller, mask = MASK_PLAYERSOLID_BRUSHONLY })
		-- a little away from what you aimed at (a wall), then down to the floor
		local base = tr.HitPos + tr.HitNormal * 64
		local right = caller:GetRight()
		right.z = 0
		right:Normalize()
		for i, p in ipairs(t) do
			local off = (i - 1 - (#t - 1) / 2) * 120
			P.SaveReturn(p)
			P.Jail(p, minutes, caller, base + right * off, reason)
		end
		P.Echo(caller, minutes > 0 and "e_jail_t" or "e_jail", { T = t, V = P.FormatDuration(minutes), V2 = reason ~= "" and reason or "@jail_no_reason" })
	end })

C({ id = "unjail", cat = "moderation", def = "moderator",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.Unjail(p, caller) end
		P.Echo(caller, "e_unjail", { T = t })
	end })

C({ id = "freeze", cat = "moderation", def = "moderator", preset = true,
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.Freeze(p, true) end
		P.Echo(caller, "e_freeze", { T = t })
	end })

C({ id = "unfreeze", cat = "moderation", def = "moderator",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do P.Freeze(p, false) end
		P.Echo(caller, "e_unfreeze", { T = t })
	end })

C({ id = "slay", cat = "moderation", def = "admin", aliases = { "kill" }, preset = true,
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do if p:Alive() then p:Kill() end end
		P.Echo(caller, "e_slay", { T = t })
	end })

C({ id = "strip", cat = "moderation", def = "admin", preset = true,
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do p:StripWeapons() end
		P.Echo(caller, "e_strip", { T = t })
	end })

C({ id = "clearprops", cat = "moderation", def = "moderator", aliases = { "cleanupprops" }, preset = true,
	args = { { type = "player", single = true } },
	run = function(caller, t)
		local n = P.ClearProps(t[1])
		P.Echo(caller, "e_clearprops", { T = t, V = n })
	end })

-- !spectate <player> = their eyes; !spectate alone = free camera; !unspectate (or Backspace) = back
C({ id = "spectate", cat = "moderation", def = "moderator", aliases = { "spec" }, preset = true,
	args = { { type = "player", single = true, higher = true, notself = true, optional = true } },
	run = function(caller, t)
		if not IsValid(caller) then return "err_console" end
		if not caller:Alive() then return "err_dead" end
		P.StartSpectate(caller, t and t[1] or nil)
	end })

C({ id = "unspectate", cat = "moderation", def = "moderator", aliases = { "unspec", "specoff" }, perm = "spectate",
	args = {},
	run = function(caller)
		if not IsValid(caller) then return "err_console" end
		if not P.IsSpectating(caller) then return "err_not_spectating" end
		P.StopSpectate(caller)
	end })

-- ------------------------------------------------------------------ teleport

C({ id = "goto", cat = "teleport", def = "moderator", preset = true,
	args = { { type = "player", single = true, higher = true, notself = true } },
	run = function(caller, t)
		if not IsValid(caller) then return "err_console" end
		local pos = P.FindSpot(t[1])
		if not pos then return "err_no_room" end
		P.SaveReturn(caller)
		caller:SetPos(pos)
		caller:SetEyeAngles((t[1]:GetPos() - pos):Angle())
		P.Echo(caller, "e_goto", { T = t })
	end })

C({ id = "bring", cat = "teleport", def = "moderator", preset = true,
	args = { { type = "player", notself = true } },
	run = function(caller, t)
		if not IsValid(caller) then return "err_console" end
		for _, p in ipairs(t) do
			if p ~= caller then
				local pos = P.FindSpot(caller, p)
				if pos then
					P.SaveReturn(p)
					if p:InVehicle() then p:ExitVehicle() end
					p:SetPos(pos)
					p:SetEyeAngles((caller:GetPos() - pos):Angle())
				end
			end
		end
		P.Echo(caller, "e_bring", { T = t })
	end })

C({ id = "return", cat = "teleport", def = "moderator", preset = true,
	args = { { type = "player", self_default = true, optional = true } },
	run = function(caller, t)
		local n = 0
		for _, p in ipairs(t) do if P.DoReturn(p) then n = n + 1 end end
		if n == 0 then return "err_no_return" end
		P.Echo(caller, "e_return", { T = t })
	end })

C({ id = "tp", cat = "teleport", def = "admin", aliases = { "teleport" },
	args = { { type = "player", self_default = true, optional = true } },
	run = function(caller, t)
		if not IsValid(caller) then return "err_console" end
		local tr = util.TraceLine({ start = caller:EyePos(), endpos = caller:EyePos() + caller:GetAimVector() * 32768, filter = caller })
		local pos = tr.HitPos + tr.HitNormal * 24
		for _, p in ipairs(t) do
			P.SaveReturn(p)
			if p:InVehicle() then p:ExitVehicle() end
			p:SetPos(pos)
			p:SetVelocity(-p:GetVelocity())
		end
		P.Echo(caller, "e_tp", { T = t })
	end })

C({ id = "send", cat = "teleport", def = "admin",
	args = { { type = "player" }, { type = "player", single = true, higher = true, hint = "destination" } },
	run = function(caller, t, dest)
		for _, p in ipairs(t) do
			if p ~= dest[1] then
				local pos = P.FindSpot(dest[1], p)
				if pos then
					P.SaveReturn(p)
					if p:InVehicle() then p:ExitVehicle() end
					p:SetPos(pos)
				end
			end
		end
		P.Echo(caller, "e_send", { T = t, V = dest[1]:Nick() })
	end })
