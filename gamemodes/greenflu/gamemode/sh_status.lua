--[[
	Green Flu: Reimagined - buffs and debuffs (status effects)
	Shown as tags above the HUD cores (cl_hud.lua), with the time left on the ones that wear off.

	Buffs
		Well fed        hunger and thirst both above 80%: stamina comes back faster, health slowly mends up to half
		Rested          slept in a bed / sleeping bag: more stamina (faster back, slower to run out) for a day
		Adrenaline      adrenaline / stimulant shots: no stamina used, less damage taken, pain and a broken leg
		                don't slow you - for a minute. Then a Crash.
	Debuffs
		Crash           after Adrenaline: stamina comes back slowly for a while
		Broken leg      a bad fall: limping, no sprinting or jumping, until a splint (or a surgical kit) sets it
		Pain            a heavy hit, an explosion, a bad fall: your aim drifts; fades, or painkillers / morphine
		Food poisoning  raw or tainted food: you throw up now and then, thirst drains fast; wears off, or a medkit /
		                antibiotics
		Exhausted       two days without sleep: stamina only fills to 60% and comes back slowly - sleep it off

	NW2 "GFR_Status": "id:endTime,id:endTime" (endTime 0 = until fixed). Stamina reads GFR.StatusMods (sh_stats.lua).
]]
GFR = GFR or {}

GFR.StatusDefs = {
	{id = "wellfed",    name = "Well fed",       buff = true},
	{id = "rested",     name = "Rested",         buff = true},
	{id = "adrenaline", name = "Adrenaline",     buff = true},
	{id = "crash",      name = "Crash"},
	{id = "brokenleg",  name = "Broken leg"},
	{id = "pain",       name = "Pain"},
	{id = "poisoned",   name = "Food poisoning"},
	{id = "exhausted",  name = "Sleep deprived"} -- (not "Exhausted": that's the out-of-stamina warning)
}
GFR.StatusById = {}
for _, d in ipairs(GFR.StatusDefs) do GFR.StatusById[d.id] = d end

-- What you have right now: {id = endTime (0 = until fixed)}
function GFR.Statuses(ply)
	local raw = ply:GetNW2String("GFR_Status", "")
	if ply.GFR_StatusRaw != raw or !ply.GFR_StatusParsed then
		local all = {}
		for id, t in string.gmatch(raw, "(%w+):([%d%.]+)") do all[id] = tonumber(t) end
		ply.GFR_StatusRaw, ply.GFR_StatusParsed = raw, all
	end
	-- (the ones that ran out drop off here)
	local out, now = {}, CurTime()
	for id, e in pairs(ply.GFR_StatusParsed) do
		if e == 0 or e > now then out[id] = e end
	end
	return out
end

function GFR.HasStatus(ply, id)
	local e = GFR.Statuses(ply)[id]
	return e != nil && (e == 0 or e > CurTime())
end

-- Stamina / thirst multipliers from what you have (sh_stats.lua)
function GFR.StatusMods(ply)
	local m = {regen = 1, drain = 1, cap = 100, thirst = 1}
	local s = GFR.Statuses(ply)
	local now = CurTime()
	local function on(id) local e = s[id] return e != nil && (e == 0 or e > now) end
	if on("wellfed") then m.regen = m.regen * 1.3 end
	if on("rested") then m.regen = m.regen * 1.25 m.drain = m.drain * 0.8 end
	if on("adrenaline") then m.drain = 0 m.regen = m.regen * 1.5 end
	if on("crash") then m.regen = m.regen * 0.5 end
	if on("exhausted") then m.regen = m.regen * 0.6 m.cap = 60 end
	if on("poisoned") then m.thirst = m.thirst * 2.5 end
	return m
end

-- A broken leg: a slow limp, no sprinting or jumping (adrenaline masks it). Shared so it's predicted.
hook.Add("SetupMove", "GFR_Status_Limp", function(ply, mv)
	if ply:GetMoveType() == MOVETYPE_NOCLIP or ply:GetNW2Bool("GFR_IsZombie") then return end
	if !GFR.HasStatus(ply, "brokenleg") or GFR.HasStatus(ply, "adrenaline") then return end
	local limp = ply:GetWalkSpeed() * 0.6
	mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(), limp))
	mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), limp))
	if ply:OnGround() then mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP))) end
end)

if CLIENT then
	-- Pain: your aim drifts, a slow wobble (the real aim, not just the view)
	hook.Add("CreateMove", "GFR_Status_Pain", function(cmd)
		local ply = LocalPlayer()
		if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
		if !GFR.HasStatus(ply, "pain") or GFR.HasStatus(ply, "adrenaline") then return end
		local t = CurTime()
		local a = cmd:GetViewAngles()
		a.p = a.p + math.sin(t * 1.3) * 0.035 + math.sin(t * 3.1) * 0.012
		a.y = a.y + math.cos(t * 0.9) * 0.045
		cmd:SetViewAngles(a)
	end)
	return
end

---------------------------------------------------------------------------------------------------------------------------------------------
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvLegSpeed = CreateConVar("gfr_status_leg_fall_speed", "720", flags, "Landing speed that breaks a leg (GMod's fall damage starts at about 580; a lethal fall is about 1000)")

local function Write(ply, list)
	local parts = {}
	for id, e in pairs(list) do parts[#parts + 1] = id .. ":" .. (e == 0 and "0" or string.format("%.1f", e)) end
	table.sort(parts)
	ply:SetNW2String("GFR_Status", table.concat(parts, ","))
end

-- Give a status for `secs` seconds (nil / 0: until it's fixed). An existing one keeps whichever lasts longer.
function GFR.AddStatus(ply, id, secs)
	if !IsValid(ply) or !GFR.StatusById[id] then return end
	local list = table.Copy(GFR.Statuses(ply))
	local e = (secs && secs > 0) and (CurTime() + secs) or 0
	local cur = list[id]
	if cur != nil && (cur == 0 or (e != 0 && cur >= e)) then return end
	list[id] = e
	Write(ply, list)
end

function GFR.RemoveStatus(ply, id)
	local list = table.Copy(GFR.Statuses(ply))
	if list[id] == nil then return end
	list[id] = nil
	Write(ply, list)
end

local function Notify(ply, msg) if GFR.Notify then GFR.Notify(ply, msg) end end

-- A day in the game, in real seconds (the day/night cycle: sh_daynight.lua)
local function DaySecs()
	return (GFR.RealSecondsPerHour && GFR.RealSecondsPerHour() or 60) * 24
end

hook.Add("PlayerSpawn", "GFR_Status_Spawn", function(ply)
	ply:SetNW2String("GFR_Status", "")
	ply.GFR_AwakeSince = CurTime()
	ply.GFR_HadAdrenaline = nil
	ply.GFR_ExhaustTold = nil
end)

-- Slept (sv_base.lua): rested for a day, the tiredness gone
function GFR.SleptWell(ply)
	ply.GFR_AwakeSince = CurTime()
	ply.GFR_ExhaustTold = nil
	GFR.RemoveStatus(ply, "exhausted")
	GFR.AddStatus(ply, "rested", DaySecs())
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- What sets them off
local painkillers = {
	other_morphine = true, weapon_eft_injectormorphine = true, weapon_eft_injectorpropital = true, weapon_eft_anaglin = true,
	nmrih_medical_pills = true, other_pills = true, uh_painkillers = true, uh_painkillers_alt = true, zps_painkillers = true,
	contagion_medical_pain_reliever = true, gfr_scp_painkillers = true
}
local splints = {weapon_eft_alusplint = true, weapon_eft_surgicalkit = true}
local stims = {gfr_scp_adrenaline = true, weapon_eft_injectoradrenaline = true, weapon_eft_injectorl1 = true}
local poisonCures = {weapon_eft_augmentin = true}

hook.Add("GFR_ItemUsed", "GFR_Status_Items", function(ply, class, ent)
	if painkillers[class] && GFR.HasStatus(ply, "pain") then
		GFR.RemoveStatus(ply, "pain")
		Notify(ply, "The pain dulls.")
	end
	if (splints[class] or string.find(class, "splint", 1, true)) && GFR.HasStatus(ply, "brokenleg") then
		GFR.RemoveStatus(ply, "brokenleg")
		Notify(ply, "You set the leg and splint it. You can walk properly again.")
	end
	if stims[class] then
		GFR.RemoveStatus(ply, "crash")
		GFR.AddStatus(ply, "adrenaline", 60)
		Notify(ply, "Your heart hammers. Nothing hurts.")
	end
	if (poisonCures[class] or (GFR.Medkits && GFR.Medkits[class])) && GFR.HasStatus(ply, "poisoned") then
		GFR.RemoveStatus(ply, "poisoned")
		Notify(ply, "Your stomach settles.")
	end
	-- Food that's gone bad: raw zombie meat, anything tainted, now and then cooked zombie meat
	local chance = (string.StartWith(class, "meat_") and 50) or (IsValid(ent) && ent.GFR_Contaminated and 40)
		or (class == "gfr_food_zmeat_cooked" and 10) or 0
	if chance > 0 && math.Rand(0, 100) < chance then
		GFR.AddStatus(ply, "poisoned", 180)
		Notify(ply, "Your stomach lurches. That was bad.")
	end
end)

-- A high fall breaks a leg (and hurts)
hook.Add("OnPlayerHitGround", "GFR_Status_Fall", function(ply, inWater, onFloater, speed)
	if inWater or ply:GetNW2Bool("GFR_IsZombie") or ply:GetMoveType() == MOVETYPE_NOCLIP or speed < cvLegSpeed:GetFloat() then return end
	if !GFR.HasStatus(ply, "brokenleg") then
		GFR.AddStatus(ply, "brokenleg")
		ply:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav", 75)
		ply:ViewPunch(Angle(10, math.Rand(-4, 4), 0))
		Notify(ply, "Something cracked as you landed. Your leg won't take your weight.")
	end
	GFR.AddStatus(ply, "pain", 60)
end)

-- Heavy hits and explosions hurt; adrenaline takes the edge off the damage
hook.Add("EntityTakeDamage", "GFR_Status_Damage", function(ply, dmg)
	if !ply:IsPlayer() or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	if GFR.HasStatus(ply, "adrenaline") then dmg:ScaleDamage(0.75) end
	if dmg:IsFallDamage() then return end -- (falls: OnPlayerHitGround)
	if dmg:GetDamage() >= 25 or dmg:IsExplosionDamage() then GFR.AddStatus(ply, "pain", 40) end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Each second: well fed / exhausted follow how you are; adrenaline ends in a crash; food poisoning; mending
local function Vomit(ply)
	ply:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 70, 80)
	ply:EmitSound("vo/npc/male01/pain0" .. math.random(1, 9) .. ".wav", 65, 90)
	ply:ViewPunch(Angle(14, 0, 0))
	ply:ScreenFade(SCREENFADE.IN, Color(70, 90, 20, 90), 0.8, 0)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 40 - Vector(0, 0, 90), filter = ply})
	if tr.Hit then util.Decal("YellowBlood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal) end
	ply:SetNW2Float("GFR_Hunger", math.max(ply:GetNW2Float("GFR_Hunger", 100) - 8, 0))
	ply:SetNW2Float("GFR_Thirst", math.max(ply:GetNW2Float("GFR_Thirst", 100) - 6, 0))
	Notify(ply, "You double over and throw up.")
end

timer.Create("GFR_Status_Tick", 1, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		if !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then continue end
		local s = GFR.Statuses(ply)

		-- Well fed: both above 80%
		local fed = ply:GetNW2Float("GFR_Hunger", 100) > 80 && ply:GetNW2Float("GFR_Thirst", 100) > 80
		if fed && s.wellfed == nil then GFR.AddStatus(ply, "wellfed")
		elseif !fed && s.wellfed != nil then GFR.RemoveStatus(ply, "wellfed") end
		-- ...and it mends you slowly, up to half health
		if fed && !ply.GFR_Bleeding && ply:Health() < ply:GetMaxHealth() * 0.5 then
			ply.GFR_MendT = (ply.GFR_MendT or 0) + 1
			if ply.GFR_MendT >= 5 then ply.GFR_MendT = 0 ply:SetHealth(ply:Health() + 1) end
		end

		-- Exhausted: two days awake. Told once (until you sleep or respawn), not every second the status is checked
		if !ply.GFR_Sleeping && now - (ply.GFR_AwakeSince or now) > DaySecs() * 2 then
			if s.exhausted == nil then GFR.AddStatus(ply, "exhausted") end
			if !ply.GFR_ExhaustTold then
				ply.GFR_ExhaustTold = true
				Notify(ply, "You haven't slept in days. Find a bed and rest.")
			end
		end

		-- Adrenaline wearing off: the crash
		if s.adrenaline != nil then
			ply.GFR_HadAdrenaline = true
		elseif ply.GFR_HadAdrenaline then
			ply.GFR_HadAdrenaline = nil
			GFR.AddStatus(ply, "crash", 45)
			Notify(ply, "The rush fades. Your legs feel like lead.")
		end

		-- Food poisoning: throwing up now and then
		if s.poisoned != nil then
			if !ply.GFR_NextVomit then ply.GFR_NextVomit = now + math.Rand(15, 30) end
			if now >= ply.GFR_NextVomit then
				ply.GFR_NextVomit = now + math.Rand(30, 50)
				Vomit(ply)
			end
		else
			ply.GFR_NextVomit = nil
		end

		-- (keep the list tidy: drop the ones that ran out)
		local raw = ply:GetNW2String("GFR_Status", "")
		local alive = 0
		for _ in pairs(s) do alive = alive + 1 end
		local listed = select(2, string.gsub(raw, ":", ""))
		if listed != alive then Write(ply, s) end
	end
end)
