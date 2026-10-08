--[[
	Custom Apocalypse - base defence turret (built from a kit: sh_items.lua gfr_deploy_turret_*, placed by sv_crafting.lua)
	A scrap-built gun on the HL2 floor turret frame. It covers a ~120 degree arc in front of it (aim it when you place
	it), shoots zombies and anyone hostile to its builder, and never you, your companions or neutral people. Players
	only if you set it to (Shift+E: none / everyone / everyone not on your access list - sv_owners.lua).
	It runs on real ammo: E loads it from your ammo (and ammo boxes in your bag). Out of ammo it just clicks.
	Gunfire carries: every burst draws the dead from far around. Zombies crowding it claw it to pieces.
	E when it's full and damaged: repair with scrap. Crouch+E: take it down (some materials back).
	Settings per kit: GFR.CustomItems[...].place.turret
]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Turret"
ENT.Spawnable = false
ENT.AutomaticFrameAdvance = true

if CLIENT then return end

local DEFAULT_MODEL = "models/combine_turrets/floor_turret.mdl"
local ARC_YAW, ARC_PITCH = 60, 35

function ENT:Initialize()
	if self:GetModel() == "" or !self:GetModel() then self:SetModel(DEFAULT_MODEL) end
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	local seq = self:LookupSequence("idlealert")
	if seq < 0 then seq = self:LookupSequence("idle") end
	if seq >= 0 then self:ResetSequence(seq) end
	self.Ammo = 0
	self.NextShot = 0
	self.NextScan = 0
	self.Yaw, self.Pitch = 0, 0
	self:SetNW2Int("GFR_TurretAmmo", 0)
end

function ENT:Cfg()
	return self.GFR_Place && self.GFR_Place.turret or {}
end

-- Called once GFR_Place is set (sv_crafting.lua: PlaceDeployable)
function ENT:SetupTurret()
	local c = self:Cfg()
	self:SetNW2String("GFR_TurretName", c.name or "Turret")
	self:SetNW2Int("GFR_TurretMax", c.cap or 200)
	self:SetNW2String("GFR_TurretAmmoName", c.ammoName or "ammo")
	if c.scale then self:SetModelScale(c.scale, 0) end
	self.GFR_Turret = true
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Ammo
function ENT:LoadFrom(ply)
	local c = self:Cfg()
	local cap = c.cap or 200
	local need = cap - self.Ammo
	if need <= 0 then return 0 end
	local got = 0
	-- Your loose ammo of the types it takes
	for _, typeName in ipairs(c.ammo or {"pistol"}) do
		if need - got <= 0 then break end
		local id = game.GetAmmoID(typeName)
		if id >= 0 then
			local take = math.min(ply:GetAmmoCount(id), need - got)
			if take > 0 then
				ply:RemoveAmmo(take, id)
				got = got + take
			end
		end
	end
	-- Ammo boxes in your bag
	local accepts = {}
	for _, t in ipairs(c.ammo or {"pistol"}) do accepts[string.lower(t)] = true end
	local inv = ply.GFR_Inv or {}
	for i = #inv, 1, -1 do
		if need - got <= 0 then break end
		local e = inv[i]
		local a = GFR.AmmoItems && GFR.AmmoItems[e.class]
		if a && accepts[string.lower(a.type)] then
			while need - got > 0 do
				local cur = ply.GFR_Inv[i]
				if !cur or cur.class != e.class or cur.count <= 0 then break end
				got = got + a.amount
				GFR.InvTake(ply, i, 1)
			end
		end
	end
	self.Ammo = math.min(self.Ammo + got, cap)
	self:SetNW2Int("GFR_TurretAmmo", self.Ammo)
	return got
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Targets: the dead, and people hostile to whoever built it
local function Hostile(self, ent)
	if !IsValid(ent) or ent == self then return false end
	-- Players: only if its owner set it to (Shift+E on it: sv_owners.lua), never its owner
	if ent:IsPlayer() then return GFR.TurretShootsPlayer && GFR.TurretShootsPlayer(self, ent) or false end
	if !ent:IsNPC() or ent:Health() <= 0 then return false end
	if ent.GFR_CompanionOf then return false end
	if GFR.IsZombie && GFR.IsZombie(ent) then
		-- Every zombie, except the one its builder is driving (sv_extract.lua)
		return !(IsValid(self.GFR_Builder) && ent.GFR_ControlPlayer == self.GFR_Builder)
	end
	local owner = self.GFR_Builder
	if ent.GFR_Group && IsValid(owner) && GFR.Spawner then
		return GFR.Spawner.PlayerDisposition(ent.GFR_Group, owner) == D_HT
	end
	return IsValid(owner) && ent:Disposition(owner) == D_HT
end
GFR.TurretHostile = Hostile -- (the Sentinel uses the same rules: gfr_sentinel.lua)

function ENT:Muzzle()
	local id = self:LookupAttachment("eyes")
	local att = id > 0 && self:GetAttachment(id)
	return att and att.Pos or (self:GetPos() + self:GetUp() * 50 * self:GetModelScale())
end

local function AimPoint(self, ent, head)
	if head then
		local b = ent:LookupBone("ValveBiped.Bip01_Head1")
		local p = b && ent:GetBonePosition(b)
		if p then return p end
	end
	return ent:WorldSpaceCenter()
end

function ENT:InArc(pos)
	local local_ = self:WorldToLocal(pos)
	local ang = local_:Angle()
	local yaw = math.NormalizeAngle(ang.y)
	local pitch = math.NormalizeAngle(ang.p)
	return math.abs(yaw) <= ARC_YAW && math.abs(pitch) <= ARC_PITCH, yaw, pitch
end

function ENT:CanSee(ent, point)
	local tr = util.TraceLine({start = self:Muzzle(), endpos = point, filter = self, mask = MASK_SHOT})
	return tr.Entity == ent or (IsValid(tr.Entity) && tr.Entity:GetParent() == ent) or tr.Fraction > 0.98
end

function ENT:FindTarget()
	local c = self:Cfg()
	local range = c.range or 900
	local best, bestD
	for _, ent in ipairs(ents.FindInSphere(self:GetPos(), range)) do
		if Hostile(self, ent) then
			local point = AimPoint(self, ent, c.headshots)
			if self:InArc(point) && self:CanSee(ent, point) then
				local d = point:DistToSqr(self:GetPos())
				if !best or d < bestD then best, bestD = ent, d end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------------------------------
function ENT:Shoot(target)
	local c = self:Cfg()
	if self.Ammo <= 0 then
		if (self.NextClick or 0) < CurTime() then
			self:EmitSound("weapons/pistol/pistol_empty.wav", 70)
			self.NextClick = CurTime() + 1.2
		end
		return
	end
	self.Ammo = self.Ammo - 1
	self:SetNW2Int("GFR_TurretAmmo", self.Ammo)
	local src = self:Muzzle()
	local point = AimPoint(self, target, c.headshots && math.random(100) <= (c.headshotChance or 50))
	local spread = c.spread or 0.04
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = c.damage or 9, Num = 1, Src = src,
		Dir = (point - src):GetNormalized(), Spread = Vector(spread, spread, 0),
		Tracer = 1, TracerName = c.tracer or "Tracer", Force = 2, IgnoreEntity = self
	})
	local fx = EffectData()
	fx:SetEntity(self)
	fx:SetAttachment(math.max(self:LookupAttachment("eyes"), 1))
	fx:SetOrigin(src)
	fx:SetAngles((point - src):Angle())
	fx:SetScale(1)
	util.Effect("MuzzleEffect", fx)
	self:EmitSound(c.sound or "weapons/smg1/smg1_fire1.wav", 85, math.random(95, 105))
	-- The noise carries (zombies and people hear it: VJ sound hints)
	if (self.NextNoise or 0) < CurTime() then
		self.NextNoise = CurTime() + 1
		sound.EmitHint(SOUND_COMBAT, self:GetPos(), c.noise or 2000, 1.2, self)
		for _, z in ipairs(ents.FindInSphere(self:GetPos(), c.noise or 2000)) do
			if z:IsNPC() && GFR.IsZombie && GFR.IsZombie(z) && !IsValid(z:GetEnemy()) && math.random(3) == 1
				&& !(GFR.ZombieResting && GFR.ZombieResting(z)) && !z.GFR_ControlPlayer then
				z:SetLastPosition(self:GetPos() + VectorRand() * 120 * Vector(1, 1, 0))
				if z.SCHEDULE_GOTO_POSITION then z:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH") end
			end
		end
	end
end

function ENT:Think()
	local now = CurTime()
	local c = self:Cfg()
	-- Pick a target a few times a second, keep it while it's valid and in sight
	if now >= self.NextScan then
		self.NextScan = now + 0.35
		local t = self.Target
		if !(IsValid(t) && Hostile(self, t) && t:GetPos():DistToSqr(self:GetPos()) < (c.range or 900) ^ 2
			&& self:InArc(AimPoint(self, t)) && self:CanSee(t, AimPoint(self, t))) then
			self.Target = self:FindTarget()
			if IsValid(self.Target) && !t then self:EmitSound("npc/turret_floor/active.wav", 70) end
		end

		-- Zombies crowding it tear at it
		local n = 0
		for _, z in ipairs(ents.FindInSphere(self:GetPos(), 70 * self:GetModelScale())) do
			if z:IsNPC() && GFR.IsZombie && GFR.IsZombie(z) && z:Health() > 0 then n = n + 1 end
		end
		if n > 0 then
			local d = DamageInfo()
			d:SetDamage(n * 2.5)
			d:SetDamageType(DMG_SLASH)
			d:SetAttacker(game.GetWorld())
			d:SetInflictor(game.GetWorld())
			self:TakeDamageInfo(d)
			if math.random(3) == 1 then self:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 70) end
		end
	end

	-- Turn toward the target (pose parameters), shoot when lined up
	local t = self.Target
	local wantYaw, wantPitch = 0, 0
	if IsValid(t) then
		local _, y, p = self:InArc(AimPoint(self, t))
		wantYaw, wantPitch = y, p
	end
	local turn = (c.turn or 220) * FrameTime()
	self.Yaw = math.Approach(self.Yaw, wantYaw, math.max(turn, 2))
	self.Pitch = math.Approach(self.Pitch, wantPitch, math.max(turn, 2))
	self:SetPoseParameter("aim_yaw", self.Yaw)
	self:SetPoseParameter("aim_pitch", -self.Pitch)
	if IsValid(t) && now >= self.NextShot && math.abs(self.Yaw - wantYaw) < 6 then
		self.NextShot = now + 1 / (c.rate or 6)
		self:Shoot(t)
	end

	self:NextThink(now)
	return true
end
