--[[
	Custom Apocalypse Project - Loot
	Uses Crunchy's Ultimate Item Pickups (Workshop 2690914262) as the item set.

	Map loot:   small stashes of themed items (pantry, medicine, ammo...) on ground spots,
	            mostly indoors, topped up over time away from the player.
	Body loot:  what a body has in its pockets depends on what it was:
	              rotten zombie   - long dead, rare sealed/durable stuff only, never fresh food
	              fresh zombie    - recently turned (player/NPC infection), still carries fresh food,
	                                goes "rotten" after gfr_fresh_minutes
	              survivor/human  - living people carry the most
	Tweaks:     Crunchy pickups no longer overheal past max. Fires GFR_ItemUsed(ply, class, ent) for stats/infection.
]]

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled   = CreateConVar("gfr_loot_enabled", "1", flags, "Enable Green Flu: Reimagined loot")
local cvMapCount  = CreateConVar("gfr_maploot_count", "40", flags, "How many loot stashes are kept on the map")
-- (Saved values were halved once for performance: sv_spawner.lua gfr_perf_half)
cookie.Set("gfr_maploot_v2", "1")
-- Map loot is topped up, and searched stashes replaced elsewhere, every gfr_loot_refresh_hours of in-game time
-- (sv_containers.lua; sleeping speeds it up). 0 = no top-ups.
local function RefreshHours() local cv = GetConVar("gfr_loot_refresh_hours") return cv and cv:GetFloat() or 12 end
local function GameHours() return GFR.GameHours and GFR.GameHours() or CurTime() / 60 end
local cvMinDist   = CreateConVar("gfr_maploot_mindist", "1200", flags, "Respawned map loot never appears closer than this to a player")
local cvFreshMins = CreateConVar("gfr_fresh_minutes", "15", flags, "Minutes a freshly turned zombie still carries fresh food")
local cvBodyMult  = CreateConVar("gfr_bodyloot_mult", "1", flags, "Multiplier for the chance that a body carries loot")
local cvNoVJDrops = CreateConVar("gfr_disable_vj_itemdrops", "1", flags, "Stop zombie NPCs dropping HL2 health kits/ammo (replaced by this loot)")
local cvClampHeal = CreateConVar("gfr_clamp_overheal", "1", flags, "Crunchy pickups can't push health/armor above max")

---------------------------------------------------------------------------------------------------------------------------------------------
-- Item pools (Crunchy classes). Missing classes are filtered out at load.
local pools = {
	-- Food, drink and meds you hold to use, with animations (sh_items.lua / sv_consumables.lua):
	-- S.T.A.L.K.E.R. 2 Consumables, plus SCP: SL painkillers and adrenaline. Repeats = more common.
	-- Shelf-stable food: cans, tins. Survives years.
	packaged = {"gfr_s2_canned", "gfr_s2_canned", "gfr_s2_canned", "gfr_s2_milk", "gfr_s2_milk", "gfr_s2_sausage",
		"arc9_eft_food_mre"}, -- (Tarkov MRE: eaten from the hands, sv_eftmeds.lua)
	-- Perishable food: only on the recently living
	fresh = {"gfr_s2_bread", "gfr_s2_bread", "gfr_s2_sausage", "gfr_s2_sausage"},
	drink = {"gfr_s2_water", "gfr_s2_water", "gfr_s2_water", "gfr_s2_water", "gfr_s2_energy", "gfr_s2_energy", "gfr_s2_vodka"},
	meds_basic = {"gfr_s2_bandage", "gfr_s2_bandage", "gfr_s2_bandage", "gfr_s2_bandage", "gfr_scp_painkillers", "gfr_scp_painkillers", "gfr_scp_painkillers"},
	meds_good = {
		"gfr_s2_medkit", "gfr_s2_medkit", "gfr_s2_medkit", "gfr_s2_medkit", "gfr_scp_adrenaline", "gfr_s2_pills_endurance",
		-- EFT Medical Items (usable meds)
		"weapon_eft_cat", "weapon_eft_anaglin", "weapon_eft_augmentin", "weapon_eft_alusplint", "weapon_eft_automedkit",
		"weapon_eft_salewa", "weapon_eft_injectormorphine"
	},
	meds_rare = {
		"gfr_s2_medkit_army", "gfr_s2_medkit_army", "gfr_s2_medkit_army", "gfr_s2_medkit_sci", "gfr_s2_medkit_sci",
		"gfr_s2_pills_revitalis", "gfr_s2_pills_revitalis", "gfr_scp_adrenaline",
		"weapon_eft_afak", "weapon_eft_grizzly", "weapon_eft_surgicalkit", "weapon_eft_injectortg12", "weapon_eft_injectoradrenaline",
		"weapon_eft_injectorpropital", "weapon_eft_injectorl1", "weapon_eft_injectoretg"
	},
	-- A few loose rounds / a pouch: what someone has in their pockets
	ammo_loose = {
		"loose_ammo_pistol", "loose_ammo_pistol_alt", "loose_ammo_smg", "loose_ammo_smg_alt", "loose_ammo_shotgun",
		"loose_ammo_rifle", "loose_ammo_magnum_pistol", "loose_ammo_magnum_revolver",
		"pouch_pistol_ammo", "pouch_smg_ammo", "pouch_shotgun_ammo", "pouch_rifle_ammo", "pouch_magnum_ammo"
	},
	-- Full boxes: found in buildings, not on bodies
	ammo_box = {
		"nmrih_pistol_ammo", "nmrih_smg_ammo", "nmrih_shotgun_ammo", "nmrih_rifle_ammo", "nmrih_magnum_ammo", "nmrih_sniper_ammo",
		"zps_ammo_pistol", "zps_ammo_smg", "zps_ammo_buckshot", "zps_ammo_rifle", "zps_ammo_357", "zps_ammo_sniper",
		"stalker_pistol_ammo", "stalker_smg_ammo", "stalker_shotgun_ammo", "stalker_rifle_ammo",
		"contagion_ammo_pistol", "contagion_ammo_smg", "contagion_ammo_shotgun", "contagion_ammo_rifle", "contagion_ammo_magnum",
		"contagion_ammo_sniper", "uh_ammo_pistol", "uh_ammo_smg", "uh_ammo_rifle", "uh_ammo_shotgun", "uh_ammo_357", "uh_ammo_sniper",
		"contagion_ammo_arrows", "nmrih_crossbow_ammo"
	},
	armor = {
		"nmrih_armor_police", "zps_kevlar", "uh_kevlar", "uh_helmet", "contagion_armor_helmet", "contagion_armor_light"
	},
	armor_rare = {
		"contagion_armor_heavy", "stalker_armor_medium"
	},
	-- Breakable supply crates that burst into themed loot
	-- (Crunchy's breakable supply crates burst into Crunchy food/meds, which the consumables above replaced)
	cache = {},
	-- Bottle caps (gfr_currency)
	currency = {"gfr_currency"},
	-- Crafting (sh_items.lua)
	materials = {"gfr_mat_scrap", "gfr_mat_scrap", "gfr_mat_cloth", "gfr_mat_cloth", "gfr_mat_wood", "gfr_mat_wood", "gfr_mat_tape",
		"gfr_mat_chem", "gfr_mat_gunpowder", "gfr_mat_parts"},
	-- Rags off the dead (zombie pockets: clothes scrap, sh_items.lua)
	cloth = {"gfr_mat_cloth"},
	notes = {}, -- (recipe notes: every recipe is known from the start now, sh_recipes.lua; an empty pool is never picked)
	-- Inventory upgrades (satchel 3x as common as a backpack)
	bags = {"gfr_item_satchel", "gfr_item_satchel", "gfr_item_satchel", "gfr_item_backpack"},

	-- ARC9 Escape from Tarkov + ARC9 Modern Warfare 2019 (arc9_cod2019_*, ammo remapped in sh_ammo.lua)
	melee = {
		"arc9_eft_melee_crowbar", "arc9_eft_melee_kukri", "arc9_eft_melee_a2607", "arc9_eft_melee_m2", "arc9_eft_melee_sp8",
		"arc9_eft_melee_taran", "arc9_eft_melee_voodoo", "arc9_eft_melee_6x5", "arc9_eft_melee_hultafors", "arc9_eft_melee_camper",
		"arc9_eft_melee_mpl50", "arc9_eft_melee_kiba", "arc9_eft_melee_cultist", "arc9_eft_melee_taiga",
		"arc9_eft_melee_fulcrum", -- (the MW2019 knife was buggy; replaced)
		"arc9_eft_melee_a2607d", "arc9_eft_melee_akula", "arc9_eft_melee_crash", "arc9_eft_melee_gladius", "arc9_eft_melee_labris",
		"arc9_eft_melee_rebel", "arc9_eft_melee_scythe", "arc9_eft_melee_wycc"
	},
	-- Civilian handguns: police, home defence, glovebox guns
	gun_pistol = {
		"arc9_eft_glock17", "arc9_eft_m9a3", "arc9_eft_m1911", "arc9_eft_pm", "arc9_eft_tt33", "arc9_eft_mp443", "arc9_eft_p226r",
		"arc9_eft_usp", "arc9_eft_pl15", "arc9_eft_fn57", "arc9_eft_aps", "arc9_eft_sr1mp", "arc9_eft_cr200ds", "arc9_eft_m45", "arc9_eft_pb",
		"arc9_cod2019_pi_m19", "arc9_cod2019_pi_m1911", "arc9_cod2019_pi_renetti", "arc9_cod2019_pi_sykov", "arc9_cod2019_pi_x16",
		"arc9_cod2019_pi_357",
		"arc9_eft_glock19x", "arc9_eft_cr50ds", "arc9_eft_apb"
	},
	-- Police/security SMGs and old surplus
	gun_smg = {
		"arc9_eft_mp5", "arc9_eft_ump", "arc9_eft_uzi", "arc9_eft_kedr", "arc9_eft_ppsh41", "arc9_eft_mp9", "arc9_eft_mpx",
		"arc9_eft_vector45", "arc9_eft_mp7a1", "arc9_eft_fn_p90", "arc9_eft_saiga9", "arc9_eft_stm9", "arc9_eft_pp1901",
		"arc9_cod2019_sm_uzi", "arc9_cod2019_sm_mp5", "arc9_cod2019_sm_bizon", "arc9_cod2019_sm_striker45", "arc9_cod2019_sm_cx9",
		"arc9_eft_glock18c", "arc9_eft_mp5k", "arc9_eft_mp7a2", "arc9_eft_mp9n", "arc9_eft_uzi_pro", "arc9_eft_vector9", "arc9_eft_sr2m"
	},
	-- Farm, hunting and home-defence shotguns
	gun_shotgun = {
		"arc9_eft_mr133", "arc9_eft_m870", "arc9_eft_m590", "arc9_eft_mr43", "arc9_eft_mr43_sawedoff", "arc9_eft_toz106",
		"arc9_eft_mr153", "arc9_eft_m3super90", "arc9_eft_saiga12k", "arc9_eft_mts255",
		"arc9_cod2019_sh_725", "arc9_cod2019_sh_model680", "arc9_cod2019_sh_r90", "arc9_cod2019_sh_vlk",
		"arc9_eft_mr155", "arc9_eft_ks23", "arc9_eft_saiga12fa"
	},
	-- Rifles a civilian or hunter might own
	gun_rifle = {
		"arc9_eft_akm", "arc9_eft_akms", "arc9_eft_ak74", "arc9_eft_ak74m", "arc9_eft_aks74u", "arc9_eft_aks74", "arc9_eft_m4a1",
		"arc9_eft_adar15", "arc9_eft_m16a2", "arc9_eft_sks", "arc9_eft_vpo136", "arc9_eft_vpo209", "arc9_eft_mosin_infantry",
		"arc9_eft_sa58", "arc9_eft_ak101", "arc9_eft_ak103",
		"arc9_cod2019_ar_ak47", "arc9_cod2019_mm_sks", "arc9_cod2019_mm_kar98k", "arc9_cod2019_mm_mk2", "arc9_cod2019_mm_m14",
		"arc9_cod2019_mm_crossbow", "arc9_cod2019_ar_cr56amax",
		"arc9_eft_mp18", "arc9_eft_vpo101", "arc9_eft_vpo215", "arc9_eft_svt", "arc9_eft_avt", "arc9_eft_tx15", "arc9_eft_rfb",
		"arc9_eft_velociraptor", "arc9_eft_radian", "arc9_eft_nl545_di", "arc9_eft_nl545_gp", "arc9_eft_sag_ak545", "arc9_eft_sag_ak545short",
		"arc9_eft_m16a1", "arc9_eft_mxlr", "arc9_eft_ak102", "arc9_eft_ak104", "arc9_eft_ak105", "arc9_eft_m1a"
	},
	-- Modern military service weapons: army lockers, cargo, checkpoints
	gun_military = {
		"arc9_cod2019_ar_m4", "arc9_cod2019_ar_m13", "arc9_cod2019_ar_kilo141", "arc9_cod2019_ar_grau556", "arc9_cod2019_ar_ram7",
		"arc9_cod2019_ar_famas", "arc9_cod2019_ar_an94", "arc9_cod2019_ar_scar", "arc9_cod2019_ar_fal", "arc9_cod2019_ar_asval",
		"arc9_cod2019_sm_mp7", "arc9_cod2019_sm_p90", "arc9_cod2019_sm_iso", "arc9_cod2019_sm_vector", "arc9_cod2019_sm_aug",
		"arc9_cod2019_sh_origin12", "arc9_cod2019_lm_sa86",
		"arc9_eft_9a91", "arc9_eft_asval", "arc9_eft_asval_mod4", "arc9_eft_sr3", "arc9_eft_vsk94", "arc9_eft_mdr", "arc9_eft_mdr556",
		"arc9_eft_mk47_mutant", "arc9_eft_rd704", "arc9_eft_auga1", "arc9_eft_aug", "arc9_eft_scarx17", "arc9_eft_spear", "arc9_eft_g36",
		"arc9_eft_mcx", "arc9_eft_rpk16"
	},
	-- Heavy, rare, high-end
	gun_rare = {
		"arc9_eft_m700", "arc9_eft_sv98", "arc9_eft_svds", "arc9_eft_mosin_sniper", "arc9_eft_hk416", "arc9_eft_ak12",
		"arc9_eft_scarl", "arc9_eft_scarh", "arc9_eft_m60e4", "arc9_eft_pkm", "arc9_eft_rpd", "arc9_eft_aa12",
		"arc9_eft_m32a1", "arc9_eft_deagle_l6", "arc9_eft_rsh12",
		"arc9_cod2019_sn_ax50", "arc9_cod2019_sn_hdr", "arc9_cod2019_sn_rytec", "arc9_cod2019_sn_svd", "arc9_cod2019_mm_spr208",
		"arc9_cod2019_ar_oden", "arc9_cod2019_sh_jak12", "arc9_cod2019_pi_50gs", "arc9_cod2019_lm_bruenmk9", "arc9_cod2019_lm_holger",
		"arc9_cod2019_lm_pkm", "arc9_cod2019_lm_m91", "arc9_cod2019_lm_mg34", "arc9_cod2019_lm_finn", "arc9_cod2019_lm_raal",
		"arc9_cod2019_la_m32", "arc9_cod2019_la_rpg", "arc9_cod2019_me_shield",
		"arc9_eft_ai_axmc", "arc9_eft_dvl10", "arc9_eft_sako_trg", "arc9_eft_t5000", "arc9_eft_mk18_mjolnir", "arc9_eft_ak50", "arc9_eft_g28",
		"arc9_eft_tkpd", "arc9_eft_ash12", "arc9_eft_vss", "arc9_eft_m60e6", "arc9_eft_pkp", "arc9_eft_deagle_l5", "arc9_eft_deagle_xix",
		"arc9_eft_fn40gl", "arc9_eft_rshg2", "arc9_eft_rsass", "arc9_eft_sr25",
		"arc9_cod2019_la_jokr", "arc9_cod2019_la_pila", "arc9_cod2019_la_strela", "arc9_cod2019_lm_minigun"
	},
	grenade = {
		"arc9_eft_f1", "arc9_eft_rgd5", "arc9_eft_m67", "arc9_eft_rgo",
		"arc9_cod2019_nade_frag", "arc9_cod2019_nade_semtex", "arc9_cod2019_nade_molotov", "arc9_cod2019_nade_molotov",
		"arc9_cod2019_nade_thermite", "arc9_cod2019_nade_flash", "arc9_cod2019_nade_stun", "arc9_cod2019_nade_smoke",
		"arc9_eft_f1_rd", "arc9_eft_rgn", "arc9_eft_v40", "arc9_eft_vog17", "arc9_eft_vog25", "arc9_eft_zarya", "arc9_eft_m7290",
		"arc9_eft_rdg2b", "arc9_eft_m18", "arc9_eft_m18y",
		-- Explosives you place (good for defending a base) and the rest of MW's throwables
		"arc9_cod2019_nade_c4", "arc9_cod2019_nade_claymores", "arc9_cod2019_nade_landmines", "arc9_cod2019_nade_gas",
		"arc9_cod2019_nade_decoy", "arc9_cod2019_nade_knife"
	}
}

local gunPools = {gun_pistol = true, gun_smg = true, gun_shotgun = true, gun_rifle = true, gun_military = true, gun_rare = true}

local profiles = {
	-- Long dead: clothes rotted, pockets mostly empty. Only things that survive time.
	-- (Zombies carry no caps: those are traded among the living. What's left of their clothes is cloth.)
	rotten = {chance = 0.22, min = 1, max = 1, weights = {ammo_loose = 30, meds_basic = 30, packaged = 25, drink = 10, armor = 5, melee = 2, cloth = 25, materials = 10}},
	-- Just turned: still has whatever they were carrying an hour ago
	fresh = {chance = 0.6, min = 1, max = 3, weights = {fresh = 25, packaged = 15, drink = 20, meds_basic = 20, meds_good = 6, ammo_loose = 14, melee = 3, gun_pistol = 1.5, cloth = 18}},
	-- Living humans (rebels, refugees, soldiers...)
	survivor = {chance = 0.85, min = 1, max = 3, weights = {packaged = 20, drink = 15, fresh = 8, meds_basic = 20, meds_good = 10, ammo_loose = 15, ammo_box = 10, armor = 2,
		melee = 4, gun_pistol = 6, gun_smg = 2, gun_shotgun = 2, gun_rifle = 2, grenade = 1, currency = 15, materials = 10, notes = 1.5, bags = 2}},
	-- World stashes: no fresh food, the world has been dead for a while
	map = {weights = {packaged = 30, drink = 20, meds_basic = 18, meds_good = 6, meds_rare = 1.5, ammo_box = 12, ammo_loose = 8, armor = 3.5, armor_rare = 0.5, cache = 1,
		melee = 3, gun_pistol = 2, gun_smg = 0.8, gun_shotgun = 1, gun_rifle = 0.6, gun_military = 0.25, gun_rare = 0.1, grenade = 0.6, currency = 5,
		materials = 18, notes = 1, bags = 1}},
	-- Faction NPCs (sv_spawner.lua). Their own gun drops separately.
	bandit = {chance = 0.9, min = 1, max = 3, weights = {packaged = 20, drink = 10, ammo_loose = 25, ammo_box = 10, meds_basic = 15, melee = 5, grenade = 2, currency = 20,
		materials = 10, notes = 1}},
	military = {chance = 0.95, min = 2, max = 4, weights = {ammo_box = 30, ammo_loose = 10, meds_good = 20, meds_basic = 15, armor = 12, grenade = 10,
		packaged = 15, meds_rare = 3, armor_rare = 1, currency = 12, materials = 6, notes = 3, bags = 3}}
}

-- Freshly turned zombies (created by infection systems from a living victim)
local freshClasses = {
	npc_vj_gotdr_zombie = true,
	npc_vj_gotdr_zombie_ply = true,
	npc_vj_cncr_infected = true
}
local hl2Zombies = {
	npc_zombie = true, npc_zombie_torso = true, npc_fastzombie = true, npc_fastzombie_torso = true,
	npc_poisonzombie = true, npc_zombine = true
}

local validPools = {}
local function BuildPools()
	for name, list in pairs(pools) do
		local valid = {}
		for _, class in ipairs(list) do
			if scripted_ents.GetStored(class) or weapons.GetStored(class) then valid[#valid + 1] = class end
		end
		validPools[name] = valid
	end
end

local function PickPool(weights, freshScale)
	local total = 0
	for name, w in pairs(weights) do
		if name == "fresh" then w = w * (freshScale or 1) end
		if validPools[name] && #validPools[name] > 0 then total = total + w end
	end
	if total <= 0 then return end
	local roll = math.Rand(0, total)
	for name, w in pairs(weights) do
		if name == "fresh" then w = w * (freshScale or 1) end
		if validPools[name] && #validPools[name] > 0 then
			roll = roll - w
			if roll <= 0 then return name end
		end
	end
end

local function PickItem(poolName)
	local list = poolName && validPools[poolName]
	if !list or #list == 0 then return end
	return list[math.random(#list)]
end

local function SpawnItem(class, pos)
	local ent = ents.Create(class)
	if !IsValid(ent) then return end
	ent:SetPos(pos)
	ent:SetAngles(Angle(0, math.random(0, 359), 0))
	ent:Spawn()
	ent:Activate()
	ent.GFR_Loot = true
	-- Found guns are never fully loaded
	if ent:IsWeapon() && ent:GetMaxClip1() > 0 then
		ent:SetClip1(math.random(0, math.ceil(ent:GetMaxClip1() / 2)))
	end
	return ent
end

-- A random Crunchy ammo item that fits this gun
local function AmmoItemFor(weaponClass)
	local fits = {}
	for item in pairs(GFR.AmmoItems or {}) do
		if scripted_ents.GetStored(item) && GFR.AmmoFits(item, weaponClass) then fits[#fits + 1] = item end
	end
	return fits[math.random(#fits)]
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Body loot
local function IsZombie(ent)
	if ent.VJ_ID_Undead or hl2Zombies[ent:GetClass()] then return true end
	local cls = ent.VJ_NPC_Class
	if istable(cls) then
		for _, c in ipairs(cls) do
			if c == "CLASS_ZOMBIE" then return true end
		end
	end
	return ent:IsNPC() && ent:Classify() == CLASS_ZOMBIE
end

-- Where infected victims recently got replaced by a fresh zombie (so the victim doesn't drop loot twice)
local recentTurns = {}

hook.Add("OnEntityCreated", "GFR_Loot_TrackSpawns", function(ent)
	timer.Simple(0, function()
		if !IsValid(ent) then return end
		if freshClasses[ent:GetClass()] then
			ent.GFR_TurnedAt = CurTime()
			recentTurns[#recentTurns + 1] = {pos = ent:GetPos(), time = CurTime()}
		end
		if cvNoVJDrops:GetBool() && ent.IsVJBaseSNPC && IsZombie(ent) then
			ent.DropDeathLoot = false
		end
	end)
end)

local function TurnedNearby(pos)
	local now = CurTime()
	for i = #recentTurns, 1, -1 do
		local t = recentTurns[i]
		if now - t.time > 3 then
			table.remove(recentTurns, i)
		elseif t.pos:DistToSqr(pos) < 96 * 96 then
			return true
		end
	end
	return false
end

local function GetBodyProfile(npc)
	-- Faction NPCs carry their faction's loot
	if npc.GFR_LootProfile && profiles[npc.GFR_LootProfile] then
		return profiles[npc.GFR_LootProfile], 1
	end
	if IsZombie(npc) then
		local turnedAt = npc.GFR_TurnedAt
		if turnedAt then
			local freshness = 1 - (CurTime() - turnedAt) / math.max(cvFreshMins:GetFloat() * 60, 1)
			if freshness > 0 then return profiles.fresh, freshness end
		end
		return profiles.rotten, 0
	end
	if npc:LookupBone("ValveBiped.Bip01_Pelvis") then
		return profiles.survivor, 1
	end
	-- Animals, headcrabs, antlions, robots: nothing in their pockets
end

-- Chance that food/drink from a zombie body is contaminated with its blood (see gfr_infection.lua)
local contaminationRisk = {fresh = 0.6, drink = 0.2}

-- Body loot stays in the corpse's pockets: Q on the body to search it (sv_harvest.lua).
-- Matched to the ragdoll by position; NPCs without a server ragdoll fall back to dropping it on the floor.
local pendingPockets = {}  -- {pos, items, time}
local recentRagdolls = {}  -- {ent, time}

local function SpillItems(pos, items)
	for i, it in ipairs(items) do
		local item = SpawnItem(it.class, pos + Vector(math.Rand(-16, 16), math.Rand(-16, 16), 8 + i * 4))
		if IsValid(item) && it.contaminated then
			item.GFR_Contaminated = true
			item:SetColor(Color(190, 120, 115))
		end
	end
end

local function AttachPockets(rag, items)
	rag.GFR_Pockets = items
	rag:SetNW2Bool("GFR_HasPockets", true)
end

hook.Add("OnEntityCreated", "GFR_Loot_TrackRagdolls", function(ent)
	if ent:GetClass() != "prop_ragdoll" then return end
	timer.Simple(0.1, function()
		if !IsValid(ent) then return end
		local pos = ent:GetPos()
		for i, p in ipairs(pendingPockets) do
			if p.pos:DistToSqr(pos) < 160 * 160 then
				AttachPockets(ent, p.items)
				table.remove(pendingPockets, i)
				return
			end
		end
		recentRagdolls[#recentRagdolls + 1] = {ent = ent, time = CurTime()}
		if #recentRagdolls > 30 then table.remove(recentRagdolls, 1) end
	end)
end)

-- Nobody's ragdoll showed up (e.g. a client-side ragdoll): drop it like before
timer.Create("GFR_Loot_PendingPockets", 1, 0, function()
	for i = #pendingPockets, 1, -1 do
		local p = pendingPockets[i]
		if CurTime() - p.time > 8 then
			SpillItems(p.pos, p.items)
			table.remove(pendingPockets, i)
		end
	end
end)

local function DropBodyLoot(npc)
	if !IsValid(npc) then return end
	-- A companion's pockets hold exactly what you gave them (sv_companions.lua)
	local fixed = npc.GFR_CompItems
	-- What they picked up searching containers (sv_groupwander.lua) is on them too
	local scavenged = npc.GFR_Scavenged
	if !fixed && !cvEnabled:GetBool() then return end
	local profile, freshness
	local rolled = true
	if !fixed then
		profile, freshness = GetBodyProfile(npc)
		if !profile && !scavenged then return end
		if !profile or math.Rand(0, 1) > profile.chance * cvBodyMult:GetFloat() then
			if !scavenged then return end
			rolled = false
		end
	end

	local basePos = npc:GetPos()
	local count = (fixed or !rolled) and 0 or math.random(profile.min, profile.max)
	local wasHuman = !IsZombie(npc)
	timer.Simple(0.3, function()
		-- An infection mod replaced this victim with a fresh zombie: the zombie keeps the loot instead
		if !fixed && wasHuman && TurnedNearby(basePos + Vector(0, 0, 36)) then return end
		local items = {}
		for _, e in ipairs(fixed or {}) do
			for _ = 1, e.count do items[#items + 1] = {class = e.class, contaminated = e.contaminated or nil} end
		end
		for _, class in ipairs(scavenged or {}) do items[#items + 1] = {class = class} end
		for _ = 1, count do
			local poolName = PickPool(profile.weights, freshness)
			local class = PickItem(poolName)
			if class then
				-- Open food/drink carried by a zombie is soaked in its blood (cans and sealed packs are safe)
				local risk = !wasHuman && contaminationRisk[poolName]
				items[#items + 1] = {class = class, contaminated = risk && math.Rand(0, 1) < risk or nil}
			end
		end
		if #items == 0 then return end

		-- The ragdoll may already exist (our human corpses), or come later (VJ death animations)
		local now = CurTime()
		for i = #recentRagdolls, 1, -1 do
			local r = recentRagdolls[i]
			if !IsValid(r.ent) or now - r.time > 6 then
				table.remove(recentRagdolls, i)
			elseif !r.ent.GFR_Pockets && r.ent:GetPos():DistToSqr(basePos) < 160 * 160 then
				AttachPockets(r.ent, items)
				table.remove(recentRagdolls, i)
				return
			end
		end
		pendingPockets[#pendingPockets + 1] = {pos = basePos, items = items, time = now}
	end)
end
GFR.SpillItems = SpillItems

hook.Add("OnNPCKilled", "GFR_Loot_BodyDrops", function(npc)
	DropBodyLoot(npc)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Map loot
local nodePositions = {}
hook.Add("EntityRemoved", "GFR_Loot_CollectNodes", function(ent)
	if ent:GetClass() == "info_node" then
		nodePositions[#nodePositions + 1] = ent:GetPos()
	end
end)

local candidates = {}
local stashes = {}
local replacements = {} -- times when a cleared-away searched stash gets replaced elsewhere
local lastTopUp = 0

local function GroundSpot(pos)
	local tr = util.TraceLine({start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 160), mask = MASK_SOLID_BRUSHONLY})
	if !tr.Hit or tr.HitSky or tr.HitNormal.z < 0.7 then return end
	if bit.band(util.PointContents(tr.HitPos + Vector(0, 0, 4)), CONTENTS_WATER) != 0 then return end
	local up = util.TraceLine({start = tr.HitPos + Vector(0, 0, 4), endpos = tr.HitPos + Vector(0, 0, 600), mask = MASK_SOLID_BRUSHONLY})
	return tr.HitPos, up.Hit && !up.HitSky
end

local function BuildCandidates()
	candidates = {}
	if navmesh.IsLoaded() then
		for _, area in ipairs(navmesh.GetAllNavAreas()) do
			if !area:IsUnderwater() && area:GetSizeX() >= 16 && area:GetSizeY() >= 16 then
				candidates[#candidates + 1] = area:GetRandomPoint()
			end
		end
	end
	for _, pos in ipairs(nodePositions) do
		candidates[#candidates + 1] = pos
	end
	-- Maps shipped with ground spots in gamemode/maps/<map>.lua (sv_mapdecor.lua), e.g. ones without navmesh/nodes
	for _, pos in ipairs(GFR.MapSpots or {}) do
		candidates[#candidates + 1] = pos
	end
	-- Last resort: around spawn points
	if #candidates == 0 then
		for _, sp in ipairs(ents.FindByClass("info_player_*")) do
			for _ = 1, 20 do
				candidates[#candidates + 1] = sp:GetPos() + Vector(math.Rand(-2500, 2500), math.Rand(-2500, 2500), 64)
			end
		end
	end
end

local function TooCloseToPlayer(pos, dist)
	-- Nothing spawns inside a claimed base either (sh_claim.lua)
	if GFR.InClaim && GFR.InClaim(pos) then return true end
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(pos) < dist * dist then return true end
	end
	return false
end

local function TooClose(pos, minDist)
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(pos) < minDist * minDist then return true end
	end
	for _, st in ipairs(stashes) do
		if st.pos:DistToSqr(pos) < 200 * 200 then return true end
	end
	return false
end

-- Map loot is placed as searchable containers (what's inside is rolled by sh_containers.lua). Which models, what each one
-- is and how often it turns up indoors / outdoors: GFR.ContainerModels in sh_containers.lua. A model that isn't installed
-- turns up as HL2's wooden crate instead - still that kind of container, with that loot.
local FALLBACK_BOX = "models/props_junk/wood_crate001a.mdl"

-- Model and skin to spawn for a GFR.ContainerModels entry
local function StashModelOf(e)
	if util.IsValidModel(e[1]) then return e[1], e.skin end
	return FALLBACK_BOX, nil
end

-- onlyType: just models of that type (a loot point set to one type). Weighted by indoor / outdoor as usual; when none of
-- that type are set to turn up here, any of its models will do, and with no models at all it's the wooden crate.
local function PickStashModel(indoor, onlyType)
	local key = indoor and "indoor" or "outdoor"
	local list, total = {}, 0
	local ofType = {}
	for _, e in ipairs(GFR.ContainerModels) do
		if e.type != "none" && (!onlyType or e.type == onlyType) then
			ofType[#ofType + 1] = e
			local w = e[key] or 0
			if w > 0 then
				list[#list + 1] = e
				total = total + w
			end
		end
	end
	if onlyType && total <= 0 then
		if #ofType == 0 then return FALLBACK_BOX, onlyType, nil end
		local e = ofType[math.random(#ofType)]
		local mdl, skin = StashModelOf(e)
		return mdl, e.type, skin
	end
	local roll = math.Rand(0, total)
	for _, e in ipairs(list) do
		roll = roll - e[key]
		if roll <= 0 then
			local mdl, skin = StashModelOf(e)
			return mdl, e.type, skin
		end
	end
end

-- What a placed loot point spawns: its own model if it has one, else a model of its type, else anything
-- (the Spawn Points tool: GFR_SP points carry ctype / model / skin)
local function PickPointModel(p, indoor)
	if p.model && p.model != "" then
		local listed = GFR.ContainerListEntry && GFR.ContainerListEntry(p.model, p.skin)
		local ctype = p.ctype or (listed && listed.type != "none" && listed.type) or nil
		if !util.IsValidModel(p.model) then return FALLBACK_BOX, ctype or "crate", nil end
		return p.model, ctype, p.skin
	end
	return PickStashModel(indoor, p.ctype)
end

local function SpawnStashProp(pos, mdl, ctype, skin)
	local ent = ents.Create("prop_physics")
	ent:SetModel(mdl)
	if skin then ent:SetSkin(skin) end
	if ctype then ent:SetNW2String("GFR_CType", ctype) end
	ent:SetAngles(Angle(0, math.random(0, 3) * 90 + math.Rand(-15, 15), 0))
	ent:SetPos(pos)
	ent:Spawn()
	ent:SetPos(pos - Vector(0, 0, ent:OBBMins().z) + Vector(0, 0, 1))
	-- Doesn't fit here (wall, another prop, a person)
	local tr = util.TraceHull({start = ent:GetPos() + Vector(0, 0, 2), endpos = ent:GetPos() + Vector(0, 0, 3),
		mins = ent:OBBMins() * 0.85, maxs = ent:OBBMaxs() * 0.85, filter = ent, mask = MASK_SOLID})
	-- No physics model = Q's trace can't hit it, so it couldn't be searched
	local phys = ent:GetPhysicsObject()
	if tr.Hit or !GFR.ContainerType(ent) or !IsValid(phys) then
		ent:Remove()
		return
	end
	phys:EnableMotion(false)
	ent.GFR_Stash = true
	return ent
end

local function StashAlive(st)
	return IsValid(st.ent)
end

local function CreateStash(minDist)
	-- About half the time, one of the loot points placed with the Spawn Points tool first (lua/autorun/gfr_spawnpoints.lua);
	-- indoors or out, a placed point is always good. With gfr_spawnpoints_only (and loot points on this map), only those.
	local only = GFR_SP && GFR_SP.Only && GFR_SP.Only("loot")
	local placed
	if GFR_SP && (only or math.Rand(0, 1) < 0.5) then
		if GFR_SP.GetPoints then
			placed = GFR_SP.GetPoints("loot")
		else
			placed = {}
			for _, pos in ipairs(GFR_SP.Get("loot")) do placed[#placed + 1] = {pos = pos} end -- (an older Spawn Points addon)
		end
	end
	if placed && #placed > 0 then
		for _ = 1, math.min(#placed, only and 20 or 8) do
			local point = placed[math.random(#placed)]
			local pos, indoor = GroundSpot(point.pos)
			if pos && !TooClose(pos, minDist) then
				local mdl, ctype, skin = PickPointModel(point, indoor)
				local ent = mdl && SpawnStashProp(pos, mdl, ctype, skin)
				if IsValid(ent) then
					stashes[#stashes + 1] = {pos = pos, ent = ent}
					return true
				end
			end
		end
	end
	if only then return false end -- (no free loot point right now: none this time)
	for _ = 1, 25 do
		local pos, indoor = GroundSpot(candidates[math.random(#candidates)])
		-- Most stashes are indoors (houses, shops, bunkers); some are out in the open
		if pos && (indoor or math.random(1, 3) == 1) && !TooClose(pos, minDist) then
			local mdl, ctype, skin = PickStashModel(indoor)
			local ent = mdl && SpawnStashProp(pos, mdl, ctype, skin)
			if IsValid(ent) then
				stashes[#stashes + 1] = {pos = pos, ent = ent}
				return true
			end
		end
	end
	return false
end

-- Loose junk lying around (pick up with E, scrap it from the inventory: sh_junk.lua)
local cvJunkCount = CreateConVar("gfr_maploot_junk", "18", flags, "How many loose junk props (cans, bottles, broken electronics...) are kept on the map")
local junk = {}

local function CreateJunk(minDist)
	-- (only placed loot points on this map: the junk lies around those, not anywhere)
	local placed = GFR_SP && GFR_SP.Only && GFR_SP.Only("loot") && GFR_SP.Get("loot")
	for _ = 1, 15 do
		local src = placed && (placed[math.random(#placed)] + Vector(math.Rand(-140, 140), math.Rand(-140, 140), 0))
			or candidates[math.random(#candidates)]
		local pos = GroundSpot(src)
		if pos && !TooCloseToPlayer(pos, minDist) then
			local mdl = GFR.JunkSpawnModels[math.random(#GFR.JunkSpawnModels)]
			if util.IsValidModel(mdl) then
				local ent = ents.Create("prop_physics")
				ent:SetModel(mdl)
				ent:SetAngles(Angle(0, math.random(0, 359), 0))
				ent:SetPos(pos + VectorRand() * 30 * Vector(1, 1, 0))
				ent:Spawn()
				ent:SetPos(ent:GetPos() - Vector(0, 0, ent:OBBMins().z) + Vector(0, 0, 2))
				if !GFR.JunkItem(ent) or util.TraceLine({start = pos + Vector(0, 0, 8), endpos = ent:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY}).Hit then
					ent:Remove()
				else
					junk[#junk + 1] = ent
					return true
				end
			end
		end
	end
	return false
end

local function TopUp(minDist, maxNew)
	if !cvEnabled:GetBool() or #candidates == 0 then return end
	for i = #stashes, 1, -1 do
		if !StashAlive(stashes[i]) then table.remove(stashes, i) end
	end
	local made = 0
	while #stashes < cvMapCount:GetInt() && made < maxNew do
		if !CreateStash(minDist) then break end
		made = made + 1
	end
	for i = #junk, 1, -1 do
		if !IsValid(junk[i]) then table.remove(junk, i) end
	end
	made = 0
	while #junk < cvJunkCount:GetInt() && made < maxNew * 2 do
		if !CreateJunk(minDist) then break end
		made = made + 1
	end
	lastTopUp = GameHours()
end

local function ClearStashes()
	for _, st in ipairs(stashes) do
		if IsValid(st.ent) then st.ent:Remove() end
	end
	for _, ent in ipairs(junk) do
		if IsValid(ent) then ent:Remove() end
	end
	stashes = {}
	junk = {}
	replacements = {}
end

-- Testing (superadmin): gfr_spawn_stash [type] puts a searchable container where you're looking - a random
-- model of that type (the wooden crate if it isn't installed) (sh_containers.lua GFR.ContainerTypes: medbag, fridge, crate, guncrate, cargo_ammo...), or any
-- type when none is given. It's a normal stash: searched with Q, rolled the same way.
local function StashTypes()
	local have = {}
	for _, e in ipairs(GFR.ContainerModels or {}) do
		if e.type && e.type != "none" then have[e.type] = true end
	end
	return have
end

concommand.Add("gfr_spawn_stash", function(ply, _, args)
	if !IsValid(ply) or !GFR.CanCheat(ply) then return end
	local want = args[1] && string.lower(args[1]) or nil
	local list = {}
	for _, e in ipairs(GFR.ContainerModels or {}) do
		if e.type && e.type != "none" && (!want or e.type == want) then list[#list + 1] = e end
	end
	if #list == 0 then
		local names = table.GetKeys(StashTypes())
		table.sort(names)
		ply:ChatPrint("[GFR] No container type '" .. tostring(want) .. "'. Types: " .. table.concat(names, ", "))
		return
	end
	local e = list[math.random(#list)]
	local mdl, skin = StashModelOf(e)
	local tr = ply:GetEyeTrace()
	local ent = ents.Create("prop_physics")
	ent:SetModel(mdl)
	if skin then ent:SetSkin(skin) end
	ent:SetNW2String("GFR_CType", e.type)
	ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
	ent:SetPos(tr.HitPos)
	ent:Spawn()
	ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z) + tr.HitNormal * 2)
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	ent.GFR_Stash = true
	local def = GFR.ContainerTypes && GFR.ContainerTypes[e.type]
	ply:ChatPrint("[GFR] Spawned " .. (def && def.name or e.type) .. " (" .. e.type .. ") - " .. mdl)
end, function(cmd, argStr)
	local out = {}
	local typed = string.lower(string.Trim(argStr or ""))
	local names = table.GetKeys(GFR.ContainerTypes or {})
	table.sort(names)
	for _, n in ipairs(names) do
		if string.StartWith(n, typed) then out[#out + 1] = cmd .. " " .. n end
	end
	return out
end, "Spawn a searchable loot container where you look: gfr_spawn_stash [type]")

concommand.Add("gfr_maploot_reset", function(ply)
	if IsValid(ply) && !GFR.CanCheat(ply) then return end
	ClearStashes()
	BuildCandidates()
	TopUp(400, 1000)
	print("[GFR] Map loot respawned: " .. #stashes .. " stashes from " .. #candidates .. " candidate spots")
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Crunchy item tweaks
local function PatchCrunchyItems()
	for class, data in pairs(scripted_ents.GetList()) do
		local stored = scripted_ents.GetStored(class)
		local tbl = stored && stored.t
		if tbl && tbl.Category == "Crunchy's Ultimate Pickups" && rawget(tbl, "Use") && !tbl.GFR_Patched then
			local origUse = tbl.Use
			tbl.Use = function(self, activator, caller, ...)
				local ply = (IsValid(activator) && activator:IsPlayer() && activator) or (IsValid(caller) && caller:IsPlayer() && caller)
				-- Picked up into the inventory instead (gfr_inventory.lua)
				if ply && GFR && GFR.InvPickup && GFR.InvPickup(ply, self, class) then return end
				-- Ammo goes into the pool the EFT guns actually use (sh_ammo.lua), not Crunchy's own type
				local ammo = GFR.AmmoItems && GFR.AmmoItems[class]
				if ply && ammo then
					ply:GiveAmmo(ammo.amount, ammo.type)
					self:Remove()
					hook.Run("GFR_ItemUsed", ply, class, self)
					return
				end
				local hp, ap = ply && ply:Health(), ply && ply:Armor()
				origUse(self, activator, caller, ...)
				if !ply or !IsValid(ply) then return end
				if !IsValid(self) or self:IsMarkedForDeletion() then
					hook.Run("GFR_ItemUsed", ply, class, self)
				end
				if cvClampHeal:GetBool() then
					if ply:Health() > ply:GetMaxHealth() then ply:SetHealth(ply:GetMaxHealth()) end
					if ply:Armor() > ply:GetMaxArmor() then ply:SetArmor(ply:GetMaxArmor()) end
				end
			end
			tbl.GFR_Patched = true
		end
	end
end

-- Shared with sv_containers.lua and sv_spawner.lua
GFR.Loot = {
	GroundSpot = GroundSpot,
	GetCandidates = function() return candidates end,
	TurnedNearby = TurnedNearby,
	PickPool = PickPool,
	PickItem = PickItem,
	SpawnItem = SpawnItem,
	AmmoItemFor = AmmoItemFor,
	GunPools = gunPools,
	AllPools = pools, -- weapon slots use these to tell a handgun from a rifle (sv_weapons.lua)
	-- A spawned stash got smashed (sv_containers.lua): a new one turns up elsewhere like a searched one would
	StashBroken = function(ent)
		for i = #stashes, 1, -1 do
			if stashes[i].ent == ent then
				table.remove(stashes, i)
				replacements[#replacements + 1] = GameHours() + RefreshHours()
			end
		end
	end
}

---------------------------------------------------------------------------------------------------------------------------------------------
hook.Add("InitPostEntity", "GFR_Loot_Init", function()
	BuildPools()
	PatchCrunchyItems()
	timer.Simple(5, function()
		BuildCandidates()
		TopUp(400, 1000)
		print("[GFR] Map loot: " .. #stashes .. " stashes from " .. #candidates .. " candidate spots")
	end)
end)

hook.Add("PostCleanupMap", "GFR_Loot_Cleanup", function()
	stashes = {}
	junk = {}
	replacements = {}
	timer.Simple(1, function()
		BuildCandidates()
		TopUp(400, 1000)
	end)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Searched stashes don't sit around empty: once nobody's near, they're cleared away,
-- and a fresh one turns up somewhere else on the map (never close to a player) gfr_loot_refresh_hours later.
local cvStashDespawn = CreateConVar("gfr_stash_despawn", "120", flags, "Seconds after a spawned stash is searched before it's cleared away (once no one is near)")
local DESPAWN_CLEAR = 700 -- no player this close, so it never vanishes in front of you

timer.Create("GFR_Loot_StashCycle", 5, 0, function()
	if !cvEnabled:GetBool() then return end
	local now = CurTime()
	for i = #stashes, 1, -1 do
		local ent = stashes[i].ent
		if IsValid(ent) && ent.GFR_SearchedAt && now - ent.GFR_SearchedAt > cvStashDespawn:GetFloat() && !TooCloseToPlayer(ent:GetPos(), DESPAWN_CLEAR) then
			ent:Remove()
			table.remove(stashes, i)
			replacements[#replacements + 1] = GameHours() + RefreshHours()
		end
	end
	for i = #replacements, 1, -1 do
		if replacements[i] <= GameHours() && #candidates > 0 then
			if #stashes >= cvMapCount:GetInt() or CreateStash(cvMinDist:GetFloat()) then table.remove(replacements, i) end
		end
	end
end)

timer.Create("GFR_Loot_Respawn", 30, 0, function()
	local interval = RefreshHours()
	if interval <= 0 or GameHours() - lastTopUp < interval then return end
	TopUp(cvMinDist:GetFloat(), 5)
end)
