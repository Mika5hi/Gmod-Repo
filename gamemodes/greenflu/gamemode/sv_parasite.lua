--[[
	Custom Apocalypse - bloaters (boomers), and raising bodies
	(The parasites that used to live here are gone; the file keeps its name so nothing that loads it changes.)

	Bloaters: the L4D2 Boomer / Boomette ([Left 4 Dead 1-2 Special Infected SNPCs]). Its puke is what makes it dangerous:
	every time it covers you, the sickness gets into you - a big dose of infection (gfr_boomer_infect). Caught in the
	burst when one dies, a smaller one (gfr_boomer_burst_infect). That's on top of the pack's own puke (blinded, the
	horde comes for you). Works for any boomer, the spawned ones and ones from the spawn menu.

	GFR.ReanimateCorpse: a body getting back up as one of them (sv_rise.lua).
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvBloater      = CreateConVar("gfr_bloater_chance", "3", flags, "% of zombies spawned by day that are bloaters")
local cvBloaterNight = CreateConVar("gfr_bloater_night_chance", "6", flags, "% of zombies spawned at night that are bloaters")
local cvPukeInfect   = CreateConVar("gfr_boomer_infect", "15", flags, "Infection % a boomer's puke adds each time it covers you")
local cvBurstInfect  = CreateConVar("gfr_boomer_burst_infect", "8", flags, "Infection % being caught in a dying boomer's burst adds")

local bloaterClasses = {"npc_vj_l4d2_boomer", "npc_vj_l4d2_boomer", "npc_vj_l4d2_boomette"}
local isBloater = {npc_vj_l4d2_boomer = true, npc_vj_l4d2_boomette = true, npc_vj_l4d_boomer = true}

-- A random boomer/boomette class, or nil if the pack isn't installed
function GFR.BloaterClass()
	local ok = {}
	for _, c in ipairs(bloaterClasses) do if scripted_ents.GetStored(c) then ok[#ok + 1] = c end end
	return ok[math.random(math.max(#ok, 1))]
end

-- Should this spawn be a bloater? (sv_spawner.lua)
function GFR.RollBloater()
	if !GFR.BloaterClass() then return false end
	local chance = (GFR.IsNight && GFR.IsNight()) and cvBloaterNight:GetFloat() or cvBloater:GetFloat()
	return math.Rand(0, 100) < chance
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Puke carries the infection. The pack calls VomitEnemy(victim, fromBurst) for everyone its puke lands on, over and
-- over while they stand in it - the dose is given once per covering (it keeps its own list of who's covered).
local function PukeInfects(z)
	if !IsValid(z) or z.GFR_PukeWrapped or !z.VomitEnemy then return end
	z.GFR_PukeWrapped = true
	local orig = z.VomitEnemy
	z.VomitEnemy = function(self, v, bDeath, ...)
		local fresh = IsValid(v) && v:IsPlayer() && !(self.tblPukedVictims && table.HasValue(self.tblPukedVictims, v))
		local ret = orig(self, v, bDeath, ...)
		-- (covered now: the pack only adds people it's hostile to)
		if fresh && v:Alive() && !v.GFR_IsZombie && self.tblPukedVictims && table.HasValue(self.tblPukedVictims, v) && GFR.Infect then
			local amount = bDeath and cvBurstInfect:GetFloat() or cvPukeInfect:GetFloat()
			if amount > 0 then
				GFR.Infect(v, amount)
				GFR.Notify(v, bDeath and "Its burst soaks you. You can taste it..." or "You're covered in its bile. It's in your mouth, your eyes...")
			end
		end
		return ret
	end
end

-- After Spawn (sv_spawner.lua): mark it a bloater
function GFR.SetupSpawnedBloater(z)
	if !IsValid(z) then return end
	z.GFR_Bloater = true -- (stays dead: sv_rise.lua)
	PukeInfects(z)
end

-- Any boomer, however it got here
hook.Add("OnEntityCreated", "GFR_Bloater_Puke", function(ent)
	if !isBloater[ent:GetClass()] then return end
	timer.Simple(0, function()
		if !IsValid(ent) then return end
		ent.GFR_Bloater = true
		PukeInfects(ent)
	end)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Raising a body as one of them (sv_rise.lua)
local function Gore(pos)
	if GFR.Gore && !GFR.Gore() then return end
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetScale(5)
	fx:SetFlags(3)
	fx:SetColor(0)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	sound.Play("physics/flesh/flesh_bloody_break.wav", pos, 75, math.random(90, 110))
end

local function CorpseLook(corpse)
	local body = corpse.Bonemerge
	if !IsValid(body) then
		for _, c in ipairs(corpse:GetChildren()) do
			if IsValid(c) && c:GetModel() && c:LookupBone("ValveBiped.Bip01_Pelvis") then body = c break end
		end
	end
	if !IsValid(body) && corpse:LookupBone("ValveBiped.Bip01_Pelvis") && !string.find(corpse:GetModel() or "", "vj_gotdr", 1, true) then body = corpse end
	if !IsValid(body) then return end
	local look = {model = body:GetModel(), skin = body:GetSkin(), bodygroups = {}}
	for i = 0, body:GetNumBodyGroups() - 1 do look.bodygroups[i] = body:GetBodygroup(i) end
	return look
end

-- Raise a body as a zombie wearing it. opts: runner, gore (burst of blood), lieTime (seconds on the ground before
-- getting up), rises, legGone / armsGone (what it lost)
local function Reanimate(corpse, opts)
	if !IsValid(corpse) or !scripted_ents.GetStored(GFR.InfectedClass()) then return end
	opts = opts or {}
	local look = CorpseLook(corpse)
	local pos, yaw = corpse:GetPos(), corpse:GetAngles().y
	if opts.gore then Gore(corpse:WorldSpaceCenter()) end
	corpse:Remove()

	local z = ents.Create(GFR.InfectedClass())
	z:SetPos(pos + Vector(0, 0, 4))
	z:SetAngles(Angle(0, yaw, 0))
	if look then
		z.GFR_ForceModel = look.model
		z.GFR_ForceSkin = look.skin
		z.GFR_ForceBodygroups = look.bodygroups
	end
	if opts.runner then z.RTRG_ForceRunner = true end
	z.GFR_Rises = opts.rises
	z:Spawn()
	z:Activate()
	if GFR.TrackZombie then GFR.TrackZombie(z) end
	-- Lost an arm (or both) before / after it went down: it gets back up without them (sv_rise.lua)
	if opts.armsGone && z.GFR_LoseArm then
		for hg in pairs(opts.armsGone) do z:GFR_LoseArm(hg, true) end
	end
	-- Lost a leg before it went down: it gets back up as a crawler (no standing up)
	if opts.legGone && z.RTRG_LoseLeg then
		z:RTRG_LoseLeg(opts.legGone, true)
		if z.GFR_RiseFromGround then
			z:GFR_RiseFromGround(opts.lieTime or math.Rand(3, 5))
		elseif z.SetStatus then
			z:SetStatus(false, false)
			timer.Simple(opts.lieTime or math.Rand(3, 5), function() if IsValid(z) then z:SetStatus(true, true) end end)
		end
		return z
	end
	-- Twitches on the ground, then drags itself up
	GFR.ZombieRise(z, opts.lieTime or math.Rand(3, 5))
	return z
end
GFR.ReanimateCorpse = Reanimate

---------------------------------------------------------------------------------------------------------------------------------------------
concommand.Add("gfr_spawn_bloater", function(ply)
	if IsValid(ply) && !GFR.CanCheat(ply) then return end
	local class = GFR.BloaterClass()
	local z = class && ents.Create(class)
	if !IsValid(z) then
		print("[Green Flu: Reimagined] No boomer (Left 4 Dead 1-2 Special Infected SNPCs) installed")
		return
	end
	local tr = ply:GetEyeTrace()
	z:SetPos(tr.HitPos + tr.HitNormal * 4)
	z:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
	z:Spawn()
	z:Activate()
	GFR.SetupSpawnedBloater(z)
end)
