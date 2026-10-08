--[[
	Custom Apocalypse - hunters (Left 4 Dead 2 Special Infected pack: npc_vj_l4d2_hunter)
	Hunters never appear on their own. They come only from the military's Experimental Vial (gfr_item_hvial):
		- bought from soldiers (sv_npc.lua trade stock)
		- used on a survivor you're looking at: they scream, collapse, lie there, twitch... and get up a hunter (AI)
		- used on yourself (twice to confirm): you collapse, twitch, and get up as a hunter YOU control
		  (sv_extract.lua: GFR.CollapseIntoZombie / GFR.BecomeZombie with GFR_ZombieKind = "hunter")
		- surrender to soldiers and they may inject you (sv_surrender.lua): you collapse and get up a hunter you
		  DON'T control; you watch it go, then respawn
	The military leaves its hunters alone and the hunters leave soldiers alone (sv_spawner.lua relations), until
	one of them attacks the other.
	Pinned by a hunter: mash E to kick it off (the pack's hunter otherwise only lets go when someone else hits it).
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvMash   = CreateConVar("gfr_hunter_mash", "10", flags, "E presses to kick off a hunter that has you pinned")
local cvHealth = CreateConVar("gfr_hunter_health", "250", flags, "Hunter health")

local REACH = 100

function GFR.HunterClass()
	if scripted_ents.GetStored("npc_vj_l4d2_hunter") then return "npc_vj_l4d2_hunter" end
	if scripted_ents.GetStored("npc_vj_l4d_hunter") then return "npc_vj_l4d_hunter" end
end

local function IsHunter(ent) return IsValid(ent) && ent.GFR_Hunter end
local function IsSoldier(ent) return IsValid(ent) && ent.GFR_Group && ent.GFR_Group.faction == "military" end

---------------------------------------------------------------------------------------------------------------------------------------------
-- The military and its hunters
function GFR.HunterTruce(h, npc)
	if !IsValid(h) or !IsValid(npc) or h.GFR_HunterBetrayed then return end
	h:AddEntityRelationship(npc, D_NU, 99)
	npc:AddEntityRelationship(h, D_NU, 99)
	if h.SetRelationshipMemory && VJ && VJ.MEM_OVERRIDE_DISPOSITION then h:SetRelationshipMemory(npc, VJ.MEM_OVERRIDE_DISPOSITION, D_NU) end
	if h:GetEnemy() == npc then h:SetEnemy(NULL) end
	if npc:GetEnemy() == h then npc:SetEnemy(NULL) end
end

local function TruceAll(h)
	for _, npc in ipairs(ents.GetAll()) do
		if IsSoldier(npc) && npc:Health() > 0 then GFR.HunterTruce(h, npc) end
	end
end

-- Wearing the person it was: their playermodel bonemerged onto the (hidden) hunter skeleton, both Valve-biped.
-- The hunter's own material is swapped for an invisible one (alpha alone doesn't hide alpha-tested parts).
local INVISIBLE = "models/effects/vol_light001"
local skinTint = Color(195, 205, 185)

local function HideBase(ent)
	ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
	ent:SetColor(Color(255, 255, 255, 0))
	ent:SetMaterial(INVISIBLE)
	ent:DrawShadow(false)
	ent:SetNW2Bool("GFR_HideBase", true) -- (not drawn at all client side: sh_zombieplayer.lua)
end

local function Dress(parent, look)
	if !look or !look.model or !util.IsValidModel(look.model) then return end
	local class = scripted_ents.GetStored("gfr_bonemerge") and "gfr_bonemerge" or "prop_dynamic"
	local body = ents.Create(class)
	if !IsValid(body) then return end
	body:SetModel(look.model)
	body:SetPos(parent:GetPos())
	body:SetAngles(parent:GetAngles())
	body:SetParent(parent)
	body:Spawn()
	body:AddEffects(EF_BONEMERGE)
	if !body:LookupBone("ValveBiped.Bip01_Pelvis") then body:Remove() return end
	body:SetSkin(look.skin or 0)
	for i, v in pairs(look.bodygroups or {}) do body:SetBodygroup(i, v) end
	body:SetColor(skinTint)
	if look.color && body.SetPlayerColor then body:SetPlayerColor(look.color) end
	parent:DeleteOnRemove(body)
	HideBase(parent)
	parent.Bonemerge = body
	return body
end

-- Keep the hunter itself hidden (the pack's ghosting / fire effects can reset it)
timer.Create("GFR_Hunter_KeepHidden", 0.5, 0, function()
	for _, h in ipairs(ents.GetAll()) do
		if h.GFR_HunterLook && IsValid(h.Bonemerge) && h:GetMaterial() != INVISIBLE then HideBase(h) end
	end
end)

-- Its corpse: VJ copies the NPC's (invisible) material and colour onto the corpse, so make it visible again, or
-- dress it in the body it wore. It counts as a zombie corpse: your own hunter gets back up in it if the head is
-- intact (sv_extract.lua), its head can be destroyed (sv_rise.lua), zombies won't eat it.
local function HookCorpse(h)
	local orig = h.OnCreateDeathCorpse
	h.OnCreateDeathCorpse = function(self, dmginfo, hitgroup, corpse)
		if orig then orig(self, dmginfo, hitgroup, corpse) end
		if !IsValid(corpse) then return end
		corpse:SetMaterial("")
		corpse:SetRenderMode(RENDERMODE_NORMAL)
		corpse:SetColor(color_white)
		corpse:DrawShadow(true)
		if self.GFR_HunterLook then Dress(corpse, self.GFR_HunterLook) end
		corpse.GFR_ZCorpse = true
		corpse:SetNW2Bool("GFR_ZCorpse", true)
		self.RTRG_DeathHitgroup = self.RTRG_DeathHitgroup or hitgroup
		hook.Run("RTRG_ZombieCorpse", self, corpse)
	end
end

-- Every hunter we make goes through here. look = {model, skin, bodygroups, color}: the person it was
function GFR.SetupHunter(h, look)
	if look && Dress(h, look) then h.GFR_HunterLook = look end
	HookCorpse(h)
	h.GFR_Hunter = true
	h:SetNW2Bool("GFR_Hunter", true)
	local hp = cvHealth:GetInt()
	h:SetMaxHealth(hp)
	h:SetHealth(hp)
	h.GFR_TurnedAt = CurTime()
	-- (after the spawner's "new zombie" relations, which run a moment after creation)
	timer.Simple(0.3, function() if IsValid(h) then TruceAll(h) end end)
	timer.Simple(2, function() if IsValid(h) then TruceAll(h) end end)
end

-- One side attacks the other: that hunter and the soldiers are enemies from then on
hook.Add("EntityTakeDamage", "GFR_Hunter_Betrayal", function(target, dmg)
	local att = dmg:GetAttacker()
	local h, soldier
	if IsHunter(target) && IsSoldier(att) then h, soldier = target, att
	elseif IsHunter(att) && IsSoldier(target) then h, soldier = att, target end
	if !h or h.GFR_HunterBetrayed then return end
	h.GFR_HunterBetrayed = true
	for _, npc in ipairs(ents.GetAll()) do
		if IsSoldier(npc) then
			h:AddEntityRelationship(npc, D_HT, 99)
			npc:AddEntityRelationship(h, D_HT, 99)
			if h.SetRelationshipMemory && VJ && VJ.MEM_OVERRIDE_DISPOSITION then h:SetRelationshipMemory(npc, VJ.MEM_OVERRIDE_DISPOSITION, D_HT) end
		end
	end
	local owner = h.GFR_ControlPlayer
	if IsValid(owner) then GFR.Notify(owner, "The soldiers have turned on you.") end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Turning into one
local function Look(ent, model, body)
	body = IsValid(body) and body or ent
	local bodygroups = {}
	for i = 0, body:GetNumBodyGroups() - 1 do bodygroups[i] = body:GetBodygroup(i) end
	return {model = model or body:GetModel(), skin = body:GetSkin(), bodygroups = bodygroups, color = body.GetPlayerColor and body:GetPlayerColor() or nil}
end

local function SpawnHunterAt(rag, look)
	local class = GFR.HunterClass()
	local pelvis = rag:LookupBone("ValveBiped.Bip01_Pelvis")
	local p = pelvis and rag:GetBonePosition(pelvis) or rag:GetPos()
	local tr = util.TraceLine({start = p + Vector(0, 0, 10), endpos = p - Vector(0, 0, 120), filter = rag, mask = MASK_NPCSOLID_BRUSHONLY})
	local yaw = rag:GetAngles().y
	local fx = EffectData()
	fx:SetOrigin(rag:WorldSpaceCenter())
	util.Effect("BloodImpact", fx)
	rag:Remove()
	if !class then return end
	local h = ents.Create(class)
	if !IsValid(h) then return end
	h:SetPos(tr.HitPos + Vector(0, 0, 4))
	h:SetAngles(Angle(0, yaw, 0))
	h:Spawn()
	h:Activate()
	GFR.SetupHunter(h, look)
	h:EmitSound("player/hunter/voice/attack/shriek_1.mp3", 95)
	return h
end

-- The body of someone (src: player or NPC) drops, lies, twitches, and gets up a hunter. onRise(h), onFail(pos)
local function TurnIntoHunter(src, look, onRise, onFail)
	local rag = GFR.DropTurningBody && GFR.DropTurningBody(src, look)
	return rag, rag && GFR.TurnBody(rag, look, {
		rise = function(body)
			local h = SpawnHunterAt(body, look)
			if IsValid(h) then
				if onRise then onRise(h) end
			elseif onFail then
				onFail(body:GetPos())
			end
		end,
		onFail = onFail
	})
end

-- A survivor (NPC) injected with the vial
local function InjectNPC(ply, npc)
	ply:EmitSound("items/medshot4.wav")
	local dmg = DamageInfo()
	dmg:SetDamage(3)
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetAttacker(ply)
	dmg:SetInflictor(ply)
	npc:TakeDamageInfo(dmg)
	if npc.GFR_Group && GFR.Say then
		GFR.Say(npc, ({"What is that?! It's cold, it's so cold...", "Get away from me! What did you do?!", "My heart... something's wrong..."})[math.random(3)])
	end
	GFR.Notify(ply, "You inject them with the vial. Step back.")
	npc.GFR_Injected = true
	timer.Simple(math.Rand(6, 10), function()
		if !IsValid(npc) or npc:Health() <= 0 then return end
		local look = Look(npc, npc.GFR_PlayerModel, npc.GFR_Body)
		local wep = npc:GetActiveWeapon()
		if IsValid(wep) then
			npc:DropWeapon(wep)
			timer.Simple(0, function() if IsValid(wep) && !IsValid(wep:GetOwner()) then wep.GFR_Loot = true end end)
		end
		npc:EmitSound("vj_cncr/zombie/zombie_pain" .. math.random(1, 8) .. ".wav", 80, 110)
		TurnIntoHunter(npc, look)
		npc:Remove()
	end)
end

-- Watching what you became: the camera stays on it (re-attached if anything knocks it off) and you see through
-- dead eyes (vein overlay, sh_zombieplayer.lua) until you respawn
local function Watch(ply, ent, minSeconds)
	if !IsValid(ply) or ply:Alive() or !IsValid(ent) then return end
	ply.GFR_WatchEnt = ent
	ply.GFR_SpectateUntil = math.max(ply.GFR_SpectateUntil or 0, CurTime() + minSeconds)
	ply:SetNW2Bool("GFR_ZombieSpectate", true)
	ply:Spectate(OBS_MODE_CHASE)
	ply:SpectateEntity(ent)
end

timer.Create("GFR_Hunter_Watch", 0.5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local ent = ply.GFR_WatchEnt
		if !ent then continue end
		if ply:Alive() then ply.GFR_WatchEnt = nil continue end
		if !IsValid(ent) then continue end -- (it died: the camera stays where it fell)
		if !ply:GetNW2Bool("GFR_ZombieSpectate") then ply:SetNW2Bool("GFR_ZombieSpectate", true) end
		if ply:GetObserverMode() != OBS_MODE_CHASE or ply:GetObserverTarget() != ent then
			ply:Spectate(OBS_MODE_CHASE)
			ply:SpectateEntity(ent)
		end
	end
end)

hook.Add("PlayerSpawn", "GFR_Hunter_WatchEnd", function(ply) ply.GFR_WatchEnt = nil end)

-- You, injected by the soldiers after surrendering: an AI hunter you only watch
function GFR.HunterTurnPlayer(ply)
	if !IsValid(ply) or !ply:Alive() then return end
	local look = Look(ply)
	local gear = GFR.CollectGear && GFR.CollectGear(ply)
	ply:GodEnable()
	ply:Freeze(true)
	ply:ScreenFade(SCREENFADE.OUT, Color(20, 40, 70, 200), 1, 0.5)
	timer.Simple(1.5, function()
		if !IsValid(ply) or !ply:Alive() then return end
		ply:GodDisable()
		ply:Freeze(false)
		local rag, total = TurnIntoHunter(ply, look,
			function(h)
				h.GFR_Gear = gear -- kill it to get your things back (sv_infection.lua drops it)
				h:SetName(ply:Nick() .. " (Hunter)")
				local cv = GetConVar("gfr_turn_spectate")
				Watch(ply, h, cv and cv:GetFloat() or 15)
			end,
			function(pos)
				if GFR.DropGearBag then GFR.DropGearBag(pos, gear) end
				if IsValid(ply) then ply.GFR_SpectateUntil = CurTime() + 2 end
			end)
		ply.GFR_Turning = true
		ply:KillSilent()
		ply.GFR_Turning = nil
		if IsValid(rag) then
			rag.GFR_PlayerBody = ply
			Watch(ply, rag, (total or 25) + 3)
		elseif GFR.DropGearBag then
			GFR.DropGearBag(ply:GetPos(), gear)
		end
		GFR.Notify(ply, "Whatever was in that vial is rewriting you. You're not the one in control anymore.")
	end)
end

-- You, injecting yourself: for 10 seconds it spreads - the veins creep across your sight, pulsing with your heart,
-- the world going darker and darker (sh_zombieplayer.lua draws it from NW2 GFR_VialT) - then you collapse, and get
-- up a hunter you control
local VIAL_TIME = 10
local function InjectSelf(ply)
	ply:EmitSound("items/medshot4.wav")
	GFR.Notify(ply, "It burns its way up your arm. You can feel it spreading...")
	ply.GFR_ZombieKind = "hunter"
	local t0 = CurTime()
	-- (checked against a plain field: the networked float is stored less precisely, so it never equalled t0 exactly
	-- and the collapse never came)
	ply.GFR_VialStart = t0
	ply:SetNW2Float("GFR_VialT", t0)
	ply.GFR_VialRun = ply:GetRunSpeed()
	ply:SetRunSpeed(ply:GetWalkSpeed()) -- (no running it off)
	timer.Simple(VIAL_TIME * 0.5, function()
		if IsValid(ply) && ply:Alive() && ply.GFR_VialStart == t0 then GFR.Notify(ply, "Your legs are going numb...") end
	end)
	timer.Simple(VIAL_TIME, function()
		if !IsValid(ply) or ply.GFR_VialStart != t0 then return end
		ply.GFR_VialStart = nil
		ply:SetNW2Float("GFR_VialT", 0)
		if ply.GFR_VialRun then ply:SetRunSpeed(ply.GFR_VialRun) ply.GFR_VialRun = nil end
		if !ply:Alive() then return end
		ply:ViewPunch(Angle(25, math.Rand(-10, 10), 0))
		GFR.CollapseIntoZombie(ply)
	end)
end

-- (died some other way first: the effect stops)
hook.Add("PlayerDeath", "GFR_Hunter_VialStop", function(ply)
	ply.GFR_VialStart = nil
	if ply:GetNW2Float("GFR_VialT", 0) > 0 then
		ply:SetNW2Float("GFR_VialT", 0)
		if ply.GFR_VialRun then ply:SetRunSpeed(ply.GFR_VialRun) ply.GFR_VialRun = nil end
	end
end)

local function LookedAtNPC(ply)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = ply, mask = MASK_SHOT})
	local ent = tr.Entity
	if IsValid(ent) && ent:IsNPC() && ent:Health() > 0 && !GFR.IsZombie(ent) && ent:LookupBone("ValveBiped.Bip01_Pelvis") then return ent end
end

function GFR.UseHunterVial(ply)
	if !ply:Alive() or ply.GFR_Tied or ply.GFR_IsZombie or ply.GFR_GivingIn then return false end
	if ply:GetNW2Float("GFR_VialT", 0) > 0 then return false end -- (already in you)
	if !GFR.HunterClass() then
		GFR.Notify(ply, "Nothing happens. (Left 4 Dead 2 Special Infected pack missing)")
		return false
	end
	local npc = LookedAtNPC(ply)
	if npc then
		InjectNPC(ply, npc)
		return true
	end
	if (ply.GFR_HVialConfirm or 0) > CurTime() then
		ply.GFR_HVialConfirm = nil
		InjectSelf(ply)
		return true
	end
	ply.GFR_HVialConfirm = CurTime() + 5
	GFR.Notify(ply, "Inject YOURSELF with the vial? Use it again within 5 seconds. (Look at someone to inject them instead.)")
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- People wearing a playermodel over a hidden NPC (our survivors/bandits/soldiers, turned infected) being held down.
-- The pack shows the held victim as a stand-in built from the victim's own model: that's the hidden base model
-- (a Combine soldier, a citizen, an L4D skeleton). Show their playermodel on it instead, and hide their real body
-- (frozen standing while held) until they're let go.
local function WornBody(ent)
	local body = IsValid(ent.GFR_Body) and ent.GFR_Body or (IsValid(ent.Bonemerge) and ent.Bonemerge) or nil
	return body
end

local function PatchIncapacitate()
	local meta = FindMetaTable("NPC")
	if !meta or !meta.IncapacitateEnemy or meta.GFR_IncapPatched then return end
	local orig = meta.IncapacitateEnemy
	meta.IncapacitateEnemy = function(self, ent, parent)
		local mdl = orig(self, ent, parent)
		local body = IsValid(ent) && WornBody(ent)
		if body then
			if IsValid(mdl) then
				mdl:SetModel(body:GetModel())
				mdl:SetSkin(body:GetSkin())
				for i = 0, body:GetNumBodyGroups() - 1 do mdl:SetBodygroup(i, body:GetBodygroup(i)) end
				mdl:SetMaterial("")
				mdl:SetRenderMode(RENDERMODE_NORMAL)
				mdl:SetColor(body:GetColor().a > 0 and body:GetColor() or color_white)
				if body.GetPlayerColor && mdl.SetPlayerColor then mdl:SetPlayerColor(body:GetPlayerColor()) end
			end
			body:SetNoDraw(true)
			ent.GFR_PinHidBody = body
		end
		return mdl
	end
	meta.GFR_IncapPatched = true
end
hook.Add("InitPostEntity", "GFR_Hunter_PatchIncap", PatchIncapacitate)
if GAMEMODE then PatchIncapacitate() end

-- Let go (or the hunter died): their body back
timer.Create("GFR_Hunter_RestoreBodies", 0.3, 0, function()
	for _, ent in ipairs(ents.GetAll()) do
		local body = ent.GFR_PinHidBody
		if body then
			local held = false
			for _, h in ipairs(ents.FindByClass("npc_vj_l4d*")) do
				if h.pIncapacitatedEnemy == ent && h.HasEnemyIncapacitated then held = true break end
			end
			if !held then
				ent.GFR_PinHidBody = nil
				if IsValid(body) then body:SetNoDraw(false) end
				if IsValid(ent) && ent.GFR_Body && GFR.HideBaseNPC then GFR.HideBaseNPC(ent) end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Pinned: mash E to kick it off
local function PinnedBy(ply)
	for _, h in ipairs(ents.GetAll()) do
		if h.pIncapacitatedEnemy == ply && h.HasEnemyIncapacitated then return h end
	end
end

timer.Create("GFR_Hunter_Pins", 0.2, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local h = ply:Alive() && PinnedBy(ply)
		if !h then ply.GFR_PinMash = 0 end
		if ply:GetNW2Bool("GFR_Pinned") != (h and true or false) then ply:SetNW2Bool("GFR_Pinned", h and true or false) end
	end
end)

hook.Add("KeyPress", "GFR_Hunter_KickOff", function(ply, key)
	if key != IN_USE or !ply:GetNW2Bool("GFR_Pinned") then return end
	local h = PinnedBy(ply)
	if !IsValid(h) then return end
	ply.GFR_PinMash = (ply.GFR_PinMash or 0) + 1
	ply:ViewPunch(Angle(math.Rand(-3, 3), math.Rand(-4, 4), 0))
	if ply.GFR_PinMash < cvMash:GetInt() then return end
	ply.GFR_PinMash = 0
	if h.DismountHunter then h:DismountHunter() end
	-- Knocked back, and it needs a moment before it can leap again
	local seq = "Melee_Pounce_Knockoff_Backward"
	if h.VJ_ACT_PLAYACTIVITY && h:LookupSequence(seq) >= 0 then
		h:VJ_ACT_PLAYACTIVITY(seq, true, h:SequenceDuration(h:LookupSequence(seq)), false)
	end
	h.NextLeapAttackT = CurTime() + 4
	h:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 75)
	timer.Simple(0, function()
		if !IsValid(ply) or !ply:Alive() then return end
		ply:SetVelocity(-ply:GetForward() * 120 + Vector(0, 0, 120))
	end)
	GFR.Notify(ply, "You kick it off!")
end)

-- Testing: gfr_spawn_hunter [how many] puts (military-tamed) hunters where you look
concommand.Add("gfr_spawn_hunter", function(ply, _, args)
	if !IsValid(ply) or !GFR.CanCheat(ply) or !GFR.HunterClass() then return end
	local list = {}
	for _, m in pairs(player_manager.AllValidModels()) do
		local l = string.lower(m)
		if !string.find(l, "zombie", 1, true) && !string.find(l, "combine", 1, true) then list[#list + 1] = m end
	end
	local base = ply:GetEyeTrace().HitPos
	local n = math.Clamp(math.floor(tonumber(args[1] or "") or 1), 1, 10)
	for i = 1, n do
		local h = ents.Create(GFR.HunterClass())
		if !IsValid(h) then return end
		local off = i == 1 and Vector(0, 0, 0) or Vector(math.Rand(-120, 120), math.Rand(-120, 120), 0)
		h:SetPos(base + off + Vector(0, 0, 8))
		h:Spawn()
		h:Activate()
		-- Someone random: one of the installed playermodels
		local mdl = #list > 0 and list[math.random(#list)] or nil
		GFR.SetupHunter(h, mdl and {model = mdl, skin = 0, bodygroups = {}, color = Vector(math.Rand(0.1, 0.5), math.Rand(0.1, 0.5), math.Rand(0.1, 0.5))} or nil)
	end
end, nil, "Spawn hunters where you look: gfr_spawn_hunter [how many, 1-10]")
