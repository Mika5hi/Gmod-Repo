-- GMod of the Dead's zombie AI: grab/bite melee, door breaking, crippling, ground rise, etc.
include("entities/npc_vj_gotdr_zombie_base/init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Invisible GOTDR animation rig (has choke grab + eating01 animations on the ValveBiped skeleton)
ENT.Model = "models/vj_gotdr/misc/breen_walply.mdl"
ENT.CanEat = true

local math_random = math.random
local math_clamp = math.Clamp

local maleModels = {
	"models/vj_cncr/zombies/zombie_male_01.mdl",
	"models/vj_cncr/zombies/zombie_male_02.mdl",
	"models/vj_cncr/zombies/zombie_male_03.mdl",
	"models/vj_cncr/zombies/zombie_male_04.mdl",
	"models/vj_cncr/zombies/zombie_male_05.mdl",
	"models/vj_cncr/zombies/zombie_male_06.mdl",
	"models/vj_cncr/zombies/zombie_male_07.mdl",
	"models/vj_cncr/zombies/zombie_male_08.mdl",
	"models/vj_cncr/zombies/zombie_male_09.mdl"
}
local femaleModels = {
	"models/vj_cncr/zombies/zombie_female_01.mdl",
	"models/vj_cncr/zombies/zombie_female_02.mdl",
	"models/vj_cncr/zombies/zombie_female_03.mdl",
	"models/vj_cncr/zombies/zombie_female_04.mdl",
	"models/vj_cncr/zombies/zombie_female_05.mdl",
	"models/vj_cncr/zombies/zombie_female_06.mdl"
}

local function numbered(path, count)
	local tbl = {}
	for i = 1, count do tbl[i] = string.format(path, i) end
	return tbl
end

local voices = {
	male = {
		Idle = numbered("vj_cncr/zombie/zombie_voice_idle%d.wav", 14),
		Alert = numbered("vj_cncr/zombie/zombie_alert%d.wav", 7),
		CombatIdle = numbered("vj_cncr/zombie/zombie_voice_idle_combat%d.wav", 8),
		BeforeMeleeAttack = numbered("vj_cncr/zombie/zo_attack%d.wav", 5),
		Pain = numbered("vj_cncr/zombie/zombie_pain%d.wav", 8),
		Death = numbered("vj_cncr/zombie/zombie_die%d.wav", 7)
	},
	female = {
		Idle = numbered("vj_cncr/zombie/Female/zombie_voice_idle%d.wav", 13),
		Alert = numbered("vj_cncr/zombie/Female/zombie_alert%d.wav", 8),
		CombatIdle = numbered("vj_cncr/zombie/Female/zombie_voice_idle_combat%d.wav", 8),
		BeforeMeleeAttack = numbered("vj_cncr/zombie/Female/zo_attack%d.wav", 8),
		Pain = numbered("vj_cncr/zombie/Female/zombie_pain%d.wav", 8),
		Death = numbered("vj_cncr/zombie/Female/zombie_die%d.wav", 8)
	}
}
---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:Zombie_Init()
	if IsValid(self.Bonemerge) then return end
	local femaleChance = math.max(GetConVar("vj_rtrg_female_chance"):GetInt(), 1)
	self.RTRG_Female = math_random(1, femaleChance) == 1
	local mdl = self.RTRG_Female and femaleModels[math_random(#femaleModels)] or maleModels[math_random(#maleModels)]
	self:VJ_GOTDR_CreateBoneMerge(self, mdl, math_random(0, 2), color_white, "", false, nil, nil)
	self.GOTDR_Gender = -1 -- Use ZombieVoice_Custom
end
---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:ZombieVoice_Custom()
	local set = self.RTRG_Female and voices.female or voices.male
	self.SoundTbl_Idle = set.Idle
	self.SoundTbl_Alert = set.Alert
	self.SoundTbl_CombatIdle = set.CombatIdle
	self.SoundTbl_BeforeMeleeAttack = set.BeforeMeleeAttack
	self.SoundTbl_Pain = set.Pain
	self.SoundTbl_Death = set.Death
end
---------------------------------------------------------------------------------------------------------------------------------------------
local baseInit = ENT.Init
--
function ENT:Init()
	baseInit(self)
	if self.RTRG_ForceRunner && !self.GOTDR_Crawler then
		-- Set by the Custom Apocalypse spawn director for night spawns
		-- With NMRiH animations (VJ_GOTDR_ZombieAnims 2) GOTDR ignores GOTDR_Runner; only sprinters run
		self.GOTDR_Runner = !self.GOTDR_NMRIHAnims
		self.GOTDR_Sprinter = self.GOTDR_NMRIHAnims or false
		self.GOTDR_SuperSprinter = false
		-- NMRiH mode only has 2 run animations (ACT_RUN_AGITATED), so every sprinter ran the same.
		-- The rig also has the BO3 sets: ~14 sprints (ACT_SPRINT) and ~25 runs (ACT_RUN_RELAXED); the engine picks a
		-- random one of the set each time it starts moving, so a crowd of sprinters all look different.
		self.RTRG_RunAct = math_random(3) == 1 and ACT_RUN_RELAXED or ACT_SPRINT
	elseif !GetConVar("vj_rtrg_runners"):GetBool() then
		self.GOTDR_Runner = false
		self.GOTDR_Sprinter = false
		self.GOTDR_SuperSprinter = false
	end
	self:DrawShadow(false)
end
---------------------------------------------------------------------------------------------------------------------------------------------
local baseTranslate = ENT.TranslateActivity
--
function ENT:TranslateActivity(act)
	if self.RTRG_RunAct && (act == ACT_WALK or act == ACT_RUN) && !self.GOTDR_Crawler && !self.GOTDR_Crippled then
		return self.RTRG_RunAct
	end
	return baseTranslate(self, act)
end
---------------------------------------------------------------------------------------------------------------------------------------------
-- L4D idles (Green Flu style). Our rig can't play Left 4 Dead animations, so while the zombie stands around
-- doing nothing, its visible body is bonemerged onto an invisible L4D common infected "puppet" that plays an
-- L4D idle (swaying, hunched, looking around - or sitting / lying on the ground for dormant ones).
-- The moment it notices something, moves, gets hurt or dies, the body snaps back onto the real rig.
-- Needs [Left 4 Dead Common Infected SNPCs] (or any addon with the L4D anim_common set); off without it.
CreateConVar("vj_rtrg_l4d_idles", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Zombies use Left 4 Dead common infected idle animations when standing around")
CreateConVar("vj_rtrg_dormant_chance", "25", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "% of zombies that start out sitting or lying on the ground")

local puppetModels = {"models/cpthazama/l4d1/common/common_male_rural01.mdl", "models/infected/common_male_rural01.mdl", "models/infected/common_male01.mdl"}
local puppetModel -- first one that exists, found on first use
local standIdles = {"Idle_Neutral_01", "Idle_Neutral_02", "Idle_Neutral_03", "Idle_Neutral_04", "Idle_Neutral_05", "Idle_Neutral_06", "Idle_Neutral_07", "Idle_Neutral_08"}
local sitIdles = {"Sitting01", "Sitting02", "Sitting03", "Sitting04", "Sitting05", "Sitting06", "Sitting07", "Sitting08"}
local lieIdles = {"Lying01", "Lying02", "Lying03", "Lying04", "Lying05", "Lying06", "Lying07", "Lying08"}
local getUps = {sit = {"Sitting_to_Standing_Alert"}, lie = {"Lying_to_Standing_Alert", "Lying_to_Standing_Alert03c", "Lying_to_Standing_Alert03d"}}
local STILL_TIME = 1.5 -- seconds of standing still before it settles into an L4D idle

local function PuppetModel()
	if puppetModel == nil then
		puppetModel = false
		for _, mdl in ipairs(puppetModels) do
			if util.IsValidModel(mdl) then puppetModel = mdl break end
		end
	end
	return puppetModel
end

-- Put the body back on the rig. animated = sitting/lying zombies get up first (they're frozen for that moment).
function ENT:RTRG_EndPose(instant)
	local pose = self.RTRG_Pose
	if !pose then return end
	self.RTRG_Pose = nil
	self.DisableWandering = self.RTRG_OrgWander
	local puppet, body = pose.puppet, self.Bonemerge
	local function Restore()
		if IsValid(body) && IsValid(self) then
			body:SetParent(self)
			body:AddEffects(EF_BONEMERGE)
		end
		if IsValid(puppet) then puppet:Remove() end
	end
	if instant or pose.kind == "stand" or !IsValid(puppet) or self.Dead then
		Restore()
		return
	end
	-- Get up off the floor before going for you
	local anims = getUps[pose.kind]
	local seq = puppet:LookupSequence(anims[math_random(#anims)])
	if seq < 0 then Restore() return end
	puppet:ResetSequence(seq)
	puppet:SetCycle(0)
	puppet:SetPlaybackRate(1)
	local dur = math.min(puppet:SequenceDuration(seq), 3)
	self.RTRG_GettingUp = true
	self:StopMoving()
	self:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK, dur)
	timer.Simple(dur, function()
		if IsValid(self) then self.RTRG_GettingUp = nil end
		Restore()
	end)
end

function ENT:RTRG_StartPose(kind)
	local mdl = PuppetModel()
	local body = self.Bonemerge
	if !mdl or !IsValid(body) then return end
	local list = kind == "sit" and sitIdles or kind == "lie" and lieIdles or standIdles
	local puppet = ents.Create("prop_dynamic")
	if !IsValid(puppet) then return end
	puppet:SetModel(mdl)
	puppet:SetPos(self:GetPos())
	puppet:SetAngles(Angle(0, self:GetAngles().y, 0))
	puppet:SetKeyValue("DefaultAnim", list[math_random(#list)]) -- loops
	puppet:SetKeyValue("solid", "0")
	puppet:Spawn()
	puppet:SetParent(self)
	puppet:SetRenderMode(RENDERMODE_TRANSALPHA)
	puppet:SetColor(Color(255, 255, 255, 0)) -- invisible, but still animates for the body to follow
	puppet:DrawShadow(false)
	puppet:SetPlaybackRate(math.Rand(0.85, 1.1))
	puppet:SetCycle(math.Rand(0, 1))
	self:DeleteOnRemove(puppet)
	body:SetParent(puppet)
	body:AddEffects(EF_BONEMERGE)
	self.RTRG_Pose = {puppet = puppet, kind = kind}
	-- Sitting/lying ones stay put until something comes along
	self.RTRG_OrgWander = self.DisableWandering
	if kind != "stand" then self.DisableWandering = true end
end

local function CanIdlePose(self)
	return !self.Dead && self:Health() > 0 && !IsValid(self:GetEnemy()) && !self.Alerted && !self:IsMoving()
		&& !self.VJ_ST_Eating && !self.VJ_IsBeingControlled && !self.GOTDR_Crawler && !self.GOTDR_Crippled && !self.Flinching
		&& !self.AttackType && self:GetState() == VJ_STATE_NONE && IsValid(self.Bonemerge)
end

function ENT:Zombie_OnThink()
	if self.RTRG_GettingUp then return end
	local now = CurTime()
	if (self.RTRG_NextPoseCheck or 0) > now then return end
	self.RTRG_NextPoseCheck = now + 0.3
	if !GetConVar("vj_rtrg_l4d_idles"):GetBool() or !PuppetModel() then
		if self.RTRG_Pose then self:RTRG_EndPose(true) end
		return
	end
	local ok = CanIdlePose(self)
	if self.RTRG_Pose then
		if !ok then self:RTRG_EndPose(false) end
		return
	end
	if !ok then self.RTRG_StillSince = nil return end
	self.RTRG_StillSince = self.RTRG_StillSince or now
	if now - self.RTRG_StillSince < STILL_TIME then return end
	-- Dormant ones sit or lie the first time; after that they just stand and sway
	local kind = "stand"
	if self.RTRG_Dormant == nil then
		self.RTRG_Dormant = math.Rand(0, 100) < GetConVar("vj_rtrg_dormant_chance"):GetFloat()
		if self.RTRG_Dormant then kind = math_random(5) <= 2 and "sit" or "lie" end
	end
	self:RTRG_StartPose(kind)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Gore you can read: a leg shot off below the knee (and it crawls from then on), the head gone on a corpse
-- whose head was destroyed (so you know that one's not getting back up), charred bodies after fire/explosions.
-- Done by shrinking bones on the visible bonemerged body (children collapse with them: calf -> foot -> toe).
CreateConVar("vj_rtrg_leg_hp", "45", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Damage to one leg before it's blown off and the zombie has to crawl (0 = never)")
CreateConVar("vj_rtrg_gore", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Visible dismemberment: missing legs, destroyed heads, charred bodies")

local legBones = {[HITGROUP_LEFTLEG] = "ValveBiped.Bip01_L_Calf", [HITGROUP_RIGHTLEG] = "ValveBiped.Bip01_R_Calf"}
local gibModels = {"models/gibs/hgibs_jaw.mdl", "models/gibs/hgibs_scapula.mdl", "models/gibs/hgibs_rib.mdl", "models/gibs/hgibs_spine.mdl"}
local vecZero = Vector(0, 0, 0)

local function HideBone(ent, bone)
	if !IsValid(ent) then return end
	local id = ent:LookupBone(bone)
	if id then ent:ManipulateBoneScale(id, vecZero) end
end

local function BonePos(ent, bone)
	local id = IsValid(ent) && ent:LookupBone(bone)
	local pos = id && ent:GetBonePosition(id)
	return pos or (IsValid(ent) && ent:WorldSpaceCenter())
end

local function Splatter(pos, gibs)
	if !pos then return end
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetScale(6)
	fx:SetFlags(3)
	fx:SetColor(0)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	sound.Play("physics/flesh/flesh_bloody_break.wav", pos, 75, math_random(90, 110))
	local tr = util.TraceLine({start = pos, endpos = pos - Vector(0, 0, 100), mask = MASK_SOLID_BRUSHONLY})
	util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
	for _ = 1, gibs or 0 do
		local mdl = gibModels[math_random(#gibModels)]
		if !util.IsValidModel(mdl) then continue end
		local gib = ents.Create("prop_physics")
		gib:SetModel(mdl)
		gib:SetPos(pos + VectorRand() * 4)
		gib:SetAngles(AngleRand())
		gib:Spawn()
		gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		gib:SetColor(Color(150, 60, 55))
		local phys = gib:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity(VectorRand() * 120 + Vector(0, 0, 150)) end
		SafeRemoveEntityDelayed(gib, 20)
	end
end

-- Blow a leg off below the knee. quiet = no gore/fall (a body getting back up that was already missing it)
function ENT:RTRG_LoseLeg(hitgroup, quiet)
	if self.RTRG_LegGone or !legBones[hitgroup] then return end
	self.RTRG_LegGone = hitgroup
	if GetConVar("vj_rtrg_gore"):GetBool() then HideBone(self.Bonemerge, legBones[hitgroup]) end
	if !quiet then Splatter(BonePos(self, legBones[hitgroup]), 1) end
	self.RTRG_RunAct = nil
	if !self.GOTDR_Crippled then
		self.GOTDR_Crippled = true
		if !quiet && self.PlayAnim then self:PlayAnim({"vjseq_nz_death_1", "vjseq_nz_death_f_7", "vjseq_nz_death_f_8"}, true, false, false) end
		if self.SetCrawler then self:SetCrawler() end
	end
end

local legDamageTypes = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_SLASH, DMG_CLUB, DMG_BLAST)

local baseOnDamaged = ENT.OnDamaged
--
function ENT:OnDamaged(dmginfo, hitgroup, status)
	if status == "PreDamage" && self.RTRG_Pose then self:RTRG_EndPose(true) end
	local ret = baseOnDamaged(self, dmginfo, hitgroup, status)
	-- Enough damage to one leg takes it off; a big blast can take one too
	if status == "PostDamage" && !self.RTRG_LegGone && !self.Dead && self:Health() > 0 && bit.band(dmginfo:GetDamageType(), legDamageTypes) != 0 then
		local limit = GetConVar("vj_rtrg_leg_hp"):GetFloat()
		if limit > 0 then
			if legBones[hitgroup] then
				self.RTRG_LegDmg = (self.RTRG_LegDmg or 0) + dmginfo:GetDamage()
				if self.RTRG_LegDmg >= limit then self:RTRG_LoseLeg(hitgroup) end
			elseif dmginfo:IsExplosionDamage() && dmginfo:GetDamage() >= limit && math_random(3) == 1 then
				self:RTRG_LoseLeg(math_random(2) == 1 and HITGROUP_LEFTLEG or HITGROUP_RIGHTLEG)
			end
		end
	end
	return ret
end

-- The corpse shows how it died (called from OnCreateDeathCorpse below)
local burnTypes = bit.bor(DMG_BURN, DMG_SLOWBURN, DMG_BLAST)

local function CorpseGore(self, corpse)
	if !GetConVar("vj_rtrg_gore"):GetBool() then return end
	local body = IsValid(corpse.Bonemerge) and corpse.Bonemerge or corpse
	if self.RTRG_LegGone then HideBone(body, legBones[self.RTRG_LegGone]) end
	if self.RTRG_DeathHitgroup == HITGROUP_HEAD then
		HideBone(body, "ValveBiped.Bip01_Head1")
		local neck = BonePos(corpse, "ValveBiped.Bip01_Neck1")
		Splatter(neck, 3)
		-- The stump keeps pumping for a few seconds
		for i = 1, 5 do
			timer.Simple(i * 0.6, function()
				if !IsValid(corpse) then return end
				local fx = EffectData()
				fx:SetOrigin(BonePos(corpse, "ValveBiped.Bip01_Neck1"))
				fx:SetScale(3)
				fx:SetFlags(3)
				fx:SetColor(0)
				util.Effect("bloodspray", fx)
			end)
		end
	end
	if bit.band(self.RTRG_DeathDmgType or 0, burnTypes) != 0 then
		body:SetColor(Color(60, 50, 45)) -- charred
	end
end

local baseOnDeath = ENT.OnDeath
--
function ENT:OnDeath(dmginfo, hitgroup, status)
	if status == "Init" then
		if self.RTRG_Pose then self:RTRG_EndPose(true) end
		-- How it died decides whether it can get back up (read from the corpse via the RTRG_ZombieCorpse hook)
		self.RTRG_DeathHitgroup = hitgroup
		self.RTRG_DeathDmgType = dmginfo:GetDamageType()
	end
	return baseOnDeath(self, dmginfo, hitgroup, status)
end
---------------------------------------------------------------------------------------------------------------------------------------------
-- Return to Ravenholm's eating behaviour, ported to the current VJ Base eating API
local vecZ50 = Vector(0, 0, -50)
--
-- Mark our corpses as harvestable zombie corpses (Custom Apocalypse sv_harvest.lua)
local baseCreateCorpse = ENT.OnCreateDeathCorpse
--
function ENT:OnCreateDeathCorpse(dmginfo, hitgroup, corpse)
	if baseCreateCorpse then baseCreateCorpse(self, dmginfo, hitgroup, corpse) end
	if IsValid(corpse) then
		corpse.GFR_ZCorpse = true
		corpse:SetNW2Bool("GFR_ZCorpse", true)
		CorpseGore(self, corpse)
		hook.Run("RTRG_ZombieCorpse", self, corpse) -- e.g. Custom Apocalypse lets it get back up later (sv_rise.lua)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:OnEat(status, statusData)
	if status == "CheckFood" then
		return true
	elseif status == "BeginEating" then
		VJ.EmitSound(self, "vj_cncr/eating/Eating_Begin" .. math_random(1, 2) .. ".wav", 65)
		self.AnimationTranslations[ACT_IDLE] = ACT_GESTURE_RANGE_ATTACK1
		return select(2, self:PlayAnim(ACT_ARM, true, false))
	elseif status == "Eat" then
		VJ.EmitSound(self, "vj_cncr/eating/Eating_Loop_DL" .. math_random(1, 4) .. ".wav", 65)
		local food = self.EatingData.Target
		local myHP = self:Health()
		self:SetHealth(math_clamp(myHP + 15, myHP, math.max(self:GetMaxHealth(), myHP)))
		local bloodData = food.BloodData
		if bloodData then
			local bloodPos = food:GetPos() + food:OBBCenter()
			local bloodParticle = VJ.PICK(bloodData.Particle)
			if bloodParticle then
				ParticleEffect(bloodParticle, bloodPos, self:GetAngles())
				ParticleEffectAttach(bloodParticle, PATTACH_POINT_FOLLOW, self, self:LookupAttachment("mouth"))
			end
			local bloodDecal = VJ.PICK(bloodData.Decal)
			if bloodDecal then
				local tr = util.TraceLine({start = bloodPos, endpos = bloodPos + vecZ50, filter = {food, self}})
				util.Decal(bloodDecal, tr.HitPos + tr.HitNormal + Vector(math_random(-45, 45), math_random(-45, 45), 0), tr.HitPos - tr.HitNormal, food)
			end
		end
		-- Meat thrown down as bait (Custom Apocalypse) is gone after a few bites
		if food.GFR_Bait then
			food.GFR_BaitBites = (food.GFR_BaitBites or 0) + 1
			if food.GFR_BaitBites >= 3 then food:Remove() end
		end
		return 5
	elseif status == "StopEating" then
		if statusData != "Dead" && self.EatingData.AnimStatus != "None" then
			return select(2, self:PlayAnim(ACT_DISARM, true, false))
		end
	end
	return 0
end
