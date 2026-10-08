--[[
	Custom Apocalypse - EFT Medical Items (Workshop 3365276999) hooked into our systems
	Each med SWEP applies its effect in SWEP:Heal(owner). We run our item hook afterwards, so they also:
		tourniquet / medkits      stop bleeding (sv_infection.lua bandage/medkit lists)
		painkillers / antibiotics slow infection; the xTG-12 antidote pushes it back
		stimulants                restore stamina (sh_stats.lua nutrition)
	They're also loot (sv_loot.lua meds pools) and craftable (sh_recipes.lua).
]]
local meds = {
	"weapon_eft_afak", "weapon_eft_alusplint", "weapon_eft_anaglin", "weapon_eft_augmentin", "weapon_eft_automedkit",
	"weapon_eft_cat", "weapon_eft_grizzly", "weapon_eft_injectoradrenaline", "weapon_eft_injectoretg", "weapon_eft_injectorl1",
	"weapon_eft_injectormorphine", "weapon_eft_injectorpropital", "weapon_eft_injectortg12", "weapon_eft_salewa", "weapon_eft_surgicalkit"
}

-- Tarkov's MRE (ARC9 EFT): eaten from the hands. Its own last bite takes its one "round"; that's when it feeds you
-- (sh_stats.lua nutrition). It ran on the grenade ammo pool, so eating one used up a grenade: it has its own now (sh_ammo.lua).
local MRE = "arc9_eft_food_mre"

hook.Add("InitPostEntity", "GFR_EFTMRE_Hook", function()
	local t = weapons.GetStored(MRE)
	local full = weapons.Get(MRE)
	if !t or !full or t.GFR_Hooked then return end
	t.GFR_Hooked = true
	local take = full.TakeAmmo
	t.TakeAmmo = function(self, ...)
		local owner = self:GetOwner()
		if IsValid(owner) && owner:IsPlayer() then hook.Run("GFR_ItemUsed", owner, MRE, self) end
		if take then return take(self, ...) end
	end
end)

hook.Add("InitPostEntity", "GFR_EFTMeds_Hook", function()
	for _, class in ipairs(meds) do
		local t = weapons.GetStored(class)
		if t && t.Heal && !t.GFR_Hooked then
			local origHeal = t.Heal
			t.Heal = function(self, owner, ...)
				local r = origHeal(self, owner, ...)
				if IsValid(owner) && owner:IsPlayer() then hook.Run("GFR_ItemUsed", owner, class, self) end
				return r
			end
			t.GFR_Hooked = true
		end
	end
end)
