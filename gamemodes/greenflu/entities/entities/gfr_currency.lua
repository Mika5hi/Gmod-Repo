-- Custom Apocalypse - a little stash of bottle caps, the currency. Press E to take.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Caps"
ENT.Spawnable = true
ENT.Category = "Green Flu: Reimagined"

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_lab/jar01b.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() end
		self.Amount = self.Amount or math.random(3, 15)
	end

	function ENT:Use(ply)
		if !IsValid(ply) or !ply:IsPlayer() or !GFR or !GFR.AddCaps then return end
		GFR.AddCaps(ply, self.Amount)
		GFR.Notify(ply, "+ " .. self.Amount .. " caps")
		self:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 60, 140)
		self:Remove()
	end
end
