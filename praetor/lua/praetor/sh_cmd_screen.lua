-- Praetor: !screengrab <player> - a picture of what the player sees (sv_screengrab).
local P = Praetor

P.AddCommand({ id = "screengrab", cat = "player", def = "admin", aliases = { "sg", "printscreen", "screenshot" },
	args = { { type = "player", single = true, self_default = false } },
	run = function(caller, t)
		local ply = t and t[1]
		if not IsValid(ply) then return "err_no_target" end
		local ok, err, args = P.ScreenGrab(caller, ply)
		if not ok then
			if err then P.Notify(caller, err, args) end
			return
		end
		P.Notify(caller, "n_sg_wait", { S = ply:Nick() })
	end,
})
