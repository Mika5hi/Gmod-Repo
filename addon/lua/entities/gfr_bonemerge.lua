-- Custom Apocalypse - a playermodel worn on top of an (invisible) NPC, following its skeleton
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

function ENT:SetupDataTables()
	-- Read by the playermodel material proxy for clothing colour
	self:NetworkVar("Vector", 0, "PlayerColor")
end

function ENT:Initialize()
	if SERVER then
		self:SetSolid(SOLID_NONE)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
	end
	self:AddEffects(EF_BONEMERGE)
	if CLIENT then self:AddCallback("BuildBonePositions", self.Retarget) end
end

function ENT:Draw()
	self:DrawModel()
end

if SERVER then return end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Keeping the playermodel's own proportions.
-- A bonemerge copies the whole bone transform from the skeleton underneath, position included, so the body gets the
-- skeleton's limb lengths: on the L4D infected / hunter / GOTDR rig a playermodel came out stretched and squashed.
-- After the merge, every bone keeps the rotation it was given but is put back at its own model's distance from its
-- parent bone; the pelvis is raised or lowered by the difference in leg length so the feet stay on the ground.
local cvRetarget = CreateClientConVar("gfr_bonemerge_retarget", "1", true, false, "Keep playermodel proportions on zombie skeletons (0 = plain bonemerge)")
local RANGE = 3000 ^ 2 -- (further than this nobody can tell)

local rigs = {} -- [model] = {parent = {[bone] = parentBone}, offset = {[bone] = Vector}, leg = length}

local function Rig(mdl)
	local r = rigs[mdl]
	if r != nil then return r end
	rigs[mdl] = false
	local cs = ClientsideModel(mdl, RENDERGROUP_OTHER)
	if !IsValid(cs) then return false end
	cs:SetNoDraw(true)
	cs:SetupBones()
	r = {parent = {}, offset = {}, count = cs:GetBoneCount()}
	for b = 0, r.count - 1 do
		local p = cs:GetBoneParent(b)
		local mb, mp = cs:GetBoneMatrix(b), p >= 0 && cs:GetBoneMatrix(p)
		if p >= 0 && mb && mp then
			r.parent[b] = p
			r.offset[b] = WorldToLocal(mb:GetTranslation(), angle_zero, mp:GetTranslation(), mp:GetAngles())
		end
	end
	local calf, foot = cs:LookupBone("ValveBiped.Bip01_R_Calf"), cs:LookupBone("ValveBiped.Bip01_R_Foot")
	if calf && foot && r.offset[calf] && r.offset[foot] then r.leg = r.offset[calf]:Length() + r.offset[foot]:Length() end
	cs:Remove()
	rigs[mdl] = r
	return r
end

function ENT:Retarget(count)
	if !cvRetarget:GetBool() or self:GetPos():DistToSqr(EyePos()) > RANGE then return end
	local parent = self:GetParent()
	if !IsValid(parent) then return end
	local own = Rig(self:GetModel())
	if !own or own.count != count then return end

	-- Pelvis height: the skeleton's legs may be longer or shorter than ours (not for ragdolls: they lie where they fell)
	local pelvis = self:LookupBone("ValveBiped.Bip01_Pelvis")
	if pelvis && own.leg && parent:GetClass() != "prop_ragdoll" then
		local base = Rig(parent:GetModel())
		local ratio = base && base.leg && own.leg / base.leg
		if ratio && math.abs(ratio - 1) > 0.02 then
			local m = self:GetBoneMatrix(pelvis)
			if m then
				local lp = parent:WorldToLocal(m:GetTranslation())
				lp.z = lp.z * ratio
				m:SetTranslation(parent:LocalToWorld(lp))
				self:SetBoneMatrix(pelvis, m)
			end
		end
	end

	-- Every other bone: the merged rotation, our own bone length (parents come before their children)
	for b = 0, count - 1 do
		local p, off = own.parent[b], own.offset[b]
		if p then
			local m, mp = self:GetBoneMatrix(b), self:GetBoneMatrix(p)
			if m && mp then
				m:SetTranslation(LocalToWorld(off, angle_zero, mp:GetTranslation(), mp:GetAngles()))
				self:SetBoneMatrix(b, m)
			end
		end
	end
end
