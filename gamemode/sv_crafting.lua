--[[
	Custom Apocalypse - crafting (server)
	- Craft from the inventory's Crafting tab; "bench" recipes need a workbench within reach
	- Recipes: known ones from the start, the rest learned from recipe notes, traders (sv_npc.lua) and quest rewards
	- Dismantle guns at a workbench into gun parts + scrap
	- Barricades: placed from kits, block zombies and people, lose HP to any damage (zombies hit props in their way),
	  E to repair with a plank or scrap, crouch + E to take it down (some materials back)
]]
util.AddNetworkString("GFR_Craft")
util.AddNetworkString("GFR_RecipesKnown")

local function SyncRecipes(ply)
	local known = {}
	for id in pairs(ply.GFR_Recipes or {}) do known[#known + 1] = id end
	net.Start("GFR_RecipesKnown")
	net.WriteTable(known)
	net.Send(ply)
end

local function EnsureRecipes(ply)
	if ply.GFR_Recipes then return end
	ply.GFR_Recipes = {}
	for _, r in ipairs(GFR.Recipes) do
		if r.known then ply.GFR_Recipes[r.id] = true end
	end
end

-- The crafting window asks for the list each time it opens (it can lose it on a Lua refresh)
util.AddNetworkString("GFR_RecipesRequest")
net.Receive("GFR_RecipesRequest", function(_, ply)
	if (ply.GFR_NextRecipeReq or 0) > CurTime() then return end
	ply.GFR_NextRecipeReq = CurTime() + 1
	EnsureRecipes(ply)
	SyncRecipes(ply)
	if GFR.SendCraftNearby then GFR.SendCraftNearby(ply) end -- what's in your crates close by (below)
end)

-- Recipes are knowledge: kept through death
hook.Add("PlayerSpawn", "GFR_Crafting_Spawn", function(ply)
	EnsureRecipes(ply)
	timer.Simple(0.5, function() if IsValid(ply) then SyncRecipes(ply) end end)
end)

function GFR.LearnRecipe(ply, id)
	EnsureRecipes(ply)
	local r = GFR.RecipeById[id]
	if !r or ply.GFR_Recipes[id] then return false end
	ply.GFR_Recipes[id] = true
	SyncRecipes(ply)
	GFR.Notify(ply, "Learned recipe: " .. r.name)
	return true
end

function GFR.UnknownRecipes(ply, filter)
	EnsureRecipes(ply)
	local list = {}
	for _, r in ipairs(GFR.Recipes) do
		if !ply.GFR_Recipes[r.id] && !r.always && GFR.RecipeAvailable(r) && (!filter or filter(r)) then list[#list + 1] = r end
	end
	return list
end

function GFR.LearnRandomRecipe(ply, filter)
	local list = GFR.UnknownRecipes(ply, filter)
	if #list == 0 then
		GFR.Notify(ply, "Nothing you don't already know. You keep the paper for kindling. +5 caps")
		GFR.AddCaps(ply, 5)
		return false
	end
	return GFR.LearnRecipe(ply, list[math.random(#list)].id)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Inventory helpers
-- class can also be an "@group" (sh_recipes.lua)
-- Materials also come out of your storage crates/lockers close by (sv_base.lua), so you don't have to fetch them first
local STORAGE_RANGE = 300
util.AddNetworkString("GFR_CraftNearby")

local function NearbyStorage(ply)
	local list = {}
	for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), STORAGE_RANGE)) do
		-- (only storage you may open: yours, or its owner has you on their access list - sv_owners.lua)
		if ent.GFR_Storage && ent:GetNW2Int("GFR_StorageSlots", 0) > 0 && (!GFR.CanUseOwned or GFR.CanUseOwned(ply, ent)) then
			list[#list + 1] = ent
		end
	end
	return list
end

local function CountClean(ply, class)
	local n = 0
	for _, e in ipairs(ply.GFR_Inv or {}) do
		if GFR.InGroup(class, e.class) && !e.contaminated && !e.wep then n = n + e.count end
	end
	for _, st in ipairs(NearbyStorage(ply)) do
		for _, e in ipairs(st.GFR_Storage) do
			if GFR.InGroup(class, e.class) && !e.contaminated && !e.wep then n = n + e.count end
		end
	end
	return n
end

local function TakeFrom(list, class, amount)
	for i = #list, 1, -1 do
		if amount <= 0 then break end
		local e = list[i]
		if GFR.InGroup(class, e.class) && !e.contaminated && !e.wep then
			local take = math.min(e.count, amount)
			amount = amount - take
			e.count = e.count - take
			if e.count <= 0 then table.remove(list, i) end
		end
	end
	return amount
end

-- Your inventory first, then the crates around you
local function TakeClean(ply, class, amount)
	amount = TakeFrom(ply.GFR_Inv or {}, class, amount)
	if amount <= 0 then return end
	for _, st in ipairs(NearbyStorage(ply)) do
		amount = TakeFrom(st.GFR_Storage, class, amount)
		if amount <= 0 then return end
	end
end

-- Tell the crafting window what's in the crates around you (class = count)
local function SendNearby(ply)
	local counts, n = {}, 0
	for _, st in ipairs(NearbyStorage(ply)) do
		n = n + 1
		for _, e in ipairs(st.GFR_Storage) do
			if !e.contaminated && !e.wep then counts[e.class] = (counts[e.class] or 0) + e.count end
		end
	end
	net.Start("GFR_CraftNearby")
	net.WriteUInt(n, 8)
	net.WriteTable(counts)
	net.Send(ply)
end
GFR.SendCraftNearby = SendNearby

local function GiveItem(ply, class, n)
	local custom = GFR.CustomItems[class]
	local model = custom && custom.model or (GFR.ModelOf && GFR.ModelOf(class))
	local added = GFR.InvAdd(ply, class, n, false, model)
	for _ = 1, n - added do
		-- No room: put it on the floor in front of you
		GFR.Loot.SpawnItem(class, ply:GetPos() + ply:GetForward() * 30 + Vector(0, 0, 30))
	end
	if added < n then GFR.Notify(ply, "No room. You put it down.") end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Crafting
-- quiet: no "Crafted:" message (batch crafting reports once). Returns true if it was made.
local function Craft(ply, id, quiet)
	EnsureRecipes(ply)
	local r = GFR.RecipeById[id]
	if !r or !GFR.RecipeAvailable(r) then return end
	if !ply.GFR_Recipes[id] && !r.always && !r.known then GFR.Notify(ply, "You don't know how to make that.") return end
	if r.bench && !GFR.NearWorkbench(ply) then GFR.Notify(ply, "You need a workbench for that.") return end
	if r.fire && !GFR.NearFire(ply) then GFR.Notify(ply, "You need a fire for that. Build a burn barrel.") return end
	for class, need in pairs(r.inputs) do
		if CountClean(ply, class) < need then
			GFR.Notify(ply, "Missing: " .. GFR.ItemDisplayName(class))
			return
		end
	end
	-- Consumables (grenades, EFT meds, flares) you already carry just get another use; a second gun/melee is pointless
	-- Single-use things (grenades, flares, EFT meds) run on reserve ammo: crafting one gives a use.
	-- ARC9 marks them Disposable / BottomlessClip; older weapons by having no magazine.
	local wepT = r.weapon && weapons.Get(r.weapon)
	local ammo = r.weapon && GFR.WeaponAmmo(r.weapon)
	local consumable = wepT && ammo && (string.lower(ammo) == "grenade" or wepT.Disposable or wepT.BottomlessClip
		or (wepT.Primary && (wepT.Primary.ClipSize or 0) <= 0 && (wepT.ClipSize or 0) <= 0))
	local refillAmmo
	if r.weapon && ply:HasWeapon(r.weapon) then
		if !consumable then GFR.Notify(ply, "You already have one.") return end
		refillAmmo = ammo
	end

	for class, need in pairs(r.inputs) do TakeClean(ply, class, need) end
	if r.weapon then
		if refillAmmo then
			ply:GiveAmmo(1, refillAmmo)
		else
			local w = ply:Give(r.weapon, true)
			if IsValid(w) then w.GaveDefaultAmmo = true end
			if consumable then
				-- Its one use
				if ammo && ply:GetAmmoCount(ammo) <= 0 then ply:GiveAmmo(1, ammo, true) end
			elseif IsValid(w) && w:GetMaxClip1() > 0 then
				-- A crafted gun comes empty (ARC9 would top it up for free otherwise: sh_attachments.lua)
				GFR.ApplyWeaponState(w, 0, nil, nil)
			end
		end
	elseif r.att then
		-- An ARC9 attachment: into the attachment stash
		ARC9:PlayerGiveAtt(ply, r.att, r.n or 1)
		ARC9:PlayerSendAttInv(ply)
	elseif r.outs then
		for class, n in pairs(r.outs) do GiveItem(ply, class, n) end
	else
		GiveItem(ply, r.out, r.n or 1)
	end
	GFR.InvSync(ply)
	SendNearby(ply)
	if !quiet then
		ply:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 65)
		GFR.Notify(ply, "Crafted: " .. r.name)
	end
	return true
end

-- What a weapon breaks down into, by tier (its trade value). {parts, scrap, gunpowder chance %}
local dismantleTiers = {
	{max = 30,  name = "melee/grenade", parts = {0, 0}, scrap = {1, 2}, powder = 30},
	{max = 70,  name = "handgun",       parts = {1, 1}, scrap = {1, 2}, powder = 15},
	{max = 130, name = "SMG/shotgun",   parts = {1, 2}, scrap = {2, 3}, powder = 25},
	{max = 220, name = "rifle",         parts = {2, 3}, scrap = {2, 3}, powder = 40},
	{max = 1e9, name = "heavy",         parts = {3, 4}, scrap = {3, 5}, powder = 60}
}

-- A gun that can be broken down (not fists, not the EFT medical "weapons")
function GFR.CanDismantle(class)
	return class && !GFR.IsFists(class) && weapons.Get(class) != nil && !string.StartWith(class, "weapon_eft_")
end

-- What breaking one down gives you (the gun itself is already gone)
local function DismantleYield(ply, class)
	local value = GFR.ItemValue and GFR.ItemValue(class) or 100
	local tier = dismantleTiers[#dismantleTiers]
	for _, t in ipairs(dismantleTiers) do
		if value <= t.max then tier = t break end
	end
	local bench = GFR.NearWorkbench(ply)
	local parts = math.random(tier.parts[1], tier.parts[2]) + ((bench && tier.parts[2] > 0) and 1 or 0)
	local scrap = math.random(tier.scrap[1], tier.scrap[2]) + (bench and 1 or 0)
	local got = {}
	if parts > 0 then GiveItem(ply, "gfr_mat_parts", parts) got[#got + 1] = parts .. " Gun Parts" end
	GiveItem(ply, "gfr_mat_scrap", scrap)
	got[#got + 1] = scrap .. " Scrap"
	if math.random(1, 100) <= tier.powder + (bench and 20 or 0) then
		GiveItem(ply, "gfr_mat_gunpowder", 1)
		got[#got + 1] = "Gunpowder"
	end
	GFR.InvSync(ply)
	ply:EmitSound("weapons/smg1/switch_single.wav", 65)
	GFR.Notify(ply, "Dismantled: " .. table.concat(got, ", ") .. (bench and "" or "  (a workbench salvages more)"))
end

-- Anywhere with your hands; at a workbench you salvage more (+1 part, +1 scrap, better powder odds)
local function Dismantle(ply, class)
	if !ply:HasWeapon(class) then return end
	if !GFR.CanDismantle(class) then GFR.Notify(ply, "There's nothing to salvage from that.") return end
	ply:StripWeapon(class)
	DismantleYield(ply, class)
end

-- A gun from your bag (inventory entry index), scrapped from the inventory window (sv_inventory.lua)
function GFR.DismantleFromInventory(ply, index)
	local e = ply.GFR_Inv && ply.GFR_Inv[index]
	if !e or !GFR.CanDismantle(e.class) then
		GFR.Notify(ply, "There's nothing to salvage from that.")
		return
	end
	GFR.InvTake(ply, index, 1)
	DismantleYield(ply, e.class)
end

net.Receive("GFR_Craft", function(_, ply)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_Tied then return end
	if (ply.GFR_NextCraft or 0) > CurTime() then return end
	ply.GFR_NextCraft = CurTime() + 0.4
	local action = net.ReadString()
	local arg = net.ReadString()
	if action == "craft" then Craft(ply, arg)
	elseif action == "craftn" then
		-- "id|count": make up to count (stops at the first one that can't be made)
		local id, n = string.match(arg, "^(.+)|(%d+)$")
		n = math.Clamp(tonumber(n) or 1, 1, 25)
		local r = id && GFR.RecipeById[id]
		if !r then return end
		local made = 0
		for i = 1, n do
			if !Craft(ply, id, i > 1 or n > 1) then break end
			made = made + 1
		end
		if made > 1 or (n > 1 && made == 1) then
			ply:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 65)
			GFR.Notify(ply, "Crafted: " .. r.name .. " x" .. made .. (made < n and "  (ran out of materials)" or ""))
		end
	elseif action == "dismantle" then Dismantle(ply, arg) end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Deployables: barricades and workbenches
-- Placing works with a preview: using a kit sends the player into placement mode (cl_placement.lua), they aim and
-- rotate a ghost of it and confirm; the spot is checked again here and the kit is used up once it's down.
util.AddNetworkString("GFR_PlaceStart")
util.AddNetworkString("GFR_PlaceConfirm")
util.AddNetworkString("GFR_PlaceCancel")

local PLACE_REACH = 260

function GFR.StartPlacement(ply, class)
	ply.GFR_Placing = class
	net.Start("GFR_PlaceStart")
	net.WriteString(class)
	net.Send(ply)
end

net.Receive("GFR_PlaceCancel", function(_, ply) ply.GFR_Placing = nil end)

net.Receive("GFR_PlaceConfirm", function(_, ply)
	local class = net.ReadString()
	local pos = net.ReadVector()
	local yaw = net.ReadFloat()
	if ply.GFR_Placing != class or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied then return end
	ply.GFR_Placing = nil
	local def = GFR.CustomItems[class]
	if !def or !def.place then return end
	local index
	for i, e in ipairs(ply.GFR_Inv or {}) do
		if e.class == class && !e.contaminated then index = i break end
	end
	if !index then return end
	if pos:Distance(ply:GetPos()) > PLACE_REACH then GFR.Notify(ply, "That's too far away.") return end
	local ent = GFR.PlaceDeployable(ply, def.place, pos, yaw)
	if ent then
		GFR.InvTake(ply, index, 1)
		if IsValid(ent) then ent.GFR_KitClass = class end -- picked back up as this kit (Crouch+E)
	end
end)

hook.Add("PlayerDeath", "GFR_Place_Death", function(ply) ply.GFR_Placing = nil end)

local placedEnts = {} -- [ent] = true: everything players have built

-- pos/yaw: from the placement preview (the spot on the ground and the facing). Without them: where you're looking.
-- Returns the placed entity (or false).
function GFR.PlaceDeployable(ply, place, pos, yaw)
	-- Built on another addon's entity that isn't installed (place.needs): the fallback version instead
	if place.fallback && ((place.needs && !scripted_ents.GetStored(place.needs)) or !util.IsValidModel(place.model)) then
		place = table.Merge(table.Copy(place), place.fallback)
		place.fallback = nil
	end
	if !pos then
		local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 160, filter = ply})
		if !tr.Hit or tr.HitNormal.z < 0.6 then
			GFR.Notify(ply, "Look at the ground where you want to put it.")
			return false
		end
		pos, yaw = tr.HitPos, ply:EyeAngles().y + 90
	end
	-- Needs solid, fairly flat ground under it
	local ground = util.TraceLine({start = pos + Vector(0, 0, 24), endpos = pos - Vector(0, 0, 40), filter = ply, mask = MASK_SOLID})
	if !ground.Hit or ground.HitNormal.z < 0.6 then
		GFR.Notify(ply, "It needs flat ground.")
		return false
	end
	pos = ground.HitPos
	if place.claim && GFR.CanClaim then
		local ok, why = GFR.CanClaim(ply, pos)
		if !ok then GFR.Notify(ply, why) return false end
	end
	local ent = ents.Create(place.class or "prop_physics") -- (turrets are their own entity: entities/gfr_turret.lua)
	ent:SetModel(place.model)
	ent:SetAngles(Angle(0, yaw, 0))
	ent:SetPos(pos)
	ent:Spawn()
	-- Map-only models (fences, bars, doors) have no physics to be a prop_physics with: build those as a solid,
	-- static piece instead. It still takes damage like any building.
	if !place.class && (!IsValid(ent) or !IsValid(ent:GetPhysicsObject())) then
		if IsValid(ent) then ent:Remove() end
		ent = ents.Create("prop_dynamic")
		ent:SetModel(place.model)
		ent:SetAngles(Angle(0, yaw, 0))
		ent:SetPos(pos)
		ent:SetKeyValue("solid", "6")
		ent:Spawn()
		ent:PhysicsInitStatic(SOLID_VPHYSICS)
		if !IsValid(ent:GetPhysicsObject()) then
			-- No collision model at all: a box the size of it
			ent:SetSolid(SOLID_BBOX)
			ent:SetCollisionBounds(ent:OBBMins(), ent:OBBMaxs())
		end
		ent:SetSaveValue("m_takedamage", 2) -- so damage reaches it (sv_crafting.lua barricade health)
	end
	ent:SetPos(pos - Vector(0, 0, ent:OBBMins().z))
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	-- Not inside a wall, another prop or a person
	local mins, maxs = ent:OBBMins() * 0.85, ent:OBBMaxs() * 0.85
	mins.z = math.max(mins.z, ent:OBBMins().z + 4)
	local hull = util.TraceHull({start = ent:GetPos() + Vector(0, 0, 2), endpos = ent:GetPos() + Vector(0, 0, 3), mins = mins, maxs = maxs, filter = ent, mask = MASK_SOLID})
	if hull.Hit then
		ent:Remove()
		GFR.Notify(ply, "It doesn't fit there.")
		return false
	end
	ent.GFR_Place = place
	if GFR.SetOwner then GFR.SetOwner(ent, ply) else ent.GFR_Builder = ply end -- (yours: sv_owners.lua)
	ent:SetNW2Bool("GFR_Placed", true) -- never a lootable map container (sh_containers.lua)
	if place.name then ent:SetNW2String("GFR_BuildName", place.name) end -- (its label, cl_crafting.lua)
	if place.storage or place.bed or place.lamp then
		if GFR.SetupBaseProp then GFR.SetupBaseProp(ent, place) end
	elseif place.workbench then
		ent:SetNW2Bool("GFR_Workbench", true)
	elseif place.gunbench then
		ent:SetNW2Bool("GFR_GunBench", true)
	elseif place.fire then
		-- Burn barrel: a harmless fire on top, lights up the night
		ent:SetNW2Bool("GFR_Fire", true)
		local fire = ents.Create("env_fire")
		fire:SetPos(ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z - 8))
		fire:SetKeyValue("firesize", "40")
		fire:SetKeyValue("damagescale", "0")
		fire:SetKeyValue("spawnflags", tostring(1 + 4 + 16)) -- infinite, start on, don't drop
		fire:SetParent(ent)
		fire:Spawn()
		fire:Fire("StartFire")
		ent:DeleteOnRemove(fire)
	else
		ent.GFR_BarricadeHP = place.hp
		ent:SetNW2Int("GFR_BarHP", place.hp)
		ent:SetNW2Int("GFR_BarMax", place.hp)
	end
	if ent.SetupTurret then ent:SetupTurret() end
	if place.claim && GFR.RegisterClaim then GFR.RegisterClaim(ent) end -- (sh_claim.lua)
	-- Stays exactly where it was put (zombies can damage it, never knock it loose: see below)
	ent.GFR_FixedPos, ent.GFR_FixedAng = ent:GetPos(), ent:GetAngles()
	placedEnts[ent] = true
	ent:EmitSound(place.material == "metal" and "physics/metal/metal_solid_impact_hard1.wav" or "physics/wood/wood_plank_impact_hard1.wav")
	return ent
end

-- VJ Base NPCs "clear" props in their way: unfreeze them and shove them hard. Our buildings only take the damage.
local function PinDown(ent)
	if !IsValid(ent) or !ent.GFR_FixedPos then return end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) && phys:IsMotionEnabled() then
		phys:EnableMotion(false)
		phys:SetVelocityInstantaneous(vector_origin)
	end
	if ent:GetPos():DistToSqr(ent.GFR_FixedPos) > 1 or math.abs(math.AngleDifference(ent:GetAngles().y, ent.GFR_FixedAng.y)) > 0.5 then
		ent:SetPos(ent.GFR_FixedPos)
		ent:SetAngles(ent.GFR_FixedAng)
	end
end

hook.Add("EntityTakeDamage", "GFR_Placed_NoShove", function(ent)
	if ent.GFR_FixedPos then
		PinDown(ent)
		timer.Simple(0, function() PinDown(ent) end) -- (the shove is applied in the same attack)
	end
end)

timer.Create("GFR_Placed_KeepFixed", 0.25, 0, function()
	for ent in pairs(placedEnts) do
		if !IsValid(ent) then placedEnts[ent] = nil else PinDown(ent) end
	end
end)

-- Barbed wire (place.spikes): zombies pushing into it get cut every half second, and the wire wears down
timer.Create("GFR_Placed_Spikes", 0.5, 0, function()
	for ent in pairs(placedEnts) do
		local spikes = IsValid(ent) && ent.GFR_Place && ent.GFR_Place.spikes
		if !spikes then continue end
		local mins, maxs = ent:OBBMins() - Vector(18, 18, 0), ent:OBBMaxs() + Vector(18, 18, 30)
		for _, z in ipairs(ents.FindInSphere(ent:WorldSpaceCenter(), ent:BoundingRadius() + 30)) do
			if !IsValid(ent) then break end -- (worn through)
			if z:IsNPC() && z:Health() > 0 && GFR.IsZombie && GFR.IsZombie(z) then
				local lp = ent:WorldToLocal(z:GetPos() + Vector(0, 0, 10))
				if lp:WithinAABox(mins, maxs) then
					z:TakeDamage(spikes, ent, ent)
					if math.random(3) == 1 then
						local fx = EffectData()
						fx:SetOrigin(z:GetPos() + Vector(0, 0, 30))
						util.Effect("BloodImpact", fx)
						ent:EmitSound("physics/metal/metal_chainlink_impact_soft" .. math.random(1, 3) .. ".wav", 60)
					end
					if IsValid(ent) then ent:TakeDamage(1, game.GetWorld(), game.GetWorld()) end
				end
			end
		end
	end
end)

local function BreakBarricade(ent)
	local metal = ent.GFR_Place && ent.GFR_Place.material == "metal"
	ent:EmitSound(metal and "physics/metal/metal_box_break1.wav" or ("physics/wood/wood_plank_break" .. math.random(1, 4) .. ".wav"))
	local fx = EffectData()
	fx:SetOrigin(ent:WorldSpaceCenter())
	fx:SetMagnitude(2)
	fx:SetScale(2)
	util.Effect(metal and "ManhackSparks" or "WheelDust", fx)
	ent:Remove()
end

-- Any damage wears it down: zombies attack props blocking their way, people shoot through them
hook.Add("EntityTakeDamage", "GFR_Barricade_Damage", function(ent, dmginfo)
	if !ent.GFR_BarricadeHP then return end
	ent.GFR_BarricadeHP = ent.GFR_BarricadeHP - dmginfo:GetDamage()
	ent:SetNW2Int("GFR_BarHP", math.max(math.ceil(ent.GFR_BarricadeHP), 0))
	if ent.GFR_BarricadeHP <= 0 then BreakBarricade(ent) end
end)

hook.Add("KeyPress", "GFR_Barricade_Use", function(ply, key)
	if key != IN_USE or !ply:Alive() or ply.GFR_IsZombie or ply:KeyDown(IN_SPEED) then return end -- (Shift+E: access, sv_owners.lua)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 110, filter = ply})
	local ent = tr.Entity
	if !IsValid(ent) or !ent.GFR_Place then return end

	if ply:Crouching() then
		-- Someone else's: only they, their access list and admins take it down
		if GFR.CanUseOwned && !GFR.CanUseOwned(ply, ent) then
			GFR.Notify(ply, "That belongs to " .. ent:GetNW2String("GFR_OwnerName", "someone else") .. ".")
			return
		end
		if ent.GFR_Storage && #ent.GFR_Storage > 0 then
			GFR.Notify(ply, "Empty it first.")
			return
		end
		local damaged = ent.GFR_BarricadeHP && ent.GFR_BarricadeHP < (ent.GFR_Place.hp or 0)
		local kit = ent.GFR_KitClass
		local function ReturnAmmo()
			if ent.GFR_Turret && (ent.Ammo or 0) > 0 then
				local types = ent.GFR_Place.turret && ent.GFR_Place.turret.ammo or {"pistol"}
				ply:GiveAmmo(ent.Ammo, types[1], true)
			end
		end

		-- In one piece: pick it up as its kit, to put it somewhere else
		if kit && !damaged then
			local def = GFR.CustomItems[kit]
			if GFR.InvAdd(ply, kit, 1, false, def && def.model) == 0 then
				GFR.Notify(ply, "No room in your bag to carry it.")
				return
			end
			ReturnAmmo()
			ent:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav")
			ent:Remove()
			GFR.Notify(ply, "Picked up. Use the kit from your bag to place it again.")
			return
		end

		-- Damaged: repair it to move it, or tear it down for some materials (Crouch+E again)
		if kit && (ply.GFR_TearDown != ent or (ply.GFR_TearDownT or 0) < CurTime()) then
			ply.GFR_TearDown, ply.GFR_TearDownT = ent, CurTime() + 3
			GFR.Notify(ply, "It's damaged: repair it (E) to pick it up and move it. Crouch+E again to tear it down for materials.")
			return
		end
		ply.GFR_TearDown = nil
		for class, n in pairs(ent.GFR_Place.refund or {}) do GiveItem(ply, class, n) end
		ReturnAmmo()
		GFR.InvSync(ply)
		ent:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav")
		ent:Remove()
		GFR.Notify(ply, "Torn down for materials.")
		return
	end

	-- Turret: E loads it with your ammo; once it's full, E repairs it
	if ent.GFR_Turret then
		local got = ent:LoadFrom(ply)
		local cap = ent:GetNW2Int("GFR_TurretMax", 0)
		if got > 0 then
			ent:EmitSound("items/ammo_pickup.wav", 65)
			GFR.Notify(ply, "Loaded " .. got .. " rounds (" .. ent.Ammo .. " / " .. cap .. ").")
			return
		end
		if ent.GFR_BarricadeHP >= ent.GFR_Place.hp then
			GFR.Notify(ply, ent.Ammo >= cap and "It's fully loaded." or ("You have no " .. ent:GetNW2String("GFR_TurretAmmoName", "ammo") .. " for it."))
			return
		end
	end

	if ent.GFR_BarricadeHP then
		local max = ent.GFR_Place.hp
		if ent.GFR_BarricadeHP >= max then return end
		local mat = ent.GFR_Place.material == "metal" and "gfr_mat_scrap" or "gfr_mat_wood"
		if CountClean(ply, mat) < 1 then
			GFR.Notify(ply, "You need " .. GFR.ItemDisplayName(mat) .. " to repair it.")
			return
		end
		TakeClean(ply, mat, 1)
		GFR.InvSync(ply)
		ent.GFR_BarricadeHP = math.min(ent.GFR_BarricadeHP + max * 0.4, max)
		ent:SetNW2Int("GFR_BarHP", math.ceil(ent.GFR_BarricadeHP))
		ent:EmitSound("physics/wood/wood_plank_impact_hard" .. math.random(1, 5) .. ".wav")
	end
end)

-- Placed props aren't carried around with E
hook.Add("AllowPlayerPickup", "GFR_Barricade_NoCarry", function(ply, ent)
	if ent.GFR_Place then return false end
end)
