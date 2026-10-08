--[[
	Custom Apocalypse Project - Infection
	Replaces GMod of the Dead's player infection with our own. NPC infection is still handled by GOTDR.

	How you catch it:
		Bite        - a zombie's grab/bite attack (high chance)
		Claw        - any other zombie hit (low chance)
		Bad food    - food/drink taken from zombie bodies may be contaminated (tinted red), human meat always risky
		Boomer bile - every time a boomer pukes on you (sv_parasite.lua)

	No cure. Treatment only buys time:
		Painkillers / morphine / medkits suppress progress for a few minutes (and ease symptoms)
		ZP:S Inoculator suppresses for a long time and pushes the infection back
		Blood bag pushes it back a little
		Bandages and medkits stop bleeding

	Stages (once past incubation, gfr_infection_reveal):
		1 Infected  - coughing
		2 Fever     - slower stamina regen, faster thirst, blurry vision
		3 Turning   - health slowly drains, vision darkens
		100%        - you die and rise as a zombie wearing your gear; the camera follows it.
		              Kill your zombie to get your belongings back.
	Dying in the Turning stage (or being killed by zombies) also makes you rise, unless it was a headshot.

	Player fields: GFR_Inf (0-100 or nil), GFR_SuppressUntil, GFR_Bleeding, GFR_InfStage (read by gfr_stats.lua)
	NW2: GFR_Infection (0-1, 0 while incubating), GFR_InfSuppressed, GFR_Bleeding
]]

GFR = GFR or {}

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled   = CreateConVar("gfr_infection_enabled", "1", flags, "Enable the Green Flu: Reimagined infection system")
local cvMinutes   = CreateConVar("gfr_infection_minutes", "45", flags, "Minutes from infection to turning with no treatment")
local cvReveal    = CreateConVar("gfr_infection_reveal", "8", flags, "Infection % before symptoms start (incubation, hidden from HUD)")
local cvBite      = CreateConVar("gfr_infection_bite", "90", flags, "% chance a bite infects you")
local cvClaw      = CreateConVar("gfr_infection_claw", "8", flags, "% chance a normal zombie hit infects you")
local cvFood      = CreateConVar("gfr_infection_food", "40", flags, "% chance contaminated food infects you")
local cvRawMeat   = CreateConVar("gfr_infection_rawmeat", "60", flags, "% chance raw zombie meat infects you")
local cvCooked    = CreateConVar("gfr_infection_cookedmeat", "10", flags, "% chance cooked zombie meat infects you")
local cvBleed     = CreateConVar("gfr_bleed_chance", "30", flags, "% chance a slash/bullet/zombie hit makes you bleed")
local cvSpectate  = CreateConVar("gfr_turn_spectate", "15", flags, "Seconds you must watch your zombie before you can respawn")

util.AddNetworkString("GFR_BloodSplat")
util.AddNetworkString("GFR_Notify")

local function Notify(ply, msg)
	net.Start("GFR_Notify")
	net.WriteString(msg)
	net.Send(ply)
end
GFR.Notify = Notify

local function Roll(percent)
	return math.Rand(0, 100) < percent
end

local hl2Zombies = {
	npc_zombie = true, npc_zombie_torso = true, npc_fastzombie = true, npc_fastzombie_torso = true,
	npc_poisonzombie = true, npc_zombine = true
}
-- The zombie NPC everything spawns: L4D-based infected (npc_gfr_infected), or the older GOTDR one if the L4D pack is missing
function GFR.InfectedClass()
	if scripted_ents.GetStored("npc_gfr_infected") && file.Exists("vj_base/extensions/l4d_com_infected.lua", "LUA") then return "npc_gfr_infected" end
	return "npc_vj_rtrg_zombie_pm"
end

-- Lie on the ground a while, then get up (whichever zombie class it is)
local riseAnimsGOTDR = {[ACT_SIGNAL1] = {"infectionrise", "infectionriseold"}, [ACT_SIGNAL2] = {"slumprise_a", "slumprise_a2"}, [ACT_SIGNAL3] = {"infectionrise2"}}
function GFR.ZombieRise(z, lieTime)
	if !IsValid(z) then return end
	if z.GFR_RiseFromGround then z:GFR_RiseFromGround(lieTime) return end
	if !(z.SetStatus && z.PlayAnim) then return end
	local death = ({ACT_SIGNAL1, ACT_SIGNAL2, ACT_SIGNAL3})[math.random(3)]
	z:PlayAnim(death, true, 120, false)
	z:SetStatus(false, false)
	timer.Simple(lieTime or math.Rand(4, 7), function()
		if !IsValid(z) then return end
		z:SetStatus(true, false)
		local anims = riseAnimsGOTDR[death]
		local anim = anims[math.random(#anims)]
		z:PlayAnim(anim, true, false, false)
		local seq = z:LookupSequence(anim)
		timer.Simple(seq >= 0 and z:SequenceDuration(seq) or 3, function()
			if IsValid(z) then z:SetStatus(true, true) end
		end)
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Losing to the infection (players here, NPCs in sv_extract.lua: GFR.TurnNPC): the body drops and lies still,
-- starts twitching and groaning, then slowly gets up as one of them. Destroy the head first and it stays down.
local cvTurnLie    = CreateConVar("gfr_turn_lie", "15", FCVAR_ARCHIVE, "Seconds a body that lost to the infection lies still")
local cvTurnTwitch = CreateConVar("gfr_turn_twitch", "10", FCVAR_ARCHIVE, "Seconds it twitches after that before getting up")

local function PoseFrom(rag, src)
	local vel = src:GetVelocity()
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if !IsValid(phys) then continue end
		local sb = src:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)))
		local m = sb && src:GetBoneMatrix(sb)
		if m then
			phys:SetPos(m:GetTranslation())
			phys:SetAngles(m:GetAngles())
		end
		phys:SetVelocity(vel)
		phys:Wake()
	end
end

-- A ragdoll of src (player or NPC) in its current pose. look = {model, skin, bodygroups, color}
function GFR.DropTurningBody(src, look)
	if !look.model or !util.IsValidRagdoll(look.model) then return end
	local rag = ents.Create("prop_ragdoll")
	if !IsValid(rag) then return end
	rag:SetModel(look.model)
	rag:SetPos(src:GetPos())
	rag:SetAngles(Angle(0, src:GetAngles().y, 0))
	rag:Spawn()
	rag:Activate()
	rag:SetSkin(look.skin or 0)
	for i, v in pairs(look.bodygroups or {}) do rag:SetBodygroup(i, v) end
	if look.color then rag:SetNW2Vector("GFR_PlyColor", look.color) end -- clothes colour (sh_zombieplayer.lua)
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	PoseFrom(rag, src)
	rag.GFR_TurningBody = true -- parasites leave it alone; its head can be destroyed (sv_rise.lua)
	return rag
end

local function Twitch(rag, strength)
	local n = rag:GetPhysicsObjectCount()
	if n <= 0 then return end
	for _ = 1, math.random(1, 3) do
		local phys = rag:GetPhysicsObjectNum(math.random(0, n - 1))
		if IsValid(phys) then
			phys:ApplyForceCenter(VectorRand() * phys:GetMass() * 150 * strength + Vector(0, 0, phys:GetMass() * 70 * strength))
		end
	end
end

local function RiseFromBody(rag, look, opts)
	local pelvis = rag:LookupBone("ValveBiped.Bip01_Pelvis")
	local p = pelvis and rag:GetBonePosition(pelvis) or rag:GetPos()
	local tr = util.TraceLine({start = p + Vector(0, 0, 10), endpos = p - Vector(0, 0, 120), filter = rag, mask = MASK_NPCSOLID_BRUSHONLY})
	local yaw = rag:GetAngles().y
	rag:Remove()
	local z = ents.Create(GFR.InfectedClass())
	if !IsValid(z) then return end
	z:SetPos(tr.HitPos + Vector(0, 0, 2))
	z:SetAngles(Angle(0, yaw, 0))
	z.GFR_ForceModel = look.model
	z.GFR_ForceSkin = look.skin
	z.GFR_ForceBodygroups = look.bodygroups
	z.GFR_ForceColor = look.color
	z.RTRG_ForceRunner = opts.runner or nil
	z:Spawn()
	z:Activate()
	if opts.name then z:SetName(opts.name) end
	z.GFR_TurnedAt = CurTime() -- still has fresh pockets (sv_loot.lua)
	if GFR.TrackZombie then GFR.TrackZombie(z) end
	GFR.ZombieRise(z, 1.5) -- already lay there long enough: a short beat, then it drags itself up
	return z
end

-- Runs the lie / twitch / rise on a body from GFR.DropTurningBody. opts: runner, name, onRise(z), onFail(pos),
-- lie / twitch (seconds, override the convars), rise(rag) (does the getting up itself instead of an AI zombie)
function GFR.TurnBody(rag, look, opts)
	opts = opts or {}
	local lie, twitch = opts.lie or cvTurnLie:GetFloat(), math.max(opts.twitch or cvTurnTwitch:GetFloat(), 0)
	local id = "GFR_TurnBody" .. rag:EntIndex()
	local start, nextT, lastPos = CurTime(), 0, rag:GetPos()
	timer.Create(id, 0.2, 0, function()
		-- Head destroyed, carved up or eaten before it got up
		if !IsValid(rag) or rag.GFR_HeadGone then
			timer.Remove(id)
			if opts.onFail then opts.onFail(lastPos) end
			return
		end
		lastPos = rag:GetPos()
		local t = CurTime() - start
		if t < lie then return end
		if t < lie + twitch then
			if CurTime() >= nextT then
				local p = (t - lie) / math.max(twitch, 0.1) -- it builds up
				Twitch(rag, 0.4 + p)
				if math.random(3) == 1 && GFR.ZombieVoice then GFR.ZombieVoice(rag, "pain", 62 + p * 12, math.random(75, 90), look.model) end
				nextT = CurTime() + math.Rand(1.2, 2.4) * (1 - p * 0.6)
			end
			return
		end
		timer.Remove(id)
		if opts.rise then opts.rise(rag) return end
		local z = RiseFromBody(rag, look, opts)
		if IsValid(z) then
			if GFR.ZombieVoice then GFR.ZombieVoice(z, "alert", 75, nil, look.model) end
			if opts.onRise then opts.onRise(z) end
		elseif opts.onFail then
			opts.onFail(lastPos)
		end
	end)
	return lie + twitch
end

function GFR.IsZombie(ent)
	if !IsValid(ent) or ent:IsPlayer() then return false end
	if ent.VJ_ID_Undead or hl2Zombies[ent:GetClass()] then return true end
	local cls = ent.VJ_NPC_Class
	if istable(cls) then
		for _, c in ipairs(cls) do
			if c == "CLASS_ZOMBIE" then return true end
		end
	end
	return ent:IsNPC() && ent:Classify() == CLASS_ZOMBIE
end
local IsZombie = GFR.IsZombie

---------------------------------------------------------------------------------------------------------------------------------------------
-- Core
function GFR.Infect(ply, amount)
	if !cvEnabled:GetBool() or !IsValid(ply) or !ply:Alive() or ply:HasGodMode() then return end
	ply.GFR_Inf = math.Clamp((ply.GFR_Inf or 0) + amount, 0.5, 100)
end

local function SetBleeding(ply, bleeding)
	ply.GFR_Bleeding = bleeding or nil
	ply:SetNW2Bool("GFR_Bleeding", bleeding)
end

local function ResetInfection(ply)
	ply.GFR_Inf = nil
	ply.GFR_InfStage = 0
	ply.GFR_SuppressUntil = 0
	ply.GFR_Revealed = nil
	ply.GFR_MaxStage = nil
	ply.GFR_Turning = nil
	ply.GFR_NextCough = nil
	ply:SetNW2Float("GFR_Infection", 0)
	ply:SetNW2Bool("GFR_InfSuppressed", false)
	SetBleeding(ply, false)
end

hook.Add("PlayerSpawn", "GFR_Infection_Spawn", function(ply)
	ResetInfection(ply)
	ply.GFR_SpectateUntil = nil
	ply:SetNW2Bool("GFR_ZombieSpectate", false)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Exposure: hits from zombies (bites and claws)
local bleedTypes = bit.bor(DMG_SLASH, DMG_BULLET, DMG_BUCKSHOT, DMG_CLUB)

local function IsBiteAttack(zombie)
	local seq = string.lower(zombie:GetSequenceName(zombie:GetSequence()) or "")
	return string.find(seq, "choke", 1, true) or string.find(seq, "grab", 1, true) or string.find(seq, "bite", 1, true) or string.find(seq, "eat", 1, true)
end

hook.Add("EntityTakeDamage", "GFR_Infection_Damage", function(target, dmginfo)
	if !cvEnabled:GetBool() then return end
	local attacker = dmginfo:GetAttacker()

	-- A player got hurt
	if target:IsPlayer() then
		if !target:Alive() or target:HasGodMode() then return end
		target.GFR_LastDmgType = dmginfo:GetDamageType()
		local fromZombie = IsZombie(attacker)
		if fromZombie then
			if IsBiteAttack(attacker) then
				if CurTime() > (target.GFR_NextBiteMsg or 0) then
					Notify(target, "You've been bitten!")
					target.GFR_NextBiteMsg = CurTime() + 3
				end
				if Roll(cvBite:GetFloat()) then GFR.Infect(target, 10) end
			elseif Roll(cvClaw:GetFloat()) then
				GFR.Infect(target, target.GFR_Inf and 3 or 1)
			end
		end
		if !target.GFR_Bleeding && dmginfo:GetDamage() >= 8 && (fromZombie or bit.band(dmginfo:GetDamageType(), bleedTypes) != 0) && Roll(cvBleed:GetFloat()) then
			SetBleeding(target, true)
			Notify(target, "You're bleeding. Find a bandage.")
		end
		return
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Items: contaminated food, treatment, bandages
local painkillers = {
	nmrih_medical_pills = true, other_pills = true, uh_painkillers = true, uh_painkillers_alt = true,
	zps_painkillers = true, contagion_medical_pain_reliever = true,
	weapon_eft_anaglin = true,
	gfr_scp_painkillers = true
}
local medkits = {
	eft_medkit = true, eft_medkit_army = true, eft_medkit_grizzly = true, nmrih_medkit = true,
	other_medkit_green = true, other_medkit_hdtf = true, other_medkit_pack_medium = true, other_medkit_pack_large = true,
	stalker_medkit_small = true, stalker_medkit_medium = true, stalker_medkit_large = true,
	uh_medkit = true, uh_medspray = true, zps_medkit = true, zps_medkit_classic = true,
	contagion_medical_kit = true, contagion_medical_bag = true,
	-- EFT Medical Items (sv_eftmeds.lua)
	weapon_eft_afak = true, weapon_eft_automedkit = true, weapon_eft_salewa = true, weapon_eft_grizzly = true, weapon_eft_surgicalkit = true,
	-- S.T.A.L.K.E.R. 2 Consumables (sv_consumables.lua)
	gfr_s2_medkit = true, gfr_s2_medkit_army = true, gfr_s2_medkit_sci = true
}
local bandages = {
	eft_bandage = true, eft_bandage_army = true, nmrih_medical_bandages = true, other_bandages = true,
	stalker_medical_bandage = true, uh_bandages = true, serious_sam_health_bandages = true,
	weapon_eft_cat = true,
	gfr_s2_bandage = true
}
-- seconds of suppression, % pushed back
local treatments = {
	other_morphine = {suppress = 240},
	zps_inoculator = {suppress = 1200, pushback = 15},
	other_blood_bag = {pushback = 10},
	weapon_eft_injectormorphine = {suppress = 240},
	weapon_eft_augmentin = {suppress = 600},           -- antibiotics
	weapon_eft_injectortg12 = {suppress = 900, pushback = 15}, -- antidote
	weapon_eft_injectoretg = {suppress = 120},
	weapon_eft_injectorpropital = {suppress = 300}
}
for class in pairs(painkillers) do treatments[class] = {suppress = 180} end
for class in pairs(medkits) do treatments[class] = {suppress = 300} end
GFR.Treatments = treatments
GFR.Bandages = bandages
GFR.Medkits = medkits

hook.Add("GFR_ItemUsed", "GFR_Infection_Items", function(ply, class, ent)
	if !cvEnabled:GetBool() then return end

	if string.StartWith(class, "meat_") then
		-- Raw zombie flesh: the virus is still in it
		Notify(ply, "Raw dead flesh... your stomach turns.")
		if Roll(cvRawMeat:GetFloat()) then GFR.Infect(ply, ply.GFR_Inf and 4 or 2) end
	elseif class == "gfr_food_zmeat_cooked" then
		-- Cooking kills most of it, not all
		if Roll(cvCooked:GetFloat()) then GFR.Infect(ply, 1) end
	elseif IsValid(ent) && ent.GFR_Contaminated then
		Notify(ply, "That tasted of blood...")
		if Roll(cvFood:GetFloat()) then GFR.Infect(ply, ply.GFR_Inf and 3 or 1) end
	end

	if ply.GFR_Bleeding && (bandages[class] or medkits[class]) then
		SetBleeding(ply, false)
		Notify(ply, "The bleeding has stopped.")
	end

	local t = treatments[class]
	if t && ply.GFR_Inf then
		if t.suppress then
			-- Stacks, but never more than 30 minutes ahead
			local from = math.max(CurTime(), ply.GFR_SuppressUntil or 0)
			ply.GFR_SuppressUntil = math.min(from + t.suppress, CurTime() + 1800)
		end
		if t.pushback then
			ply.GFR_Inf = math.max(ply.GFR_Inf - t.pushback, 0.5)
		end
		if ply.GFR_Revealed then
			Notify(ply, t.pushback && "You feel the fever pull back... for now." or "The symptoms ease... for now.")
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Turning
local skipWeapons = {weapon_physgun = true, gmod_tool = true, gmod_camera = true, weapon_fists = true, arc9_cod2019_me_fist = true}

local function CollectGear(ply)
	local gear = {name = ply:Nick(), weapons = {}, ammo = {}, items = table.Copy(ply.GFR_Inv or {}), caps = ply:GetNW2Int("GFR_Caps", 0)}
	-- The bag on your back goes with your body too (put it on again to get the slots back)
	local bag = ply.GFR_BagClass
	if bag && GFR.CustomItems[bag] then
		table.insert(gear.items, 1, {class = bag, count = 1, contaminated = false, model = GFR.CustomItems[bag].model})
	end
	-- Died with a consumable in your hands (sv_consumables.lua): it goes back in the bag, not as a weapon
	local c = ply.GFR_Consume
	if c && ply:GetAmmoCount(c.ammo) > 0 then
		table.insert(gear.items, {class = c.class, count = 1, contaminated = false, model = GFR.CustomItems[c.class] && GFR.CustomItems[c.class].model})
	end
	-- ...and the one lined up to use next
	if c && c.next then
		table.insert(gear.items, {class = c.next, count = 1, contaminated = false, model = GFR.CustomItems[c.next] && GFR.CustomItems[c.next].model})
	end
	for _, wep in ipairs(ply:GetWeapons()) do
		local wc = wep:GetClass()
		if IsValid(wep) && !skipWeapons[wc] && !string.StartWith(wc, "weapon_stalker2_") && !string.StartWith(wc, "weapon_scpsl_") then
			-- ARC9 guns keep the parts you fitted (sh_attachments.lua)
			gear.weapons[#gear.weapons + 1] = {class = wep:GetClass(), clip1 = wep:Clip1(), clip2 = wep:Clip2(), atts = GFR.CaptureWeaponAtts && GFR.CaptureWeaponAtts(wep)}
		end
	end
	for id, count in pairs(ply:GetAmmo()) do
		if count > 0 then gear.ammo[id] = count end
	end
	-- Loose attachments in your ARC9 stash
	if GFR.TakeAttStash then gear.attstash = GFR.TakeAttStash(ply) end
	return gear
end

local origCreateZombie -- GOTDR's VJ_GOTDR_CreateZombie, captured at init

-- Spawn the player's zombie ourselves (GOTDR's VJ_GOTDR_CreateZombie only does it for entities flagged VJ_ID_Living,
-- which players aren't, so it silently made nothing). It wears the player's own model, lies there, then gets up.
local riseAnims = {[ACT_SIGNAL1] = {"infectionrise", "infectionriseold"}, [ACT_SIGNAL2] = {"slumprise_a", "slumprise_a2"}, [ACT_SIGNAL3] = {"infectionrise2"}}

local DropGearBag -- below

local function RiseAsZombie(ply, gear)
	if !IsValid(ply) or !scripted_ents.GetStored(GFR.InfectedClass()) then return end
	local pos, ang = ply:GetPos(), Angle(0, ply:EyeAngles().y, 0)
	local bodygroups = {}
	for i = 0, ply:GetNumBodyGroups() - 1 do bodygroups[i] = ply:GetBodygroup(i) end
	local look = {model = ply:GetModel(), skin = ply:GetSkin(), bodygroups = bodygroups, color = ply:GetPlayerColor()}
	local runner = ply.GFR_ParasiteInfected or nil -- a parasite got into you (sv_parasite.lua): you come back fast

	-- You drop where you stood and lie there a while, twitching before you get back up
	local old = ply:GetRagdollEntity()
	local rag = GFR.DropTurningBody(ply, look)
	if IsValid(rag) then
		if IsValid(old) then old:Remove() end
		ply.GFR_ParasiteInfected = nil
		rag.GFR_PlayerBody = ply
		local total = GFR.TurnBody(rag, look, {
			runner = runner,
			name = ply:Nick() .. " (Zombie)",
			onRise = function(z)
				z.GFR_Gear = gear -- the zombie carries everything; kill it to get it back
				if IsValid(ply) && !ply:Alive() then
					ply:SpectateEntity(z)
					ply.GFR_SpectateUntil = CurTime() + cvSpectate:GetFloat()
				end
			end,
			onFail = function(where)
				DropGearBag(where, gear)
				if IsValid(ply) && !ply:Alive() then
					ply.GFR_SpectateUntil = CurTime() + 2
					Notify(ply, "Your body was put down before it could get back up.")
				end
			end
		})
		-- Camera stays on your body, seen through dead eyes (vein overlay, sh_zombieplayer.lua)
		ply:Spectate(OBS_MODE_CHASE)
		ply:SpectateEntity(rag)
		ply.GFR_SpectateUntil = CurTime() + total + 3
		ply:SetNW2Bool("GFR_ZombieSpectate", true)
		return
	end

	-- Couldn't make a body (odd playermodel): straight to the zombie
	local z = ents.Create(GFR.InfectedClass())
	z:SetPos(pos)
	z:SetAngles(ang)
	z.GFR_ForceModel = ply:GetModel()
	z.GFR_ForceSkin = ply:GetSkin()
	z.GFR_ForceBodygroups = bodygroups
	z.GFR_ForceColor = ply:GetPlayerColor()
	z.RTRG_ForceRunner = ply.GFR_ParasiteInfected or nil -- a parasite got into you (sv_parasite.lua): you come back fast
	ply.GFR_ParasiteInfected = nil
	z:Spawn()
	z:Activate()
	z:SetName(ply:Nick() .. " (Zombie)")
	z.GFR_Gear = gear
	z.GFR_TurnedAt = CurTime()

	-- Lie dead for a few seconds, then rise
	GFR.ZombieRise(z, math.Rand(5, 9))

	-- Your corpse is the zombie now, not a ragdoll next to it
	local rag = ply:GetRagdollEntity()
	if IsValid(rag) then rag:Remove() end

	-- Camera follows your body, seen through dead eyes (vein overlay, sh_zombieplayer.lua)
	ply:Spectate(OBS_MODE_CHASE)
	ply:SpectateEntity(z)
	ply.GFR_SpectateUntil = CurTime() + cvSpectate:GetFloat()
	ply:SetNW2Bool("GFR_ZombieSpectate", true)
end

function GFR.Turn(ply)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_GivingIn or ply.GFR_IsZombie then return end
	-- You collapse and get up as your own zombie, which you control, the same as giving in (sv_extract.lua)
	if GFR.CollapseIntoZombie then
		ResetInfection(ply) -- (done: no ticking on, or turning again, while you lie there)
		ply.GFR_Turning = true
		Notify(ply, "You have turned.")
		GFR.CollapseIntoZombie(ply)
		ply.GFR_Turning = nil
		return
	end
	local gear = CollectGear(ply)
	ply.GFR_Turning = true
	Notify(ply, "You have turned.")
	ply:KillSilent()
	RiseAsZombie(ply, gear)
end

hook.Add("DoPlayerDeath", "GFR_Infection_CollectGear", function(ply)
	ply.GFR_DeathGear = CollectGear(ply)
end)

local function HasGear(gear)
	return gear && (#gear.weapons > 0 or !table.IsEmpty(gear.ammo) or #(gear.items or {}) > 0 or (gear.caps or 0) > 0)
end

function DropGearBag(pos, gear)
	if !HasGear(gear) then return end
	local bag = ents.Create("gfr_gear_bag")
	if !IsValid(bag) then return end
	bag:SetPos(pos + Vector(0, 0, 20))
	bag.Gear = gear
	bag:Spawn()
	bag:SetOwnerName(gear.name)
end
GFR.CollectGear = CollectGear
GFR.DropGearBag = DropGearBag

local function ShouldRise(ply, attacker)
	if !cvEnabled:GetBool() then return false end
	-- Shot in the head while tied up (sv_surrender.lua)
	if ply.GFR_Executed then return false end
	-- Killed by the dead, or far enough gone (turning stage, 67%+) that your body gets back up anyway
	if !((ply.GFR_Inf or 0) >= 67 or IsZombie(attacker)) then return false end
	if ply:LastHitGroup() == HITGROUP_HEAD then return false end
	local dmgType = ply.GFR_LastDmgType or 0
	if bit.band(dmgType, bit.bor(DMG_DISSOLVE, DMG_BLAST, DMG_ALWAYSGIB)) != 0 then return false end
	-- Return to Ravenholm's own infection already makes a zombie from this body
	if IsValid(attacker) && attacker.CNCR_VirusInfection == true then return false end
	return scripted_ents.GetStored(GFR.InfectedClass()) != nil
end

local TURNING = 67 -- infection % of the last stage ("Turning"): from here dying means getting back up

-- Infected (turning stage) and something else finishes you (a gun, a fall, a blade): you don't die and watch an AI zombie get up -
-- you drop, and get up as your own zombie, the same as losing to the infection (GFR.CollapseIntoZombie, sv_extract.lua).
-- Killed by the dead is sv_extract.lua's own (GFR_ZombieKill_GiveIn: it feeds on you first). A headshot, an
-- explosion or being burnt to nothing still ends you.
hook.Add("EntityTakeDamage", "GFR_Infection_DownNotDead", function(ply, dmg)
	if !ply:IsPlayer() or !ply:Alive() or (ply.GFR_Inf or 0) < TURNING or !cvEnabled:GetBool() or !GFR.CollapseIntoZombie then return end
	if ply.GFR_IsZombie or ply.GFR_GivingIn or ply.GFR_Collapsing or ply.GFR_Executed or ply.GFR_Bait or ply:HasGodMode() then return end
	if dmg:GetDamage() < ply:Health() then return end
	local att = dmg:GetAttacker()
	if IsZombie(att) then return end
	if bit.band(dmg:GetDamageType(), bit.bor(DMG_DISSOLVE, DMG_BLAST, DMG_ALWAYSGIB)) != 0 then return end
	if ply:LastHitGroup() == HITGROUP_HEAD && dmg:IsBulletDamage() then return end
	ply:SetHealth(1)
	ply:GodEnable()
	if ply:InVehicle() then ply:ExitVehicle() end
	ResetInfection(ply) -- (it's done its work)
	ply:ViewPunch(Angle(18, math.Rand(-8, 8), 0))
	ply:ScreenFade(SCREENFADE.IN, Color(120, 0, 0, 180), 0.6, 0)
	Notify(ply, "You're down. The infection will bring you back.")
	timer.Simple(0, function()
		if !IsValid(ply) or !ply:Alive() then return end
		local ok, err = xpcall(GFR.CollapseIntoZombie, debug.traceback, ply)
		if !ok then
			file.Append("gfr_debug.txt", os.date("%H:%M:%S") .. " infected death collapse: " .. tostring(err) .. "\n")
			ErrorNoHalt("[GFR] " .. tostring(err) .. "\n")
		end
		-- Never left standing in god mode if that didn't take
		if IsValid(ply) && ply:Alive() && !ply.GFR_Collapsing && !ply.GFR_IsZombie then
			ply:GodDisable()
			ply:Kill()
		end
	end)
	return true
end)

hook.Add("PlayerDeath", "GFR_Infection_Rise", function(ply, inflictor, attacker)
	if ply.GFR_Turning then return end
	-- Already a zombie (self-injected extract, sv_extract.lua): your zombie body was the corpse; no second one
	if ply.GFR_IsZombie or (ply.GFR_ExZombieUntil or 0) > CurTime() then return end
	local gear = ply.GFR_DeathGear
	if ShouldRise(ply, attacker) then
		-- The zombie carries everything; kill it to get it back
		timer.Simple(0, function()
			if IsValid(ply) && !ply:Alive() then RiseAsZombie(ply, gear) end
		end)
	else
		-- Stays dead: belongings are left where you fell
		DropGearBag(ply:GetPos(), gear)
	end
end)

hook.Add("PlayerDeathThink", "GFR_Infection_Spectate", function(ply)
	if ply.GFR_SpectateUntil && CurTime() < ply.GFR_SpectateUntil then return false end
end)

-- Your zombie dies: your belongings drop
hook.Add("OnNPCKilled", "GFR_Infection_DropGear", function(npc)
	if npc.GFR_Gear then DropGearBag(npc:GetPos(), npc.GFR_Gear) end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Progress + symptoms
local coughSounds = {"ambient/voices/cough1.wav", "ambient/voices/cough2.wav", "ambient/voices/cough3.wav", "ambient/voices/cough4.wav"}
local stageNames = {"You feel feverish... something is wrong.", "Your skin burns with fever.", "You can feel yourself slipping away..."}

timer.Create("GFR_Infection_Tick", 1, 0, function()
	if !cvEnabled:GetBool() then return end
	local now = CurTime()
	local rate = 100 / math.max(cvMinutes:GetFloat() * 60, 1)

	for _, ply in ipairs(player.GetAll()) do
		if !ply:Alive() or ply.GFR_IsZombie then continue end

		-- Bleeding: lose blood, wounds sometimes clot on their own
		if ply.GFR_Bleeding then
			ply.GFR_BleedT = (ply.GFR_BleedT or 0) + 1
			if ply.GFR_BleedT >= 4 then
				ply.GFR_BleedT = 0
				if ply:Health() > 1 then ply:SetHealth(ply:Health() - 1) end
			end
			if Roll(1) then
				SetBleeding(ply, false)
				Notify(ply, "Your wound has clotted.")
			end
		end

		if !ply.GFR_Inf then continue end

		local suppressed = now < (ply.GFR_SuppressUntil or 0)
		ply.GFR_Inf = ply.GFR_Inf + rate * (suppressed and 0.2 or 1)
		ply:SetNW2Bool("GFR_InfSuppressed", suppressed)

		if ply.GFR_Inf >= 100 then
			GFR.Turn(ply)
			continue
		end

		local revealed = ply.GFR_Inf >= cvReveal:GetFloat()
		if !revealed then
			ply.GFR_InfStage = 0
			ply:SetNW2Float("GFR_Infection", 0)
			continue
		end

		local stage = (ply.GFR_Inf < 34 and 1) or (ply.GFR_Inf < 67 and 2) or 3
		if stage > (ply.GFR_MaxStage or 0) then
			Notify(ply, stageNames[stage])
			ply.GFR_MaxStage = stage
		end
		ply.GFR_Revealed = true
		ply.GFR_InfStage = suppressed and math.max(stage - 1, 1) or stage
		ply:SetNW2Float("GFR_Infection", ply.GFR_Inf / 100)

		-- Coughing fits
		if !ply.GFR_NextCough then ply.GFR_NextCough = now + math.Rand(10, 30) end
		if now > ply.GFR_NextCough then
			ply:EmitSound(coughSounds[math.random(#coughSounds)], 70, math.random(95, 105))
			local base = (stage == 1) and 40 or 20
			ply.GFR_NextCough = now + math.Rand(base, base * 2) * (suppressed and 2 or 1)
		end

		-- Turning: the body is failing
		if stage == 3 && !suppressed then
			ply.GFR_DrainT = (ply.GFR_DrainT or 0) + 1
			if ply.GFR_DrainT >= 6 then
				ply.GFR_DrainT = 0
				if ply:Health() > 1 then ply:SetHealth(ply:Health() - 1) end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Take player infection over from GMod of the Dead (it still infects NPCs)
hook.Add("InitPostEntity", "GFR_Infection_TakeOverGOTDR", function()
	origCreateZombie = VJ_GOTDR_CreateZombie

	local origApply = VJ_GOTDR_InfectionApply
	if origApply then
		VJ_GOTDR_InfectionApply = function(victim, ...)
			if cvEnabled:GetBool() && IsValid(victim) && victim:IsPlayer() then
				victim.GOTDR_InfectedVictim = false
				return
			end
			return origApply(victim, ...)
		end
	end
	local origInfect = VJ_GOTDR_Infect
	if origInfect then
		VJ_GOTDR_Infect = function(victim, ...)
			if cvEnabled:GetBool() && IsValid(victim) && victim:IsPlayer() then return end
			-- Faction humans (sv_spawner.lua) are an invisible HL2 NPC under a playermodel:
			-- let the zombie copy the playermodel, not the hidden base model
			if IsValid(victim) && victim.GFR_PlayerModel then
				local body = victim.GFR_Body
				victim:SetModel(victim.GFR_PlayerModel)
				victim:SetRenderMode(RENDERMODE_NORMAL)
				victim:SetColor(color_white)
				if IsValid(body) then
					victim:SetSkin(body:GetSkin())
					for i = 0, body:GetNumBodyGroups() - 1 do victim:SetBodygroup(i, body:GetBodygroup(i)) end
				end
			end
			return origInfect(victim, ...)
		end
	end
	local origSetPly = VJ_GOTDR_SetPlayerZombie
	if origSetPly then
		VJ_GOTDR_SetPlayerZombie = function(victim, ...)
			if cvEnabled:GetBool() && IsValid(victim) && victim:IsPlayer() then return end
			return origSetPly(victim, ...)
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Debug / admin
concommand.Add("gfr_infection_set", function(ply, _, args)
	if IsValid(ply) && !GFR.CanCheat(ply) then return end
	local target = IsValid(ply) and ply or player.GetAll()[1]
	local amount = tonumber(args[1] or "")
	if !IsValid(target) or !amount then print("Usage: gfr_infection_set <0-100>  (0 = clear)") return end
	if !target:Alive() or target.GFR_IsZombie then print("gfr_infection_set: you need to be alive and human") return end
	if amount <= 0 then ResetInfection(target) else target.GFR_Inf = math.min(amount, 100) end -- (100: you turn on the next tick)
end)
