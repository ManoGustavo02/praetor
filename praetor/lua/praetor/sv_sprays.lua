-- Praetor: player sprays (the image a player paints on walls with the spray key).
--  * Every spray is remembered (one per player, the newest): who, where and when.
--    Staff with spray_info see whose spray they are looking at.
--  * !sprayban / !unsprayban block a player's sprays; the block survives rejoins.
--  * !cleardecals (also !clearsprays) wipes every spray and mark on the map.
--  * Settings > Moderation > "Allow sprays" turns sprays off for everyone.
local P = Praetor

P.Sprays = P.Sprays or {}
P.SprayBans = P.DB.Get("spraybans", {}) or {}

local function save() P.DB.Set("spraybans", P.SprayBans) end

local function packed()
	local list = {}
	for sid, s in pairs(P.Sprays) do
		list[#list + 1] = {
			s = sid, n = s.name, t = s.t,
			p = { math.Round(s.pos.x, 1), math.Round(s.pos.y, 1), math.Round(s.pos.z, 1) },
			nr = { math.Round(s.normal.x, 2), math.Round(s.normal.y, 2), math.Round(s.normal.z, 2) },
		}
	end
	return list
end

local function push(target)
	target = target or P.WithPerm("spray_info")
	if istable(target) and #target == 0 then return end
	P.Send(target, "sprays", { list = packed() })
end

function P.ClearSprays()
	P.Sprays = {}
	push()
end

function P.IsSprayBanned(ply)
	return IsValid(ply) and P.SprayBans[P.SIDOf(ply)] ~= nil
end

function P.SetSprayBan(ply, on, actor)
	local sid = P.SIDOf(ply)
	if on then
		P.SprayBans[sid] = { n = ply:Nick(), by = IsValid(actor) and actor:Nick() or "Console", t = os.time() }
	else
		P.SprayBans[sid] = nil
	end
	ply:SetNW2Bool("pr_sprayban", on and true or false)
	save()
	P.Log("punish", on and "l_sprayban" or "l_unsprayban", { A = P.LogPly(actor), T = P.LogPly(ply) }, { actor, ply })
end

hook.Add("PlayerSpray", "Praetor.Sprays", function(ply)
	if P.Setting("sprays") == false then return true end
	if ply:GetNW2Bool("pr_sprayban", false) or P.IsSprayBanned(ply) then
		if (ply.PraetorSprayWarn or 0) < CurTime() then
			ply.PraetorSprayWarn = CurTime() + 5
			P.Notify(ply, "err_spray_banned", nil, "warn")
		end
		return true
	end
	-- the same trace the game uses to place the spray
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 128,
		filter = ply,
		mask = MASK_SOLID_BRUSHONLY,
	})
	if not tr.Hit then return end
	local sid = P.SIDOf(ply)
	P.Sprays[sid] = { pos = tr.HitPos, normal = tr.HitNormal, name = ply:Nick(), t = os.time() }
	push()
	P.Log("player", "l_spray", { A = P.LogPly(ply) }, { ply })
end)

hook.Add("PlayerInitialSpawn", "Praetor.Sprays", function(ply)
	timer.Simple(6, function()
		if not IsValid(ply) then return end
		if P.SprayBans[P.SIDOf(ply)] then ply:SetNW2Bool("pr_sprayban", true) end
		if P.Has(ply, "spray_info") and next(P.Sprays) then push(ply) end
	end)
end)

-- the map's decals are gone after a cleanup
hook.Add("PostCleanupMap", "Praetor.Sprays", function() P.ClearSprays() end)
