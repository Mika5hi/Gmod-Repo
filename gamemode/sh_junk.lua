--[[
	Custom Apocalypse - junk
	Small loose props (cans, bottles, paint tins, broken electronics, wood chunks, shoes...) can be picked up with E
	like any item (sh_pickup.lua). Junk that breaks down into something else goes into the inventory as junk
	(sh_items.lua: gfr_junk_*) and "Scrap" there breaks it down; wood and rags are the material already and go
	straight in as Wood Planks / Cloth Rags.
	Map loot also scatters some junk around (sv_loot.lua, gfr_maploot_junk).
]]
AddCSLuaFile()
GFR = GFR or {}

-- Model substring -> junk item. Checked in order; first match wins.
local patterns = {
	-- metal
	{"metalcan", "gfr_junk_metal"}, {"popcan", "gfr_junk_metal"}, {"paintcan", "gfr_junk_metal"}, {"metalbucket", "gfr_junk_metal"},
	{"metal_paintcan", "gfr_junk_metal"}, {"gascan", "gfr_junk_metal"}, {"metalpot", "gfr_junk_metal"}, {"props_interiors/pot", "gfr_junk_metal"},
	{"tools_", "gfr_junk_metal"}, {"sawblade", "gfr_junk_metal"}, {"shovel", "gfr_junk_metal"}, {"pulleywheels", "gfr_junk_metal"},
	{"trappropeller_lever", "gfr_junk_metal"}, {"meathook", "gfr_junk_metal"}, {"propane_tank", "gfr_junk_metal"}, {"metal_gib", "gfr_junk_metal"},
	{"props_c17/oildrum001_explosive", nil},
	-- wood: a board is already a plank, it goes straight in as one (no pointless "scrap it into wood" step)
	{"wood_crate001a_chunk", "gfr_mat_wood"}, {"wood_crate002a_chunk", "gfr_mat_wood"}, {"wood_pallet001a_chunk", "gfr_mat_wood"},
	{"wood_chunk", "gfr_mat_wood"}, {"wood_board", "gfr_mat_wood"}, {"wood_gib", "gfr_mat_wood"}, {"furniturechair001a_chunk", "gfr_mat_wood"},
	-- electronics
	{"reciever", "gfr_junk_electronics"}, {"harddrive", "gfr_junk_electronics"}, {"keyboard", "gfr_junk_electronics"},
	{"monitor", "gfr_junk_electronics"}, {"consolebox", "gfr_junk_electronics"}, {"computer", "gfr_junk_electronics"},
	{"clock01", "gfr_junk_electronics"}, {"radio", "gfr_junk_electronics"}, {"camera", "gfr_junk_electronics"}, {"phone", "gfr_junk_electronics"},
	-- bottles
	{"glassbottle", "gfr_junk_bottle"}, {"plasticbottle", "gfr_junk_bottle"}, {"plasticbucket", "gfr_junk_bottle"}, {"milkcarton", "gfr_junk_bottle"},
	{"coffeemug", "gfr_junk_bottle"}, {"glassjug", "gfr_junk_bottle"}, {"bottle", "gfr_junk_bottle"},
	-- cloth / rags: straight in as cloth too
	{"shoe0", "gfr_mat_cloth"}, {"garbage_newspaper", "gfr_mat_cloth"}, {"garbage_bag", "gfr_mat_cloth"}, {"takeoutcarton", "gfr_mat_cloth"}
}

local junkClasses = {prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true}
local MAX_SIZE = 48 -- anything bigger than this (longest side) isn't pocket junk

local cache = {}

-- The junk item class a prop turns into when picked up, or nil
function GFR.JunkItem(ent)
	if !IsValid(ent) or !junkClasses[ent:GetClass()] or ent:GetNW2Bool("GFR_Placed") then return end
	if GFR.ContainerType && GFR.ContainerType(ent) then return end
	local mdl = string.lower(ent:GetModel() or "")
	if mdl == "" then return end
	local cached = cache[mdl]
	if cached == nil then
		cached = false
		for _, p in ipairs(patterns) do
			if string.find(mdl, p[1], 1, true) then
				cached = p[2] or false
				break
			end
		end
		if cached then
			local size = ent:OBBMaxs() - ent:OBBMins()
			if math.max(size.x, size.y, size.z) > MAX_SIZE then cached = false end
		end
		cache[mdl] = cached
	end
	return cached or nil
end

-- What map loot scatters around (all stock HL2 models)
GFR.JunkSpawnModels = {
	"models/props_junk/garbage_metalcan001a.mdl", "models/props_junk/garbage_metalcan002a.mdl", "models/props_junk/popcan01a.mdl",
	"models/props_junk/metal_paintcan001a.mdl", "models/props_junk/metal_paintcan001b.mdl", "models/props_junk/metalbucket01a.mdl",
	"models/props_junk/metalgascan.mdl", "models/props_c17/metalpot001a.mdl", "models/props_c17/tools_wrench01a.mdl", "models/props_c17/tools_pliers01a.mdl",
	"models/props_junk/garbage_glassbottle001a.mdl", "models/props_junk/garbage_glassbottle003a.mdl", "models/props_junk/glassbottle01a.mdl",
	"models/props_junk/garbage_plasticbottle001a.mdl", "models/props_junk/garbage_plasticbottle002a.mdl", "models/props_junk/garbage_milkcarton002a.mdl",
	"models/props_junk/garbage_coffeemug001a.mdl", "models/props_junk/plasticbucket001a.mdl",
	"models/props_junk/shoe001a.mdl", "models/props_junk/garbage_newspaper001a.mdl", "models/props_junk/garbage_bag001a.mdl",
	"models/props_lab/reciever01a.mdl", "models/props_lab/reciever01b.mdl", "models/props_lab/harddrive02.mdl", "models/props_c17/computer01_keyboard.mdl",
	"models/props_c17/clock01.mdl",
	"models/props_debris/wood_board02a.mdl", "models/props_debris/wood_chunk03a.mdl", "models/props_junk/wood_crate001a_chunk03.mdl"
}

if CLIENT then return end

-- E on it (from sh_pickup.lua): into the inventory
function GFR.PickupJunk(ply, ent)
	local class = GFR.JunkItem(ent)
	if !class then return end
	if GFR.InvAdd(ply, class, 1, false, GFR.CustomItems[class].model) == 0 then
		GFR.Notify(ply, "You can't carry any more.")
		return
	end
	ent:EmitSound("items/itempickup.wav", 60)
	ent:Remove()
	GFR.Notify(ply, "+ " .. GFR.CustomItems[class].name)
end

-- Can't haul junk around with the engine's E (it's picked up into the inventory instead)
hook.Add("AllowPlayerPickup", "GFR_Junk_NoCarry", function(ply, ent)
	if GFR.JunkItem(ent) then return false end
end)
