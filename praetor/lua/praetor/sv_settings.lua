-- Praetor: settings + the "sync" packet every client receives.
local P = Praetor

-- settings only the owners can change (they protect the server itself)
P.OwnerSettings = { rank_lock = true, rank_lock_max = true, equal_target = true, webhook_url = true, family_ban = true, family_block = true, loading_base = true }

-- settings that never leave the server (players only learn if they are set)
P.PrivateSettings = { webhook_url = true }

-- longer text limits
P.SettingMax = { automod_words = 8000, automod_allow = 4000, automod_image_words = 4000, chat_image_hosts = 2000 }

-- allowed values of the "choice" settings
P.SettingChoices = {
	lang = { auto = true, en = true, pt = true },
	echo = { all = true, staff = true, none = true },
	chat_mode = { praetor = true, tags = true, off = true },
	scoreboard_group = { group = true, rank = true, job = true, none = true },
	dupe_announce = { all = true, staff = true, none = true },
	automod_action = { block = true, warn = true, mute = true, kick = true },
	webhook_lang = { en = true, pt = true },
	webhook_weekly_day = { mon = true, tue = true, wed = true, thu = true, fri = true, sat = true, sun = true },
	alt_action = { alert = true, kick = true, ban = true },
	perm_announce = { all = true, staff = true, none = true },
	ban_announce = { all = true, staff = true, none = true },
	ban_try_announce = { all = true, staff = true, none = true },
}

function P.LoadSettings()
	local saved = P.DB.Get("settings", {})
	P.Settings = {}
	for k, v in pairs(saved) do
		if P.Defaults[k] ~= nil and type(v) == type(P.Defaults[k]) then P.Settings[k] = v end
	end
end

function P.SaveSettings()
	P.DB.Set("settings", P.Settings)
end

-- Validates a value against the type of its default.
local function cleanValue(k, v)
	local def = P.Defaults[k]
	if def == nil then return nil end
	if isbool(def) then return v == true end
	if isnumber(def) then
		v = tonumber(v)
		if not v then return nil end
		return math.Clamp(math.floor(v), -1, 1000000)
	end
	if isstring(def) then
		v = P.Str(v, P.SettingMax[k] or 1200)
		if P.SettingChoices[k] and not P.SettingChoices[k][v] then return nil end
		if k == "webhook_url" then
			v = P.Trim(v)
			if v ~= "" and not (P.ValidWebhook and P.ValidWebhook(v)) then return nil end
		end
		return v
	end
	if istable(def) and k == "warn_rules" and istable(v) then
		local out = {}
		for i = 1, math.min(#v, 8) do
			local r = v[i]
			if istable(r) then
				local act = (r.act == "kick" or r.act == "ban" or r.act == "jail" or r.act == "mute") and r.act or "kick"
				out[#out + 1] = { pts = math.Clamp(math.floor(tonumber(r.pts) or 3), 1, 100), act = act, min = math.Clamp(math.floor(tonumber(r.min) or 0), 0, 5256000) }
			end
		end
		table.sort(out, function(a, b) return a.pts < b.pts end)
		return out
	end
	return nil
end
P.CleanSetting = cleanValue

P.Receive("settings_set", { perm = "settings", rate = 6 }, function(ply, data)
	if not istable(data.v) then return end
	local changed = {}
	for k, v in pairs(data.v) do
		if isstring(k) and P.Defaults[k] ~= nil then
			if P.OwnerSettings[k] and not P.IsOwner(ply) then
				P.Notify(ply, "err_owner_only")
			else
				local val = cleanValue(k, v)
				if val == nil and k == "webhook_url" then P.Notify(ply, "err_webhook_url") end
				if val ~= nil then
					P.Settings[k] = val
					changed[#changed + 1] = k
				end
			end
		end
	end
	if #changed == 0 then return end
	P.SaveSettings()
	P.Log("settings", "l_settings", { A = P.LogPly(ply), V = table.concat(changed, ", ") }, { ply })
	P.SyncSettings()
	hook.Run("Praetor.SettingsChanged", changed)
end)

P.Receive("settings_reset", { perm = "settings", rate = 1 }, function(ply, data)
	local k = isstring(data.k) and data.k
	if not k or P.Defaults[k] == nil then return end
	if P.OwnerSettings[k] and not P.IsOwner(ply) then return end
	P.Settings[k] = nil
	P.SaveSettings()
	P.SyncSettings()
end)

-- ------------------------------------------------------------------ sync

local function permList()
	local out = {}
	for id, p in pairs(P.Perms) do out[#out + 1] = { id, p.cat, p.def, p.ext and 1 or 0 } end
	return out
end

local function commandList()
	local out = {}
	for id, d in pairs(P.Commands) do
		local args = {}
		for i, a in ipairs(d.args) do
			args[i] = { t = a.type, h = a.hint, o = a.optional and 1 or nil, s = a.single and 1 or nil, opt = a.options, min = a.min, max = a.max, d = (not istable(a.default)) and a.default or nil }
		end
		out[#out + 1] = { id = id, cat = d.cat, perm = d.perm, args = args, al = d.aliases, help = d.helpText, hid = d.hidden and 1 or nil, own = d.owner_only and 1 or nil, cu = d.custom and 1 or nil, pre = d.preset, ic = isstring(d.icon) and d.icon or nil }
	end
	return out
end

function P.PublicSettings()
	local t = {}
	for k in pairs(P.Defaults) do
		local v = P.Setting(k)
		if P.PrivateSettings[k] then v = (v ~= "" and v ~= nil) and "set" or "" end
		t[k] = v
	end
	return t
end

function P.BuildSync()
	return {
		ranks = P.Ranks,
		rgroups = P.RankGroups or {},
		perms = permList(),
		cmds = commandList(),
		settings = P.PublicSettings(),
		owners = P.Owners,
		titles = P.TitlePresets or {},
		wljobs = P.WhitelistJobs or {},
		bridge = { ulx = P.Bridge.hasULX, sam = P.Bridge.hasSAM, bbx = BBX ~= nil },
		ver = P.Version,
	}
end

function P.SyncTo(ply)
	P.Send(ply, "sync", P.BuildSync())
end

function P.SyncAll()
	P.Send(nil, "sync", P.BuildSync())
	hook.Run("Praetor.RanksUpdated")
end

function P.SyncSettings()
	P.Send(nil, "settings", P.PublicSettings())
end

-- Permissions and commands registered by other addons arrive in bursts while
-- the server loads, so the sync is debounced.
function P.QueuePermSync()
	if not P.Ready then return end
	timer.Create("Praetor.PermSync", 1, 1, function() P.SyncAll() end)
end

P.Receive("sync_req", { rate = 0.5 }, function(ply)
	P.SyncTo(ply)
	if P.SendPlayerExtras then P.SendPlayerExtras(ply) end
end)
