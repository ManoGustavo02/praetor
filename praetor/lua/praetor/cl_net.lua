-- Praetor: network layer (client side) and the synced data.
local P = Praetor

P.Handlers = P.Handlers or {}
P.ServerCmds = P.ServerCmds or {}
P.TitlePresets = P.TitlePresets or {}
P.WhitelistJobs = P.WhitelistJobs or {}
P.BridgeInfo = P.BridgeInfo or {}

function P.On(op, fn) P.Handlers[op] = fn end

function P.Request(op, data)
	local packed = data and P.Pack(data) or ""
	if #packed > 65000 then
		chat.AddText(P.Col.crimson, "[Praetor] request too large")
		return
	end
	net.Start("praetor_rq")
	net.WriteString(op)
	net.WriteUInt(#packed, 16)
	if #packed > 0 then net.WriteData(packed, #packed) end
	net.SendToServer()
end

net.Receive("praetor_rs", function()
	local op = net.ReadString()
	local size = net.ReadUInt(16)
	local data = size > 0 and P.Unpack(net.ReadData(size), 4194304) or {}
	local fn = P.Handlers[op]
	if fn and istable(data) then
		local ok, err = pcall(fn, data)
		if not ok then ErrorNoHalt("[Praetor] handler '" .. op .. "': " .. tostring(err) .. "\n") end
	end
	hook.Run("Praetor.Net." .. op, data)
end)

P.On("sync", function(d)
	if istable(d.ranks) then P.Ranks = d.ranks end
	if istable(d.rgroups) then P.RankGroups = d.rgroups end
	if istable(d.perms) then
		local perms = {}
		for _, p in ipairs(d.perms) do perms[p[1]] = { id = p[1], cat = p[2], def = p[3], ext = p[4] == 1 or nil } end
		P.Perms = perms
	end
	if istable(d.cmds) then
		local cmds = {}
		for _, c in ipairs(d.cmds) do cmds[c.id] = c end
		P.ServerCmds = cmds
	end
	if istable(d.settings) then P.Settings = d.settings end
	if istable(d.owners) then P.Owners = d.owners end
	if istable(d.titles) then P.TitlePresets = d.titles end
	if istable(d.wljobs) then P.WhitelistJobs = d.wljobs end
	if istable(d.bridge) then P.BridgeInfo = d.bridge end
	P.Synced = true
	hook.Run("Praetor.Synced")
	hook.Run("Praetor.RanksUpdated")
end)

P.On("settings", function(d)
	P.Settings = d
	hook.Run("Praetor.SettingsChanged")
end)

P.On("userperms", function(d)
	local me = LocalPlayer()
	if IsValid(me) and me:SteamID64() then P.UserPerms[me:SteamID64()] = (next(d) ~= nil) and d or nil end
end)

hook.Add("InitPostEntity", "Praetor.Sync", function()
	timer.Simple(2, function() if not P.Synced then P.Request("sync_req") end end)
end)

-- Helpers for menus
function P.Me() return LocalPlayer() end
function P.MyHas(perm) return P.Has(LocalPlayer(), perm) end

function P.CanRunId(id)
	local c = P.ServerCmds[id]
	if not c then return false end
	if c.own and not P.IsOwner(LocalPlayer()) then return false end
	return P.Has(LocalPlayer(), c.perm)
end

function P.RunCmd(id, args, silent)
	P.Request("run", { id = id, args = args or {}, silent = silent or nil })
end
