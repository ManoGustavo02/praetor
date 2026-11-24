-- Praetor: player and fun commands.
local P = Praetor
local C = P.AddCommand

local function selfArg() return { type = "player", self_default = true, optional = true } end

C({ id = "hp", cat = "player", def = "admin", aliases = { "health", "sethealth" },
	args = { selfArg(), { type = "number", hint = "amount", min = 1, max = 100000, optional = true, default = 100 } },
	run = function(caller, t, n)
		for _, p in ipairs(t) do
			if n > p:GetMaxHealth() then p:SetMaxHealth(n) end
			p:SetHealth(n)
		end
		P.Echo(caller, "e_hp", { T = t, V = n })
	end })

C({ id = "armor", cat = "player", def = "admin", aliases = { "armour", "setarmor" },
	args = { selfArg(), { type = "number", hint = "amount", min = 0, max = 100000, optional = true, default = 100 } },
	run = function(caller, t, n)
		for _, p in ipairs(t) do
			if p.SetMaxArmor and n > p:GetMaxArmor() then p:SetMaxArmor(n) end
			p:SetArmor(n)
		end
		P.Echo(caller, "e_armor", { T = t, V = n })
	end })

C({ id = "god", cat = "player", def = "admin", preset = true,
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetGod(p, true) end
		P.Echo(caller, "e_god", { T = t })
	end })

C({ id = "ungod", cat = "player", def = "admin",
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetGod(p, false) end
		P.Echo(caller, "e_ungod", { T = t })
	end })

C({ id = "cloak", cat = "player", def = "admin", aliases = { "invisible" },
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetCloak(p, true) end
		P.Echo(caller, "e_cloak", { T = t })
	end })

C({ id = "uncloak", cat = "player", def = "admin", aliases = { "visible" },
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do P.SetCloak(p, false) end
		P.Echo(caller, "e_uncloak", { T = t })
	end })

C({ id = "noclip", cat = "player", def = "admin",
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do
			if p:GetMoveType() == MOVETYPE_NOCLIP then p:SetMoveType(MOVETYPE_WALK)
			else p:SetMoveType(MOVETYPE_NOCLIP) end
		end
		P.Echo(caller, "e_noclip", { T = t })
	end })

C({ id = "respawn", cat = "player", def = "moderator", aliases = { "spawn" }, preset = true,
	args = { selfArg() },
	run = function(caller, t)
		for _, p in ipairs(t) do
			if P.IsJailed and P.IsJailed(p) then P.Unjail(p, caller) end
			p:Spawn()
		end
		P.Echo(caller, "e_respawn", { T = t })
	end })

-- !give weapon_ar2 bob,alice   (the player list is optional: without it you get the weapon)
C({ id = "give", cat = "player", def = "superadmin", aliases = { "giveweapon", "weapon" },
	args = { { type = "class", hint = "weapon" }, selfArg() },
	run = function(caller, class, t)
		local w = weapons.GetStored(class) or list.Get("Weapon")[class]
		if not w and not class:match("^weapon_") and not class:match("^item_") then return "err_class" end
		for _, p in ipairs(t) do p:Give(class) end
		P.Echo(caller, "e_give", { T = t, V = class })
	end })

C({ id = "model", cat = "player", def = "admin", aliases = { "setmodel" },
	args = { selfArg(), { type = "model", hint = "model" } },
	run = function(caller, t, mdl)
		if not util.IsValidModel(mdl) then return "err_model" end
		for _, p in ipairs(t) do p:SetModel(mdl) end
		P.Echo(caller, "e_model", { T = t, V = mdl })
	end })

C({ id = "speed", cat = "player", def = "admin", aliases = { "runspeed" },
	args = { selfArg(), { type = "number", hint = "multiplier", min = 0.1, max = 10, round = false, optional = true, default = 1 } },
	run = function(caller, t, mult)
		for _, p in ipairs(t) do P.SetSpeed(p, mult) end
		P.Echo(caller, "e_speed", { T = t, V = math.Round(mult, 2) })
	end })

C({ id = "scale", cat = "player", def = "admin", aliases = { "size" },
	args = { selfArg(), { type = "number", hint = "size", min = 0.2, max = 4, round = false, optional = true, default = 1 } },
	run = function(caller, t, s)
		for _, p in ipairs(t) do P.SetScale(p, s) end
		P.Echo(caller, "e_scale", { T = t, V = math.Round(s, 2) })
	end })

-- ------------------------------------------------------------------ fun

C({ id = "slap", cat = "fun", def = "admin",
	args = { { type = "player" }, { type = "number", hint = "damage", min = 0, max = 10000, optional = true, default = 0 } },
	run = function(caller, t, dmg)
		for _, p in ipairs(t) do
			if p:Alive() then
				local dir = VectorRand()
				dir.z = math.abs(dir.z) + 0.6
				p:SetVelocity(dir:GetNormalized() * 420)
				p:ViewPunch(Angle(math.Rand(-15, 15), math.Rand(-15, 15), 0))
				p:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav")
				if dmg > 0 then p:TakeDamage(dmg, IsValid(caller) and caller or game.GetWorld()) end
			end
		end
		P.Echo(caller, dmg > 0 and "e_slap_d" or "e_slap", { T = t, V = dmg })
	end })

C({ id = "launch", cat = "fun", def = "admin", aliases = { "rocket" },
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do
			if p:Alive() then
				if p:GetMoveType() == MOVETYPE_NOCLIP then p:SetMoveType(MOVETYPE_WALK) end
				p:SetVelocity(Vector(0, 0, 1400))
				p:EmitSound("weapons/rpg/rocketfire1.wav")
				local e = EffectData()
				e:SetOrigin(p:GetPos())
				util.Effect("ThumperDust", e)
			end
		end
		P.Echo(caller, "e_launch", { T = t })
	end })

C({ id = "ignite", cat = "fun", def = "admin", aliases = { "burn" },
	args = { { type = "player" }, { type = "number", hint = "seconds", min = 1, max = 300, optional = true, default = 10 } },
	run = function(caller, t, secs)
		for _, p in ipairs(t) do p:Ignite(secs) end
		P.Echo(caller, "e_ignite", { T = t, V = secs })
	end })

C({ id = "extinguish", cat = "fun", def = "admin", aliases = { "unignite" },
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do p:Extinguish() end
		P.Echo(caller, "e_extinguish", { T = t })
	end })

C({ id = "blind", cat = "fun", def = "admin",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do p:SetNW2Bool("pr_blind", true) end
		P.Echo(caller, "e_blind", { T = t })
	end })

C({ id = "unblind", cat = "fun", def = "admin",
	args = { { type = "player" } },
	run = function(caller, t)
		for _, p in ipairs(t) do p:SetNW2Bool("pr_blind", false) end
		P.Echo(caller, "e_unblind", { T = t })
	end })
