--[[
	Custom Apocalypse - weapon slots
	You carry one weapon per slot: primary (rifles, SMGs, shotguns...), secondary (handguns), melee, throwable.
	Picking up / being given a second one for a slot drops the one you had (sv_weapons.lua).
	Fists, EFT medical tools (weapon_eft_*) and Sandbox tools don't take a slot.
]]
AddCSLuaFile()
GFR = GFR or {}

GFR.WeaponSlots = {
	{id = "primary",   name = "Primary"},
	{id = "secondary", name = "Secondary"},
	{id = "melee",     name = "Melee"},
	{id = "throwable", name = "Throwable"}
}

local free = {
	weapon_physgun = true, weapon_physcannon = true, gmod_tool = true, gmod_camera = true, weapon_medkit = true,
	weapon_fists = true, arc9_cod2019_me_fist = true, gfr_zombie_claws = true,
	arc9_eft_food_mre = true -- (food: held to eat, sv_eftmeds.lua)
}
local meleeWords = {"melee", "_me_", "knife", "crowbar", "stunstick", "machete", "hatchet", "katana", "shovel", "bayonet"}
local throwWords = {"nade", "grenade", "molotov", "flashbang", "_frag", "weapon_frag", "throw", "_smoke", "slam", "_c4"}
local pistolWords = {"_pi_", "pistol", "revolver", "_357", "deagle", "glock", "m1911", "m9a3"}
local primaryWords = {"rpg", "launcher", "crossbow", "_sm_", "_ar_", "_sh_", "_sn_", "_lm_", "_mr_"}

local function Has(class, words)
	for _, w in ipairs(words) do
		if string.find(class, w, 1, true) then return true end
	end
	return false
end

local cache = {}

-- "primary" / "secondary" / "melee" / "throwable", or nil if it doesn't take a slot
function GFR.WeaponSlot(class)
	if !class then return end
	class = string.lower(class)
	local cached = cache[class]
	if cached != nil then return cached or nil end
	local slot
	-- (weapons.Get: with what it inherits - e.g. the red flare gets its Slot from the white one's file)
	local stored = weapons.Get(class)
	-- Consumable packs (EFT meds, STALKER 2, SCP: SL) are held to use, not carried as weapons; signal flares are a tool
	if free[class] or string.StartWith(class, "weapon_eft_") or string.StartWith(class, "weapon_stalker2_") or string.StartWith(class, "weapon_scpsl_")
		or string.find(class, "rsp30", 1, true) or (GFR.IsFists && GFR.IsFists(class)) then
		slot = nil
	elseif Has(class, meleeWords) then
		slot = "melee"
	elseif Has(class, throwWords) then
		slot = "throwable"
	elseif Has(class, primaryWords) then
		slot = "primary"
	elseif Has(class, pistolWords) then
		slot = "secondary"
	elseif stored then
		local s = stored.Slot
		if s == 0 then slot = "melee"
		elseif s == 1 then slot = "secondary"
		elseif s == 4 then slot = "throwable"
		elseif s == 5 then slot = nil
		else slot = "primary" end
	else
		-- Engine weapons (HL2)
		local hl2 = {weapon_crowbar = "melee", weapon_stunstick = "melee", weapon_pistol = "secondary", weapon_357 = "secondary",
			weapon_smg1 = "primary", weapon_ar2 = "primary", weapon_shotgun = "primary", weapon_crossbow = "primary", weapon_rpg = "primary",
			weapon_frag = "throwable", weapon_slam = "throwable"}
		slot = hl2[class]
	end
	cache[class] = slot or false
	return slot
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Melee reach. The EFT melee pack uses real-world blade lengths (a knife reaches ~30 units from your eyes), so you
-- had to be touching a zombie to hit it. Every ARC9 melee weapon gets at least gfr_melee_reach, scaled up by how
-- long it really is (an axe still out-reaches a knife). Shared: ARC9 melee is predicted on both sides.
local cvReach = CreateConVar("gfr_melee_reach", "68", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Minimum reach of melee weapons (units; GMod's crowbar is 75)")

local function FixMeleeReach()
	local minReach = cvReach:GetFloat()
	for _, t in ipairs(weapons.GetList()) do
		local class = t.ClassName
		if !class or !(string.StartWith(class, "arc9_eft_melee_") or string.StartWith(class, "arc9_cod2019_me_")) then continue end
		local stored = weapons.GetStored(class)
		if !stored then continue end
		for _, key in ipairs({"BashRange", "Bash2Range"}) do
			-- Remember the original the first time, so a Lua refresh doesn't stack the boost
			local origKey = "GFR_Orig" .. key
			local orig = stored[origKey] or rawget(stored, key)
			if orig then
				stored[origKey] = orig
				stored[key] = math.max(minReach, orig * 1.6)
			end
		end
	end
	-- The base the EFT melee inherits from
	local base = weapons.GetStored("arc9_eft_melee_base")
	if base then
		for _, key in ipairs({"BashRange", "Bash2Range"}) do
			local orig = base["GFR_Orig" .. key] or rawget(base, key)
			if orig then
				base["GFR_Orig" .. key] = orig
				base[key] = math.max(minReach, orig * 1.6)
			end
		end
	end
end
hook.Add("InitPostEntity", "GFR_MeleeReach", FixMeleeReach)
if GAMEMODE then FixMeleeReach() end -- Lua refresh
cvars.AddChangeCallback("gfr_melee_reach", FixMeleeReach, "GFR_MeleeReach")

-- Knives and blades (what you can butcher a body with): knives, bayonets, machetes, the kukri, the gladius
local bladeWords = {"knife", "bayonet", "machete", "kukri", "_6x5", "a2607", "akula", "cultist", "fulcrum", "_sp8", "taiga", "gladius"}
function GFR.IsBlade(class)
	if !class then return false end
	class = string.lower(class)
	for _, w in ipairs(bladeWords) do
		if string.find(class, w, 1, true) then return true end
	end
	return false
end

function GFR.HoldingBlade(ply)
	local w = IsValid(ply) && ply:GetActiveWeapon()
	return IsValid(w) && GFR.IsBlade(w:GetClass())
end

-- The weapon this player has in a slot (or nil)
function GFR.WeaponInSlot(ply, slotId, except)
	for _, w in ipairs(ply:GetWeapons()) do
		local s = w:GetNW2String("GFR_WSlot", "")
		if s == "" then s = GFR.WeaponSlot(w:GetClass()) end
		if w != except && s == slotId then return w end
	end
end
