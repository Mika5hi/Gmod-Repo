--[[
	Custom Apocalypse - container search (server)
	Press Q on a container to search it. Keep looking at it and stay close until the bar fills.
	Found items go straight into your inventory (guns and anything that doesn't fit are left at the container).
	A searched container refills after gfr_loot_refresh_hours of in-game time (12; sleeping through it counts).
	Fallout Looting System's own container looting is switched off while this gamemode runs (its body searching stays).
]]

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_containers_enabled", "1", flags, "Enable searching containers")
local cvRefill = CreateConVar("gfr_loot_refresh_hours", "12", flags, "In-game hours before a searched container has loot again (and before map loot is topped up); sleeping speeds it up")

-- In-game hours now (sv_daynight.lua; real time as a stand-in if that isn't loaded)
local function GameHours() return GFR.GameHours and GFR.GameHours() or CurTime() / 60 end

-- Searched: empty until gfr_loot_refresh_hours of in-game time have gone by (also people scavenging: sv_groupwander.lua)
function GFR.MarkSearched(ent)
	ent.GFR_SearchedUntil = math.huge
	ent.GFR_RefillHour = GameHours() + cvRefill:GetFloat()
	ent.GFR_SearchedAt = CurTime() -- spawned stashes are cleared away a bit later (sv_loot.lua)
	ent:SetNW2Bool("GFR_Searched", true)
end
local cvSpeed   = CreateConVar("gfr_container_speed", "1", flags, "Search time multiplier (lower = faster)")
local cvAmount  = CreateConVar("gfr_container_loot_mult", "1", flags, "How much is in each container (2 = twice the items and fewer empty ones, 0.5 = half)")

-- n items x the multiplier (a fraction is a chance at one more)
local function Scaled(n)
	local v = n * math.max(cvAmount:GetFloat(), 0)
	local whole = math.floor(v)
	return whole + (math.Rand(0, 1) < v - whole and 1 or 0)
end

-- Chance it's empty: more loot means fewer empty ones, less means more
local function EmptyChance(empty)
	local m = math.max(cvAmount:GetFloat(), 0.01)
	if m >= 1 then return empty / m end
	return 1 - (1 - empty) * m
end

util.AddNetworkString("GFR_Search")

local SEARCH_RANGE = 110

-- Crunchy's spawnable supply crates are searched like containers (sh_containers.lua GFR.ContainerClasses),
-- not shot open for Crunchy's own items
hook.Add("EntityTakeDamage", "GFR_Containers_NoBreak", function(ent)
	if GFR.ContainerClasses && GFR.ContainerClasses[ent:GetClass()] then return true end
end)

local function SendSearch(ply, ent, duration)
	net.Start("GFR_Search")
	net.WriteEntity(ent or NULL)
	net.WriteFloat(duration or 0)
	net.Send(ply)
end

local function LookedAtContainer(ply)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * SEARCH_RANGE, filter = ply})
	local ent = tr.Entity
	if IsValid(ent) && GFR.ContainerType(ent) then return ent end
end

local function StopSearch(ply, silent)
	if !ply.GFR_Search then return end
	ply.GFR_Search = nil
	SendSearch(ply, NULL, 0)
	if !silent then GFR.Notify(ply, "Search interrupted.") end
end

-- ply: who's searching (attachments are mostly for guns they carry, sh_attachments.lua)
local function RollLoot(typeId, ply)
	local def = GFR.ContainerTypes[typeId]
	local found = {}
	if !def or !GFR.Loot then return found end
	-- Some containers pack a set loadout instead of random rolls (supply drops: sv_airdrop.lua)
	if def.custom && GFR[def.custom] then return GFR[def.custom](ply) end

	-- Weapon attachments ("att:<name>"), rolled on their own
	local a = def.atts
	if a && GFR.RandomAttachment && GetConVar("gfr_arc9_found"):GetBool() && math.Rand(0, 1) < a.chance then
		for _ = 1, math.random(a.n[1], a.n[2]) do
			local att = GFR.RandomAttachment(ply)
			if att then found[#found + 1] = "att:" .. att end
		end
	end

	-- Salvage: materials that fit this kind of container, rolled separately so junk is rarely empty
	local s = def.salvage
	if s && math.Rand(0, 1) < s.chance then
		for _ = 1, Scaled(math.random(s.n[1], s.n[2])) do
			local mat = s.mats[math.random(#s.mats)]
			if scripted_ents.GetStored(mat) then found[#found + 1] = mat end
		end
	end

	-- Always one of these (a weapon crate always holds a gun: def.always = pool weights), with its ammo as usual
	if def.always then
		local pool = GFR.Loot.PickPool(def.always)
		local class = GFR.Loot.PickItem(pool)
		if class then
			found[#found + 1] = class
			if GFR.Loot.GunPools[pool] && math.random(1, 3) != 1 then
				local ammo = GFR.Loot.AmmoItemFor(class)
				if ammo then found[#found + 1] = ammo end
			end
		end
	end

	if math.Rand(0, 1) < EmptyChance(def.empty) then return found end
	for _ = 1, math.max(Scaled(math.random(def.min, def.max)), 1) do
		local pool = GFR.Loot.PickPool(def.weights)
		local class = GFR.Loot.PickItem(pool)
		if class then
			found[#found + 1] = class
			-- A gun usually comes with some ammo for it
			if GFR.Loot.GunPools[pool] && math.random(1, 3) != 1 then
				local ammo = GFR.Loot.AmmoItemFor(class)
				if ammo then found[#found + 1] = ammo end
			end
		end
	end
	return found
end

local function CleanName(class)
	local stored = scripted_ents.GetStored(class)
	if stored then return GFR.CleanName(stored.t.PrintName or class) end
	local wep = weapons.GetStored(class)
	return wep && wep.PrintName or class
end

-- World model of an item class (some Crunchy items only set it in Initialize), for the inventory icon
local modelCache = {}
local function ModelOf(class)
	if modelCache[class] then return modelCache[class] end
	local stored = scripted_ents.GetStored(class)
	local mdl = stored && stored.t.WorldModel
	if !mdl then
		local tmp = ents.Create(class)
		if IsValid(tmp) then
			tmp:Spawn()
			mdl = tmp:GetModel()
			tmp:Remove()
		end
	end
	modelCache[class] = mdl
	return mdl
end
GFR.ModelOf = ModelOf

-- Supply Units (cargo): searching unlocks it. The lid opens (its opened model) and the loot is laid out inside, to take
-- with E. Opened, it stays open and empty for good.
local function OpenUnit(ply, ent, found, opened)
	ent.GFR_SearchedUntil = math.huge
	ent:SetSkin(1) -- (the lock light goes green, as Crunchy's do)
	ent:EmitSound("supply_unit_open.wav", 75)
	local seq = ent:LookupSequence("opening")
	if seq >= 0 then ent:ResetSequence(seq) end
	GFR.Notify(ply, "The lock clicks open.")
	timer.Simple(0.9, function()
		if !IsValid(ent) then return end
		local pos, ang = ent:GetPos(), ent:GetAngles()
		ent:SetModel(opened)
		ent:SetSkin(0)
		ent:PhysicsInit(SOLID_VPHYSICS)
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		ent:SetPos(pos)
		ent:SetAngles(ang)
		timer.Simple(0.1, function()
			if !IsValid(ent) then return end
			ent:InvalidateBoneCache() -- (bones from the new model; SetupBones is client-only)
			local bones = ent:GetBoneCount()
			for i, class in ipairs(found) do
				-- Crunchy's opened models have a spot for an item on each bone after the first two
				local p = (i + 1 < bones) && ent:GetBonePosition(i + 1)
				if !p or p:DistToSqr(ent:GetPos()) < 1 then
					p = ent:WorldSpaceCenter() + ent:GetForward() * math.Rand(-14, 14) + ent:GetRight() * math.Rand(-8, 8)
				end
				p = p + Vector(0, 0, 3)
				local att = string.match(class, "^att:(.+)$")
				local item = att and GFR.SpawnAttachmentBox && GFR.SpawnAttachmentBox(att, p) or (!att and GFR.Loot.SpawnItem(class, p))
				if IsValid(item) then
					item:SetAngles(ang)
					local ip = item:GetPhysicsObject()
					if IsValid(ip) then ip:Sleep() end
				end
			end
		end)
	end)
end

-- Crunchy's spawn-menu Supply Units open themselves on E with Crunchy's items: searching them is the only way in
hook.Add("PlayerUse", "GFR_Containers_UnitNoUse", function(ply, ent)
	if GFR.ContainerClasses[ent:GetClass()] then return false end
end)

local function FinishSearch(ply, ent)
	local typeId = GFR.ContainerType(ent)
	GFR.MarkSearched(ent)

	local found = RollLoot(typeId, ply)
	local opened = GFR.ContainerOpensTo(ent)
	if opened && util.IsValidModel(opened) then
		OpenUnit(ply, ent, found, opened)
		return
	end
	if #found == 0 then
		GFR.Notify(ply, "Nothing useful.")
		return
	end

	local names, leftBehind = {}, false
	local dropPos = ent:WorldSpaceCenter() + (ply:GetPos() - ent:GetPos()):GetNormalized() * 30 + Vector(0, 0, 10)
	local gotAtt = false
	for _, class in ipairs(found) do
		local att = string.match(class, "^att:(.+)$")
		if att then
			-- Straight into your attachment stash
			ARC9:PlayerGiveAtt(ply, att, 1)
			gotAtt = true
			names[#names + 1] = GFR.AttName(att)
			continue
		end
		if class == "gfr_currency" then
			local caps = math.random(3, 15)
			GFR.AddCaps(ply, caps)
			names[#names + 1] = caps .. " caps"
			continue
		end
		if class == "gfr_recipe_note" then
			-- Read on the spot
			names[#names + 1] = "a recipe note"
			timer.Simple(0.5, function() if IsValid(ply) then GFR.LearnRandomRecipe(ply) end end)
			continue
		end
		names[#names + 1] = CleanName(class)
		-- Supply crates are too big to pocket
		local isItem = scripted_ents.GetStored(class) != nil && !string.StartWith(class, "supply_")
		local stored = isItem && GFR.InvAdd && GFR.InvAdd(ply, class, 1, false, ModelOf(class)) or 0
		if stored == 0 then
			-- Guns, crates, or no room: leave it at the container
			GFR.Loot.SpawnItem(class, dropPos + VectorRand() * 8)
			if isItem then leftBehind = true end
		end
	end
	-- "3x Scrap Metal, Water Bottle" instead of repeating names
	local counts, order = {}, {}
	for _, n in ipairs(names) do
		if !counts[n] then order[#order + 1] = n end
		counts[n] = (counts[n] or 0) + 1
	end
	local parts = {}
	for _, n in ipairs(order) do parts[#parts + 1] = (counts[n] > 1 and (counts[n] .. "x ") or "") .. n end
	GFR.Notify(ply, "Found: " .. table.concat(parts, ", "))
	if gotAtt then
		ARC9:PlayerSendAttInv(ply)
		GFR.Notify(ply, "Weapon parts go in your attachment stash: fit them at a Gun Table.")
	end
	if leftBehind then GFR.Notify(ply, "You can't carry it all. Some was left behind.") end
end

-- Q searches (E stays for picking things up / talking)
hook.Add("PlayerButtonDown", "GFR_Containers_Search", function(ply, button)
	if button != KEY_Q or !cvEnabled:GetBool() or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Search or ply.GFR_Tied then return end
	local ent = LookedAtContainer(ply)
	if !ent then return end

	if (ent.GFR_SearchedUntil or 0) > CurTime() then
		GFR.Notify(ply, "Already searched.")
		return
	end
	local def = GFR.ContainerTypes[GFR.ContainerType(ent)]
	local duration = def.time * math.max(cvSpeed:GetFloat(), 0.05)
	ply.GFR_Search = {ent = ent, finish = CurTime() + duration, pos = ply:GetPos()}
	SendSearch(ply, ent, duration)
	ent:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 60)
end)

-- Smashing a breakable container (wooden crates, boxes...) spills what was inside, unless it was already searched
GFR.RollContainerLoot = RollLoot
hook.Add("PropBreak", "GFR_Containers_BreakLoot", function(attacker, prop)
	if !cvEnabled:GetBool() then return end
	local typeId = GFR.ContainerType(prop)
	if !typeId then return end
	if prop.GFR_Stash && GFR.Loot && GFR.Loot.StashBroken then GFR.Loot.StashBroken(prop) end
	if (prop.GFR_SearchedUntil or 0) > CurTime() then return end
	local center = prop:WorldSpaceCenter()
	for _, class in ipairs(RollLoot(typeId, IsValid(attacker) && attacker:IsPlayer() and attacker or nil)) do
		local pos = center + Vector(math.Rand(-14, 14), math.Rand(-14, 14), math.Rand(4, 16))
		local att = string.match(class, "^att:(.+)$")
		local item = att and GFR.SpawnAttachmentBox(att, pos) or (!att and GFR.Loot.SpawnItem(class, pos))
		local phys = IsValid(item) && item:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity(VectorRand() * 60 + Vector(0, 0, 80)) end
	end
end)

-- Can't carry containers around with E (the physgun still works)
hook.Add("AllowPlayerPickup", "GFR_Containers_NoCarry", function(ply, ent)
	if cvEnabled:GetBool() && GFR.ContainerType(ent) then return false end
end)

hook.Add("EntityTakeDamage", "GFR_Containers_HurtInterrupts", function(target)
	if target:IsPlayer() && target.GFR_Search then StopSearch(target) end
end)

timer.Create("GFR_Containers_Tick", 0.1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local s = ply.GFR_Search
		if !s then continue end
		if !ply:Alive() or !IsValid(s.ent) or LookedAtContainer(ply) != s.ent or ply:GetPos():DistToSqr(s.pos) > 40 * 40 then
			StopSearch(ply, !ply:Alive())
		elseif CurTime() >= s.finish then
			StopSearch(ply, true)
			FinishSearch(ply, s.ent)
		elseif math.random(1, 8) == 1 then
			s.ent:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 55, math.random(90, 110))
		end
	end
end)

-- Refilled containers become searchable again (in-game time: GFR.MarkSearched; a few still use a real-time
-- GFR_SearchedUntil)
timer.Create("GFR_Containers_Refill", 5, 0, function()
	local hours = GameHours()
	for _, ent in ipairs(ents.GetAll()) do
		local due = ent.GFR_RefillHour and hours >= ent.GFR_RefillHour
			or (!ent.GFR_RefillHour && ent.GFR_SearchedUntil && ent.GFR_SearchedUntil <= CurTime())
		if due then
			ent.GFR_SearchedUntil = nil
			ent.GFR_RefillHour = nil
			ent:SetNW2Bool("GFR_Searched", false)
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Fallout Looting System: turn off its container looting while this gamemode runs, restore it afterwards. Your value is
-- kept in a cookie too, so a crash doesn't leave it off (lua/autorun/gfr_restore_settings.lua puts it back)
local FALLOUT_COOKIE = "gfr_fallout_saved"
hook.Add("InitPostEntity", "GFR_Containers_FalloutOff", function()
	local cv = GetConVar("loots_enable_container")
	if cv && cv:GetBool() then
		if !cookie.GetString(FALLOUT_COOKIE) then cookie.Set(FALLOUT_COOKIE, cv:GetString()) end
		RunConsoleCommand("loots_enable_container", "0")
	end
end)
hook.Add("ShutDown", "GFR_Containers_FalloutRestore", function()
	local was = cookie.GetString(FALLOUT_COOKIE)
	if was then RunConsoleCommand("loots_enable_container", was) end
	cookie.Delete(FALLOUT_COOKIE)
end)
