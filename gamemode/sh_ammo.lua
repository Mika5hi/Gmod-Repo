--[[
	Crunchy ammo pickups -> the ammo pool the ARC9 EFT guns actually use.

	EFT pools:
		Pistol        every pistol caliber and all SMGs (9x19, .45, 9x18, 7.62x25, 5.7, 4.6)
		SMG1          5.45 / 5.56 assault rifles (AK-74, M4, AUG, G36...)
		AR2           7.62 rifles (AKM, SKS, SVD, M700, Mosin) and 9x39 (VSS, AS VAL)
		357           .357 / .50 AE pistols, .338 / 12.7 rifles
		Buckshot      shotguns
		SMG1_Grenade  40mm launchers (M32A1, FN40GL)
		RPG_Round     RShG-2

	Crunchy's own types don't line up (its "SMG ammo" is SMG1, which EFT uses for 5.56 rifles),
	so each item is mapped by what it represents.
]]
GFR = GFR or {}

-- Tarkov's MRE (arc9_eft_food_mre) is food, but used the grenade pool: eating one used up a grenade. Its own pool.
game.AddAmmoType({name = "gfr_mre", dmgtype = DMG_GENERIC, maxcarry = 20})
hook.Add("InitPostEntity", "GFR_MREAmmo", function()
	local t = weapons.GetStored("arc9_eft_food_mre")
	if !t then return end
	t.Ammo = "gfr_mre"
	if t.Primary then t.Primary.Ammo = "gfr_mre" end
end)

GFR.AmmoGroups = {
	Pistol = "Pistol & SMG rounds (9mm, .45, 5.7)",
	SMG1 = "5.45 / 5.56 rifle rounds",
	AR2 = "7.62 rifle rounds",
	["357"] = "Magnum & heavy rounds (.357, .50, .338)",
	Buckshot = "12 gauge shells",
	SMG1_Grenade = "40mm grenades",
	RPG_Round = "Rockets",
	XBowBolt = "Crossbow bolts"
}

--[[
	Carrying rounds (sv_inventory.lua): ammo isn't kept as boxes in the bag, it's loose rounds per caliber - but those
	take bag slots (perSlot rounds to a slot). No other cap: bag room is the limit. Small rounds pack tight; the big
	ones take a slot for a few. They show in the bag as their own stacks (model: an installed ammo pickup of that
	caliber, sv_inventory.lua RoundModel; the one here if there's none), and can go into storage like any stack.
]]
GFR.AmmoRules = {
	{type = "Pistol",       perSlot = 60, model = "models/items/boxsrounds.mdl"},
	{type = "SMG1",         perSlot = 50, model = "models/items/boxmrounds.mdl"},
	{type = "AR2",          perSlot = 40, model = "models/items/boxmrounds.mdl"},
	{type = "Buckshot",     perSlot = 16, model = "models/items/boxbuckshot.mdl"},
	{type = "357",          perSlot = 20, model = "models/items/357ammo.mdl"},
	{type = "XBowBolt",     perSlot = 10, model = "models/items/crossbowrounds.mdl"},
	{type = "SMG1_Grenade", perSlot = 2,  model = "models/items/ar2_grenade.mdl"},
	{type = "RPG_Round",    perSlot = 1,  model = "models/weapons/w_missile_closed.mdl"}
}
GFR.AmmoRuleByType = {}
for _, r in ipairs(GFR.AmmoRules) do
	GFR.AmmoRuleByType[r.type] = r
	-- ARC9's own ammo boxes (its spawn menu picture in the bag, its model when there's no picture): the small pistol
	-- box for pistol & SMG rounds, the bigger one for rifle rounds. Shells, magnum rounds, bolts, 40mm grenades and
	-- rockets look like their own pickup instead (sv_inventory.lua RoundModel), so each is told apart at a glance
	local notBullets = {
		Buckshot = {"nmrih_shotgun_ammo", "zps_ammo_buckshot", "stalker_shotgun_ammo", "uh_ammo_shotgun", "pouch_shotgun_ammo", "contagion_ammo_shotgun"},
		["357"] = {"nmrih_magnum_ammo", "zps_ammo_357", "stalker_magnum_ammo", "uh_ammo_357", "pouch_magnum_ammo", "contagion_ammo_magnum"},
		XBowBolt = {"nmrih_crossbow_ammo", "contagion_ammo_arrows"},
		SMG1_Grenade = {"contagion_ammo_m79_pack", "contagion_ammo_m79", "loose_ammo_m79"},
		RPG_Round = {"stalker_rpg_ammo"}
	}
	if notBullets[r.type] then
		r.pickupIcons = notBullets[r.type] -- (their spawn menu pictures, in the bag: cl_inventory.lua)
	else
		local small = r.type == "Pistol"
		r.arc9Icon = small and "arc9_ammo" or "arc9_ammo_big"
		r.arc9Model = small and "models/items/arc9/ammo_pistol_box.mdl" or "models/items/arc9/ammo_middle_box.mdl"
	end
end

local function A(ammoType, amount) return {type = ammoType, amount = amount} end

GFR.AmmoItems = {
	-- Pistol / SMG -> Pistol
	contagion_ammo_pistol = A("Pistol", 15), loose_ammo_pistol = A("Pistol", 12), loose_ammo_pistol_alt = A("Pistol", 12),
	nmrih_pistol_ammo = A("Pistol", 10), pouch_pistol_ammo = A("Pistol", 20), stalker_pistol_ammo = A("Pistol", 20),
	uh_ammo_pistol = A("Pistol", 20), zps_ammo_pistol = A("Pistol", 20),
	contagion_ammo_smg = A("Pistol", 25), loose_ammo_smg = A("Pistol", 15), loose_ammo_smg_alt = A("Pistol", 15),
	nmrih_smg_ammo = A("Pistol", 20), pouch_smg_ammo = A("Pistol", 30), stalker_smg_ammo = A("Pistol", 30),
	uh_ammo_smg = A("Pistol", 30), zps_ammo_smg = A("Pistol", 30),
	-- Intermediate rifle -> SMG1
	contagion_ammo_rifle = A("SMG1", 30), loose_ammo_rifle = A("SMG1", 10), pouch_rifle_ammo = A("SMG1", 30),
	stalker_rifle_ammo = A("SMG1", 25), uh_ammo_rifle = A("SMG1", 30), zps_ammo_rifle = A("SMG1", 30),
	-- Full-power rifle / sniper -> AR2
	nmrih_rifle_ammo = A("AR2", 10), nmrih_rifle_ammo_mag = A("AR2", 20),
	contagion_ammo_sniper = A("AR2", 10), nmrih_sniper_ammo = A("AR2", 5), stalker_sniper_ammo = A("AR2", 10),
	uh_ammo_sniper = A("AR2", 10), zps_ammo_sniper = A("AR2", 10),
	-- Magnum / heavy -> 357
	contagion_ammo_magnum = A("357", 6), contagion_ammo_magnum_large = A("357", 12),
	loose_ammo_magnum_pistol = A("357", 6), loose_ammo_magnum_revolver = A("357", 6),
	nmrih_magnum_ammo = A("357", 6), pouch_magnum_ammo = A("357", 10), stalker_magnum_ammo = A("357", 12),
	uh_ammo_357 = A("357", 12), zps_ammo_357 = A("357", 12), pouch_sniper_ammo = A("357", 10),
	-- Shotgun
	contagion_ammo_shotgun = A("Buckshot", 8), loose_ammo_shotgun = A("Buckshot", 4), nmrih_shotgun_ammo = A("Buckshot", 6),
	pouch_shotgun_ammo = A("Buckshot", 12), stalker_shotgun_ammo = A("Buckshot", 10), uh_ammo_shotgun = A("Buckshot", 12),
	zps_ammo_buckshot = A("Buckshot", 12),
	-- Explosives
	contagion_ammo_m79 = A("SMG1_Grenade", 1), contagion_ammo_m79_pack = A("SMG1_Grenade", 3), loose_ammo_m79 = A("SMG1_Grenade", 2),
	stalker_rpg_ammo = A("RPG_Round", 1),
	-- Crossbow (MW2019 crossbow)
	contagion_ammo_arrows = A("XBowBolt", 5), nmrih_crossbow_ammo = A("XBowBolt", 5)
}

--[[
	ARC9 Modern Warfare 2019 uses its own ammo convention (9mm SMGs on SMG1, every rifle on AR2, snipers on
	SniperPenetratedRound). Remap each MW gun to its real caliber in the EFT scheme above, so the same rounds
	feed the same caliber whichever pack the gun comes from.
]]
local mwAmmo = {
	-- Assault rifles
	ar_ak47 = "AR2", ar_cr56amax = "AR2", ar_asval = "AR2", ar_fal = "AR2", ar_scar = "AR2", ar_m13 = "SMG1",
	ar_an94 = "SMG1", ar_famas = "SMG1", ar_grau556 = "SMG1", ar_kilo141 = "SMG1", ar_m4 = "SMG1", ar_ram7 = "SMG1", ar_oden = "357",
	-- Light machine guns
	lm_bruenmk9 = "SMG1", lm_holger = "SMG1", lm_sa86 = "SMG1", lm_finn = "AR2", lm_m91 = "AR2", lm_mg34 = "AR2", lm_pkm = "AR2",
	lm_raal = "357", lm_minigun = "AR2",
	-- SMGs: pistol calibers
	sm_aug = "Pistol", sm_bizon = "Pistol", sm_cx9 = "Pistol", sm_iso = "Pistol", sm_mp5 = "Pistol", sm_mp7 = "Pistol",
	sm_p90 = "Pistol", sm_striker45 = "Pistol", sm_uzi = "Pistol", sm_vector = "Pistol",
	-- Marksman / snipers
	mm_kar98k = "AR2", mm_m14 = "AR2", mm_sks = "AR2", mm_mk2 = "357", mm_spr208 = "357", mm_crossbow = "XBowBolt",
	sn_svd = "AR2", sn_ax50 = "357", sn_hdr = "357", sn_rytec = "357",
	-- Handguns
	pi_m19 = "Pistol", pi_m1911 = "Pistol", pi_renetti = "Pistol", pi_sykov = "Pistol", pi_x16 = "Pistol", pi_357 = "357", pi_50gs = "357",
	-- Shotguns
	sh_725 = "Buckshot", sh_jak12 = "Buckshot", sh_model680 = "Buckshot", sh_origin12 = "Buckshot", sh_r90 = "Buckshot", sh_vlk = "Buckshot"
}

hook.Add("InitPostEntity", "GFR_MW2019_AmmoRemap", function()
	for short, ammo in pairs(mwAmmo) do
		local t = weapons.GetStored("arc9_cod2019_" .. short)
		if t then
			t.Ammo = ammo
			t.Primary = t.Primary or {}
			t.Primary.Ammo = ammo
		end
	end
end)

-- Default unarmed weapon: MW2019's fists if installed, GMod's otherwise
function GFR.Fists()
	return weapons.GetStored("arc9_cod2019_me_fist") and "arc9_cod2019_me_fist" or "weapon_fists"
end

-- Fists are never looted, stolen, sold, dismantled or left in a death bag
function GFR.IsFists(class)
	return class == "weapon_fists" or class == "arc9_cod2019_me_fist"
end

-- Primary ammo type name of a weapon class (handles EFT variants that inherit it from a base)
function GFR.WeaponAmmo(class)
	local wep = weapons.Get(class)
	local ammo = wep && ((wep.Primary && wep.Primary.Ammo) or wep.Ammo)
	if !ammo or ammo == "" or ammo == "none" then return end
	return ammo
end

-- Is this Crunchy ammo item usable by that weapon?
function GFR.AmmoFits(itemClass, weaponClass)
	local item = GFR.AmmoItems[itemClass]
	local ammo = GFR.WeaponAmmo(weaponClass)
	return item && ammo && string.lower(item.type) == string.lower(ammo)
end
