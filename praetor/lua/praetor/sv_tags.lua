-- Praetor: custom tags and titles. Both work by SteamID, so they can be given
-- to players who are offline; they show up the next time the player joins.
local P = Praetor

P.TitlePresets = P.TitlePresets or {}

function P.LoadTitles()
	P.TitlePresets = {}
	for _, s in ipairs(P.DB.Get("titles", {})) do
		local c = P.CleanStyle(s, 32)
		if c then P.TitlePresets[#P.TitlePresets + 1] = c end
	end
end

local function apply(sid, column, nwkey, style, actor, logKey)
	P.EnsureUser(sid)
	local json = style and util.TableToJSON(style) or nil
	P.DB.Query("UPDATE praetor_users SET " .. column .. " = ? WHERE sid = ?", json, sid)
	local ply = P.BySID(sid)
	if IsValid(ply) then ply:SetNW2String(nwkey, json or "") end
	P.Log("rank", logKey, { A = P.LogPly(actor), T = { n = P.KnownName(sid) or sid, s = sid }, V = style and style.text or "-" }, { actor, sid })
end

function P.SetTagSID(sid, style, actor) apply(sid, "tag", "pr_tag", style, actor, "l_tag") end
function P.SetTitleSID(sid, style, actor) apply(sid, "title", "pr_title", style, actor, "l_title") end

P.Receive("tag_set", { perm = "manage_tags", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then P.Notify(ply, "err_steamid") return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	local style = data.style and P.CleanStyle(data.style, 24) or nil
	P.SetTagSID(sid, style, ply)
	P.Notify(ply, style and "ok_tag_set" or "ok_tag_clear", { S = P.KnownName(sid) or P.SID32(sid) }, "ok")
end)

P.Receive("title_set", { perm = "manage_titles", rate = 2 }, function(ply, data)
	local sid = P.ToSID64(data.sid)
	if not sid then P.Notify(ply, "err_steamid") return end
	if not P.CanTargetSID(ply, sid) then P.Notify(ply, "err_authority", { S = P.KnownName(sid) or sid }) return end
	local style = data.style and P.CleanStyle(data.style, 32) or nil
	P.SetTitleSID(sid, style, ply)
	P.Notify(ply, style and "ok_title_set" or "ok_title_clear", { S = P.KnownName(sid) or P.SID32(sid) }, "ok")
end)

P.Receive("self_tag", { perm = "self_tag", rate = 1 }, function(ply, data)
	local style = data.style and P.CleanStyle(data.style, 20) or nil
	P.SetTagSID(ply:SteamID64(), style, ply)
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("titles_save", { perm = "manage_titles", rate = 1 }, function(ply, data)
	if not istable(data.list) then return end
	local out = {}
	for i = 1, math.min(#data.list, 40) do
		local c = P.CleanStyle(data.list[i], 32)
		if c then out[#out + 1] = c end
	end
	P.TitlePresets = out
	P.DB.Set("titles", out)
	P.SyncAll()
	P.Notify(ply, "ok_saved", nil, "ok")
end)

P.Receive("tags_list", { perm = { "manage_tags", "manage_titles" }, rate = 2 }, function(ply)
	local rows = P.DB.Query("SELECT sid, name, rank, tag, title FROM praetor_users WHERE (tag IS NOT NULL AND tag != '') OR (title IS NOT NULL AND title != '') ORDER BY last DESC LIMIT 200") or {}
	P.Send(ply, "tags_list", { rows = rows })
end)
