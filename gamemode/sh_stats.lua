--[[
	Custom Apocalypse Project - Survival stats
	Stamina, hunger and thirst, networked for the HUD (cl_gfr_hud.lua). Infection lives in gfr_infection.lua.

	NW2 vars on the player:
		GFR_Stamina, GFR_Hunger, GFR_Thirst  (0-100)
		GFR_Exhausted                        (bool, can't sprint until stamina recovers)
]]
AddCSLuaFile()

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED)
local cvEnabled     = CreateConVar("gfr_stats_enabled", "1", flags, "Enable stamina/hunger/thirst")
local cvHungerMins  = CreateConVar("gfr_hunger_minutes", "60", flags, "Minutes for hunger to drain from full to empty")
local cvThirstMins  = CreateConVar("gfr_thirst_minutes", "40", flags, "Minutes for thirst to drain from full to empty")
local cvSprintDrain = CreateConVar("gfr_stamina_drain", "12", flags, "Stamina lost per second while sprinting")
local cvStamRegen   = CreateConVar("gfr_stamina_regen", "15", flags, "Stamina regained per second while resting")
local cvJumpCost    = CreateConVar("gfr_stamina_jump", "8", flags, "Stamina cost of a jump")

local EXHAUST_RECOVER = 30 -- Stamina needed before sprinting again after running out

-- Sprint/jump gating (shared so movement is predicted)
hook.Add("SetupMove", "GFR_Stamina_Move", function(ply, mv)
	if !cvEnabled:GetBool() or ply:GetMoveType() == MOVETYPE_NOCLIP then return end
	if ply:GetNW2Bool("GFR_Exhausted") && mv:KeyDown(IN_SPEED) then
		local walk = ply:GetWalkSpeed()
		mv:SetMaxSpeed(walk)
		mv:SetMaxClientSpeed(walk)
	end
	if ply:OnGround() && ply:GetNW2Float("GFR_Stamina", 100) < cvJumpCost:GetFloat() then
		mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
	end
end)

-- No bunnyhopping: strafing in the air can't push you past the speed you're allowed to move at (walk / run).
-- Speed you already had in the air (an explosion, a fall) is kept; it just can't be built up.
hook.Add("SetupMove", "GFR_NoBhop", function(ply, mv)
	ply.GFR_AirSpeed = (!ply:OnGround() && ply:GetMoveType() == MOVETYPE_WALK) and mv:GetVelocity():Length2D() or nil
end)

hook.Add("FinishMove", "GFR_NoBhop", function(ply, mv)
	if ply:GetMoveType() != MOVETYPE_WALK or ply:OnGround() then return end
	local vel = mv:GetVelocity()
	local flat = vel:Length2D()
	local allowed = math.max(mv:GetMaxSpeed(), ply.GFR_AirSpeed or 0)
	if flat > allowed && flat > 0 then
		local k = allowed / flat
		mv:SetVelocity(Vector(vel.x * k, vel.y * k, vel.z))
	end
end)

if CLIENT then return end

-- Movement speed like a DarkRP server (Sandbox's 200 walk / 400 run is far too quick for this)
local cvWalk = CreateConVar("gfr_walk_speed", "160", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Walking speed (Sandbox: 200)")
local cvRun  = CreateConVar("gfr_run_speed", "240", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Sprinting speed (Sandbox: 400)")
hook.Add("PlayerLoadout", "GFR_Stats_Speed", function(ply)
	ply:SetWalkSpeed(cvWalk:GetFloat())
	ply:SetRunSpeed(cvRun:GetFloat())
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- What each consumable restores: hunger, thirst, stamina (applied when it's actually eaten/drunk)
-- Food and drink: S.T.A.L.K.E.R. 2 Consumables (sv_consumables.lua). Crunchy's food is no longer used, except the
-- raw zombie parts from harvesting.
local nutrition = {
	-- Food
	gfr_s2_bread = {hunger = 19, thirst = -3},
	gfr_s2_sausage = {hunger = 19, thirst = -3},
	gfr_s2_canned = {hunger = 26},
	gfr_s2_milk = {hunger = 15, stamina = 10},
	arc9_eft_food_mre = {hunger = 40, thirst = 5}, -- Tarkov MRE: a whole meal (sv_eftmeds.lua)
	-- Drinks
	gfr_s2_water = {thirst = 30},
	gfr_s2_energy = {thirst = 15, stamina = 50},
	gfr_s2_vodka = {thirst = 4},
	-- Zombie meat (raw parts from harvesting; very risky raw, see sv_infection.lua)
	meat_chunk1 = {hunger = 8, thirst = -5}, meat_chunk2 = {hunger = 8, thirst = -5},
	meat_arm1 = {hunger = 11, thirst = -5}, meat_arm2 = {hunger = 11, thirst = -5},
	meat_leg1 = {hunger = 15, thirst = -6}, meat_leg2 = {hunger = 15, thirst = -6},
	meat_torso = {hunger = 26, thirst = -8}, meat_head = {hunger = 6, thirst = -3},
	gfr_food_zmeat_cooked = {hunger = 19, thirst = -3},
	-- Medical boosters
	gfr_s2_pills_endurance = {stamina = 100},
	gfr_scp_adrenaline = {stamina = 100},
	-- EFT stimulants (sv_eftmeds.lua)
	weapon_eft_injectoradrenaline = {stamina = 100},
	weapon_eft_injectorl1 = {stamina = 80},
	weapon_eft_injectorpropital = {stamina = 60}
}

GFR = GFR or {}
GFR.Nutrition = nutrition

local function Set(ply, key, value)
	ply:SetNW2Float(key, math.Clamp(value, 0, 100))
end

local function ResetStats(ply)
	Set(ply, "GFR_Stamina", 100)
	Set(ply, "GFR_Hunger", 100)
	Set(ply, "GFR_Thirst", 100)
	ply:SetNW2Bool("GFR_Exhausted", false)
	ply.GFR_StarveT = 0
	ply.GFR_StamDelay = 0
end

hook.Add("PlayerSpawn", "GFR_Stats_Spawn", ResetStats)

hook.Add("GFR_ItemUsed", "GFR_Stats_Eat", function(ply, class)
	local n = nutrition[class]
	if !n then return end
	if n.hunger then Set(ply, "GFR_Hunger", ply:GetNW2Float("GFR_Hunger", 100) + n.hunger) end
	if n.thirst then Set(ply, "GFR_Thirst", ply:GetNW2Float("GFR_Thirst", 100) + n.thirst) end
	if n.stamina then
		Set(ply, "GFR_Stamina", ply:GetNW2Float("GFR_Stamina", 100) + n.stamina)
		if ply:GetNW2Float("GFR_Stamina") >= EXHAUST_RECOVER then ply:SetNW2Bool("GFR_Exhausted", false) end
	end
end)

hook.Add("KeyPress", "GFR_Stats_Jump", function(ply, key)
	if key != IN_JUMP or !cvEnabled:GetBool() or !ply:Alive() or !ply:OnGround() or ply:GetMoveType() == MOVETYPE_NOCLIP then return end
	Set(ply, "GFR_Stamina", ply:GetNW2Float("GFR_Stamina", 100) - cvJumpCost:GetFloat())
	ply.GFR_StamDelay = CurTime() + 1
end)

local TICK = 0.1

-- Infection symptom penalties (GFR_InfStage is set by gfr_infection.lua: 0 none/incubating, 1 infected, 2 fever, 3 turning)
local stageRegen = {[2] = 0.6, [3] = 0.4}
local stageThirst = {[2] = 1.5, [3] = 1.5}

timer.Create("GFR_Stats_Tick", TICK, 0, function()
	local enabled = cvEnabled:GetBool()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		if !ply:Alive() then continue end
		-- Hard cap: nothing (food, meds, other addons) can push health/armor past max
		if ply:Health() > ply:GetMaxHealth() then ply:SetHealth(ply:GetMaxHealth()) end
		if ply:Armor() > ply:GetMaxArmor() then ply:SetArmor(ply:GetMaxArmor()) end
		-- Controlling your own zombie body (sv_extract.lua): the dead don't get hungry
		if !enabled or ply.GFR_IsZombie or ply:GetMoveType() == MOVETYPE_NOCLIP or ply:InVehicle() then continue end
		local stage = ply.GFR_InfStage or 0

		local hunger = ply:GetNW2Float("GFR_Hunger", 100)
		local thirst = ply:GetNW2Float("GFR_Thirst", 100)
		local stamina = ply:GetNW2Float("GFR_Stamina", 100)
		local sprinting = ply:KeyDown(IN_SPEED) && !ply:GetNW2Bool("GFR_Exhausted") && ply:GetVelocity():Length2D() > ply:GetWalkSpeed() + 10

		-- Buffs and debuffs (sh_status.lua): faster / slower stamina, a lower top, thirstier
		local mods = GFR.StatusMods && GFR.StatusMods(ply) or {regen = 1, drain = 1, cap = 100, thirst = 1}

		-- Stamina: drains while sprinting, recovers after a short rest; slower when starving/thirsty
		if sprinting then
			stamina = stamina - cvSprintDrain:GetFloat() * mods.drain * TICK
			ply.GFR_StamDelay = now + 1.2
		elseif now > (ply.GFR_StamDelay or 0) then
			local regen = cvStamRegen:GetFloat() * mods.regen
			if hunger < 20 or thirst < 20 then regen = regen * 0.5 end
			regen = regen * (stageRegen[stage] or 1)
			stamina = stamina + regen * TICK
		end
		stamina = math.min(stamina, mods.cap)
		Set(ply, "GFR_Stamina", stamina)
		if stamina <= 0 then
			ply:SetNW2Bool("GFR_Exhausted", true)
		elseif stamina >= EXHAUST_RECOVER && ply:GetNW2Bool("GFR_Exhausted") then
			ply:SetNW2Bool("GFR_Exhausted", false)
		end

		-- Hunger/thirst: steady drain, faster while sprinting
		local mult = sprinting and 2 or 1
		hunger = hunger - 100 / math.max(cvHungerMins:GetFloat() * 60, 1) * TICK * mult
		thirst = thirst - 100 / math.max(cvThirstMins:GetFloat() * 60, 1) * TICK * mult * (stageThirst[stage] or 1) * mods.thirst
		Set(ply, "GFR_Hunger", hunger)
		Set(ply, "GFR_Thirst", thirst)

		-- Starving or dehydrated: lose health slowly
		if hunger <= 0 or thirst <= 0 then
			ply.GFR_StarveT = (ply.GFR_StarveT or 0) + TICK
			local interval = (hunger <= 0 && thirst <= 0) and 1.5 or 3
			if ply.GFR_StarveT >= interval then
				ply.GFR_StarveT = 0
				local dmg = DamageInfo()
				dmg:SetDamage(1)
				dmg:SetDamageType(DMG_GENERIC)
				dmg:SetAttacker(game.GetWorld())
				dmg:SetInflictor(game.GetWorld())
				ply:TakeDamageInfo(dmg)
			end
		end
	end
end)

concommand.Add("gfr_stats_refill", function(ply)
	if IsValid(ply) && !GFR.CanCheat(ply) then return end
	for _, p in ipairs(IsValid(ply) and {ply} or player.GetAll()) do ResetStats(p) end
end)
