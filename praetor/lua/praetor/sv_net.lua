-- Praetor: network layer (server side).
-- One message for every request. Each request type declares the permission it
-- needs and a rate limit; anything that fails is dropped and written to the
-- security log. Clients never send who they are: the server always uses the
-- player that sent the message.
local P = Praetor

P.Receivers = P.Receivers or {}
local buckets = {}

-- P.Receive("op", { perm = "manage_ranks", rate = 4, owner = false }, function(ply, data) end)
function P.Receive(op, opts, fn)
	P.Receivers[op] = { opts = opts or {}, fn = fn }
end

local function allowRate(ply, op, perSec)
	local key = ply:EntIndex() .. op
	local now = SysTime()
	local b = buckets[key]
	perSec = perSec or 3
	local cap = math.max(2, perSec * 2)
	if not b then
		b = { tokens = cap, t = now }
		buckets[key] = b
	end
	b.tokens = math.min(cap, b.tokens + (now - b.t) * perSec)
	b.t = now
	if b.tokens < 1 then return false end
	b.tokens = b.tokens - 1
	return true
end

hook.Add("PlayerDisconnected", "Praetor.NetBuckets", function(ply)
	local prefix = tostring(ply:EntIndex())
	for k in pairs(buckets) do
		if k:sub(1, #prefix) == prefix then buckets[k] = nil end
	end
end)

local strikes = {}
local soft = {}

-- kind: what was wrong. soft = something an honest game can also do now and then
-- (clicking very fast, a menu still open right after the rank changed): those only
-- reach the security log when they repeat many times in a minute. Messages that a
-- normal game never sends (unknown operation, giant packet) are logged at once.
local function flag(ply, kind, info, isSoft)
	local sid = P.SIDOf(ply)
	strikes[sid] = (strikes[sid] or 0) + 1
	if isSoft then
		local key = sid .. kind
		local r = soft[key]
		local now = CurTime()
		if not r or now - r.t > 60 then r = { t = now, n = 0 } soft[key] = r end
		r.n = r.n + 1
		if r.n ~= (kind == "net_rate" and 60 or 8) then return end
		info = tostring(info) .. " (x" .. r.n .. " / 60s)"
	end
	if P.Security then P.Security(ply, kind, info) end
end

net.Receive("praetor_rq", function(len, ply)
	if not IsValid(ply) or ply.PraetorBanned then return end
	if len > 8 * 65000 then flag(ply, "net_size", tostring(len)) return end

	local op = net.ReadString()
	if #op > 32 then flag(ply, "net_op", "long") return end
	local rec = P.Receivers[op]
	if not rec then flag(ply, "net_op", op) return end
	local o = rec.opts

	if not allowRate(ply, op, o.rate) then
		flag(ply, "net_rate", op, true)
		return
	end

	if o.owner and not P.IsOwner(ply) then flag(ply, "net_denied", op, true) return end
	if o.perm then
		local perms = istable(o.perm) and o.perm or { o.perm }
		local any = false
		for _, pm in ipairs(perms) do
			if P.Has(ply, pm) then any = true break end
		end
		if not any then flag(ply, "net_denied", op, true) return end
	end

	local size = net.ReadUInt(16)
	local data = {}
	if size > 0 then
		local raw = net.ReadData(size)
		data = P.Unpack(raw, o.max or 131072)
		if not istable(data) then flag(ply, "net_bad", op) return end
	end

	local ok, err = pcall(rec.fn, ply, data)
	if not ok then
		MsgC(Color(220, 80, 80), "[Praetor] error in request '", op, "': ", tostring(err), "\n")
	end
end)

-- Sends `data` to a player, a list of players, or everyone (target = nil).
function P.Send(target, op, data)
	local packed = P.Pack(data)
	if #packed > 64000 then
		MsgC(Color(220, 80, 80), "[Praetor] message '", op, "' is too big (", #packed, " bytes)\n")
		return
	end
	net.Start("praetor_rs")
	net.WriteString(op)
	net.WriteUInt(#packed, 16)
	net.WriteData(packed, #packed)
	if target == nil then net.Broadcast()
	else net.Send(target) end
end

-- Everyone online who has a permission.
function P.WithPerm(perm)
	local out = {}
	for _, p in ipairs(player.GetHumans()) do
		if P.Has(p, perm) then out[#out + 1] = p end
	end
	return out
end

-- Localised chat line: the key is translated on each client.
function P.Notify(ply, key, args, kind)
	if not IsValid(ply) then
		MsgC(P.Col.bronze, "[Praetor] ", P.Col.ivory, P.LText and P.LText("en", key, args) or key, "\n")
		return
	end
	P.Send(ply, "notify", { k = key, a = args, kind = kind })
end

-- Raw coloured chat line (used by the ULX/SAM bridge).
function P.ChatTo(ply, ...)
	local parts = {}
	for _, v in ipairs({ ... }) do
		if IsColor(v) or (istable(v) and v.r) then parts[#parts + 1] = { c = { v.r, v.g, v.b } }
		else parts[#parts + 1] = tostring(v) end
	end
	if ply == nil then P.Send(nil, "chat", parts)
	elseif IsValid(ply) then P.Send(ply, "chat", parts)
	else
		local txt = {}
		for _, v in ipairs(parts) do if isstring(v) then txt[#txt + 1] = v end end
		MsgN(table.concat(txt, ""))
	end
end

function P.Announce(ply, text)
	P.Send(IsValid(ply) and ply or nil, "announce", { t = P.Str(text, 200) })
end
