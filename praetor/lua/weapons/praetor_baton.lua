-- Praetor: staff baton. Given by !duty (staff mode), taken back when it ends.
-- It never hurts anyone. R switches the mode (Shift + R goes back); the list of
-- modes and what each button does shows on the left of the screen while it is held.
--   Hold     LMB hold: carry a player or prop   RMB while carrying: throw
--            (mouse wheel while carrying: closer / farther)
--   Freeze   LMB: freeze / unfreeze a player or prop
--   Push     LMB: push away                      RMB: pull closer
--   Teleport LMB: go to where you aim            RMB: bring the player you aim at
--   Info     LMB: who is it (rank, SteamID...)   RMB: copy the SteamID / model
--   Room     LMB: support room with the player     RMB: end your room
--   Jail     LMB: jail the player for 5 minutes    RMB: release (player or cell)
--   Watch    LMB: spectate the player              RMB: free camera
--   Remove   LMB: delete the prop you aim at
--   Cloak    LMB: turn your invisibility on / off
--   ESP      LMB: turn the staff ESP on / off
-- Every action checks the same permissions as the matching command and logs it.
AddCSLuaFile()

SWEP.PrintName = "Staff baton"
if CLIENT and Praetor and Praetor.L then SWEP.PrintName = Praetor.L("bt_title", nil, "Staff baton") end
SWEP.Author = "Praetor"
SWEP.Category = "Praetor"
SWEP.Purpose = "Staff mode tool"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.SlotPos = 6
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.ViewModelFOV = 58
SWEP.UseHands = true
SWEP.HoldType = "melee"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- id, icon, permission that the mode needs (players / props are checked again per action)
local MODES = {
	{ id = "grab",   icon = "hand" },
	{ id = "freeze", icon = "snow" },
	{ id = "push",   icon = "jump" },
	{ id = "tp",     icon = "portal" },
	{ id = "info",   icon = "info" },
	{ id = "sit",    icon = "headset" },
	{ id = "jail",   icon = "jail" },
	{ id = "spec",   icon = "eye" },
	{ id = "remove", icon = "trash" },
	{ id = "cloak",  icon = "ghost" },
	{ id = "esp",    icon = "target" },
}
local JAIL_MINUTES = 5
SWEP.Modes = MODES

local SND = {
	mode = "buttons/button14.wav", deny = "buttons/button17.wav",
	grab = "weapons/physcannon/physcannon_pickup.wav", drop = "weapons/physcannon/physcannon_drop.wav",
	throw = "weapons/physcannon/superphys_launch1.wav", freeze = "physics/glass/glass_impact_hard1.wav",
	push = "weapons/stunstick/spark1.wav", tp = "ambient/machines/teleport1.wav",
	remove = "ambient/levels/citadel/weapon_disintegrate2.wav", cloak = "buttons/blip1.wav",
	jail = "doors/heavy_metal_stop1.wav", sit = "buttons/button9.wav",
}

function SWEP:SetupDataTables()
	self:NetworkVar("Int", 0, "Mode")
	self:NetworkVar("Entity", 0, "Held")
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
	self:SendWeaponAnim(ACT_VM_DRAW)
	return true
end

function SWEP:Reload() end -- R is read in Think (switches the mode)

function SWEP:CurMode()
	return MODES[math.Clamp(self:GetMode(), 0, #MODES - 1) + 1]
end

local function aimTrace(owner, dist)
	local start = owner:GetShootPos()
	return util.TraceLine({ start = start, endpos = start + owner:GetAimVector() * (dist or 4096), filter = owner, mask = MASK_SHOT })
end
SWEP.AimTrace = aimTrace

-- ------------------------------------------------------------------ server side
if SERVER then
	local P = Praetor

	local function has(o, perm) return P and P.Has(o, perm) end

	local function deny(o, key, args)
		o:EmitSound(SND.deny, 60, 100, 0.6)
		if P then P.Notify(o, key, args or {}) end
		return false
	end

	-- may the staff touch this player / prop with the baton
	local function canPlayer(o, t, perm)
		if not has(o, perm) then return deny(o, "err_bt_perm", { V = perm }) end
		if not P.CanTarget(o, t) then return deny(o, "err_bt_immune", { S = t:Nick() }) end
		return true
	end
	local function canProp(o, e)
		if e:IsWorld() or e:IsPlayer() or e:IsWeapon() and IsValid(e:GetOwner()) then return deny(o, "err_bt_target") end
		if e:GetClass() == "praetor_jail" then return deny(o, "err_bt_target") end
		local own = e.CPPIGetOwner and e:CPPIGetOwner()
		if own == o or has(o, "pp_all") then return true end
		return deny(o, "err_bt_perm", { V = "pp_all" })
	end

	local function log(o, mode, t)
		if not P then return end
		if P.ShiftCount then P.ShiftCount(o, "baton") end
		if IsValid(t) and t:IsPlayer() then
			P.Log("cmd", "l_baton_ply", { A = P.LogPly(o), T = { P.LogPly(t) }, V = "@bt_" .. mode }, { o, t })
		elseif IsValid(t) then
			P.Log("cmd", "l_baton_prop", { A = P.LogPly(o), V = "@bt_" .. mode, V2 = t:GetModel() or t:GetClass() }, { o })
		else
			P.Log("cmd", "l_baton_self", { A = P.LogPly(o), V = "@bt_" .. mode }, { o })
		end
	end

	-- -------------------------------------------------------------- hold / throw
	function SWEP:StartGrab(t)
		local o = self:GetOwner()
		if t:IsPlayer() then
			if not canPlayer(o, t, "physgun_players") then return end
			if not t:Alive() or t:GetNW2Bool("pr_jailed") or t:InVehicle() then return deny(o, "err_bt_target") end
			t.PraetorBatonBy = o
			t:SetMoveType(MOVETYPE_NONE)
			t:SetLocalVelocity(vector_origin)
		else
			if not canProp(o, t) then return end
			local ph = t:GetPhysicsObject()
			if not IsValid(ph) then return deny(o, "err_bt_target") end
			ph:EnableMotion(true)
			ph:Wake()
		end
		self.GrabDist = math.Clamp(o:GetShootPos():Distance(t:WorldSpaceCenter()), 70, 500)
		self:SetHeld(t)
		o:EmitSound(SND.grab, 60, 100, 0.6)
		log(o, "grab", t)
	end

	function SWEP:Drop(throw)
		local t = self:GetHeld()
		self:SetHeld(NULL)
		if not IsValid(t) then return end
		local o = self:GetOwner()
		local aim = IsValid(o) and o:GetAimVector() or vector_up
		if t:IsPlayer() then
			t.PraetorBatonBy = nil
			if t:GetNW2Bool("pr_frozen") or t.PraetorPhysFrozen then
				t:SetMoveType(MOVETYPE_NONE)
			else
				t:SetMoveType(MOVETYPE_WALK)
			end
			t.PraetorNoFall = CurTime() + 6 -- the baton never hurts: no fall damage after it
			t:SetLocalVelocity(vector_origin)
			if throw then t:SetVelocity(aim * 900 + Vector(0, 0, 220)) end
		else
			local ph = t:GetPhysicsObject()
			if IsValid(ph) then
				ph:SetVelocity(throw and aim * 1600 or ph:GetVelocity() * 0.3)
			end
		end
		if IsValid(o) then
			o:EmitSound(throw and SND.throw or SND.drop, 60, 100, 0.6)
			if throw then log(o, "throw", t) end
		end
	end

	function SWEP:MoveHeld()
		local t, o = self:GetHeld(), self:GetOwner()
		local want = o:GetShootPos() + o:GetAimVector() * (self.GrabDist or 150)
		if t:IsPlayer() then
			if not t:Alive() or t:GetNW2Bool("pr_jailed") then return self:Drop() end
			local feet = want - Vector(0, 0, 36)
			t:SetPos(LerpVector(0.5, t:GetPos(), feet))
			t:SetLocalVelocity(vector_origin)
		else
			local ph = t:GetPhysicsObject()
			if not IsValid(ph) then return self:Drop() end
			ph:Wake()
			ph:SetVelocity((want - t:WorldSpaceCenter()) * 12)
			ph:AddAngleVelocity(-ph:GetAngleVelocity() * 0.4)
		end
	end

	-- -------------------------------------------------------------- the other modes
	local ACT = {}

	ACT.freeze = function(self, o, t)
		if not IsValid(t) then return end
		if t:IsPlayer() then
			if not canPlayer(o, t, "freeze") then return end
			local on = not t:GetNW2Bool("pr_frozen")
			P.Freeze(t, on)
			if not on then t.PraetorPhysFrozen = nil t:SetMoveType(MOVETYPE_WALK) end
			P.Notify(o, on and "bt_froze" or "bt_unfroze", { S = t:Nick() }, "ok")
			log(o, on and "freeze" or "unfreeze", t)
		else
			if not canProp(o, t) then return end
			local ph = t:GetPhysicsObject()
			if not IsValid(ph) then return end
			local on = ph:IsMotionEnabled()
			ph:EnableMotion(not on)
			if not on then ph:Wake() end
		end
		t:EmitSound(SND.freeze, 60, 110, 0.5)
	end

	ACT.push = function(self, o, t, pull)
		if not IsValid(t) then return end
		local dir = pull and (o:GetPos() - t:GetPos()) or o:GetAimVector()
		dir.z = 0
		dir:Normalize()
		if t:IsPlayer() then
			if not canPlayer(o, t, "slap") then return end
			if t:GetNW2Bool("pr_frozen") or t:GetNW2Bool("pr_jailed") then return deny(o, "err_bt_target") end
			if t:InVehicle() then t:ExitVehicle() end
			t.PraetorNoFall = CurTime() + 6
			t:SetVelocity(dir * (pull and 520 or 720) + Vector(0, 0, 240))
			log(o, pull and "pull" or "push", t)
		else
			if not canProp(o, t) then return end
			local ph = t:GetPhysicsObject()
			if not IsValid(ph) then return end
			ph:Wake()
			ph:SetVelocity(ph:GetVelocity() + dir * (pull and 500 or 800) + Vector(0, 0, 160))
		end
		o:EmitSound(SND.push, 60, 100, 0.6)
	end

	ACT.tp = function(self, o, t, second, tr)
		if second then
			if not IsValid(t) or not t:IsPlayer() then return deny(o, "err_bt_aim_player") end
			if not canPlayer(o, t, "bring") then return end
			if t:InVehicle() then t:ExitVehicle() end
			local spot = P.FindSpot(o, t)
			if not spot then return deny(o, "err_bt_no_room") end
			P.SaveReturn(t)
			t:SetPos(spot)
			t:SetLocalVelocity(vector_origin)
			t:EmitSound(SND.tp, 60, 100, 0.5)
			log(o, "bring", t)
			return
		end
		if not has(o, "goto") then return deny(o, "err_bt_perm", { V = "goto" }) end
		if not tr.Hit or tr.HitSky then return deny(o, "err_bt_no_room") end
		-- a free spot for our hull, walking back from the wall we aim at
		local mins, maxs = o:GetHull()
		local aim = o:GetAimVector()
		local base = tr.HitPos + tr.HitNormal * 4
		for i = 0, 12 do
			local pos = base - aim * (i * 16)
			if tr.HitNormal.z < 0.7 then pos = pos + tr.HitNormal * 18 end
			local down = util.TraceHull({ start = pos + Vector(0, 0, 8), endpos = pos - Vector(0, 0, 48), mins = mins, maxs = maxs, filter = o, mask = MASK_PLAYERSOLID })
			local spot = down.Hit and down.HitPos or pos
			local free = util.TraceHull({ start = spot + Vector(0, 0, 2), endpos = spot + Vector(0, 0, 2), mins = mins, maxs = maxs, filter = o, mask = MASK_PLAYERSOLID })
			if not free.StartSolid and not free.Hit then
				P.SaveReturn(o)
				if o:InVehicle() then o:ExitVehicle() end
				o:SetPos(spot + Vector(0, 0, 2))
				o:SetLocalVelocity(vector_origin)
				o:EmitSound(SND.tp, 60, 100, 0.5)
				return
			end
		end
		deny(o, "err_bt_no_room")
	end

	ACT.remove = function(self, o, t)
		if not IsValid(t) then return deny(o, "err_bt_aim_prop") end
		if t:IsPlayer() then return deny(o, "err_bt_target") end
		if not canProp(o, t) then return end
		log(o, "remove", t)
		local fx = EffectData()
		fx:SetEntity(t)
		util.Effect("entity_remove", fx, true, true)
		t:EmitSound(SND.remove, 70, 100, 0.6)
		SafeRemoveEntityDelayed(t, 0)
	end

	ACT.sit = function(self, o, t, second)
		if second then
			local sit = P.SitOf(o)
			if not sit then return deny(o, "err_sit_none") end
			P.EndSit(sit, o)
			P.Echo(o, "e_endsit", {})
			log(o, "sit_end")
			return
		end
		if not IsValid(t) or not t:IsPlayer() then return deny(o, "err_bt_aim_player") end
		if not canPlayer(o, t, "sit") then return end
		local ok, err, eargs = P.StartSit(o, { t }, {})
		if not ok then
			if err then P.Notify(o, err, eargs) end
			return
		end
		o:EmitSound(SND.sit, 50, 100, 0.5)
		log(o, "sit", t)
	end

	ACT.jail = function(self, o, t, second)
		-- aiming at a cell counts as aiming at the prisoner inside it
		if IsValid(t) and t:GetClass() == "praetor_jail" and t.GetPrisoner then t = t:GetPrisoner() end
		if not IsValid(t) or not t:IsPlayer() then return deny(o, "err_bt_aim_player") end
		if second then
			if not canPlayer(o, t, "unjail") then return end
			if not t:GetNW2Bool("pr_jailed", false) then return deny(o, "err_bt_not_jailed", { S = t:Nick() }) end
			P.Unjail(t, o)
			P.Echo(o, "e_unjail", { T = { t } })
			log(o, "unjail", t)
			return
		end
		if not canPlayer(o, t, "jail") then return end
		if t:GetNW2Bool("pr_jailed", false) then return deny(o, "err_bt_jailed", { S = t:Nick() }) end
		if t:InVehicle() then t:ExitVehicle() end
		P.Jail(t, JAIL_MINUTES, o, nil, "")
		P.Echo(o, "e_jail_t", { T = { t }, V = P.FormatDuration(JAIL_MINUTES), V2 = "@jail_no_reason" })
		o:EmitSound(SND.jail, 60, 100, 0.5)
		log(o, "jail", t)
	end

	ACT.spec = function(self, o, t, second)
		if not o:Alive() then return deny(o, "err_dead") end
		if second then
			if not has(o, "spectate") then return deny(o, "err_bt_perm", { V = "spectate" }) end
			P.StartSpectate(o, nil)
			return
		end
		if not IsValid(t) or not t:IsPlayer() then return deny(o, "err_bt_aim_player") end
		if not canPlayer(o, t, "spectate") then return end
		P.StartSpectate(o, t)
	end

	-- info mode: the card is drawn on the client; the server only adds the notes count
	ACT.info = function(self, o, t)
		if not IsValid(t) or not t:IsPlayer() or t:IsBot() or not has(o, "user_notes") then return end
		local n = tonumber(P.DB.Value("SELECT COUNT(*) FROM praetor_notes WHERE sid = ?", t:SteamID64())) or 0
		if n > 0 then P.Notify(o, "bt_info_notes", { S = t:Nick(), V = n }, "info") end
	end

	ACT.cloak = function(self, o)
		if not has(o, "cloak") then return deny(o, "err_bt_perm", { V = "cloak" }) end
		local on = not o:GetNW2Bool("pr_cloak")
		P.SetCloak(o, on)
		o:EmitSound(SND.cloak, 50, on and 90 or 120, 0.5)
		P.Notify(o, on and "bt_cloak_on" or "bt_cloak_off", {}, "ok")
		log(o, on and "cloak" or "uncloak")
	end

	function SWEP:Act(second)
		local o = self:GetOwner()
		if not IsValid(o) or not P then return end
		if not P.OnDuty(o) then return deny(o, "err_bt_duty") end
		local m = self:CurMode().id
		local tr = aimTrace(o, m == "tp" and 16384 or 2048)
		local t = IsValid(tr.Entity) and tr.Entity or nil
		if m == "grab" then
			if second then
				if IsValid(self:GetHeld()) then self:Drop(true) end
				return
			end
			if not t then return end
			self:StartGrab(t)
		elseif m == "freeze" then ACT.freeze(self, o, t)
		elseif m == "push" then ACT.push(self, o, t, second)
		elseif m == "tp" then ACT.tp(self, o, t, second, tr)
		elseif m == "info" then if not second then ACT.info(self, o, t) end
		elseif m == "sit" then ACT.sit(self, o, t, second)
		elseif m == "jail" then ACT.jail(self, o, t, second)
		elseif m == "spec" then ACT.spec(self, o, t, second)
		elseif m == "remove" then if not second then ACT.remove(self, o, t) end
		elseif m == "cloak" then if not second then ACT.cloak(self, o) end
		end -- esp is switched on the client
	end

	function SWEP:Think()
		local o = self:GetOwner()
		if not IsValid(o) then return end
		if o:KeyPressed(IN_RELOAD) then
			if IsValid(self:GetHeld()) then self:Drop() end
			local step = o:KeyDown(IN_SPEED) and -1 or 1
			self:SetMode((self:GetMode() + step) % #MODES)
			o:EmitSound(SND.mode, 45, 100 + self:GetMode() * 4, 0.4)
		end
		if IsValid(self:GetHeld()) then
			if not o:KeyDown(IN_ATTACK) or not o:Alive() then self:Drop() return end
			-- the mouse wheel brings what you carry closer / sends it farther
			local cmd = o:GetCurrentCommand()
			local wheel = cmd and cmd:GetMouseWheel() or 0
			if wheel ~= 0 then self.GrabDist = math.Clamp((self.GrabDist or 150) + wheel * 30, 60, 1000) end
			self:MoveHeld()
		end
	end

	function SWEP:Holster()
		self:Drop()
		return true
	end
	function SWEP:OnRemove() self:Drop() end
	function SWEP:OnDrop()
		self:Drop()
		self:Remove() -- never stays on the floor for someone else
	end

	hook.Add("PlayerDisconnected", "Praetor.Baton", function(ply)
		for _, p in player.Iterator() do
			local w = p:GetActiveWeapon()
			if IsValid(w) and w:GetClass() == "praetor_baton" and w:GetHeld() == ply then w:SetHeld(NULL) end
		end
	end)

	-- a player carried by the baton takes no damage
	hook.Add("EntityTakeDamage", "Praetor.Baton", function(ent)
		if ent:IsPlayer() and IsValid(ent.PraetorBatonBy) then return true end
	end)
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.3)
	self:SendWeaponAnim(ACT_VM_HITCENTER)
	local o = self:GetOwner()
	if IsValid(o) then o:SetAnimation(PLAYER_ATTACK1) end
	if SERVER then self:Act(false) elseif IsFirstTimePredicted() then self:ClientAct(false) end
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 0.3)
	if SERVER then self:Act(true) elseif IsFirstTimePredicted() then self:ClientAct(true) end
end

if SERVER then return end

-- ------------------------------------------------------------------ client side
local P = Praetor

-- info mode is drawn on this side: what we know about the player / prop we aim at.
-- The ESP mode only flips the praetor_esp setting of this player.
function SWEP:ClientAct(second)
	if not P then return end
	if self:CurMode().id == "esp" then
		if second or not P.EspVar then return end
		if not LocalPlayer():GetNW2Bool("pr_duty", false) then return end
		local on = not P.EspVar:GetBool()
		RunConsoleCommand("praetor_esp", on and "1" or "0")
		P.Toast(P.L("bt_esp"), P.L(on and "bt_esp_on" or "bt_esp_off"), "ok", 3)
		return
	end
	if self:CurMode().id ~= "info" then return end
	local o = self:GetOwner()
	local tr = aimTrace(o, 4096)
	local t = tr.Entity
	if not IsValid(t) then return end
	if t:IsPlayer() then
		local sid = t:SteamID()
		if second then
			SetClipboardText(sid)
			P.Toast(P.L("bt_copied"), sid, "ok", 4)
			return
		end
		local rank = P.RankOf and P.RankOf(t)
		local lines = {
			P.L("bt_info_rank", { V = rank and (rank.title or rank.name) or t:GetUserGroup() }),
			"SteamID: " .. sid,
			P.L("bt_info_hp", { V = t:Health(), V2 = t:Armor() }),
		}
		if t.getDarkRPVar then
			local job = team.GetName(t:Team())
			if job and job ~= "" then lines[#lines + 1] = P.L("bt_info_job", { V = job }) end
		end
		P.Toast(t:Nick(), table.concat(lines, "  ·  "), "info", 8)
	else
		local mdl = t:GetModel() or t:GetClass()
		if second then
			SetClipboardText(mdl)
			P.Toast(P.L("bt_copied"), mdl, "ok", 4)
			return
		end
		local sid = t:GetNW2String("pr_osid", "")
		local own = sid ~= "" and player.GetBySteamID64(sid)
		local who = IsValid(own) and own:Nick() or (sid ~= "" and sid or P.L("pp_world"))
		P.Toast(t:GetClass(), P.L("bt_info_owner", { V = who }) .. "  ·  " .. mdl, "info", 8)
	end
end

-- ------------------------------------------------------------------ the paint job
-- the HL2 stun baton in the Praetor colour, with a soft energy layer over it
local glow = Material("models/props_combine/portalball001_sheet")
local function tint()
	local c = P and P.UI and P.UI.C and P.UI.C.bronze or Color(142, 98, 255)
	return c.r / 255, c.g / 255, c.b / 255
end

function SWEP:PreDrawViewModel()
	local r, g, b = tint()
	render.SetColorModulation(0.45 + r * 0.55, 0.45 + g * 0.55, 0.45 + b * 0.55)
end

function SWEP:ViewModelDrawn(vm)
	render.SetColorModulation(1, 1, 1)
	if self.Overlay or not IsValid(vm) then return end
	self.Overlay = true
	local r, g, b = tint()
	render.MaterialOverride(glow)
	render.SetColorModulation(r, g, b)
	render.SetBlend(0.35)
	vm:DrawModel()
	render.SetBlend(1)
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride()
	self.Overlay = nil
end

function SWEP:DrawWorldModel()
	local r, g, b = tint()
	render.SetColorModulation(0.45 + r * 0.55, 0.45 + g * 0.55, 0.45 + b * 0.55)
	self:DrawModel()
	render.MaterialOverride(glow)
	render.SetColorModulation(r, g, b)
	render.SetBlend(0.35)
	self:DrawModel()
	render.SetBlend(1)
	render.MaterialOverride()
	render.SetColorModulation(1, 1, 1)
end

-- while carrying something the mouse wheel moves it, not the weapon selection
hook.Add("PlayerBindPress", "Praetor.Baton", function(ply, bind, pressed)
	if not pressed or (bind ~= "invprev" and bind ~= "invnext") then return end
	local w = ply:GetActiveWeapon()
	if IsValid(w) and w:GetClass() == "praetor_baton" and IsValid(w:GetHeld()) then return true end
end)

-- beam from the baton to what it carries
local beam = Material("sprites/physbeama")
hook.Add("PostDrawTranslucentRenderables", "Praetor.Baton", function(depth, sky)
	if depth or sky then return end
	local me = LocalPlayer()
	for _, p in player.Iterator() do
		local w = p:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "praetor_baton" and IsValid(w:GetHeld()) and (p == me or not p:GetNW2Bool("pr_cloak")) then
			local start
			if p == me and not p:ShouldDrawLocalPlayer() then
				local a = EyeAngles()
				start = EyePos() + a:Forward() * 26 + a:Right() * 8 - a:Up() * 9
			else
				local bone = p:LookupBone("ValveBiped.Bip01_R_Hand")
				start = bone and p:GetBonePosition(bone) or p:GetShootPos()
			end
			local r, g, b = tint()
			render.SetMaterial(beam)
			render.DrawBeam(start, w:GetHeld():WorldSpaceCenter(), 6, 0, 1, Color(r * 255, g * 255, b * 255, 200))
		end
	end
end)

-- ------------------------------------------------------------------ the modes on screen
-- left side, under the "on duty" card (cl_duty.lua)
function SWEP:DrawHUD()
	if not P or not P.UI then return end
	local me = LocalPlayer()
	if not IsValid(me) or me:GetNW2Bool("pr_specon", false) then return end
	local UI, C, S = P.UI, P.UI.C, P.S
	local cur = self:GetMode() + 1
	local m = MODES[cur]
	local w = S(250)
	local pad = S(12)
	local rowH = S(21)
	local inner = w - pad * 2
	local hint1 = P.L("bt_" .. m.id .. "_l")
	local hint2 = P.L("bt_" .. m.id .. "_r", nil, "")
	local hl1 = UI.Wrap(P.L("bt_lmb") .. ": " .. hint1, "Praetor.Small", inner)
	local hl2 = hint2 ~= "" and UI.Wrap(P.L("bt_rmb") .. ": " .. hint2, "Praetor.Small", inner) or {}
	local lines = #hl1 + #hl2 + 1
	local h = pad + S(22) + #MODES * rowH + S(8) + lines * S(17) + pad
	local x = S(22)
	local y = (P.DutyCardBottom and P.DutyCardBottom() or math.floor(ScrH() * 0.30)) + S(10)
	-- never over the HUD card at the bottom left
	local floor = ScrH() - S(200)
	if y + h > floor then y = math.max(S(16), floor - h) end

	UI.Comic(x, y, w, h, S(12), Color(C.panel.r, C.panel.g, C.panel.b, 235), C.edge, S(4), 190)
	UI.Text(P.L("bt_title"):upper(), "Praetor.Tiny", x + pad, y + pad + S(6), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	UI.Text("R", "Praetor.SmallB", x + w - pad, y + pad + S(6), C.bronzeL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	local ry = y + pad + S(22)
	for i, md in ipairs(MODES) do
		local sel = i == cur
		if sel then UI.Round(x + pad - S(4), ry, inner + S(8), rowH - S(2), S(6), Color(C.bronze.r, C.bronze.g, C.bronze.b, 70), C.bronze, 1) end
		local col = sel and C.ivory or C.muted
		UI.Icon(md.icon, x + pad, ry + (rowH - S(2) - 16) / 2, 16, sel and C.bronzeL or C.dim)
		UI.Text(UI.Fit(P.L("bt_" .. md.id), sel and "Praetor.SmallB" or "Praetor.Small", inner - S(26)), sel and "Praetor.SmallB" or "Praetor.Small", x + pad + S(24), ry + (rowH - S(2)) / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		ry = ry + rowH
	end

	ry = ry + S(4)
	UI.Rect(x + pad, ry, inner, 1, C.line)
	ry = ry + S(4)
	for _, l in ipairs(hl1) do UI.Text(l, "Praetor.Small", x + pad, ry, C.text) ry = ry + S(17) end
	for _, l in ipairs(hl2) do UI.Text(l, "Praetor.Small", x + pad, ry, C.text) ry = ry + S(17) end
	UI.Text(UI.Fit(P.L("bt_switch"), "Praetor.Small", inner), "Praetor.Small", x + pad, ry, C.dim)
end
