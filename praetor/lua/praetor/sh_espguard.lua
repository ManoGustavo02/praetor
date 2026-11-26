-- Praetor: keeps staff on duty and cloaked players out of Expression 2 and Starfall
-- chips, so "ESP" chips can't find or follow them.
--
-- Nothing in Wiremod or Starfall is edited. Praetor only wraps, from the outside:
--  * E2: the functions that list players / find entities drop hidden players, the
--    functions that return an entity give NULL for them, the entity functions that
--    return a position give 0,0,0 and holograms / EGP can't be parented to them.
--  * Starfall (server and client chips): find.*, team.getPlayers, player(n) and
--    entity(n) drop them, and entity methods that return a position give 0,0,0.
-- The hidden player's own chips and staff who could cloak them still see them.
--
-- On the server it also notes, per chip, which other players the chip reads the
-- position of and whether it parents holograms to a player. sv_chips uses that
-- to point out chips that behave like an ESP / aimbot.
local P = Praetor

-- ------------------------------------------------------------------ who is hidden
-- refreshed four times a second; the wrappers only do a table lookup
local hidden, anyHidden = {}, false
local isPly = {}

-- chip entity -> { [player] = true } players whose position the chip read
P.ChipEspHits = P.ChipEspHits or setmetatable({}, { __mode = "k" })
-- chip entity -> true when it parented a hologram / EGP object to a player
P.ChipHoloPly = P.ChipHoloPly or setmetatable({}, { __mode = "k" })

local function note(chip, target, owner)
	if not isPly[target] or target == owner or not IsValid(chip) then return end
	local h = P.ChipEspHits[chip]
	if not h then h = {} P.ChipEspHits[chip] = h end
	h[target] = true
end
local function noteHolo(chip, target, owner)
	if isPly[target] and target ~= owner and IsValid(chip) then P.ChipHoloPly[chip] = true end
end

function P.EspHidden(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if P.Setting("esp_block") == false then return false end
	return ply:GetNW2Bool("pr_cloak", false) or ply:GetNW2Bool("pr_duty", false)
end

-- true when the chips of `viewer` must not see `ply`
function P.EspHiddenFrom(ply, viewer)
	if not hidden[ply] then return false end
	if viewer == ply then return false end
	if IsValid(viewer) and viewer:IsPlayer() and P.Has(viewer, "cloak") and P.CanTarget(viewer, ply) then return false end
	return true
end

local function refresh()
	local t, any, pl = {}, false, {}
	for _, p in player.Iterator() do
		pl[p] = true
		if P.EspHidden(p) then t[p] = true any = true end
	end
	hidden, anyHidden, isPly = t, any, pl
end
timer.Create("Praetor.EspGuard", 0.25, 0, refresh)

-- ------------------------------------------------------------------ Expression 2
if SERVER then
	local mine = setmetatable({}, { __mode = "k" }) -- wrappers already made (no double wrapping)

	local LISTS = { ["players()"] = true, ["playersAdmins()"] = true, ["playersSuperAdmins()"] = true, ["teamMembers(n)"] = true }
	local FINDS = {
		["findInSphere(vn)"] = true, ["findInCone(vvnn)"] = true, ["findInBox(vv)"] = true,
		["findByName(s)"] = true, ["findByModel(s)"] = true, ["findByClass(s)"] = true,
	}

	local function wrap(sig, ret, fn)
		local name = sig:match("^([%w_]+)%(")
		if not name then return end
		local method = sig:find("(e:", 1, true) ~= nil

		if LISTS[sig] then
			return function(self, args, types)
				local r = fn(self, args, types)
				if not anyHidden or not istable(r) then return r end
				local out = {}
				for _, v in ipairs(r) do
					if not P.EspHiddenFrom(v, self.player) then out[#out + 1] = v end
				end
				return out
			end
		end

		if FINDS[sig] then
			return function(self, args, types)
				local n = fn(self, args, types)
				local list = self.data and self.data.findlist
				if not anyHidden or not isnumber(n) or n <= 0 or not istable(list) then return n end
				for i = #list, 1, -1 do
					if P.EspHiddenFrom(list[i], self.player) then table.remove(list, i) end
				end
				return #list
			end
		end

		-- holograms and EGP objects can't follow a hidden player
		if name:find("^holoParent") or name:find("^egpParent") then
			return function(self, args, types)
				for _, v in ipairs(args) do
					noteHolo(self.entity, v, self.player)
					if anyHidden and P.EspHiddenFrom(v, self.player) then return end
				end
				return fn(self, args, types)
			end
		end

		if ret == "e" then
			return function(self, args, types)
				local r = fn(self, args, types)
				if anyHidden and P.EspHiddenFrom(r, self.player) then return NULL end
				return r
			end
		end

		if method and ret == "v" then
			return function(self, args, types)
				local e = args[1]
				if isPly[e] then
					note(self.entity, e, self.player)
					if anyHidden and P.EspHiddenFrom(e, self.player) then return Vector(0, 0, 0) end
				end
				return fn(self, args, types)
			end
		end
	end

	function P.EspGuardE2()
		local funcs = wire_expression2_funcs
		if not istable(funcs) then return end
		local n = 0
		for sig, data in pairs(funcs) do
			local fn = istable(data) and data[3]
			-- only functions made for the current E2 compiler: they get (context, values, types)
			if isfunction(fn) and not mine[fn] and isstring(sig) and sig:sub(1, 3) ~= "op:"
				and not (istable(data.attributes) and data.attributes.legacy) then
				local w = wrap(sig, data[2], fn)
				if w then
					mine[w] = true
					data[3] = w
					n = n + 1
				end
			end
		end
		if n > 0 then MsgN("[Praetor] E2 guard: ", n, " functions protected") end
	end

	-- E2 builds its function list when it loads (and on wire_expression2_reload);
	-- chips compile after that, so the wrapped functions are the ones they use
	hook.Add("Expression2_PostLoadExtensions", "Praetor.EspGuard", function() timer.Simple(0, P.EspGuardE2) end)
	hook.Add("Initialize", "Praetor.EspGuard", function() timer.Simple(0, P.EspGuardE2) end)
	if wire_expression2_funcs then P.EspGuardE2() end
end

-- ------------------------------------------------------------------ Starfall
-- every chip instance gets its own copy of the libraries; they are wrapped right
-- after the chip is compiled, before any of its code runs
-- entity methods that tell where a player is (used to spot ESP chips)
local SF_POS = {
	getPos = true, getShootPos = true, getEyePos = true, obbCenterW = true, worldSpaceCenter = true,
	localToWorld = true, getBonePosition = true, getAttachment = true, getNearestPoint = true,
}
local SF_FIND = { "inBox", "inSphere", "inCone", "inRay", "byClass", "byName", "byModel", "inPVS", "allPlayers", "all" }

hook.Add("StarfallPostInstanceCompile", "Praetor.EspGuard", function(inst)
	if not istable(inst) or not istable(inst.Types) or not isfunction(inst.UnwrapObject) then return end
	local viewer = inst.player
	local chip = inst.entity
	local unwrap = inst.UnwrapObject
	local T = inst.Types

	local function hid(o)
		if not anyHidden or o == nil then return false end
		local ok, e = pcall(unwrap, o)
		return ok and P.EspHiddenFrom(e, viewer)
	end
	local function keep(list)
		if not anyHidden or not istable(list) then return list end
		local out = {}
		for i = 1, #list do
			if not hid(list[i]) then out[#out + 1] = list[i] end
		end
		return out
	end

	local libs = inst.Libraries or {}
	if istable(libs.find) then
		for _, k in ipairs(SF_FIND) do
			local f = libs.find[k]
			if isfunction(f) then libs.find[k] = function(...) return keep(f(...)) end end
		end
	end
	if istable(libs.team) and isfunction(libs.team.getPlayers) then
		local f = libs.team.getPlayers
		libs.team.getPlayers = function(...) return keep(f(...)) end
	end

	local env = inst.env
	if istable(env) then
		for _, k in ipairs({ "player", "entity" }) do
			local f = env[k]
			if isfunction(f) then
				env[k] = function(...)
					local r = f(...)
					if hid(r) then return nil end
					return r
				end
			end
		end
	end

	-- positions read from a hidden player come back as 0,0,0
	local vwrap = istable(T.Vector) and T.Vector.Wrap
	local function zero(...)
		local n = select("#", ...)
		if n == 0 or not vwrap then return ... end
		local r = { ... }
		for i = 1, n do
			if getmetatable(r[i]) == "Vector" then r[i] = vwrap(Vector(0, 0, 0)) end
		end
		return unpack(r, 1, n)
	end
	local function guard(methods)
		if not istable(methods) then return end
		for k, f in pairs(methods) do
			if isfunction(f) then
				if k == "setParent" then
					methods[k] = function(self, parent, ...)
						if SERVER and parent ~= nil then
							local ok, e = pcall(unwrap, parent)
							if ok then noteHolo(chip, e, viewer) end
						end
						if hid(parent) then return end
						return f(self, parent, ...)
					end
				elseif SERVER and SF_POS[k] then
					methods[k] = function(self, ...)
						local ok, e = pcall(unwrap, self)
						if ok and isPly[e] then
							note(chip, e, viewer)
							if anyHidden and P.EspHiddenFrom(e, viewer) then return zero(f(self, ...)) end
						end
						return f(self, ...)
					end
				else
					methods[k] = function(self, ...)
						if hid(self) then return zero(f(self, ...)) end
						return f(self, ...)
					end
				end
			end
		end
	end
	guard(T.Entity and T.Entity.Methods)
	guard(T.Player and T.Player.Methods)
	-- holograms and other entity types have their own setParent
	for name, meta in pairs(T) do
		if name ~= "Entity" and name ~= "Player" and istable(meta) and istable(meta.Methods) then
			local f = rawget(meta.Methods, "setParent")
			if isfunction(f) then
				meta.Methods.setParent = function(self, parent, ...)
					if SERVER and parent ~= nil then
						local ok, e = pcall(unwrap, parent)
						if ok then noteHolo(chip, e, viewer) end
					end
					if hid(parent) then return end
					return f(self, parent, ...)
				end
			end
		end
	end
end)
