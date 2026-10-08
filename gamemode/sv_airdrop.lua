--[[
	Custom Apocalypse - supply drops
	Fire a signal flare (ARC9 EFT RSP-30, craftable) up at open sky. A while later a plane passes over and a supply
	crate comes down near where you fired it, trailing red smoke. It's searched like any container (Q) and holds
	far better loot than anything on the ground: military guns, armor, good meds, attachments.
	You won't be the only one who saw it:
		- the crash of it landing draws in every zombie within earshot
		- sometimes a horde follows the plane in
		- sometimes bandits head for it to take it first; if they get to it before you, they clean it out
	One drop at a time, and a cooldown before the next flare is answered (gfr_airdrop_*).
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled  = CreateConVar("gfr_airdrop_enabled", "1", flags, "Signal flares fired at the sky call in a supply drop")
local cvCooldown = CreateConVar("gfr_airdrop_cooldown", "900", flags, "Seconds before another flare is answered")
local cvDelay    = CreateConVar("gfr_airdrop_delay", "45", flags, "Average seconds between the flare and the drop")
local cvHorde    = CreateConVar("gfr_airdrop_horde", "45", flags, "% chance a zombie horde comes for the drop")
local cvBandits  = CreateConVar("gfr_airdrop_bandits", "35", flags, "% chance bandits come to take the drop")
local cvLife     = CreateConVar("gfr_airdrop_life", "900", flags, "Seconds an unsearched drop stays before it's gone")

-- First one installed is used: a plain wooden crate from the base game, so everyone has it (the old care package came
-- from an unrelated content pack)
local CRATE_MODELS = {"models/props_junk/wood_crate001a.mdl", "models/props_junk/wood_crate002a.mdl", "models/items/item_item_crate.mdl"}
local PLANE_SOUNDS = {"ambient/overhead/plane1.wav", "ambient/overhead/hel1.wav", "ambient/overhead/hel2.wav", "ambient/levels/streetwar/heli_distant1.wav"}

local nextDrop = 0
local active -- the drop currently in the world

---------------------------------------------------------------------------------------------------------------------------------------------
-- What's in the crate: a real supply drop, not a lucky dip
--   a gun (mostly military rifles) and 3-4 boxes of the ammo it takes
--   2-3 tins of food and 2 waters
--   a grenade (or molotov), a good med, and one of: armour / a rare med / another grenade
--   1-2 weapon attachments, and gunpowder or gun parts
local function Add(list, class) if class then list[#list + 1] = class end end

function GFR.AirdropLoot(ply)
	local L = GFR.Loot
	local found = {}
	if !L then return found end

	local gun
	for _ = 1, 10 do
		local c = L.PickItem(L.PickPool({gun_military = 55, gun_rifle = 20, gun_smg = 15, gun_shotgun = 10}))
		if c && weapons.GetStored(c) && L.AmmoItemFor(c) then gun = c break end
	end
	if gun then
		Add(found, gun)
		for _ = 1, math.random(3, 4) do Add(found, L.AmmoItemFor(gun)) end
	end

	for _ = 1, math.random(2, 3) do Add(found, L.PickItem("packaged")) end
	for _ = 1, 2 do Add(found, scripted_ents.GetStored("gfr_s2_water") and "gfr_s2_water" or L.PickItem("drink")) end

	Add(found, L.PickItem("grenade"))
	Add(found, L.PickItem("meds_good"))
	Add(found, L.PickItem(L.PickPool({armor = 35, meds_rare = 35, grenade = 30})))

	if GFR.RandomAttachment && GetConVar("gfr_arc9_found") && GetConVar("gfr_arc9_found"):GetBool() then
		for _ = 1, math.random(1, 2) do
			local att = GFR.RandomAttachment(ply)
			if att then Add(found, "att:" .. att) end
		end
	end
	local mats = {"gfr_mat_gunpowder", "gfr_mat_gunpowder", "gfr_mat_parts"}
	Add(found, mats[math.random(#mats)])
	return found
end

local function SoundThatExists(list)
	for _, s in ipairs(list) do
		if file.Exists("sound/" .. s, "GAME") then return s end
	end
end

local function OpenSky(pos)
	local tr = util.TraceLine({start = pos + Vector(0, 0, 8), endpos = pos + Vector(0, 0, 8000), mask = MASK_SOLID_BRUSHONLY})
	return tr.HitSky, tr.HitPos
end

-- Close to where the flare went up, with open sky above and solid ground below (spreading out if it has to)
local function FindDropSpot(origin)
	local why = {nosky = 0, startsolid = 0, noground = 0, steep = 0, water = 0, skyabove = 0}
	for i = 1, 50 do
		local dist = i == 1 and 0 or i < 25 and math.Rand(0, 400) or math.Rand(400, 1200)
		local ang = math.Rand(0, math.pi * 2)
		local xy = origin + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 0)
		-- Measure the sky above this spot first, then come down from just under it: a fixed height above you can
		-- already be inside/above the skybox on maps with a low sky (every trace failed there)
		local up = util.TraceLine({start = xy + Vector(0, 0, 40), endpos = xy + Vector(0, 0, 10000), mask = MASK_SOLID_BRUSHONLY})
		if up.StartSolid then
			why.startsolid = why.startsolid + 1
		elseif !up.HitSky then
			why.nosky = why.nosky + 1
		else
			local top = up.HitPos - Vector(0, 0, 16)
			local down = util.TraceLine({start = top, endpos = top - Vector(0, 0, 6000), mask = MASK_SOLID_BRUSHONLY})
			if !down.Hit or down.StartSolid or down.HitSky then
				why.noground = why.noground + 1
			elseif down.HitNormal.z <= 0.6 then
				why.steep = why.steep + 1
			elseif bit.band(util.PointContents(down.HitPos + Vector(0, 0, 8)), CONTENTS_WATER) != 0 then
				why.water = why.water + 1
			else
				local sky, skyPos = OpenSky(down.HitPos)
				if sky then return down.HitPos, skyPos end
				why.skyabove = why.skyabove + 1
			end
		end
	end
	print(string.format("[GFR] Airdrop: no landing spot near %s. Rejected: start in solid %d, no sky above %d, no ground %d, too steep %d, water %d, roof over ground %d",
		tostring(origin), why.startsolid, why.nosky, why.noground, why.steep, why.water, why.skyabove))
	-- The flare had open sky over it: drop it right there, onto whatever's under where it was fired
	local down = util.TraceLine({start = origin + Vector(0, 0, 20), endpos = origin - Vector(0, 0, 4000), mask = MASK_SOLID, filter = player.GetAll()})
	if down.Hit && !down.StartSolid then
		local _, skyPos = OpenSky(down.HitPos)
		return down.HitPos, skyPos
	end
end

local function Smoke(parent, pos, duration)
	local s = ents.Create("env_smokestack")
	if !IsValid(s) then return end
	s:SetPos(pos)
	s:SetKeyValue("InitialState", "1")
	s:SetKeyValue("BaseSpread", "12")
	s:SetKeyValue("SpreadSpeed", "18")
	s:SetKeyValue("Speed", "90")
	s:SetKeyValue("StartSize", "30")
	s:SetKeyValue("EndSize", "90")
	s:SetKeyValue("Rate", "24")
	s:SetKeyValue("JetLength", "420")
	s:SetKeyValue("rendercolor", "210 45 40")
	s:SetKeyValue("renderamt", "220")
	s:SetKeyValue("SmokeMaterial", "particle/SmokeStack.vmt")
	s:Spawn()
	s:Activate()
	if IsValid(parent) then
		s:SetParent(parent)
		parent:DeleteOnRemove(s)
	end
	timer.Simple(duration, function() if IsValid(s) then s:Remove() end end)
	return s
end

local function NotifyAll(msg)
	for _, ply in ipairs(player.GetAll()) do GFR.Notify(ply, msg) end
end

-- Send an NPC running to a spot (VJ NPCs have their own move order)
local function SendTo(npc, pos)
	if !IsValid(npc) or npc:Health() <= 0 then return end
	if IsValid(npc:GetEnemy()) then return end -- busy fighting
	if npc.GFR_Group then npc.GFR_Group.noWanderT = CurTime() + 15 end -- (heading for the drop, not scavenging: sv_groupwander.lua)
	npc:SetLastPosition(pos + VectorRand() * 60 * Vector(1, 1, 0))
	if npc.SCHEDULE_GOTO_POSITION then
		npc:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH")
	else
		npc:SetSchedule(SCHED_FORCED_GO_RUN)
	end
end

local function SpotAround(pos, minD, maxD)
	local cands = GFR.Loot && GFR.Loot.GetCandidates && GFR.Loot.GetCandidates() or {}
	local near = {}
	for _, c in ipairs(cands) do
		local d = c:Distance(pos)
		if d > minD && d < maxD then near[#near + 1] = c end
	end
	for _ = 1, 10 do
		local c = #near > 0 and near[math.random(#near)] or (pos + VectorRand() * maxD * Vector(1, 1, 0))
		local g = GFR.Loot && GFR.Loot.GroundSpot && GFR.Loot.GroundSpot(c)
		if g && !(GFR.InClaim && GFR.InClaim(g, 250)) then return g end -- (no horde/bandits spawning inside a base)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Threats drawn to the drop
local function Attract(drop)
	local pos = drop.pos
	-- The noise: zombies in earshot come to look
	local n = 0
	for _, ent in ipairs(ents.FindInSphere(pos, 2600)) do
		if ent:IsNPC() && GFR.IsZombie && GFR.IsZombie(ent) then
			SendTo(ent, pos)
			n = n + 1
		end
	end

	-- A horde followed the plane in
	if math.random(100) <= cvHorde:GetFloat() && GFR.Spawner then
		local count = math.random(6, 12) + (GFR.IsNight && GFR.IsNight() and 4 or 0)
		local made = {}
		for _ = 1, count do
			local spot = SpotAround(pos, 900, 2000)
			local z = spot && GFR.Spawner.SpawnZombie(spot + Vector(0, 0, 4))
			if IsValid(z) then made[#made + 1] = z end
		end
		drop.horde = made
		if #made > 0 then timer.Simple(3, function() NotifyAll("The dead heard it come down. Lots of them.") end) end
	end

	-- Bandits want it too
	if math.random(100) <= cvBandits:GetFloat() && GFR.Spawner then
		local spot = SpotAround(pos, 1200, 2600)
		local g = spot && GFR.Spawner.SpawnGroup("bandit", spot, {size = math.random(3, 5), keep = true})
		if g then
			drop.bandits = g
			timer.Simple(6, function() NotifyAll("Voices in the distance... someone else is heading for the drop.") end)
		end
	end

	-- Keep them all heading there for a while (they get distracted)
	local id = "GFR_Airdrop_Attract"
	local runs = 0
	timer.Create(id, 6, 20, function()
		runs = runs + 1
		if !IsValid(drop.crate) then timer.Remove(id) return end
		for _, z in ipairs(drop.horde or {}) do SendTo(z, pos) end
		if drop.bandits then
			for _, m in ipairs(drop.bandits.members or {}) do SendTo(m, pos) end
		end
		if runs <= 3 then
			for _, ent in ipairs(ents.FindInSphere(pos, 2000)) do
				if ent:IsNPC() && GFR.IsZombie && GFR.IsZombie(ent) && !(GFR.ZombieResting && GFR.ZombieResting(ent)) && !ent.GFR_ControlPlayer then SendTo(ent, pos) end
			end
		end
	end)
end

-- Bandits standing at the crate with no one to stop them take everything
local function BanditCheck(drop)
	local crate = drop.crate
	if !drop.bandits or !IsValid(crate) or crate.GFR_SearchedAt then return end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() && ply:GetPos():DistToSqr(crate:GetPos()) < 500 * 500 then drop.banditTime = 0 return end
	end
	local near = false
	for _, m in ipairs(drop.bandits.members or {}) do
		if IsValid(m) && m:Health() > 0 && m:GetPos():DistToSqr(crate:GetPos()) < 140 * 140 then near = true break end
	end
	if !near then return end
	drop.banditTime = (drop.banditTime or 0) + 1
	if drop.banditTime >= 10 then
		crate.GFR_SearchedUntil = CurTime() + 99999
		crate.GFR_SearchedAt = CurTime()
		crate:SetNW2Bool("GFR_Searched", true)
		crate:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav", 80)
		NotifyAll("Bandits got to the supply drop first and stripped it bare.")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- The care package's parachute (bodygroup "Parachute": 0 = open, the last option = none)
local function Parachute(crate, open)
	local id = crate:FindBodygroupByName("Parachute")
	if id < 0 then return end
	crate:SetBodygroup(id, open and 0 or math.max(crate:GetBodygroupCount(id) - 1, 0))
end

local function Land(drop)
	local crate = drop.crate
	if !IsValid(crate) then return end
	Parachute(crate, false)
	local phys = crate:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	crate:SetNW2String("GFR_CType", "airdrop")
	crate.GFR_Airdrop = true
	crate:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 100, 80)
	util.ScreenShake(crate:GetPos(), 6, 5, 1, 900)
	local fx = EffectData()
	fx:SetOrigin(crate:GetPos())
	fx:SetScale(3)
	util.Effect("ThumperDust", fx)
	drop.pos = crate:GetPos()
	drop.landedAt = CurTime()
	Smoke(crate, crate:GetPos() + Vector(0, 0, 30), 120)
	Attract(drop)
	NotifyAll("The supply drop has landed. Look for the red smoke.")
end

local function DropCrate(drop)
	local mdl
	for _, m in ipairs(CRATE_MODELS) do if util.IsValidModel(m) then mdl = m break end end
	local crate = ents.Create("prop_physics")
	if !IsValid(crate) then return end
	crate:SetModel(mdl)
	local startZ = math.max(math.min(drop.skyPos.z - 120, drop.ground.z + 3500), drop.ground.z + 80) -- (never under a low sky's floor)
	crate:SetPos(Vector(drop.ground.x, drop.ground.y, startZ))
	crate:SetAngles(Angle(0, math.random(0, 359), 0))
	crate:Spawn()
	crate:Activate()
	Parachute(crate, true)
	crate.GFR_Stash = nil
	drop.crate = crate
	active = drop
	Smoke(crate, crate:GetPos(), 600)

	-- Slow parachute fall: no gravity, a steady sink; it lands when it stops coming down
	local phys = crate:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableGravity(false)
		phys:Wake()
	end
	local lastZ, still = crate:GetPos().z, 0
	local id = "GFR_Airdrop_Fall"
	timer.Create(id, 0.1, 0, function()
		if !IsValid(crate) then timer.Remove(id) return end
		local p = crate:GetPhysicsObject()
		if IsValid(p) then
			p:SetVelocity(Vector(math.sin(CurTime()) * 15, math.cos(CurTime() * 0.7) * 15, -260))
			p:SetAngleVelocity(Vector(0, 0, 0))
		end
		local z = crate:GetPos().z
		if lastZ - z < 2 then still = still + 1 else still = 0 end
		lastZ = z
		if still >= 4 or z <= drop.ground.z + 2 then
			timer.Remove(id)
			if IsValid(p) then p:EnableGravity(true) end
			Land(drop)
		end
	end)
end

local function CallDrop(ply, origin)
	local ground, skyPos = FindDropSpot(origin)
	if !ground then
		GFR.Notify(ply, "No answer. Nowhere out here a plane could drop anything.")
		return
	end
	nextDrop = CurTime() + cvCooldown:GetFloat()
	local drop = {ground = ground, skyPos = skyPos, caller = ply}
	active = drop
	local delay = math.max(cvDelay:GetFloat() * math.Rand(0.7, 1.3), 5)
	GFR.Notify(ply, "Your flare burns in the sky. If anyone's still flying, they've seen it.")
	print(string.format("[GFR] Airdrop called by %s, landing at %s in %.0fs", ply:Nick(), tostring(ground), delay))
	timer.Simple(delay - 4, function()
		local s = SoundThatExists(PLANE_SOUNDS)
		for _, p in ipairs(player.GetAll()) do
			if s then p:EmitSound(s, 75, 90) end
			GFR.Notify(p, "An engine drones overhead...")
		end
	end)
	timer.Simple(delay, function() DropCrate(drop) end)
end

-- A flare leaves the launcher. Follow it: once it's climbed high under open sky, someone answers,
-- and the drop comes down around the spot under the flare.
local CLIMB = 700 -- how far above the launch point it has to get to be seen

local function FlareOwner(ent)
	local ply = ent:GetOwner()
	if !IsValid(ply) then ply = ent.Owner end
	return IsValid(ply) && ply:IsPlayer() and ply or nil
end

local function Answer(ply, flare)
	if active && (IsValid(active.crate) or !active.landedAt) then
		GFR.Notify(ply, "There's already a drop on its way or waiting out there.")
		return
	end
	if CurTime() < nextDrop then
		GFR.Notify(ply, "No one answers. Try again later. (" .. math.ceil((nextDrop - CurTime()) / 60) .. " min)")
		return
	end
	CallDrop(ply, flare)
end

local function WatchFlare(ent)
	local ply = FlareOwner(ent)
	if !IsValid(ent) or !ply then return end
	local start = ent:GetPos()
	local peak, answered = start.z, false
	local id = "GFR_Airdrop_Flare" .. ent:EntIndex()
	timer.Create(id, 0.2, 100, function()
		if answered then timer.Remove(id) return end
		local gone = !IsValid(ent)
		local pos = !gone and ent:GetPos()
		if pos then peak = math.max(peak, pos.z) end
		-- High enough with sky above it (or right up against a low skybox)
		local sky, skyPos = false, nil
		if pos then sky, skyPos = OpenSky(pos) end
		if sky && (peak - start.z >= CLIMB or skyPos.z - pos.z < 300) then
			answered = true
			timer.Remove(id)
			Answer(ply, Vector(pos.x, pos.y, start.z))
			return
		end
		-- Burned out, or fell back without getting up there
		if gone or (pos && pos.z < peak - 200) or timer.RepsLeft(id) == 0 then
			timer.Remove(id)
			if IsValid(ply) then GFR.Notify(ply, "Fire the flare up at open sky to signal for a supply drop.") end
		end
	end)
end

hook.Add("OnEntityCreated", "GFR_Airdrop_Flare", function(ent)
	if !cvEnabled:GetBool() then return end
	local class = ent:GetClass()
	if !string.StartWith(class, "arc9_eft_26x75_") or string.find(class, "firework", 1, true) then return end
	-- The owner is set right after it's created; give it a moment
	timer.Simple(0.05, function() if IsValid(ent) then WatchFlare(ent) end end)
end)

-- Bandit looting, and clearing the crate away once it's done
timer.Create("GFR_Airdrop_Tick", 1, 0, function()
	local drop = active
	if !drop or !drop.landedAt then return end
	local crate = drop.crate
	if !IsValid(crate) then active = nil return end
	BanditCheck(drop)
	local done = crate.GFR_SearchedAt && CurTime() - crate.GFR_SearchedAt > 180
	local expired = CurTime() - drop.landedAt > cvLife:GetFloat()
	if done or expired then
		local nearby = false
		for _, ply in ipairs(player.GetAll()) do
			if ply:GetPos():DistToSqr(crate:GetPos()) < 900 * 900 then nearby = true break end
		end
		if !nearby then
			crate:Remove()
			active = nil
		end
	end
end)

hook.Add("PostCleanupMap", "GFR_Airdrop_Cleanup", function()
	active = nil
	timer.Remove("GFR_Airdrop_Fall")
	timer.Remove("GFR_Airdrop_Attract")
end)

-- Testing: gfr_airdrop calls one in where you stand, ignoring the cooldown
concommand.Add("gfr_airdrop", function(ply)
	if !IsValid(ply) or !GFR.CanCheat(ply) then return end
	active = nil
	nextDrop = 0
	CallDrop(ply, ply:GetPos())
end)
