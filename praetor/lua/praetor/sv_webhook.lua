-- Praetor: Discord webhook. Log lines of the chosen categories are sent as
-- embeds (who did it, on whom, what). Lines are queued and sent a few at a
-- time so Discord's rate limit is respected. The URL never reaches players.
local P = Praetor

-- Some hosts get the default HTTP of the game refused by Discord; the CHTTP
-- binary module (if the server has it) sends the same request another way.
if util.IsBinaryModuleInstalled and util.IsBinaryModuleInstalled("chttp") then pcall(require, "chttp") end

local HOSTS = { ["discord.com"] = true, ["discordapp.com"] = true, ["ptb.discord.com"] = true, ["canary.discord.com"] = true }

function P.ValidWebhook(url)
	if not isstring(url) then return false end
	local host = url:match("^https://([%w%.]+)/api/webhooks/%d+/[%w_%-]+$")
	return host ~= nil and HOSTS[host] == true
end

local COLORS = {
	cmd = 15254138, punish = 11678786, automod = 14721072, report = 7907026, rank = 8038498,
	security = 13647936, settings = 7907026, chat = 15590611, conn = 7907026, kill = 11678786, rp = 8038498, money = 13145930, player = 7907026, round = 14721072,
}

local function lang() return P.Setting("webhook_lang") end

local function esc(s)
	return (tostring(s or ""):gsub("([\\%*_~`|>%[%]])", "\\%1"))
end

local function cut(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	return P.Str(s, n - 3) .. "..."
end

local function person(p)
	if not istable(p) then return nil end
	local out = esc(p.n or "?")
	local sid = tostring(p.s or "")
	if sid:match("^%d+$") then
		out = out .. "\n[" .. util.SteamIDFrom64(sid) .. "](https://steamcommunity.com/profiles/" .. sid .. ")"
	end
	return out
end

local function targets(a, t)
	if not istable(t) then return nil end
	local list = t.n and { t } or t
	local out = {}
	for i, x in ipairs(list) do
		if i > 5 then out[#out + 1] = "+" .. (#list - 5) break end
		if istable(x) and istable(a) and x.s and x.s == a.s then
			out[#out + 1] = P.LText(lang(), "wh_self")
		elseif istable(x) then
			out[#out + 1] = person(x)
		end
	end
	if #out == 0 then return nil end
	return table.concat(out, "\n")
end

-- ------------------------------------------------------------------ queue

local queue = {}
local busyUntil, waitUntil = 0, 0
local warned = 0

local function post(embeds, done)
	local url = P.Setting("webhook_url")
	if url == "" or not P.ValidWebhook(url) then if done then done(0) end return end
	local body = util.TableToJSON({ username = cut(P.Setting("webhook_name"), 70), embeds = embeds }) or "{}"
	-- integers must not leave as 123.0, and nobody can be pinged by a log line
	body = body:gsub('"color":(%d+)%.0+', '"color":%1')
	body = body:sub(1, -2) .. ',"allowed_mentions":{"parse":[]}}'
	local ok = (CHTTP or HTTP)({
		url = url, method = "POST", type = "application/json", body = body,
		success = function(code, resp) if done then done(code, resp) end end,
		failed = function(reason) if done then done(0, reason) end end,
	})
	if ok == false and done then done(0, "HTTP refused") end
end

timer.Create("Praetor.Webhook", 2.5, 0, function()
	if #queue == 0 or CurTime() < busyUntil or CurTime() < waitUntil then return end
	if P.Setting("webhook_url") == "" then queue = {} return end
	local batch = {}
	while #batch < 5 and queue[1] do batch[#batch + 1] = table.remove(queue, 1) end
	busyUntil = CurTime() + 20
	post(batch, function(code, resp)
		busyUntil = 0
		if code == 429 then
			for i = #batch, 1, -1 do table.insert(queue, 1, batch[i]) end
			local info = util.JSONToTable(resp or "") or {}
			waitUntil = CurTime() + math.Clamp(tonumber(info.retry_after) or 5, 1, 60)
		elseif code < 200 or code >= 300 then
			waitUntil = CurTime() + 15
			if warned < CurTime() then
				warned = CurTime() + 300
				MsgC(Color(230, 120, 60), "[Praetor] Discord webhook failed (", tostring(code), "): ", tostring(resp or ""):sub(1, 200), "\n")
			end
		end
	end)
end)

local function push(embed)
	if P.Setting("webhook_url") == "" then return end
	embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
	embed.footer = { text = cut(GetHostName(), 120) }
	queue[#queue + 1] = embed
	while #queue > 120 do table.remove(queue, 1) end
end

-- ------------------------------------------------------------------ log lines

local punishTick = {}

hook.Add("Praetor.Logged", "Praetor.Webhook", function(cat, key, args)
	if P.Setting("webhook_url") == "" then return end
	if cat == "dmg" or cat == "prop" or cat == "tool" or cat == "dupe" then return end
	local a = istable(args.A) and args.A or nil
	if cat == "punish" and a then punishTick[a.s or ""] = engine.TickCount() end
	if not P.Setting("webhook_" .. cat) then return end
	-- a ban already arrives as "punish": the "command used" line for it would be a copy
	if key == "l_cmd" and a and P.Setting("webhook_punish") and punishTick[a.s or ""] == engine.TickCount() then return end

	local L = lang()
	local embed = { title = P.LText(L, "logcat_" .. cat), color = COLORS[cat] or 13145930, fields = {} }
	if key == "l_cmd" then
		local line = "!" .. tostring(args.V or "") .. " " .. tostring(args.V2 or "")
		embed.description = "`" .. cut(P.Trim((line:gsub("`", "'"))), 300) .. "`"
		if args.S then embed.title = embed.title .. " (" .. P.LText(L, "silent") .. ")" end
	else
		embed.description = cut(esc(P.LText(L, key, args)), 600)
	end
	local who = person(a)
	if who then embed.fields[#embed.fields + 1] = { name = P.LText(L, "wh_who"), value = cut(who, 300), inline = true } end
	local tg = targets(a, args.T)
	if tg then embed.fields[#embed.fields + 1] = { name = P.LText(L, "wh_target"), value = cut(tg, 600), inline = true } end
	if key == "l_automod_img" and args.V2 then
		embed.fields[#embed.fields + 1] = { name = P.LText(L, "wh_link"), value = "`" .. cut((tostring(args.V2):gsub("`", "'")), 300) .. "`", inline = false }
	end
	if #embed.fields == 0 then embed.fields = nil end
	push(embed)
end)

hook.Add("Praetor.SecurityEvent", "Praetor.Webhook", function(kind, name, sid, info)
	if not P.Setting("webhook_security") then return end
	local L = lang()
	local text = P.LText(L, "sec_" .. tostring(kind), nil, tostring(kind))
	if info and info ~= "" then text = text .. "\n" .. esc(info) end
	push({
		title = P.LText(L, "security_alert"), color = COLORS.security, description = cut(text, 600),
		fields = { { name = P.LText(L, "wh_who"), value = cut(person({ n = name, s = sid }), 300), inline = true } },
	})
end)

-- ------------------------------------------------------------------ test button

P.Receive("webhook_test", { perm = "settings", owner = true, rate = 0.2 }, function(ply)
	if P.Setting("webhook_url") == "" then P.Notify(ply, "err_webhook_none") return end
	local L = lang()
	post({ {
		title = P.LText(L, "wh_test_title"), color = COLORS.cmd,
		description = P.LText(L, "wh_test_text", { S = esc(ply:Nick()) }),
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"), footer = { text = cut(GetHostName(), 120) },
	} }, function(code)
		if not IsValid(ply) then return end
		if code >= 200 and code < 300 then P.Notify(ply, "ok_webhook", nil, "ok")
		else P.Notify(ply, "err_webhook", { V = code == 0 and "-" or code }) end
	end)
end)
