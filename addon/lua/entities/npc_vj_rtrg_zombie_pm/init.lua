-- Same zombie as the Ravenholm Grabber (GOTDR grab/bite AI, Ravenholm eating, walkers only),
-- but wearing a random installed playermodel instead of a Ravenholm zombie model.
include("entities/npc_vj_rtrg_zombie/init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local math_random = math.random

local femaleWords = {"female", "alyx", "mossman", "chell", "zoey", "producer", "rochelle", "girl", "woman", "lady", "_f_", "fem", "boomette"}
local skipWords = {"skeleton", "headcrab", "zombine", "charple"}

local function HasWord(str, list)
	for _, w in ipairs(list) do
		if string.find(str, w, 1, true) then return true end
	end
	return false
end

-- Rotting skin tint and faded clothes
local skinTint = Color(195, 205, 185)

function ENT:Zombie_Init()
	if IsValid(self.Bonemerge) then return end

	-- A specific person turned (Custom Apocalypse: GFR_ForceModel/Skin/Bodygroups/Color set before Spawn)
	if self.GFR_ForceModel then
		local clothes = self.GFR_ForceColor or Vector(0.3, 0.3, 0.3)
		self:VJ_GOTDR_CreateBoneMerge(self, self.GFR_ForceModel, self.GFR_ForceSkin or 0, self.GFR_ForceTint or skinTint, "", clothes, nil, nil)
		local body = self.Bonemerge
		if IsValid(body) && body:LookupBone("ValveBiped.Bip01_Pelvis") then
			for i, v in pairs(self.GFR_ForceBodygroups or {}) do body:SetBodygroup(i, v) end
			self.RTRG_Female = HasWord(string.lower(self.GFR_ForceModel), femaleWords)
			self.GOTDR_Gender = -1
			return
		end
		if IsValid(body) then body:Remove() end
		self.Bonemerge = nil
	end

	local models = {}
	for _, mdl in pairs(player_manager.AllValidModels()) do
		if !HasWord(string.lower(mdl), skipWords) then models[#models + 1] = mdl end
	end

	-- Try a few: some playermodels aren't on the Valve skeleton and won't bonemerge
	for _ = 1, 6 do
		local mdl = models[math_random(#models)]
		if !mdl then break end
		local clothes = Vector(math.Rand(0.1, 0.45), math.Rand(0.1, 0.45), math.Rand(0.1, 0.45))
		self:VJ_GOTDR_CreateBoneMerge(self, mdl, 0, skinTint, "", clothes, nil, nil)
		local body = self.Bonemerge
		if IsValid(body) && body:LookupBone("ValveBiped.Bip01_Pelvis") then
			body:SetSkin(math_random(0, math.max(body:SkinCount() - 1, 0)))
			for i = 0, body:GetNumBodyGroups() - 1 do
				body:SetBodygroup(i, math_random(0, math.max(body:GetBodygroupCount(i) - 1, 0)))
			end
			self.RTRG_Female = HasWord(string.lower(mdl), femaleWords)
			self.GOTDR_Gender = -1
			return
		end
		if IsValid(body) then body:Remove() end
		self.Bonemerge = nil
	end

	-- No usable playermodel: fall back to a Ravenholm zombie model
	local mdl = "models/vj_cncr/zombies/zombie_male_0" .. math_random(1, 9) .. ".mdl"
	self:VJ_GOTDR_CreateBoneMerge(self, mdl, math_random(0, 2), color_white, "", false, nil, nil)
	self.GOTDR_Gender = -1
end
