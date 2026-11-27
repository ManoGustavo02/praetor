-- Praetor: spawn limits per rank, blocked tools / entities / weapons, prop
-- model blacklist and the duplicator guard (huge dupes are refused before they
-- are pasted, so they never lag the server).
local P = Praetor

local function rankValue(ply, key)
	for _, r in ipairs(P.RankChain(ply:GetUserGroup())) do
		local v = r.limits and r.limits[key]
		if v ~= nil and v >= 0 then return v end
	end
	return nil
end

local function bypass(ply) return P.IsOwner(ply) or P.Has(ply, "bypass_limits") end

-- GMod asks this hook before every ply:CheckLimit(); returning false blocks.
hook.Add("PlayerCheckLimit", "Praetor.Limits", function(ply, name, current, default)
	if not IsValid(ply) or bypass(ply) then return end
	local limit = rankValue(ply, name)
	if limit == nil then return end
	if current >= limit then
		P.Notify(ply, "err_limit", { V = limit, S = name })
		return false
	end
	return true
end)

local function blockedBy(ply, list, class)
	if bypass(ply) then return false end
	class = tostring(class or ""):lower()
	for _, r in ipairs(P.RankChain(ply:GetUserGroup())) do
		for _, c in ipairs((r.block and r.block[list]) or {}) do
			if c == class then return true end
			if c:sub(-1) == "*" and class:sub(1, #c - 1) == c:sub(1, -2) then return true end
		end
	end
	return false
end
P.BlockedBy = blockedBy

local blacklistCache, blacklistRaw = {}, nil
local function propBlacklisted(model)
	local raw = P.Setting("prop_blacklist")
	if raw ~= blacklistRaw then
		blacklistRaw = raw
		blacklistCache = {}
		for m in string.gmatch(raw, "[^,%s]+") do blacklistCache[m:lower():gsub("\\", "/")] = true end
	end
	return blacklistCache[tostring(model or ""):lower():gsub("\\", "/")]
end

hook.Add("PlayerSpawnProp", "Praetor.Limits", function(ply, model)
	if bypass(ply) then return end
	if propBlacklisted(model) then
		if (ply.PraetorModelMsg or 0) < CurTime() then
			ply.PraetorModelMsg = CurTime() + 2
			P.Notify(ply, "err_blocked_model")
		end
		return false
	end
	if rankValue(ply, "props") == 0 then P.Notify(ply, "err_limit", { V = 0, S = "props" }) return false end
end)

hook.Add("PlayerSpawnSENT", "Praetor.Limits", function(ply, class)
	if blockedBy(ply, "ents", class) then P.Notify(ply, "err_blocked", { S = class }) return false end
end)

hook.Add("PlayerSpawnSWEP", "Praetor.Limits", function(ply, class)
	if blockedBy(ply, "weps", class) then P.Notify(ply, "err_blocked", { S = class }) return false end
end)

hook.Add("PlayerGiveSWEP", "Praetor.Limits", function(ply, class)
	if blockedBy(ply, "weps", class) then P.Notify(ply, "err_blocked", { S = class }) return false end
end)

hook.Add("PlayerSpawnNPC", "Praetor.Limits", function(ply, class)
	if blockedBy(ply, "ents", class) then P.Notify(ply, "err_blocked", { S = class }) return false end
end)

hook.Add("PlayerSpawnVehicle", "Praetor.Limits", function(ply, model, class)
	if blockedBy(ply, "ents", class) then P.Notify(ply, "err_blocked", { S = class }) return false end
end)

-- ------------------------------------------------------------------ dupes
-- Every paste goes through P.CheckDupe: the default Duplicator (also Workshop
-- dupes), Advanced Duplicator 1 and 2, and any code that calls
-- duplicator.Paste. A refused paste shows a card to the player and an alert to
-- the staff. Ranks that ignore limits may paste past the limit (setting
-- dupe_bypass), but they and the staff are still told it was a huge dupe.

local lastPaste, lastAlert = {}, {}

local function countDupe(t)
	local ents, cons, bad = 0, 0, nil
	if istable(t) then
		for _, e in pairs(t.Entities or {}) do
			ents = ents + 1
			if not bad and istable(e) and isstring(e.Model) and propBlacklisted(e.Model) then bad = e.Model end
		end
		for _ in pairs(t.Constraints or t.ConstraintList or {}) do cons = cons + 1 end
	end
	return ents, cons, bad
end
P.CountDupe = countDupe

local function dupeLimit(ply)
	local own = rankValue(ply, "dupe_ents")
	return own or P.Setting("dupe_max_ents")
end

local function mayBypass(ply)
	return P.Setting("dupe_bypass") and bypass(ply)
end

-- the same paste can be seen twice (toolgun + paste function): one alert only
local function once(ply, tag)
	local key = (ply:SteamID64() or ply:EntIndex()) .. tag
	if (lastAlert[key] or 0) > CurTime() then return false end
	lastAlert[key] = CurTime() + 3
	return true
end

-- Tells the chosen audience about a refused (or huge but allowed) dupe.
--   why: "ents" / "cons" / "model" / "off"     allowed: pasted anyway (rank bypass)
function P.DupeBlocked(ply, count, limit, tool, why, allowed, model)
	why = why or "ents"
	local info = { n = count, m = limit, t = tool or "", w = why, ok = allowed and 1 or nil, md = model }
	P.Send(ply, "dupe_alert", info)
	local mode = P.Setting("dupe_announce")
	if mode == "none" then return end
	local to = mode == "all" and player.GetHumans() or P.WithPerm("logs")
	for i = #to, 1, -1 do if to[i] == ply then table.remove(to, i) end end
	if #to == 0 then return end
	local custom = P.Setting("dupe_message")
	if custom ~= "" and not allowed then
		local nick = ply:Nick():gsub("%%", "%%%%")
		local txt = custom:gsub("{player}", nick):gsub("{count}", tostring(count)):gsub("{limit}", tostring(limit))
		P.Send(to, "chat", { { c = { 226, 160, 64 } }, "[Praetor] ", { c = { 237, 228, 211 } }, txt })
		return
	end
	info.p = ply:Nick()
	info.ps = ply:SteamID64()
	P.Send(to, "dupe_alert", info)
end

-- true when the paste may go on
function P.CheckDupe(ply, nEnts, nCons, tool, badModel)
	if not IsValid(ply) or not ply:IsPlayer() then return true end
	local maxE = dupeLimit(ply)
	local maxC = P.Setting("dupe_max_cons")
	local free = mayBypass(ply)
	local why, n, lim
	if maxE == 0 then why, n, lim = "off", nEnts, 0
	elseif badModel then why, n, lim = "model", nEnts, maxE
	elseif maxE > 0 and nEnts > maxE then why, n, lim = "ents", nEnts, maxE
	elseif maxC > 0 and nCons > maxC then why, n, lim = "cons", nCons, maxC end
	if why then
		if free then
			if once(ply, "ok") then
				P.Log("dupe", "l_dupe_big_ok", { A = P.LogPly(ply), V = n, V2 = tool }, { ply })
				P.DupeBlocked(ply, n, lim, tool, why, true, badModel)
			end
		else
			if once(ply, "no") then
				P.Log("dupe", "l_dupe_blocked", { A = P.LogPly(ply), V = n, V2 = tool }, { ply })
				P.DupeBlocked(ply, n, lim, tool, why, false, badModel)
				if why ~= "off" and n >= lim * 3 and P.Security then P.Security(ply, "dupe_huge", n .. " (" .. why .. ", limit " .. lim .. ", " .. tostring(tool) .. ")") end
			end
			return false
		end
	end
	if not bypass(ply) then
		local cd = P.Setting("dupe_cooldown")
		local key = ply:SteamID64() or ply:EntIndex()
		if cd > 0 and lastPaste[key] and lastPaste[key] > CurTime() then
			if once(ply, "cd") then P.Notify(ply, "err_dupe_wait", { V = math.ceil(lastPaste[key] - CurTime()) }) end
			return false
		end
		-- bigger dupes wait longer before the next one
		lastPaste[key] = CurTime() + cd + math.min(30, math.floor(nEnts / 50))
	end
	if once(ply, "log") then P.Log("dupe", "l_dupe", { A = P.LogPly(ply), V = nEnts, V2 = tool }, { ply }) end
	return true
end

-- ------------------------------------------------------------------ dupe names
-- Dupes whose name (or, for Workshop dupes, title / tags / description) has one
-- of the words of dupe_block_words are refused: crash dupes are usually shared
-- with names like "crasher" or "server crash". Owners are not checked.
local function dupeWord(text)
	local list = P.Setting("dupe_block_words")
	if not isstring(list) or P.Trim(list) == "" or not P.AutoModCompile then return nil end
	local block = P.AutoModCompile(list)
	if #block == 0 then return nil end
	return P.AutoModFind(tostring(text or ""), block, {}, false)
end
P.DupeWord = dupeWord

function P.DupeNameRefused(ply, name, word, tool)
	if not IsValid(ply) or not once(ply, "name") then return end
	P.Log("dupe", "l_dupe_name", { A = P.LogPly(ply), V = P.Str(tostring(name), 80), S = word, V2 = tool }, { ply })
	P.DupeBlocked(ply, 0, 0, tool, "name", false, word)
	if P.Security then P.Security(ply, "dupe_name", P.Str(tostring(name), 80) .. " (" .. word .. ", " .. tostring(tool) .. ")", true) end
end

local function fileBase(path)
	return (string.GetFileFromFilename(tostring(path or "")):gsub("%.%w+$", ""))
end

-- Advanced Duplicator 2 keeps the name of the file the player opened
local function adv2Word(ply)
	if P.IsOwner(ply) then return nil end
	local d = ply.AdvDupe2
	local name = istable(d) and (d.Name or d.name)
	if not isstring(name) or name == "" then return nil end
	local word = dupeWord(fileBase(name))
	return word, fileBase(name)
end

-- GMod's duplicator: the name of the dupe file comes at the end of "ArmDupe".
-- The original receiver runs as always; when the name is refused, the dupe it
-- armed is taken away before it can be pasted.
local function wrapArm()
	local recv = net.Receivers and net.Receivers["armdupe"]
	if not recv or recv == P.ArmWrapped then return end
	local orig = recv
	local wrapped = function(len, client)
		local captured
		local rs = net.ReadString
		net.ReadString = function(...)
			local v = rs(...)
			if captured == nil then captured = v end
			return v
		end
		local ok, err = pcall(orig, len, client)
		net.ReadString = rs
		if not ok then ErrorNoHalt("[Praetor] ArmDupe: " .. tostring(err) .. "\n") end
		if not IsValid(client) or not client.CurrentDupe or P.IsOwner(client) then return end
		local base = captured and fileBase(captured) or ""
		local word = base ~= "" and dupeWord(base) or nil
		-- a Workshop dupe already refused by its title / description
		if not word and (client.PraetorWSDupeBad or 0) > CurTime() then
			word, base = client.PraetorWSDupeWord, client.PraetorWSDupeTitle or base
		end
		if word then
			client.CurrentDupe = nil
			client.CurrentDupeArmed = false
			P.DupeNameRefused(client, base, word, "duplicator")
		end
	end
	net.Receivers["armdupe"] = wrapped
	P.ArmWrapped = wrapped
end
hook.Add("InitPostEntity", "Praetor.DupeNames", function() timer.Simple(2, wrapArm) end)
timer.Simple(6, wrapArm)

local DUPE_TOOLS = { duplicator = true, advdupe2 = true, adv_duplicator = true }

-- Checked before the toolgun fires.
hook.Add("CanTool", "Praetor.Dupes", function(ply, tr, tool)
	if not DUPE_TOOLS[tool] then return end
	if not ply:KeyDown(IN_ATTACK) and not ply:KeyPressed(IN_ATTACK) then return end
	local data
	if tool == "duplicator" then data = ply.CurrentDupe
	elseif tool == "advdupe2" then data = ply.AdvDupe2
	else data = ply.AdvDupe end
	if not data then return end
	if tool == "advdupe2" then
		local word, name = adv2Word(ply)
		if word then P.DupeNameRefused(ply, name, word, tool) return false end
	end
	local e, c, bad = countDupe(data)
	if e == 0 then return end
	if not P.CheckDupe(ply, e, c, tool, bad) then return false end
end)

-- Pastes that do not come from the toolgun click (contraption spawners, other
-- addons, Workshop dupes) still go through these functions.
local function wrap()
	if duplicator and duplicator.Paste and not duplicator.PraetorWrapped then
		local orig = duplicator.Paste
		duplicator.PraetorWrapped = true
		duplicator.Paste = function(ply, entList, conList, ...)
			if IsValid(ply) and ply:IsPlayer() then
				local e, c, bad = countDupe({ Entities = entList, Constraints = conList })
				if e > 1 and not P.CheckDupe(ply, e, c, "duplicator", bad) then return {}, {} end
				-- the anti-crash spawn-spam guard must not count the pasted props
				ply.PraetorPasting = true
				local r = { pcall(orig, ply, entList, conList, ...) }
				ply.PraetorPasting = nil
				if not r[1] then ErrorNoHalt(tostring(r[2]) .. "\n") return {}, {} end
				if P.ACCheckPasted and istable(r[2]) then pcall(P.ACCheckPasted, ply, r[2]) end
				return unpack(r, 2)
			end
			return orig(ply, entList, conList, ...)
		end
	end
	if AdvDupe2 and AdvDupe2.InitPastingQueue and not AdvDupe2.PraetorWrapped then
		local orig = AdvDupe2.InitPastingQueue
		AdvDupe2.PraetorWrapped = true
		AdvDupe2.InitPastingQueue = function(ply, ...)
			if IsValid(ply) and ply:IsPlayer() and ply.AdvDupe2 then
				local word, name = adv2Word(ply)
				if word then
					ply.AdvDupe2.Pasting = false
					P.DupeNameRefused(ply, name, word, "advdupe2")
					return
				end
				local e, c, bad = countDupe(ply.AdvDupe2)
				if e > 0 and not P.CheckDupe(ply, e, c, "advdupe2", bad) then
					ply.AdvDupe2.Pasting = false
					if AdvDupe2.Notify then AdvDupe2.Notify(ply, "Praetor: dupe refused.", NOTIFY_ERROR) end
					return
				end
			end
			return orig(ply, ...)
		end
	end
end
hook.Add("InitPostEntity", "Praetor.DupeWrap", wrap)
if GAMEMODE then wrap() end
timer.Simple(5, wrap)

-- Blocked tools per rank
hook.Add("CanTool", "Praetor.ToolBlock", function(ply, tr, tool)
	if blockedBy(ply, "tools", tool) then
		if (ply.PraetorToolMsg or 0) < CurTime() then
			ply.PraetorToolMsg = CurTime() + 2
			P.Notify(ply, "err_blocked", { S = tool })
		end
		return false
	end
end)
