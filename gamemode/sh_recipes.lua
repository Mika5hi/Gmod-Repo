--[[
	Custom Apocalypse - crafting recipes (shared)
	out/n   = item class + amount put in the inventory      weapon = weapon class given instead
	outs    = {class = amount, ...} several outputs (salvage recipes)
	bench   = needs a workbench nearby                      known  = known from the start (others are learned)
	fire    = needs a burn barrel nearby                    inputs = class or "@group" (GFR.ItemGroups) = amount
	Recipes whose output isn't installed are hidden automatically.
]]
GFR = GFR or {}

GFR.Recipes = {
	-- Medical
	-- S.T.A.L.K.E.R. 2 / SCP: SL consumables (sh_items.lua gfr_s2_* / gfr_scp_*)
	{id = "bandage", name = "Bandage", cat = "Medical", out = "gfr_s2_bandage", n = 1, inputs = {gfr_mat_cloth = 2}, known = true},
	{id = "medkit", name = "Field Medkit", cat = "Medical", out = "gfr_s2_medkit", n = 1, inputs = {["@bandage"] = 2, ["@booze"] = 1, gfr_mat_chem = 1}, bench = true, known = true},
	-- EFT Medical Items (usable meds; hooked into bleeding/infection in sv_eftmeds.lua)
	{id = "tourniquet", name = "CAT Tourniquet (stops bleeding)", cat = "Medical", weapon = "weapon_eft_cat", inputs = {gfr_mat_cloth = 2, gfr_mat_scrap = 1}, known = true},
	{id = "alusplint", name = "Aluminium Splint", cat = "Medical", weapon = "weapon_eft_alusplint", inputs = {gfr_mat_scrap = 2, gfr_mat_cloth = 1}, known = true},
	{id = "antibiotics", name = "Antibiotics (slows infection 10 min)", cat = "Medical", weapon = "weapon_eft_augmentin", inputs = {gfr_mat_chem = 2, ["@pills"] = 1}, bench = true, known = true},
	{id = "carkit", name = "Car First Aid Kit", cat = "Medical", weapon = "weapon_eft_automedkit", inputs = {["@bandage"] = 2, gfr_mat_cloth = 2, gfr_mat_chem = 1}, bench = true, known = true},
	{id = "afak", name = "AFAK Medkit", cat = "Medical", weapon = "weapon_eft_afak", inputs = {["@bandage"] = 2, gfr_mat_chem = 2, gfr_mat_tape = 1}, bench = true},
	{id = "surgical", name = "Surgical Kit", cat = "Medical", weapon = "weapon_eft_surgicalkit", inputs = {gfr_mat_scrap = 3, gfr_mat_chem = 2, gfr_mat_cloth = 2, gfr_mat_tape = 1}, bench = true},
	{id = "antidote", name = "xTG-12 Antidote (pushes infection back)", cat = "Medical", weapon = "weapon_eft_injectortg12", inputs = {gfr_mat_zblood = 3, gfr_mat_chem = 3, ["@pills"] = 1}, bench = true},
	{id = "adrenaline", name = "Adrenaline Injector (stamina)", cat = "Medical", weapon = "weapon_eft_injectoradrenaline", inputs = {gfr_mat_chem = 3}, bench = true},
	{id = "pills", name = "Painkillers", cat = "Medical", out = "gfr_scp_painkillers", n = 1, inputs = {gfr_mat_chem = 2}, bench = true},
	{id = "inoculator", name = "Inoculator (slows infection)", cat = "Medical", out = "zps_inoculator", n = 1, inputs = {gfr_mat_chem = 4, gfr_mat_zblood = 1, ["@pills"] = 1}, bench = true},

	-- Ammo reloading
	{id = "ammo_pistol", name = "Pistol/SMG Rounds", cat = "Ammo", out = "loose_ammo_pistol", n = 1, inputs = {gfr_mat_gunpowder = 1, gfr_mat_scrap = 1}, bench = true, known = true},
	{id = "ammo_shells", name = "Shotgun Shells", cat = "Ammo", out = "loose_ammo_shotgun", n = 1, inputs = {gfr_mat_gunpowder = 1, gfr_mat_scrap = 1, gfr_mat_cloth = 1}, bench = true, known = true},
	{id = "ammo_556", name = "5.45/5.56 Rounds", cat = "Ammo", out = "loose_ammo_rifle", n = 1, inputs = {gfr_mat_gunpowder = 2, gfr_mat_scrap = 1}, bench = true},
	{id = "ammo_762", name = "7.62 Rounds", cat = "Ammo", out = "nmrih_rifle_ammo", n = 1, inputs = {gfr_mat_gunpowder = 2, gfr_mat_scrap = 2}, bench = true},
	{id = "bolts", name = "Crossbow Bolts", cat = "Ammo", out = "nmrih_crossbow_ammo", n = 1, inputs = {gfr_mat_wood = 2, gfr_mat_scrap = 1}, bench = true, known = true},
	{id = "ammo_pistol_bulk", name = "Pistol Ammo Pouch (20)", cat = "Ammo", out = "pouch_pistol_ammo", n = 1, inputs = {gfr_mat_gunpowder = 3, gfr_mat_scrap = 3}, bench = true},
	{id = "ammo_40mm", name = "40mm Grenade", cat = "Ammo", out = "contagion_ammo_m79", n = 1, inputs = {gfr_mat_gunpowder = 3, gfr_mat_scrap = 2}, bench = true},
	{id = "ammo_magnum", name = "Magnum Rounds", cat = "Ammo", out = "loose_ammo_magnum_pistol", n = 1, inputs = {gfr_mat_gunpowder = 2, gfr_mat_scrap = 1}, bench = true},

	-- Materials
	{id = "tape", name = "Duct Tape", cat = "Materials", out = "gfr_mat_tape", n = 1, inputs = {gfr_mat_cloth = 2, gfr_mat_chem = 1}, bench = true, known = true},
	{id = "gunpowder", name = "Gunpowder", cat = "Materials", out = "gfr_mat_gunpowder", n = 1, inputs = {gfr_mat_chem = 2}, bench = true},

	-- Weapons
	{id = "crowbar", name = "Crowbar", cat = "Weapons", weapon = "arc9_eft_melee_crowbar", inputs = {gfr_mat_scrap = 3}, known = true},
	{id = "machete", name = "Survival Machete", cat = "Weapons", weapon = "arc9_eft_melee_sp8", inputs = {gfr_mat_scrap = 4, gfr_mat_tape = 1}, bench = true},
	{id = "kukri", name = "Kukri", cat = "Weapons", weapon = "arc9_eft_melee_kukri", inputs = {gfr_mat_scrap = 5, gfr_mat_tape = 1}, bench = true},
	{id = "pistol", name = "Makeshift PM Pistol", cat = "Weapons", weapon = "arc9_eft_pm", inputs = {gfr_mat_parts = 2, gfr_mat_scrap = 3}, bench = true},
	{id = "sawedoff", name = "Sawed-off Shotgun", cat = "Weapons", weapon = "arc9_eft_mr43_sawedoff", inputs = {gfr_mat_parts = 3, gfr_mat_scrap = 4, gfr_mat_tape = 2}, bench = true},
	{id = "grenade", name = "Improvised Grenade", cat = "Weapons", weapon = "arc9_eft_rgd5", inputs = {gfr_mat_gunpowder = 3, gfr_mat_scrap = 2, gfr_mat_tape = 1}, bench = true},
	{id = "knife", name = "Combat Knife", cat = "Weapons", weapon = "arc9_eft_melee_fulcrum", inputs = {gfr_mat_scrap = 2, gfr_mat_tape = 1}, known = true},
	{id = "shovel", name = "Shovel", cat = "Weapons", weapon = "arc9_eft_melee_mpl50", inputs = {gfr_mat_wood = 2, gfr_mat_scrap = 3}, bench = true, known = true},
	{id = "molotov", name = "Molotov Cocktail", cat = "Weapons", weapon = "arc9_cod2019_nade_molotov", inputs = {["@booze"] = 1, gfr_mat_cloth = 1}, known = true},
	{id = "pipebomb", name = "Pipe Bomb", cat = "Weapons", weapon = "arc9_cod2019_nade_frag", inputs = {gfr_mat_gunpowder = 2, gfr_mat_scrap = 2, gfr_mat_tape = 1}, bench = true},
	{id = "thermite", name = "Thermite Charge", cat = "Weapons", weapon = "arc9_cod2019_nade_thermite", inputs = {gfr_mat_chem = 3, gfr_mat_scrap = 2}, bench = true},
	{id = "doublebarrel", name = "Double-Barrel Shotgun", cat = "Weapons", weapon = "arc9_cod2019_sh_725", inputs = {gfr_mat_parts = 3, gfr_mat_scrap = 4, gfr_mat_wood = 2}, bench = true},
	{id = "crossbow", name = "Crossbow", cat = "Weapons", weapon = "arc9_cod2019_mm_crossbow", inputs = {gfr_mat_wood = 4, gfr_mat_parts = 2, gfr_mat_tape = 2, gfr_mat_cloth = 1}, bench = true},
	{id = "shield", name = "Riot Shield", cat = "Weapons", weapon = "arc9_cod2019_me_shield", inputs = {gfr_mat_scrap = 8, gfr_mat_tape = 2}, bench = true},

	-- Armor
	{id = "vest", name = "Makeshift Vest", cat = "Armor", out = "contagion_armor_light", n = 1, inputs = {gfr_mat_scrap = 5, gfr_mat_cloth = 3, gfr_mat_tape = 2}, bench = true, known = true},
	{id = "helmet", name = "Scrap Helmet", cat = "Armor", out = "uh_helmet", n = 1, inputs = {gfr_mat_scrap = 4, gfr_mat_cloth = 1}, bench = true, known = true},
	{id = "heavyarmor", name = "Heavy Plate Armor", cat = "Armor", out = "contagion_armor_heavy", n = 1, inputs = {gfr_mat_scrap = 10, gfr_mat_cloth = 4, gfr_mat_tape = 3, gfr_mat_parts = 1}, bench = true},

	-- Salvage: break loot back down into materials
	{id = "salvage_armor", name = "Salvage Armor -> 2 Cloth, 2 Scrap", cat = "Salvage", outs = {gfr_mat_cloth = 2, gfr_mat_scrap = 2}, inputs = {["@armor"] = 1}, known = true},
	-- (no "pull rounds": ammo is never an item in the bag now - it goes straight into your rounds, sv_inventory.lua)
	{id = "salvage_booze", name = "Distill Alcohol -> 2 Chemicals", cat = "Salvage", outs = {gfr_mat_chem = 2}, inputs = {["@booze"] = 1}, bench = true, known = true},
	{id = "salvage_pills", name = "Crush Pills -> Chemicals", cat = "Salvage", outs = {gfr_mat_chem = 1}, inputs = {["@pills"] = 2}, known = true},
	{id = "salvage_cans", name = "Flatten Cans -> Scrap", cat = "Salvage", outs = {gfr_mat_scrap = 1}, inputs = {["@cans"] = 2}, known = true},

	-- Building
	{id = "barricade_wood", name = "Wooden Barricade (300 HP)", cat = "Building", out = "gfr_deploy_barricade_wood", n = 1, inputs = {gfr_mat_wood = 3, gfr_mat_scrap = 1}, known = true},
	{id = "wall_wood", name = "Plank Wall (550 HP)", cat = "Building", out = "gfr_deploy_wall_wood", n = 1, inputs = {gfr_mat_wood = 5, gfr_mat_scrap = 2}, bench = true, known = true},
	{id = "barricade_metal", name = "Metal Barricade (1200 HP)", cat = "Building", out = "gfr_deploy_barricade_metal", n = 1, inputs = {gfr_mat_scrap = 6, gfr_mat_tape = 2}, bench = true},
	{id = "workbench", name = "Workbench", cat = "Building", out = "gfr_deploy_workbench", n = 1, inputs = {gfr_mat_wood = 3, gfr_mat_scrap = 2}, known = true},
	{id = "gunbench", name = "Gun Table (customize guns)", cat = "Building", out = "gfr_deploy_gunbench", n = 1, inputs = {gfr_mat_scrap = 6, gfr_mat_parts = 2, gfr_mat_tape = 2, gfr_mat_wood = 2}, bench = true, known = true},
	{id = "satchel", name = "Satchel (+5 slots)", cat = "Survival", out = "gfr_item_satchel", n = 1, inputs = {gfr_mat_cloth = 4, gfr_mat_tape = 1}, known = true},
	{id = "backpack", name = "Backpack (+10 slots)", cat = "Survival", out = "gfr_item_backpack", n = 1, inputs = {gfr_mat_cloth = 6, gfr_mat_tape = 2, gfr_mat_scrap = 2}, bench = true, known = true},
	{id = "burnbarrel", name = "Burn Barrel (cooking fire)", cat = "Building", out = "gfr_deploy_burnbarrel", n = 1, inputs = {gfr_mat_scrap = 3, gfr_mat_wood = 2, gfr_mat_cloth = 1}, known = true},
	{id = "crate", name = "Storage Crate (12 slots)", cat = "Building", out = "gfr_deploy_crate", n = 1, inputs = {gfr_mat_wood = 4, gfr_mat_scrap = 1}, known = true},
	{id = "locker", name = "Storage Locker (24 slots)", cat = "Building", out = "gfr_deploy_locker", n = 1, inputs = {gfr_mat_scrap = 7, gfr_mat_tape = 1, gfr_mat_parts = 1}, bench = true, known = true},
	{id = "sleepbag", name = "Sleeping Mat (sleep, respawn)", cat = "Building", out = "gfr_deploy_sleepbag", n = 1, inputs = {gfr_mat_cloth = 4, gfr_mat_tape = 1}, known = true},
	{id = "bed", name = "Bed (better sleep, respawn)", cat = "Building", out = "gfr_deploy_bed", n = 1, inputs = {gfr_mat_wood = 3, gfr_mat_scrap = 3, gfr_mat_cloth = 4}, bench = true, known = true},
	{id = "lamp", name = "Oil Lamp (light)", cat = "Building", out = "gfr_deploy_lamp", n = 1, inputs = {gfr_mat_scrap = 2, gfr_mat_chem = 1, gfr_mat_cloth = 1}, known = true},
	{id = "barricade_planks", name = "Plank Barricade (420 HP)", cat = "Building", out = "gfr_deploy_barricade_planks", n = 1, inputs = {gfr_mat_wood = 4, gfr_mat_scrap = 1}, known = true},
	{id = "fence_planks", name = "Long Plank Fence (480 HP)", cat = "Building", out = "gfr_deploy_fence_planks", n = 1, inputs = {gfr_mat_wood = 7, gfr_mat_scrap = 2}, bench = true, known = true},
	{id = "barbed", name = "Barbed Wire (hurts zombies, 300 HP)", cat = "Building", out = "gfr_deploy_barbed", n = 1, inputs = {gfr_mat_scrap = 5, gfr_mat_tape = 1}, bench = true, known = true},
	{id = "bars", name = "Steel Bars (900 HP)", cat = "Building", out = "gfr_deploy_bars", n = 1, inputs = {gfr_mat_scrap = 8, gfr_mat_tape = 2}, bench = true},
	{id = "fence_tall", name = "Tall Fence (1000 HP)", cat = "Building", out = "gfr_deploy_fence_tall", n = 1, inputs = {gfr_mat_scrap = 9, gfr_mat_tape = 2, gfr_mat_wood = 2}, bench = true},
	{id = "dumpster", name = "Dumpster Barricade (1600 HP)", cat = "Building", out = "gfr_deploy_dumpster", n = 1, inputs = {gfr_mat_scrap = 12, gfr_mat_tape = 2}, bench = true},
	{id = "steelwall", name = "Steel Slab Wall (2400 HP)", cat = "Building", out = "gfr_deploy_steelwall", n = 1, inputs = {gfr_mat_scrap = 16, gfr_mat_parts = 2, gfr_mat_tape = 3}, bench = true},
	{id = "claim", name = "Claim Flag (nothing spawns around your base)", cat = "Building", out = "gfr_deploy_claim", n = 1, inputs = {gfr_mat_scrap = 4, gfr_mat_cloth = 3, gfr_mat_wood = 2, gfr_mat_tape = 1}, known = true},
	{id = "turret_light", name = "Light Turret (pistol/SMG rounds)", cat = "Building", out = "gfr_deploy_turret_light", n = 1, inputs = {gfr_mat_scrap = 8, gfr_mat_parts = 3, gfr_mat_tape = 2}, bench = true, known = true},
	{id = "turret_heavy", name = "Sentinel Turret (rifle rounds)", cat = "Building", out = "gfr_deploy_turret_heavy", n = 1, inputs = {gfr_mat_scrap = 14, gfr_mat_parts = 6, gfr_mat_tape = 3, gfr_mat_gunpowder = 2}, bench = true},
	{id = "fence", name = "Chain-link Fence (800 HP)", cat = "Building", out = "gfr_deploy_fence", n = 1, inputs = {gfr_mat_scrap = 5, gfr_mat_tape = 1}, bench = true},
	{id = "flare", name = "Signal Flare (light at night)", cat = "Survival", weapon = "arc9_eft_rsp30_red", inputs = {gfr_mat_chem = 1, gfr_mat_gunpowder = 1, gfr_mat_cloth = 1}, known = true},

	-- Zombie parts (sv_harvest.lua)
	{id = "cook_zmeat", name = "Cook Zombie Meat", cat = "Survival", out = "gfr_food_zmeat_cooked", n = 1, inputs = {["@zmeat"] = 1}, fire = true, known = true},
	{id = "cook_zmeat3", name = "Cook Zombie Meat (x3)", cat = "Survival", out = "gfr_food_zmeat_cooked", n = 3, inputs = {["@zmeat"] = 3, gfr_mat_wood = 1}, fire = true, known = true},
	{id = "camo", name = "Gut Camouflage", cat = "Survival", out = "gfr_item_camo", n = 1, inputs = {gfr_mat_zblood = 3, gfr_mat_cloth = 2}, known = true},
	{id = "zextract", name = "Zombie Blood Extract", cat = "Survival", out = "gfr_item_zextract", n = 1, inputs = {gfr_mat_zblood = 3, gfr_mat_chem = 1}, bench = true, known = true}
}

-- "@group" inputs accept any item in the group
local function Set(list) local t = {} for _, c in ipairs(list) do t[c] = true end return t end
GFR.ItemGroups = {
	["@zmeat"] = {name = "Zombie Meat (any)", classes = Set({"meat_chunk1", "meat_chunk2", "meat_arm1", "meat_arm2", "meat_leg1", "meat_leg2", "meat_torso", "meat_head"})},
	["@bandage"] = {name = "Bandage (any)", classes = Set({"gfr_s2_bandage", "other_bandages", "eft_bandage", "eft_bandage_army", "nmrih_medical_bandages", "stalker_medical_bandage", "uh_bandages"})},
	["@pills"] = {name = "Painkillers (any)", classes = Set({"gfr_scp_painkillers", "other_pills", "nmrih_medical_pills", "uh_painkillers", "uh_painkillers_alt", "zps_painkillers", "contagion_medical_pain_reliever"})},
	["@booze"] = {name = "Alcohol (vodka)", classes = Set({"gfr_s2_vodka"})},
	["@armor"] = {name = "Armor (any)", classes = Set({"nmrih_armor_police", "zps_kevlar", "uh_kevlar", "uh_helmet", "contagion_armor_helmet", "contagion_armor_light",
		"contagion_armor_heavy", "stalker_armor_medium", "stalker_armor_small", "stalker_armor_small_2", "csgo_armor_medium", "csgo_armor_full"})},
	-- Any canned food: eat it and the tin is scrap (cans are consumed as-is, food and all)
	["@cans"] = {name = "Canned Food (any)", classes = Set({"gfr_s2_canned", "gfr_s2_milk"})},
	["@ammo"] = {name = "Ammo (any)", classes = {}}
}
for class in pairs(GFR.AmmoItems or {}) do GFR.ItemGroups["@ammo"].classes[class] = true end

function GFR.InGroup(input, class)
	local g = GFR.ItemGroups[input]
	if g then return g.classes[class] == true end
	return input == class
end

-- Nothing is saved between sessions, so there's nothing to learn: every recipe is known from the start
-- (no recipe notes in loot, no recipes for sale: sv_loot.lua, sv_npc.lua skip what's already known)
for _, r in ipairs(GFR.Recipes) do r.known = true end

GFR.RecipeById = {}
for _, r in ipairs(GFR.Recipes) do GFR.RecipeById[r.id] = r end

-- Is the recipe's output installed?
function GFR.RecipeAvailable(r)
	if r.weapon then return weapons.GetStored(r.weapon) != nil end
	if r.att then return ARC9 != nil && ARC9.GetAttTable(r.att) != nil end -- ARC9 attachment (hand-loading, sh_attachments.lua)
	if r.outs then
		for class in pairs(r.outs) do
			if !scripted_ents.GetStored(class) then return false end
		end
		return true
	end
	return scripted_ents.GetStored(r.out) != nil
end

function GFR.ItemDisplayName(class)
	if GFR.ItemGroups[class] then return GFR.ItemGroups[class].name end
	local custom = GFR.CustomItems && GFR.CustomItems[class]
	if custom then return custom.name end
	local stored = scripted_ents.GetStored(class)
	local name = stored && stored.t.PrintName or class
	name = string.gsub(name, "%s*%(%+*%d+%a*P%)", "")
	return string.match(name, "^.-%s%-%s(.+)$") or name
end

GFR.WORKBENCH_RANGE = 160

function GFR.NearWorkbench(ply)
	for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), GFR.WORKBENCH_RANGE)) do
		if ent:GetNW2Bool("GFR_Workbench") then return true end
	end
	return false
end

-- Gun customizing (sh_attachments.lua)
function GFR.NearGunBench(ply)
	for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), GFR.WORKBENCH_RANGE)) do
		if ent:GetNW2Bool("GFR_GunBench") then return true end
	end
	return false
end

-- The body you're looking at: a zombie corpse (harvest) or any corpse with something in its pockets (search).
-- VJ corpses use the debris collision group, which a plain eye trace can pass straight through,
-- so fall back to the closest body in front of you.
local function IsBody(ent) return ent:GetNW2Bool("GFR_ZCorpse") or ent:GetNW2Bool("GFR_HasPockets") end

function GFR.LookedAtBody(ply)
	local eye, aim = ply:EyePos(), ply:GetAimVector()
	local tr = util.TraceLine({start = eye, endpos = eye + aim * 110, filter = ply, mask = MASK_SHOT})
	if IsValid(tr.Entity) && IsBody(tr.Entity) then return tr.Entity end
	local best, bestDot
	for _, ent in ipairs(ents.FindInSphere(eye + aim * 60, 90)) do
		if IsBody(ent) then
			local dir = ent:GetPos() - eye
			if dir:LengthSqr() < 140 * 140 then
				local dot = aim:Dot(dir:GetNormalized())
				if dot > 0.5 && (!best or dot > bestDot) then best, bestDot = ent, dot end
			end
		end
	end
	return best
end
GFR.LookedAtZCorpse = GFR.LookedAtBody

function GFR.NearFire(ply)
	for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), GFR.WORKBENCH_RANGE)) do
		if ent:GetNW2Bool("GFR_Fire") then return true end
	end
	return false
end
