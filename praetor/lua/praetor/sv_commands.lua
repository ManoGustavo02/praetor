-- Praetor: running commands (chat, console, menu) and the action broadcast.
local P = Praetor

local spam = {}

local function packTarget(v)
	if IsValid(v) and v:IsPlayer() then
		local r = P.RankOf(v)
		local c = r and r.style and r.style.c1 or { r = 237, g = 228, b = 211 }
		return { n = v:Nick(), c = c, me = nil, sid = v:SteamID64() }
	end
	if istable(v) and v.n then return v end
	return { n = tostring(v) }
end

local function packArgs(caller, args)
	local out = {}
	out.A = caller ~= nil and packTarget(IsValid(caller) and caller or "Console") or nil
	if args then
		if args.T ~= nil then
			local list = istable(args.T) and not IsValid(args.T) and args.T or { args.T }
			local t = {}
			for _, v in ipairs(list) do t[#t + 1] = packTarget(v) end
			if #list == #player.GetAll() and #list > 1 then t = { { n = "*", all = true } } end
			out.T = t
		end
		for k, v in pairs(args) do
			if k ~= "T" and k ~= "A" then out[k] = isnumber(v) and v or tostring(v) end
		end
	end
	return out
end

-- Broadcasts what a staff member did, e.g. "Admin kicked Bob (spam)".
function P.Echo(caller, key, args)
	-- bans have their own chat line (sv_banscreen, setting ban_announce)
	if P.BanEchoKeys and P.BanEchoKeys[key] and P.Setting("ban_announce") ~= "none" then
		local plain = P.EchoPlain(packArgs(caller, args))
		MsgC(P.Col.bronze, "[Praetor] ", P.Col.ivory, P.LText("en", key, plain), "\n")
		return
	end
	local silent = P.CurrentSilent == true
	local data = { k = key, a = packArgs(caller, args), s = silent and 1 or nil }
	local mode = P.Setting("echo")
	local to
	if silent or mode == "staff" then
		to = P.WithPerm("see_silent")
		if IsValid(caller) and not table.HasValue(to, caller) then to[#to + 1] = caller end
	elseif mode == "none" then
		to = IsValid(caller) and { caller } or {}
	end
	if to then
		if #to > 0 then P.Send(to, "echo", data) end
	else
		P.Send(nil, "echo", data)
	end
	MsgC(P.Col.bronze, "[Praetor] ", P.Col.ivory, P.LText("en", key, P.EchoPlain(data.a)), "\n")
end

function P.EchoRaw(caller, text)
	P.Echo(caller, "e_raw", { V = P.Str(text, 300) })
end

-- flattens packed echo args into plain strings (console / logs)
function P.EchoPlain(a)
	local out = {}
	for k, v in pairs(a or {}) do
		if istable(v) and v.n then out[k] = v.n
		elseif istable(v) then
			local names = {}
			for _, x in ipairs(v) do names[#names + 1] = istable(x) and (x.all and "everyone" or x.n) or tostring(x) end
			out[k] = table.concat(names, ", ")
		else out[k] = v end
	end
	return out
end

-- ------------------------------------------------------------------ run

function P.RunCommand(caller, def, argv, silent)
	if not def then return false end
	if IsValid(caller) then
		local key = caller:EntIndex()
		local now = SysTime()
		spam[key] = spam[key] or {}
		local s = spam[key]
		s[#s + 1] = now
		while s[1] and s[1] < now - 2 do table.remove(s, 1) end
		if #s > 8 then P.Notify(caller, "err_slow") return false end
	end
	if not P.CanRun(caller, def) then
		P.Notify(caller, "err_no_perm", { S = def.id })
		return false
	end
	if def.noconsole and not IsValid(caller) then P.Notify(caller, "err_console") return false end
	if silent and not P.Has(caller, "silent") then silent = false end

	local vals, err, eargs = P.ParseArgs(caller, def, argv or {})
	if not vals then
		P.Notify(caller, err, eargs)
		-- always show how the command is written after a mistake in it
		if err ~= "err_internal" and err ~= "err_missing_arg" then P.Notify(caller, "n_usage_u", { U = def.id }) end
		return false
	end

	P.CurrentSilent = silent or nil
	local ok, res = pcall(def.run, caller, unpack(vals, 1, #def.args))
	P.CurrentSilent = nil
	if not ok then
		MsgC(Color(220, 80, 80), "[Praetor] command '", def.id, "' failed: ", tostring(res), "\n")
		P.Notify(caller, "err_internal")
		return false
	end
	if isstring(res) then P.Notify(caller, res) end

	local targets = {}
	for _, v in ipairs(vals) do
		if istable(v) then
			for _, p in ipairs(v) do if IsValid(p) and p.IsPlayer and p:IsPlayer() then targets[#targets + 1] = p end end
			if v.sid then targets[#targets + 1] = v.sid end
		end
	end
	local tlist = {}
	for i, t in ipairs(targets) do
		if i > 16 then break end
		tlist[#tlist + 1] = P.LogPly(t)
	end
	table.insert(targets, 1, caller)
	P.Log("cmd", "l_cmd", { A = P.LogPly(caller), T = #tlist > 0 and tlist or nil, V = def.id, V2 = P.Str(table.concat(argv or {}, " "), 200), S = silent and "silent" or nil }, targets)
	hook.Run("Praetor.CommandRan", caller, def.id, vals, silent)
	return true
end

-- Runs a full text line ("kick bob spam") as a player.
function P.RunLine(caller, line, silent)
	local argv = P.SplitArgs(line)
	local name = table.remove(argv, 1)
	local def = P.FindCommand(name)
	if not def then
		P.Notify(caller, "err_unknown_cmd", { S = name or "" })
		return false
	end
	return P.RunCommand(caller, def, argv, silent)
end

-- ------------------------------------------------------------------ chat

local menuWords = { menu = true, praetor = true, p = true, admin = true }

hook.Add("PlayerSay", "Praetor.Commands", function(ply, text, teamChat)
	text = P.Trim(text)
	if text == "" then return end
	if P.AutoModBlock and P.AutoModBlock(ply, text) then return "" end

	-- admin chat: "@ message"
	local acp = P.Setting("adminchat_prefix")
	if acp ~= "" and text:sub(1, #acp) == acp and #text > #acp then
		local msg = P.Trim(text:sub(#acp + 1))
		if msg ~= "" then
			local to = P.WithPerm("adminchat")
			local staff = P.Has(ply, "adminchat")
			if not table.HasValue(to, ply) then to[#to + 1] = ply end
			P.Send(to, "adminchat", { n = ply:Nick(), sid = ply:SteamID64(), m = P.Str(msg, 300), staff = staff and 1 or nil })
			P.Log("chat", "l_adminchat", { A = P.LogPly(ply), V = P.Str(msg, 300) }, { ply })
			return ""
		end
	end

	local first = text:sub(1, 1)
	local silentPrefix = P.Setting("prefix_silent")
	local silent = silentPrefix ~= "" and text:sub(1, #silentPrefix) == silentPrefix
	if not silent and first ~= "!" and first ~= "/" then
		if P.ChatBlocked and P.ChatBlocked(ply, text) then return "" end
		P.Log("chat", teamChat and "l_chat_team" or "l_chat", { A = P.LogPly(ply), V = P.Str(text, 300) }, { ply })
		return
	end

	local body = text:sub(silent and #silentPrefix + 1 or 2)
	local argv = P.SplitArgs(body)
	local name = argv[1] and argv[1]:lower()
	if not name then return end

	if menuWords[name] and not P.Commands[name] then
		P.Send(ply, "open_menu", {})
		return ""
	end

	if name == "report" and P.Setting("reports") and not P.FindCommand("report") then
		if BBX and P.Setting("reports_blackbox") then return end
		table.remove(argv, 1)
		P.Send(ply, "open_report", { t = argv[1] })
		return ""
	end

	local def = P.FindCommand(name)
	if not def then
		if P.ChatBlocked and P.ChatBlocked(ply, text) then return "" end
		-- "//ooc", "/advert", "/pm"... of DarkRP and other addons still go to the chat log
		P.Log("chat", teamChat and "l_chat_team" or "l_chat", { A = P.LogPly(ply), V = P.Str(text, 300) }, { ply })
		return
	end
	-- "/job", "/advert"... belong to DarkRP
	if first == "/" and not silent and DarkRP and DarkRP.getChatCommand and DarkRP.getChatCommand(name) then
		P.Log("chat", "l_chat", { A = P.LogPly(ply), V = P.Str(text, 300) }, { ply })
		return
	end

	table.remove(argv, 1)
	P.RunCommand(ply, def, argv, silent)
	return ""
end)

-- ------------------------------------------------------------------ console

local function complete(cmd, line)
	line = line:gsub("^%s+", "")
	local out = {}
	local want = line:lower()
	for id in pairs(P.Commands) do
		if id:sub(1, #want) == want then out[#out + 1] = cmd .. " " .. id end
	end
	table.sort(out)
	return out
end

concommand.Add("praetor", function(ply, _, args, line)
	if #args == 0 then
		if IsValid(ply) then P.Send(ply, "open_menu", {}) return end
		print("[Praetor " .. P.Version .. "] usage: praetor <command> <args>")
		local ids = table.GetKeys(P.Commands)
		table.sort(ids)
		print("  " .. table.concat(ids, ", "))
		return
	end
	P.RunLine(ply, line, false)
end, complete)

concommand.Add("praetor_silent", function(ply, _, _, line)
	P.RunLine(ply, line, true)
end, complete)

-- short alias for binds: bind g "pr god"
concommand.Add("pr", function(ply, _, args, line)
	if #args == 0 then return end
	P.RunLine(ply, line, false)
end, complete)

-- clients run console lines through here (their own "praetor" command has autocomplete)
P.Receive("run_line", { rate = 4 }, function(ply, data)
	local line = P.Str(data.line, 400)
	if P.Trim(line) == "" then return end
	P.RunLine(ply, line, data.silent == true)
end)

-- ------------------------------------------------------------------ menu

P.Receive("run", { rate = 4 }, function(ply, data)
	local def = P.FindCommand(isstring(data.id) and data.id or "")
	if not def then return end
	local argv = {}
	if istable(data.args) then
		for i = 1, math.min(#data.args, 8) do argv[i] = P.Str(data.args[i], 250) end
	end
	P.RunCommand(ply, def, argv, data.silent == true)
end)
