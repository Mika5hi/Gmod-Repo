--[[
	Custom Apocalypse - our own items: crafting materials, deployable kits, recipe notes
	Registered as scripted entities here (shared). E picks them up into the inventory.
	Deployable kits are "used" from the inventory to place them (sv_crafting.lua: GFR.PlaceDeployable).
]]
GFR = GFR or {}

GFR.CustomItems = {
	-- Materials
	gfr_mat_scrap     = {name = "Scrap Metal", model = "models/gibs/metal_gib4.mdl", cat = "material", weight = 0.4},
	gfr_mat_cloth     = {name = "Cloth Rags", model = "models/props_junk/garbage_newspaper001a.mdl", cat = "material", weight = 0.2},
	gfr_mat_wood      = {name = "Wood Planks", model = "models/props_debris/wood_board04a.mdl", cat = "material", weight = 0.8},
	gfr_mat_tape      = {name = "Duct Tape", model = "models/props_junk/garbage_metalcan001a.mdl", cat = "material", weight = 0.2},
	gfr_mat_chem      = {name = "Chemicals", model = "models/props_junk/garbage_plasticbottle001a.mdl", cat = "material", weight = 0.4},
	gfr_mat_gunpowder = {name = "Gunpowder", model = "models/props_lab/jar01a.mdl", cat = "material", weight = 0.3},
	gfr_mat_parts     = {name = "Gun Parts", model = "models/props_c17/trappropeller_lever.mdl", cat = "material", weight = 0.5},
	gfr_mat_zblood    = {name = "Zombie Blood", model = "models/props_junk/glassjug01.mdl", cat = "material", weight = 0.3},

	-- Zombie harvesting products (sv_harvest.lua)
	gfr_food_zmeat_cooked = {name = "Cooked Zombie Meat", model = "models/crunchy/props/fallout_props/gorelegb03.mdl", cat = "food", weight = 0.5,
		food = true, heal = 5},
	gfr_item_camo = {name = "Gut Camouflage", model = "models/props_junk/garbage_bag001a.mdl", cat = "misc", weight = 1, use = "ApplyCamo"},
	-- Bags: use to strap on extra inventory slots (sv_inventory.lua)
	gfr_item_satchel  = {name = "Satchel (+5 slots)", model = "models/props_c17/suitcase001a.mdl", cat = "misc", stack = 1, use = "EquipSatchel", bag = 5},
	gfr_item_backpack = {name = "Backpack (+10 slots)", model = "models/props_c17/suitcase_passenger_physics.mdl", cat = "misc", stack = 1, use = "EquipBackpack", bag = 10},
	-- Look at someone and use it to inject them; use it twice while looking at nothing to inject yourself (sv_extract.lua)
	gfr_item_zextract = {name = "Zombie Blood Extract", model = "models/healthvial.mdl", cat = "misc", weight = 0.2, use = "UseExtract",
		color = Color(120, 20, 20)},
	-- Military only (trade): the same, but whoever it's used on becomes a hunter, and the soldiers leave hunters alone (sv_hunter.lua)
	gfr_item_hvial = {name = "Experimental Vial", model = "models/healthvial.mdl", cat = "misc", weight = 0.2, stack = 2, use = "UseHunterVial",
		color = Color(70, 170, 220)},
	gfr_deploy_burnbarrel = {name = "Burn Barrel Kit", model = "models/props_c17/oildrum001.mdl", cat = "deployable", weight = 6,
		place = {model = "models/props_c17/oildrum001.mdl", fire = true, refund = {gfr_mat_scrap = 1}}},

	-- More barricades (all stock HL2 models). spikes = damage every half second to zombies pushing into it.
	gfr_deploy_barricade_planks = {name = "Plank Barricade Kit", model = "models/props_debris/wood_board04a.mdl", cat = "deployable", weight = 4,
		place = {model = "models/props_wasteland/barricade002a.mdl", hp = 420, material = "wood", name = "Plank Barricade", refund = {gfr_mat_wood = 2}}},
	gfr_deploy_fence_planks = {name = "Long Plank Fence Kit", model = "models/props_debris/wood_board04a.mdl", cat = "deployable", weight = 6,
		place = {model = "models/props_wasteland/wood_fence02a.mdl", hp = 480, material = "wood", name = "Long Plank Fence", refund = {gfr_mat_wood = 3}}},
	gfr_deploy_barbed = {name = "Barbed Wire Kit", model = "models/props_c17/fence01a.mdl", cat = "deployable", weight = 4,
		place = {model = "models/props_forest/fencebarbedwire01.mdl", hp = 300, material = "metal", name = "Barbed Wire", spikes = 6,
			refund = {gfr_mat_scrap = 2}}},
	gfr_deploy_bars = {name = "Steel Bars Kit", model = "models/gibs/metal_gib4.mdl", cat = "deployable", weight = 8,
		place = {model = "models/props_building_details/storefront_template001a_bars.mdl", hp = 900, material = "metal", name = "Steel Bars",
			refund = {gfr_mat_scrap = 3}}},
	gfr_deploy_fence_tall = {name = "Tall Fence Kit", model = "models/props_c17/fence01a.mdl", cat = "deployable", weight = 9,
		place = {model = "models/props_wasteland/exterior_fence001a.mdl", hp = 1000, material = "metal", name = "Tall Fence",
			refund = {gfr_mat_scrap = 4}}},
	gfr_deploy_dumpster = {name = "Dumpster Barricade Kit", model = "models/props_junk/trashdumpster02.mdl", cat = "deployable", weight = 14,
		place = {model = "models/props_junk/trashdumpster02.mdl", hp = 1600, material = "metal", name = "Dumpster Barricade",
			refund = {gfr_mat_scrap = 5}}},
	gfr_deploy_steelwall = {name = "Steel Slab Wall Kit", model = "models/gibs/metal_gib4.mdl", cat = "deployable", weight = 18,
		place = {model = "models/props_lab/blastdoor001a.mdl", hp = 2400, material = "metal", name = "Steel Slab Wall",
			refund = {gfr_mat_scrap = 7, gfr_mat_parts = 1}}},

	-- Claim flag (sh_claim.lua): nothing spawns within gfr_claim_radius of it
	gfr_deploy_claim = {name = "Claim Flag", model = "models/props_c17/signpole001.mdl", cat = "deployable", weight = 4, stack = 1,
		place = {model = "models/props_c17/signpole001.mdl", hp = 600, material = "metal", claim = true, name = "Claim Flag",
			refund = {gfr_mat_scrap = 2, gfr_mat_cloth = 1}}},

	-- Turrets (entities/gfr_turret.lua): aim them when placing, they cover ~120 degrees in front. E loads ammo.
	gfr_deploy_turret_light = {name = "Light Turret Kit", model = "models/items/item_item_crate.mdl", cat = "deployable", weight = 8, stack = 1,
		place = {class = "gfr_turret", model = "models/combine_turrets/floor_turret.mdl", hp = 350, material = "metal",
			refund = {gfr_mat_scrap = 3, gfr_mat_parts = 1},
			turret = {name = "Light Turret", range = 900, damage = 9, rate = 7, spread = 0.045, cap = 250,
				ammo = {"Pistol"}, ammoName = "pistol / SMG rounds (9mm, .45, 5.7)", sound = "weapons/smg1/smg1_fire1.wav", noise = 1800}}},
	-- The heavy tier is Frasiu's Sentinel minigun (workshop "Sentinel Turret": entities/gfr_sentinel.lua). Without that
	-- addon it falls back to a big floor turret (place.fallback).
	gfr_deploy_turret_heavy = {name = "Sentinel Turret Kit", model = "models/items/item_item_crate.mdl", cat = "deployable", weight = 14, stack = 1,
		place = {class = "gfr_sentinel", needs = "entity_sentrygun_reworked", model = "models/codmw2rm/other/sentry_minigun_recompiled_creditinvalidate.mdl",
			hp = 700, material = "metal", name = "Sentinel Turret",
			refund = {gfr_mat_scrap = 5, gfr_mat_parts = 3},
			turret = {name = "Sentinel Turret", range = 1400, damage = 14, rate = 12, cap = 400,
				ammo = {"SMG1", "AR2"}, ammoName = "rifle rounds (5.45 / 5.56 / 7.62)", noise = 2600},
			fallback = {class = "gfr_turret", model = "models/combine_turrets/floor_turret.mdl",
				turret = {name = "Heavy Turret", scale = 1.25, range = 1400, damage = 24, rate = 3.5, spread = 0.02, cap = 180,
					headshots = true, headshotChance = 45, ammo = {"SMG1", "AR2"}, ammoName = "rifle rounds (5.45 / 5.56 / 7.62)",
					sound = "weapons/ar2/fire1.wav", tracer = "AR2Tracer", noise = 2600}}}},

	-- Deployable kits (placed from the inventory)
	gfr_deploy_barricade_wood  = {name = "Wooden Barricade Kit", model = "models/props_debris/wood_board04a.mdl", cat = "deployable", weight = 3,
		place = {model = "models/props_wasteland/barricade001a.mdl", hp = 300, material = "wood", refund = {gfr_mat_wood = 1}}},
	gfr_deploy_wall_wood       = {name = "Plank Wall Kit", model = "models/props_debris/wood_board04a.mdl", cat = "deployable", weight = 5,
		place = {model = "models/props_wasteland/wood_fence01a.mdl", hp = 550, material = "wood", refund = {gfr_mat_wood = 2, gfr_mat_scrap = 1}}},
	gfr_deploy_barricade_metal = {name = "Metal Barricade Kit", model = "models/gibs/metal_gib4.mdl", cat = "deployable", weight = 6,
		place = {model = "models/props_c17/concrete_barrier001a.mdl", hp = 1200, material = "metal", refund = {gfr_mat_scrap = 3}}},
	gfr_deploy_fence           = {name = "Chain-link Fence Kit", model = "models/props_c17/fence01a.mdl", cat = "deployable", weight = 5,
		place = {model = "models/props_c17/fence01a.mdl", hp = 800, material = "metal", refund = {gfr_mat_scrap = 2}}},
	gfr_deploy_workbench       = {name = "Workbench Kit", model = "models/props_c17/furnituretable002a.mdl", cat = "deployable", weight = 8,
		place = {model = "models/props_c17/furnituretable002a.mdl", workbench = true, refund = {gfr_mat_wood = 2, gfr_mat_scrap = 2}}},
	-- Where guns are customized (sh_attachments.lua)
	gfr_deploy_gunbench        = {name = "Gun Table Kit", model = "models/props_wasteland/controlroom_desk001b.mdl", cat = "deployable", weight = 10,
		place = {model = "models/props_wasteland/controlroom_desk001b.mdl", gunbench = true, name = "Gun Table", material = "metal", refund = {gfr_mat_scrap = 3, gfr_mat_parts = 1}}},
	-- Base building (sv_base.lua): storage you can put things in, beds to sleep through the hours and respawn at, light
	gfr_deploy_crate           = {name = "Storage Crate Kit", model = "models/props_junk/wood_crate001a.mdl", cat = "deployable", weight = 6,
		place = {model = "models/props_junk/wood_crate001a.mdl", storage = 12, name = "Storage Crate", material = "wood", refund = {gfr_mat_wood = 2}}},
	gfr_deploy_locker          = {name = "Storage Locker Kit", model = "models/props_c17/lockers001a.mdl", cat = "deployable", weight = 10,
		place = {model = "models/props_c17/lockers001a.mdl", storage = 24, name = "Storage Locker", material = "metal", refund = {gfr_mat_scrap = 3}}},
	gfr_deploy_sleepbag        = {name = "Sleeping Mat", model = "models/props_c17/furnituremattress001a.mdl", cat = "deployable", weight = 4,
		place = {model = "models/props_c17/furnituremattress001a.mdl", bed = 1, name = "Sleeping Mat", refund = {gfr_mat_cloth = 2}}},
	gfr_deploy_bed             = {name = "Bed Kit", model = "models/props_c17/furniturebed001a.mdl", cat = "deployable", weight = 10,
		place = {model = "models/props_c17/furniturebed001a.mdl", bed = 2, name = "Bed", material = "metal", refund = {gfr_mat_scrap = 2, gfr_mat_cloth = 1}}},
	gfr_deploy_lamp            = {name = "Oil Lamp Kit", model = "models/props_interiors/furniture_lamp01a.mdl", cat = "deployable", weight = 3,
		place = {model = "models/props_interiors/furniture_lamp01a.mdl", lamp = true, name = "Oil Lamp", refund = {gfr_mat_scrap = 1}}},

	-- Junk: small props lying around (cans, bottles, broken electronics...) picked up with E (sh_junk.lua).
	-- "Scrap" it from the inventory to break it down: scrap = {material = {min, max}}
	gfr_junk_metal       = {name = "Metal Junk", model = "models/props_junk/metal_paintcan001a.mdl", cat = "junk", stack = 5, weight = 0.6,
		scrap = {gfr_mat_scrap = {1, 2}}},
	-- (wood and rags are now picked up as the material directly, sh_junk.lua; these two stay so old ones still scrap)
	gfr_junk_wood        = {name = "Wood Scraps", model = "models/props_debris/wood_board02a.mdl", cat = "junk", stack = 5, weight = 0.6,
		scrap = {gfr_mat_wood = {1, 1}}},
	gfr_junk_electronics = {name = "Broken Electronics", model = "models/props_lab/reciever01b.mdl", cat = "junk", stack = 3, weight = 1,
		scrap = {gfr_mat_scrap = {1, 1}, gfr_mat_parts = {0, 1}, gfr_mat_tape = {0, 1}}},
	gfr_junk_bottle      = {name = "Bottles & Jugs", model = "models/props_junk/garbage_plasticbottle002a.mdl", cat = "junk", stack = 5, weight = 0.3,
		scrap = {gfr_mat_chem = {0, 1}, gfr_mat_scrap = {0, 1}}},
	gfr_junk_cloth       = {name = "Old Rags", model = "models/props_junk/shoe001a.mdl", cat = "junk", stack = 5, weight = 0.2,
		scrap = {gfr_mat_cloth = {1, 2}}},

	-- Consumables you hold to use (sv_consumables.lua): S.T.A.L.K.E.R. 2 Consumables (Workshop 3426614364) and the
	-- non-overlapping grounded ones from SCP: SL Consumables (3310620322). Using one from the inventory puts it in your
	-- hands and plays its animation; hunger/thirst/bleeding/infection effects land when it's actually consumed.
	-- swep/ammo = the pack's weapon and its ammo type, click = needs a left click to start (SCP items)
	gfr_s2_water    = {name = "Water", model = "models/weapons/sweps/stalker2/water/w_item_water.mdl", skin = 1, scale = 1.77, cat = "drink", stack = 3,
		swep = "weapon_stalker2_water", ammo = "water"},
	gfr_s2_energy   = {name = "Energy Drink", model = "models/weapons/sweps/stalker2/energy/w_item_energy.mdl", scale = 1.77, cat = "drink", stack = 3,
		swep = "weapon_stalker2_energy", ammo = "energy"},
	gfr_s2_vodka    = {name = "Vodka", model = "models/weapons/sweps/stalker2/vodka/w_item_vodka.mdl", skin = 1, scale = 1.77, cat = "drink", stack = 2,
		swep = "weapon_stalker2_vodka", ammo = "vodka"},
	gfr_s2_bread    = {name = "Bread", model = "models/weapons/sweps/stalker2/bread/w_item_bread.mdl", skin = 1, scale = 1.77, cat = "food", stack = 3,
		swep = "weapon_stalker2_bread", ammo = "bread"},
	gfr_s2_canned   = {name = "Canned Food", model = "models/weapons/sweps/stalker2/canned/w_item_canned.mdl", skin = 1, scale = 1.77, cat = "food", stack = 4,
		swep = "weapon_stalker2_canned", ammo = "canned"},
	gfr_s2_sausage  = {name = "Sausage", model = "models/weapons/sweps/stalker2/sausage/w_item_sausage.mdl", skin = 1, scale = 1.77, cat = "food", stack = 3,
		swep = "weapon_stalker2_sausage", ammo = "sausage"},
	gfr_s2_milk     = {name = "Condensed Milk", model = "models/weapons/sweps/stalker2/milk/w_item_milk.mdl", skin = 1, scale = 1.77, cat = "food", stack = 4,
		swep = "weapon_stalker2_milk", ammo = "milk"},
	gfr_s2_bandage  = {name = "Bandage", model = "models/weapons/sweps/stalker2/bandage/w_item_bandage.mdl", skin = 1, scale = 1.77, cat = "medical", stack = 5,
		swep = "weapon_stalker2_bandage", ammo = "bandage"},
	gfr_s2_medkit   = {name = "Medkit", model = "models/weapons/sweps/stalker2/medkit/w_item_medkit.mdl", scale = 1.77, cat = "medical", stack = 2,
		swep = "weapon_stalker2_medkit", ammo = "medkit_general"},
	gfr_s2_medkit_army = {name = "Army Medkit", model = "models/weapons/sweps/stalker2/medkit/w_item_medkit.mdl", skin = 1, scale = 1.77, cat = "medical", stack = 2,
		swep = "weapon_stalker2_medkit_army", ammo = "medkit_army"},
	gfr_s2_medkit_sci  = {name = "Scientific Medkit", model = "models/weapons/sweps/stalker2/medkit/w_item_medkit.mdl", skin = 2, scale = 1.77, cat = "medical", stack = 2,
		swep = "weapon_stalker2_medkit_scientific", ammo = "medkit_scientific"},
	gfr_s2_pills_endurance = {name = "Endurance Pills", model = "models/weapons/sweps/stalker2/pills/w_item_pills.mdl", skin = 2, scale = 1.77, cat = "medical", stack = 3,
		swep = "weapon_stalker2_pills_endurance", ammo = "enhancers"},
	gfr_s2_pills_revitalis = {name = "Revitalis Pills", model = "models/weapons/sweps/stalker2/pills/w_item_pills.mdl", scale = 1.77, cat = "medical", stack = 3,
		swep = "weapon_stalker2_pills_revitalis", ammo = "regenerator"},
	gfr_scp_painkillers = {name = "Painkillers", model = "models/weapons/sweps/scpsl/painkillers/w_painkillers.mdl", cat = "medical", stack = 4,
		swep = "weapon_scpsl_painkillers", ammo = "painkillers", click = true},
	gfr_scp_adrenaline  = {name = "Adrenaline", model = "models/weapons/sweps/scpsl/injector/w_injector.mdl", cat = "medical", stack = 2,
		swep = "weapon_scpsl_injector", ammo = "injector", click = true},

	-- Recipe note: reading it (E) teaches a random recipe you don't know yet
	gfr_recipe_note = {name = "Recipe Note", model = "models/props_lab/clipboard.mdl", cat = "misc", note = true}
}

for class, def in pairs(GFR.CustomItems) do
	local ENT = {}
	ENT.Type = "anim"
	ENT.Base = "base_gmodentity"
	ENT.PrintName = def.name
	ENT.Category = "Green Flu: Reimagined"
	ENT.Spawnable = true
	ENT.WorldModel = def.model

	if SERVER then
		function ENT:Initialize()
			self:SetModel(util.IsValidModel(def.model) and def.model or "models/props_junk/cardboard_box004a.mdl")
			if def.food && class == "gfr_food_zmeat_cooked" then self:SetColor(Color(120, 80, 60)) end -- charred
			if def.color then self:SetColor(def.color) end
			if def.skin then self:SetSkin(def.skin) end
			if def.scale then self:SetModelScale(def.scale) end
			self:PhysicsInit(SOLID_VPHYSICS)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetUseType(SIMPLE_USE)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:Wake() end
		end

		function ENT:Use(ply)
			if !IsValid(ply) or !ply:IsPlayer() then return end
			if def.note then
				if GFR.LearnRandomRecipe then GFR.LearnRandomRecipe(ply) end
				self:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 60)
				self:Remove()
				return
			end
			if !self.GFR_FromInventory then
				-- Picked up off the ground
				if GFR.InvPickup then GFR.InvPickup(ply, self, class) end
				return
			end
			-- Used from the inventory: food is eaten, kits get placed, usables run their effect, materials do nothing
			if def.swep then
				-- Into your hands; it's used up once the animation actually consumes it (sv_consumables.lua)
				if GFR.StartConsumable && GFR.StartConsumable(ply, class) then self:Remove() end
			elseif def.scrap then
				-- Break it down into materials (whatever doesn't fit drops at your feet)
				local got = {}
				for mat, range in pairs(def.scrap) do
					local n = math.random(range[1], range[2])
					if n > 0 then
						local mdef = GFR.CustomItems[mat]
						local stored = GFR.InvAdd(ply, mat, n, false, mdef && mdef.model)
						for _ = 1, n - stored do
							local drop = ents.Create(mat)
							drop:SetPos(ply:GetPos() + Vector(math.Rand(-12, 12), math.Rand(-12, 12), 30))
							drop:Spawn()
						end
						got[#got + 1] = (n > 1 and n .. "x " or "") .. (mdef && mdef.name or mat)
					end
				end
				ply:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 60)
				GFR.Notify(ply, #got > 0 and ("Scrapped: " .. table.concat(got, ", ")) or "Nothing worth keeping in it.")
				self:Remove()
			elseif def.food then
				hook.Run("GFR_ItemUsed", ply, class, self)
				if def.heal then ply:SetHealth(math.min(ply:Health() + def.heal, ply:GetMaxHealth())) end
				ply:EmitSound("npc/barnacle/barnacle_crunch" .. math.random(2, 3) .. ".wav", 60)
				self:Remove()
			elseif def.place then
				-- Kits: a ghost preview to aim and rotate first; the kit is used up once it's placed (sv_crafting.lua)
				if GFR.StartPlacement then GFR.StartPlacement(ply, class) end
			elseif def.use && GFR[def.use] && GFR[def.use](ply) then
				self:Remove()
			end
		end
	end

	scripted_ents.Register(ENT, class)
end
