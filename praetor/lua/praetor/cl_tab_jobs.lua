-- Praetor menu: DarkRP jobs. Whitelist-only jobs, job bans (blacklist) and
-- whitelist entries, all by SteamID so they work offline too.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

P.AddTab("jobs", {
	cat = "management", icon = "key", order = 4,
	can = function() return P.MyHas("manage_jobs") and P.IsDarkRP() end,
	build = function(panel, data)
		local left = vgui.Create("DPanel", panel)
		left:Dock(LEFT)
		left:SetWide(S(330))
		left:DockMargin(0, 0, S(12), 0)
		left.Paint = nil
		UI.Header(left, P.L("job_list"), P.L("job_list_sub")):Dock(TOP)
		local jobs = UI.Scroll(left)
		jobs:Dock(FILL)
		jobs:DockMargin(0, S(6), 0, 0)

		local bar = UI.Toolbar(panel)
		local search = UI.Tool(bar, UI.Entry(bar, P.L("job_search"), data.sid or ""), nil, FILL)
		local add = UI.Tool(bar, UI.Button(bar, P.L("job_add"), "primary", "key"), S(170), RIGHT)
		local tbl = UI.Table(panel, { { P.L("col_name"), 0.25 }, { P.L("job_kind"), 0.12 }, { P.L("sb_job"), 0.2 }, { P.L("arg_reason"), 0.25 }, { P.L("ban_expires"), 0.18 }, { "", 70, TEXT_ALIGN_RIGHT } })
		tbl:Dock(FILL)

		local function ask() P.Request("jobs_info", { q = search:GetValue() }) end
		search.OnEnter = ask
		add.DoClick = function()
			UI.Form(P.L("job_add"), {
				{ "sid", "player", P.L("ui_player_or_steamid"), data.sid or "" },
				{ "kind", "choice", P.L("job_kind"), "bl", { { "bl", P.L("job_bl") }, { "wl", P.L("job_wl") } } },
				{ "cmd", "job", P.L("sb_job"), nil, nil, true },
				{ "min", "duration", P.L("arg_time"), "" },
				{ "reason", "text", P.L("arg_reason"), "" },
			}, function(v)
				if P.Trim(v.sid) == "" or not v.cmd then return false end
				P.Request("jobs_add", { sid = v.sid, kind = v.kind, cmd = v.cmd, min = v.min or 0, reason = v.reason })
				timer.Simple(0.4, ask)
			end, P.L("job_add"))
		end

		P.On("jobs_info", function(d)
			if not IsValid(tbl) then return end
			jobs:Clear()
			table.sort(d.jobs, function(a, b) return (a.name or "") < (b.name or "") end)
			for _, j in ipairs(d.jobs) do
				local row = vgui.Create("DPanel", jobs)
				row:Dock(TOP)
				row:SetTall(S(36))
				row:DockMargin(0, 0, 0, S(2))
				local col = P.ReadColor(j.col, C.text)
				row.Paint = function(_, w, h)
					UI.Rect(0, 0, w, h, C.panel2)
					UI.Rect(0, 0, S(4), h, col)
					UI.Text(UI.Fit(j.name, "Praetor.BodyB", w - S(150)), "Praetor.BodyB", S(12), S(4), C.ivory)
					UI.Text(j.cmd .. "  -  " .. (j.n or 0) .. " " .. P.L("online"), "Praetor.Tiny", S(12), S(22), C.dim)
				end
				local sw = vgui.Create("PraetorSwitch", row)
				sw:Setup(P.L("job_wl_only"), nil, j.wl == 1, function(v) P.Request("jobs_wlflag", { cmd = j.cmd, on = v }) end)
				sw:Dock(RIGHT)
				sw:SetWide(S(140))
			end
			tbl:Clear()
			if #d.rows == 0 then tbl:Empty(P.L("job_none"), "badge") return end
			for _, r in ipairs(d.rows) do
				local exp = tonumber(r.expires) or 0
				tbl:AddRow({
					r.name,
					{ r.kind == "wl" and P.L("job_wl") or P.L("job_bl"), r.kind == "wl" and C.laurel or C.crimsonL },
					r.job == "*" and P.L("ui_all_jobs") or r.job,
					(r.reason or "") ~= "NULL" and (r.reason or "") or "",
					{ exp > 0 and P.Date(exp) or P.L("ui_perm"), C.muted },
					{ P.L("ui_remove"), C.crimsonL },
				}, { accent = r.kind == "wl" and C.laurel or C.crimsonL, onClick = function()
					UI.Confirm(P.L("ui_remove"), P.L("job_remove_q", { S = r.name, V = r.job }), function()
						P.Request("jobs_remove", { id = r.id })
						timer.Simple(0.4, ask)
					end, true)
				end })
			end
		end)
		ask()
	end,
})
