--[[
	Custom Apocalypse - a found weapon attachment (sh_attachments.lua)
	E picks it up into your ARC9 attachment stash; fit it to a gun at a workbench.
]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Weapon Attachment"
ENT.Spawnable = false

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Att")
end

function ENT:Initialize()
	if CLIENT then return end
	self:SetModel(util.IsValidModel("models/items/arc9/att_plastic_box.mdl") and "models/items/arc9/att_plastic_box.mdl" or "models/items/boxsrounds.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	self:SetUseType(SIMPLE_USE)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end
end

function ENT:Use(ply)
	if !IsValid(ply) or !ply:IsPlayer() or !ARC9 then return end
	local att = self:GetAtt()
	if att == "" or !ARC9.GetAttTable(att) then self:Remove() return end
	ARC9:PlayerGiveAtt(ply, att, 1)
	ARC9:PlayerSendAttInv(ply)
	self:EmitSound("items/itempickup.wav", 60)
	GFR.Notify(ply, "+ " .. GFR.AttName(att) .. "  (fit it at a Gun Table)")
	self:Remove()
end
