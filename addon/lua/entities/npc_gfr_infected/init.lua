--[[
	Custom Apocalypse - the infected
	Left 4 Dead common infected (models, movement, swipes, stumbles, sit/lie idles, limb gibs, L4D voices) with:
		- walks by day, runs at night (RTRG_ForceRunner = always runs, e.g. parasite-turned)
		- each attack is a swipe or a grab, 50/50 (gfr_infected_grab_chance). A grab holds you and bites; mash E to shove
		  it off, J to give in (sv_extract.lua), shooting it hard also makes it let go
		- eats bodies (VJ eating)
		- enough damage to a leg takes it off and it crawls
		- turned people (GFR_ForceModel...) wear their own body on an invisible L4D skeleton
		- grab, eating and crawling play GMod of the Dead's animations: for those moments the body is moved onto an
		  invisible GOTDR rig "puppet" playing them (the L4D rig has no such animations)
	Keeps the old zombie's names so the gamemode's systems still work: RTRG_ForceRunner, RTRG_LoseLeg, RTRG_LegGone,
	RTRG_DeathHitgroup/DmgType, the RTRG_ZombieCorpse hook (rising again), GOTDR_CurEnt / GOTDR_Grappled / ResetGrapple
	(giving in, surrender), Bonemerge (parasites read the corpse's look).
]]
include("vj_base/extensions/l4d_com_infected.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvGrab   = CreateConVar("gfr_infected_grab_chance", "50", flags, "% of infected attacks that are grabs instead of swipes")
local cvLegHP  = CreateConVar("gfr_infected_leg_hp", "45", flags, "Damage to one leg before it comes off and the infected crawls (0 = never)")
local cvGore   = CreateConVar("gfr_infected_gore", "0", flags, "Gore: missing limbs/heads, flying gibs, blood bursts, charred bodies (0 = none; limbs still count as lost)")
local cvArmHP  = CreateConVar("gfr_infected_arm_hp", "35", flags, "Damage to one arm before it comes off (0 = never). One arm gone: weaker hits; both: weak hits and no grabbing")
-- How far they notice you. VJ's default is ~6500 units in an almost 180 degree cone, plus calling every zombie within
-- 2000 to join in: the whole street came for you the moment you showed up, nothing ever just wandered.
-- They don't call each other at all (the dead don't coordinate): each one has to notice you itself.
local cvSight      = CreateConVar("gfr_zombie_sight", "1300", flags, "How far zombies see you by day")
local cvSightNight = CreateConVar("gfr_zombie_sight_night", "900", flags, "How far zombies see you at night (it's dark)")

ENT.Model = "models/cpthazama/l4d1/common/male_01.mdl" -- replaced per zombie in PreInit
ENT.StartHealth = 80
ENT.CanEat = true
-- Movement jumps: VJ's default lets it leap 220 units up a wall to reach you. The dead stumble over a low wall
-- or drop off a ledge, nothing more. (Given per zombie in Init: VJ's controller edits this table in place.)
ENT.HasLeapAttack = false
local JUMPS = {Enabled = true, MaxRise = 40, MaxDrop = 160, MaxDistance = 140}

local math_random = math.random
local RIG = "models/vj_gotdr/misc/breen_walply.mdl" -- GMod of the Dead's animation rig (grab, eating, crawling)

-- Which L4D infected a random one is: model, bodygroup/skin randomiser and gib code are borrowed from that class
local variants = {
	{"npc_vj_l4d_com_male", 7}, {"npc_vj_l4d_com_female", 5}, {"npc_vj_l4d_com_f_nurse", 1}, {"npc_vj_l4d_com_m_airport", 1},
	{"npc_vj_l4d_com_m_hospital", 1}, {"npc_vj_l4d_com_m_police", 1}, {"npc_vj_l4d_com_m_soldier", 1}, {"npc_vj_l4d_com_m_worker", 1},
	{"npc_vj_l4d_com_m_ceda", 0.4}, {"npc_vj_l4d_com_m_fallsur", 0.3}
}
local SKELETON = {[0] = "models/cpthazama/l4d1/common/male_01.mdl", [1] = "models/cpthazama/l4d1/common/common_female01.mdl"}

local femaleWords = {"female", "alyx", "mossman", "chell", "zoey", "producer", "rochelle", "girl", "woman", "lady", "_f_", "fem", "boomette"}
local function IsFemale(mdl)
	mdl = string.lower(mdl or "")
	for _, w in ipairs(femaleWords) do if string.find(mdl, w, 1, true) then return true end end
	return false
end

local function PickVariant()
	local total = 0
	for _, v in ipairs(variants) do if scripted_ents.GetStored(v[1]) then total = total + v[2] end end
	local roll = math.Rand(0, total)
	for _, v in ipairs(variants) do
		local stored = scripted_ents.GetStored(v[1])
		if stored then
			roll = roll - v[2]
			if roll <= 0 then return stored.t end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:PreInit()
	local gibs
	if self.GFR_ForceModel then
		-- A turned person: an L4D skeleton under their own body
		self.RTRG_Female = IsFemale(self.GFR_ForceModel)
		self.Zombie_Gender = self.RTRG_Female and 1 or 0
		self.Model = SKELETON[self.Zombie_Gender]
		self.GFR_PM = true
		self.Zombie_OnInit = nil
	else
		local t = PickVariant()
		if t then
			self.Model = t.Model
			self.Zombie_Gender = t.Zombie_Gender or 0
			self.Zombie_OnInit = t.Zombie_OnInit
			gibs = t.Zombie_Gibs
		end
	end
	-- Each gib only once (the L4D code toggles bodygroups, a second call would undo it)
	self.GFR_Gibbed = {}
	self.Zombie_Gibs = function(s, kind)
		if s.GFR_PM or s.GFR_Gibbed[kind] then return end
		s.GFR_Gibbed[kind] = true
		if gibs then gibs(s, kind) end
	end
end

-- Rotting skin and faded clothes for turned people
local skinTint = Color(195, 205, 185)

local function MakeBody(parent, mdl, skin, bodygroups, color, playerColor)
	local class = scripted_ents.GetStored("gfr_bonemerge") and "gfr_bonemerge" or "prop_dynamic"
	local body = ents.Create(class)
	if !IsValid(body) then return end
	body:SetModel(mdl)
	body:SetPos(parent:GetPos())
	body:SetAngles(parent:GetAngles())
	body:SetParent(parent)
	body:Spawn()
	body:AddEffects(EF_BONEMERGE)
	if !body:LookupBone("ValveBiped.Bip01_Pelvis") then body:Remove() return end
	body:SetSkin(skin or 0)
	for i, v in pairs(bodygroups or {}) do body:SetBodygroup(i, v) end
	if color then body:SetColor(color) end
	if playerColor && body.SetPlayerColor then body:SetPlayerColor(playerColor) end
	parent:DeleteOnRemove(body)
	return body
end

-- Invisible but still animating (bonemerged bodies follow it). Alpha alone isn't enough: the L4D models' torn
-- clothes are alpha-tested and ignore it, so they'd still show through - an invisible material hides everything.
local INVISIBLE = "models/effects/vol_light001"

-- keepDrawn: the animation rig (GFR_PuppetStart). A prop_dynamic that isn't drawn doesn't animate on the client, so the
-- body worn on it would stand frozen in its default pose instead of eating / grabbing / crawling. It keeps the faint
-- glow of the invisible material; everything else hidden this way isn't drawn at all (sh_zombieplayer.lua).
local function Hide(ent, keepDrawn)
	ent:SetMaterial(INVISIBLE)
	ent:DrawShadow(false)
	if keepDrawn then
		-- The rig: fully opaque as far as the engine knows (so it's drawn, and its animation worked out every frame),
		-- drawn at zero opacity on the client (sh_zombieplayer.lua GFR_DrawHidden)
		ent:SetRenderMode(RENDERMODE_NORMAL)
		ent:SetColor(color_white)
		ent:SetNW2Bool("GFR_DrawHidden", true)
	else
		ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
		ent:SetColor(Color(255, 255, 255, 0))
		ent:SetNW2Bool("GFR_HideBase", true)
	end
	ent.GFR_Hidden = true
end

local function Show(ent)
	ent:SetMaterial("")
	ent:SetColor(Color(255, 255, 255, 255))
	ent:SetRenderMode(RENDERMODE_NORMAL)
	ent:DrawShadow(true)
	ent:SetNW2Bool("GFR_HideBase", false)
	ent.GFR_Hidden = nil
end

local baseInit = ENT.Init
--
function ENT:Init()
	baseInit(self)
	self.JumpParams = table.Copy(JUMPS)
	self.Zombie_CanClimb = false -- the L4D pack's "experimental" climb teleports it up walls (vj_l4d_alllowclimbing)
	self.SightAngle = 130
	self.CallForHelp = false
	self:GFR_UpdateSight()
	if self.GFR_PM then
		local body = MakeBody(self, self.GFR_ForceModel, self.GFR_ForceSkin, self.GFR_ForceBodygroups,
			self.GFR_ForceTint or skinTint, self.GFR_ForceColor or Vector(math.Rand(0.1, 0.4), math.Rand(0.1, 0.4), math.Rand(0.1, 0.4)))
		if IsValid(body) then
			self.Bonemerge = body
			Hide(self)
		else
			self.GFR_PM = nil -- not a Valve-skeleton model: just stay an L4D infected
		end
	end
	self.GFR_NextGrabT = CurTime() + math.Rand(1, 4)
	-- Removed while holding someone (cleanup, despawn): let them go
	self:CallOnRemove("GFR_InfectedRelease", function(ent)
		if ent.GOTDR_CurEnt then ent:ResetGrapple() end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Walkers and runners mixed: a few run by day, more at night (gfr_day_runner_chance / gfr_night_runner_chance,
-- sv_spawner.lua). Each one rolls once, so a runner stays a runner and some walkers start running when night falls.
function ENT:GFR_Runner()
	if self.RTRG_LegGone then return false end
	if self.RTRG_ForceRunner then return true end
	if self.GFR_ChaseRun then return true end -- (a player's zombie the AI is driving, going for someone: sv_zombiehunger.lua)
	local night = GFR && GFR.IsNight && GFR.IsNight() or false
	local cv = !self.GFR_ControlPlayer && GetConVar(night and "gfr_night_runner_chance" or "gfr_day_runner_chance")
	if !cv then return night end -- (a player's zombie, or no gamemode: run at night)
	self.GFR_RunRoll = self.GFR_RunRoll or math.Rand(0, 100)
	return self.GFR_RunRoll < cv:GetFloat()
end

local baseTranslate = ENT.TranslateActivity
--
function ENT:TranslateActivity(act)
	if act == ACT_RUN && !self:GFR_Runner() && !self:IsOnFire() then act = ACT_WALK end
	-- Driven by a player: under the VJ controller it's always "in combat" (the aim point is its enemy), so the L4D code
	-- would only ever use the one alert idle. Standing, it uses the neutral ones instead: Idle_Neutral_01-08 and the two
	-- crouched ones all share ACT_IDLE, and VJ picks a new one at random each time one plays out.
	if act == ACT_IDLE && self.VJ_IsBeingControlled && (self.Zombie_IdleState or 0) == 0 && !self:IsOnFire() then return ACT_IDLE end
	-- Leaning on a wall (crouch next to one, sv_extract.lua): our own idle state 3, unknown to the L4D code
	if act == ACT_IDLE && self.Zombie_IdleState == 3 && self.GFR_LeanAct then return self.GFR_LeanAct end
	return baseTranslate(self, act)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Retching (Idle_Neutral_04 / 05's "event_vomit"): instead of the L4D pack's bile, it brings up blood - dark red and the
-- Green Flu's sick green-yellow - in a few heaves, splattering the ground under its face
local baseOnInput = ENT.OnInput
--
function ENT:OnInput(key, activator, caller, data)
	if key != "event_vomit" then return baseOnInput(self, key, activator, caller, data) end
	if self.GFR_NextPuke && self.GFR_NextPuke > CurTime() then return end
	self.GFR_NextPuke = CurTime() + 0.6
	local att = self:LookupAttachment("mouth")
	if att <= 0 then att = 9 end
	VJ.EmitSound(self, "npc/zombie_poison/pz_throw" .. math.random(2, 3) .. ".wav", 62, math.random(80, 95))
	for i = 0, 5 do
		timer.Simple(i * 0.12, function()
			if !IsValid(self) or self.Dead then return end
			local a = self:GetAttachment(att)
			if !a then return end
			local dir = a.Ang:Forward() * 0.6 + Vector(0, 0, -1)
			dir:Normalize()
			for _, color in ipairs({BLOOD_COLOR_RED, BLOOD_COLOR_RED, BLOOD_COLOR_YELLOW}) do
				local ed = EffectData()
				ed:SetOrigin(a.Pos)
				ed:SetNormal(dir)
				ed:SetColor(color)
				ed:SetScale(6)
				ed:SetFlags(3)
				util.Effect("bloodspray", ed)
			end
			if i % 2 == 0 then
				local tr = util.TraceLine({start = a.Pos, endpos = a.Pos + dir * 90, filter = {self, self.Bonemerge}})
				if tr.Hit then
					util.Decal(math.random(3) == 1 and "YellowBlood" or "Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
				end
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Puppet: the body shown on the GOTDR rig while it grabs, eats or crawls
function ENT:GFR_PuppetStart(loopSeq, introSeq)
	if !util.IsValidModel(RIG) then return false end
	local p = self.GFR_Puppet
	if !p then
		local rig = ents.Create("prop_dynamic")
		if !IsValid(rig) then return false end
		rig:SetModel(RIG)
		rig:SetPos(self:GetPos())
		rig:SetAngles(Angle(0, self:GetAngles().y, 0))
		rig:SetKeyValue("DefaultAnim", loopSeq)
		rig:SetKeyValue("solid", "0")
		rig:Spawn()
		rig:SetParent(self)
		Hide(rig, true)
		self:DeleteOnRemove(rig)
		local body, own = self.Bonemerge, false
		if IsValid(body) then
			body:SetParent(rig)
			body:AddEffects(EF_BONEMERGE)
		else
			local bgs = {}
			for i = 0, self:GetNumBodyGroups() - 1 do bgs[i] = self:GetBodygroup(i) end
			body = MakeBody(rig, self:GetModel(), self:GetSkin(), bgs)
			own = true
			if !IsValid(body) then rig:Remove() return false end
			Hide(self)
		end
		p = {rig = rig, body = body, own = own}
		self.GFR_Puppet = p
	end
	p.rig:Fire("SetDefaultAnimation", loopSeq)
	p.rig:Fire("SetAnimation", introSeq or loopSeq)
	p.loop = loopSeq
	p.intro = introSeq
	-- When the intro has played through: by the clock. Some of GMod of the Dead's intros (eating01_to_start) are
	-- flagged as looping in its model, so on the rig they wrap round instead of ending - waiting to catch their last
	-- few frames (checked 10 times a second) usually missed, and the intro just kept repeating (the body never got
	-- past the start of sitting down to eat).
	local introId = introSeq && p.rig:LookupSequence(introSeq) or -1
	p.introEnds = introId >= 0 and (CurTime() + p.rig:SequenceDuration(introId) - 0.05) or nil
	-- GOTDR's other loops (crawl...) aren't all flagged as looping (its own code repeats them): on a prop_dynamic they'd
	-- play once and freeze, so those get restarted when they run out.
	local id = "GFR_PuppetLoop" .. self:EntIndex()
	if !timer.Exists(id) then
		timer.Create(id, 0.05, 0, function()
			local cur = IsValid(self) && self.GFR_Puppet
			if !cur or !IsValid(cur.rig) then timer.Remove(id) return end
			local rig = cur.rig
			if !cur.loop then return end
			if cur.intro then
				if cur.introEnds && CurTime() < cur.introEnds then return end
				rig:Fire("SetAnimation", cur.loop)
				cur.intro, cur.introEnds = nil, nil
				return
			end
			if rig:GetCycle() >= 0.95 && rig:GetSequence() == rig:LookupSequence(cur.loop) then rig:Fire("SetAnimation", cur.loop) end
		end)
	end
	return true
end

-- Back to the normal body (crawlers stay on the rig, just crawling again)
function ENT:GFR_PuppetEnd(force)
	local p = self.GFR_Puppet
	if !p then return end
	if self.GFR_Crawl && !force && !self.Dead then
		self:GFR_PuppetStart(self:IsMoving() and "crawl" or "crawlidle")
		return
	end
	self.GFR_Puppet = nil
	if p.own then
		if IsValid(p.body) then p.body:Remove() end
		if !self.GFR_PM then Show(self) end
	elseif IsValid(p.body) then
		p.body:SetParent(self)
		p.body:AddEffects(EF_BONEMERGE)
	end
	if IsValid(p.rig) then p.rig:Remove() end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Grab: holds you and bites. Mash E to shove it off (counted in sv hook below), J gives in (sv_extract.lua)

local function CanGrab(ent)
	if !IsValid(ent) or ent.GOTDR_Grappled then return false end
	if ent:IsPlayer() then
		return ent:Alive() && !ent.GFR_IsZombie && !ent:InVehicle() && ent:GetMoveType() == MOVETYPE_WALK
	end
	return ent:IsNPC() && ent:Health() > 0 && ent:LookupBone("ValveBiped.Bip01_Pelvis") != nil && !(GFR && GFR.IsZombie && GFR.IsZombie(ent))
end

function ENT:GFR_CanGrab(ent) return CanGrab(ent) end

-- A player driving it: right click grabs whoever's in front of it (sv_extract.lua)
function ENT:GFR_TryGrab(aimDir)
	if self.GOTDR_CurEnt or self.VJ_ST_Eating or self.GFR_Crawl or self.GFR_NoArms or CurTime() < (self.GFR_NextGrabT or 0) then return false end
	if self.GetState && self:GetState() != VJ_STATE_NONE then return false end
	local best, bestScore
	local from = self:GetPos() + Vector(0, 0, 40)
	for _, ent in ipairs(ents.FindInSphere(self:GetPos(), 90)) do
		if ent != self && CanGrab(ent) then
			local to = ent:WorldSpaceCenter() - from
			local dot = to:GetNormalized():Dot(aimDir)
			if dot > 0.4 then
				local score = dot - to:Length() / 200
				if !best or score > bestScore then best, bestScore = ent, score end
			end
		end
	end
	if !best then return false end
	self:GFR_StartGrab(best)
	return true
end

function ENT:GFR_StartGrab(victim)
	self.GOTDR_CurEnt = victim
	victim.GOTDR_Grappled = true
	victim.GFR_GrabbedBy = self
	victim.GFR_GrabMash = 0
	self:StopMoving()
	self:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK)
	local yaw = (victim:GetPos() - self:GetPos()):Angle().y
	self:SetAngles(Angle(0, yaw, 0))
	self:GFR_PuppetStart("choke_eating", "enter_choke")
	VJ.EmitSound(self, "vj_gotdr/shared/melee/zombie_bite" .. math_random(1, 3) .. ".wav", 75)
	if victim:IsPlayer() then
		self.GFR_VictimMoveType = victim:GetMoveType()
		victim:SetMoveType(MOVETYPE_NONE)
		victim:SetVelocity(-victim:GetVelocity())
		victim:SetEyeAngles(Angle(0, yaw + 180, 0))
		victim:ViewPunch(Angle(-8, math.Rand(-6, 6), 0))
	elseif victim.IsVJBaseSNPC then
		victim:StopMoving()
		victim:SetState(VJ_STATE_ONLY_ANIMATION)
	else
		victim:SetSchedule(SCHED_NPC_FREEZE)
	end
	-- Bites while it holds on - and it doesn't let go by itself: you shove it off (mash E), hit it hard enough to knock
	-- it back, or it kills you
	local id = "GFR_InfGrab" .. self:EntIndex()
	timer.Create(id, 1.1, 0, function()
		if !IsValid(self) or self.GOTDR_CurEnt != victim then timer.Remove(id) return end
		if !IsValid(victim) or (victim:IsPlayer() and !victim:Alive()) or (victim:IsNPC() and victim:Health() <= 0) then
			self:ResetGrapple()
			return
		end
		local dmg = DamageInfo()
		dmg:SetDamage(math_random(6, 10))
		dmg:SetDamageType(DMG_SLASH)
		dmg:SetAttacker(self)
		dmg:SetInflictor(self)
		dmg:SetDamagePosition(victim:EyePos() - Vector(0, 0, 8))
		victim:TakeDamageInfo(dmg)
		VJ.EmitSound(self, "vj_gotdr/shared/melee/zombie_bite" .. math_random(1, 3) .. ".wav", 75)
		local fx = EffectData()
		fx:SetOrigin(victim:EyePos() - Vector(0, 0, 10))
		util.Effect("BloodImpact", fx)
		if victim:IsPlayer() then victim:ViewPunch(Angle(math.Rand(-6, 2), math.Rand(-5, 5), 0)) end
	end)
end

-- Knocked off someone: the shove that matches where the push came from (backward, forward, to either side), and
-- slamming into the wall if there's one right there
local shoveAnims = {
	back = {"Shoved_Backward_01", "Shoved_Backward_02", "Shoved_Backward_03", "Shoved_Backward_03a", "Shoved_Backward_04e",
		"Shoved_Backward_04g", "Shoved_Backward_04i", "Shoved_Backward_04j", "Shoved_Backward_04m", "Shoved_Backward_04o"},
	backWall = {"Shoved_Backward_IntoWall_01", "Shoved_Backward_IntoWall_02", "Shoved_Backward_IntoWall_03", "Shoved_Backward_IntoWall_04"},
	fwd = {"Shoved_Forward_01"}, fwdWall = {"Shoved_Forward_IntoWall_02"},
	left = {"Shoved_Leftward_01"}, leftWall = {"Shoved_Leftward_IntoWall_02"},
	right = {"Shoved_Rightward_01"}, rightWall = {"Shoved_Rightward_IntoWall_01"}
}
-- push: the way it's being pushed (world direction), or true for "straight back"
function ENT:GFR_Shove(push)
	local d = isvector(push) and Vector(push.x, push.y, 0) or -self:GetForward()
	if d:LengthSqr() < 0.01 then d = -self:GetForward() end
	d:Normalize()
	local f, r = d:Dot(self:GetForward()), d:Dot(self:GetRight())
	local kind = (f < -0.5 and "back") or (f > 0.5 and "fwd") or (r > 0 and "right") or "left"
	local from = self:WorldSpaceCenter()
	local tr = util.TraceLine({start = from, endpos = from + d * 50, filter = {self, self.Bonemerge}, mask = MASK_SOLID_BRUSHONLY})
	local list = (tr.Hit && shoveAnims[kind .. "Wall"]) or shoveAnims[kind]
	self:PlayAnim("vjseq_" .. list[math_random(#list)], true, false, false)
end

-- Let go (also called by the gamemode: giving in, death). shoved: true or the direction it was pushed (GFR_Shove)
function ENT:ResetGrapple(shoved)
	local victim = self.GOTDR_CurEnt
	self.GOTDR_CurEnt = nil
	timer.Remove("GFR_InfGrab" .. self:EntIndex())
	if IsValid(victim) then
		victim.GOTDR_Grappled = false
		victim.GFR_GrabbedBy = nil
		if victim:IsPlayer() then
			if victim:GetMoveType() == MOVETYPE_NONE then victim:SetMoveType(self.GFR_VictimMoveType or MOVETYPE_WALK) end
		elseif victim.IsVJBaseSNPC then
			victim:SetState()
		elseif victim:IsNPC() then
			victim:SetSchedule(SCHED_IDLE_STAND)
		end
	end
	if !IsValid(self) or self.Dead then return end
	self:GFR_PuppetEnd()
	self:SetState()
	self.GFR_NextGrabT = CurTime() + math.Rand(4, 7)
	if shoved then
		-- (no direction given: away from whoever it had hold of)
		if !isvector(shoved) && IsValid(victim) then shoved = self:GetPos() - victim:GetPos() end
		self:GFR_Shove(shoved)
	end
end

function ENT:OnMeleeAttack(status, enemy)
	if status == "PreInit" then
		if self.GOTDR_CurEnt or self.VJ_ST_Eating or self.GFR_ScriptFeed then return true end
		if (self.GFR_BusyUntil or 0) > CurTime() or (self.GFR_TurnUntil or 0) > CurTime() then return true end
		if self.GFR_Crawl then
			if self.GFR_Puppet then self.GFR_Puppet.rig:Fire("SetAnimation", "crawl_attack") end
			return
		end
		-- (Driven by a player: attack is always a swipe, right click grabs: sv_extract.lua)
		if !self.VJ_IsBeingControlled && !self.GFR_NoArms && CurTime() > (self.GFR_NextGrabT or 0) && math.Rand(0, 100) < cvGrab:GetFloat() && CanGrab(enemy)
			&& self:GetPos():DistToSqr(enemy:GetPos()) < 80 * 80 then
			self:GFR_StartGrab(enemy)
			return true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Legs: enough damage to one takes it off below the knee, and it crawls from then on
local legBones = {[HITGROUP_LEFTLEG] = "ValveBiped.Bip01_L_Calf", [HITGROUP_RIGHTLEG] = "ValveBiped.Bip01_R_Calf"}
local legGibs = {[HITGROUP_LEFTLEG] = "ll", [HITGROUP_RIGHTLEG] = "rl"}
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

local function Splatter(pos)
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
end

-- The severed piece flying off (Custom Apocalypse: sv_rise.lua GFR.LimbGib, with the gore setting)
local function FlyingGib(kind, pos, force)
	if GFR && GFR.LimbGib then GFR.LimbGib(kind, pos, force) end
end

-- quiet = no splatter/fall (a body getting back up that was already missing it). force: the hit, for the gib
function ENT:RTRG_LoseLeg(hitgroup, quiet, force)
	if self.RTRG_LegGone or !legBones[hitgroup] then return end
	self.RTRG_LegGone = hitgroup
	if cvGore:GetBool() then
		if self.GFR_PM then HideBone(self.Bonemerge, legBones[hitgroup]) else self:Zombie_Gibs(legGibs[hitgroup]) end
	end
	if !quiet && cvGore:GetBool() then
		local at = BonePos(self, legBones[hitgroup])
		Splatter(at)
		FlyingGib(legGibs[hitgroup], at, force)
	end
	if self.GOTDR_CurEnt then self:ResetGrapple() end
	self.GFR_Crawl = true
	self.AnimationPlaybackRate = 0.45 -- drags itself along
	self:GFR_PuppetStart("crawlidle", !quiet and "nz_death_f_7" or nil)
end

-- Arms: enough damage to one takes it off at the elbow. One gone: its hits are weaker; both: weaker still, and it
-- can't grab anyone (GFR_NoArms)
local armBones = {[HITGROUP_LEFTARM] = "ValveBiped.Bip01_L_Forearm", [HITGROUP_RIGHTARM] = "ValveBiped.Bip01_R_Forearm"}
local armGibs = {[HITGROUP_LEFTARM] = "la", [HITGROUP_RIGHTARM] = "ra"}

function ENT:GFR_LoseArm(hitgroup, quiet, force)
	self.GFR_ArmGone = self.GFR_ArmGone or {}
	if self.GFR_ArmGone[hitgroup] or !armBones[hitgroup] then return end
	self.GFR_ArmGone[hitgroup] = true
	if cvGore:GetBool() then
		if self.GFR_PM then HideBone(self.Bonemerge, armBones[hitgroup]) else self:Zombie_Gibs(armGibs[hitgroup]) end
		if !quiet then
			local at = BonePos(self, armBones[hitgroup])
			Splatter(at)
			FlyingGib(armGibs[hitgroup], at, force)
		end
	end
	self.GFR_BaseMeleeDmg = self.GFR_BaseMeleeDmg or self.MeleeAttackDamage
	local n = table.Count(self.GFR_ArmGone)
	if isnumber(self.GFR_BaseMeleeDmg) then
		self.MeleeAttackDamage = math.max(math.Round(self.GFR_BaseMeleeDmg * (n >= 2 and 0.35 or 0.65)), 1)
	end
	if n >= 2 then
		self.GFR_NoArms = true
		if self.GOTDR_CurEnt then self:ResetGrapple() end
	end
end

local legDamageTypes = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_SLASH, DMG_CLUB, DMG_BLAST)
local baseOnDamaged = ENT.OnDamaged

-- The engine only records hitgroups for bullets; Custom Apocalypse works out melee head hits (sv_rise.lua)
local function RealHitgroup(self, dmginfo, hitgroup)
	local hg = GFR && GFR.DamageHitgroup && GFR.DamageHitgroup(self, dmginfo)
	return hg or hitgroup
end
--
function ENT:OnDamaged(dmginfo, hitgroup, status)
	hitgroup = RealHitgroup(self, dmginfo, hitgroup)
	-- Hurt while sitting (crouch, sv_extract.lua): it gets up (the L4D code's quick stand)
	if self.GFR_ManualSit && status == "PreDamage" then
		self.GFR_ManualSit = nil
		self:SetNW2Bool("GFR_ZSitting", false)
		self.Zombie_IdleStandT = 0
	end
	local ret = baseOnDamaged(self, dmginfo, hitgroup, status)
	if status != "PostDamage" or self.Dead or self:Health() <= 0 then return ret end
	-- A hard hit makes it let go of whoever it's holding
	-- (knocked the way the hit came from: away from whoever hit it)
	if self.GOTDR_CurEnt && dmginfo:GetDamage() >= 20 then
		local att = dmginfo:GetAttacker()
		local force = dmginfo:GetDamageForce()
		self:ResetGrapple(force:LengthSqr() > 1 and force or (IsValid(att) and self:GetPos() - att:GetPos()) or true)
	end
	if !self.RTRG_LegGone && bit.band(dmginfo:GetDamageType(), legDamageTypes) != 0 then
		local limit = cvLegHP:GetFloat()
		if limit > 0 then
			if legBones[hitgroup] then
				self.RTRG_LegDmg = (self.RTRG_LegDmg or 0) + dmginfo:GetDamage()
				if self.RTRG_LegDmg >= limit then self:RTRG_LoseLeg(hitgroup, false, dmginfo:GetDamageForce()) end
			elseif dmginfo:IsExplosionDamage() && dmginfo:GetDamage() >= limit && math_random(3) == 1 then
				self:RTRG_LoseLeg(math_random(2) == 1 and HITGROUP_LEFTLEG or HITGROUP_RIGHTLEG, false, dmginfo:GetDamageForce())
			end
		end
	end
	if armBones[hitgroup] && bit.band(dmginfo:GetDamageType(), legDamageTypes) != 0 && !(self.GFR_ArmGone && self.GFR_ArmGone[hitgroup]) then
		local limit = cvArmHP:GetFloat()
		if limit > 0 then
			self.GFR_ArmDmg = self.GFR_ArmDmg or {}
			self.GFR_ArmDmg[hitgroup] = (self.GFR_ArmDmg[hitgroup] or 0) + dmginfo:GetDamage()
			if self.GFR_ArmDmg[hitgroup] >= limit then self:GFR_LoseArm(hitgroup, false, dmginfo:GetDamageForce()) end
		end
	end
	return ret
end

-- Sight range: shorter at night (cvSight / cvSightNight); a zombie a player drives sees as far as VJ likes
function ENT:GFR_UpdateSight()
	if self.VJ_IsBeingControlled or self.GFR_ControlPlayer then return end
	local night = GFR && GFR.IsNight && GFR.IsNight()
	local d = night and cvSightNight:GetFloat() or cvSight:GetFloat()
	if self.SightDistance != d then
		self.SightDistance = d
		self:SetMaxLookDistance(d)
	end
end

-- The VJ controller orders "idle stand" every tick you're not moving, which would cut the sit-down animation short:
-- ignored until that's played out. After that it's what plays the seated idle loop (the L4D code turns "idle" into
-- its sitting animation while Zombie_IdleState is sitting), so it goes through again.
-- (Lying down works the same way: Zombie_IdleState 2, standing_to_lying03 and the lying idle)
local getDown = {standing_to_sitting03 = true, standing_to_lying03 = true}
local function GettingDown(self)
	return getDown[string.lower(self:GetSequenceName(self:GetSequence()) or "")] && self:GetCycle() < 0.95
end

local baseIdleStand
function ENT:SCHEDULE_IDLE_STAND(...)
	if self.GFR_ManualSit && GettingDown(self) then return end
	if (self.GFR_LungeUntil or 0) > CurTime() then return end -- (a feral lunge: sv_zombiehunger.lua)
	-- Lost to the hunger, it's hunting on its own (sv_zombiehunger.lua): the controller's order cancelled each new walk
	-- before it got going (walk a little, stop, again)
	if self.GFR_AIDriven then return end
	if (self.GFR_TurnUntil or 0) > CurTime() then return end -- (turning on the spot: GFR_TurnInPlace)
	if (self.GFR_BusyUntil or 0) > CurTime() then return end -- (clawing at someone down / pounding on a door)
	if !baseIdleStand then
		local base = scripted_ents.Get(self.Base or "npc_vj_creature_base")
		baseIdleStand = base && base.SCHEDULE_IDLE_STAND
	end
	if baseIdleStand then return baseIdleStand(self, ...) end
end

-- The retching idles (Idle_Neutral_04 / 05, blood: OnInput above) come up 1 in 5 standing idles: most of the time one
-- starts, it's skipped to its end so VJ picks another idle straight away
local PUKE_KEEP = 0.25 -- chance a retching idle that came up actually plays
local function SkipPuke(self)
	if !self.GFR_PukeSeqs then
		self.GFR_PukeSeqs = {}
		for _, n in ipairs({"Idle_Neutral_04", "Idle_Neutral_05"}) do
			local s = self:LookupSequence(n)
			if s >= 0 then self.GFR_PukeSeqs[s] = true end
		end
	end
	local seq = self:GetSequence()
	if !self.GFR_PukeSeqs[seq] then self.GFR_PukeRolled = nil return end
	-- (already rolled for this one - unless we skipped it and the same one came up again from the start)
	if self.GFR_PukeRolled == seq && !(self.GFR_PukeSkipped && self:GetCycle() < 0.5) then return end
	self.GFR_PukeRolled = seq
	self.GFR_PukeSkipped = math.random() > PUKE_KEEP && self:GetCycle() < 0.3
	if self.GFR_PukeSkipped then self:SetCycle(0.99) end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Turning on the spot (the L4D turn shuffles). The turn in them is root motion VJ never applies, so the body is
-- turned here along each one's own curve (frame -> degrees, read from the model) while it plays.
local turnAnims = {
	right = {{"Idle_Neutral_Turn_Right", 92, {{0, 0}, {25, -29.8}, {56, -104.9}, {91, -112.8}}}},
	left = {{"Idle_Neutral_Turn_Left", 113, {{0, 0}, {15, 26.9}, {30, 57}, {64, 101.7}, {82, 95}, {112, 96.8}}}},
	around = {
		{"Idle_Neutral_Turn_Around_01a", 98, {{0, 0}, {70, -197.3}, {97, -197.3}}},
		{"Idle_Neutral_Turn_Around_01b", 124, {{0, 0}, {13, 24.1}, {35, 56.6}, {50, 67.2}, {85, 162.8}, {123, 157.7}}},
		{"Idle_Neutral_Turn_Around_01c", 114, {{0, 0}, {82, -185.2}, {113, -160.4}}}
	}
}

local function CurveAt(curve, frame)
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if frame <= b[1] then return Lerp((frame - a[1]) / math.max(b[1] - a[1], 1), a[2], b[2]) end
	end
	return curve[#curve][2]
end

function ENT:GFR_CanShuffle()
	return !self:IsMoving() && (self.Zombie_IdleState or 0) == 0 && !self.GFR_Puppet && !self.GFR_Crawl && !self.GOTDR_CurEnt
		&& !self.VJ_ST_Eating && !self.GFR_ScriptFeed && !self.GFR_ManualSit && (self.GFR_TurnUntil or 0) < CurTime()
		&& (self.GFR_BusyUntil or 0) < CurTime() && (!self.GetState or self:GetState() == VJ_STATE_NONE) && !self:IsOnFire()
end

-- Turns to face yaw with the right shuffle (left, right, or all the way round). False if it's near enough already.
function ENT:GFR_TurnInPlace(yaw)
	local delta = math.AngleDifference(yaw, self:GetAngles().y)
	if math.abs(delta) < 70 then return false end
	local list = math.abs(delta) > 135 and turnAnims.around or (delta > 0 and turnAnims.left or turnAnims.right)
	local pick = list[math_random(#list)]
	local seq = self:LookupSequence(pick[1])
	if seq < 0 then return false end
	local dur = self:SequenceDuration(seq)
	local frames, curve = pick[2], pick[3]
	local total = curve[#curve][2]
	-- (turns its own way: scaled so it ends facing where it should, whichever way the shuffle goes round)
	local want = (math.abs(delta) > 135 && (total > 0) != (delta > 0)) and (delta > 0 and delta - 360 or delta + 360) or delta
	local scale = want / total
	local yaw0, t0 = self:GetAngles().y, CurTime()
	self.GFR_TurnUntil = t0 + dur
	self:PlayAnim("vjseq_" .. pick[1], true, dur, false)
	local id = "GFR_Turn" .. self:EntIndex()
	timer.Create(id, 0, 0, function()
		if !IsValid(self) or self.Dead then timer.Remove(id) return end
		local t = (CurTime() - t0) / dur
		-- (cut short - it set off walking, got grabbed, died...)
		if t >= 1 or self:IsMoving() or self.GOTDR_CurEnt or self.GFR_Puppet then
			timer.Remove(id)
			self.GFR_TurnUntil = 0
			if t >= 1 then self:SetAngles(Angle(0, yaw0 + want, 0)) end
			return
		end
		self:SetAngles(Angle(0, yaw0 + CurveAt(curve, t * (frames - 1)) * scale, 0))
	end)
	return true
end

-- Your zombie: standing still and looking well away from where it faces, it shuffles round to face that way (VJ's
-- controller doesn't turn it on the spot, it just slid round when you started walking)
local function PlayerTurn(self)
	local bull = self.VJ_TheControllerBullseye
	if !IsValid(bull) or self.GFR_AIDriven or !self:GFR_CanShuffle() then self.GFR_TurnWantT = nil return end
	-- (over the shoulder only: on the full-body or first-person camera it doesn't follow where you look)
	local ply = self.GFR_ControlPlayer
	if IsValid(ply) && ply:GetInfoNum("gfr_zcam_mode", 0) != 0 then self.GFR_TurnWantT = nil return end
	local yaw = (bull:GetPos() - self:GetPos()):Angle().y
	if math.abs(math.AngleDifference(yaw, self:GetAngles().y)) < 75 then self.GFR_TurnWantT = nil return end
	-- (looked away for a moment, not just flicking the mouse past)
	self.GFR_TurnWantT = self.GFR_TurnWantT or CurTime()
	if CurTime() - self.GFR_TurnWantT > 0.35 then
		self.GFR_TurnWantT = nil
		self:GFR_TurnInPlace(yaw)
	end
end

-- The dead: one that notices someone behind it (a new target) turns round to them before going
local function AITurn(self)
	local ene = self:GetEnemy()
	local had = self.GFR_HadEnemy
	self.GFR_HadEnemy = IsValid(ene) && ene or nil
	if !IsValid(ene) or ene == had or !self:GFR_CanShuffle() then return end
	local yaw = (ene:GetPos() - self:GetPos()):Angle().y
	if math.abs(math.AngleDifference(yaw, self:GetAngles().y)) > 110 then self:GFR_TurnInPlace(yaw) end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Doors and barricades in the way: chasing someone and stuck behind one, it pounds on it. Barricades take the damage
-- (sv_crafting.lua keeps their health); a door gives way after a few blows.
local doorClasses = {prop_door_rotating = true, func_door_rotating = true, func_door = true}
local DOOR_HITS = 7

-- Something to pound on between it and who it's after (or right in front of it)
local function Blocker(self, ene)
	local from = self:WorldSpaceCenter()
	for _, dir in ipairs({ene:GetPos() - self:GetPos(), self:GetForward()}) do
		dir.z = 0
		dir:Normalize()
		local tr = util.TraceHull({start = from, endpos = from + dir * 60, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8),
			filter = {self, self.Bonemerge}, mask = MASK_NPCSOLID})
		local e = tr.Entity
		if IsValid(e) && (doorClasses[e:GetClass()] or e.GFR_BarricadeHP) then return e, dir end
	end
end

local function Pound(self)
	if self.VJ_IsBeingControlled or self.GFR_AIDriven then return end
	-- (not GFR_CanShuffle: stuck against a door it may still count as "moving", trying to path through)
	if (self.Zombie_IdleState or 0) != 0 or self.GFR_Puppet or self.GFR_Crawl or self.GOTDR_CurEnt or self.VJ_ST_Eating
		or self.GFR_ScriptFeed or (self.GFR_TurnUntil or 0) > CurTime() or (self.GFR_BusyUntil or 0) > CurTime() then return end
	local ene = self:GetEnemy()
	local now = CurTime()
	-- Stuck while chasing: hasn't got anywhere for a second and a half
	if !IsValid(ene) or ene:GetPos():DistToSqr(self:GetPos()) < 110 * 110 then self.GFR_StuckAt = nil return end
	local pos = self:GetPos()
	if !self.GFR_StuckAt or pos:DistToSqr(self.GFR_StuckAt) > 20 * 20 then self.GFR_StuckAt, self.GFR_StuckT = pos, now return end
	if now - self.GFR_StuckT < 1.5 then return end
	local target, dir = Blocker(self, ene)
	if !target then return end
	local seq = "AttackDoor_01"
	self.GFR_BusyUntil = now + 1.4
	self:StopMoving()
	self:SetAngles(Angle(0, dir:Angle().y, 0))
	self:PlayAnim("vjseq_" .. seq, true, 1.4, false)
	timer.Simple(0.5, function()
		if !IsValid(self) or self.Dead or !IsValid(target) then return end
		target:EmitSound("npc/zombie/zombie_pound_door.wav", 80, math_random(90, 110))
		util.ScreenShake(target:GetPos(), 2, 6, 0.4, 300)
		if target.GFR_BarricadeHP then
			target:TakeDamage(math_random(10, 16), self, self)
		else
			target.GFR_ZombieHits = (target.GFR_ZombieHits or 0) + 1
			if target.GFR_ZombieHits >= DOOR_HITS then
				target.GFR_ZombieHits = 0
				target:Fire("Unlock")
				target:Fire("OpenAwayFrom", "!activator", 0, self, self)
				target:Fire("Open", "", 0.05, self, self)
				target:EmitSound("physics/wood/wood_crate_break" .. math_random(1, 5) .. ".wav", 80)
			end
		end
	end)
end

local baseThink = ENT.OnThinkActive
--
function ENT:OnThinkActive()
	SkipPuke(self)
	if self.VJ_IsBeingControlled then PlayerTurn(self) else AITurn(self) Pound(self) end
	-- VJ twists its body and head toward its target (pose parameters) - for your zombie the target is the marker under
	-- your cursor, so it twisted after the mouse. Only over the shoulder; on the full-body / first-person camera it
	-- eases back straight and stays that way.
	local ply = self.GFR_ControlPlayer
	if IsValid(ply) then
		local look = ply:GetInfoNum("gfr_zcam_mode", 0) == 0
		self.HasPoseParameterLooking = look
		if !look then
			for _, p in ipairs({"body_yaw", "body_pitch", "lean_yaw", "lean_pitch"}) do
				local v = self:GetPoseParameter(p)
				if v != 0 then self:SetPoseParameter(p, math.Approach(v, 0, 3)) end
			end
		end
	end
	-- Hunched over a body (its own eating, or yours: E): held where it went down, so it doesn't slide about under the meal
	if self.VJ_ST_Eating && self.GFR_Puppet && !self.GFR_Crawl then
		local hold = self.GFR_EatHoldPos
		if !hold then
			self.GFR_EatHoldPos = self:GetPos()
		elseif self:GetPos():DistToSqr(hold) > 4 then
			self:StopMoving()
			self:SetPos(hold)
			self:SetLocalVelocity(vector_origin)
		end
	else
		self.GFR_EatHoldPos = nil
	end
	if (self.GFR_NextSight or 0) < CurTime() then
		self.GFR_NextSight = CurTime() + 5
		self:GFR_UpdateSight()
	end
	-- A player driving it (self-injected extract) shouldn't have it sit down on them
	if self.VJ_IsBeingControlled then self.Zombie_IdleStateChangeT = CurTime() + 999 end
	-- Keep the hidden body hidden (fire effects etc. can reset the material)
	if self.GFR_Hidden && self:GetMaterial() != INVISIBLE then Hide(self) end
	if self.GFR_Crawl then
		-- The L4D sit/lie idles make no sense with no legs
		self.Zombie_IdleStateChangeT = CurTime() + 999
		local p = self.GFR_Puppet
		if p && !self.GOTDR_CurEnt && !self.VJ_ST_Eating then
			local want = self:IsMoving() and "crawl" or "crawlidle"
			if p.loop != want then self:GFR_PuppetStart(want) end
		end
	end
	-- Sat down by the player driving it (crouch, sv_extract.lua). The L4D sit code (baseThink) stands it up the moment
	-- it has an enemy, is moving or its sit time runs out, and under the VJ controller it always "has an enemy" (the aim
	-- point) and gets an idle-stand order every tick. So while you sit, that code doesn't run at all; you stand up by
	-- pressing crouch again (GFR_ManualSit cleared), and it plays its get-up animation then.
	if self.GFR_ManualSit then
		local idle = self.Zombie_IdleState
		if idle == 1 or idle == 2 or idle == 3 then
			self.Zombie_IdleStandT = CurTime() + 99999
			if self:GetState() != VJ_STATE_ONLY_ANIMATION then self:SetState(VJ_STATE_ONLY_ANIMATION, 99999) end
			-- Down (or leaning): keep the seated / lying / leaning idle loop playing (if the controller's idle order doesn't start it)
			local loop = idle == 3 and self.GFR_LeanAct or idle == 2 and self.ZombieAnim_IdleLying or self.ZombieAnim_IdleSitting
			if loop && self:GetSequenceActivity(self:GetSequence()) != loop && (self.GFR_NextSitIdle or 0) < CurTime() && !GettingDown(self) then
				self.GFR_NextSitIdle = CurTime() + 0.5
				self:SCHEDULE_IDLE_STAND()
			end
			return
		end
		self.GFR_ManualSit = nil
		self:SetNW2Bool("GFR_ZSitting", false) -- (got up some other way: hurt)
	end
	return baseThink(self)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Eating (VJ Base eating system); the feeding itself is GOTDR's eating01 on the puppet
local vecZ50 = Vector(0, 0, -50)

-- Scripted feeding (giving in, sv_extract.lua): drops down onto `body`, feeds on it for `duration` seconds, gets back up
-- and wanders off. onDone(self) runs when it's up (or right away if it dies / is removed first).
function ENT:GFR_FeedOn(body, duration, onDone)
	local done = false
	local function Done()
		if done then return end
		done = true
		if onDone then onDone(self) end
	end
	if !IsValid(body) or self.Dead or self:Health() <= 0 then Done() return end
	self.GFR_ScriptFeed = body
	self:CallOnRemove("GFR_ScriptFeed", Done)
	if self.GOTDR_CurEnt then self:ResetGrapple() end
	self:StopMoving()
	self:ClearSchedule() -- (a walk it was on - running over to a pushed survivor - mustn't carry on under the meal)
	self:SetEnemy(NULL)
	self:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK)
	-- Pinned to the spot while it feeds: nothing (a leftover path, the AI turning, others bumping it) slides it about
	local feedPos = self:GetPos()
	local holdId = "GFR_FeedHold" .. self:EntIndex()
	timer.Create(holdId, 0.1, 0, function()
		if !IsValid(self) or self.GFR_ScriptFeed != body then timer.Remove(holdId) return end
		if self:GetPos():DistToSqr(feedPos) > 4 then
			self:StopMoving()
			self:SetPos(feedPos)
			self:SetLocalVelocity(vector_origin)
		end
	end)
	local yaw = (body:GetPos() - self:GetPos()):Angle().y
	self:SetAngles(Angle(0, yaw, 0))
	VJ.EmitSound(self, "vj_cncr/eating/Eating_Begin" .. math_random(1, 2) .. ".wav", 70)
	if !self.GFR_Crawl then self:GFR_PuppetStart("eating01", "eating01_to_start") end

	local id = "GFR_ScriptFeed" .. self:EntIndex()
	local ends = CurTime() + duration
	timer.Create(id, 2.2, 0, function()
		if !IsValid(self) or self.Dead or self:Health() <= 0 then timer.Remove(id) Done() return end
		if !IsValid(body) or CurTime() >= ends then
			timer.Remove(id)
			self.GFR_ScriptFeed = nil
			-- Gets up off the body (the whole get-up animation), then wanders off
			local function Leave()
				if !IsValid(self) or self.Dead then return end
				self:SetState()
				local from = IsValid(body) and body:GetPos() or self:GetPos()
				local away = (self:GetPos() - from)
				away.z = 0
				if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
				self:SetLastPosition(self:GetPos() + away:GetNormalized() * math.Rand(350, 600))
				self:SCHEDULE_GOTO_POSITION("TASK_WALK_PATH")
				Done()
			end
			local p = self.GFR_Puppet
			if p && IsValid(p.rig) && !self.GFR_Crawl then
				local s = p.rig:LookupSequence("eating01_to_stand")
				local dur = s >= 0 and p.rig:SequenceDuration(s) or 1.3
				p.loop, p.intro = nil, nil
				p.rig:Fire("SetDefaultAnimation", "eating01_to_stand")
				p.rig:Fire("SetAnimation", "eating01_to_stand")
				timer.Simple(math.max(dur - 0.05, 0.3), function()
					if !IsValid(self) then return end
					self:GFR_PuppetEnd()
					Leave()
				end)
			else
				self:GFR_PuppetEnd()
				Leave()
			end
			return
		end
		-- A bite
		VJ.EmitSound(self, "vj_cncr/eating/Eating_Loop_DL" .. math_random(1, 4) .. ".wav", 70)
		local bloodPos = body:GetPos() + body:OBBCenter()
		ParticleEffect("blood_impact_red_01", bloodPos, self:GetAngles())
		local tr = util.TraceLine({start = bloodPos, endpos = bloodPos + vecZ50, filter = {body, self}})
		util.Decal("Blood", tr.HitPos + tr.HitNormal + Vector(math_random(-30, 30), math_random(-30, 30), 0), tr.HitPos - tr.HitNormal, body)
	end)
end

function ENT:OnEat(status, statusData)
	if status == "CheckFood" then
		-- Sitting / lying down to rest: the smell doesn't get it up (it'd stand straight back up, l4d_com_infected.lua)
		if (self.Zombie_IdleState or 0) != 0 or self.GFR_ScriptFeed then return false end
		-- People only: not other zombies' bodies (they may get back up), not someone turning, not a player's own body
		local food = statusData && statusData.owner
		if !IsValid(food) then return false end
		if food.GFR_ZCorpse or food.GFR_Limp or food.GFR_TurningBody or IsValid(food.GFR_PlayerBody) or food.GFR_ParasiteClaimed or IsValid(food.GFR_DraggedBy) then return false end
		-- A body is several meals: VJ finishes food when its health hits 0, and a ragdoll starts at 0
		if !food.GFR_FoodHP && food:Health() <= 0 then
			food.GFR_FoodHP = true
			food:SetHealth(60)
		end
		return true
	elseif status == "BeginEating" then
		VJ.EmitSound(self, "vj_cncr/eating/Eating_Begin" .. math_random(1, 2) .. ".wav", 65)
		if !self.GFR_Crawl then self:GFR_PuppetStart("eating01", "eating01_to_start") end
		return 1.6
	elseif status == "Eat" then
		VJ.EmitSound(self, "vj_cncr/eating/Eating_Loop_DL" .. math_random(1, 4) .. ".wav", 65)
		local food = self.EatingData.Target
		local myHP = self:Health()
		self:SetHealth(math.Clamp(myHP + 15, myHP, math.max(self:GetMaxHealth(), myHP)))
		local bloodPos = food:GetPos() + food:OBBCenter()
		ParticleEffect("blood_impact_red_01", bloodPos, self:GetAngles())
		local tr = util.TraceLine({start = bloodPos, endpos = bloodPos + vecZ50, filter = {food, self}})
		util.Decal("Blood", tr.HitPos + tr.HitNormal + Vector(math_random(-45, 45), math_random(-45, 45), 0), tr.HitPos - tr.HitNormal, food)
		-- Meat thrown down as bait (Custom Apocalypse) is gone after a few bites
		if food.GFR_Bait then
			food.GFR_BaitBites = (food.GFR_BaitBites or 0) + 1
			if food.GFR_BaitBites >= 3 then food:Remove() end
		elseif food.GFR_FoodHP then
			food:SetHealth(food:Health() - 8) -- about 8 bites (40 s) for one zombie; less when several share it
		end
		return 5
	elseif status == "StopEating" then
		local p = self.GFR_Puppet
		if statusData != "Dead" && p && !self.GFR_Crawl then
			p.rig:Fire("SetAnimation", "eating01_to_stand")
			timer.Simple(1.3, function() if IsValid(self) && !self.VJ_ST_Eating then self:GFR_PuppetEnd() end end)
			return 1.3
		end
		self:GFR_PuppetEnd()
	end
	return 0
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Getting up off the ground (turned people, risen corpses, parasite hosts)
function ENT:GFR_RiseFromGround(lieTime)
	lieTime = lieTime or math.Rand(4, 7)
	if self.GFR_Crawl then
		self:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK, lieTime)
		return
	end
	self:PlayAnim("vjseq_Lying01", true, lieTime, false)
	timer.Simple(lieTime, function()
		if IsValid(self) && !self.Dead then self:PlayAnim("vjseq_Lying_to_Standing_Alert", true, false, false) end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Death: remember how (decides whether it gets back up), and the corpse shows it
local burnTypes = bit.bor(DMG_BURN, DMG_SLOWBURN, DMG_BLAST)
local baseOnDeath = ENT.OnDeath
--
function ENT:OnDeath(dmginfo, hitgroup, status)
	if status == "Init" then
		hitgroup = RealHitgroup(self, dmginfo, hitgroup)
		if self.GOTDR_CurEnt then self:ResetGrapple() end
		self:GFR_PuppetEnd(true)
		if self.GFR_PM && IsValid(self.Bonemerge) then Hide(self) end
		self.RTRG_DeathHitgroup = hitgroup
		self.RTRG_DeathDmgType = dmginfo:GetDamageType()
		-- Head destroyed: show it, so you know this one stays down (and what's left of it flies off). Only when it really
		-- was blown apart (sv_headshots.lua GFR_HeadPopped) or taken off (a heavy blade: melee only counts as the head
		-- then) - finished by an ordinary headshot it keeps its head, and still stays down
		self.GFR_HeadIntact = hitgroup == HITGROUP_HEAD && dmginfo:IsBulletDamage() && !self.GFR_HeadPopped
		if hitgroup == HITGROUP_HEAD && !self.GFR_HeadIntact && cvGore:GetBool() then
			self:Zombie_Gibs("h")
			FlyingGib("h", BonePos(self, "ValveBiped.Bip01_Head1"), dmginfo:GetDamageForce())
		end
	end
	return baseOnDeath(self, dmginfo, hitgroup, status)
end

-- The L4D pack's own death gibs (a hard hit to a limb or the head threw that piece off) are ours now: limbs come off
-- by damage (RTRG_LoseLeg / GFR_LoseArm), heads in OnDeath, all with gfr_infected_gore - no doubled-up pieces
function ENT:HandleGibOnDeath(dmginfo, hitgroup)
	if self.IsGibDamage && self:IsGibDamage(dmginfo:GetDamageType()) then self.HasDeathAnimation = false return end
	return false
end

function ENT:OnCreateDeathCorpse(dmginfo, hitgroup, corpse)
	if !IsValid(corpse) then return end
	corpse.GFR_ZCorpse = true
	corpse:SetNW2Bool("GFR_ZCorpse", true)
	local body = corpse
	if self.GFR_PM && IsValid(self.Bonemerge) then
		local b = self.Bonemerge
		local bgs = {}
		for i = 0, b:GetNumBodyGroups() - 1 do bgs[i] = b:GetBodygroup(i) end
		local cb = MakeBody(corpse, b:GetModel(), b:GetSkin(), bgs, b:GetColor(), b.GetPlayerColor and b:GetPlayerColor() or nil)
		if IsValid(cb) then
			Hide(corpse)
			corpse.Bonemerge = cb
			body = cb
		end
	else
		Show(corpse)
	end
	-- Killed while a hunter had it pinned (L4D2 special infected pack): the pack's "make the held victim's corpse visible"
	-- passes run over nearby bodies for a couple of seconds after (unhiding, unparenting, removing what it takes for its
	-- own display props), and the worn body could end up gone - an invisible corpse with only its shadow showing.
	-- Keep it right for a few seconds: the skeleton hidden (no shadow), the worn body there and visible.
	if body != corpse then
		local look = {model = body:GetModel(), skin = body:GetSkin(), bodygroups = {}, color = body:GetColor(),
			pcolor = body.GetPlayerColor and body:GetPlayerColor() or nil}
		for i = 0, body:GetNumBodyGroups() - 1 do look.bodygroups[i] = body:GetBodygroup(i) end
		for _, t in ipairs({0.2, 0.6, 1.2, 2, 3.5}) do
			timer.Simple(t, function()
				if !IsValid(corpse) then return end
				local cb = corpse.Bonemerge
				if !IsValid(cb) then
					cb = MakeBody(corpse, look.model, look.skin, look.bodygroups, look.color, look.pcolor)
					if !IsValid(cb) then Show(corpse) return end
					corpse.Bonemerge = cb
				end
				if cb:GetParent() != corpse then
					cb:SetParent(corpse)
					cb:AddEffects(EF_BONEMERGE)
				end
				cb:SetNoDraw(false)
				if cb:GetColor().a < 255 then local c = cb:GetColor() cb:SetColor(Color(c.r, c.g, c.b, 255)) end
				if cb:GetRenderMode() != RENDERMODE_NORMAL then cb:SetRenderMode(RENDERMODE_NORMAL) end
				if !corpse:GetNW2Bool("GFR_HideBase") or corpse:GetMaterial() != INVISIBLE then Hide(corpse) end
				corpse:DrawShadow(false)
			end)
		end
	end
	-- What it had lost goes with the body: the corpse can lose more (sv_rise.lua), and it gets back up without them
	corpse.GFR_LegGone = self.RTRG_LegGone
	corpse.GFR_ArmGone = self.GFR_ArmGone && table.Copy(self.GFR_ArmGone) or nil
	if cvGore:GetBool() then
		if self.RTRG_LegGone && body != corpse then HideBone(body, legBones[self.RTRG_LegGone]) end
		for hg in pairs(self.GFR_ArmGone or {}) do
			if body != corpse then HideBone(body, armBones[hg]) end
		end
		if self.RTRG_DeathHitgroup == HITGROUP_HEAD && !self.GFR_HeadIntact then
			if body != corpse then HideBone(body, "ValveBiped.Bip01_Head1") end
			Splatter(BonePos(corpse, "ValveBiped.Bip01_Neck1"))
		end
		if bit.band(self.RTRG_DeathDmgType or 0, burnTypes) != 0 then body:SetColor(Color(60, 50, 45)) end
	end
	hook.Run("RTRG_ZombieCorpse", self, corpse) -- Custom Apocalypse: it may get back up later (sv_rise.lua)
end


---------------------------------------------------------------------------------------------------------------------------------------------
-- Mashing E while held: enough presses shoves it off
hook.Add("KeyPress", "GFR_Infected_BreakGrab", function(ply, key)
	if key != IN_USE or !ply.GOTDR_Grappled then return end
	local z = ply.GFR_GrabbedBy
	if !IsValid(z) or !z.ResetGrapple then return end
	ply.GFR_GrabMash = (ply.GFR_GrabMash or 0) + 1
	ply:ViewPunch(Angle(math.Rand(-2, 2), math.Rand(-3, 3), 0))
	if ply.GFR_GrabMash >= 7 then
		ply.GFR_GrabMash = 0
		z:ResetGrapple(true)
		ply:EmitSound("physics/body/body_medium_impact_hard" .. math_random(1, 6) .. ".wav", 70)
		if GFR && GFR.Notify then GFR.Notify(ply, "You shove it off!") end
	end
end)
