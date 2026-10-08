--[[
	Custom Apocalypse - your zombie's hunger (your zombie: sv_extract.lua; HUD: cl_zombietame.lua)
	One meter, 100 = full. It drains (gfr_zhunger_minutes from full to empty) and eating fills it:
		bodies and meat (E, sv_extract.lua), and biting the living (grabs and swipes that draw blood).
	Stages:
		sated    70+    heals slowly; people watching you read you as calmer
		hungry   40-70  groans now and then
		starving 15-40  too restless to sit or lie down; people read you as more dangerous
		feral    <15    the hunger takes over: every so often you lunge at whatever's alive and close, on your own;
		                you waste away (health drains, down to a third); people see a threat almost at once
	Kept while your zombie is down and gets back up; gone when you're put down for good.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvMinutes = CreateConVar("gfr_zhunger_minutes", "20", flags, "Minutes for your zombie's hunger to go from full to empty")

local TICK = 1
local STAGES = {
	{id = "sated", min = 70, name = "Sated"},
	{id = "hungry", min = 40, name = "Hungry"},
	{id = "starving", min = 15, name = "Starving"},
	{id = "feral", min = -1, name = "FERAL"}
}

local function StageOf(h)
	for _, s in ipairs(STAGES) do if h >= s.min then return s end end
	return STAGES[#STAGES]
end

function GFR.ZombieHunger(ply) return ply.GFR_ZHunger or 70 end
function GFR.ZombieHungerStage(ply) return StageOf(GFR.ZombieHunger(ply)).id end

local function Set(ply, v)
	ply.GFR_ZHunger = math.Clamp(v, 0, 100)
	ply:SetNW2Float("GFR_ZHunger", ply.GFR_ZHunger)
end

-- Eating: bites of bodies / meat (sv_extract.lua Bite), blood drawn from the living (below)
function GFR.ZombieFeed(ply, amount)
	if !IsValid(ply) or !ply.GFR_IsZombie then return end
	local before = StageOf(GFR.ZombieHunger(ply)).id
	Set(ply, GFR.ZombieHunger(ply) + amount)
	local after = StageOf(ply.GFR_ZHunger)
	if after.id != before && after.id == "sated" then GFR.Notify(ply, "The gnawing in your gut goes quiet. For now.") end
end

local function Groan(z)
	if GFR.ZombieVoice then GFR.ZombieVoice(z, "alert", 75, math.random(80, 95), z.GFR_PlyModel) end
end

-- While the hunger drives (lost, or a feral lunge), the VJ controller mustn't steer: with no movement key held its
-- Controller_Movement calls StopMoving() every tick (walk a step, stop, again), and with one held it walks toward your
-- aim point. Its idle-stand order does the same to a standing start. Both are skipped meanwhile (per zombie).
-- (not while it eats or holds someone: then the controller's constant stop is what keeps it still over the meal -
-- without it, it slid on along its last walk, got "moved off the food" and stood back up)
local function HungerDriving(z)
	if z.GFR_EatFood or z.GOTDR_CurEnt or z.GFR_ScriptFeed then return false end
	return z.GFR_AIDriven or (z.GFR_LungeUntil or 0) > CurTime()
end
local function GuardMovement(z)
	if z.GFR_MoveGuarded then return end
	z.GFR_MoveGuarded = true
	local move, idle = z.Controller_Movement, z.SCHEDULE_IDLE_STAND
	if move then
		z.Controller_Movement = function(self, ...)
			if HungerDriving(self) then return true end
			return move(self, ...)
		end
	end
	if idle then
		z.SCHEDULE_IDLE_STAND = function(self, ...)
			if HungerDriving(self) then return end
			return idle(self, ...)
		end
	end
end

-- Sends it walking (or running) somewhere on its own. Setting off from an idle, the idle (a crouched one especially)
-- could keep playing while it moved - sliding along the ground in the pose - so the walk animation is set every time
-- the order goes out, the way VJ's controller does for your own steering.
-- Someone (not something): what it breaks into a run for
local function Human(e)
	return e:IsPlayer() or e.GFR_Group != nil or e:LookupBone("ValveBiped.Bip01_Pelvis") != nil
end

-- run: going for someone alive (it runs, day or night); otherwise it walks (wandering, going to a body)
local function MoveTo(z, pos, run)
	z.GFR_ChaseRun = run or nil -- (npc_gfr_infected's GFR_Runner: lets it run by day)
	local act = run and ACT_RUN or ACT_WALK
	z:SetLastPosition(pos)
	if !z.SCHEDULE_GOTO_POSITION then return end
	z:SCHEDULE_GOTO_POSITION(run and "TASK_RUN_PATH" or "TASK_WALK_PATH", function()
		z:SetMovementActivity(act)
	end)
	local cur = z:GetActivity()
	if cur == ACT_IDLE or z:GetSequenceActivity(z:GetSequence()) == ACT_IDLE then
		z:SetIdealActivity(act)
	end
end

-- Feral: lunge at the closest living thing in reach
local function Lunge(ply, z)
	GuardMovement(z)
	local best, bestD
	for _, e in ipairs(ents.FindInSphere(z:GetPos(), 650)) do
		if e != z && !(e:GetClass() == "obj_vj_bullseye" or e.VJ_IsBeingControlled) && ((e:IsNPC() && e:Health() > 0 && !(GFR.IsZombie && GFR.IsZombie(e))) or (e:IsPlayer() && e:Alive() && e != ply && !e.GFR_IsZombie)) then
			local d = e:GetPos():DistToSqr(z:GetPos())
			if (!bestD or d < bestD) && z:Visible(e) then best, bestD = e, d end
		end
	end
	Groan(z)
	if !best then
		util.ScreenShake(z:GetPos(), 3, 8, 0.8, 300)
		return
	end
	z.GFR_LungeUntil = CurTime() + 1.8 -- (npc_gfr_infected ignores the controller's idle order meanwhile)
	MoveTo(z, best:GetPos(), Human(best))
	if !ply.GFR_ZFeralTold then
		ply.GFR_ZFeralTold = true
		GFR.Notify(ply, "The hunger takes over - your body lunges on its own. Eat something.")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Lost to the hunger: at 0 you lose control. Your zombie hunts and eats on its own (you can only look around)
-- until the meter is full again, then it's yours.
local function SetLost(ply, z, lost)
	ply.GFR_ZLost = lost or nil
	ply:SetNW2Bool("GFR_ZLost", lost)
	if IsValid(z) then
		z.GFR_AIDriven = lost or nil
		if !lost then z:StopMoving() z.GFR_ChaseRun = nil end
	end
	if lost then
		GFR.Notify(ply, "The hunger takes you. You can only watch until it has eaten its fill.")
	else
		GFR.Notify(ply, "Full at last. The hunger lets go - you're in control again.")
	end
end

-- Your keys do nothing meanwhile (the mouse still looks around)
hook.Add("StartCommand", "GFR_ZHunger_Lost", function(ply, cmd)
	if !ply.GFR_ZLost then return end
	cmd:ClearMovement()
	cmd:ClearButtons()
end)

local function Edible(e)
	if e:GetClass() == "prop_ragdoll" then
		return !e.GFR_EatenBy && !e.GFR_Limp && !e.GFR_TurningBody && !IsValid(e.GFR_PlayerBody) && !e.GFR_Burned && !e.GFR_Decor
			&& e:LookupBone("ValveBiped.Bip01_Pelvis") != nil
	end
	return e.GFR_Bait && !e.GFR_EatenBy
end

-- (the VJ controller's aim-point marker is an "NPC" sitting wherever you aim: never prey)
local function Marker(e) return e.VJ_IsBeingControlled or e:GetClass() == "obj_vj_bullseye" end

local function Prey(e, ply, z)
	if e == z or e == ply or Marker(e) then return false end
	if e:IsPlayer() then return e:Alive() && !e.GFR_IsZombie end
	return e:IsNPC() && e:Health() > 0 && !(GFR.IsZombie && GFR.IsZombie(e))
end

local function GoTo(z, pos, run)
	if (z.GFR_NextDriveMove or 0) > CurTime() && (z.GFR_ChaseRun or false) == (run or false) then return end
	z.GFR_NextDriveMove = CurTime() + 1
	MoveTo(z, pos, run)
end

-- idle: driving it because you've left it alone (below), not the hunger - it only stops to eat if it's hungry
local function Drive(ply, z, idle)
	if z.GFR_EatFood or z.GOTDR_CurEnt or z.GFR_ScriptFeed then return end -- (busy eating / biting someone)
	if z.GetState && z:GetState() != VJ_STATE_NONE then return end
	local zpos = z:GetPos()
	local food, foodD, prey, preyD
	for _, e in ipairs(ents.FindInSphere(zpos, 2500)) do
		local d = e:GetPos():DistToSqr(zpos)
		if Edible(e) then
			if !foodD or d < foodD then food, foodD = e, d end
		elseif d < 1200 * 1200 && Prey(e, ply, z) && (!preyD or d < preyD) && z:Visible(e) then
			prey, preyD = e, d
		end
	end
	if idle && GFR.ZombieHunger(ply) >= 70 then food = nil end -- (not hungry: leaves bodies alone)
	-- Something alive and close beats walking to a body (only for ones that can grab: a hunter goes for bodies)
	if !z.GFR_TryGrab then prey = nil end
	if prey && (!food or preyD < foodD * 0.5 or preyD < 500 * 500) then
		local run = Human(prey) -- (runs at people; anything else it just walks after)
		if preyD < 95 * 95 && z.GFR_TryGrab then
			z:SetAngles(Angle(0, (prey:GetPos() - zpos):Angle().y, 0))
			if !z:GFR_TryGrab((prey:WorldSpaceCenter() - z:WorldSpaceCenter()):GetNormalized()) then GoTo(z, prey:GetPos(), run) end
		else
			GoTo(z, prey:GetPos(), run)
		end
		return
	end
	if food then
		if foodD < 70 * 70 && GFR.ZombieStartEating then
			z:StopMoving()
			z:ClearSchedule() -- (the walk over here is done with: it must not carry on under the meal)
			GFR.ZombieStartEating(ply, z)
		else
			GoTo(z, food:GetPos())
		end
		return
	end
	-- Nothing around: roams, looking - stands a while, shambles somewhere, stands again.
	-- Drifting (idle): like any other zombie (gfr_zombie_roam_min / _max, sv_zombieworld.lua), short walks.
	-- Lost to the hunger: short pauses, long walks - it goes much further looking for something to eat.
	if (z.GFR_NextDriveWander or 0) < CurTime() then
		if !z.GFR_DriftRested then
			z.GFR_DriftRested = true
			local lo, hi = 5, 15
			if idle then
				local cvLo, cvHi = GetConVar("gfr_zombie_roam_min"), GetConVar("gfr_zombie_roam_max")
				lo, hi = cvLo and cvLo:GetFloat() or 20, cvHi and cvHi:GetFloat() or 70
			end
			z.GFR_NextDriveWander = CurTime() + math.Rand(lo, math.max(hi, lo))
			z.GFR_ChaseRun = nil
			z:StopMoving()
			return
		end
		z.GFR_DriftRested = nil
		z.GFR_NextDriveWander = CurTime() + (idle and math.Rand(10, 16) or math.Rand(25, 35))
		local ang = math.Rand(0, math.pi * 2)
		z.GFR_NextDriveMove = 0
		GoTo(z, zpos + Vector(math.cos(ang), math.sin(ang), 0) * (idle and math.Rand(300, 700) or math.Rand(1200, 2000)))
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Left alone: no movement keys for a minute and your zombie wanders, hunts and (hungry) eats on its own, the same AI
-- as being lost to the hunger. Any movement key and it's yours again. (Not while you've sat it down or it's eating.)
local IDLE_TAKEOVER = 300
local moveKeys = bit.bor(IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT)

hook.Add("StartCommand", "GFR_ZIdle_Watch", function(ply, cmd)
	if !ply.GFR_IsZombie or ply.GFR_ZLost then return end
	if bit.band(cmd:GetButtons(), moveKeys) != 0 or cmd:GetForwardMove() != 0 or cmd:GetSideMove() != 0 then
		ply.GFR_ZLastMove = CurTime()
		if ply.GFR_ZIdleAI then ply.GFR_ZWake = true end
	end
end)

local function SetIdleAI(ply, z, on)
	ply.GFR_ZIdleAI = on or nil
	ply.GFR_ZWake = nil
	ply:SetNW2Bool("GFR_ZIdleAI", on)
	if IsValid(z) && !ply.GFR_ZLost then
		z.GFR_AIDriven = on or nil
		if !on then z.GFR_ChaseRun = nil end
		if !on && !z.GFR_EatFood then z:StopMoving() end
	end
	if on then GFR.Notify(ply, "You drift. Your body shambles on by itself... move to take it back.") end
end

-- (debug, not advertised anywhere: middle mouse drops straight into drifting / back out - cl_zombietame.lua)
util.AddNetworkString("GFR_ZDriftToggle")
net.Receive("GFR_ZDriftToggle", function(_, ply)
	if !ply.GFR_IsZombie or ply.GFR_ZLost then return end
	if (ply.GFR_ZNextToggle or 0) > CurTime() then return end
	ply.GFR_ZNextToggle = CurTime() + 0.5
	local z = ply.GFR_ZombieNPC
	if !IsValid(z) or z:Health() <= 0 then return end
	if ply.GFR_ZIdleAI then
		SetIdleAI(ply, z, false)
		ply.GFR_ZLastMove = CurTime()
	elseif !z.GFR_ManualSit && !z.GFR_EatFood && !z.GOTDR_CurEnt && !z.GFR_ScriptFeed then
		SetIdleAI(ply, z, true)
	end
end)

timer.Create("GFR_ZHunger_Drive", 0.4, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		if !ply.GFR_IsZombie then
			if ply.GFR_ZLost then SetLost(ply, nil, false) end
			if ply.GFR_ZIdleAI then SetIdleAI(ply, nil, false) end
			ply.GFR_ZLastMove = nil
			continue
		end
		local z = ply.GFR_ZombieNPC
		if !IsValid(z) or z:Health() <= 0 then ply.GFR_ZLastMove = now continue end
		ply.GFR_ZLastMove = ply.GFR_ZLastMove or now
		local h = GFR.ZombieHunger(ply)
		if !ply.GFR_ZLost && h <= 0 then
			if z.GFR_ManualSit then z.GFR_ManualSit = nil z.Zombie_IdleStandT = 0 z:SetNW2Bool("GFR_ZSitting", false) end
			if ply.GFR_ZIdleAI then SetIdleAI(ply, z, false) end
			SetLost(ply, z, true)
		elseif ply.GFR_ZLost && h >= 100 then
			if z.GFR_EatFood && GFR.ZombieStopEating then GFR.ZombieStopEating(z) end
			SetLost(ply, z, false)
			ply.GFR_ZLastMove = now
		end
		if ply.GFR_ZLost then
			z.GFR_AIDriven = true -- (a zombie that got back up after going down: it's still lost)
			GuardMovement(z)
			Drive(ply, z)
			continue
		end

		-- Left alone
		if ply.GFR_ZIdleAI then
			if ply.GFR_ZWake then
				SetIdleAI(ply, z, false)
				GFR.Notify(ply, "You're back in control.")
			else
				z.GFR_AIDriven = true
				GuardMovement(z)
				Drive(ply, z, true)
			end
		elseif now - ply.GFR_ZLastMove > IDLE_TAKEOVER && !z.GFR_ManualSit && !z.GFR_EatFood && !z.GOTDR_CurEnt && !z.GFR_ScriptFeed then
			SetIdleAI(ply, z, true)
		end
	end
end)

timer.Create("GFR_ZHunger_Tick", TICK, 0, function()
	local drain = 100 / math.max(cvMinutes:GetFloat() * 60, 1) * TICK
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		if !ply.GFR_IsZombie then continue end
		-- (however you became one, you have a meter: and it's re-sent so your screen always has it)
		if ply.GFR_ZHunger == nil then Set(ply, 70) end
		if ply:GetNW2Float("GFR_ZHunger", -1) < 0 then ply:SetNW2Float("GFR_ZHunger", ply.GFR_ZHunger) end
		local z = ply.GFR_ZombieNPC
		if !IsValid(z) or z:Health() <= 0 then continue end -- (down: the hunger waits for you)
		local eating = z.GFR_EatFood != nil
		if !eating then Set(ply, GFR.ZombieHunger(ply) - drain) end
		local stage = StageOf(ply.GFR_ZHunger)
		if stage.id != ply.GFR_ZStage then
			local was = ply.GFR_ZStage
			ply.GFR_ZStage = stage.id
			if was && stage.min < (StageOf(ply.GFR_ZPrevH or 100).min) then
				if stage.id == "hungry" then GFR.Notify(ply, "You're getting hungry.")
				elseif stage.id == "starving" then GFR.Notify(ply, "Starving. You can't keep still - find something to eat.")
				elseif stage.id == "feral" then GFR.Notify(ply, "FERAL. The hunger is taking over.") end
			end
			if stage.id != "feral" then ply.GFR_ZFeralTold = nil end
		end
		ply.GFR_ZPrevH = ply.GFR_ZHunger

		local max = z:GetMaxHealth()
		if stage.id == "sated" then
			if now >= (ply.GFR_ZNextHeal or 0) && z:Health() < max then
				ply.GFR_ZNextHeal = now + 2
				z:SetHealth(math.min(z:Health() + 1, max))
			end
		elseif stage.id == "hungry" or stage.id == "starving" then
			if now >= (ply.GFR_ZNextGroan or 0) then
				ply.GFR_ZNextGroan = now + (stage.id == "starving" and math.Rand(12, 20) or math.Rand(25, 45))
				if !eating then Groan(z) end
			end
		elseif stage.id == "feral" then
			-- Wasting away
			if now >= (ply.GFR_ZNextWaste or 0) && z:Health() > max * 0.33 then
				ply.GFR_ZNextWaste = now + 2
				z:SetHealth(z:Health() - 1)
			end
			-- Lunges on its own (not once it's lost to the hunger: then it's hunting by itself anyway)
			if !eating && !ply.GFR_ZLost && !z.GOTDR_CurEnt && now >= (ply.GFR_ZNextLunge or 0) then
				ply.GFR_ZNextLunge = now + math.Rand(10, 18)
				Lunge(ply, z)
			end
		end
	end
end)

-- Biting the living: blood is food too
hook.Add("EntityTakeDamage", "GFR_ZHunger_Blood", function(target, dmg)
	local att = dmg:GetAttacker()
	local ply = IsValid(att) && att.GFR_ControlPlayer
	if !IsValid(ply) or target == att then return end
	if (target:IsNPC() && target:Health() > 0 && !(GFR.IsZombie && GFR.IsZombie(target))) or (target:IsPlayer() && target:Alive()) then
		GFR.ZombieFeed(ply, 2)
	end
end)

-- A fresh zombie starts fairly fed (it just ate, or was just bitten); getting back up after going down keeps the meter.
-- Respawning as a survivor clears it.
hook.Add("PlayerSpawn", "GFR_ZHunger_Spawn", function(ply)
	timer.Simple(0.5, function()
		if !IsValid(ply) or ply.GFR_IsZombie or ply:GetNW2Bool("GFR_ZombieSpectate") then return end
		ply.GFR_ZHunger, ply.GFR_ZStage, ply.GFR_ZPrevH, ply.GFR_ZLost = nil, nil, nil, nil
		ply:SetNW2Float("GFR_ZHunger", -1)
		ply:SetNW2Bool("GFR_ZLost", false)
	end)
end)

-- Checking it: gfr_zhunger (prints it), gfr_zhunger <0-100> (sets it, admins: to try the stages)
concommand.Add("gfr_zhunger", function(ply, _, args)
	if !IsValid(ply) then return end
	local v = tonumber(args[1] or "")
	if v && GFR.CanCheat(ply) && ply.GFR_IsZombie then Set(ply, v) end
	ply:PrintMessage(HUD_PRINTCONSOLE, string.format("[GFR] zombie: %s  hunger: %s  stage: %s", tostring(ply.GFR_IsZombie or false),
		tostring(ply.GFR_ZHunger), ply.GFR_IsZombie and GFR.ZombieHungerStage(ply) or "-"))
end)

function GFR.ZombieHungerStart(ply)
	if ply.GFR_ZHunger == nil then Set(ply, 70) end
	ply:SetNW2Float("GFR_ZHunger", ply.GFR_ZHunger)
end
