--[[
	Custom Apocalypse - searchable containers (definitions, shared)
	A prop is a container if its class is a physics/dynamic prop and its model path matches one of the patterns below.
	Map-baked static props are not entities and can never be searched.

	Each type: name shown on screen, search time, chance the main loot roll is empty, item count, loot pool weights
	(pools in sv_loot.lua), and a separate salvage roll: chance, how many, which materials fit that kind of container.
	Salvage is rolled even when the main roll comes up empty, so junk is rarely truly empty.
]]
GFR = GFR or {}

local SCRAP, CLOTH, WOOD, TAPE, CHEM, POWDER, PARTS = "gfr_mat_scrap", "gfr_mat_cloth", "gfr_mat_wood", "gfr_mat_tape", "gfr_mat_chem", "gfr_mat_gunpowder", "gfr_mat_parts"

-- Loot follows what the container is: medicine in med kits, food in kitchens, materials in garbage, guns in lockers.
GFR.ContainerTypes = {
	-- Medical
	medbag   = {name = "First Aid Kit", time = 2.5, empty = 0.15, min = 1, max = 3, weights = {meds_basic = 55, meds_good = 35, meds_rare = 7},
		salvage = {chance = 0.45, n = {1, 1}, mats = {CLOTH, CLOTH, TAPE, CHEM}}},
	-- Food and drink
	fridge   = {name = "Fridge", time = 2.5, empty = 0.3, min = 1, max = 2, weights = {drink = 60, packaged = 40},
		salvage = {chance = 0.25, n = {1, 1}, mats = {SCRAP, CHEM}}},
	kitchen  = {name = "Kitchen", time = 2.5, empty = 0.25, min = 1, max = 2, weights = {packaged = 70, drink = 22, melee = 6},
		salvage = {chance = 0.45, n = {1, 2}, mats = {SCRAP, SCRAP, CHEM, CLOTH}}},
	-- General supplies
	crate    = {name = "Supply Crate", time = 3, empty = 0.2, min = 1, max = 3, weights = {packaged = 30, drink = 22, meds_basic = 14, ammo_loose = 8, melee = 5, armor = 2, materials = 15,
		gun_pistol = 3, gun_shotgun = 1.5, gun_smg = 1, gun_rifle = 1},
		salvage = {chance = 0.6, n = {1, 2}, mats = {WOOD, WOOD, SCRAP, CLOTH}}},
	box      = {name = "Box", time = 2, empty = 0.3, min = 1, max = 2, weights = {packaged = 35, drink = 20, meds_basic = 12, currency = 10, materials = 12, notes = 4},
		salvage = {chance = 0.5, n = {1, 2}, mats = {CLOTH, CLOTH, TAPE, WOOD}}},
	shelf    = {name = "Shelves", time = 2.5, empty = 0.3, min = 1, max = 2, weights = {packaged = 40, drink = 25, meds_basic = 10, materials = 15, melee = 3},
		salvage = {chance = 0.45, n = {1, 2}, mats = {SCRAP, TAPE, CLOTH, WOOD}}},
	-- Junk: mostly materials
	trash    = {name = "Garbage", time = 3.5, empty = 0.35, min = 1, max = 2, weights = {materials = 65, packaged = 10, drink = 6, currency = 6, melee = 4, ammo_loose = 3},
		salvage = {chance = 0.95, n = {1, 3}, mats = {SCRAP, SCRAP, SCRAP, CLOTH, CLOTH, TAPE, CHEM, WOOD, WOOD}}},
	tools    = {name = "Parts Bin", time = 3, empty = 0.25, min = 1, max = 2, weights = {materials = 60, melee = 15, notes = 6},
		salvage = {chance = 0.9, n = {2, 3}, mats = {PARTS, PARTS, TAPE, TAPE, SCRAP, SCRAP, POWDER}}},
	-- Personal belongings
	cabinet  = {name = "Drawers", atts = {chance = 0.05, n = {1, 1}}, time = 3, empty = 0.3, min = 1, max = 2, weights = {currency = 25, meds_basic = 15, bags = 8, armor = 6, notes = 8, packaged = 6, ammo_loose = 6, gun_pistol = 1.5},
		salvage = {chance = 0.6, n = {1, 2}, mats = {CLOTH, CLOTH, CLOTH, TAPE}}},
	bag      = {name = "Bag", time = 2.5, empty = 0.2, min = 1, max = 2, weights = {packaged = 22, drink = 22, meds_basic = 20, currency = 15, bags = 7, ammo_loose = 10, gun_pistol = 2, notes = 3},
		salvage = {chance = 0.45, n = {1, 2}, mats = {CLOTH, CLOTH, TAPE}}},
	desk     = {name = "Desk", atts = {chance = 0.05, n = {1, 1}}, time = 3, empty = 0.3, min = 1, max = 2, weights = {currency = 30, notes = 15, meds_basic = 15, ammo_loose = 8, gun_pistol = 2.5, materials = 8},
		salvage = {chance = 0.55, n = {1, 2}, mats = {TAPE, TAPE, CHEM, SCRAP}}},
	filing   = {name = "Filing Cabinet", time = 3, empty = 0.4, min = 1, max = 1, weights = {currency = 30, notes = 20, meds_basic = 15, ammo_loose = 6},
		salvage = {chance = 0.5, n = {1, 1}, mats = {SCRAP, TAPE}}},
	car      = {name = "Car", atts = {chance = 0.08, n = {1, 1}}, time = 5, empty = 0.25, min = 1, max = 2, weights = {ammo_loose = 20, meds_basic = 20, drink = 18, currency = 15, packaged = 10, gun_pistol = 3, melee = 4, materials = 15},
		salvage = {chance = 0.9, n = {2, 3}, mats = {SCRAP, SCRAP, SCRAP, PARTS, TAPE, CHEM}}},
	-- Weapons and ammo (map lockers, gun racks and weapon cases count as weapon crates too).
	-- always: every weapon crate holds one gun (pistols most often, rifles less, military ones rarely), then the usual roll
	guncrate = {name = "Weapon Crate", atts = {chance = 0.45, n = {1, 2}}, time = 4, empty = 0.15, min = 1, max = 3, weights = {ammo_loose = 24, ammo_box = 16, melee = 10, armor = 8, grenade = 3,
		gun_pistol = 7, gun_smg = 3.5, gun_shotgun = 3.5, gun_rifle = 2, gun_military = 0.6},
		always = {gun_pistol = 40, gun_smg = 20, gun_shotgun = 20, gun_rifle = 14, gun_military = 5, gun_rare = 1},
		salvage = {chance = 0.5, n = {1, 2}, mats = {WOOD, WOOD, POWDER, PARTS}}},
	-- ARC9's wooden attachment box: always holds 1-3 weapon attachments, now and then a few rounds or gun parts too
	attcrate = {name = "Attachment Crate", atts = {chance = 1, n = {1, 3}}, time = 3.5, empty = 0.6, min = 1, max = 1, weights = {ammo_loose = 50, materials = 50},
		salvage = {chance = 0.5, n = {1, 1}, mats = {PARTS, PARTS, TAPE}}},
	-- Supply drop called in with a signal flare: a set loadout (sv_airdrop.lua GFR.AirdropLoot); the rest is unused
	airdrop  = {name = "Supply Drop", custom = "AirdropLoot", atts = {chance = 0.9, n = {2, 3}}, time = 5, empty = 0, min = 4, max = 6, weights = {ammo_box = 22, gun_military = 7, gun_rifle = 5,
		gun_rare = 2, gun_shotgun = 3, gun_smg = 3, armor = 10, armor_rare = 4, meds_good = 14, meds_rare = 8, grenade = 8, packaged = 8, drink = 6, notes = 3, bags = 2},
		salvage = {chance = 0.7, n = {1, 3}, mats = {POWDER, POWDER, PARTS, PARTS, TAPE, CHEM}}},
	-- always: an ammo crate is never empty - at least one box of rounds, then the usual roll
	ammo     = {name = "Ammo Crate", atts = {chance = 0.25, n = {1, 1}}, time = 3, empty = 0.1, min = 1, max = 3, weights = {ammo_box = 65, ammo_loose = 27, grenade = 8},
		always = {ammo_box = 70, ammo_loose = 30},
		salvage = {chance = 0.6, n = {1, 2}, mats = {POWDER, POWDER, SCRAP, PARTS}}},
	military = {name = "Military Crate", atts = {chance = 0.6, n = {1, 2}}, time = 4.5, empty = 0.1, min = 2, max = 3, weights = {ammo_box = 35, grenade = 14, armor = 12, armor_rare = 3, meds_good = 12,
		gun_rifle = 4, gun_military = 4, gun_shotgun = 2, gun_rare = 0.5},
		salvage = {chance = 0.6, n = {1, 2}, mats = {POWDER, PARTS, SCRAP}}},
	-- Cargo: Crunchy's Supply Units, the big sealed ones. Never empty, a lot more inside, and of one kind only.
	-- Searching unlocks it: the lid opens and what's inside is laid out in it to take (GFR.ContainerModels "opens")
	cargo_ammo    = {name = "Supply Unit (Ammo)", atts = {chance = 0.3, n = {1, 2}}, time = 5, empty = 0, min = 3, max = 5,
		weights = {ammo_box = 60, ammo_loose = 25, grenade = 12}},
	cargo_meds    = {name = "Supply Unit (Medical)", time = 5, empty = 0, min = 3, max = 5,
		weights = {meds_good = 45, meds_basic = 30, meds_rare = 15, armor = 6, armor_rare = 2}},
	cargo_rations = {name = "Supply Unit (Rations)", time = 5, empty = 0, min = 3, max = 5,
		weights = {packaged = 55, drink = 40}}
}

---------------------------------------------------------------------------------------------------------------------------------------------
-- CONTAINER MODELS - the old built-in list. This version starts with NO containers: every lootbox model is assigned
-- in-game with the Lootbox Models tool (sh_lootmodels.lua, saved to data/greenflu/containers.json). The list below is
-- only loaded when you press "Load the old built-in list" in that tool, as a starting point.
--   [1]     model path
--   type    which container it is = which loot it holds (the types above: medbag, fridge, crate, guncrate, attcrate, ammo...)
--   skin    optional: only this skin of the model counts (one model, different crates: Crunchy's crate_ammo.mdl)
--   indoor  how often map loot spawns it inside buildings (0 / left out = never)
--   outdoor how often map loot spawns it outside (0 / left out = never)
-- A model in this list is that container wherever it is, map-placed or spawned. A model that isn't installed spawns as
-- HL2's wooden crate (wood_crate001a) instead, still that type with its loot (sv_loot.lua).
-- (After editing: restart the map.)
GFR.ContainerModels = {
	-- Medical
	{"models/crunchy/props/random_props/crate_ammo.mdl", skin = 1, type = "medbag", indoor = 4, outdoor = 2},           -- Supply Crate (Health)
	{"models/crunchy/props/eft_props/carmedkit.mdl", type = "medbag", indoor = 1.5, outdoor = 1},
	{"models/crunchy/props/stalker_props/medkit_high.mdl", type = "medbag", indoor = 1},
	{"models/crunchy/props/stalker_props/medkit_med.mdl", type = "medbag", indoor = 1},
	{"models/crunchy/props/stalker_props/medkit_low.mdl", type = "medbag", outdoor = 1},
	{"models/crunchy/props/contagion_props/w_first_aid.mdl", type = "medbag", indoor = 1},
	{"models/items/healthkit.mdl", type = "medbag", indoor = 1},

	-- Food and supplies
	{"models/crunchy/props/random_props/crate_ammo.mdl", skin = 2, type = "crate", indoor = 4, outdoor = 2},            -- Supply Crate (Rations)
	{"models/items/item_item_crate.mdl", type = "crate", indoor = 5, outdoor = 4},
	{"models/props_junk/plasticcrate01a.mdl", type = "crate", indoor = 6, outdoor = 8},
	{"models/props_junk/wood_crate001a.mdl", type = "crate", indoor = 3, outdoor = 3},
	{"models/props_junk/wood_crate001a_half.mdl", type = "crate", indoor = 2, outdoor = 2},
	{"models/props_junk/wood_crate003a.mdl", type = "crate", indoor = 2, outdoor = 2},
	{"models/props_c17/furniturefridge001a.mdl", type = "fridge", indoor = 3},
	{"models/props_interiors/refrigerator01a.mdl", type = "fridge", indoor = 3},
	{"models/props_c17/furniturestove001a.mdl", type = "kitchen", indoor = 2.5},
	{"models/props_c17/furniturecupboard001a.mdl", type = "kitchen", indoor = 2.5},
	{"models/props_junk/cardboard_box001a.mdl", type = "box", indoor = 4, outdoor = 6},
	{"models/props_junk/cardboard_box002a.mdl", type = "box", indoor = 4, outdoor = 6},
	{"models/props_junk/cardboard_box003a.mdl", type = "box", indoor = 4},
	{"models/props_junk/cardboard_box004a.mdl", type = "box", indoor = 4},
	{"models/props_c17/furnitureshelf001a.mdl", type = "shelf", indoor = 2},
	{"models/props_c17/shelfunit01a.mdl", type = "shelf", indoor = 2},
	{"models/props_interiors/furniture_shelf01a.mdl", type = "shelf", indoor = 2},

	-- Junk (materials)
	{"models/props_trainstation/trashcan_indoor001a.mdl", type = "trash", indoor = 4},
	{"models/props_junk/trashbin01a.mdl", type = "trash", indoor = 4, outdoor = 14},
	{"models/props_junk/trashdumpster01a.mdl", type = "trash", outdoor = 10},
	{"models/props_junk/garbage128_composite001a.mdl", type = "trash", outdoor = 3.3},
	{"models/props_junk/garbage128_composite001b.mdl", type = "trash", outdoor = 3.3},
	{"models/props_junk/garbage128_composite001c.mdl", type = "trash", outdoor = 3.3},
	{"models/props_junk/garbage128_composite001d.mdl", type = "trash", outdoor = 3.3},
	{"models/props_junk/garbage256_composite001a.mdl", type = "trash", outdoor = 3.3},
	{"models/props_junk/garbage256_composite002a.mdl", type = "trash", outdoor = 3.3},
	{"models/props_lab/partsbin01.mdl", type = "tools", indoor = 4, outdoor = 3},

	-- Personal belongings
	{"models/props_c17/furnituredrawer001a.mdl", type = "cabinet", indoor = 3.5},
	{"models/props_c17/furnituredresser001a.mdl", type = "cabinet", indoor = 3.5},
	{"models/props_c17/suitcase001a.mdl", type = "bag", indoor = 1.5, outdoor = 2},
	{"models/props_c17/suitcase_passenger_physics.mdl", type = "bag", indoor = 1.5},
	{"models/props_c17/briefcase001a.mdl", type = "bag", indoor = 1.5},
	{"models/vj_base/duffle_bag.mdl", type = "bag", indoor = 1.5, outdoor = 2},
	{"models/props_interiors/furniture_desk01a.mdl", type = "desk", indoor = 4},
	{"models/props_lab/filecabinet02.mdl", type = "filing", indoor = 1.5},
	{"models/props_wasteland/controlroom_filecabinet001a.mdl", type = "filing", indoor = 1.5},

	-- Cargo: Crunchy's Supply Units. "opens" = the model it turns into once searched, with the loot laid out inside
	{"models/crunchy/props/borderlands_props/dahlammocrate.mdl", type = "cargo_ammo", indoor = 1.5, outdoor = 1,
		opens = "models/crunchy/props/borderlands_props/dahlammocrate_opened.mdl"},
	{"models/crunchy/props/borderlands_props/dahlammocrate_meds.mdl", type = "cargo_meds", indoor = 1.5, outdoor = 1,
		opens = "models/crunchy/props/borderlands_props/dahlammocrate_opened_meds.mdl"},
	{"models/crunchy/props/borderlands_props/dahlammocrate_rations.mdl", type = "cargo_rations", indoor = 1.5, outdoor = 1,
		opens = "models/crunchy/props/borderlands_props/dahlammocrate_opened_rations.mdl"},

	-- Cars: GMod's own HL2 cars, searchable wherever a map has them as movable props (never spawned: too big)
	{"models/props_vehicles/car001a_hatchback.mdl", type = "car"}, {"models/props_vehicles/car001b_hatchback.mdl", type = "car"},
	{"models/props_vehicles/car002a_physics.mdl", type = "car"}, {"models/props_vehicles/car002b_physics.mdl", type = "car"},
	{"models/props_vehicles/car003a_physics.mdl", type = "car"}, {"models/props_vehicles/car003b_physics.mdl", type = "car"},
	{"models/props_vehicles/car004a_physics.mdl", type = "car"}, {"models/props_vehicles/car004b_physics.mdl", type = "car"},
	{"models/props_vehicles/car005a_physics.mdl", type = "car"}, {"models/props_vehicles/car005b_physics.mdl", type = "car"},
	{"models/props_vehicles/van001a_physics.mdl", type = "car"}, {"models/props_vehicles/truck001a.mdl", type = "car"},
	{"models/props_vehicles/truck002a_cab.mdl", type = "car"}, {"models/props_vehicles/truck003a.mdl", type = "car"},

	-- Weapons
	{"models/tfa_cso/entities/supplybox_hs.mdl", type = "guncrate", indoor = 4, outdoor = 4},
	{"models/props/stalker2/wood_crate_02/w_wood_crate_02.mdl", type = "guncrate", indoor = 5, outdoor = 5},
	{"models/props_junk/wood_crate002a.mdl", type = "guncrate", indoor = 2, outdoor = 2},
	{"models/props_crates/supply_crate01.mdl", type = "guncrate", indoor = 1.5, outdoor = 1},
	{"models/props_crates/supply_crate02.mdl", type = "guncrate", indoor = 1.5, outdoor = 1},
	{"models/items/arc9/att_wooden_box.mdl", type = "attcrate", indoor = 3, outdoor = 1.5},

	-- Ammo
	{"models/crunchy/props/random_props/crate_ammo.mdl", skin = 0, type = "ammo", indoor = 4, outdoor = 3},            -- Supply Crate (Ammo)
	-- (HL2's metal ammo crate is out: it showed up with a missing texture)
	{"models/items/ammocrate_ar2.mdl", type = "military", indoor = 1.5, outdoor = 3},
	{"models/items/ammocrate_grenade.mdl", type = "military", indoor = 1.5},
}

-- Crunchy's spawnable crates (spawn menu "Supply Crate / Supply Unit"): searched like the matching container instead of
-- being smashed open for Crunchy's own items (sv_containers.lua makes them unbreakable)
GFR.ContainerClasses = {
	supply_crate_ammo = "ammo", supply_crate_health = "medbag", supply_crate_rations = "crate",
	supply_unit_ammo = "cargo_ammo", supply_unit_meds = "cargo_meds", supply_unit_rations = "cargo_rations"
}

-- The list in use is the one made with the Lootbox Models tool (sh_lootmodels.lua loads it); nothing until then
GFR.BuiltinContainerModels = GFR.ContainerModels
GFR.ContainerModels = GFR.ContainerModelsSaved or {} -- (Lua refresh: keep the edited list)

-- Props that aren't on the list can also count by their model name ("crate", "fridge", "locker"... below). Off: only
-- what you assigned is a container.
local cvNameMatch = CreateConVar("gfr_container_namematch", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Props not on the Lootbox Models list are containers if their model name looks like one (crate, fridge, locker...)")

local byModel = {} -- [model] = {[skin or -1] = type, or false: listed as "none", never a container}
local opensTo = {} -- [model] = opened model
local cache = {}

function GFR.RebuildContainerIndex()
	byModel, opensTo, cache = {}, {}, {}
	for _, e in ipairs(GFR.ContainerModels) do
		local mdl = string.lower(e[1])
		byModel[mdl] = byModel[mdl] or {}
		byModel[mdl][e.skin or -1] = e.type != "none" && e.type or false
		if e.opens then opensTo[mdl] = e.opens end
	end
end
GFR.RebuildContainerIndex()

-- The list entry for this model / skin (exact skin first, then the any-skin one), or nil
function GFR.ContainerListEntry(mdl, skin)
	mdl = string.lower(mdl or "")
	local any
	for _, e in ipairs(GFR.ContainerModels) do
		if string.lower(e[1]) == mdl then
			if e.skin && e.skin == skin then return e end
			if !e.skin then any = e end
		end
	end
	return any
end

-- The opened model of a container that opens up when searched (Supply Units), or nil
function GFR.ContainerOpensTo(ent)
	return opensTo[string.lower(ent:GetModel() or "")]
end

-- Older pattern matching, for map props not in the list above. Checked in order; first substring match wins
local patterns = {
	{"_chunk", nil}, {"gib", nil}, -- pieces of a broken crate/furniture (junk, sh_junk.lua)
	{"carmedkit", "medbag"}, {"medkit_", "medbag"}, {"w_first_aid", "medbag"}, {"items/healthkit", "medbag"}, {"medbag", "medbag"}, {"med_bag", "medbag"},
	{"medicalcabinet", "medbag"}, {"medcab", "medbag"}, {"first_aid", "medbag"}, {"medkit", "medbag"}, {"health_charger", nil},
	{"fridge", "fridge"}, {"refrigerator", "fridge"}, {"vending", "fridge"},
	{"stove", "kitchen"}, {"oven", "kitchen"}, {"microwave", "kitchen"}, {"kitchen_shelf", "kitchen"}, {"kitchen_counter", "kitchen"}, {"cupboard", "kitchen"},
	-- Day of Defeat supply crates some maps ship (rp_necro_forest_revamped) and Crunchy's green ammo crate
	{"props_crates/supply_crate", "guncrate"}, {"props_crates/static_crate", "crate"}, {"random_props/crate_ammo", "guncrate"},
	{"ammocrate_ar2", "military"}, {"ammocrate_rockets", "military"}, {"ammocrate_grenade", "military"},
	{"ammo_can", "ammo"}, {"ammocrate", "ammo"}, {"ammo_crate", "ammo"}, {"ammobox", "ammo"},
	{"footlocker", "guncrate"}, {"locker", "guncrate"}, {"storagecloset", "guncrate"}, {"gunrack", "guncrate"}, {"weapon_case", "guncrate"},
	{"filecabinet", "filing"}, {"file_cabinet", "filing"},
	{"furnituredrawer", "cabinet"}, {"dresser", "cabinet"}, {"cabinetdrawer", "cabinet"}, {"wardrobe", "cabinet"},
	{"nightstand", "cabinet"}, {"cabinet", "cabinet"},
	{"desklamp", nil}, {"desk", "desk"},
	{"partsbin", "tools"}, {"toolbox", "tools"}, {"tool_box", "tools"}, {"toolchest", "tools"},
	{"shelfunit", "shelf"}, {"shelf", "shelf"},
	{"dumpster", "trash"}, {"trashbin", "trash"}, {"trashcan", "trash"}, {"trash_can", "trash"}, {"garbage", "trash"}, {"bin0", "trash"},
	{"suitcase", "bag"}, {"briefcase", "bag"}, {"backpack", "bag"}, {"duffel", "bag"}, {"duffle", "bag"},
	{"props_vehicles/car", "car"}, {"props_vehicles/van", "car"}, {"props_vehicles/truck", "car"}, {"props_vehicles/pickup", "car"},
	{"wood_crate", "crate"}, {"plasticcrate", "crate"}, {"crate", "crate"},
	{"cardboard_box", "box"}, {"cardboard", "box"}
}

-- Crunchy's models are item pickups, except these medkit cases, which make good first aid kit containers
local crunchyContainers = {"carmedkit", "medkit_high", "medkit_med", "medkit_low", "w_first_aid", "random_props/crate_ammo"}

local propClasses = {
	prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true,
	prop_dynamic = true, prop_dynamic_override = true
}

-- Returns the container type id for an entity, or nil
function GFR.ContainerType(ent)
	if !IsValid(ent) or ent:GetNW2Bool("GFR_Placed") then return end
	local byClass = GFR.ContainerClasses[ent:GetClass()]
	if byClass then return byClass end
	if !propClasses[ent:GetClass()] then return end
	local forced = ent:GetNW2String("GFR_CType", "")
	if forced != "" && GFR.ContainerTypes[forced] then return forced end
	local mdl = string.lower(ent:GetModel() or "")
	if mdl == "" then return end
	local listed = byModel[mdl]
	if listed then
		local t = listed[ent:GetSkin()]
		if t == nil then t = listed[-1] end
		if t != nil then return t or nil end -- (false: listed as not a container, whatever its name says)
	end
	if !cvNameMatch:GetBool() then return end
	local cached = cache[mdl]
	if cached == nil && string.find(mdl, "models/crunchy/", 1, true) then
		local ok = false
		for _, w in ipairs(crunchyContainers) do
			if string.find(mdl, w, 1, true) then ok = true break end
		end
		if !ok then cache[mdl] = false return end
	end
	if cached != nil then return cached or nil end
	local found = false
	for _, p in ipairs(patterns) do
		if string.find(mdl, p[1], 1, true) then
			found = p[2] or false
			break
		end
	end
	cache[mdl] = found
	return found or nil
end
