--[[
	Custom Apocalypse - the dead out in the world
	Bodies rot: a few minutes after death a body starts to decay (darkens, flies buzz around it) and the smell
	draws nearby zombies to it (they come to feed). Later it's gone. (gfr_body_*)
	Zombies roam: an idle zombie doesn't stand on one spot forever, every so often it shambles off somewhere
	else nearby, so the streets shift around you. (gfr_zombie_roam*)
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvDecay   = CreateConVar("gfr_body_decay", "180", flags, "Seconds after death before a body starts to rot and smell")
local cvRemove  = CreateConVar("gfr_body_remove", "420", flags, "Seconds after death before a rotting body is gone (0 = never)")
local cvRemoveZ = CreateConVar("gfr_body_remove_dead", "150", flags, "Seconds before a zombie corpse that won't get back up (head destroyed) is gone")
local cvMaxBodies = CreateConVar("gfr_body_max", "20", flags, "Most bodies kept in the world; the oldest go first")
-- (old configs had 720: bring it down once)
if cookie.GetString("gfr_body_remove_v2") != "1" then
	cookie.Set("gfr_body_remove_v2", "1")
	timer.Simple(0, function() if cvRemove:GetInt() == 720 then RunConsoleCommand("gfr_body_remove", "420") end end)
end
local cvSmell   = CreateConVar("gfr_body_smell_range", "1500", flags, "How far zombies smell a rotting body")
local cvRoam    = CreateConVar("gfr_zombie_roam", "1", flags, "Idle zombies wander around instead of standing in one place")
local cvRoamMin = CreateConVar("gfr_zombie_roam_min", "20", flags, "Fewest seconds an idle zombie stays before moving on")
local cvRoamMax = CreateConVar("gfr_zombie_roam_max", "70", flags, "Most seconds an idle zombie stays before moving on")

---------------------------------------------------------------------------------------------------------------------------------------------
-- Rotting bodies
local bodies = {} -- [ragdoll] = time of death

hook.Add("OnEntityCreated", "GFR_Decay_Track", function(ent)
	if ent:GetClass() != "prop_ragdoll" then return end
	timer.Simple(0.5, function()
		-- Whole bodies only (not severed limbs or map decoration)
		if !IsValid(ent) or ent.GFR_Decor or !ent:LookupBone("ValveBiped.Bip01_Pelvis") then return end
		bodies[ent] = CurTime()
	end)
end)

local function Visual(body)
	return IsValid(body.Bonemerge) and body.Bonemerge or body
end

-- Zombies with nothing better to do come to the smell
-- Sitting / lying down to rest (L4D infected): left alone. Moving it makes it stand straight back up.
function GFR.ZombieResting(z)
	return (z.Zombie_IdleState or 0) != 0
end

local function SendTo(z, pos)
	if !IsValid(z) or z:Health() <= 0 or IsValid(z:GetEnemy()) or z.VJ_ST_Eating or z.GOTDR_CurEnt or z.GFR_ScriptFeed or GFR.ZombieResting(z) then return end
	if z.VJ_IsBeingControlled or z.GFR_ControlPlayer then return end -- (yours: you decide where it goes)
	z:SetLastPosition(pos + VectorRand() * 50 * Vector(1, 1, 0))
	if z.SCHEDULE_GOTO_POSITION then z:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH") else z:SetSchedule(SCHED_FORCED_GO) end
	z.GFR_NextRoam = CurTime() + 40
end

-- VJ marks a body "being eaten" when a zombie starts on it and often never unmarks it when that zombie wanders off:
-- only count it if someone is really at it
local function ReallyBeingEaten(body)
	if body.GFR_EatenBy && IsValid(body.GFR_EatenBy) then return true end
	if !body.VJ_ST_BeingEaten then return false end
	for _, z in ipairs(ents.FindInSphere(body:GetPos(), 150)) do
		if z:IsNPC() && z.VJ_ST_Eating && z.EatingData && z.EatingData.Target == body then return true end
	end
	body.VJ_ST_BeingEaten = nil
	return false
end

local function Seen(body)
	for _, ply in ipairs(player.GetAll()) do
		local d = ply:GetPos():DistToSqr(body:GetPos())
		if d < 500 * 500 then return true end
		if d < 2500 * 2500 && ply:GetAimVector():Dot((body:GetPos() - ply:EyePos()):GetNormalized()) > 0.6
			&& !util.TraceLine({start = ply:EyePos(), endpos = body:WorldSpaceCenter(), mask = MASK_VISIBLE}).Hit then return true end
	end
	return false
end

local function RemoveBody(body)
	bodies[body] = nil
	local fx = EffectData()
	fx:SetOrigin(body:WorldSpaceCenter())
	util.Effect("BloodImpact", fx)
	body:Remove()
end

-- Clearing out: zombie corpses that are done (head destroyed / burned) go soonest, anything past its time goes once
-- nobody's looking right at it, and past gfr_body_max the oldest go first
timer.Create("GFR_Body_Cleanup", 3, 0, function()
	local now = CurTime()
	local list = {}
	for body, died in pairs(bodies) do
		if !IsValid(body) then bodies[body] = nil continue end
		if body.GFR_DraggedBy or body.GFR_TurningBody or IsValid(body.GFR_PlayerBody) or ReallyBeingEaten(body) then continue end
		local age = now - died
		local done = body.GFR_ZCorpse && body.GFR_HeadGone -- (a zombie corpse that won't get up)
		local limit = done and cvRemoveZ:GetFloat() or cvRemove:GetFloat()
		if limit > 0 && age >= limit && !Seen(body) then
			RemoveBody(body)
		else
			list[#list + 1] = {body, died}
		end
	end
	local max = cvMaxBodies:GetInt()
	if max > 0 && #list > max then
		table.sort(list, function(a, b) return a[2] < b[2] end)
		for i = 1, #list - max do
			local body = list[i][1]
			if IsValid(body) && !Seen(body) then RemoveBody(body) end
		end
	end
end)

timer.Create("GFR_Decay_Tick", 5, 0, function()
	local now = CurTime()
	local decay, remove = cvDecay:GetFloat(), cvRemove:GetFloat()
	for body, died in pairs(bodies) do
		if !IsValid(body) then bodies[body] = nil continue end
		local age = now - died
		if age < decay then continue end

		if !body.GFR_Rotting then
			body.GFR_Rotting = true
			body.GFR_NextSmell = now
		end
		-- Darker and greyer the longer it lies there
		local f = math.Clamp((age - decay) / math.max(remove - decay, 60), 0, 1)
		local vis = Visual(body)
		if IsValid(vis) then
			local base = vis.GFR_OrgColor or vis:GetColor()
			vis.GFR_OrgColor = base
			vis:SetColor(Color(base.r * (1 - 0.55 * f), base.g * (1 - 0.5 * f), base.b * (1 - 0.6 * f), base.a))
		end
		if math.random(100) <= 45 then
			sound.Play("ambient/creatures/flies" .. math.random(1, 5) .. ".wav", body:WorldSpaceCenter(), 58, math.random(90, 110), 0.6)
		end
		-- The smell carries
		if now >= (body.GFR_NextSmell or 0) then
			body.GFR_NextSmell = now + 25
			local pos = body:GetPos()
			local n = 0
			for _, ent in ipairs(ents.FindInSphere(pos, cvSmell:GetFloat())) do
				if ent:IsNPC() && GFR.IsZombie && GFR.IsZombie(ent) && math.random(100) <= 60 then
					SendTo(ent, pos)
					n = n + 1
					if n >= 4 then break end
				end
			end
		end
		-- (removal: GFR_Body_Cleanup above)
	end
end)

hook.Add("PostCleanupMap", "GFR_Decay_Cleanup", function() bodies = {} end)

-- Zombies find food by smell (VJ's SOUND_CARCASS hints), but only VJ's own corpses give one off: people's bodies
-- (survivors, bandits, soldiers) never did, so nothing ate them. Every edible body smells; a rotting one carries further.
local function Edible(body)
	return !body.GFR_ZCorpse && !body.GFR_TurningBody && !IsValid(body.GFR_PlayerBody) && !body.GFR_ParasiteClaimed && !body.GFR_DraggedBy
		&& !body.GFR_Burned
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Burning bodies: a molotov's fire (or any fire, a burn barrel, fire damage) sets a body alight. It chars, then burns
-- away to nothing. A burned body never gets back up, can't be butchered, isn't eaten and stops smelling.
local cvBurnTime = CreateConVar("gfr_body_burn_time", "22", flags, "Seconds a burning body takes to burn away")

local function BurnBody(rag)
	if !IsValid(rag) or rag.GFR_Burned or rag:GetClass() != "prop_ragdoll" or !rag:LookupBone("ValveBiped.Bip01_Pelvis") then return end
	rag.GFR_Burned = true
	rag:SetNW2Bool("GFR_Burned", true)
	rag.GFR_HeadGone = true -- it won't get back up (sv_rise.lua, a turning body: sv_infection.lua, your own: sv_extract.lua)
	local t = cvBurnTime:GetFloat()
	rag:Ignite(t + 2)
	sound.Play("ambient/fire/ignite.wav", rag:WorldSpaceCenter(), 70)
	timer.Simple(math.min(6, t * 0.3), function()
		local vis = IsValid(rag) && (IsValid(rag.Bonemerge) and rag.Bonemerge or rag)
		if IsValid(vis) then vis:SetColor(Color(45, 38, 34, vis:GetColor().a)) end
	end)
	timer.Simple(t, function()
		if !IsValid(rag) then return end
		local fx = EffectData()
		fx:SetOrigin(rag:WorldSpaceCenter())
		fx:SetScale(2)
		util.Effect("ThumperDust", fx)
		rag:Remove()
	end)
end
GFR.BurnBody = BurnBody

-- Fire damage
hook.Add("EntityTakeDamage", "GFR_Body_BurnDamage", function(ent, dmg)
	if ent:GetClass() == "prop_ragdoll" && bit.band(dmg:GetDamageType(), bit.bor(DMG_BURN, DMG_SLOWBURN)) != 0 then BurnBody(ent) end
end)

-- Bodies lying in fire: molotov / incendiary fire pools (MW2019), vFire, env_fire (burn barrels: drag a body onto one)
local fireSources = {arc9_cod2019_fire_pool = 150, vfire = 90, vfire_ball = 60, env_fire = 60, entityflame = 40}
timer.Create("GFR_Body_FireCheck", 0.5, 0, function()
	for class, radius in pairs(fireSources) do
		for _, fire in ipairs(ents.FindByClass(class)) do
			local owner = class == "entityflame" && fire:GetParent()
			if owner && IsValid(owner) && owner:GetClass() == "prop_ragdoll" then continue end -- (a body's own flames don't spread it)
			for _, rag in ipairs(ents.FindInSphere(fire:GetPos(), radius)) do
				if rag:GetClass() == "prop_ragdoll" && !rag.GFR_Burned then BurnBody(rag) end
			end
		end
	end
end)

timer.Create("GFR_Body_Smell", 2, 0, function()
	for body in pairs(bodies) do
		if IsValid(body) && Edible(body) then
			sound.EmitHint(SOUND_CARCASS, body:GetPos(), body.GFR_Rotting and 1100 or 700, 2.5, body)
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Roaming
local roamers = {npc_gfr_infected = true, npc_vj_rtrg_zombie = true, npc_vj_rtrg_zombie_pm = true, npc_vj_l4d2_boomer = true, npc_vj_l4d2_boomette = true}

local function RoamSpot(from)
	local cands = GFR.Loot && GFR.Loot.GetCandidates && GFR.Loot.GetCandidates() or {}
	local near = {}
	for i = 1, math.min(#cands, 400) do
		local c = cands[math.random(#cands)]
		local d = c:Distance(from)
		if d > 300 && d < 1500 && !(GFR.InClaim && GFR.InClaim(c)) then near[#near + 1] = c end -- (not into a claimed base)
		if #near >= 12 then break end
	end
	if #near > 0 then return near[math.random(#near)] end
	-- No spot list: somewhere on the ground in a random direction
	for _ = 1, 8 do
		local ang = math.Rand(0, math.pi * 2)
		local d = math.Rand(300, 900)
		local p = from + Vector(math.cos(ang) * d, math.sin(ang) * d, 60)
		local tr = util.TraceLine({start = p, endpos = p - Vector(0, 0, 300), mask = MASK_SOLID_BRUSHONLY})
		if tr.Hit && !tr.StartSolid && tr.HitNormal.z > 0.7 && !(GFR.InClaim && GFR.InClaim(tr.HitPos)) then return tr.HitPos end
	end
end

local function Idle(z)
	if z:Health() <= 0 or z.Dead or IsValid(z:GetEnemy()) or z.Alerted or z.VJ_ST_Eating or z.GOTDR_CurEnt or z:IsMoving() then return false end
	if z.VJ_IsBeingControlled or z.GFR_ControlPlayer then return false end
	if z.GetState && z:GetState() != VJ_STATE_NONE then return false end
	if z.Zombie_IdleState && z.Zombie_IdleState != 0 then return false end -- sitting / lying (L4D): they get up on their own
	return true
end

timer.Create("GFR_Zombie_Roam", 3, 0, function()
	if !cvRoam:GetBool() then return end
	local now = CurTime()
	for _, z in ipairs(ents.GetAll()) do
		if !roamers[z:GetClass()] or !IsValid(z) then continue end
		if !z.GFR_NextRoam then z.GFR_NextRoam = now + math.Rand(cvRoamMin:GetFloat(), cvRoamMax:GetFloat()) continue end
		if now < z.GFR_NextRoam or !Idle(z) then continue end
		z.GFR_NextRoam = now + math.Rand(cvRoamMin:GetFloat(), cvRoamMax:GetFloat())
		local spot = RoamSpot(z:GetPos())
		if spot && z.SCHEDULE_GOTO_POSITION then
			z:SetLastPosition(spot)
			z:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH")
		end
	end
end)
