-- Praetor: the jail cell. A real cage that blocks players and props (one entity
-- with six collision boxes: floor, roof and four walls), drawn as metal bars with
-- the accent colour, and a sign on top with the name, the time left and the reason.
-- Spawned and removed by Praetor's !jail; it can't be picked up, removed or tooled.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Praetor Jail"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true
ENT.PhysgunDisabled = true
ENT.m_tblToolsAllowed = {}

-- inside: 96 x 96 x 112, walls 4 thick
local HALF, HIGH, T = 50, 112, 4

local function box(x1, y1, z1, x2, y2, z2)
	return {
		Vector(x1, y1, z1), Vector(x2, y1, z1), Vector(x1, y2, z1), Vector(x2, y2, z1),
		Vector(x1, y1, z2), Vector(x2, y1, z2), Vector(x1, y2, z2), Vector(x2, y2, z2),
	}
end

local function shell()
	local o = HALF + T
	return {
		box(-o, -o, -T, o, o, 0),             -- floor
		box(-o, -o, HIGH, o, o, HIGH + T),    -- roof
		box(-o, -o, 0, -HALF, o, HIGH),       -- walls
		box(HALF, -o, 0, o, o, HIGH),
		box(-HALF, -o, 0, HALF, -HALF, HIGH),
		box(-HALF, HALF, 0, HALF, o, HIGH),
	}
end

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Prisoner")
end

function ENT:Initialize()
	-- the same collision on both sides, so walking into the bars doesn't stutter
	self:PhysicsInitMultiConvex(shell())
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:EnableCustomCollisions(true)
	self:DrawShadow(false)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	if CLIENT then
		local o = HALF + T
		self:SetRenderBounds(Vector(-o, -o, -T), Vector(o, o, HIGH + 60))
	end
end

if SERVER then
	function ENT:UpdateTransmitState() return TRANSMIT_PVS end
	function ENT:CanTool() return false end
	function ENT:CanProperty() return false end
	function ENT:GravGunPickupAllowed() return false end
	function ENT:GravGunPunt() return false end
	function ENT:OnTakeDamage() end
	return
end

-- ------------------------------------------------------------------ drawing
local P = Praetor

local function accent()
	local c = P and P.UI and P.UI.C and P.UI.C.bronze
	return c or Color(142, 98, 255)
end

local METAL = Color(34, 30, 48)
local METAL_L = Color(70, 64, 96)

function ENT:Draw()
	render.SetColorMaterial()
	local o = HALF + T / 2
	local acc = accent()
	local trim = Color(acc.r, acc.g, acc.b, 255)
	local pos, ang = self:GetPos(), self:GetAngles()
	local function W(v) return LocalToWorld(v, Angle(), pos, ang) end
	-- vertical bars on the four sides
	local step = 12.5
	for s = -o, o + 0.1, step do
		for _, v in ipairs({ Vector(s, -o, 0), Vector(s, o, 0), Vector(-o, s, 0), Vector(o, s, 0) }) do
			render.DrawBox(W(v), ang, Vector(-1.1, -1.1, 0), Vector(1.1, 1.1, HIGH), METAL)
		end
	end
	-- frames: bottom, middle and top, in the accent colour
	for _, z in ipairs({ 0, HIGH * 0.5, HIGH }) do
		local th = z == HIGH * 0.5 and 1.4 or 2.4
		local col = z == HIGH * 0.5 and METAL_L or trim
		render.DrawBox(W(Vector(-o, -o, z)), ang, Vector(-th, -th, -th), Vector(o * 2 + th, th, th), col)
		render.DrawBox(W(Vector(-o, o, z)), ang, Vector(-th, -th, -th), Vector(o * 2 + th, th, th), col)
		render.DrawBox(W(Vector(-o, -o, z)), ang, Vector(-th, -th, -th), Vector(th, o * 2 + th, th), col)
		render.DrawBox(W(Vector(o, -o, z)), ang, Vector(-th, -th, -th), Vector(th, o * 2 + th, th), col)
	end
	-- roof grid
	for s = -o, o + 0.1, step * 2 do
		render.DrawBox(W(Vector(s, -o, HIGH)), ang, Vector(-1, -1, -1), Vector(1, o * 2 + 1, 1), METAL)
		render.DrawBox(W(Vector(-o, s, HIGH)), ang, Vector(-1, -1, -1), Vector(o * 2 + 1, 1, 1), METAL)
	end
	-- corner posts
	for _, v in ipairs({ Vector(-o, -o, 0), Vector(o, -o, 0), Vector(-o, o, 0), Vector(o, o, 0) }) do
		render.DrawBox(W(v), ang, Vector(-2.6, -2.6, 0), Vector(2.6, 2.6, HIGH), trim)
	end
end

-- the sign above the cell: name, time left (or permanent) and reason
function ENT:DrawTranslucent()
	if not P or not P.UI or not P.JailInfo then return end
	local ply = self:GetPrisoner()
	if not IsValid(ply) then return end
	local eye = EyePos()
	local top = self:GetPos() + Vector(0, 0, HIGH + 34)
	if eye:DistToSqr(top) > 1400 * 1400 then return end
	local info = P.JailInfo(ply)
	local ang = (eye - top):Angle()
	ang = Angle(0, ang.y + 90, 90)
	cam.Start3D2D(top + Vector(0, 0, math.sin(RealTime() * 1.5) * 1.2), ang, 0.09)
		P.DrawJailSign(ply, info)
	cam.End3D2D()
end
