-- Praetor: start-up (loaded last on the server).
local P = Praetor

file.CreateDir("praetor")
file.CreateDir("praetor/backups")

P.LoadSettings()
P.LoadOwners()
P.LoadRanks()
P.LoadBans()
P.LoadTitles()
P.LoadJobConfig()
P.LoadCustom()
P.Ready = true

hook.Add("InitPostEntity", "Praetor.Start", function()
	P.PruneLogs()
	P.CAMIRegisterRanks()
	if CAMI then
		for name, priv in pairs(CAMI.GetPrivileges()) do
			if not P.Perms[name] then P.RegisterPerm(name, "addons", priv.MinAccess or "admin", true) end
		end
	end
	P.SyncAll()
	MsgC(P.Col.bronze, "[Praetor] ", P.Col.ivory, "v" .. P.Version .. " ready - ", table.Count(P.Ranks), " ranks, ", table.Count(P.Commands), " commands.\n")
	if table.Count(P.Owners) == 0 and game.IsDedicated() then
		MsgC(Color(230, 160, 60), "[Praetor] No owner set yet. Run in the server console: praetor_owner add <your SteamID>\n")
	end
end)

-- warn staff when another admin mod is running next to Praetor
hook.Add("Praetor.UserLoaded", "Praetor.Conflicts", function(ply)
	if not (P.IsOwner(ply) or ply:IsSuperAdmin()) then return end
	timer.Simple(8, function()
		if not IsValid(ply) then return end
		local realULX = ULib and not ULib.Praetor
		local realSAM = sam and not sam.Praetor
		if realULX or realSAM then
			P.Notify(ply, "n_conflict", { V = realSAM and "SAM" or "ULX" })
		end
		if table.Count(P.Owners) == 0 and game.IsDedicated() then
			P.Notify(ply, "n_no_owner")
		end
	end)
end)
