--[[
	Custom Apocalypse - Zombie Blood Extract (crafted: 3 zombie blood + 1 chemicals at a workbench)

	Use it from the inventory:
		Looking at a person (within reach)  -> you stab them with it. It hurts and scares them, so they turn hostile.
		                                       ~10 seconds later they turn into a runner zombie wearing their own body.
		Looking at nothing                   -> inject yourself. Use it a second time within 5s to confirm.
		                                       You become a runner zombie you control yourself (VJ NPC controller).
		                                       Your gear stays on your zombie body. When it dies, or you stop
		                                       controlling it, you're dead and respawn normally (unless the head
	                                       was intact - then it gets back up and you take control again).
]]
local REACH = 100

local function LookedAtNPC(ply)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = ply, mask = MASK_SHOT})
	local ent = tr.Entity
	if IsValid(ent) && ent:IsNPC() && ent:Health() > 0 && !GFR.IsZombie(ent) && ent:LookupBone("ValveBiped.Bip01_Pelvis") then return ent end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Injecting someone else
-- They drop, lie there, twitch, then get up as one of them (sv_infection.lua: GFR.TurnBody). onRise(z) when they do.
local function TurnNPC(npc, walker, onRise)
	local mdl = npc.GFR_PlayerModel or npc:GetModel()
	local body = IsValid(npc.GFR_Body) and npc.GFR_Body or npc
	local skin, bodygroups = body:GetSkin(), {}
	for i = 0, body:GetNumBodyGroups() - 1 do bodygroups[i] = body:GetBodygroup(i) end
	local color = body.GetPlayerColor and body:GetPlayerColor() or nil

	-- Their gun falls to the floor
	local wep = npc:GetActiveWeapon()
	if IsValid(wep) then
		npc:DropWeapon(wep)
		timer.Simple(0, function()
			if IsValid(wep) && !IsValid(wep:GetOwner()) then wep.GFR_Loot = true end
		end)
	end

	local pos, ang = npc:GetPos(), npc:GetAngles()
	local fx = EffectData()
	fx:SetOrigin(npc:WorldSpaceCenter())
	util.Effect("BloodImpact", fx)
	npc:EmitSound("vj_cncr/zombie/zombie_pain" .. math.random(1, 8) .. ".wav", 80, 90)
	if !scripted_ents.GetStored(GFR.InfectedClass()) then npc:Remove() return end

	local look = {model = mdl, skin = skin, bodygroups = bodygroups, color = color}
	local rag = GFR.DropTurningBody && GFR.DropTurningBody(npc, look)
	npc:Remove()
	if IsValid(rag) then
		GFR.TurnBody(rag, look, {runner = !walker, onRise = onRise})
		return
	end

	-- Couldn't make a body: straight to the zombie
	local z = ents.Create(GFR.InfectedClass())
	z:SetPos(pos)
	z:SetAngles(ang)
	z.GFR_ForceModel = mdl
	z.GFR_ForceSkin = skin
	z.GFR_ForceBodygroups = bodygroups
	z.GFR_ForceColor = color
	z.RTRG_ForceRunner = !walker -- the extract is a fast-acting strain
	z:Spawn()
	z:Activate()
	z.GFR_TurnedAt = CurTime() -- still has fresh pockets (sv_loot.lua)
	if onRise then onRise(z) end
end
GFR.TurnNPC = TurnNPC -- also used by parasites (sv_parasite.lua)

local function InjectNPC(ply, npc)
	ply:EmitSound("items/medshot4.wav")
	-- It hurts, and they saw what you did
	local dmg = DamageInfo()
	dmg:SetDamage(3)
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetAttacker(ply)
	dmg:SetInflictor(ply)
	npc:TakeDamageInfo(dmg)
	npc:AddEntityRelationship(ply, D_HT, 99)
	npc:UpdateEnemyMemory(ply, ply:GetPos())
	if npc.GFR_Group && GFR.Say then
		local lines = {"What did you just put in me?!", "Get away from me! What was that?!", "You sick bastard!"}
		GFR.Say(npc, lines[math.random(#lines)])
	end
	GFR.Notify(ply, "You inject them. It won't take long.")

	npc.GFR_Injected = true
	timer.Simple(math.Rand(8, 14), function()
		if IsValid(npc) && npc:Health() > 0 then TurnNPC(npc) end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Injecting yourself: become a runner zombie under your own control (VJ NPC controller on a GMod of the Dead
-- zombie wearing your playermodel). Your gear stays on your zombie body. E next to a body: eat.
-- Killed with the head intact, it gets back up after a bit and you take control again;
-- head destroyed (headshot, explosion, fire): your belongings drop and you respawn as a survivor.
local femaleWords = {"female", "alyx", "mossman", "chell", "zoey", "producer", "rochelle", "girl", "woman", "lady", "_f_", "fem", "boomette"}

local function IsFemaleModel(mdl)
	mdl = string.lower(mdl or "")
	for _, w in ipairs(femaleWords) do
		if string.find(mdl, w, 1, true) then return true end
	end
	return false
end

-- Return to Ravenholm voice line from any entity, male or female by model (kind: idle, alert, combat, attack, pain, die)
local voiceCounts = {
	male = {idle = 14, alert = 7, combat = 8, attack = 5, pain = 8, die = 7},
	female = {idle = 13, alert = 8, combat = 8, attack = 8, pain = 8, die = 8}
}
local voiceFiles = {idle = "zombie_voice_idle%d", alert = "zombie_alert%d", combat = "zombie_voice_idle_combat%d", attack = "zo_attack%d", pain = "zombie_pain%d", die = "zombie_die%d"}

function GFR.ZombieVoice(ent, kind, level, pitch, mdl)
	if !IsValid(ent) then return end
	local female = IsFemaleModel(mdl or ent:GetModel())
	local n = voiceCounts[female and "female" or "male"][kind]
	if !n then return end
	local path = "vj_cncr/zombie/" .. (female and "Female/" or "") .. string.format(voiceFiles[kind], math.random(1, n)) .. ".wav"
	ent:EmitSound(path, level or 80, pitch or math.random(95, 105))
end

local RISE_MIN, RISE_MAX = 10, 18
local HandleRelease -- below

-- The dead don't carry flashlights: F toggles your dead eyes instead (night vision, sh_zombieplayer.lua)
hook.Add("PlayerSwitchFlashlight", "GFR_Zombie_NoFlashlight", function(ply, on)
	if !ply.GFR_IsZombie then return end
	if on then
		local nv = !ply:GetNW2Bool("GFR_ZNightVis")
		ply:SetNW2Bool("GFR_ZNightVis", nv)
		ply:EmitSound(nv and "npc/zombie/zombie_voice_idle" .. math.random(1, 14) .. ".wav" or "player/breathe1.wav", 40, nv and 70 or 60, 0.5)
	end
	return !on -- (turning it off is always allowed)
end)

-- rising = getting back up after being put down (belongings are already on ply.GFR_ZombieGear)
function GFR.BecomeZombie(ply, rising)
	if !IsValid(ply) or !ply:Alive() or ply.VJ_IsControllingNPC then return end
	-- The L4D infected (npc_gfr_infected) wearing your body; the old GOTDR player zombie if that pack is missing.
	-- An experimental vial made you a hunter instead (sv_hunter.lua): ply.GFR_ZombieKind
	local hunter = ply.GFR_ZombieKind == "hunter" && GFR.HunterClass && GFR.HunterClass()
	local class = hunter or (GFR.InfectedClass() == "npc_gfr_infected" and "npc_gfr_infected" or "npc_vj_gotdr_zombie_ply")
	if !scripted_ents.GetStored(class) or !scripted_ents.GetStored("obj_vj_controller") then
		GFR.Notify(ply, "Nothing happens. (zombie NPC pack / VJ Base missing)")
		return
	end

	-- Everything you carry stays on your zombie body
	if !rising then ply.GFR_ZombieGear = GFR.CollectGear(ply) end
	ply:StripWeapons()
	ply:RemoveAllAmmo()
	ply.GFR_Inv = {}
	GFR.InvSync(ply)
	ply:SetNW2Int("GFR_Caps", 0)
	ply.GFR_Bleeding = nil
	ply:SetNW2Bool("GFR_Bleeding", false)

	local mdl = ply:GetModel()
	local z = ents.Create(class)
	z:SetPos(ply:GetPos())
	z:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	if hunter then
		-- Your own body on the hunter's skeleton; crouch + attack pounces (the pack's controls)
		z:Spawn()
		z:Activate()
		local bodygroups = {}
		for i = 0, ply:GetNumBodyGroups() - 1 do bodygroups[i] = ply:GetBodygroup(i) end
		GFR.SetupHunter(z, {model = mdl, skin = ply:GetSkin(), bodygroups = bodygroups, color = ply:GetPlayerColor()})
		z:SetNW2Bool("GFR_PlayerZombie", true) -- our over-the-shoulder camera (sh_zombieplayer.lua), not the pack's low one
		-- None of the pack's Left 4 Dead versus-mode extras on your hunter: E toggled its "ghost" mode (blue screen) and
		-- out of it you got its yellow infected tint, the pounce meter and outlines on everyone. Never ghosted, no HUD.
		local setGhost = z.SetGhost
		z.SetGhost = function(self) if setGhost then setGhost(self, false) end self.IsGhosted = false end
		z.OnGhost = function() end
		z.ManageHUD = function() end
		z.IsGhosted = false
	elseif class == "npc_gfr_infected" then
		-- Your own body on the infected's skeleton; you always run
		local bodygroups = {}
		for i = 0, ply:GetNumBodyGroups() - 1 do bodygroups[i] = ply:GetBodygroup(i) end
		z.GFR_ForceModel = mdl
		z.GFR_ForceSkin = ply:GetSkin()
		z.GFR_ForceBodygroups = bodygroups
		z.GFR_ForceColor = ply:GetPlayerColor()
		z.RTRG_ForceRunner = true
		z:Spawn()
		z:Activate()
		z:SetNW2Bool("GFR_PlayerZombie", true) -- close, centred camera (npc_gfr_infected shared.lua)
	else
		z:Spawn()
		z:Activate()
		z:VJ_GOTDR_CreateBoneMerge(z, mdl, ply:GetSkin(), ply:GetColor(), ply:GetMaterial(), ply:GetPlayerColor(), ply, ply)
		-- With NMRiH animations (VJ_GOTDR_ZombieAnims 2) GOTDR ignores GOTDR_Runner; only sprinters run
		z.GOTDR_Runner = !z.GOTDR_NMRIHAnims
		z.GOTDR_Sprinter = z.GOTDR_NMRIHAnims or false
		z.GOTDR_SuperSprinter = false
		local runAct = math.random(3) == 1 and ACT_RUN_RELAXED or ACT_SPRINT
		local baseTranslate = z.TranslateActivity
		z.TranslateActivity = function(self, act)
			if (act == ACT_WALK or act == ACT_RUN) && !self.GOTDR_Crawler && !self.GOTDR_Crippled then return runAct end
			return baseTranslate(self, act)
		end
		if IsFemaleModel(mdl) then z.GOTDR_Gender = 1 z:ZombieVoice_FemaleWal() else z.GOTDR_Gender = 0 z:ZombieVoice_MaleWal() end
	end
	z:SetName(ply:Nick() .. " (Zombie)")

	-- Not allowed to play as your zombie (sv_zombieperms.lua): it gets up without you, an ordinary zombie carrying your
	-- gear (kill it to get it back), and you respawn as a survivor
	if GFR.CanPlayZombie && !GFR.CanPlayZombie(ply) then
		z:SetNW2Bool("GFR_PlayerZombie", false)
		z.RTRG_ForceRunner = nil
		z.GFR_PlyModel = mdl
		z.GFR_TurnedAt = CurTime()
		z.GFR_Gear = ply.GFR_ZombieGear
		ply.GFR_ZombieGear = nil
		ply.GFR_ZombieKind = nil
		ply.GFR_ParasiteHost = nil
		ply.GFR_ZombieRise = nil
		ply.GFR_ZombieNPC = nil
		ply.GFR_IsZombie = nil -- (getting back up after being put down: you were one)
		ply:SetNW2Bool("GFR_IsZombie", false)
		ply.VJ_NPC_Class = nil
		ply:UnSpectate()
		if ply:Alive() then ply:KillSilent() end
		if GFR.ZombieRise then GFR.ZombieRise(z, 0.6) end -- (it drags itself up off the ground)
		-- You watch it go through the zombie camera, as when staff take your zombie away (HandleRelease), and click
		-- to respawn
		timer.Simple(0, function()
			if !IsValid(ply) or ply:Alive() or !IsValid(z) then return end
			ply:Spectate(OBS_MODE_CHASE)
			ply:SpectateEntity(z)
			ply:SetNW2Entity("GFR_ZWatch", z)
		end)
		GFR.Notify(ply, "Your body got up as a zombie.")
		return
	end

	-- No pathfinding jumps: it would leap at whatever you aim at. You move it; it doesn't hop on its own.
	z.JumpParams = {Enabled = false, MaxRise = 0, MaxDrop = 0, MaxDistance = 0}
	z.Zombie_CanClimb = false
	if !hunter then z.HasLeapAttack = false end -- (the hunter's pounce IS its leap attack)
	z.GFR_ControlPlayer = ply
	z.GFR_PlyModel = mdl
	z.GFR_TurnedAt = CurTime()
	ply.GFR_ZombieNPC = z

	ply.GFR_IsZombie = true
	ply:SetNW2Bool("GFR_IsZombie", true)
	if ply:FlashlightIsOn() then ply:Flashlight(false) end -- (and it stays off: PlayerSwitchFlashlight below)
	if GFR.ZombieHungerStart then GFR.ZombieHungerStart(ply) end -- (sv_zombiehunger.lua; kept when getting back up)

	local cont = ents.Create("obj_vj_controller")
	cont.VJCE_Player = ply
	cont.VJC_Player_DrawHUD = false  -- no VJ controller panel: the zombie shouldn't look like a game menu
	cont.VJC_NPC_CanTurn = hunter and true or false -- standing still, the camera looks around freely (a hunter faces where it'll pounce)
	cont.VJC_Player_CanChatMessage = false
	cont.ToggleMovementJumping = function() end -- VJ binds J to "allow jumping"; J is give-in here, and it shouldn't hop
	cont:SetControlledNPC(z)
	cont:Spawn()
	cont:StartControlling()
	ply.GFR_ZombieController = cont
	if hunter then
		-- A hunter faces where you look so it can line up a pounce - but only over the shoulder, like the infected
		-- (npc_gfr_infected PlayerTurn): on the full-body or first-person camera it stays as it is
		local id = "GFR_HunterTurn" .. cont:EntIndex()
		timer.Create(id, 0.2, 0, function()
			if !IsValid(cont) or !IsValid(ply) then timer.Remove(id) return end
			cont.VJC_NPC_CanTurn = ply:GetInfoNum("gfr_zcam_mode", 0) == 0
		end)
		-- (and any of its tint / HUD already on your screen from before is taken off)
		timer.Simple(0.3, function()
			if !IsValid(ply) then return end
			for _, msg in ipairs({"L4D2HunterHUD", "L4D2HunterHUDGhost"}) do
				if util.NetworkStringToID(msg) != 0 then
					net.Start(msg) net.WriteBool(true) net.WriteEntity(z) net.WriteEntity(ply) net.Send(ply)
				end
			end
		end)
	end

	-- Control ends when your zombie goes down (or you let go of it)
	timer.Simple(0.2, function()
		if !IsValid(cont) then return end
		local orig = cont.OnStopControlling
		cont.OnStopControlling = function(self, ...)
			if IsValid(ply) then ply.GFR_ZReleasing = true end
			if orig then orig(self, ...) end
			timer.Simple(0.3, function() HandleRelease(ply, z) end)
		end
	end)
	if rising then
		GFR.Notify(ply, "Your zombie is back up.")
	elseif hunter then
		GFR.Notify(ply, "You're a hunter. Crouch + attack: pounce   E by a body: eat. Soldiers leave you alone.")
	else
		GFR.Notify(ply, "You're a zombie. Attack: swipe   Right click: grab   Crouch: sit   E by a body: eat")
	end
end

-- Attacking turns it to where you're aiming (otherwise it faces where it walks, not your camera)
hook.Add("KeyPress", "GFR_ZombiePlayer_AimAttack", function(ply, key)
	if (key != IN_ATTACK && key != IN_ATTACK2) or !ply.GFR_IsZombie then return end
	local cont, z = ply.GFR_ZombieController, ply.GFR_ZombieNPC
	if !IsValid(cont) or !IsValid(z) or !IsValid(cont.VJCE_Bullseye) then return end
	z:SetTurnTarget(cont.VJCE_Bullseye, 0.6)
end)

-- Your infected's own moves (not a hunter's: it has the pack's controls, crouch + attack pounces)
--   right click  grab whoever's in front of you and bite (attack is always a swipe)
--   crouch       sit down / lean on a wall / get back up (the L4D idles)

-- A wall close beside, behind or in front of the zombie: which side it's on (as the L4D lean names it), and where to
-- stand and face to lean on it
local LEAN_REACH, LEAN_GAP = 40, 16
local leanSides = {{"Backward", 180, 0}, {"Forward", 0, 180}, {"Leftward", 90, 90}, {"Rightward", -90, -90}}
local function FindLeanWall(z)
	local pos, yaw = z:GetPos(), z:GetAngles().y
	local best
	for _, s in ipairs(leanSides) do
		local dir = Angle(0, yaw + s[2], 0):Forward()
		local start = pos + Vector(0, 0, 40)
		local tr = util.TraceLine({start = start, endpos = start + dir * LEAN_REACH, filter = {z, z.Bonemerge}, mask = MASK_SOLID_BRUSHONLY})
		if tr.Hit && math.abs(tr.HitNormal.z) < 0.3 && (!best or tr.Fraction < best.frac) then
			local n = Vector(tr.HitNormal.x, tr.HitNormal.y, 0):GetNormalized()
			local at = Vector(tr.HitPos.x, tr.HitPos.y, pos.z) + n * LEAN_GAP
			-- (facing set square to the wall: away from it, into it, or side-on)
			best = {side = s[1], frac = tr.Fraction, pos = at, yaw = n:Angle().y + s[3]}
		end
	end
	return best
end

hook.Add("KeyPress", "GFR_ZombiePlayer_Moves", function(ply, key)
	if !ply.GFR_IsZombie or (key != IN_ATTACK2 && key != IN_DUCK) then return end
	local z = ply.GFR_ZombieNPC
	if !IsValid(z) or z:GetClass() != "npc_gfr_infected" or z.Dead or z:Health() <= 0 then return end

	if key == IN_ATTACK2 then
		if !z:GFR_TryGrab(ply:GetAimVector()) && (ply.GFR_NextGrabHint or 0) < CurTime() then
			ply.GFR_NextGrabHint = CurTime() + 3
			GFR.Notify(ply, "Nobody close enough to grab.")
		end
		return
	end

	-- Crouch: sit down, or stand back up
	if z.GOTDR_CurEnt or z.VJ_ST_Eating or z.GFR_Crawl then return end
	if (z.Zombie_IdleState or 0) == 0 then
		if z:IsMoving() or (z.GetState && z:GetState() != VJ_STATE_NONE) then return end
		-- Starving or feral: too restless to rest (sv_zombiehunger.lua)
		local stage = GFR.ZombieHungerStage && GFR.ZombieHungerStage(ply)
		if stage == "starving" or stage == "feral" then
			GFR.Notify(ply, "Too hungry to rest. Eat something first.")
			return
		end
		-- Up against a wall: usually lean on it (16 leaning idles, 4 per side) instead
		local wall = FindLeanWall(z)
		if wall && math.random(3) != 1 then
			z:SetPos(wall.pos)
			z:SetAngles(Angle(0, wall.yaw, 0))
			local act = VJ && VJ.SequenceToActivity && VJ.SequenceToActivity(z, "Leaning" .. wall.side .. "0" .. math.random(1, 4))
			if act && act > 0 then
				z.GFR_LeanAct = act
				z.Zombie_IdleState = 3 -- leaning (npc_gfr_infected; the L4D code just stands it back up with no animation)
				z.Zombie_IdleQuickStand = false
				z:SetState(VJ_STATE_ONLY_ANIMATION, 99999)
				z.Zombie_IdleStandT = CurTime() + 99999
				z.GFR_ManualSit = true
				z:SCHEDULE_IDLE_STAND()
				return
			end
		end
		-- A different rest each time: sit (9 seated idles) or lie down (8 lying idles) at random
		-- (the L4D pack picks one of each per zombie for good: l4d_com_infected.lua)
		local lie = math.random(3) == 1
		local poses = lie and {"lying01", "lying02", "lying03", "lying04", "lying05", "lying06", "lying07", "lying08"}
			or {"Sitting01", "Sitting02", "Sitting03", "Sitting04", "Sitting05", "Sitting06", "Sitting07", "Sitting08", "Sitting09"}
		local act = VJ && VJ.SequenceToActivity && VJ.SequenceToActivity(z, poses[math.random(#poses)])
		if act && act > 0 then
			if lie then z.ZombieAnim_IdleLying = act else z.ZombieAnim_IdleSitting = act end
		end
		z.Zombie_IdleState = lie and 2 or 1 -- lying / sitting (l4d_com_infected.lua)
		z.Zombie_IdleQuickStand = false
		z:PlayAnim(lie and "standing_to_lying03" or "standing_to_sitting03", true, false)
		z:SetState(VJ_STATE_ONLY_ANIMATION, 99999)
		z.Zombie_IdleStandT = CurTime() + 99999
		z.GFR_ManualSit = true -- (npc_gfr_infected keeps it seated)
		z:SetNW2Bool("GFR_ZSitting", true) -- (the camera looks at the seated body: sh_zombieplayer.lua)
	else
		z.GFR_ManualSit = nil
		z:SetNW2Bool("GFR_ZSitting", false)
		z.Zombie_IdleStandT = 0 -- its think gets it up (standing-up animation)
	end
end)

-- How your zombie went down: only a destroyed head keeps it down (sv_rise.lua: GFR.HeadDestroyed)
hook.Add("ScaleNPCDamage", "GFR_ZombiePlayer_Hit", function(npc, hitgroup)
	if npc.GFR_ControlPlayer then npc.GFR_LastHit, npc.GFR_LastHitT = hitgroup, CurTime() end
end)
hook.Add("EntityTakeDamage", "GFR_ZombiePlayer_Dmg", function(ent, dmg)
	if !ent.GFR_ControlPlayer then return end
	ent.GFR_LastDmgType = dmg:GetDamageType()
	local hg = GFR.DamageHitgroup && GFR.DamageHitgroup(ent, dmg) -- melee head blows (sv_rise.lua)
	if hg then ent.GFR_LastHit, ent.GFR_LastHitT = hg, CurTime()
	elseif ent.GFR_LastHitT != CurTime() then ent.GFR_LastHit = HITGROUP_GENERIC end
end)
hook.Add("OnNPCKilled", "GFR_ZombiePlayer_Killed", function(npc)
	local ply = npc.GFR_ControlPlayer
	if !ply then return end
	npc.GFR_Died = true
	npc.GFR_DeathPos = npc:GetPos()
	npc.GFR_HeadGone = GFR.HeadDestroyed && GFR.HeadDestroyed(npc.GFR_LastHit, npc.GFR_LastDmgType) or false
	-- Kept on the player too: the NPC is usually gone by the time control is handed back
	if IsValid(ply) then ply.GFR_ZDeath = {pos = npc:GetPos(), ang = npc:GetAngles(), head = npc.GFR_HeadGone, model = npc.GFR_PlyModel} end
end)

-- Your zombie's corpse is yours to get back up in, not a free AI zombie (sv_rise.lua skips it)
hook.Add("RTRG_ZombieCorpse", "GFR_ZombiePlayer_Corpse", function(z, corpse)
	local ply = z.GFR_ControlPlayer
	if !IsValid(ply) then return end
	ply.GFR_ZCorpseEnt = corpse
	corpse.GFR_PlayerBody = ply
end)

local function FindCorpse(z, pos, ply)
	if IsValid(ply) && IsValid(ply.GFR_ZCorpseEnt) then return ply.GFR_ZCorpseEnt end
	if IsValid(z) && IsValid(z.Corpse) then return z.Corpse end
	local best, bestDist
	for _, ent in ipairs(ents.FindInSphere(pos, 120)) do
		if ent:GetClass() == "prop_ragdoll" && !ent.GFR_Decor then
			local d = ent:GetPos():DistToSqr(pos)
			if !bestDist or d < bestDist then best, bestDist = ent, d end
		end
	end
	return best
end

-- Down for good: belongings drop, a parasite you gave in to crawls out, you respawn as a survivor
local function FinalDeath(ply, pos, msg)
	ply.GFR_ZombieRise = nil
	ply.GFR_ExZombieUntil = CurTime() + 5
	if ply.GFR_ParasiteHost then
		ply.GFR_ParasiteHost = nil
		timer.Simple(1, function() if GFR.SpawnParasite then GFR.SpawnParasite(pos + Vector(0, 0, 20)) end end)
	end
	if ply.GFR_ZombieGear then GFR.DropGearBag(pos, ply.GFR_ZombieGear) end
	ply.GFR_ZombieGear = nil
	ply.GFR_ZombieKind = nil
	ply.GFR_IsZombie = nil
	ply:SetNW2Bool("GFR_IsZombie", false)
	ply.VJ_NPC_Class = nil
	ply:UnSpectate()
	if ply:Alive() then ply:KillSilent() end
	if msg != false then GFR.Notify(ply, msg or "You're dead.") end -- (false: no message)
end

function HandleRelease(ply, z)
	if !IsValid(ply) then return end
	ply.GFR_ZReleasing = nil
	if !ply.GFR_IsZombie then return end
	ply.GFR_ZombieNPC = nil
	local death = ply.GFR_ZDeath
	ply.GFR_ZDeath = nil
	local died = death != nil or !IsValid(z) or z.GFR_Died or z:Health() <= 0
	local pos = death and death.pos or IsValid(z) and (z.GFR_DeathPos or z:GetPos()) or ply:GetPos()
	local headGone = death and death.head or IsValid(z) and z.GFR_HeadGone

	if !died && ply.GFR_ZSuicide then
		-- You killed yourself (the kill command) while driving it: that's the end of this body - no AI zombie wearing you
		-- left wandering about, no second body. Your belongings drop where it stood.
		ply.GFR_ZSuicide = nil
		if IsValid(z) then
			z.GFR_ControlPlayer = nil
			z.GFR_Gear = nil
			z:Remove()
		end
		FinalDeath(ply, pos, "You let go of your zombie.")
		return
	end
	ply.GFR_ZSuicide = nil
	if !died then
		-- You let go: it keeps shambling around on its own with your stuff (kill it to get it back, sv_infection.lua)
		z.GFR_ControlPlayer = nil
		z.GFR_Gear = ply.GFR_ZombieGear
		ply.GFR_ZombieGear = nil
		ply.GFR_ParasiteHost = nil
		local taken = ply.GFR_ZTakenAway
		ply.GFR_ZTakenAway = nil
		FinalDeath(ply, pos, (!taken) and "You let go of your zombie.")
		if taken then
			-- Taken away by staff (sv_admin.lua): you keep watching it through the zombie camera (cl: sh_zombieplayer.lua),
			-- without control, until you click to respawn
			timer.Simple(0, function()
				if !IsValid(ply) or ply:Alive() or !IsValid(z) then return end
				ply:Spectate(OBS_MODE_CHASE)
				ply:SpectateEntity(z)
				ply:SetNW2Entity("GFR_ZWatch", z)
			end)
		end
		return
	end

	local riseOn = !GetConVar("gfr_zombie_rise") or GetConVar("gfr_zombie_rise"):GetBool()
	local corpse = FindCorpse(z, pos, ply)
	ply.GFR_ZCorpseEnt = nil
	if !riseOn or headGone then
		if IsValid(corpse) then corpse.GFR_PlayerBody = nil end
		FinalDeath(ply, pos)
		return
	end

	-- Head intact: you lie there twitching, then get back up and take control again
	ply.GFR_ZombieRise = {pos = pos, ang = death and death.ang or IsValid(z) and z:GetAngles() or ply:EyeAngles(), corpse = corpse}
	if ply:Alive() then ply:KillSilent() end
	ply:SetNW2Bool("GFR_ZombieSpectate", true) -- keep the veins while you're down
	local function WatchCorpse(c)
		ply.GFR_ZombieRise.corpse = c
		GFR.ZombieVoice(c, "pain", 75, nil, death and death.model or IsValid(z) and z.GFR_PlyModel or nil)
		ply:Spectate(OBS_MODE_CHASE)
		ply:SpectateEntity(c)
	end
	if IsValid(corpse) then
		WatchCorpse(corpse)
	else
		-- Its corpse isn't there yet (the infected plays a death animation first): wait for it. Without this the camera
		-- had nothing to look at, and getting back up left the corpse lying there (a second body).
		local id = "GFR_ZWaitCorpse" .. ply:EntIndex()
		timer.Create(id, 0.2, 30, function()
			if !IsValid(ply) or !ply.GFR_ZombieRise then timer.Remove(id) return end
			local c = (IsValid(ply.GFR_ZCorpseEnt) and ply.GFR_ZCorpseEnt) or (IsValid(z) && IsValid(z.Corpse) and z.Corpse) or nil
			if c then
				timer.Remove(id)
				ply.GFR_ZCorpseEnt = nil
				WatchCorpse(c)
			end
		end)
	end
	GFR.Notify(ply, "Your zombie is down. It gets back up unless its head is destroyed.")
	timer.Simple(math.Rand(RISE_MIN, RISE_MAX), function()
		if !IsValid(ply) or ply:Alive() or ply.GFR_ZombieRise == nil then return end
		local rise = ply.GFR_ZombieRise
		-- Carved up or eaten while you lay there: that's the end of it
		if rise.corpse != nil && !IsValid(rise.corpse) then
			FinalDeath(ply, rise.pos, "Your body is gone.")
			return
		end
		if IsValid(rise.corpse) && rise.corpse.GFR_HeadGone then
			FinalDeath(ply, rise.pos, "Your zombie's head was destroyed.")
			return
		end
		ply:Spawn()
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Giving in: while a zombie has you in its grip (GMod of the Dead's grab), J stops the struggle.
-- It bites, everything goes black, and you get back up as one of them - your gear still on you.
local function Grabber(ply)
	for _, z in ipairs(ents.FindInSphere(ply:GetPos(), 200)) do
		if z:IsNPC() && z.GOTDR_CurEnt == ply then return z end
	end
end

-- viaParasite: giving in to a latched parasite (sv_parasite.lua) instead of a zombie's grab
function GFR.GiveIn(ply, viaParasite)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_GivingIn then return end
	if !viaParasite && !ply.GOTDR_Grappled then return end
	ply.GFR_GivingIn = true
	ply.VJ_NPC_Class = {"CLASS_ZOMBIE"} -- the dead lose interest in their own
	if viaParasite then ply.GFR_ParasiteHost = true end -- it lives in you now; it leaves when you're put down for good
	local z = !viaParasite && Grabber(ply)
	if IsValid(z) then
		z:EmitSound("vj_gotdr/shared/melee/zombie_bite" .. math.random(1, 3) .. ".wav", 80)
		if z.ResetGrapple then z:ResetGrapple() end
		if z:GetEnemy() == ply then z:SetEnemy(NULL) end
		if z.ClearEnemyMemory then z:ClearEnemyMemory(ply) end
	end
	ply.GOTDR_Grappled = false
	local fx = EffectData()
	fx:SetOrigin(ply:EyePos() - Vector(0, 0, 10))
	util.Effect("BloodImpact", fx)
	ply:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75)
	ply:GodEnable()
	ply:Freeze(true)
	ply:ViewPunch(Angle(14, math.Rand(-6, 6), 0))
	ply:ScreenFade(SCREENFADE.IN, Color(120, 0, 0, 160), 0.6, 0) -- (a flash of red, no fading out: you watch it happen)
	GFR.Notify(ply, viaParasite and "You gave in to the parasite."
		or "You gave in.")

	-- You go down, and the one that had you feeds on you (CollapseIntoZombie)
	timer.Simple(0.4, function() GFR.CollapseIntoZombie(ply, IsValid(z) && z.GFR_FeedOn && z or nil) end)
end

local FEED_TIME = 15 -- seconds the zombie that brought you down feeds before it wanders off

-- You collapse: your body drops, lies still, starts to twitch, then gets up as your zombie, which you control
-- (sv_infection.lua: GFR.TurnBody). Giving in, and injecting yourself with an experimental vial (sv_hunter.lua).
-- eater (giving in): the zombie that had you feeds on your body for FEED_TIME and wanders off first; the turning
-- (lying still, twitching, getting up) starts once it's gone.
function GFR.CollapseIntoZombie(ply, eater)
	-- (only once: two ways of going down at the same time - the vial finishing as the infection does, or a zombie's
	-- blow - would drop two bodies)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Collapsing then return end
	ply.GFR_Collapsing = true
	ply.GFR_GivingIn = true
	ply.VJ_NPC_Class = {"CLASS_ZOMBIE"}
	ply:GodEnable()
	ply:Freeze(true)
	do
		local bodygroups = {}
		for i = 0, ply:GetNumBodyGroups() - 1 do bodygroups[i] = ply:GetBodygroup(i) end
		local look = {model = ply:GetModel(), skin = ply:GetSkin(), bodygroups = bodygroups, color = ply:GetPlayerColor()}
		local rag = GFR.DropTurningBody && GFR.DropTurningBody(ply, look)
		local function Finish(pos, yaw)
			if !IsValid(ply) then return end
			ply.GFR_GivingIn = nil
			ply.GFR_Collapsing = nil
			ply:SetNW2Bool("GFR_ZombieSpectate", false)
			ply:UnSpectate()
			ply:SetMoveType(MOVETYPE_WALK)
			ply:SetNoDraw(false)
			ply:SetNotSolid(false)
			ply:DrawViewModel(true)
			ply:GodDisable()
			ply:Freeze(false)
			if !ply:Alive() then return end
			if pos then ply:SetPos(pos) end
			if yaw then ply:SetEyeAngles(Angle(0, yaw, 0)) end
			GFR.BecomeZombie(ply)
			-- ...and it drags itself up off the ground
			local z = ply.GFR_ZombieNPC
			if IsValid(z) && GFR.ZombieRise then GFR.ZombieRise(z, 0.6) end
			ply:ScreenFade(SCREENFADE.IN, Color(90, 0, 0), 2.5, 0)
		end
		if !IsValid(rag) then Finish() return end -- odd playermodel with no ragdoll: straight over

		rag.GFR_PlayerBody = ply
		-- You watch your own body from outside, through dead eyes (vein overlay)
		ply:SetNoDraw(true)
		ply:SetNotSolid(true)
		ply:DrawViewModel(false)
		ply:Spectate(OBS_MODE_CHASE)
		ply:SpectateEntity(rag)
		ply:SetNW2Bool("GFR_ZombieSpectate", true)
		-- Spectating holds you in place anyway; frozen, you couldn't even turn the camera around your body
		ply:Freeze(false)
		ply:ScreenFade(SCREENFADE.IN, Color(60, 0, 0, 200), 1.5, 0)
		-- Head destroyed (or the body gone) before you got up: that's the end
		local function Fail()
			if !IsValid(ply) then return end
			ply.GFR_GivingIn = nil
			ply.GFR_Collapsing = nil
			ply:SetNW2Bool("GFR_ZombieSpectate", false)
			ply:UnSpectate()
			ply:SetNoDraw(false)
			ply:SetNotSolid(false)
			ply:DrawViewModel(true)
			ply:GodDisable()
			ply:Freeze(false)
			ply.GFR_Executed = true -- no getting up again (sv_infection.lua), cleared on respawn (sv_surrender.lua)
			ply.GFR_ZombieKind = nil
			if ply:Alive() then ply:Kill() end
		end

		-- Same lie / twitch time as losing to the infection (gfr_turn_lie / gfr_turn_twitch)
		local function StartTurning()
			if !IsValid(ply) then return end
			if !IsValid(rag) then Fail() return end
			GFR.TurnBody(rag, look, {
				rise = function(body)
					local pelvis = body:LookupBone("ValveBiped.Bip01_Pelvis")
					local p = pelvis and body:GetBonePosition(pelvis) or body:GetPos()
					local tr = util.TraceLine({start = p + Vector(0, 0, 10), endpos = p - Vector(0, 0, 120), filter = body, mask = MASK_PLAYERSOLID_BRUSHONLY})
					local yaw = body:GetAngles().y
					body:Remove()
					Finish(tr.HitPos + Vector(0, 0, 2), yaw)
				end,
				onFail = Fail
			})
		end

		if IsValid(eater) then
			-- It feeds on you first: you lie there and watch, then it gets up and wanders off
			GFR.Notify(ply, "It's eating you.")
			eater:GFR_FeedOn(rag, FEED_TIME, function()
				if !IsValid(ply) then return end
				if IsValid(rag) then GFR.Notify(ply, "It's finished with you.") end
				StartTurning()
			end)
		else
			StartTurning()
		end
	end
end

-- Killed by the dead: instead of dying and watching an AI zombie get up in your place, it goes the way giving in does -
-- the blow that would kill you drags you down, the zombie that did it feeds on you, wanders off, and you get up as
-- your own zombie (CollapseIntoZombie)
hook.Add("EntityTakeDamage", "GFR_ZombieKill_GiveIn", function(ply, dmg)
	if !ply:IsPlayer() or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_GivingIn or ply.GFR_Executed or ply.GFR_Bait then return end
	local cv = GetConVar("gfr_infection_enabled")
	if cv && !cv:GetBool() then return end
	local att = dmg:GetAttacker()
	if !IsValid(att) or !att:IsNPC() or !GFR.IsZombie(att) or att.GFR_ControlPlayer then return end
	if bit.band(dmg:GetDamageType(), bit.bor(DMG_DISSOLVE, DMG_BLAST, DMG_ALWAYSGIB)) != 0 then return end
	if dmg:GetDamage() < ply:Health() then return end
	-- Not dead: down
	ply:SetHealth(1)
	if att.ResetGrapple && att.GOTDR_CurEnt == ply then att:ResetGrapple() end
	-- Pinned by a special infected (hunter / charger / jockey): it lets go, or you'd go down still parented to it,
	-- invisible and stuck in its custom move type
	if att.pIncapacitatedEnemy == ply then
		local dismount = att.DismountHunter or att.DismountCharger or att.DismountJockey
		if dismount then dismount(att) end
		ply:SetParent(NULL)
		ply:SetMoveType(MOVETYPE_WALK)
		ply:SetNoDraw(false)
		ply:RemoveEFlags(EFL_NO_THINK_FUNCTION)
	end
	if att:GetEnemy() == ply then att:SetEnemy(NULL) end
	if att.ClearEnemyMemory then att:ClearEnemyMemory(ply) end
	ply.GOTDR_Grappled = false
	ply.GFR_GivingIn = true
	ply.VJ_NPC_Class = {"CLASS_ZOMBIE"} -- (the rest of them lose interest)
	ply:GodEnable()
	ply:Freeze(true)
	ply:ViewPunch(Angle(18, math.Rand(-8, 8), 0))
	ply:ScreenFade(SCREENFADE.IN, Color(120, 0, 0, 180), 0.6, 0)
	ply:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75)
	GFR.Notify(ply, "You're down.")
	local downAt = CurTime()
	ply.GFR_DownedAt = downAt
	timer.Simple(0.4, function()
		if !IsValid(ply) then return end
		ply.GFR_GivingIn = nil -- (CollapseIntoZombie sets it again)
		-- Whatever was holding you (a grab's camera, a special infected's pin) lets go first
		ply.GOTDR_Grappled = false
		ply:SetViewEntity(ply)
		ply:UnSpectate()
		local eater = IsValid(att) && att.GFR_FeedOn && !att.Dead && att:Health() > 0 && att or nil
		local ok, err = xpcall(GFR.CollapseIntoZombie, debug.traceback, ply, eater)
		if !ok then
			-- (kept for checking: garrysmod/data/gfr_debug.txt)
			file.Append("gfr_debug.txt", os.date("%H:%M:%S") .. " CollapseIntoZombie: " .. tostring(err) .. "\n")
			ErrorNoHalt("[GFR] " .. tostring(err) .. "\n")
		end
	end)
	-- Never left stuck: if that didn't get you down onto the ground and watching (or up as a zombie), you die the old
	-- way instead (your body still gets up as one of them)
	timer.Simple(3, function()
		if !IsValid(ply) or ply.GFR_DownedAt != downAt then return end
		ply.GFR_DownedAt = nil
		if !ply:Alive() or ply.GFR_IsZombie or ply:GetNW2Bool("GFR_ZombieSpectate") then return end
		file.Append("gfr_debug.txt", os.date("%H:%M:%S") .. " zombie kill: still standing after 3 s (spectate " .. tostring(ply:GetObserverMode()) .. ")\n")
		ply.GFR_GivingIn = nil
		ply:GodDisable()
		ply:Freeze(false)
		ply:SetViewEntity(ply)
		ply:Kill()
	end)
	return true
end)

-- Tell the client when it's grabbed, for the "[J] Give in" prompt
timer.Create("GFR_GiveIn_Grabbed", 0.2, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local grabbed = ply:Alive() && ply.GOTDR_Grappled == true && !ply.GFR_IsZombie && !ply.GFR_GivingIn
		if ply:GetNW2Bool("GFR_Grabbed") != grabbed then ply:SetNW2Bool("GFR_Grabbed", grabbed) end
	end
end)

hook.Add("PlayerButtonDown", "GFR_GiveIn_Key", function(ply, button)
	if button == KEY_J && ply.GOTDR_Grappled then GFR.GiveIn(ply) end
end)

hook.Add("PlayerSpawn", "GFR_GiveIn_Spawn", function(ply) ply.GFR_Collapsing = nil end)

hook.Add("PlayerDeath", "GFR_GiveIn_Death", function(ply)
	ply.GFR_Collapsing = nil
	if ply.GFR_GivingIn then
		ply.GFR_GivingIn = nil
		ply:GodDisable()
		ply:Freeze(false)
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Eating while you control your zombie (VJ's controller switches the NPC's own eating off): E next to a body
local EAT_RANGE = 80
local BITES_PER_BODY = 12

local function FindFood(z)
	local best, bestDist
	for _, ent in ipairs(ents.FindInSphere(z:GetPos(), EAT_RANGE)) do
		if ent != z && (ent:GetClass() == "prop_ragdoll" or ent.GFR_Bait) && !ent.GFR_EatenBy && !ent.GFR_Limp then
			local d = z:GetPos():DistToSqr(ent:WorldSpaceCenter())
			if !bestDist or d < bestDist then best, bestDist = ent, d end
		end
	end
	return best
end

local function StopEating(z)
	if !IsValid(z) or !z.GFR_EatFood then return end
	if IsValid(z.GFR_EatFood) then z.GFR_EatFood.GFR_EatenBy = nil end
	z.GFR_EatFood = nil
	z.VJ_ST_Eating = nil
	timer.Remove("GFR_ZEat" .. z:EntIndex())
	timer.Remove("GFR_ZEatAnim" .. z:EntIndex())
	if z.GFR_Hunter then
		-- Hunter: up off the body
		if z.SetState then z:SetState() end
		z:SetNW2Bool("GFR_ZEating", false)
		if z:Health() > 0 && z.PlayAnim then z:PlayAnim(ACT_IDLE, false, 0.1, false) end
		return
	end
	if z.GFR_PuppetStart then
		-- L4D infected: get up off the body (GOTDR anim on its puppet, npc_gfr_infected)
		z:SetState()
		local p = z.GFR_Puppet
		if p && !z.GFR_Crawl && z:Health() > 0 && IsValid(p.rig) then
			-- The whole get-up plays (its real length, not a fixed 1.3 s), standing still while it does, and the rig
			-- doesn't fall back into the feeding loop at the end of it (that's its default animation)
			local stand = "eating01_to_stand"
			local s = p.rig:LookupSequence(stand)
			local dur = s >= 0 and p.rig:SequenceDuration(s) or 1.3
			p.loop, p.intro = nil, nil -- (npc_gfr_infected's loop keeper leaves it alone)
			p.rig:Fire("SetDefaultAnimation", stand)
			p.rig:Fire("SetAnimation", stand)
			z:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK, dur)
			-- (the close eating camera stays on until it's up: sh_zombieplayer.lua)
			timer.Simple(math.max(dur - 0.05, 0.3), function()
				if IsValid(z) && !z.GFR_EatFood then
					z:SetNW2Bool("GFR_ZEating", false)
					z:GFR_PuppetEnd()
					z:SetState()
				end
			end)
		else
			z:SetNW2Bool("GFR_ZEating", false)
			z:GFR_PuppetEnd()
		end
		return
	end
	z.AnimationTranslations[ACT_IDLE] = z.GFR_EatOrgIdle
	if z:Health() > 0 then z:PlayAnim(ACT_DISARM, true, false) end
end

local function Bite(z, food)
	VJ.EmitSound(z, "vj_cncr/eating/Eating_Loop_DL" .. math.random(1, 4) .. ".wav", 65)
	z:SetHealth(math.min(z:Health() + 15, z:GetMaxHealth()))
	local pos = food:WorldSpaceCenter()
	ParticleEffect("blood_impact_red_01", pos, z:GetAngles())
	local mouth = z:LookupAttachment("mouth")
	if mouth > 0 then ParticleEffectAttach("blood_impact_red_01", PATTACH_POINT_FOLLOW, z, mouth) end
	local tr = util.TraceLine({start = pos, endpos = pos - Vector(0, 0, 50), filter = {food, z}})
	util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal, food)
	food.GFR_Bites = (food.GFR_Bites or 0) + 1
	if GFR.ZombieFeed then GFR.ZombieFeed(z.GFR_ControlPlayer, food.GFR_Bait and 12 or 9) end -- (your zombie's hunger)
	if food.GFR_Bites >= (food.GFR_Bait and 3 or BITES_PER_BODY) then
		food:Remove() -- nothing left
		StopEating(z)
	end
end

local function FoodGone(z, f)
	return !IsValid(f) or f:GetPos():DistToSqr(z.GFR_EatFoodFrom or f:GetPos()) > 100 * 100
		or z:GetPos():DistToSqr(z.GFR_EatFrom or z:GetPos()) > 60 * 60
end

local function StartEating(ply, z)
	local food = FindFood(z)
	if !IsValid(food) then
		GFR.Notify(ply, "Nothing to eat here.")
		return
	end
	food.GFR_EatenBy = z
	-- Where it all started: eating stops if the food gets taken / dragged off or your zombie gets moved, not by measuring
	-- to the food's "centre" (a ragdoll's can be far from where the body lies: it stopped right away, straight into
	-- getting back up)
	z.GFR_EatFrom, z.GFR_EatFoodFrom = z:GetPos(), food:GetPos()
	z.GFR_EatFood = food
	z:SetTurnTarget(food, 1)
	VJ.EmitSound(z, "vj_cncr/eating/Eating_Begin" .. math.random(1, 2) .. ".wav", 65)
	if z.GFR_Hunter then
		-- Hunter: crouched over the body, shredding it (its pinned-victim animation), with its shred sounds
		z.VJ_ST_Eating = true
		z:SetNW2Bool("GFR_ZEating", true)
		z:StopMoving()
		if z.SetState then z:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK) end
		local seq = z:LookupSequence("Melee_Pounce")
		local function Shred()
			if seq < 0 then return end
			if z.PlayAnim then
				z:PlayAnim("vjseq_Melee_Pounce", true, false, false)
			elseif z.VJ_ACT_PLAYACTIVITY then
				z:VJ_ACT_PLAYACTIVITY("Melee_Pounce", true, false, false)
			end
		end
		Shred()
		local animId = "GFR_ZEatAnim" .. z:EntIndex()
		timer.Create(animId, 0.3, 0, function()
			if !IsValid(z) or !z.GFR_EatFood or z:Health() <= 0 then timer.Remove(animId) return end
			if seq >= 0 && z:GetSequence() != seq then Shred() end
		end)
		local id = "GFR_ZEat" .. z:EntIndex()
		timer.Create(id, 2, 0, function()
			if !IsValid(z) or z:Health() <= 0 then timer.Remove(id) return end
			local f = z.GFR_EatFood
			if FoodGone(z, f) then
				StopEating(z)
				return
			end
			z:EmitSound("player/hunter/voice/attack/hunter_shred_" .. string.format("%02d", math.random(1, 12)) .. ".mp3", 75)
			Bite(z, f)
		end)
		return
	end
	if z.GFR_PuppetStart then
		-- L4D infected: hunch over the body with GOTDR's feeding animation on its puppet; stays put until E again
		z.VJ_ST_Eating = true
		z:SetNW2Bool("GFR_ZEating", true)
		z:StopMoving()
		z:SetState(VJ_STATE_ONLY_ANIMATION_NOATTACK)
		if !z.GFR_Crawl then z:GFR_PuppetStart("eating01", "eating01_to_start") end
		local id = "GFR_ZEat" .. z:EntIndex()
		timer.Create(id, 2.5, 0, function()
			if !IsValid(z) or z:Health() <= 0 then timer.Remove(id) return end
			local f = z.GFR_EatFood
			if FoodGone(z, f) then
				StopEating(z)
				return
			end
			Bite(z, f)
		end)
		return
	end
	z.GFR_EatOrgIdle = z.AnimationTranslations[ACT_IDLE]
	z.AnimationTranslations[ACT_IDLE] = ACT_GESTURE_RANGE_ATTACK1
	-- GOTDR's TranslateActivity forces its own idle (it would stand back up) unless this flag is set;
	-- VJ normally sets it in its eating AI, which the controller switches off
	z.VJ_ST_Eating = true
	z:PlayAnim(ACT_ARM, true, false)

	-- Keep the feeding loop going: if anything swaps the animation out, put it back (after the crouch-down finishes)
	local loopSeq = z:SelectWeightedSequence(ACT_GESTURE_RANGE_ATTACK1)
	local armSeq = z:SelectWeightedSequence(ACT_ARM)
	local loopFrom = CurTime() + (armSeq >= 0 and z:SequenceDuration(armSeq) or 1.5)
	local animId = "GFR_ZEatAnim" .. z:EntIndex()
	timer.Create(animId, 0.3, 0, function()
		if !IsValid(z) or !z.GFR_EatFood or z:Health() <= 0 then timer.Remove(animId) return end
		if CurTime() < loopFrom or loopSeq < 0 then return end
		if z:GetSequence() != loopSeq then
			z:PlayAnim(ACT_GESTURE_RANGE_ATTACK1, true, false, false)
		end
	end)

	local id = "GFR_ZEat" .. z:EntIndex()
	timer.Create(id, 2.5, 0, function()
		if !IsValid(z) or z:Health() <= 0 then timer.Remove(id) return end
		local f = z.GFR_EatFood
		-- Walking away, or the body got knocked away: stop
		if FoodGone(z, f) or z:IsMoving() then
			StopEating(z)
			return
		end
		Bite(z, f)
	end)
end

-- (lost to the hunger, your zombie feeds by itself: sv_zombiehunger.lua)
GFR.ZombieStartEating = StartEating
GFR.ZombieStopEating = StopEating

hook.Add("KeyPress", "GFR_Extract_ZombieEat", function(ply, key)
	if key != IN_USE or !ply.GFR_IsZombie or !ply.VJ_IsControllingNPC then return end
	local cont = ply.VJ_TheControllerEntity
	local z = IsValid(cont) and cont.VJCE_NPC
	if !IsValid(z) or z:Health() <= 0 then return end
	if z.GFR_EatFood then StopEating(z) return end
	-- Carrying food for people who took you in, or handing it over (sv_zombietame.lua) comes before eating
	if GFR.ZombieUse && GFR.ZombieUse(ply, z) then return end
	StartEating(ply, z)
end)

local function InjectSelf(ply)
	ply:EmitSound("items/medshot4.wav")
	net.Start("GFR_BloodSplat")
	net.Send(ply)
	GFR.Notify(ply, "The extract is taking hold.")
	ply:SetNW2Bool("GFR_HandsUp", true) -- no shooting while it takes hold
	timer.Simple(4, function()
		if !IsValid(ply) then return end
		ply:SetNW2Bool("GFR_HandsUp", false)
		if ply:Alive() then GFR.BecomeZombie(ply) end
	end)
end

function GFR.UseExtract(ply)
	if !ply:Alive() or ply.GFR_Tied or ply.GFR_IsZombie then return false end
	local npc = LookedAtNPC(ply)
	if npc then
		InjectNPC(ply, npc)
		return true
	end
	-- Self-injection needs confirming
	if (ply.GFR_ExtractConfirm or 0) > CurTime() then
		ply.GFR_ExtractConfirm = nil
		InjectSelf(ply)
		return true
	end
	ply.GFR_ExtractConfirm = CurTime() + 5
	GFR.Notify(ply, "Inject YOURSELF? Use it again within 5 seconds to confirm. (Look at someone to inject them instead.)")
	return false
end

-- You die as a player while you're a zombie (the kill command, or anything that kills the hidden player rather than
-- the zombie): the zombie is your body, so the player's own death ragdoll is never left lying about, and a kill
-- while driving it ends that body (HandleRelease)
hook.Add("PlayerDeath", "GFR_ZombiePlayer_NoExtraBody", function(ply)
	if !ply.GFR_IsZombie then return end
	if IsValid(ply.GFR_ZombieNPC) && ply.GFR_ZombieNPC:Health() > 0 then ply.GFR_ZSuicide = true end
	timer.Simple(0, function()
		if !IsValid(ply) then return end
		local rag = ply:GetRagdollEntity()
		if IsValid(rag) then rag:Remove() end
	end)
end)

-- While your zombie body is down, you can't respawn early
hook.Add("PlayerDeathThink", "GFR_ZombiePlayer_Down", function(ply)
	if ply.GFR_ZombieRise then return false end
end)

hook.Add("PlayerSpawn", "GFR_Extract_ZWatchEnd", function(ply)
	if IsValid(ply:GetNW2Entity("GFR_ZWatch")) then ply:SetNW2Entity("GFR_ZWatch", NULL) end
end)

hook.Add("PlayerSpawn", "GFR_Extract_Spawn", function(ply)
	-- VJ's controller respawns you itself when control ends; that's handled in HandleRelease
	if ply.GFR_ZReleasing then return end
	local rise = ply.GFR_ZombieRise
	ply.GFR_ZombieRise = nil
	if rise then
		-- Your body gets back up where it fell, still carrying your stuff
		ply:UnSpectate()
		timer.Simple(0.1, function() -- after other spawn hooks (bed respawn, loadout)
			if !IsValid(ply) or !ply:Alive() then return end
			local corpse = IsValid(rise.corpse) and rise.corpse or (IsValid(ply.GFR_ZCorpseEnt) and ply.GFR_ZCorpseEnt) or nil
			ply.GFR_ZCorpseEnt = nil
			-- Up from where the body actually lies (it may have been pushed or dragged), facing the way it lay
			local pos, yaw = rise.pos, rise.ang.y
			if IsValid(corpse) then
				local pelvis = corpse:LookupBone("ValveBiped.Bip01_Pelvis")
				local p = pelvis and corpse:GetBonePosition(pelvis) or corpse:GetPos()
				local tr = util.TraceLine({start = p + Vector(0, 0, 10), endpos = p - Vector(0, 0, 120), filter = corpse, mask = MASK_PLAYERSOLID_BRUSHONLY})
				pos = tr.HitPos + Vector(0, 0, 2)
				yaw = corpse:GetAngles().y
				corpse:Remove() -- (the zombie that gets up replaces it: no second body left behind)
			end
			ply:SetPos(pos)
			ply:SetEyeAngles(Angle(0, yaw, 0))
			GFR.BecomeZombie(ply, true)
			-- ...and it drags itself up off the ground (lying, then the get-up animation)
			local z = ply.GFR_ZombieNPC
			if IsValid(z) && GFR.ZombieRise then GFR.ZombieRise(z, 0.6) end
		end)
		return
	end
	ply.GFR_IsZombie = nil
	ply.GFR_ZombieGear = nil
	ply.GFR_ZombieKind = nil
	ply.GFR_ParasiteHost = nil
	ply:SetNW2Bool("GFR_IsZombie", false)
	ply.VJ_NPC_Class = nil
end)
