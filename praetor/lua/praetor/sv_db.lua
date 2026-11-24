-- Praetor: storage (SQLite, the server's sv.db). Every value goes through
-- sql.SQLStr, so names or reasons typed by players can never break a query.
local P = Praetor
P.DB = P.DB or {}
local DB = P.DB

local function fmt(q, args)
	local i = 0
	return (q:gsub("%?", function()
		i = i + 1
		local v = args[i]
		if v == nil then return "NULL" end
		if isbool(v) then return v and "1" or "0" end
		if isnumber(v) then
			if v ~= v or v == math.huge or v == -math.huge then return "0" end
			return string.format("%d", math.floor(v))
		end
		return sql.SQLStr(tostring(v))
	end))
end

function DB.Query(q, ...)
	local full = fmt(q, { ... })
	local res = sql.Query(full)
	if res == false then
		local err = sql.LastError() or "?"
		MsgC(Color(220, 80, 80), "[Praetor] SQL error: ", err, "\n  ", full:sub(1, 300), "\n")
		return nil, err
	end
	return res or {}
end

function DB.Row(q, ...)
	local res = DB.Query(q, ...)
	return res and res[1] or nil
end

function DB.Value(q, ...)
	local row = DB.Row(q, ...)
	if not row then return nil end
	for _, v in pairs(row) do return v end
end

function DB.Begin() sql.Begin() end
function DB.Commit() sql.Commit() end

-- key/value store for json blobs (ranks, settings, custom commands...)
function DB.Get(key, default)
	local v = DB.Value("SELECT v FROM praetor_kv WHERE k = ?", key)
	if v == nil then return default end
	local t = util.JSONToTable(v)
	if t == nil then return default end
	return t
end

function DB.Set(key, value)
	DB.Query("REPLACE INTO praetor_kv (k, v) VALUES (?, ?)", key, util.TableToJSON(value) or "{}")
end

local schema = {
	[[CREATE TABLE IF NOT EXISTS praetor_kv (k TEXT PRIMARY KEY, v TEXT)]],
	[[CREATE TABLE IF NOT EXISTS praetor_sessions (
		id INTEGER PRIMARY KEY AUTOINCREMENT, started INTEGER, last INTEGER, ended INTEGER DEFAULT 0, map TEXT)]],
	[[CREATE TABLE IF NOT EXISTS praetor_users (
		sid TEXT PRIMARY KEY, name TEXT, rank TEXT DEFAULT 'user', rank_exp INTEGER DEFAULT 0, rank_prev TEXT,
		title TEXT, tag TEXT, perms TEXT, first INTEGER DEFAULT 0, last INTEGER DEFAULT 0, playtime INTEGER DEFAULT 0,
		mute_until INTEGER DEFAULT 0, gag_until INTEGER DEFAULT 0, jail_until INTEGER DEFAULT 0, names TEXT)]],
	[[CREATE TABLE IF NOT EXISTS praetor_bans (
		id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT, name TEXT, reason TEXT, admin TEXT, admin_sid TEXT,
		created INTEGER, expires INTEGER DEFAULT 0, lifted INTEGER DEFAULT 0, lifted_by TEXT)]],
	[[CREATE INDEX IF NOT EXISTS praetor_bans_sid ON praetor_bans (sid)]],
	[[CREATE TABLE IF NOT EXISTS praetor_warns (
		id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT, reason TEXT, points INTEGER DEFAULT 1,
		admin TEXT, admin_sid TEXT, created INTEGER)]],
	[[CREATE INDEX IF NOT EXISTS praetor_warns_sid ON praetor_warns (sid)]],
	[[CREATE TABLE IF NOT EXISTS praetor_notes (
		id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT, text TEXT, admin TEXT, admin_sid TEXT, created INTEGER)]],
	[[CREATE TABLE IF NOT EXISTS praetor_jobs (
		id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT, name TEXT, job TEXT, kind TEXT, reason TEXT,
		admin TEXT, admin_sid TEXT, created INTEGER, expires INTEGER DEFAULT 0)]],
	[[CREATE INDEX IF NOT EXISTS praetor_jobs_sid ON praetor_jobs (sid)]],
	[[CREATE TABLE IF NOT EXISTS praetor_logs (
		id INTEGER PRIMARY KEY AUTOINCREMENT, t INTEGER, cat TEXT, k TEXT, a TEXT, sids TEXT, txt TEXT)]],
	[[CREATE INDEX IF NOT EXISTS praetor_logs_t ON praetor_logs (t)]],
	[[CREATE TABLE IF NOT EXISTS praetor_reports (
		id INTEGER PRIMARY KEY AUTOINCREMENT, sid TEXT, name TEXT, tsid TEXT, tname TEXT, reason TEXT, text TEXT,
		created INTEGER, status TEXT DEFAULT 'open', staff_sid TEXT, staff_name TEXT, closed INTEGER DEFAULT 0, verdict TEXT)]],
	[[CREATE TABLE IF NOT EXISTS praetor_security (
		id INTEGER PRIMARY KEY AUTOINCREMENT, t INTEGER, sid TEXT, name TEXT, kind TEXT, info TEXT)]],
}

function DB.Init()
	for _, q in ipairs(schema) do
		if sql.Query(q) == false then
			MsgC(Color(220, 80, 80), "[Praetor] could not create table: ", sql.LastError() or "?", "\n")
		end
	end
end

DB.Init()
