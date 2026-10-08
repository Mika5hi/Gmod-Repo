--[[
	Custom Apocalypse - the dead don't stay down
	A zombie killed any way other than destroying the head (a headshot, an explosion, fire) gets back up after a while.
	Before it rises the body twitches and groans, so you get a warning (and a chance to finish it).
	Bloaters (their belly bursts) stay dead.
	Harvesting a body, or zombies eating it, also puts it down for good.
	Your own zombie (sv_extract.lua) follows the same rule.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_zombie_rise", "1", flags, "Zombies not killed by a headshot get back up")
local cvMin     = CreateConVar("gfr_zombie_rise_min", "25", flags, "Fewest seconds before a downed zombie gets back up")
local cvMax     = CreateConVar("gfr_zombie_rise_max", "60", flags, "Most seconds before a downed zombie gets back up")
local cvLimit   = CreateConVar("gfr_zombie_rise_limit", "0", flags, "How many times one zombie can get back up (0 = until its head is destroyed)")
local cvChance  = CreateConVar("gfr_zombie_rise_chance", "30", flags, "% chance a zombie whose head wasn't destroyed gets back up (no twitching warning when it won't)")
local cvMeleeHead = CreateConVar("gfr_melee_head_mult", "2", flags, "Damage multiplier for melee blows to a zombie's head")
local cvCorpseHead = CreateConVar("gfr_corpse_head_hp", "25", flags, "Melee damage to a downed zombie's head that destroys it (bullets always do)")

-- Damage that destroys the head / the whole body
local FINAL_DMG = bit.bor(DMG_BLAST, DMG_BURN, DMG_SLOWBURN, DMG_DISSOLVE, DMG_ALWAYSGIB, DMG_PLASMA)

function GFR.HeadDestroyed(hitgroup, dmgType)
	return hitgroup == HITGROUP_HEAD or bit.band(dmgType or 0, FINAL_DMG) != 0
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Where a hit landed. The engine only records a hitgroup for bullets: melee weapons that hand out damage directly
-- leave the NPC's last hitgroup stale, so a blow to the head never counted. Work it out from the swing instead.
local HEAD = "ValveBiped.Bip01_Head1"
local MELEE_DMG = bit.bor(DMG_CLUB, DMG_SLASH)

local function IsMelee(dmg)
	if dmg:IsBulletDamage() then return false end
	local t = dmg:GetDamageType()
	if bit.band(t, MELEE_DMG) != 0 then return true end
	-- Plain DMG_GENERIC from a player's own weapon (some melee packs use it)
	local att = dmg:GetAttacker()
	return t == DMG_GENERIC && IsValid(att) && att:IsPlayer() && dmg:GetInflictor() != att
end

local function NearHead(ent, pos)
	local id = ent:LookupBone(HEAD)
	if !id or !pos or pos:IsZero() then return false end
	local m = ent:GetBoneMatrix(id)
	local bp = m and m:GetTranslation() or ent:GetBonePosition(id)
	if !bp then return false end
	-- The head bone sits at the base of the skull; its forward axis runs up through it
	local top = m and (bp + m:GetForward() * 5) or bp
	return math.min(pos:Distance(bp), pos:Distance(top)) < 11
end

-- Is this hit on ent's head? Traces the attacker's swing first, then falls back to the damage position.
local function HitsHead(ent, dmg)
	local att = dmg:GetAttacker()
	if IsValid(att) && att:IsPlayer() then
		local tr = util.TraceLine({start = att:EyePos(), endpos = att:EyePos() + att:GetAimVector() * 160, filter = att, mask = MASK_SHOT})
		if tr.Entity == ent then
			if ent:IsNPC() then return tr.HitGroup == HITGROUP_HEAD end
			local head = ent:LookupBone(HEAD)
			if head && tr.PhysicsBone && ent:TranslatePhysBoneToBone(tr.PhysicsBone) == head then return true end
			return NearHead(ent, tr.HitPos)
		end
	end
	return NearHead(ent, dmg:GetDamagePosition())
end

-- Melee and heads:
--   fists           never take a head
--   normal melee    hurts a standing zombie's head badly, but only takes the head off one that's down (a body)
--   heavy melee     (sledgehammers, axes, machetes, swords... or any blow of gfr_heavy_melee_dmg+) takes it off a
--                   standing zombie too: a head hit kills it for good
local cvHeavyDmg = CreateConVar("gfr_heavy_melee_dmg", "45", flags, "A melee blow this strong counts as heavy (can take a standing zombie's head)")
local heavyWords = {"sledge", "axe", "hatchet", "machete", "katana", "sword", "cleaver", "maul", "shovel", "chainsaw", "claymore", "halberd", "scythe", "spade"}

local function MeleeWeapon(dmg)
	local inf, att = dmg:GetInflictor(), dmg:GetAttacker()
	if IsValid(inf) && inf:IsWeapon() then return inf end
	if IsValid(att) && (att:IsPlayer() or att:IsNPC()) then
		local w = att:GetActiveWeapon()
		if IsValid(w) then return w end
	end
end

local function FistsHit(dmg)
	local w = MeleeWeapon(dmg)
	if !IsValid(w) then return true end -- (bare hands)
	return GFR.IsFists && GFR.IsFists(w:GetClass()) or false
end

-- A gun used as a club (ARC9's bash: pistol whip, rifle butt) - never heavy, however hard it hits (ARC9 bashes do 50)
local function GunBash(w)
	if w.ARC9 then return !w.PrimaryBash end -- (ARC9 melee weapons attack with PrimaryBash; guns only bash)
	if GFR.SlotOfClass && GFR.SlotOfClass(w:GetClass()) == "melee" then return false end
	return w.GetPrimaryAmmoType && w:GetPrimaryAmmoType() >= 0
end

local function HeavyHit(dmg)
	if FistsHit(dmg) then return false end
	local w = MeleeWeapon(dmg)
	if GunBash(w) then return false end
	if dmg:GetDamage() >= cvHeavyDmg:GetFloat() then return true end
	local name = string.lower(w:GetClass() .. " " .. (w.PrintName or ""))
	for _, word in ipairs(heavyWords) do
		if string.find(name, word, 1, true) then return true end
	end
	return false
end
GFR.HeavyMeleeHit = HeavyHit

-- The hitgroup to use for this damage (sv_extract.lua, npc_gfr_infected). nil: trust the engine's (bullets).
-- A melee blow only counts as "the head" (destroyed, stays down) when it's heavy enough to take it off.
function GFR.DamageHitgroup(ent, dmg)
	if dmg:IsBulletDamage() then return nil end
	if ent.GFR_DmgHitT == CurTime() then return ent.GFR_DmgHitgroup end
	ent.GFR_DmgHitT = CurTime()
	ent.GFR_DmgHead = IsMelee(dmg) && HitsHead(ent, dmg)
	ent.GFR_DmgHitgroup = (ent.GFR_DmgHead && HeavyHit(dmg)) and HITGROUP_HEAD or HITGROUP_GENERIC
	return ent.GFR_DmgHitgroup
end

hook.Add("EntityTakeDamage", "GFR_MeleeHead", function(ent, dmg)
	if !ent:IsNPC() or !GFR.IsZombie or !GFR.IsZombie(ent) or !IsMelee(dmg) then return end
	GFR.DamageHitgroup(ent, dmg)
	if !ent.GFR_DmgHead then return end
	if ent.GFR_DmgHitgroup == HITGROUP_HEAD then
		-- Heavy: the head comes off
		dmg:SetDamage(ent:Health() + 100)
		ent:EmitSound("physics/flesh/flesh_bloody_break.wav", 75, math.random(90, 105))
	else
		dmg:ScaleDamage(cvMeleeHead:GetFloat())
		ent:EmitSound("physics/flesh/flesh_bloody_impact_hard1.wav", 70, math.random(90, 110))
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Gore: gfr_infected_gore (npc_gfr_infected) switches all of it off - no gibs, stumps or blood bursts. Limbs and heads
-- still count as gone (a crawler still crawls, a destroyed head still stays down); you just don't see it.
function GFR.Gore()
	local cv = GetConVar("gfr_infected_gore")
	return !cv or cv:GetBool()
end

-- A severed piece (h / la / ra / ll / rl) flying off, the L4D pack's limb gibs, thrown the way the hit went
local gibModels = {
	h = "models/cpthazama/l4d1/gibs/limb_male_head01.mdl",
	la = "models/cpthazama/l4d1/gibs/limb_male_larm01.mdl", ra = "models/cpthazama/l4d1/gibs/limb_male_rarm01.mdl",
	ll = "models/cpthazama/l4d1/gibs/limb_male_lleg01.mdl", rl = "models/cpthazama/l4d1/gibs/limb_male_rleg01.mdl"
}
local GIB_LIFE = 90

function GFR.LimbGib(kind, pos, force)
	if !GFR.Gore() or !pos then return end
	local mdl = gibModels[kind]
	if !mdl or !util.IsValidModel(mdl) then return end
	local gib = ents.Create("prop_ragdoll")
	if !IsValid(gib) then return end
	gib:SetModel(mdl)
	gib:SetPos(pos)
	gib:SetAngles(AngleRand())
	gib:Spawn()
	gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	gib.GFR_Gib = true
	local dir = (isvector(force) && force:LengthSqr() > 1) and force:GetNormalized() or VectorRand()
	local vel = dir * math.Rand(120, 220) + Vector(0, 0, math.Rand(80, 160))
	for i = 0, gib:GetPhysicsObjectCount() - 1 do
		local phys = gib:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:SetVelocity(vel) phys:AddAngleVelocity(VectorRand() * 300) end
	end
	SafeRemoveEntityDelayed(gib, GIB_LIFE)
	return gib
end

local function Splat(pos, ent)
	if !GFR.Gore() then return end
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetScale(6)
	fx:SetFlags(3)
	fx:SetColor(0)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	if IsValid(ent) then ent:EmitSound("physics/flesh/flesh_bloody_break.wav", 75, math.random(90, 105)) end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Finishing a downed zombie: destroy the head of the body before it gets back up
function GFR.DestroyCorpseHead(corpse, force)
	if !IsValid(corpse) or corpse.GFR_HeadGone then return end
	corpse.GFR_HeadGone = true
	local hid = corpse:LookupBone(HEAD)
	local pos = hid && corpse:GetBonePosition(hid) or corpse:WorldSpaceCenter()
	if !GFR.Gore() then return end
	local body = IsValid(corpse.Bonemerge) and corpse.Bonemerge or corpse
	local id = body:LookupBone(HEAD)
	if id then body:ManipulateBoneScale(id, Vector(0, 0, 0)) end
	Splat(pos, corpse)
	GFR.LimbGib("h", pos, force)
end

-- Limbs off a body: shot / hacked enough, an arm or a leg comes off (the same damage as on a standing one:
-- gfr_infected_arm_hp / gfr_infected_leg_hp; heavy melee in one blow, fists never). It gets back up without it.
local limbOf = {
	["ValveBiped.Bip01_L_Thigh"] = "ll", ["ValveBiped.Bip01_L_Calf"] = "ll", ["ValveBiped.Bip01_L_Foot"] = "ll",
	["ValveBiped.Bip01_R_Thigh"] = "rl", ["ValveBiped.Bip01_R_Calf"] = "rl", ["ValveBiped.Bip01_R_Foot"] = "rl",
	["ValveBiped.Bip01_L_UpperArm"] = "la", ["ValveBiped.Bip01_L_Forearm"] = "la", ["ValveBiped.Bip01_L_Hand"] = "la",
	["ValveBiped.Bip01_R_UpperArm"] = "ra", ["ValveBiped.Bip01_R_Forearm"] = "ra", ["ValveBiped.Bip01_R_Hand"] = "ra"
}
local cutBone = {ll = "ValveBiped.Bip01_L_Calf", rl = "ValveBiped.Bip01_R_Calf", la = "ValveBiped.Bip01_L_Forearm", ra = "ValveBiped.Bip01_R_Forearm"}
local limbHitgroup = {ll = HITGROUP_LEFTLEG, rl = HITGROUP_RIGHTLEG, la = HITGROUP_LEFTARM, ra = HITGROUP_RIGHTARM}

-- Which limb of the body this hit landed on (the attacker's aim through the ragdoll's physics bones, else the nearest
-- limb bone to where it hit)
local function LimbHit(ent, dmg)
	local att = dmg:GetAttacker()
	if IsValid(att) && att:IsPlayer() then
		local tr = util.TraceLine({start = att:EyePos(), endpos = att:EyePos() + att:GetAimVector() * 4000, filter = att, mask = MASK_SHOT})
		if tr.Entity == ent && tr.PhysicsBone then
			local name = ent:GetBoneName(ent:TranslatePhysBoneToBone(tr.PhysicsBone))
			return limbOf[name]
		end
	end
	local pos = dmg:GetDamagePosition()
	if !pos or pos:IsZero() then return end
	local best, bestD
	for name, kind in pairs(limbOf) do
		local id = ent:LookupBone(name)
		local bp = id && ent:GetBonePosition(id)
		if bp then
			local d = bp:DistToSqr(pos)
			if d < 12 * 12 && (!bestD or d < bestD) then best, bestD = kind, d end
		end
	end
	return best
end

function GFR.CutCorpseLimb(corpse, kind, force)
	corpse.GFR_LimbsCut = corpse.GFR_LimbsCut or {}
	if corpse.GFR_LimbsCut[kind] then return end
	corpse.GFR_LimbsCut[kind] = true
	local id = corpse:LookupBone(cutBone[kind])
	local pos = id && corpse:GetBonePosition(id) or corpse:WorldSpaceCenter()
	if !GFR.Gore() then return end
	local body = IsValid(corpse.Bonemerge) and corpse.Bonemerge or corpse
	local bid = body:LookupBone(cutBone[kind])
	if bid then body:ManipulateBoneScale(bid, Vector(0, 0, 0)) end
	Splat(pos, corpse)
	GFR.LimbGib(kind, pos, force)
end

hook.Add("EntityTakeDamage", "GFR_CorpseLimbs", function(ent, dmg)
	if !ent.GFR_ZCorpse or ent:GetClass() != "prop_ragdoll" then return end
	local t = dmg:GetDamageType()
	if !dmg:IsBulletDamage() && !IsMelee(dmg) && bit.band(t, DMG_BLAST) == 0 then return end
	local kind = LimbHit(ent, dmg)
	if !kind then return end
	if (kind == "ll" && ent.GFR_LegGone == HITGROUP_LEFTLEG) or (kind == "rl" && ent.GFR_LegGone == HITGROUP_RIGHTLEG)
		or (ent.GFR_ArmGone && ent.GFR_ArmGone[limbHitgroup[kind]]) or (ent.GFR_LimbsCut && ent.GFR_LimbsCut[kind]) then return end
	local melee = IsMelee(dmg)
	if melee && FistsHit(dmg) then return end
	local cv = GetConVar((kind == "la" or kind == "ra") and "gfr_infected_arm_hp" or "gfr_infected_leg_hp")
	local limit = cv and cv:GetFloat() or 40
	if limit <= 0 then return end
	ent.GFR_LimbDmg = ent.GFR_LimbDmg or {}
	ent.GFR_LimbDmg[kind] = (ent.GFR_LimbDmg[kind] or 0) + dmg:GetDamage()
	if (melee && HeavyHit(dmg)) or ent.GFR_LimbDmg[kind] >= limit then GFR.CutCorpseLimb(ent, kind, dmg:GetDamageForce()) end
end)

hook.Add("EntityTakeDamage", "GFR_CorpseHead", function(ent, dmg)
	if !(ent.GFR_ZCorpse or ent.GFR_TurningBody) or ent.GFR_HeadGone or ent:GetClass() != "prop_ragdoll" then return end
	local final = bit.band(dmg:GetDamageType(), FINAL_DMG) != 0
	if !final && !HitsHead(ent, dmg) then return end
	if !final && dmg:IsBulletDamage() then
		-- A bullet: the same chance as on a standing one (sv_headshots.lua)
		if GFR.HeadPopChance && math.Rand(0, 1) >= GFR.HeadPopChance(dmg) then
			ent:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 70)
			return
		end
	elseif !final then
		if FistsHit(dmg) then return end -- (fists can't)
		if !HeavyHit(dmg) then
			-- Hack at it: a couple of good blows take it off
			ent.GFR_HeadDmg = (ent.GFR_HeadDmg or 0) + dmg:GetDamage() * cvMeleeHead:GetFloat()
			if ent.GFR_HeadDmg < cvCorpseHead:GetFloat() then
				ent:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 70)
				return
			end
		end
	end
	GFR.DestroyCorpseHead(ent, dmg:GetDamageForce())
end)

local function BeingHandled(corpse)
	if corpse.GFR_ParasiteClaimed or corpse.GFR_EatenBy or corpse.VJ_ST_BeingEaten then return true end
	for _, ply in ipairs(player.GetAll()) do
		if ply.GFR_Harvest && ply.GFR_Harvest.ent == corpse then return true end
	end
	return false
end

-- A limb jerks and it groans: it's about to get up
local function Twitch(corpse)
	if !IsValid(corpse) or corpse.GFR_HeadGone then return end
	local n = corpse:GetPhysicsObjectCount()
	if n > 0 then
		local phys = corpse:GetPhysicsObjectNum(math.random(0, n - 1))
		if IsValid(phys) then phys:ApplyForceCenter(VectorRand() * phys:GetMass() * 120 + Vector(0, 0, phys:GetMass() * 80)) end
	end
	sound.Play("vj_cncr/zombie/zombie_voice_idle" .. math.random(1, 14) .. ".wav", corpse:WorldSpaceCenter(), 70, math.random(80, 95))
end

local function TryRise(corpse, info, tries)
	if !IsValid(corpse) or corpse.GFR_HeadGone or !cvEnabled:GetBool() or !GFR.ReanimateCorpse then return end
	if BeingHandled(corpse) then
		-- Someone's busy with it; check again later (unless it gets eaten or carved up first)
		if (tries or 0) < 6 then timer.Simple(10, function() TryRise(corpse, info, (tries or 0) + 1) end) end
		return
	end
	-- It gets up without whatever it lost, standing or after it went down (GFR.CutCorpseLimb)
	local cut = corpse.GFR_LimbsCut or {}
	local legGone = info.legGone or (cut.ll and HITGROUP_LEFTLEG) or (cut.rl and HITGROUP_RIGHTLEG) or nil
	local armsGone = table.Copy(info.armsGone or {})
	if cut.la then armsGone[HITGROUP_LEFTARM] = true end
	if cut.ra then armsGone[HITGROUP_RIGHTARM] = true end
	GFR.ReanimateCorpse(corpse, {host = false, runner = info.runner or false, gore = false, rises = info.rises, lieTime = math.Rand(1, 2),
		legGone = legGone, armsGone = armsGone})
end

hook.Add("RTRG_ZombieCorpse", "GFR_Rise_Schedule", function(z, corpse)
	if IsValid(z.GFR_ControlPlayer) then return end -- a player's zombie: they get back up in it themselves (sv_extract.lua)
	-- Down for good: the corpse is marked so it's cleared away sooner (sv_zombieworld.lua)
	if !cvEnabled:GetBool() or z.GFR_Bloater or z.GFR_ParasiteHost or z.GFR_Hunter or GFR.HeadDestroyed(z.RTRG_DeathHitgroup, z.RTRG_DeathDmgType) then
		corpse.GFR_HeadGone = true
		return
	end
	local rises = (z.GFR_Rises or 0) + 1
	if cvLimit:GetInt() > 0 && rises > cvLimit:GetInt() then return end
	-- Stays down this time - but its head's still there, so nobody can tell which ones will get up
	if math.Rand(0, 100) >= cvChance:GetFloat() then return end
	local info = {runner = z.RTRG_ForceRunner, rises = rises, legGone = z.RTRG_LegGone, armsGone = z.GFR_ArmGone && table.Copy(z.GFR_ArmGone)}
	corpse.GFR_RiseInfo = info
	local delay = math.Rand(cvMin:GetFloat(), math.max(cvMax:GetFloat(), cvMin:GetFloat()))
	timer.Simple(math.max(delay - 6, 1), function() Twitch(corpse) end)
	timer.Simple(math.max(delay - 2, 1.5), function() Twitch(corpse) end)
	timer.Simple(delay, function() TryRise(corpse, info) end)
end)
