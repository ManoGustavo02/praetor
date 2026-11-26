-- Praetor Admin System
-- Loader. The file name starts with "_" so it loads before most other autorun
-- files: addons written for ULX or SAM can find the compatibility bridge early.

Praetor = Praetor or {}
Praetor.Version = "1.6.0"

local shared = {
	"sh_core.lua",
	"sh_lang.lua",
	"sh_cami.lua",
	"sh_ranks.lua",
	"sh_style.lua",
	"sh_automod.lua",
	"sh_commands.lua",
	"sh_bridge.lua",
	"sh_cmd_moderation.lua",
	"sh_cmd_player.lua",
	"sh_cmd_server.lua",
	"sh_cmd_users.lua",
	"sh_cmd_darkrp.lua",
	"sh_cmd_sits.lua",
	"sh_cmd_votes.lua",
	"sh_cmd_screen.lua",
	"sh_espguard.lua",
}

local server = {
	"sv_db.lua",
	"sv_net.lua",
	"sv_settings.lua",
	"sv_security.lua",
	"sv_ranks.lua",
	"sv_users.lua",
	"sv_bans.lua",
	"sv_banscreen.lua",
	"sv_commands.lua",
	"sv_punish.lua",
	"sv_warns.lua",
	"sv_tags.lua",
	"sv_icons.lua",
	"sv_darkrp.lua",
	"sv_limits.lua",
	"sv_anticrash.lua",
	"sv_propprotect.lua",
	"sv_logs.lua",
	"sv_logs_game.lua",
	"sv_automod.lua",
	"sv_chat.lua",
	"sv_webhook.lua",
	"sv_reports.lua",
	"sv_staffstats.lua",
	"sv_duty.lua",
	"sv_sprays.lua",
	"sv_chips.lua",
	"sv_alts.lua",
	"sv_promote.lua",
	"sv_sits.lua",
	"sv_restart.lua",
	"sv_screengrab.lua",
	"sv_custom.lua",
	"sv_restrict.lua",
	"sv_vote.lua",
	"sv_announce.lua",
	"sv_import.lua",
	"sv_menu.lua",
	"sh_workshop_guard.lua",
	"sv_loading.lua",
}

local client = {
	"cl_fonts.lua",
	"cl_theme.lua",
	"cl_widgets.lua",
	"cl_net.lua",
	"cl_notify.lua",
	"cl_vote.lua",
	"cl_announce.lua",
	"cl_banscreen.lua",
	"cl_propprotect.lua",
	"cl_icons.lua",
	"cl_style.lua",
	"cl_chat.lua",
	"cl_chatbox.lua",
	"cl_overhead.lua",
	"cl_jail.lua",
	"cl_duty.lua",
	"cl_esp.lua",
	"cl_scoreboard.lua",
	"cl_hud.lua",
	"cl_f4.lua",
	"cl_spectate.lua",
	"cl_report.lua",
	"cl_staff.lua",
	"cl_sits.lua",
	"cl_runner.lua",
	"cl_menu.lua",
	"cl_tab_players.lua",
	"cl_tab_commands.lua",
	"cl_tab_ranks.lua",
	"cl_tab_users.lua",
	"cl_tab_bans.lua",
	"cl_tab_tags.lua",
	"cl_tab_jobs.lua",
	"cl_tab_reports.lua",
	"cl_tab_sits.lua",
	"cl_tab_staff.lua",
	"cl_tab_promote.lua",
	"cl_tab_logs.lua",
	"cl_tab_automod.lua",
	"cl_tab_custom.lua",
	"cl_restrict.lua",
	"cl_tab_restrict.lua",
	"cl_tab_votes.lua",
	"cl_tab_announce.lua",
	"cl_restart.lua",
	"cl_screengrab.lua",
	"cl_tab_chips.lua",
	"cl_wiki.lua",
	"cl_tab_wiki.lua",
	"cl_tab_settings.lua",
	"cl_tab_security.lua",
	"sh_workshop_guard.lua",
}

local dir = "praetor/"

for _, f in ipairs(shared) do
	if SERVER then AddCSLuaFile(dir .. f) end
	include(dir .. f)
end

if SERVER then
	for _, f in ipairs(client) do AddCSLuaFile(dir .. f) end
	for _, f in ipairs(server) do include(dir .. f) end

	-- icons, sounds and fonts for players joining (servers using the Workshop
	-- version can also add resource.AddWorkshop with the addon id)
	local function send(folder, pattern)
		local files = file.Find(folder .. pattern, "GAME")
		for _, f in ipairs(files or {}) do resource.AddSingleFile(folder .. f) end
	end
	send("materials/praetor/icons/", "*.png")
	send("materials/praetor/", "*.png")
	send("sound/praetor/", "*.ogg")
	send("sound/praetor/music/", "*.mp3")
	send("resource/fonts/", "praetor_*.ttf")
else
	for _, f in ipairs(client) do include(dir .. f) end
end

hook.Run("Praetor.Loaded")
if SERVER then MsgC(Color(201, 147, 74), "[Praetor] v" .. Praetor.Version .. " loaded\n") end
