-- Praetor menu: every server setting, split in sections, plus the options
-- that only change this computer and the SAM / ULX importers.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

-- { key, kind, options } ; kinds: bool, number, text, choice, longtext
local SECTIONS = {
	{ "general", {
		{ "lang", "choice", { "auto", "en", "pt" } },
		{ "echo", "choice", { "all", "staff", "none" } },
		{ "perm_announce", "choice", { "all", "staff", "none" } },
		{ "prefix_silent", "text" },
		{ "adminchat_prefix", "text" },
		{ "menu_key", "text" },
	} },
	{ "protection", {
		{ "rank_lock", "bool", owner = true },
		{ "rank_lock_max", "number", owner = true },
		{ "equal_target", "bool", owner = true },
		{ "family_ban", "bool", owner = true },
		{ "family_block", "bool", owner = true },
	} },
	{ "chat", {
		{ "chat_mode", "choice", { "praetor", "tags", "off" } },
		{ "chat_avatars", "bool" },
		{ "chat_rank_tag", "bool" },
		{ "chat_local_dist", "number" },
		{ "chat_timestamps", "bool" },
		{ "chat_images", "bool" },
		{ "chat_image_size", "number" },
		{ "chat_image_hosts", "longtext" },
	} },
	{ "loading", {
		{ "loading_on", "bool" }, { "loading_name", "text" }, { "loading_sub", "text" }, { "loading_tips", "longtext" },
		{ "loading_accent", "text" }, { "loading_bg", "text" }, { "loading_logo", "text" }, { "loading_discord", "text" },
		{ "loading_music", "bool" }, { "loading_music_url", "text" }, { "loading_vol", "number" }, { "loading_base", "text", owner = true },
	} },
	{ "scoreboard", {
		{ "scoreboard", "bool" },
		{ "tab_music", "bool" }, { "menu_music", "bool" }, { "f4_music", "bool" }, { "tab_music_url", "text" }, { "tab_music_vol", "number" },
		{ "scoreboard_group", "choice", { "group", "rank", "job", "none" } },
		{ "scoreboard_title", "text" },
		{ "scoreboard_darkrp", "bool" },
	} },
	{ "darkrpui", {
		{ "hud", "bool" }, { "hud_hunger", "bool" }, { "hud_agenda", "bool" },
		{ "f4", "bool" }, { "rp_drawer", "bool" }, { "rp_aliases", "bool" },
	} },
	{ "overhead", {
		{ "overhead", "bool" }, { "overhead_dist", "number" }, { "overhead_avatar", "bool" }, { "overhead_rank", "bool" },
		{ "overhead_title", "bool" }, { "overhead_tag", "bool" }, { "overhead_job", "bool" }, { "overhead_hours", "bool" },
		{ "overhead_staff", "bool" }, { "overhead_voice", "bool" }, { "overhead_health", "bool" }, { "overhead_target", "bool" },
	} },
	{ "moderation", {
		{ "afk_time", "number" }, { "warn_decay_days", "number" }, { "warn_rules", "rules" },
		{ "physgun_players", "bool" }, { "physgun_freeze", "bool" },
		{ "sprays", "bool" },
	} },
	-- staff mode (!staffmode): each part can be turned off on its own
	{ "duty", {
		{ "duty_on", "bool" },
		{ "duty_reports", "bool" },
		{ "duty_strip", "bool" }, { "duty_baton", "bool" }, { "duty_cloak", "bool" },
		{ "duty_afk", "bool" }, { "duty_goal", "bool" },
		{ "staff_esp", "bool" }, { "esp_chams", "bool" }, { "ghost_cloaked", "bool" },
	} },
	-- E2 / Starfall: alerts, anti-lag and blocked names
	{ "chips", {
		{ "chip_alerts", "bool" }, { "chip_cpu_alert", "number" }, { "chip_esp_alert", "bool" },
		{ "chip_autostop", "bool" }, { "chip_stop_pct", "number" }, { "chip_stop_secs", "number" },
		{ "chip_lag_guard", "bool" }, { "chip_lag_pct", "number" },
		{ "chip_block_words", "longtext" }, { "esp_block", "bool" },
	} },
	{ "logs", {
		{ "log_days", "number" }, { "log_damage", "bool" }, { "log_props", "bool" },
		{ "reports", "bool" }, { "reports_cooldown", "number" }, { "reports_blackbox", "bool" }, { "report_shot", "bool" },
	} },
	{ "pvotes", {
		{ "pv_enabled", "bool" }, { "pv_ratio", "number" }, { "pv_min_votes", "number" }, { "pv_min_players", "number" },
		{ "pv_time", "number" }, { "pv_cooldown", "number" }, { "pv_ban_min", "number" }, { "pv_no_staff", "bool" },
	} },
	{ "staffsec", {
		{ "sit_auto", "bool" }, { "sit_god", "bool" }, { "sit_on_claim", "bool" },
		{ "staff_inactive_days", "number" },
		{ "alt_check", "bool" }, { "alt_action", "choice", { "alert", "kick", "ban" } },
		{ "alt_days", "number" }, { "alt_alert_all", "bool" },
		{ "sg_quality", "number" },
	} },
	{ "webhook", {
		{ "webhook_url", "secret", owner = true },
		{ "webhook_name", "text" },
		{ "webhook_lang", "choice", { "en", "pt" } },
		{ "webhook_cmd", "bool" }, { "webhook_punish", "bool" }, { "webhook_automod", "bool" }, { "webhook_report", "bool" },
		{ "webhook_rank", "bool" }, { "webhook_security", "bool" }, { "webhook_settings", "bool" }, { "webhook_chat", "bool" },
		{ "webhook_conn", "bool" }, { "webhook_kill", "bool" }, { "webhook_rp", "bool" }, { "webhook_money", "bool" },
		{ "webhook_player", "bool" }, { "webhook_round", "bool" },
	} },
	{ "spawning", {
		{ "dupe_max_ents", "number" }, { "dupe_max_cons", "number" }, { "dupe_cooldown", "number" }, { "dupe_bypass", "bool" },
		{ "dupe_announce", "choice", { "all", "staff", "none" } }, { "dupe_message", "longtext" },
		{ "dupe_block_words", "longtext" },
		{ "prop_blacklist", "longtext" },
	} },
	{ "propprotect", {
		{ "pp_enabled", "bool" }, { "pp_cleanup_min", "number" }, { "pp_world", "bool" },
		{ "pp_damage", "bool" }, { "pp_use", "bool" }, { "pp_hud", "bool" },
	} },
	{ "banscreen", {
		{ "ban_discord", "text" }, { "ban_appeal", "longtext" },
		{ "ban_screen", "bool" }, { "ban_screen_join", "bool" }, { "ban_screen_time", "number" },
		{ "ban_announce", "choice", { "all", "staff", "none" } }, { "ban_try_announce", "choice", { "all", "staff", "none" } },
	} },
	{ "anticrash", {
		{ "ac_enabled", "bool" }, { "ac_notify", "bool" },
		{ "ac_lag", "bool" }, { "ac_lag_ms", "number" }, { "ac_min_awake", "number" }, { "ac_lag_remove", "bool" },
		{ "ac_crazy", "bool" }, { "ac_spawn_freeze", "bool" }, { "ac_physenv", "bool" },
		{ "ac_unfreeze", "bool" }, { "ac_unfreeze_min", "number" },
		{ "ac_spam", "bool" }, { "ac_spam_count", "number" }, { "ac_spam_secs", "number" },
		{ "ac_net", "bool" }, { "ac_net_limit", "number" },
		{ "ac_chat", "bool" }, { "ac_chat_count", "number" }, { "ac_chat_secs", "number" },
		{ "ac_ent_cap", "number" },
	} },
	{ "darkrp", {
		{ "rp_blacklist_kick", "bool" },
	} },
}

local function send(k, v)
	P.Request("settings_set", { v = { [k] = v } })
end

local function rulesEditor(sc)
	local rules = table.Copy(P.Setting("warn_rules") or {})
	local holder = vgui.Create("DPanel", sc)
	holder:Dock(TOP)
	holder.Paint = nil
	local function rebuild()
		holder:Clear()
		holder:SetTall(#rules * S(38) + S(44))
		for i, r in ipairs(rules) do
			local row = vgui.Create("DPanel", holder)
			row:Dock(TOP)
			row:SetTall(S(34))
			row:DockMargin(0, 0, 0, S(4))
			row.Paint = function(_, w, h) UI.Text(P.L("set_rule_pts"), "Praetor.Small", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			local pts = UI.Entry(row, "3", tostring(r.pts))
			pts:SetNumeric(true)
			pts:SetPos(S(90), 0)
			pts:SetSize(S(60), S(34))
			pts.OnChange = function(s) r.pts = tonumber(s:GetValue()) or r.pts end
			local act = UI.Combo(row, { { "kick", P.L("qa_kick") }, { "ban", P.L("qa_ban") }, { "jail", P.L("qa_jail") }, { "mute", P.L("qa_mute") } }, r.act, function(v) r.act = v end)
			act:SetPos(S(160), 0)
			act:SetSize(S(130), S(34))
			local mins = UI.Entry(row, P.L("ui_duration_hint"), r.min and r.min > 0 and (r.min .. "m") or "")
			mins:SetPos(S(300), 0)
			mins:SetSize(S(120), S(34))
			mins.OnChange = function(s) r.min = P.ParseDuration(s:GetValue()) or 0 end
			local del = UI.Button(row, "x", "ghost", nil, function() table.remove(rules, i) rebuild() end)
			del:SetPos(S(428), 0)
			del:SetSize(S(34), S(34))
		end
		local bar = vgui.Create("DPanel", holder)
		bar:Dock(TOP)
		bar:SetTall(S(34))
		bar.Paint = nil
		local add = UI.Button(bar, P.L("set_rule_add"), "ghost", nil, function()
			if #rules < 8 then rules[#rules + 1] = { pts = 10, act = "ban", min = 43200 } rebuild() end
		end)
		add:Dock(LEFT)
		add:SetWide(S(150))
		local save = UI.Button(bar, P.L("ui_save"), "primary", nil, function() send("warn_rules", rules) end)
		save:Dock(LEFT)
		save:SetWide(S(120))
		save:DockMargin(S(6), 0, 0, 0)
	end
	rebuild()
end

local function settingRow(sc, def)
	local k, kind = def[1], def[2]
	local locked = def.owner and not P.IsOwner(LocalPlayer())
	local title = P.L("set_" .. k, nil, k)
	local desc = P.L("setd_" .. k, nil, "")
	if desc == "" then desc = nil end
	if locked then desc = (desc and (desc .. " ") or "") .. "(" .. P.L("owner_only") .. ")" end
	if kind == "bool" then
		local sw = UI.Switch(sc, title, desc, P.Setting(k) == true, function(v) send(k, v) end)
		sw:Dock(TOP)
		sw:DockMargin(0, 0, 0, S(2))
		if locked then sw:SetEnabled(false) end
		return
	end
	if kind == "rules" then
		local l = UI.Label(sc, title, "Praetor.BodyB", C.ivory)
		l:Dock(TOP)
		if desc then
			local d = UI.Label(sc, desc, "Praetor.Small", C.muted)
			d:SetWrap(true)
			d:SetAutoStretchVertical(true)
			d:Dock(TOP)
			d:DockMargin(0, 0, 0, S(4))
		end
		rulesEditor(sc)
		return
	end
	local row = vgui.Create("DPanel", sc)
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(2))
	local long = kind == "longtext" or kind == "secret"
	local lines = desc and UI.Wrap(desc, "Praetor.Small", S(420)) or {}
	local hgt = math.max(S(44), S(24) + #lines * S(17) + S(8))
	if long then hgt = hgt + S(40) end
	row:SetTall(hgt)
	row.Paint = function(s, w, h)
		if s:IsHovered() or s:IsChildHovered() then UI.Rect(0, 0, w, h, Color(255, 255, 255, 6)) end
		UI.Text(title, "Praetor.BodyB", S(4), S(4), locked and C.dim or C.ivory)
		for i, l in ipairs(lines) do UI.Text(l, "Praetor.Small", S(4), S(24) + (i - 1) * S(17), C.muted) end
	end
	local ctl
	if kind == "choice" then
		local opts = {}
		for _, o in ipairs(def[3]) do opts[#opts + 1] = { o, P.L("opt_" .. o, nil, o) } end
		ctl = UI.Combo(row, opts, P.Setting(k), function(v) send(k, v) end)
	elseif kind == "secret" then
		-- the server only says whether it is set; the value itself never comes back
		ctl = UI.Entry(row, P.L(P.Setting(k) == "set" and "wh_url_set" or "wh_url_hint"), "")
		local function commit()
			local v = P.Trim(ctl:GetValue())
			if v ~= "" then send(k, v) ctl:SetValue("") ctl:SetPlaceholderText(P.L("wh_url_set")) end
		end
		ctl.OnEnter = commit
		ctl.OnLoseFocus = function(s) commit() hook.Call("OnTextEntryLoseFocus", nil, s) end
	else
		ctl = UI.Entry(row, "", tostring(P.Setting(k) or ""))
		if kind == "number" then ctl:SetNumeric(true) end
		local function commit()
			local v = ctl:GetValue()
			if kind == "number" then v = tonumber(v) if not v then return end end
			if v ~= P.Setting(k) then send(k, v) end
		end
		ctl.OnEnter = commit
		ctl.OnLoseFocus = function(s) commit() hook.Call("OnTextEntryLoseFocus", nil, s) end
	end
	if locked then ctl:SetEnabled(false) end
	row.PerformLayout = function(_, w, h)
		if long then
			ctl:SetPos(S(4), h - S(38))
			ctl:SetSize(w - S(8), S(34))
		else
			local cw = kind == "number" and S(120) or S(220)
			ctl:SetPos(w - cw - S(6), (h - S(34)) / 2)
			ctl:SetSize(cw, S(34))
		end
	end
end

local function webhookButtons(sc)
	local bar = vgui.Create("DPanel", sc)
	bar:Dock(TOP)
	bar:SetTall(S(34))
	bar:DockMargin(0, S(6), 0, S(4))
	bar.Paint = nil
	local test = UI.Button(bar, P.L("wh_test_btn"), "primary", "bolt", function() P.Request("webhook_test") end)
	test:Dock(LEFT)
	test:SetWide(S(200))
	local clear = UI.Button(bar, P.L("wh_remove_btn"), "ghost", nil, function()
		UI.Confirm(P.L("wh_remove_btn"), P.L("wh_remove_q"), function() send("webhook_url", "") end, true)
	end)
	clear:Dock(LEFT)
	clear:SetWide(S(170))
	clear:DockMargin(S(8), 0, 0, 0)
end

local function clientSection(sc)
	local head = UI.Section(sc, P.L("setsec_client"), P.L("setsec_client_sub"))
	local function cv(name, title, desc)
		local var = GetConVar(name)
		if not var then return end
		local sw = UI.Switch(sc, title, desc, var:GetBool(), function(v) RunConsoleCommand(name, v and "1" or "0") end)
		sw:Dock(TOP)
	end
	cv("praetor_sounds", P.L("cl_sounds"), nil)
	cv("praetor_overhead", P.L("cl_overhead"), nil)
	cv("praetor_chatbox", P.L("cl_chatbox"), P.L("cl_chatbox_d"))
	cv("praetor_chat_images", P.L("cl_chat_images"), nil)
	cv("praetor_tab_music", P.L("cl_tab_music"), nil)
	cv("praetor_menu_music", P.L("cl_menu_music"), nil)
	if P.IsDarkRP() then cv("praetor_f4_music", P.L("cl_f4_music"), nil) end
	if P.IsDarkRP() then cv("praetor_hud", P.L("cl_hud"), nil) end
	-- interface sounds volume
	local vrow = vgui.Create("DPanel", sc)
	vrow:Dock(TOP)
	vrow:SetTall(S(44))
	vrow.Paint = function(_, w, h) UI.Text(P.L("cl_sounds_volume"), "Praetor.BodyB", S(4), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	local vsl = vgui.Create("DNumSlider", vrow)
	vsl:Dock(RIGHT)
	vsl:SetWide(S(300))
	vsl:SetMin(0)
	vsl:SetMax(100)
	vsl:SetDecimals(0)
	vsl:SetValue(GetConVar("praetor_sounds_volume") and GetConVar("praetor_sounds_volume"):GetFloat() or 100)
	vsl.Label:SetVisible(false)
	vsl.OnValueChanged = function(_, v)
		timer.Create("Praetor.SoundVol", 0.3, 1, function()
			RunConsoleCommand("praetor_sounds_volume", tostring(math.Round(v)))
			timer.Simple(0.1, function() UI.Sound("click") end)
		end)
	end
	local row = vgui.Create("DPanel", sc)
	row:Dock(TOP)
	row:SetTall(S(44))
	row.Paint = function(_, w, h) UI.Text(P.L("cl_chat_scale"), "Praetor.BodyB", S(4), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	local sl = vgui.Create("DNumSlider", row)
	sl:Dock(RIGHT)
	sl:SetWide(S(300))
	sl:SetMin(0.8)
	sl:SetMax(1.5)
	sl:SetDecimals(2)
	sl:SetValue(P.ChatScaleVar and P.ChatScaleVar:GetFloat() or 1)
	sl.Label:SetVisible(false)
	sl.OnValueChanged = function(_, v)
		timer.Create("Praetor.ChatScale", 0.4, 1, function() RunConsoleCommand("praetor_chat_scale", string.format("%.2f", v)) end)
	end
	return head
end

local function importSection(sc)
	local head = UI.Section(sc, P.L("setsec_import"), P.L("setsec_import_sub"))
	local box = vgui.Create("DPanel", sc)
	box:Dock(TOP)
	box:SetTall(S(40))
	box.Paint = nil
	local status = UI.Label(sc, P.L("ui_loading"), "Praetor.Small", C.muted)
	status:Dock(TOP)
	status:DockMargin(0, S(4), 0, 0)
	local function importBtn(from, label)
		local b = UI.Button(box, label, "primary", "scroll", function()
			UI.Confirm(label, P.L("imp_confirm", { S = string.upper(from) }), function() P.Request("import", { from = from }) end)
		end)
		b:Dock(LEFT)
		b:SetWide(S(200))
		b:DockMargin(0, 0, S(8), 0)
		b:SetEnabled(false)
		return b
	end
	local sam = importBtn("sam", P.L("imp_sam"))
	local ulx = importBtn("ulx", P.L("imp_ulx"))
	P.On("import_check", function(d)
		if not IsValid(status) then return end
		sam:SetEnabled(d.sam == true)
		ulx:SetEnabled(d.ulx == true)
		local found = {}
		if d.sam then found[#found + 1] = "SAM" end
		if d.ulx then found[#found + 1] = "ULX" end
		status:SetText(#found > 0 and P.L("imp_found", { S = table.concat(found, ", ") }) or P.L("imp_nothing"))
		status:SizeToContents()
	end)
	P.Request("import_check")
	return head
end

P.AddTab("settings", {
	cat = "server", icon = "gear", order = 2,
	can = function() return true end,
	build = function(panel)
		local nav = vgui.Create("DPanel", panel)
		nav:Dock(LEFT)
		nav:SetWide(S(180))
		nav:DockMargin(0, 0, S(12), 0)
		nav.Paint = nil
		local sc = UI.Scroll(panel)
		sc:Dock(FILL)
		local anchors = {}
		local function jump(name)
			local a = anchors[name]
			if IsValid(a) then sc:ScrollToChild(a) end
		end
		local function navBtn(name, label)
			local b = UI.Button(nav, label, "ghost", nil, function() jump(name) end)
			b:SetFont("Praetor.Small")
			b:Dock(TOP)
			b:SetTall(S(30))
			b:DockMargin(0, 0, 0, S(2))
		end

		anchors.client = clientSection(sc)
		navBtn("client", P.L("setsec_client"))

		if P.MyHas("settings") then
			for _, sec in ipairs(SECTIONS) do
				if sec[1] ~= "darkrp" or P.IsDarkRP() then
					anchors[sec[1]] = UI.Section(sc, P.L("setsec_" .. sec[1]), P.L("setsecd_" .. sec[1], nil, ""))
					navBtn(sec[1], P.L("setsec_" .. sec[1]))
					if sec[1] == "anticrash" then
						local warn = UI.Label(sc, P.L("set_ac_note"), "Praetor.Small", C.amber)
						warn:SetWrap(true)
						warn:SetAutoStretchVertical(true)
						warn:Dock(TOP)
						warn:DockMargin(0, 0, 0, S(6))
					end
					if sec[1] == "propprotect" then
						-- another prop protection (FPP from DarkRP...) in charge: say so
						local note = UI.Label(sc, "", "Praetor.Small", C.amber)
						note:SetWrap(true)
						note:SetAutoStretchVertical(true)
						note:Dock(TOP)
						note:DockMargin(0, 0, 0, S(6))
						note:SetVisible(false)
						P.PPNote = note
						P.Request("pp_state")
					end
					for _, def in ipairs(sec[2]) do settingRow(sc, def) end
					if sec[1] == "webhook" and P.IsOwner(LocalPlayer()) then webhookButtons(sc) end
				end
			end
			local reset = UI.Button(nav, P.L("set_reload"), "subtle", "gear", function() P.Request("sync_req") timer.Simple(0.5, function() if IsValid(P.Menu) then P.Menu:SelectTab("settings") end end) end)
			reset:Dock(BOTTOM)
			reset:SetTall(S(32))
		end
		if P.IsOwner(LocalPlayer()) then
			anchors.import = importSection(sc)
			navBtn("import", P.L("setsec_import"))
		end
	end,
})
