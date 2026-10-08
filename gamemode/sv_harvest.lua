--[[
	Custom Apocalypse - harvesting zombie corpses
	Q on a zombie corpse while holding a knife (or another blade: GFR.IsBlade) to cut 1-2 body parts + zombie blood.
		Raw parts (Crunchy's meat_*) can be eaten: filling, but 60% infection chance.
		Cook them at a burn barrel (Crafting > Survival) for a 10% chance instead.
		Zombie Blood + cloth = Gut Camouflage: the dead ignore you for a while, until you attack one.
		Drop raw meat on the ground and the dead come to eat it: bait.
		The military buys parts and blood for research (sv_npc.lua).
	Cutting while bleeding is a good way to get infected.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvTime = CreateConVar("gfr_harvest_time", "4", flags, "Seconds to harvest a zombie corpse")
local cvCamo = CreateConVar("gfr_camo_time", "150", flags, "Seconds gut camouflage lasts")

util.AddNetworkString("GFR_Progress")

local function Progress(ply, text, duration)
	net.Start("GFR_Progress")
	net.WriteString(text or "")
	net.WriteFloat(duration or 0)
	net.Send(ply)
end

local function Zombies()
	local list = {}
	for _, ent in ipairs(ents.GetAll()) do
		if ent:IsNPC() && GFR.IsZombie(ent) then list[#list + 1] = ent end
	end
	return list
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Which ragdolls are zombie corpses: matched to where a zombie just died (death animations delay the ragdoll)
local zombieDeaths = {}

hook.Add("OnNPCKilled", "GFR_Harvest_TrackDeaths", function(npc)
	if !GFR.IsZombie(npc) then return end
	zombieDeaths[#zombieDeaths + 1] = {pos = npc:GetPos(), time = CurTime()}
	if #zombieDeaths > 40 then table.remove(zombieDeaths, 1) end
end)

hook.Add("OnEntityCreated", "GFR_Harvest_MarkCorpse", function(ent)
	local class = ent:GetClass()
	if class == "prop_ragdoll" then
		timer.Simple(0.2, function()
			if !IsValid(ent) or ent.GFR_HumanCorpse then return end
			local pos, now = ent:GetPos(), CurTime()
			for i = #zombieDeaths, 1, -1 do
				local d = zombieDeaths[i]
				if now - d.time > 30 then
					table.remove(zombieDeaths, i)
				elseif d.pos:DistToSqr(pos) < 150 * 150 then
					ent.GFR_ZCorpse = true
					ent:SetNW2Bool("GFR_ZCorpse", true)
					table.remove(zombieDeaths, i)
					return
				end
			end
		end)

	-- Raw meat on the ground is bait: the dead smell it and come to eat
	elseif string.StartWith(class, "meat_") then
		timer.Simple(0.3, function()
			if !IsValid(ent) or ent.GFR_FromInventory or !VJ or !VJ.Corpse_AddStinky then return end
			ent:SetMaxHealth(30)
			ent:SetHealth(30)
			ent.BloodData = {Color = VJ.BLOOD_COLOR_RED, Particle = "blood_impact_red_01", Decal = "Blood"}
			ent.GFR_Bait = true
			VJ.Corpse_AddStinky(ent, false)
		end)
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Harvesting
local parts = {
	{"meat_chunk1", 20}, {"meat_chunk2", 20}, {"meat_arm1", 12}, {"meat_arm2", 12},
	{"meat_leg1", 10}, {"meat_leg2", 10}, {"meat_torso", 8}, {"meat_head", 8}
}

local function PickPart()
	local total = 0
	for _, p in ipairs(parts) do if scripted_ents.GetStored(p[1]) then total = total + p[2] end end
	local roll = math.Rand(0, total)
	for _, p in ipairs(parts) do
		if scripted_ents.GetStored(p[1]) then
			roll = roll - p[2]
			if roll <= 0 then return p[1] end
		end
	end
end

local function HasBlade(ply)
	for _, w in ipairs(ply:GetWeapons()) do
		local c = w:GetClass()
		if string.find(c, "melee", 1, true) or string.find(c, "knife", 1, true) or string.find(c, "machete", 1, true)
			or string.find(c, "axe", 1, true) or c == "weapon_crowbar" then
			return true
		end
	end
	return false
end

local function LookedAtCorpse(ply)
	return GFR.LookedAtZCorpse(ply)
end

local function GiveOrDrop(ply, class, pos)
	local model = (GFR.CustomItems[class] && GFR.CustomItems[class].model) or (GFR.ModelOf && GFR.ModelOf(class))
	if GFR.InvAdd(ply, class, 1, false, model) == 0 then
		GFR.Loot.SpawnItem(class, pos + VectorRand() * 10 + Vector(0, 0, 10))
		return false
	end
	return true
end

local function FinishHarvest(ply, ent)
	ent.GFR_Harvested = true
	ent:SetNW2Bool("GFR_Harvested", true)
	ent:SetColor(Color(150, 90, 90))
	local pos = ent:WorldSpaceCenter()
	local got, full = {}, false

	for _ = 1, math.random(1, 2) do
		local part = PickPart()
		if part then
			if !GiveOrDrop(ply, part, pos) then full = true end
			got[#got + 1] = GFR.ItemDisplayName(part)
		end
	end
	if math.random(1, 100) <= 60 then
		local n = math.random(1, 2)
		for _ = 1, n do
			if !GiveOrDrop(ply, "gfr_mat_zblood", pos) then full = true end
		end
		got[#got + 1] = n .. "x Zombie Blood"
	end
	GFR.Notify(ply, "Harvested: " .. table.concat(got, ", "))
	if full then GFR.Notify(ply, "No room. Some was left on the ground.") end
	ent:EmitSound("physics/flesh/flesh_bloody_break.wav", 70)

	-- Nothing much is left of it afterwards: a wet mess, then it's gone
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetScale(6)
	fx:SetFlags(3)
	fx:SetColor(0)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	local tr = util.TraceLine({start = pos, endpos = pos - Vector(0, 0, 80), filter = ent})
	util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
	-- Anything still in its pockets falls out
	for _, it in ipairs(ent.GFR_Pockets or {}) do
		local class = istable(it) and it.class or it
		if class && GFR.Loot && GFR.Loot.SpawnItem then GFR.Loot.SpawnItem(class, pos + VectorRand() * 12 + Vector(0, 0, 8)) end
	end
	ent.GFR_Pockets = nil
	ent:Remove()

	-- Elbow-deep in the dead
	if ply.GFR_Bleeding && math.random(1, 100) <= 30 then
		GFR.Notify(ply, "Zombie blood got into your open wound...")
		GFR.Infect(ply, 1)
	elseif math.random(1, 100) <= 4 then
		net.Start("GFR_BloodSplat")
		net.Send(ply)
		GFR.Notify(ply, "Zombie blood splashed into your face!")
		if math.random(1, 100) <= 35 then GFR.Infect(ply, 1) end
	end
end

local function StopHarvest(ply, msg)
	if !ply.GFR_Harvest then return end
	ply.GFR_Harvest = nil
	Progress(ply, "", 0)
	if msg then GFR.Notify(ply, msg) end
end

-- Q harvests, same key as searching containers
-- Going through a dead body's pockets (loot put there by sv_loot.lua)
local function FinishPockets(ply, ent)
	local items = ent.GFR_Pockets or {}
	ent.GFR_Pockets = nil
	ent:SetNW2Bool("GFR_HasPockets", false)
	local names, dropped = {}, false
	local pos = ent:WorldSpaceCenter()
	for _, it in ipairs(items) do
		local class = it.class
		if class == "gfr_currency" then
			local caps = math.random(3, 15)
			GFR.AddCaps(ply, caps)
			names[#names + 1] = caps .. " caps"
		elseif class == "gfr_recipe_note" then
			names[#names + 1] = "a recipe note"
			timer.Simple(0.5, function() if IsValid(ply) then GFR.LearnRandomRecipe(ply) end end)
		elseif weapons.GetStored(class) then
			-- Guns/knives: straight into your hands if you don't have one, else left on the body
			if !ply:HasWeapon(class) then
				local w = ply:Give(class, true)
				if IsValid(w) && w:GetMaxClip1() > 0 then w:SetClip1(math.random(0, math.ceil(w:GetMaxClip1() / 2))) end
			else
				GFR.Loot.SpawnItem(class, pos + Vector(0, 0, 10))
			end
			names[#names + 1] = GFR.ItemDisplayName(class) != class and GFR.ItemDisplayName(class) or (weapons.Get(class).PrintName or class)
		else
			local model = (GFR.CustomItems[class] && GFR.CustomItems[class].model) or (GFR.ModelOf && GFR.ModelOf(class))
			if GFR.InvAdd(ply, class, 1, it.contaminated, model) == 0 then
				GFR.SpillItems(pos, {it})
				dropped = true
			end
			names[#names + 1] = GFR.ItemDisplayName(class) .. (it.contaminated and " (bloody)" or "")
		end
	end
	if #names == 0 then
		GFR.Notify(ply, "Nothing useful.")
	else
		GFR.Notify(ply, "Found: " .. table.concat(names, ", "))
		if dropped then GFR.Notify(ply, "No room. Some was left by the body.") end
	end
end

hook.Add("PlayerButtonDown", "GFR_Harvest_Use", function(ply, button)
	if button != KEY_Q or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Harvest or ply.GFR_Tied then return end
	local ent = LookedAtCorpse(ply)
	if !ent then return end
	-- Pockets first (no blade needed), then harvesting if it's one of the dead
	if ent:GetNW2Bool("GFR_HasPockets") then
		ply.GFR_Harvest = {ent = ent, finish = CurTime() + 2.5, pos = ply:GetPos(), pockets = true}
		Progress(ply, "Searching the body...", 2.5)
		ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 60)
		return
	end
	if !ent.GFR_ZCorpse then return end
	if ent.GFR_Harvested then GFR.Notify(ply, "There's nothing useful left on this one.") return end
	if !GFR.HoldingBlade(ply) then return end -- (hold a knife to butcher it: sh_equipment.lua GFR.IsBlade)
	if ent.GFR_Burned then GFR.Notify(ply, "It's burned through. Nothing worth taking.") return end
	ply.GFR_Harvest = {ent = ent, finish = CurTime() + cvTime:GetFloat(), pos = ply:GetPos()}
	Progress(ply, "Harvesting...", cvTime:GetFloat())
	ent:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 65)
end)

hook.Add("EntityTakeDamage", "GFR_Harvest_Interrupt", function(target)
	if target:IsPlayer() && target.GFR_Harvest then StopHarvest(target, "Harvest interrupted.") end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Gut camouflage
local function RemoveCamo(ply, msg)
	if !ply.GFR_CamoActive then return end
	ply.GFR_CamoActive = nil
	ply.VJ_NPC_Class = ply.GFR_CamoOldClass
	ply:SetNW2Float("GFR_CamoUntil", 0)
	for _, z in ipairs(Zombies()) do z:AddEntityRelationship(ply, D_HT, 99) end
	if msg then GFR.Notify(ply, msg) end
end

function GFR.ApplyCamo(ply)
	if !ply:Alive() then return false end
	if !ply.GFR_CamoActive then ply.GFR_CamoOldClass = ply.VJ_NPC_Class end
	ply.GFR_CamoActive = true
	ply.GFR_CamoUntil = CurTime() + cvCamo:GetFloat()
	ply:SetNW2Float("GFR_CamoUntil", ply.GFR_CamoUntil)
	-- VJ NPCs treat entities sharing their class as friends; HL2 zombies use relationships
	ply.VJ_NPC_Class = {"CLASS_ZOMBIE"}
	for _, z in ipairs(Zombies()) do
		z:AddEntityRelationship(ply, D_NU, 99)
		if z:GetEnemy() == ply then
			z:SetEnemy(NULL)
			z:ClearEnemyMemory(ply)
		end
	end
	ply:EmitSound("physics/flesh/flesh_bloody_break.wav")
	GFR.Notify(ply, "You smear gore all over yourself. The dead won't notice you... for a while.")
	return true
end

-- Zombies that show up later are fooled too
hook.Add("OnEntityCreated", "GFR_Camo_NewZombies", function(ent)
	timer.Simple(0.2, function()
		if !IsValid(ent) or !ent:IsNPC() or !GFR.IsZombie(ent) then return end
		for _, ply in ipairs(player.GetAll()) do
			if ply.GFR_CamoActive then ent:AddEntityRelationship(ply, D_NU, 99) end
		end
	end)
end)

-- Attacking one gives you away
hook.Add("EntityTakeDamage", "GFR_Camo_Break", function(target, dmginfo)
	local attacker = dmginfo:GetAttacker()
	if IsValid(attacker) && attacker:IsPlayer() && attacker.GFR_CamoActive && GFR.IsZombie(target) then
		RemoveCamo(attacker, "The dead noticed you!")
	end
end)

hook.Add("PlayerDeath", "GFR_Camo_Death", function(ply) RemoveCamo(ply) StopHarvest(ply) end)
hook.Add("PlayerSpawn", "GFR_Camo_Spawn", function(ply) RemoveCamo(ply) end)

---------------------------------------------------------------------------------------------------------------------------------------------
timer.Create("GFR_Harvest_Tick", 0.1, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		local h = ply.GFR_Harvest
		if h then
			if !ply:Alive() or !IsValid(h.ent) or LookedAtCorpse(ply) != h.ent or ply:GetPos():DistToSqr(h.pos) > 40 * 40 then
				StopHarvest(ply, ply:Alive() and "Harvest interrupted." or nil)
			elseif now >= h.finish then
				StopHarvest(ply)
				if h.pockets then FinishPockets(ply, h.ent) else FinishHarvest(ply, h.ent) end
			end
		end
		if ply.GFR_CamoActive && now > (ply.GFR_CamoUntil or 0) then
			RemoveCamo(ply, "The gore has dried. They can smell you again.")
		end
	end
end)
