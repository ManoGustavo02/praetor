-- Praetor menu: bans (online and offline, by SteamID).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local state = { q = "", all = false, page = 0 }

local function banState(r)
	if tonumber(r.lifted) == 1 then return P.L("ban_lifted"), C.laurel end
	local exp = tonumber(r.expires) or 0
	if exp > 0 and exp <= os.time() then return P.L("ban_expired"), C.dim end
	if exp == 0 then return P.L("ui_perm"), C.crimsonL end
	return P.FormatDuration(math.ceil((exp - os.time()) / 60)), C.amber
end

local function openBan(r)
	local m = UI.Modal(P.L("ban_detail") .. ": " .. tostring(r.name), S(520), S(420))
	local info = vgui.Create("DPanel", m.body)
	info:Dock(FILL)
	local st, stc = banState(r)
	local rows = {
		{ P.L("col_name"), r.name }, { "SteamID", P.SID32(r.sid) .. "   (" .. r.sid .. ")" },
		{ P.L("ban_reason"), r.reason }, { P.L("ban_admin"), r.admin },
		{ P.L("ban_created"), P.Date(tonumber(r.created)) },
		{ P.L("ban_expires"), (tonumber(r.expires) or 0) > 0 and P.Date(tonumber(r.expires)) or P.L("ui_perm") },
		{ P.L("ban_state"), st, stc },
	}
	if (r.lifted_by or "") ~= "" and r.lifted_by ~= "NULL" then rows[#rows + 1] = { P.L("ban_lifted_by"), r.lifted_by } end
	info.Paint = function(_, w)
		for i, row in ipairs(rows) do
			local y = (i - 1) * S(28)
			UI.Text(row[1], "Praetor.Small", 0, y, C.muted)
			UI.Text(UI.Fit(tostring(row[2] or "-"), "Praetor.BodyB", w - S(140)), "Praetor.BodyB", S(130), y - S(2), row[3] or C.text)
		end
	end
	local copy = UI.Button(m.foot, "SteamID", "ghost", nil, function() SetClipboardText(P.SID32(r.sid)) P.Toast(P.L("copied"), P.SID32(r.sid), "ok", 3) end)
	copy:Dock(LEFT)
	copy:SetWide(S(110))
	local active = tonumber(r.lifted) ~= 1 and ((tonumber(r.expires) or 0) == 0 or tonumber(r.expires) > os.time())
	if active and P.CanRunId("unban") then
		local lift = UI.Button(m.foot, P.L("ban_lift"), "danger", nil, function()
			UI.Confirm(P.L("ban_lift"), P.L("ban_lift_q", { S = r.name }), function()
				P.Request("ban_lift", { sid = r.sid })
				m:Close()
				timer.Simple(0.4, function() if IsValid(P.Menu) and P.Menu.current == "bans" then P.Menu:SelectTab("bans") end end)
			end, true)
		end)
		lift:Dock(RIGHT)
		lift:SetWide(S(130))
	end
	if active and P.MyHas("manage_bans") then
		local edit = UI.Button(m.foot, P.L("ban_edit"), "primary", nil, function()
			local left = (tonumber(r.expires) or 0) > 0 and math.ceil(((tonumber(r.expires) or 0) - (tonumber(r.created) or 0)) / 60) or 0
			UI.Form(P.L("ban_edit"), {
				{ "min", "duration", P.L("ban_total"), left > 0 and (left .. "m") or "perm" },
				{ "reason", "text", P.L("ban_reason"), r.reason },
			}, function(v)
				if v.min == nil then return false end
				P.Request("ban_edit", { id = r.id, min = v.min, reason = v.reason })
				m:Close()
				timer.Simple(0.4, function() if IsValid(P.Menu) and P.Menu.current == "bans" then P.Menu:SelectTab("bans") end end)
			end)
		end)
		edit:Dock(RIGHT)
		edit:SetWide(S(130))
		edit:DockMargin(0, 0, S(8), 0)
	end
end

P.AddTab("bans", {
	cat = "moderation", icon = "hammer", order = 2,
	can = function() return P.MyHas("manage_bans") or P.CanRunId("ban") or P.CanRunId("banid") or P.CanRunId("unban") end,
	build = function(panel)
		local bar = UI.Toolbar(panel)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("ban_search"), state.q), nil, FILL)
		if P.CanRunId("banid") then
			UI.Tool(bar, UI.Button(bar, P.L("ban_add"), "primary", "hammer", function()
				UI.Form(P.L("ban_add"), {
					{ "sid", "player", P.L("ui_player_or_steamid"), "" },
					{ "min", "duration", P.L("arg_time"), "1d" },
					{ "reason", "text", P.L("ban_reason"), "" },
				}, function(v)
					if v.min == nil or P.Trim(v.sid) == "" then return false end
					P.Request("ban_add", { sid = v.sid, min = v.min, reason = v.reason })
					timer.Simple(0.5, function() if IsValid(P.Menu) and P.Menu.current == "bans" then P.Menu:SelectTab("bans") end end)
				end, P.L("ban_add"))
			end), S(140), RIGHT)
		end
		UI.Tool(bar, UI.Toggle(bar, P.L("ban_show_all"), nil, state.all, function(v) state.all = v state.page = 0 P.Menu:SelectTab("bans") end), S(184), RIGHT)

		local tbl = UI.Table(panel, {
			{ P.L("col_name"), 0.25 }, { "SteamID", 0.22 }, { P.L("ban_reason"), 0.3 }, { P.L("ban_admin"), 0.15 }, { P.L("ban_state"), 0.18 }, { P.L("ban_created"), 120, TEXT_ALIGN_RIGHT },
		})
		tbl:Dock(FILL)

		local function ask() P.Request("bans_list", { q = state.q, all = state.all or nil, page = state.page }) end
		local pager = UI.Pager(panel, function(n) state.page = n ask() end)
		search.OnEnter = function(s) state.q = s:GetValue() state.page = 0 ask() end

		P.On("bans_list", function(d)
			if not IsValid(tbl) then return end
			tbl:Clear()
			pager:SetPage(d.page or 0, #d.rows > 0)
			if #d.rows == 0 then tbl:Empty(P.L("ban_none"), "hammer", P.L("ban_none_hint")) return end
			for _, r in ipairs(d.rows) do
				local st, stc = banState(r)
				tbl:AddRow({ r.name, { P.SID32(r.sid), C.muted }, r.reason, r.admin, { st, stc }, { P.Date(tonumber(r.created)), C.muted } },
					{ accent = stc, onClick = function() openBan(r) end })
			end
		end)
		ask()
	end,
})
