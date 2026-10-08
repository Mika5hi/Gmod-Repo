--[[
	Custom Apocalypse - things you can do to people (E on a friendly survivor / soldier -> Actions, cl_npc.lua)

	Chat       a word or two about the world (what Talk used to be)
	Give food  hand over something to eat from your pack: they owe you one (one of them comes along for free,
	           sv_companions.lua), sometimes they pay you back in caps
	Push       shove them over: they go limp on the ground for a few seconds and get back up, annoyed.
	           If one of the dead is close enough to reach them first, it falls on them and feeds like it does when
	           you give in - fifteen seconds, then it wanders off and what's left gets up as one of them.
	           Their friends saw what you did.
]]

local LIMP_TIME = 4      -- seconds on the ground when nothing gets them
local REACH = 380        -- how close one of the dead has to be to get to them first
local CATCH_TIME = 9     -- how long the dead get to reach them before they're back up
local FEED_TIME = 15

local pushedLines = {"Hey! What the hell?!", "Whoa-!", "Are you insane?!"}
local upLines = {"Do that again and I'll shoot you.", "What's wrong with you?", "Touch me again. I dare you."}
local thanksLines = {"...Thank you. Really.", "God, I haven't eaten in days.", "I won't forget this."}

local function Line(t) return t[math.random(#t)] end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Limp: the person is hidden and frozen in place while a ragdoll of them lies on the ground
local function HidePerson(npc, on)
	local body, wep = npc.GFR_Body, npc:GetActiveWeapon()
	npc:SetNoDraw(on)
	if IsValid(body) then body:SetNoDraw(on) end
	if IsValid(wep) then wep:SetNoDraw(on) end
	npc:SetNotSolid(on)
	if on then
		npc.GFR_LimpMoveType = npc:GetMoveType()
		npc:SetMoveType(MOVETYPE_NONE)
		npc:AddFlags(FL_NOTARGET)
		npc:SetSchedule(SCHED_NPC_FREEZE)
	else
		npc:SetMoveType(npc.GFR_LimpMoveType or MOVETYPE_STEP)
		npc:RemoveFlags(FL_NOTARGET)
		npc:SetSchedule(SCHED_IDLE_STAND)
	end
end

local function LookOf(npc)
	local body = npc.GFR_Body
	local look = {model = npc.GFR_PlayerModel, skin = 0, bodygroups = {}}
	if IsValid(body) then
		look.skin = body:GetSkin()
		for i = 0, body:GetNumBodyGroups() - 1 do look.bodygroups[i] = body:GetBodygroup(i) end
		look.color = body.GetPlayerColor and body:GetPlayerColor() or nil
	end
	return look
end

local function MakeLimp(npc, look, vel)
	if !look.model then return end
	local rag = ents.Create("prop_ragdoll")
	if !IsValid(rag) then return end
	rag:SetModel(look.model)
	rag:SetPos(npc:GetPos())
	rag:SetAngles(npc:GetAngles())
	rag:Spawn()
	rag:Activate()
	if !rag:LookupBone("ValveBiped.Bip01_Pelvis") then rag:Remove() return end
	rag:SetSkin(look.skin)
	for i, v in pairs(look.bodygroups) do rag:SetBodygroup(i, v) end
	if look.color then rag:SetNW2Vector("GFR_PlyColor", look.color) end
	-- Posed as they stood
	local center = npc:GetPos()
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local bone = npc:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)))
		local m = bone && npc:GetBoneMatrix(bone)
		if IsValid(phys) then
			if m && m:GetTranslation():DistToSqr(center) < 150 * 150 then
				phys:SetPos(m:GetTranslation())
				phys:SetAngles(m:GetAngles())
			end
			phys:SetVelocity(vel)
		end
	end
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	rag.GFR_Limp = npc
	return rag
end

local function Pelvis(rag)
	local b = rag:LookupBone("ValveBiped.Bip01_Pelvis")
	return b and rag:GetBonePosition(b) or rag:GetPos()
end

local function GroundUnder(pos, filter)
	local tr = util.TraceLine({start = pos + Vector(0, 0, 20), endpos = pos - Vector(0, 0, 150), filter = filter, mask = MASK_NPCSOLID_BRUSHONLY})
	return tr.HitPos + Vector(0, 0, 2)
end

local function GetUp(npc, rag)
	if !IsValid(npc) or npc:Health() <= 0 then
		if IsValid(rag) && rag.GFR_Limp then rag:Remove() end
		return
	end
	if IsValid(rag) then
		npc:SetPos(GroundUnder(Pelvis(rag), {rag, npc}))
		rag:Remove()
	end
	npc.GFR_LimpRag = nil
	HidePerson(npc, false)
	GFR.Say(npc, Line(upLines))
end

-- One of the dead close enough to get to them first
local function FindEater(pos)
	local best, bestD
	for _, z in ipairs(ents.FindInSphere(pos, REACH)) do
		if z:IsNPC() && z:Health() > 0 && !z.Dead && GFR.IsZombie(z) && z.GFR_FeedOn && !z.GFR_ControlPlayer
			&& !z.GFR_ScriptFeed && !z.GOTDR_CurEnt && !z.GFR_Crawl then
			local d = z:GetPos():DistToSqr(pos)
			if !bestD or d < bestD then best, bestD = z, d end
		end
	end
	return best
end

-- It reaches them: they die under it, it feeds, and they get up as one of the dead
local function Devour(ply, npc, rag, z, look)
	local group = npc.GFR_Group
	npc.GFR_UseCorpse = rag -- (the limp body is the corpse: sv_spawner.lua)
	rag.GFR_EatenBy = z
	npc:SetPos(GroundUnder(Pelvis(rag), {rag, npc})) -- (their gun and loot end up by the body)
	local wep = npc:GetActiveWeapon()
	if IsValid(wep) then wep:SetNoDraw(false) end
	rag:EmitSound("vj_gotdr/shared/melee/zombie_bite" .. math.random(1, 3) .. ".wav", 80)
	rag:EmitSound(look.model && string.find(string.lower(look.model), "female", 1, true) and "vo/npc/female01/pain0" .. math.random(1, 9) .. ".wav"
		or "vo/npc/male01/pain0" .. math.random(1, 9) .. ".wav", 80)
	local dmg = DamageInfo()
	dmg:SetDamage(npc:Health() + 200)
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetAttacker(z)
	dmg:SetInflictor(z)
	npc:TakeDamageInfo(dmg)
	-- Their friends saw who put them there
	if group && IsValid(ply) && GFR.Spawner && GFR.Spawner.Provoke then GFR.Spawner.Provoke(group, ply) end
	local function Feed()
		if !IsValid(z) or z.Dead then
			-- (it was put down before it got its meal: they still get back up as one of them)
			if IsValid(rag) && GFR.TurnBody then rag.GFR_EatenBy = nil rag.GFR_TurningBody = true GFR.TurnBody(rag, look, {runner = false}) end
			return
		end
		z:GFR_FeedOn(rag, FEED_TIME, function()
			if !IsValid(rag) or !GFR.TurnBody then return end
			rag.GFR_EatenBy = nil
			rag.GFR_TurningBody = true
			GFR.TurnBody(rag, look, {runner = false})
		end)
	end
	Feed()
end

function GFR.PushPerson(ply, npc)
	if !IsValid(npc) or IsValid(npc.GFR_LimpRag) or npc:Health() <= 0 then return end
	local dir = npc:GetPos() - ply:GetPos()
	dir.z = 0
	dir:Normalize()
	local look = LookOf(npc)
	local rag = MakeLimp(npc, look, dir * 260 + Vector(0, 0, 90))
	ply:ViewPunch(Angle(2, 0, 0))
	ply:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 70)
	if !IsValid(rag) then
		GFR.Say(npc, Line(pushedLines))
		return
	end
	GFR.Say(npc, Line(pushedLines))
	npc.GFR_LimpRag = rag
	HidePerson(npc, true)

	local z = FindEater(npc:GetPos())
	local started = CurTime()
	local id = "GFR_Limp" .. npc:EntIndex()
	timer.Create(id, 0.25, 0, function()
		if !IsValid(npc) or !IsValid(rag) or npc:Health() <= 0 then
			timer.Remove(id)
			if IsValid(rag) && rag.GFR_Limp && !(IsValid(npc) && npc.GFR_UseCorpse == rag) then rag:Remove() end
			return
		end
		local now = CurTime()
		if npc:GetMoveType() != MOVETYPE_NONE then npc:SetMoveType(MOVETYPE_NONE) end
		if (npc.GFR_NextFreeze or 0) < now then npc.GFR_NextFreeze = now + 1 npc:SetSchedule(SCHED_NPC_FREEZE) end
		-- One of the dead going for them
		if IsValid(z) && z:Health() > 0 && !z.Dead && !z.GFR_ScriptFeed && now - started < CATCH_TIME then
			local p = Pelvis(rag)
			if z:GetPos():DistToSqr(p) < 75 * 75 then
				timer.Remove(id)
				Devour(ply, npc, rag, z, look)
				return
			end
			if (z.GFR_NextLimpPath or 0) < now then
				z.GFR_NextLimpPath = now + 0.8
				z:SetEnemy(NULL)
				z:SetLastPosition(p)
				z:SCHEDULE_GOTO_POSITION("TASK_RUN_PATH")
			end
			return
		end
		-- Nothing got them: back on their feet
		if now - started >= LIMP_TIME then
			timer.Remove(id)
			GetUp(npc, rag)
		end
	end)
end

function GFR.GiveFoodTo(ply, npc)
	local inv = ply.GFR_Inv or {}
	local pick
	for i, e in ipairs(inv) do
		if GFR.ItemCategory && GFR.ItemCategory(e.class) == "food" && !e.contaminated && !string.StartWith(e.class, "meat_") then pick = i break end
	end
	if !pick then return false, "You've got nothing fit to eat." end
	GFR.InvTake(ply, pick, 1)
	local group = npc.GFR_Group
	if group then
		group.helped = group.helped or {}
		group.helped[ply] = true -- (one of them comes along for free now: sv_companions.lua)
	end
	npc:EmitSound("npc/barnacle/barnacle_crunch2.wav", 60)
	if math.random(3) == 1 && GFR.AddCaps then
		local caps = math.random(5, 20)
		GFR.AddCaps(ply, caps)
		return true, Line(thanksLines) .. " Here - it's not much.", caps
	end
	return true, Line(thanksLines)
end
