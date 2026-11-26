-- Praetor: support room commands.
--  !sit [player] [player]  takes them (and you) to a support room. With no
--                          names: the players of the Blackbox case / Praetor
--                          report you claimed.
--  !endsit                 everyone goes back to where they were.
--  !setsit [name]          saves the spot you stand on as a room of this map.
local P = Praetor
local C = P.AddCommand

C({ id = "sit", cat = "teleport", def = "moderator", aliases = { "atendimento", "sala" },
	args = { { type = "player", optional = true, notself = true }, { type = "player", optional = true, notself = true } },
	run = function(caller, a, b)
		if not IsValid(caller) then return "err_console" end
		if P.NeedDuty and P.NeedDuty(caller) then return end
		local list, seen = {}, {}
		for _, t in ipairs({ a or {}, b or {} }) do
			for _, p in ipairs(t) do
				if IsValid(p) and p ~= caller and not seen[p] then
					if not P.CanTarget(caller, p) then return "err_authority" end
					seen[p] = true
					list[#list + 1] = p
				end
			end
		end
		local opts = {}
		if #list == 0 then
			local auto, o = P.SitClaimedFor(caller)
			if not auto then return "err_sit_who" end
			list, opts = auto, o
		end
		if #list > 8 then return "err_sit_many" end
		local ok, err, eargs = P.StartSit(caller, list, opts)
		if not ok then
			if err then P.Notify(caller, err, eargs) end
			return
		end
		P.Echo(caller, "e_sit", { T = #list > 0 and list or { caller } })
	end })

C({ id = "endsit", cat = "teleport", def = "moderator", perm = "sit", aliases = { "stopsit", "fimsala" },
	args = {},
	run = function(caller)
		local sit = P.SitOf(caller)
		if not sit then return "err_sit_none" end
		P.EndSit(sit, caller)
		P.Echo(caller, "e_endsit", {})
	end })

C({ id = "setsit", cat = "teleport", def = "admin", perm = "manage_sits", aliases = { "addsit" },
	args = { { type = "text", hint = "name", optional = true, default = "" } },
	run = function(caller, name)
		if not IsValid(caller) then return "err_console" end
		local ok, res = P.AddSitRoom(caller, name)
		if not ok then P.Notify(caller, res, { V = 10 }) return end
		P.Notify(caller, "n_sit_room_saved", { S = res }, "ok")
	end })
