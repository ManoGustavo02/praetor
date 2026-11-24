-- Praetor: commands created in game with blocks (no code). A custom command has
-- up to three arguments and a script: a list of blocks that run top to bottom.
-- Action blocks do something to the targets; control blocks hold other blocks:
--   if      { cond, body, els }  - with a player condition the targets are split:
--                                  the ones that pass run `body`, the rest `els`
--   each    { body }             - runs `body` once per target ({target} = that one)
--   repeat  { n, body }          - runs `body` n times (max 20)
--   wait    { n }                - pauses n seconds (works inside loops too)
--   stop    {}                   - ends the command
-- Text accepts placeholders: {caller} {target} {1} {2} {3}.
local P = Praetor

P.CustomDefs = P.CustomDefs or {}

local ARG_TYPES = { player = true, number = true, text = true, duration = true }
local MAX_BLOCKS, MAX_DEPTH, MAX_OPS = 80, 4, 400

-- block -> parameter rules
local ACTIONS = {
	msg_all = { text = 200, color = true }, msg_target = { text = 200, color = true }, msg_caller = { text = 200, color = true },
	announce = { text = 200 },
	hp = { n = { 1, 100000 } }, armor = { n = { 0, 100000 } },
	give = { class = true }, strip = {}, slay = {}, respawn = {},
	freeze = { on = true }, god = { on = true }, cloak = { on = true },
	ignite = { n = { 1, 300 } }, extinguish = {},
	bring = {}, ["goto"] = {}, ["return"] = {}, tp_pos = { pos = true },
	launch = { n = { 100, 5000 } }, model = { mdl = true },
	speed = { n = { 0.1, 10 } }, scale = { n = { 0.2, 4 } },
	sound = { path = true },
	kick = { text = 200 }, ban = { min = true, text = 200 }, jail = { min = true }, mute = { min = true },
	setjob = { job = true }, money = { n = { -1e9, 1e9 } },
	run = { text = 250 },
	wait = { n = { 0.1, 60 } },
	console = { text = 250 },
	-- control blocks
	["if"] = { cond = true, body = true, els = true },
	each = { body = true },
	["repeat"] = { n = { 1, 20 }, int = true, body = true },
	stop = {},
}
P.CustomActions = ACTIONS

-- conditions of the "if" block (all but chance / arg_set look at each target)
local CONDS = {
	alive = {}, dead = {}, staff = {}, is_caller = {},
	rank = { rank = true },
	hp_below = { n = { 1, 100000 } }, armor_below = { n = { 0, 100000 } },
	money_atleast = { n = { 0, 1e12 } }, job = { job = true },
	chance = { n = { 1, 100 } }, arg_set = { i = true },
}
local GLOBAL_COND = { chance = true, arg_set = true }
P.CustomConds = CONDS

local function cleanCond(c)
	if not istable(c) or not CONDS[c.k] then return { k = "alive" } end
	local rule = CONDS[c.k]
	local out = { k = c.k, neg = c.neg == true or nil }
	if rule.n then out.n = math.Clamp(tonumber(c.n) or rule.n[1], rule.n[1], rule.n[2]) end
	if rule.i then out.i = math.Clamp(math.floor(tonumber(c.i) or 1), 1, 3) end
	if rule.rank then out.rank = (isstring(c.rank) and P.Ranks[c.rank]) and c.rank or "user" end
	if rule.job then out.job = P.Str(c.job or "", 40) end
	return out
end

local cleanList

local function cleanAction(a, owner, depth, count)
	if not istable(a) or not ACTIONS[a.t] then return nil end
	local rule = ACTIONS[a.t]
	if a.t == "console" and not owner then return nil, "err_owner_only" end
	local out = { t = a.t }
	if rule.text then out.text = P.Str(a.text, rule.text) end
	if rule.color then out.c = P.ColorTable(P.ReadColor(a.c, Color(232, 194, 122))) end
	if rule.n then
		out.n = math.Clamp(tonumber(a.n) or rule.n[1], rule.n[1], rule.n[2])
		if rule.int then out.n = math.floor(out.n) end
	end
	if rule.on then out.on = a.on ~= false end
	if rule.class then out.class = tostring(a.class or ""):lower():match("^[%w_%-%.]+$") or "weapon_crowbar" end
	if rule.mdl then out.mdl = tostring(a.mdl or ""):lower():gsub("\\", "/"):match("^[%w_%-%./]+%.mdl$") or "" end
	if rule.path then out.path = tostring(a.path or ""):lower():gsub("\\", "/"):match("^[%w_%-%./]+%.[mwo][pag][3vg]$") or "" end
	if rule.min then out.min = math.Clamp(math.floor(tonumber(a.min) or 0), 0, 5256000) end
	if rule.job then out.job = P.Str(a.job, 40) end
	if rule.pos then
		local p = istable(a.pos) and a.pos or {}
		out.pos = { math.Clamp(tonumber(p[1]) or 0, -32768, 32768), math.Clamp(tonumber(p[2]) or 0, -32768, 32768), math.Clamp(tonumber(p[3]) or 0, -32768, 32768) }
	end
	if rule.cond then out.cond = cleanCond(a.cond) end
	if rule.body then
		if depth >= MAX_DEPTH then return nil, "err_cu_depth" end
		local body, err = cleanList(a.body, owner, depth + 1, count)
		if err then return nil, err end
		out.body = body
	end
	if rule.els then
		local els, err = cleanList(a.els, owner, depth + 1, count)
		if err then return nil, err end
		if #els > 0 then out.els = els end
	end
	return out
end

cleanList = function(list, owner, depth, count)
	local out = {}
	if not istable(list) then return out end
	for i = 1, #list do
		count.n = count.n + 1
		if count.n > MAX_BLOCKS then return nil, "err_cu_big" end
		local act, err = cleanAction(list[i], owner, depth, count)
		if err then return nil, err end
		if act then out[#out + 1] = act end
	end
	return out
end

-- true when a script (or any block inside it) uses the server console
local function hasConsole(list)
	for _, a in ipairs(list or {}) do
		if a.t == "console" or hasConsole(a.body) or hasConsole(a.els) then return true end
	end
	return false
end
P.CustomHasConsole = hasConsole

function P.CleanCustom(d, owner)
	if not istable(d) then return nil, "err_internal" end
	local id = tostring(d.id or ""):lower():gsub("[^%w_]", "")
	if #id < 2 or #id > 24 then return nil, "err_cmd_name" end
	local existing = P.Commands[id]
	if existing and not existing.custom then return nil, "err_cmd_exists" end
	local out = {
		id = id,
		help = P.Str(d.help or "", 120),
		def = P.Ranks[d.def] and d.def or "superadmin",
		icon = isstring(d.icon) and d.icon:match("^[%w_]+$") and #d.icon <= 32 and d.icon or "wrench",
		args = {},
		silent = d.silent == true,
	}
	for i = 1, math.min(#(d.args or {}), 3) do
		local a = d.args[i]
		if istable(a) and ARG_TYPES[a.type] then
			out.args[#out.args + 1] = { type = a.type, hint = P.Str(a.hint or a.type, 20), optional = a.optional == true, default = a.type == "number" and (tonumber(a.default) or 0) or (a.type == "duration" and (tonumber(a.default) or 0)) or (a.type == "text" and P.Str(a.default or "", 100)) or nil }
		end
	end
	local count = { n = 0 }
	local actions, err = cleanList(d.actions, owner, 1, count)
	if err then return nil, err end
	if count.n == 0 or #actions == 0 then return nil, "err_cmd_empty" end
	out.actions = actions
	out.blocks = count.n
	return out
end

local function fill(text, caller, target, vals)
	return (tostring(text or ""):gsub("{(%w+)}", function(k)
		if k == "caller" then return P.NameOf(caller) end
		if k == "target" then return IsValid(target) and target:Nick() or "" end
		local n = tonumber(k)
		if n then
			local v = vals[n]
			if istable(v) then
				local names = {}
				for _, p in ipairs(v) do if IsValid(p) then names[#names + 1] = p:Nick() end end
				return table.concat(names, ", ")
			end
			return v ~= nil and tostring(v) or ""
		end
	end))
end

local depth = 0

local function runAction(a, caller, targets, vals)
	local t = a.t
	if t == "msg_all" then P.ChatTo(nil, P.ReadColor(a.c, P.Col.bronzeL), fill(a.text, caller, targets[1], vals)) return end
	if t == "msg_caller" then if IsValid(caller) then P.ChatTo(caller, P.ReadColor(a.c, P.Col.bronzeL), fill(a.text, caller, targets[1], vals)) end return end
	if t == "announce" then P.Send(nil, "announce", { t = fill(a.text, caller, targets[1], vals), n = P.NameOf(caller) }) return end
	if t == "run" then
		if depth > 3 then return end
		depth = depth + 1
		P.RunLine(caller, fill(a.text, caller, targets[1], vals), true)
		depth = depth - 1
		return
	end
	if t == "console" then
		local line = fill(a.text, caller, targets[1], vals)
		local first = (P.SplitArgs(line)[1] or ""):lower()
		if first == "praetor_owner" or first == "rcon_password" or first == "lua_run" then return end
		game.ConsoleCommand(line .. "\n")
		return
	end

	for _, p in ipairs(targets) do
		if IsValid(p) then
			if t == "msg_target" then P.ChatTo(p, P.ReadColor(a.c, P.Col.bronzeL), fill(a.text, caller, p, vals))
			elseif t == "hp" then if a.n > p:GetMaxHealth() then p:SetMaxHealth(a.n) end p:SetHealth(a.n)
			elseif t == "armor" then p:SetArmor(a.n)
			elseif t == "give" then p:Give(a.class)
			elseif t == "strip" then p:StripWeapons()
			elseif t == "slay" then if p:Alive() then p:Kill() end
			elseif t == "respawn" then p:Spawn()
			elseif t == "freeze" then P.Freeze(p, a.on)
			elseif t == "god" then P.SetGod(p, a.on)
			elseif t == "cloak" then P.SetCloak(p, a.on)
			elseif t == "ignite" then p:Ignite(a.n)
			elseif t == "extinguish" then p:Extinguish()
			elseif t == "bring" and IsValid(caller) and p ~= caller then
				local pos = P.FindSpot(caller, p)
				if pos then P.SaveReturn(p) p:SetPos(pos) end
			elseif t == "goto" and IsValid(caller) and p ~= caller then
				local pos = P.FindSpot(p, caller)
				if pos then P.SaveReturn(caller) caller:SetPos(pos) end
			elseif t == "return" then P.DoReturn(p)
			elseif t == "tp_pos" then P.SaveReturn(p) p:SetPos(Vector(a.pos[1], a.pos[2], a.pos[3]))
			elseif t == "launch" then p:SetVelocity(Vector(0, 0, a.n))
			elseif t == "model" and a.mdl ~= "" and util.IsValidModel(a.mdl) then p:SetModel(a.mdl)
			elseif t == "speed" then P.SetSpeed(p, a.n)
			elseif t == "scale" then P.SetScale(p, a.n)
			elseif t == "sound" and a.path ~= "" then p:EmitSound(a.path)
			elseif t == "kick" and P.CanTarget(caller, p) then p:Kick(fill(a.text, caller, p, vals))
			elseif t == "ban" and P.CanTarget(caller, p) and P.CheckBanLimit(caller, a.min) then
				P.AddBan(p:SteamID64(), p:Nick(), a.min, fill(a.text, caller, p, vals), caller)
			elseif t == "jail" then P.Jail(p, a.min, caller)
			elseif t == "mute" then P.SetMute(p, a.min, caller)
			elseif t == "setjob" and P.IsDarkRP() then
				local _, idx = P.JobByCommand(a.job)
				if idx then p:changeTeam(idx, true, true) end
			elseif t == "money" and P.IsDarkRP() then p:addMoney(a.n)
			end
		end
	end
end

local function condPasses(c, caller, p, vals)
	local k, r = c.k, false
	if k == "chance" then r = math.random(1, 100) <= (c.n or 50)
	elseif k == "arg_set" then
		local v = vals[c.i or 1]
		r = v ~= nil and v ~= "" and not (istable(v) and #v == 0)
	elseif IsValid(p) then
		if k == "alive" then r = p:Alive()
		elseif k == "dead" then r = not p:Alive()
		elseif k == "staff" then r = P.IsStaff(p)
		elseif k == "is_caller" then r = p == caller
		elseif k == "rank" then
			local rk = P.Ranks[c.rank or "user"]
			r = P.Authority(p) >= (rk and rk.immunity or 0)
		elseif k == "hp_below" then r = p:Health() < c.n
		elseif k == "armor_below" then r = p:Armor() < c.n
		elseif k == "money_atleast" then r = P.IsDarkRP() and p.getDarkRPVar ~= nil and (tonumber(p:getDarkRPVar("money")) or 0) >= c.n
		elseif k == "job" and P.IsDarkRP() then
			local _, idx = P.JobByCommand(c.job)
			r = idx ~= nil and p:Team() == idx
		end
	end
	if c.neg then r = not r end
	return r == true
end

-- walks a list of blocks; runs inside a coroutine so "wait" can pause anywhere
local function execList(list, ctx, targets)
	for _, a in ipairs(list or {}) do
		if ctx.stop then return end
		ctx.ops = ctx.ops + 1
		if ctx.ops > MAX_OPS then ctx.stop = true return end
		local t = a.t
		if t == "wait" then
			coroutine.yield(a.n)
		elseif t == "stop" then
			ctx.stop = true
			return
		elseif t == "if" then
			local c = a.cond or { k = "alive" }
			if GLOBAL_COND[c.k] then
				if condPasses(c, ctx.caller, targets[1], ctx.vals) then execList(a.body, ctx, targets)
				else execList(a.els, ctx, targets) end
			else
				local yes, no = {}, {}
				for _, p in ipairs(targets) do
					if condPasses(c, ctx.caller, p, ctx.vals) then yes[#yes + 1] = p else no[#no + 1] = p end
				end
				if #yes > 0 then execList(a.body, ctx, yes) end
				if #no > 0 and a.els then execList(a.els, ctx, no) end
			end
		elseif t == "each" then
			for _, p in ipairs(targets) do
				if ctx.stop then return end
				if IsValid(p) then execList(a.body, ctx, { p }) end
			end
		elseif t == "repeat" then
			for _ = 1, a.n or 1 do
				if ctx.stop then return end
				execList(a.body, ctx, targets)
			end
		else
			local ok, err = pcall(runAction, a, ctx.caller, targets, ctx.vals)
			if not ok then MsgC(Color(220, 80, 80), "[Praetor] custom command ", ctx.id, ": ", tostring(err), "\n") end
		end
	end
end

local function runScript(d, caller, targets, vals)
	local ctx = { id = d.id, caller = caller, vals = vals, ops = 0 }
	local co = coroutine.create(function() execList(d.actions, ctx, targets) end)
	local function resume()
		local ok, wait = coroutine.resume(co)
		if not ok then
			MsgC(Color(220, 80, 80), "[Praetor] custom command ", d.id, ": ", tostring(wait), "\n")
			return
		end
		if coroutine.status(co) ~= "dead" then timer.Simple(tonumber(wait) or 0.1, resume) end
	end
	resume()
end

local function register(d)
	local def = {
		id = d.id, cat = "custom", def = d.def, custom = true, helpText = d.help, icon = d.icon,
		args = table.Copy(d.args),
		run = function(caller, ...)
			local vals = { ... }
			local targets = (d.args[1] and d.args[1].type == "player" and istable(vals[1])) and vals[1] or { caller }
			runScript(d, caller, targets, vals)
			if not d.silent then
				P.Echo(caller, "e_custom", { V = d.id, T = (d.args[1] and d.args[1].type == "player") and targets or nil })
			end
		end,
	}
	P.AddCommand(def)
	if P.Perms[d.id] then P.Perms[d.id].def = d.def end
end

function P.LoadCustom()
	P.CustomDefs = {}
	for _, d in ipairs(P.DB.Get("customcmds", {})) do
		local c = P.CleanCustom(d, true)
		if c then
			P.CustomDefs[c.id] = c
			register(c)
		end
	end
end

local function save()
	local list = {}
	for _, d in pairs(P.CustomDefs) do list[#list + 1] = d end
	P.DB.Set("customcmds", list)
end

P.Receive("custom_list", { perm = "manage_commands", rate = 3 }, function(ply)
	local list = {}
	for _, d in pairs(P.CustomDefs) do list[#list + 1] = d end
	P.Send(ply, "custom_list", { list = list })
end)

P.Receive("custom_save", { perm = "manage_commands", rate = 1, max = 65536 }, function(ply, data)
	local d, err = P.CleanCustom(data.d, P.IsOwner(ply))
	if not d then P.Notify(ply, err or "err_internal") return end
	-- editing a command that has a console block needs an owner too
	local old = P.CustomDefs[d.id]
	if old and not P.IsOwner(ply) and hasConsole(old.actions) then P.Notify(ply, "err_owner_only") return end
	if not P.CanManageRank(ply, d.def) and d.def ~= "user" then P.Notify(ply, "err_rank_authority") return end
	-- renaming: the editor sends the old name, which is removed
	local was = isstring(data.was) and data.was or nil
	-- a new command (or a rename) must not overwrite another custom command
	if old and was ~= d.id then P.Notify(ply, "err_cu_taken", { S = d.id }) return end
	if was and was ~= d.id and P.CustomDefs[was] then
		if hasConsole(P.CustomDefs[was].actions) and not P.IsOwner(ply) then P.Notify(ply, "err_owner_only") return end
		P.CustomDefs[was] = nil
		P.RemoveCommand(was)
	end
	if old then P.RemoveCommand(d.id) end
	P.CustomDefs[d.id] = d
	register(d)
	save()
	P.Log("settings", "l_custom_save", { A = P.LogPly(ply), V = d.id }, { ply })
	P.SyncAll()
	P.Notify(ply, "ok_saved", nil, "ok")
	P.Send(ply, "custom_saved", { id = d.id })
end)

P.Receive("custom_delete", { perm = "manage_commands", rate = 2 }, function(ply, data)
	local id = isstring(data.id) and data.id or ""
	local d = P.CustomDefs[id]
	if not d then return end
	if hasConsole(d.actions) and not P.IsOwner(ply) then P.Notify(ply, "err_owner_only") return end
	P.CustomDefs[id] = nil
	P.RemoveCommand(id)
	save()
	P.Log("settings", "l_custom_delete", { A = P.LogPly(ply), V = id }, { ply })
	P.SyncAll()
	P.Notify(ply, "ok_removed", nil, "ok")
end)
