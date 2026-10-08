--[[
	Custom Apocalypse - Sentinel Turret: the heavy base turret (kit: sh_items.lua gfr_deploy_turret_heavy)
	Frasiu's Sentinel minigun (workshop "Sentinel Turret", entity_sentrygun_reworked) - its model, spin-up, laser,
	tracers and sounds - run by our rules, like the light turret (gfr_turret.lua):
		- shoots zombies and anyone hostile to its builder (GFR.TurretHostile), never you, companions or neutrals
		- real ammo: E loads rifle rounds from your ammo / ammo boxes. No free 600-round belt: empty, it just clicks
		- its health is the building's (sv_crafting.lua: repair with scrap, pick up undamaged with Crouch+E)
		- loud: firing draws the dead
		- covers all 360 degrees: the gun swings +-100 (the model's limit), the tripod turns for anything further round
	Settings per kit: GFR.CustomItems[...].place.turret (range, damage per round, rate = rounds a second, cap)
]]
AddCSLuaFile()
DEFINE_BASECLASS("entity_sentrygun_reworked")

ENT.Type = "ai"
ENT.Base = "entity_sentrygun_reworked"
ENT.PrintName = "Sentinel Turret"
ENT.Spawnable = false
ENT.Editable = false -- (no context-menu ammo types / manual control)
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_BOTH

if CLIENT then return end

local function SetBelt(self, full)
	self:SetBodygroup(1, full and 0 or 1)
	self:SetBodygroup(2, full and 0 or 1)
end

function ENT:Initialize()
	BaseClass.Initialize(self)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	self.GFR_Sentinel = true
	self.Ammo = 0
	self:SetNWInt("Ammount", 0) -- (the count on its side)
	self:SetNW2Int("GFR_TurretAmmo", 0)
	SetBelt(self, false)
end

function ENT:Cfg()
	return self.GFR_Place && self.GFR_Place.turret or {}
end

-- Called once GFR_Place is set (sv_crafting.lua: PlaceDeployable)
function ENT:SetupTurret()
	local c = self:Cfg()
	self:SetNW2String("GFR_TurretName", c.name or "Sentinel Turret")
	self:SetNW2Int("GFR_TurretMax", c.cap or 400)
	self:SetNW2String("GFR_TurretAmmoName", c.ammoName or "ammo")
	self:SetRadiuso(math.Clamp((c.range or 1400) * 0.5, 100, 2048))
	self.ShootDelay = 1 / (c.rate or 12)
	self.GFR_Turret = true
end

local function SyncAmmo(self)
	self.Ammo = math.max(self:GetNWInt("Ammount"), 0)
	if self:GetNW2Int("GFR_TurretAmmo") != self.Ammo then self:SetNW2Int("GFR_TurretAmmo", self.Ammo) end
end

-- E with ammo on you (sv_crafting.lua): same loading as the light turret
function ENT:LoadFrom(ply)
	SyncAmmo(self)
	local got = scripted_ents.GetStored("gfr_turret").t.LoadFrom(self, ply)
	self:SetNWInt("Ammount", self.Ammo)
	if got > 0 then SetBelt(self, true) end
	return got
end

-- Sees all the way round (the base only looks ~120 degrees ahead): the gun swings +-100 degrees, and for anything
-- further round the whole turret pivots on its tripod (Think)
function ENT:CanSeeEntity(ent)
	if !IsValid(ent) then return false end
	local src = self:GetAttachment(1).Pos
	local height = (ent:OBBMaxs() - ent:OBBMins()).z
	for i = 1, 4 do
		local tr = util.TraceLine({start = src, endpos = ent:GetPos() + Vector(0, 0, height * i / 4), filter = self})
		if tr.Entity == ent then return true end
	end
	return false
end

-- Who it shoots at: our rules instead of NPC relationships
function ENT:GetEnemies()
	local list = {}
	if !GFR.TurretHostile then return list end
	for _, ent in ipairs(ents.FindInSphere(self:GetPos(), self:Cfg().range or 1400)) do
		if GFR.TurretHostile(self, ent) then list[#list + 1] = ent end
	end
	return list
end

function ENT:HandleShooting()
	local before = self:GetNWInt("Ammount")
	if before <= 0 then
		-- Empty: no shooting (and no reloading itself)
		if self.IsShooting && (self.NextClick or 0) < CurTime() then
			self:EmitSound("weapons/pistol/pistol_empty.wav", 70)
			self.NextClick = CurTime() + 1.2
		end
		self.IsShooting = false
	end
	BaseClass.HandleShooting(self)
	local now = self:GetNWInt("Ammount")
	if now < 0 then
		-- It ran dry: the base gun would start a free reload. Stays empty until someone loads it.
		self:SetNWInt("Ammount", 0)
		self.ReloadFinish = 0
	end
	SyncAmmo(self)
	-- The noise carries: zombies come to see what it's shooting at
	if now < before && (self.NextNoise or 0) < CurTime() then
		local range = self:Cfg().noise or 2600
		self.NextNoise = CurTime() + 1
		sound.EmitHint(SOUND_COMBAT, self:GetPos(), range, 1.2, self)
		for _, z in ipairs(ents.FindInSphere(self:GetPos(), range)) do
			if z:IsNPC() && GFR.IsZombie && GFR.IsZombie(z) && !IsValid(z:GetEnemy()) && math.random(3) == 1
				&& !(GFR.ZombieResting && GFR.ZombieResting(z)) && !z.GFR_ControlPlayer then
				z:SetLastPosition(self:GetPos() + VectorRand() * 120 * Vector(1, 1, 0))
				if z.SCHEDULE_GOTO_POSITION then z:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH") end
			end
		end
	end
end

local PIVOT_SPEED = 110 -- degrees a second the tripod turns

function ENT:Think()
	-- A target beyond the gun's swing: turn the whole turret toward it (it stays put: sv_crafting.lua keeps it at GFR_FixedAng)
	local enemy = self._Enemy
	if IsValid(enemy) && self:GetNWBool("Active") then
		local yaw = math.NormalizeAngle(self:WorldToLocal(enemy:GetPos()):Angle().y)
		if math.abs(yaw) > 70 then
			local ang = self:GetAngles()
			ang.y = ang.y + math.Clamp(yaw, -PIVOT_SPEED * FrameTime(), PIVOT_SPEED * FrameTime())
			self:SetAngles(Angle(0, ang.y, 0))
			if self.GFR_FixedAng then self.GFR_FixedAng = self:GetAngles() end
		end
	end

	-- Zombies crowding it tear at it (the building's health: sv_crafting.lua)
	if (self.NextSwarm or 0) < CurTime() then
		self.NextSwarm = CurTime() + 0.35
		local n = 0
		for _, z in ipairs(ents.FindInSphere(self:GetPos(), 70)) do
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
	return BaseClass.Think(self)
end

-- Damage is the building's health (sv_crafting.lua), not the Sentinel's own 200 HP / explode-and-vanish
function ENT:OnTakeDamage() end

-- Its rounds: our damage per round, and real bullets (its own are "airboat" damage, which wouldn't count headshots)
hook.Add("EntityTakeDamage", "GFR_Sentinel_Damage", function(ent, dmg)
	local att = dmg:GetAttacker()
	if !IsValid(att) or !att.GFR_Sentinel then return end
	dmg:SetDamage(att:Cfg().damage or 14)
	dmg:SetDamageType(DMG_BULLET)
end)
