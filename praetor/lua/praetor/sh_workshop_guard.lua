-- Praetor: AutoMod for Workshop content (player models, outfits, PAC3 parts).
-- Before anything is downloaded from the Workshop, the title, tags and
-- description of the item are read from Steam and checked with the AutoMod
-- lists (nsfw, porn, hentai, gore...). Blocked items are never downloaded,
-- neither by the player nor by anyone else.
--
-- It works with every system that downloads skins:
--   * steamworks.DownloadUGC is wrapped on client and server, so any addon that
--     downloads Workshop items (Outfitter, PAC3, model selectors, wardrobe
--     addons...) waits for the verdict first;
--   * Outfitter (CanOutfit), Wardrobe (Wardrobe_RecieveModel / _ValidateInfo)
--     and PAC3 (PrePACConfigApply) are also stopped
--     before the outfit is kept and sent to the other players;
--   * other addons can ask Praetor.CheckWorkshop(id, function(ok) end).
local P = Praetor

P.WSVerdict = P.WSVerdict or {} -- [id] = true (ok) / false (blocked)

-- a Workshop id from a number, "123", or a steamcommunity link
local function wsId(info)
	if isnumber(info) then return tostring(math.floor(info)) end
	if not isstring(info) then return nil end
	if info:match("^%d+$") then return info end
	return info:match("steamcommunity%.com/.-[?&]id=(%d+)") or info:match("^workshop[:/](%d+)$")
end
P.WorkshopId = wsId

local function enabled()
	return P.Setting("automod") and P.Setting("automod_workshop")
end

local function skips(ply)
	return P.AutoModSkips and P.AutoModSkips(ply) or false
end

if SERVER then
	local pending = {}

	local function verdict(id, ok, why, title)
		P.WSVerdict[id] = ok
		P.Send(nil, "ws_verdict", { id = id, ok = ok })
		local waiting = pending[id] or {}
		pending[id] = nil
		for _, w in ipairs(waiting) do if w.cb then w.cb(ok, why, title) end end
		hook.Run("Praetor.WorkshopVerdict", id, ok, why, title)
	end

	-- Asks Steam about a Workshop item. cb(ok, matchedWord, title)
	function P.CheckWorkshop(id, cb)
		id = wsId(id)
		if not id then if cb then cb(true) end return end
		if P.WSVerdict[id] ~= nil then if cb then cb(P.WSVerdict[id]) end return end
		if pending[id] then table.insert(pending[id], { cb = cb }) return end
		pending[id] = { { cb = cb } }
		http.Post("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/",
			{ itemcount = "1", ["publishedfileids[0]"] = id },
			function(body)
				local t = util.JSONToTable(body or "") or {}
				local d = t.response and t.response.publishedfiledetails and t.response.publishedfiledetails[1]
				if not d or tonumber(d.result) ~= 1 then
					-- private, removed or unknown items can't be checked: blocked
					verdict(id, false, "?", id)
					return
				end
				if tonumber(d.banned) == 1 then verdict(id, false, "banned", d.title or id) return end
				local tags = {}
				for _, tg in ipairs(d.tags or {}) do tags[#tags + 1] = tostring(tg.tag or "") end
				local text = table.concat({ tostring(d.title or ""), table.concat(tags, " "), P.Str(d.description or "", 3000) }, "\n")
				local img = P.AutoModCompile(P.Setting("automod_image_words"))
				local block = P.AutoModCompile(P.Setting("automod_words"))
				local allow = P.AutoModCompile(P.Setting("automod_allow"))
				local word = P.AutoModFind(text, img, allow, true) or P.AutoModFind(text, block, allow, false)
				verdict(id, word == nil, word, tostring(d.title or id))
			end,
			function()
				-- Steam did not answer: try again next time instead of caching
				local waiting = pending[id] or {}
				pending[id] = nil
				for _, w in ipairs(waiting) do if w.cb then w.cb(false, "steam", id) end end
			end)
	end

	local notified = {}
	local function tell(ply, key, args)
		if not IsValid(ply) then return end
		local k = ply:EntIndex() .. key
		if (notified[k] or 0) > CurTime() then return end
		notified[k] = CurTime() + 3
		P.Notify(ply, key, args, key == "n_automod_ws_ok" and "ok" or "warn")
	end

	local function blocked(ply, id, word, title)
		tell(ply, "n_automod_ws_bad")
		P.Log("automod", "l_automod_ws", { A = P.LogPly(ply), V = word or "?", V2 = P.Str(title or id, 120) .. " (" .. id .. ")" }, { ply })
	end

	-- checks a link (model / texture URL) with the image word list
	local function badLink(url)
		local word = P.AutoModScan(" " .. url, { images = true })
		return word
	end

	-- Outfitter: false stops the outfit before the server keeps or sends it
	hook.Add("CanOutfit", "Praetor.WorkshopGuard", function(ply, mdl, info)
		if not enabled() or not IsValid(ply) or skips(ply) then return end
		if isstring(info) and info:find("^https?://") and not wsId(info) then
			local word = badLink(info .. " " .. tostring(mdl or ""))
			if word then blocked(ply, info, word, info) return false end
			return
		end
		local id = wsId(info)
		if not id then return end
		local v = P.WSVerdict[id]
		if v == true then return end
		if v == false then blocked(ply, id, nil, id) return false end
		tell(ply, "n_automod_ws_check")
		P.CheckWorkshop(id, function(ok, word, title)
			if not IsValid(ply) then return end
			if ok then tell(ply, "n_automod_ws_ok") else blocked(ply, id, word, title) end
		end)
		return false
	end)

	-- Wardrobe (CaveeJohnson): checked before the server sets the model and
	-- sends it to everyone. Once approved, the model goes on by itself.
	hook.Add("Wardrobe_RecieveModel", "Praetor.WorkshopGuard", function(ply, wsid, mdl)
		if not enabled() or not IsValid(ply) or skips(ply) then return end
		local id = wsId(wsid)
		if not id then return end
		local v = P.WSVerdict[id]
		if v == true then return end
		if v == false then blocked(ply, id, nil, id) return false end
		tell(ply, "n_automod_ws_check")
		P.CheckWorkshop(id, function(ok, word, title)
			if not IsValid(ply) then return end
			if not ok then blocked(ply, id, word, title) return end
			tell(ply, "n_automod_ws_ok")
			if wardrobe and wardrobe.setModel and ply.wardrobe ~= mdl then
				wardrobe.setModel(ply, tonumber(id), mdl)
			end
		end)
		return false
	end)

	-- PAC3: every link and Workshop id inside the outfit is checked before
	-- the server accepts it and sends it to the other players
	local function collect(t, out, depth)
		if depth > 12 or out.n > 4000 then return end
		for k, v in pairs(t) do
			out.n = out.n + 1
			if istable(v) then collect(v, out, depth + 1)
			elseif isstring(v) and #v < 2048 then
				if v:find("://", 1, true) then out.links[#out.links + 1] = v end
				local id = wsId(v)
				if id and (v:find("steamcommunity", 1, true) or v:find("^workshop")) then out.ids[id] = true end
			end
		end
	end
	hook.Add("PrePACConfigApply", "Praetor.WorkshopGuard", function(ply, data)
		if not enabled() or not IsValid(ply) or skips(ply) or not istable(data) then return end
		local found = { links = {}, ids = {}, n = 0 }
		collect(data, found, 0)
		for _, url in ipairs(found.links) do
			local word = badLink(url)
			if word then blocked(ply, url, word, url) return false, P.LText("en", "n_automod_ws_bad") end
		end
		local waiting = false
		for id in pairs(found.ids) do
			local v = P.WSVerdict[id]
			if v == false then blocked(ply, id, nil, id) return false, P.LText("en", "n_automod_ws_bad") end
			if v == nil then
				waiting = true
				P.CheckWorkshop(id, function(ok, word, title)
					if not IsValid(ply) then return end
					if ok then tell(ply, "n_automod_ws_ok") else blocked(ply, id, word, title) end
				end)
			end
		end
		if waiting then
			tell(ply, "n_automod_ws_check")
			return false, P.LText("en", "n_automod_ws_check")
		end
	end)

	-- the server itself downloading Workshop items (runtime content addons)
	if steamworks and steamworks.DownloadUGC and not P.WSWrappedSV then
		local orig = steamworks.DownloadUGC
		P.WSWrappedSV = true
		steamworks.DownloadUGC = function(id, cb, ...)
			local sid = wsId(id)
			if not sid or not enabled() then return orig(id, cb, ...) end
			local extra = { ... }
			P.CheckWorkshop(sid, function(ok)
				if ok then orig(id, cb, unpack(extra)) elseif cb then cb(nil, nil) end
			end)
		end
	end

	-- the player's own game asks before downloading
	P.Receive("ws_check", { rate = 6 }, function(ply, data)
		local id = wsId(data.id)
		if not id then return end
		if not enabled() then P.Send(ply, "ws_answer", { id = id, ok = true }) return end
		P.CheckWorkshop(id, function(ok, word, title)
			if not IsValid(ply) then return end
			P.Send(ply, "ws_answer", { id = id, ok = ok })
			if ok then tell(ply, "n_automod_ws_ok") else blocked(ply, id, word, title) end
		end)
	end)

	-- Workshop dupes (spawn menu > Dupes): before the game downloads one, the
	-- player's client asks here; the title, tags and description are checked
	-- with dupe_block_words. Steam not answering lets the dupe through.
	local dupeCache = {}
	function P.CheckDupeWorkshop(id, cb)
		id = wsId(id)
		if not id then cb(nil) return end
		local c = dupeCache[id]
		if c ~= nil then cb(c.word or nil, c.title) return end
		http.Post("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/",
			{ itemcount = "1", ["publishedfileids[0]"] = id },
			function(body)
				local t = util.JSONToTable(body or "") or {}
				local d = t.response and t.response.publishedfiledetails and t.response.publishedfiledetails[1]
				if not d or tonumber(d.result) ~= 1 then cb(nil, id) return end
				local tags = {}
				for _, tg in ipairs(d.tags or {}) do tags[#tags + 1] = tostring(tg.tag or "") end
				local text = table.concat({ tostring(d.title or ""), table.concat(tags, " "), P.Str(d.description or "", 3000) }, "\n")
				local word = P.DupeWord and P.DupeWord(text) or nil
				dupeCache[id] = { word = word or false, title = tostring(d.title or id) }
				cb(word, tostring(d.title or id))
			end,
			function() cb(nil, id) end)
	end

	P.Receive("dupe_ws", { rate = 3 }, function(ply, data)
		local id = wsId(data.id)
		if not id then return end
		if P.IsOwner(ply) then P.Send(ply, "dupe_ws", { id = id, ok = true }) return end
		P.CheckDupeWorkshop(id, function(word, title)
			if not IsValid(ply) then return end
			if word then
				ply.PraetorWSDupeBad = CurTime() + 120
				ply.PraetorWSDupeWord = word
				ply.PraetorWSDupeTitle = P.Str(title or id, 80) .. " (" .. id .. ")"
				if P.DupeNameRefused then P.DupeNameRefused(ply, ply.PraetorWSDupeTitle, word, "workshop") end
			end
			P.Send(ply, "dupe_ws", { id = id, ok = word == nil })
		end)
	end)

	-- players joining late learn the verdicts already made
	hook.Add("PlayerInitialSpawn", "Praetor.WorkshopGuard", function(ply)
		timer.Simple(5, function()
			if not IsValid(ply) or table.IsEmpty(P.WSVerdict) then return end
			local list = {}
			for id, ok in pairs(P.WSVerdict) do list[#list + 1] = { id, ok } if #list >= 300 then break end end
			P.Send(ply, "ws_verdicts", { list = list })
		end)
	end)
else
	-- downloads waiting for the server's answer: [id] = { {args}, ... }
	local queue = {}
	local origDownload = P.WSOrigDownload or (steamworks and steamworks.DownloadUGC)
	P.WSOrigDownload = origDownload

	-- Wardrobe keeps a failed download in memory and never tries it again:
	-- once the item is approved, that mark is cleared
	local function unstick(id)
		if not (workshop and istable(workshop.got)) then return end
		local n = tonumber(id)
		if workshop.got[id] == false then workshop.got[id] = nil end
		if n and workshop.got[n] == false then workshop.got[n] = nil end
	end

	local function release(id, ok)
		if ok then unstick(id) end
		local list = queue[id]
		queue[id] = nil
		if not list then return end
		for _, a in ipairs(list) do
			if ok then origDownload(a.id, a.cb, unpack(a.extra))
			elseif a.cb then a.cb(nil, nil) end
		end
	end

	P.On("ws_verdict", function(d)
		if not d.id then return end
		local id = tostring(d.id)
		P.WSVerdict[id] = d.ok == true
		release(id, d.ok == true)
	end)
	P.On("ws_answer", function(d) if d.id then release(tostring(d.id), d.ok == true) end end)
	P.On("ws_verdicts", function(d)
		for _, v in ipairs(d.list or {}) do P.WSVerdict[tostring(v[1])] = v[2] == true end
	end)

	local asked = {}
	local function ask(id)
		if asked[id] and asked[id] > CurTime() then return end
		asked[id] = CurTime() + 10
		P.Request("ws_check", { id = id })
	end

	-- every Workshop download of this game waits for the verdict
	if origDownload and not P.WSWrappedCL then
		P.WSWrappedCL = true
		steamworks.DownloadUGC = function(id, cb, ...)
			local sid = wsId(id)
			local me = LocalPlayer()
			if not sid or not enabled() or (IsValid(me) and skips(me)) then return origDownload(id, cb, ...) end
			local v = P.WSVerdict[sid]
			if v == true then return origDownload(id, cb, ...) end
			if v == false then if cb then cb(nil, nil) end return end
			queue[sid] = queue[sid] or {}
			table.insert(queue[sid], { id = id, cb = cb, extra = { ... } })
			ask(sid)
			-- no answer (server busy, Steam down): give up and let it be tried again
			timer.Create("Praetor.WS." .. sid, 25, 1, function()
				asked[sid] = nil
				release(sid, false)
			end)
		end
	end

	-- Workshop dupes: the spawn menu's "download and arm" waits for the server
	local dupeWait = {}
	P.On("dupe_ws", function(d)
		local id = tostring(d.id or "")
		local go = dupeWait[id]
		dupeWait[id] = nil
		timer.Remove("Praetor.DupeWS." .. id)
		if go and d.ok then go() end
	end)
	local function wrapDupeMenu()
		local wd = rawget(_G, "ws_dupe")
		if not istable(wd) or not isfunction(wd.DownloadAndArm) or wd.DownloadAndArm == wd.PraetorDAA then return end
		local orig = wd.DownloadAndArm
		local mine = function(self, id, ...)
			local sid = wsId(id)
			if not sid then return orig(self, id, ...) end
			local extra = { ... }
			dupeWait[sid] = function() orig(self, id, unpack(extra)) end
			P.Request("dupe_ws", { id = sid })
			-- no answer: the dupe goes on as normal
			timer.Create("Praetor.DupeWS." .. sid, 12, 1, function()
				local go = dupeWait[sid]
				dupeWait[sid] = nil
				if go then go() end
			end)
		end
		wd.DownloadAndArm = mine
		wd.PraetorDAA = mine
	end
	timer.Create("Praetor.DupeMenuWrap", 2, 0, wrapDupeMenu)

	-- Wardrobe: before it downloads an addon (also for the model list of its menu)
	hook.Add("Wardrobe_ValidateInfo", "Praetor.WorkshopGuard", function(wsid, info)
		if not enabled() then return end
		local id = wsId(wsid)
		if not id then return end
		local v = P.WSVerdict[id]
		if v == false then return false end
		if v == true then return end
		local me = LocalPlayer()
		if IsValid(me) and skips(me) then return end
		ask(id)
		return false
	end)

	hook.Add("CanOutfit", "Praetor.WorkshopGuard", function(ply, mdl, info)
		if not enabled() then return end
		local id = wsId(info)
		if not id then return end
		local v = P.WSVerdict[id]
		if v == false then return false end
		if v == true or not IsValid(ply) then return end
		-- an outfit of someone else was already approved by the server to get here
		if ply ~= LocalPlayer() then return end
		if skips(ply) then return end
		ask(id)
		return false
	end)
end
