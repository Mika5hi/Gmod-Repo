--[[
	Custom Apocalypse - spawn director and human factions

	Keeps the world populated around the player, out of sight:
		Zombies   - Playermodel Zombies (random installed playermodels) plus some Ravenholm Grabbers
		Survivors - 1-3 people, pistols/SMGs/shotguns/old rifles. Neutral until you hurt one.
		Bandits   - 2-4 people, same kind of gear, hostile on sight.
		Military  - 3-5 soldiers, assault rifles/DMRs/MGs, armor, grenades, the best loot.
		            Friendly or neutral; they only turn on you if you shoot one of them.

	Humans are HL2 NPCs (npc_citizen / npc_combine_s for better tactics) carrying real ARC9 EFT guns,
	drawn as a random playermodel (gfr_bonemerge). Their gun drops when they die (press E to take it),
	their pockets use the faction's loot profile (sv_loot.lua) and they leave a playermodel corpse.
	Hurting any member turns that whole group hostile to you until you respawn.
]]

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled    = CreateConVar("gfr_spawn_enabled", "1", flags, "Enable the spawn director")
local cvZombies    = CreateConVar("gfr_zombie_count", "20", flags, "Zombies kept alive around the player")
local cvL4DRatio   = CreateConVar("gfr_zombie_l4d_ratio", "0.2", flags, "Share of zombies using Left 4 Dead infected models instead of playermodels (0-1)")
local cvGroups     = CreateConVar("gfr_human_groups", "3", flags, "Max human groups alive at once")
local cvGroupDelay = CreateConVar("gfr_human_group_delay", "60", flags, "Average seconds between new human groups")
local cvMilitary   = CreateConVar("gfr_military_chance", "5", flags, "% of human groups that are military")
local cvBandit     = CreateConVar("gfr_bandit_chance", "40", flags, "% of non-military groups that are hostile bandits")
local cvMilFriend  = CreateConVar("gfr_military_friendly_chance", "50", flags, "% of military groups that are friendly (the rest are neutral)")
local cvMinDist    = CreateConVar("gfr_spawn_mindist", "1500", flags, "Closest distance things spawn from the player")
local cvMaxDist    = CreateConVar("gfr_spawn_maxdist", "4500", flags, "Furthest distance things spawn from the player")
local cvDespawn    = CreateConVar("gfr_despawn_dist", "7000", flags, "Unseen NPCs further than this are recycled")
local cvCorpseTime = CreateConVar("gfr_corpse_time", "300", flags, "Seconds human corpses stay")
local cvNightMult  = CreateConVar("gfr_night_zombie_mult", "2", flags, "Zombie count multiplier at night")
local cvLocalShare = CreateConVar("gfr_zombie_local_share", "0.6", flags, "Share of the zombie count kept within spawn range of the player (0-1)")
local cvNightRunner = CreateConVar("gfr_night_runner_chance", "30", flags, "% of zombies that run at night (the rest walk)")
CreateConVar("gfr_day_runner_chance", "5", flags, "% of zombies that run by day (the rest walk)")

-- Performance pass: zombies, human groups, map loot, junk and kept bodies all halved, once (your saved values too)
if cookie.GetString("gfr_perf_half") != "1" then
	cookie.Set("gfr_perf_half", "1")
	timer.Simple(0, function()
		for _, name in ipairs({"gfr_zombie_count", "gfr_human_groups", "gfr_maploot_count", "gfr_maploot_junk", "gfr_body_max"}) do
			local cv = GetConVar(name)
			-- (a value already at the new default stays: that's a fresh config)
			if cv && cv:GetInt() > tonumber(cv:GetDefault()) then RunConsoleCommand(name, tostring(math.max(math.floor(cv:GetInt() / 2), 1))) end
		end
	end)
end
cookie.Set("gfr_spawn_v2", "1") -- (an older one-time move, superseded by the above)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Factions
local militaryGuns = {
	-- Weighted by repeats: mostly assault rifles, some SMGs/shotguns/DMRs, rare machine guns
	"arc9_eft_m4a1", "arc9_eft_m4a1", "arc9_eft_hk416", "arc9_eft_ak74m", "arc9_eft_ak74m", "arc9_eft_ak12", "arc9_eft_scarl",
	"arc9_eft_scarh", "arc9_eft_mcx", "arc9_eft_aug", "arc9_eft_g36", "arc9_eft_rpk16",
	"arc9_eft_mp7a1", "arc9_eft_mp5", "arc9_eft_m590", "arc9_eft_saiga12k",
	"arc9_eft_sr25", "arc9_eft_rsass", "arc9_eft_m1a", "arc9_eft_m60e4", "arc9_eft_pkm",
	-- ARC9 Modern Warfare 2019
	"arc9_cod2019_ar_m4", "arc9_cod2019_ar_m4", "arc9_cod2019_ar_m13", "arc9_cod2019_ar_kilo141", "arc9_cod2019_ar_grau556",
	"arc9_cod2019_ar_ram7", "arc9_cod2019_ar_scar", "arc9_cod2019_ar_fal", "arc9_cod2019_ar_an94", "arc9_cod2019_ar_famas",
	"arc9_cod2019_sm_mp7", "arc9_cod2019_sm_p90", "arc9_cod2019_sm_vector", "arc9_cod2019_sm_iso",
	"arc9_cod2019_sh_origin12", "arc9_cod2019_mm_m14", "arc9_cod2019_lm_sa86", "arc9_cod2019_lm_pkm"
}

local factions = {
	survivor = {
		name = "Survivor", base = "npc_citizen", baseModel = "models/humans/group01/male_07.mdl",
		health = {70, 100}, size = {1, 2}, prof = WEAPON_PROFICIENCY_AVERAGE, loot = "survivor",
		meleeChance = 0.4, mags = {1, 2}, -- scavengers: many only have a crowbar, the rest a mag or two
		weapons = {gun_pistol = 45, gun_smg = 20, gun_shotgun = 25, gun_rifle = 10}
	},
	bandit = {
		name = "Bandit", base = "npc_citizen", baseModel = "models/humans/group03/male_07.mdl",
		health = {80, 110}, size = {1, 2}, prof = WEAPON_PROFICIENCY_AVERAGE, loot = "bandit",
		meleeChance = 0.25, mags = {1, 3},
		weapons = {gun_pistol = 30, gun_smg = 25, gun_shotgun = 30, gun_rifle = 15}
	},
	military = {
		name = "Military", base = "npc_combine_s", baseModel = "models/combine_soldier.mdl",
		health = {140, 170}, size = {3, 5}, prof = WEAPON_PROFICIENCY_GOOD, loot = "military", grenades = 2,
		meleeChance = 0, -- well supplied (combine-based soldiers can't fight with melee, so their ammo isn't limited)
		weaponList = militaryGuns, military = true
	}
}

local militaryWords = {"soldier", "military", "army", "swat", "spetsnaz", "usmc", "marine", "pmc", "usec", "bear", "sas", "seal",
	"gign", "gsg", "ranger", "delta", "operator", "tactical", "riot", "urban", "gasmask", "police", "merc", "specops", "spec_ops"}
local skipWords = {"zombie", "corpse", "skeleton", "charple", "headcrab", "zombine", "combine", "metrocop", "kleiner", "gman", "breen", "monk", "eli", "odessa"}

local function HasWord(str, list)
	for _, w in ipairs(list) do
		if string.find(str, w, 1, true) then return true end
	end
	return false
end

local survivorModels, militaryModels
local function BuildModelLists()
	-- SFW mode (sh_sfw.lua): GMod's own playermodels only
	if GFR.SFW && GFR.SFW() then
		survivorModels, militaryModels = GFR.SFWModels("survivor"), GFR.SFWModels("military")
		return
	end
	survivorModels, militaryModels = {}, {}
	for _, mdl in pairs(player_manager.AllValidModels()) do
		local m = string.lower(mdl)
		if HasWord(m, militaryWords) then
			militaryModels[#militaryModels + 1] = mdl
		elseif !HasWord(m, skipWords) then
			survivorModels[#survivorModels + 1] = mdl
		end
	end
	-- GMod's own Counter-Strike playermodels as a military fallback
	if #militaryModels == 0 then
		for _, mdl in ipairs({"models/player/swat.mdl", "models/player/urban.mdl", "models/player/riot.mdl", "models/player/gasmask.mdl"}) do
			if util.IsValidModel(mdl) then militaryModels[#militaryModels + 1] = mdl end
		end
	end
end

-- Switching SFW mode takes effect for everyone spawned from then on
cvars.AddChangeCallback("gfr_sfw", function() if survivorModels then BuildModelLists() end end, "GFR_Spawner_SFW")

---------------------------------------------------------------------------------------------------------------------------------------------
-- Relationships
local humans = {}  -- [npc] = true
local groups = {}  -- list of {faction, squad, members, attitude, hostileTo}
local groupId = 0

local function PlayerDisposition(group, ply)
	-- Holding fire: a warning shout, a surrender in progress, or letting you go after a robbery
	if group.truce && (group.truce[ply] or 0) > CurTime() then return D_NU end
	if group.hostileTo[ply] then return D_HT end
	return group.attitude
end

local function NPCDisposition(a, b)
	local ga, gb = a.GFR_Group, b.GFR_Group
	if ga == gb then return D_LI end
	if ga.faction == "bandit" or gb.faction == "bandit" then
		return (ga.faction == gb.faction) and D_NU or D_HT
	end
	if ga.faction == gb.faction then return D_LI end
	return D_NU -- survivors and military leave each other alone
end

local function UpdateAttitudeNW(npc)
	local ply = player.GetAll()[1]
	npc:SetNW2Int("GFR_Disp", IsValid(ply) and PlayerDisposition(npc.GFR_Group, ply) or npc.GFR_Group.attitude)
end

local function ApplyRelations(npc)
	for _, ply in ipairs(player.GetAll()) do
		npc:AddEntityRelationship(ply, PlayerDisposition(npc.GFR_Group, ply), 99)
	end
	for other in pairs(humans) do
		if IsValid(other) && other != npc then
			local d = NPCDisposition(npc, other)
			npc:AddEntityRelationship(other, d, 50)
			other:AddEntityRelationship(npc, d, 50)
		end
	end
	for _, z in ipairs(ents.GetAll()) do
		if z:IsNPC() && GFR.IsZombie(z) then
			-- Their own experiments (sv_hunter.lua): the military and hunters leave each other alone
			if z.GFR_Hunter && npc.GFR_Group.faction == "military" && GFR.HunterTruce && !z.GFR_HunterBetrayed then
				GFR.HunterTruce(z, npc)
			else
				npc:AddEntityRelationship(z, D_HT, 80)
				z:AddEntityRelationship(npc, D_HT, 80)
			end
		end
	end
	UpdateAttitudeNW(npc)
end

-- New zombies hate every human and vice versa
hook.Add("OnEntityCreated", "GFR_Factions_ZombieRelations", function(ent)
	timer.Simple(0.1, function()
		if !IsValid(ent) or !ent:IsNPC() or !GFR.IsZombie(ent) then return end
		for npc in pairs(humans) do
			if IsValid(npc) && ent.GFR_Hunter && npc.GFR_Group && npc.GFR_Group.faction == "military" && GFR.HunterTruce then
				GFR.HunterTruce(ent, npc) -- (sv_hunter.lua)
			elseif IsValid(npc) then
				npc:AddEntityRelationship(ent, D_HT, 80)
				ent:AddEntityRelationship(npc, D_HT, 80)
			end
		end
	end)
end)

-- Hurt one, the whole group turns on you
local provokeMsg = {
	survivor = "The survivors turn on you!",
	military = "The military is now hostile to you!",
	bandit = nil
}
local function RefreshGroup(group)
	for _, m in ipairs(group.members) do
		if IsValid(m) then
			for _, ply in ipairs(player.GetAll()) do
				local d = PlayerDisposition(group, ply)
				m:AddEntityRelationship(ply, d, 99)
				if d == D_HT then m:UpdateEnemyMemory(ply, ply:GetPos()) end
			end
			UpdateAttitudeNW(m)
		end
	end
end

local function Provoke(group, attacker)
	if group.companion then return end -- your own people forgive a stray shot (sv_companions.lua)
	local inTruce = group.truce && (group.truce[attacker] or 0) > CurTime()
	if group.hostileTo[attacker] && !inTruce then return end
	if group.truce then group.truce[attacker] = nil end
	hook.Run("GFR_GroupProvoked", group, attacker)
	group.hostileTo[attacker] = true
	for _, m in ipairs(group.members) do
		if IsValid(m) then
			m:AddEntityRelationship(attacker, D_HT, 99)
			m:UpdateEnemyMemory(attacker, attacker:GetPos())
			UpdateAttitudeNW(m)
		end
	end
	if provokeMsg[group.faction] then GFR.Notify(attacker, provokeMsg[group.faction]) end
end

hook.Add("EntityTakeDamage", "GFR_Factions_Provoke", function(target, dmginfo)
	local group = target.GFR_Group
	local attacker = dmginfo:GetAttacker()
	if !group or !IsValid(attacker) or !attacker:IsPlayer() then return end
	Provoke(group, attacker)
end)

-- A new life: old grudges are forgotten
hook.Add("PlayerSpawn", "GFR_Factions_Forget", function(ply)
	timer.Simple(0.5, function()
		if !IsValid(ply) then return end
		for _, group in ipairs(groups) do
			group.hostileTo[ply] = nil
			for _, m in ipairs(group.members) do
				if IsValid(m) then
					m:AddEntityRelationship(ply, PlayerDisposition(group, ply), 99)
					UpdateAttitudeNW(m)
				end
			end
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Spawning humans
-- The HL2 NPC under the playermodel stays invisible. An invisible material as well as alpha: other addons "restore"
-- an NPC's visibility by resetting its colour/render mode (the L4D2 hunter does after letting go of a victim), which
-- would show the Combine soldier / citizen underneath.
local INVISIBLE = "models/effects/vol_light001"
local function HideBaseNPC(npc)
	npc:SetRenderMode(RENDERMODE_TRANSCOLOR)
	npc:SetColor(Color(255, 255, 255, 0))
	npc:SetMaterial(INVISIBLE)
	npc:DrawShadow(false)
	npc:SetNW2Bool("GFR_HideBase", true) -- (not drawn at all client side: sh_zombieplayer.lua)
end
GFR.HideBaseNPC = HideBaseNPC

-- ...and if something un-hides it anyway, hide it again
timer.Create("GFR_Factions_KeepHidden", 0.5, 0, function()
	for npc in pairs(humans) do
		if IsValid(npc) && IsValid(npc.GFR_Body) && (npc:GetMaterial() != INVISIBLE or npc:GetColor().a != 0) then HideBaseNPC(npc) end
	end
end)

local function AttachPlayermodel(npc, list)
	if !list or #list == 0 then return end
	for _ = 1, 6 do
		local mdl = list[math.random(#list)]
		local body = ents.Create("gfr_bonemerge")
		body:SetModel(mdl)
		body:SetPos(npc:GetPos())
		body:SetAngles(npc:GetAngles())
		body:SetParent(npc)
		body:Spawn()
		if body:LookupBone("ValveBiped.Bip01_Pelvis") then
			body:SetPlayerColor(Vector(math.Rand(0, 1), math.Rand(0, 1), math.Rand(0, 1)))
			body:SetSkin(math.random(0, math.max(body:SkinCount() - 1, 0)))
			for i = 0, body:GetNumBodyGroups() - 1 do
				body:SetBodygroup(i, math.random(0, math.max(body:GetBodygroupCount(i) - 1, 0)))
			end
			npc:DeleteOnRemove(body)
			HideBaseNPC(npc)
			npc.GFR_Body = body
			npc.GFR_PlayerModel = mdl
			npc:SetNW2Bool("GFR_PM", true)
			return body
		end
		body:Remove()
	end
end

-- Guns an NPC can actually hold: some packs flag theirs "not for NPCs" (most of ARC9 MW2019 inherits it from its base,
-- only some of its rifles turn it back off), and an NPC given one just ends up empty-handed
local function NPCUsable(class)
	local w = class && weapons.Get(class)
	return w && !w.NotForNPCs
end

-- If nothing usable turns up: the Half-Life 2 gun of the same kind
local fallbackGun = {gun_pistol = "weapon_pistol", gun_smg = "weapon_smg1", gun_shotgun = "weapon_shotgun", gun_rifle = "weapon_ar2"}

local function PickWeapon(f)
	if f.weaponList then
		for _ = 1, 15 do
			local class = f.weaponList[math.random(#f.weaponList)]
			if NPCUsable(class) then return class end
		end
		return "weapon_ar2"
	end
	local pool = GFR.Loot.PickPool(f.weapons)
	for _ = 1, 15 do
		local class = GFR.Loot.PickItem(pool)
		if NPCUsable(class) then return class end
	end
	return fallbackGun[pool] or "weapon_pistol"
end

local function SpawnHuman(group, pos, opts)
	opts = opts or {}
	local f = factions[group.faction]
	local npc = ents.Create(f.base)
	if !IsValid(npc) then return end
	npc:SetPos(pos)
	npc:SetAngles(Angle(0, math.random(0, 359), 0))
	npc:SetModel(f.baseModel)
	npc:SetKeyValue("squadname", group.squad)
	if f.base == "npc_citizen" then
		npc:SetKeyValue("citizentype", "4")
		npc:SetKeyValue("spawnflags", tostring(1048576)) -- not commandable by the player
	elseif f.grenades then
		npc:SetKeyValue("NumGrenades", tostring(f.grenades))
	end
	if f.base == "npc_combine_s" then
		-- No Half-Life 2 grenade / AR2 orb drops (their loot is ours, sv_loot.lua)
		npc:SetKeyValue("spawnflags", tostring(131072 + 262144))
	end
	npc:Spawn()
	npc:Activate()

	local hp = math.random(f.health[1], f.health[2])
	npc:SetMaxHealth(hp)
	npc:SetHealth(hp)

	-- Melee-only, or a gun with a few spare magazines (tracked by the ammo timer below)
	if !opts.noWeapon then
		if math.Rand(0, 1) < (f.meleeChance or 0) then
			npc.GFR_Weapon = npc:Give("weapon_crowbar")
		else
			local wepClass = PickWeapon(f)
			if wepClass then
				npc.GFR_Weapon = npc:Give(wepClass)
				if f.mags then npc.GFR_Mags = math.random(f.mags[1], f.mags[2]) end
			end
		end
		-- Still empty-handed a moment later (the gun refused an NPC owner and removed itself): a Half-Life 2 one instead
		timer.Simple(0.5, function()
			if !IsValid(npc) or npc:Health() <= 0 or IsValid(npc:GetActiveWeapon()) then return end
			npc.GFR_Weapon = npc:Give(f.military and "weapon_ar2" or "weapon_smg1")
		end)
	end
	npc:SetCurrentWeaponProficiency(f.prof)

	AttachPlayermodel(npc, f.military and militaryModels or survivorModels)

	npc.GFR_Group = group
	npc.GFR_LootProfile = f.loot
	npc.GFR_Helmet = f.military -- soldiers wear helmets: a headshot hurts, but doesn't drop them outright (sv_headshots.lua)
	npc:SetNW2String("GFR_Faction", group.faction)
	group.members[#group.members + 1] = npc
	humans[npc] = true
	ApplyRelations(npc)
	return npc
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Limited ammo: NPC reloads are free, so count them against GFR_Mags. Out of mags -> toss the gun, pull a crowbar.
local outLines = {"I'm out!", "Damn it, empty!", "No more ammo!", "Out of rounds!"}

local function OutOfAmmo(npc, wep)
	if GFR.Say then GFR.Say(npc, outLines[math.random(#outLines)]) end
	-- A companion keeps the gun slung and pulls a crowbar until you hand them ammo (sv_companions.lua)
	if npc.GFR_CompanionOf then
		npc.GFR_OutOfAmmo = true
		npc.GFR_Mags = 0
		npc.GFR_LastClip = nil
		if !npc:HasWeapon("weapon_crowbar") then npc:Give("weapon_crowbar") end
		npc:SelectWeapon("weapon_crowbar")
		if GFR.Notify && IsValid(npc.GFR_CompanionOf) then
			GFR.Notify(npc.GFR_CompanionOf, npc:GetNW2String("GFR_Name", "Your companion") .. " is out of ammo. Give them some (E on them).")
		end
		return
	end
	npc:DropWeapon(wep)
	timer.Simple(0, function()
		if IsValid(wep) && !IsValid(wep:GetOwner()) then
			wep.GFR_Loot = true
			wep:SetClip1(0)
		end
	end)
	npc.GFR_Mags = nil
	npc.GFR_LastClip = nil
	npc.GFR_Weapon = npc:Give("weapon_crowbar")
	npc:SelectWeapon("weapon_crowbar")
end

timer.Create("GFR_Factions_Ammo", 0.5, 0, function()
	for npc in pairs(humans) do
		-- skip the first second: ARC9 fills the clip in its NPC init, which would look like a reload
		if !IsValid(npc) or !npc.GFR_Mags or CurTime() - npc:GetCreationTime() < 1.5 then continue end
		local wep = npc:GetActiveWeapon()
		if !IsValid(wep) or wep != npc.GFR_Weapon then continue end
		local clip = wep:Clip1()
		local last = npc.GFR_LastClip
		if last && clip > last then -- reloaded
			if npc.GFR_Mags <= 0 then
				OutOfAmmo(npc, wep)
				continue
			end
			npc.GFR_Mags = npc.GFR_Mags - 1
		elseif clip <= 0 && npc.GFR_Mags <= 0 then
			OutOfAmmo(npc, wep)
			continue
		end
		npc.GFR_LastClip = clip
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Death: drop the gun as loot, leave a playermodel corpse
local function MakeCorpse(d)
	local rag = ents.Create("prop_ragdoll")
	if !IsValid(rag) then return end
	rag:SetModel(d.model)
	rag:SetPos(d.pos)
	rag:SetAngles(d.ang)
	rag:Spawn()
	rag:Activate()
	rag:SetSkin(d.skin)
	for i, v in pairs(d.bodygroups) do rag:SetBodygroup(i, v) end
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local b = d.bones[rag:GetBoneName(rag:TranslatePhysBoneToBone(i))]
		if IsValid(phys) && b then
			phys:SetPos(b[1])
			phys:SetAngles(b[2])
			phys:SetVelocity(d.vel)
		end
	end
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	rag.GFR_HumanCorpse = true
	if d.color then rag:SetNW2Vector("GFR_PlyColor", d.color) end -- (clothes colour: sh_zombieplayer.lua)
	-- Make sure it's seen: nothing (the hunter pack's held-victim clean-up passes, our hidden-NPC rules) may leave it
	-- invisible in the first moments
	for _, t in ipairs({0.1, 0.5, 1.2, 2.5}) do
		timer.Simple(t, function()
			if !IsValid(rag) then return end
			if rag:GetNoDraw() then rag:SetNoDraw(false) end
			if rag:GetMaterial() != "" then rag:SetMaterial("") end
			if rag:GetColor().a < 255 then rag:SetColor(color_white) end
			if rag:GetRenderMode() != RENDERMODE_NORMAL then rag:SetRenderMode(RENDERMODE_NORMAL) end
			if rag:GetNW2Bool("GFR_HideBase") then rag:SetNW2Bool("GFR_HideBase", false) end
			if rag:GetParent() != NULL then rag:SetParent(nil) end
		end)
	end
	timer.Simple(cvCorpseTime:GetFloat(), function()
		if IsValid(rag) then rag:Remove() end
	end)
	return rag
end

-- Killed by a hunter (the pack's, or one of ours: sv_hunter.lua)? Its victims come back as ordinary infected.
local function KilledByHunter(npc, attacker)
	local function IsHunter(e)
		return IsValid(e) && e:IsNPC() && (e.GFR_Hunter or string.find(e:GetClass(), "hunter", 1, true) != nil)
	end
	if IsHunter(attacker) then return true end
	local held = L4D2SI_SpecialVictims && L4D2SI_SpecialVictims[npc]
	return held && IsHunter(held.attacker) or false
end

hook.Add("OnNPCKilled", "GFR_Factions_Death", function(npc, attacker)
	if !npc.GFR_Group then return end
	local byHunter = KilledByHunter(npc, attacker)
	humans[npc] = nil

	local wep = npc.GFR_Weapon
	timer.Simple(0, function()
		if IsValid(wep) && !IsValid(wep:GetOwner()) then
			wep.GFR_Loot = true
			if wep:GetMaxClip1() > 0 then wep:SetClip1(math.random(0, wep:GetMaxClip1())) end
		end
	end)

	-- Already lying there limp (pushed, sv_actions.lua): that body is the corpse
	local limp = npc.GFR_UseCorpse
	if IsValid(limp) then
		limp.GFR_Limp = nil
		limp.GFR_HumanCorpse = true
		timer.Simple(cvCorpseTime:GetFloat(), function() if IsValid(limp) then limp:Remove() end end)
		return
	end

	local body = npc.GFR_Body
	if !npc.GFR_PlayerModel or !IsValid(body) then return end
	local d = {
		model = npc.GFR_PlayerModel, skin = body:GetSkin(), bodygroups = {}, bones = {},
		pos = npc:GetPos(), ang = npc:GetAngles(), vel = npc:GetVelocity()
	}
	for i = 0, body:GetNumBodyGroups() - 1 do d.bodygroups[i] = body:GetBodygroup(i) end
	-- Its pose at death, unless a hunter / charger / jockey had it held (L4D2 special infected pack): the pack hides and
	-- freezes the real NPC while it holds it, so its skeleton isn't where the body is - posing the corpse from it left
	-- a collapsed, invisible body (only its shadow showing). Those get the ragdoll's own pose, and stray bones are skipped.
	local held = npc.GFR_PinHidBody != nil or npc:GetNoDraw() or (L4D2SI_SpecialVictims && L4D2SI_SpecialVictims[npc] != nil)
	if !held then
		local center = npc:GetPos()
		for i = 0, npc:GetBoneCount() - 1 do
			local m = npc:GetBoneMatrix(i)
			if m && m:GetTranslation():DistToSqr(center) < 150 * 150 then d.bones[npc:GetBoneName(i)] = {m:GetTranslation(), m:GetAngles()} end
		end
	end
	d.color = body.GetPlayerColor and body:GetPlayerColor() or nil
	timer.Simple(0.05, function()
		-- Infected and rose as a zombie instead: no corpse
		if GFR.Loot && GFR.Loot.TurnedNearby(d.pos + Vector(0, 0, 36)) then return end
		local rag = MakeCorpse(d)
		-- A hunter's kill: it lies there, twitches, and gets up as an ordinary infected (a walker, wearing them) -
		-- never a hunter or any other special infected (sv_infection.lua GFR.TurnBody)
		if byHunter && IsValid(rag) && GFR.TurnBody then
			rag.GFR_TurningBody = true -- (zombies don't eat it, its head can be destroyed to keep it down: sv_rise.lua)
			GFR.TurnBody(rag, {model = d.model, skin = d.skin, bodygroups = d.bodygroups, color = d.color}, {runner = false})
		end
	end)
end)

-- The engine ragdoll would be the invisible base model; ours replaces it
hook.Add("CreateEntityRagdoll", "GFR_Factions_NoEngineRagdoll", function(owner, ragdoll)
	if IsValid(owner) && owner.GFR_PlayerModel then ragdoll:Remove() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Director
local zombies = {} -- [npc] = true, the ones we spawned

-- A spot something can appear at right now: the right distance from everyone, out of sight, not in a claimed base,
-- room to stand
local function SpotUsable(p, minD, maxD)
	local nearest, visible = math.huge, false
	for _, ply in ipairs(player.GetAll()) do
		local d = ply:GetPos():Distance(p)
		nearest = math.min(nearest, d)
		if d < 3500 && !util.TraceLine({start = ply:EyePos(), endpos = p + Vector(0, 0, 48), mask = MASK_VISIBLE}).Hit then
			visible = true
		end
	end
	-- (not inside anyone's claimed base, with a margin: sh_claim.lua)
	if nearest >= minD && nearest <= maxD && !visible && !(GFR.InClaim && GFR.InClaim(p, 250)) then
		local hull = util.TraceHull({start = p + Vector(0, 0, 4), endpos = p + Vector(0, 0, 8), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_NPCSOLID})
		return !hull.Hit
	end
	return false
end

local function FindSpawnSpot(minD, maxD)
	local cands = GFR.Loot && GFR.Loot.GetCandidates() or {}
	if #cands == 0 then return end
	for _ = 1, 30 do
		local p = GFR.Loot.GroundSpot(cands[math.random(#cands)])
		if p && SpotUsable(p, minD, maxD) then return p end
	end
end

-- Points placed with the Spawn Points tool (lua/autorun/gfr_spawnpoints.lua), used on top of the random spots: about
-- half the time one of them is tried first. kinds: list of point kinds; returns the spot and which kind it was.
-- With gfr_spawnpoints_only (and points of these kinds on the map) they're the only spots: always tried, harder
-- (PlacedOnly: the caller doesn't fall back to random spots).
local PLACED_SHARE = 0.5
local function PlacedOnly(kinds) return GFR_SP && GFR_SP.Only && GFR_SP.Only(kinds) end

local function PlacedSpot(kinds, minD, maxD)
	if !GFR_SP then return end
	local only = PlacedOnly(kinds)
	if !only && math.Rand(0, 1) >= PLACED_SHARE then return end
	local list = {}
	for _, kind in ipairs(kinds) do
		for _, pos in ipairs(GFR_SP.Get(kind)) do list[#list + 1] = {pos = pos, kind = kind} end
	end
	for _ = 1, math.min(#list, only and 25 or 10) do
		local e = list[math.random(#list)]
		local p = (GFR.Loot && GFR.Loot.GroundSpot(e.pos)) or e.pos
		if SpotUsable(p, minD, maxD) then return p, e.kind end
	end
end

-- Pick the best of a few valid spots: the one furthest from the zombies already out there, so they spread over the map
local function FindSpreadSpot(minD, maxD)
	local best, bestGap
	for _ = 1, 6 do
		local p = FindSpawnSpot(minD, maxD)
		if p then
			local gap = math.huge
			for z in pairs(zombies) do
				if IsValid(z) then gap = math.min(gap, z:GetPos():DistToSqr(p)) end
			end
			if !best or gap > bestGap then best, bestGap = p, gap end
		end
	end
	return best
end

local function FreeSpotNear(pos)
	for _ = 1, 8 do
		local p = pos + Vector(math.Rand(-90, 90), math.Rand(-90, 90), 0)
		local down = util.TraceLine({start = p + Vector(0, 0, 40), endpos = p - Vector(0, 0, 100), mask = MASK_NPCSOLID_BRUSHONLY})
		if down.Hit then
			local hull = util.TraceHull({start = down.HitPos + Vector(0, 0, 4), endpos = down.HitPos + Vector(0, 0, 8), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_NPCSOLID})
			if !hull.Hit then return down.HitPos end
		end
	end
end

-- Zombies made elsewhere (risen corpses, sv_rise.lua) count toward the population and get recycled like the rest
function GFR.TrackZombie(z)
	if IsValid(z) then zombies[z] = true end
end

local spawnFails = 0

-- nearPlayer: refill around the player (the area you're in got cleared) instead of spreading over the whole map
local function SpawnZombie(atPos, nearPlayer)
	local pos = atPos
	if !pos then
		local minD, maxD = cvMinDist:GetFloat(), cvMaxDist:GetFloat()
		pos = PlacedSpot({"zombie"}, minD, maxD)
		if pos or PlacedOnly({"zombie"}) then
			-- (one of your zombie points; or only those, and none usable right now: none this time)
		elseif nearPlayer then
			pos = FindSpawnSpot(minD, math.max(minD + 500, maxD * 0.65)) or FindSpawnSpot(minD * 0.7, maxD)
		else
			pos = FindSpreadSpot(minD, maxD)
		end
	end
	if !pos then spawnFails = spawnFails + 1 return false end
	-- The infected (L4D-based, sv_infection.lua GFR.InfectedClass), now and then a bloater (boomer, sv_parasite.lua)
	local bloater = GFR.RollBloater && GFR.RollBloater()
	local class = bloater and GFR.BloaterClass() or GFR.InfectedClass()
	if !scripted_ents.GetStored(class) then return false end
	local z = ents.Create(class)
	if !IsValid(z) then return false end
	z:SetPos(pos)
	z:SetAngles(Angle(0, math.random(0, 359), 0))
	-- Most of the dead were people like you: a random playermodel worn on the infected's skeleton (npc_gfr_infected)
	local pm
	if !bloater && class == "npc_gfr_infected" && !(GFR.SFW && GFR.SFW()) && math.Rand(0, 1) >= cvL4DRatio:GetFloat() then
		if !survivorModels then BuildModelLists() end
		local list = (math.random(10) == 1 && #militaryModels > 0) and militaryModels or survivorModels
		pm = #list > 0 && list[math.random(#list)]
		if pm then
			z.GFR_ForceModel = pm
			z.GFR_ForceColor = Vector(math.Rand(0.05, 0.45), math.Rand(0.05, 0.45), math.Rand(0.05, 0.45))
		end
	end
	z:Spawn()
	z:Activate()
	-- Random outfit, like the living (AttachPlayermodel)
	local body = pm && IsValid(z.Bonemerge) && z.Bonemerge
	if body then
		body:SetSkin(math.random(0, math.max(body:SkinCount() - 1, 0)))
		for i = 0, body:GetNumBodyGroups() - 1 do
			body:SetBodygroup(i, math.random(0, math.max(body:GetBodygroupCount(i) - 1, 0)))
		end
	end
	zombies[z] = true
	if bloater then
		GFR.SetupSpawnedBloater(z)
	elseif GFR.MaybeParasiteHost then
		GFR.MaybeParasiteHost(z) -- a few carry a parasite (sv_parasite.lua)
	end
	return z
end

-- opts (quests): size, attitude, keep (never recycled), noWeapon, minDist, maxDist
local function SpawnGroup(forced, nearPos, opts)
	opts = opts or {}
	local minD, maxD = opts.minDist or cvMinDist:GetFloat(), opts.maxDist or cvMaxDist:GetFloat()
	local pos, placedKind = nearPos, nil
	-- One of your survivor / bandit / military points: that faction turns up there
	if !pos && !forced then
		pos, placedKind = PlacedSpot({"survivor", "bandit", "military"}, minD, maxD)
		if !pos && PlacedOnly({"survivor", "bandit", "military"}) then return end -- (only the placed ones: none usable now)
	end
	pos = pos or FindSpawnSpot(minD, maxD)
	if !pos then return end
	local faction = factions[forced or ""] && forced
	if faction then
		-- forced (debug command)
	elseif placedKind && factions[placedKind] then
		faction = placedKind
	elseif math.Rand(0, 100) < cvMilitary:GetFloat() then
		faction = "military"
	else
		faction = math.Rand(0, 100) < cvBandit:GetFloat() and "bandit" or "survivor"
	end
	local attitude = D_NU
	if faction == "bandit" then attitude = D_HT
	elseif faction == "military" && math.Rand(0, 100) < cvMilFriend:GetFloat() then attitude = D_LI end
	if opts.attitude then attitude = opts.attitude end

	groupId = groupId + 1
	local group = {faction = faction, squad = "gfr_group_" .. groupId, members = {}, attitude = attitude, hostileTo = {}, truce = {}, keep = opts.keep}
	groups[#groups + 1] = group

	local f = factions[faction]
	for i = 1, opts.size or math.random(f.size[1], f.size[2]) do
		local p = (i == 1) and pos or FreeSpotNear(pos)
		if p then SpawnHuman(group, p + Vector(0, 0, 4), opts) end
	end
	return group
end

local function NearestPlayerDist(pos)
	local best = math.huge
	for _, ply in ipairs(player.GetAll()) do best = math.min(best, ply:GetPos():Distance(pos)) end
	return best
end

local function SeenByAnyone(ent)
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(ent:GetPos()) < 3500 * 3500 && !util.TraceLine({start = ply:EyePos(), endpos = ent:WorldSpaceCenter(), mask = MASK_VISIBLE}).Hit then
			return true
		end
	end
	return false
end

local nextGroupT = 0

timer.Create("GFR_Director", 4, 0, function()
	if !cvEnabled:GetBool() or #player.GetAll() == 0 then return end
	if !survivorModels then BuildModelLists() end

	-- Recycle far-away, unseen NPCs so the population follows the player
	local despawn = cvDespawn:GetFloat()
	local zCount = 0
	for z in pairs(zombies) do
		if !IsValid(z) or z:Health() <= 0 then
			zombies[z] = nil
		elseif NearestPlayerDist(z:GetPos()) > despawn && !SeenByAnyone(z) then
			z:Remove()
			zombies[z] = nil
		else
			zCount = zCount + 1
		end
	end
	for i = #groups, 1, -1 do
		local g, alive = groups[i], 0
		for j = #g.members, 1, -1 do
			local m = g.members[j]
			if !g.keep && IsValid(m) && m:Health() > 0 && NearestPlayerDist(m:GetPos()) > despawn && !SeenByAnyone(m) then
				humans[m] = nil
				m:Remove()
			end
			if IsValid(m) && m:Health() > 0 then alive = alive + 1 end
		end
		if alive == 0 then table.remove(groups, i) end
	end

	-- Top up zombies a few at a time. Most of them belong around the player: if the area you're in has been
	-- cleared, refills come in there (just out of sight); otherwise they spread over the map.
	local made = 0
	local target = cvZombies:GetInt()
	if GFR.IsNight && GFR.IsNight() then target = math.Round(target * cvNightMult:GetFloat()) end
	local localRange = cvMaxDist:GetFloat()
	local nearCount = 0
	for z in pairs(zombies) do
		if IsValid(z) && NearestPlayerDist(z:GetPos()) <= localRange then nearCount = nearCount + 1 end
	end
	local nearTarget = math.ceil(target * cvLocalShare:GetFloat())
	-- Too few near you but the map's "full": recycle the furthest unseen ones so they can come back nearby
	if zCount >= target && nearCount < nearTarget then
		local far = {}
		for z in pairs(zombies) do
			if IsValid(z) && !z.GFR_Gear && !z.GFR_ControlPlayer then
				local d = NearestPlayerDist(z:GetPos())
				if d > localRange * 1.2 && !SeenByAnyone(z) then far[#far + 1] = {z, d} end
			end
		end
		table.sort(far, function(a, b) return a[2] > b[2] end)
		for i = 1, math.min(3, #far, nearTarget - nearCount) do
			zombies[far[i][1]] = nil
			far[i][1]:Remove()
			zCount = zCount - 1
		end
	end
	while zCount < target && made < 4 do
		local near = nearCount < nearTarget
		if !SpawnZombie(nil, near) then break end
		zCount, made = zCount + 1, made + 1
		if near then nearCount = nearCount + 1 end
	end

	-- A new group now and then
	if #groups < cvGroups:GetInt() && CurTime() > nextGroupT then
		SpawnGroup()
		nextGroupT = CurTime() + cvGroupDelay:GetFloat() * math.Rand(0.6, 1.4)
	end
end)

-- How the population looks right now (and whether spawn spots are being found)
concommand.Add("gfr_spawn_status", function(ply)
	if IsValid(ply) && !ply:IsSuperAdmin() then return end
	local total, near = 0, 0
	for z in pairs(zombies) do
		if IsValid(z) && z:Health() > 0 then
			total = total + 1
			if NearestPlayerDist(z:GetPos()) <= cvMaxDist:GetFloat() then near = near + 1 end
		end
	end
	local target = cvZombies:GetInt()
	if GFR.IsNight && GFR.IsNight() then target = math.Round(target * cvNightMult:GetFloat()) end
	local cands = GFR.Loot && GFR.Loot.GetCandidates() or {}
	local msg = string.format("[GFR] Zombies: %d / %d (%d within %d of you, want %d). Spawn points: %d. Failed spawn attempts: %d. Human groups: %d",
		total, target, near, cvMaxDist:GetInt(), math.ceil(target * cvLocalShare:GetFloat()), #cands, spawnFails, #groups)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) ply:ChatPrint(msg) else print(msg) end
end)

hook.Add("InitPostEntity", "GFR_Director_Start", function()
	nextGroupT = CurTime() + 30
end)

-- Half-Life 2 NPCs drop HL2 pickups when they die (Combine soldiers: health vials and grenades, others ammo).
-- Those don't belong here: anything like that appearing where a person just died is removed. Their real loot
-- (their gun, their pockets) is ours.
local hl2Drops = {
	item_healthvial = true, item_healthkit = true, item_battery = true, weapon_frag = true, item_ammo_ar2_altfire = true,
	item_ammo_pistol = true, item_ammo_smg1 = true, item_ammo_ar2 = true, item_box_buckshot = true, item_ammo_357 = true,
	item_ammo_crossbow = true, item_rpg_round = true, item_ammo_smg1_grenade = true, item_ammo_pistol_large = true,
	item_ammo_smg1_large = true, item_ammo_ar2_large = true, item_ammo_357_large = true
}

hook.Add("OnNPCKilled", "GFR_Spawner_NoHL2Drops", function(npc)
	local pos = npc:GetPos()
	local function Sweep()
		for _, ent in ipairs(ents.FindInSphere(pos, 160)) do
			if hl2Drops[ent:GetClass()] && !ent.GFR_Loot && !IsValid(ent:GetOwner()) && ent:GetCreationTime() > CurTime() - 2 then
				ent:Remove()
			end
		end
	end
	timer.Simple(0, Sweep)
	timer.Simple(0.5, Sweep)
end)

-- Used by sv_surrender.lua and sv_npc.lua
GFR.Spawner = {
	Groups = function() return groups end,
	SpawnGroup = function(...)
		if !survivorModels then BuildModelLists() end
		return SpawnGroup(...)
	end,
	SpawnZombie = SpawnZombie,
	FindSpawnSpot = FindSpawnSpot,
	PlayerDisposition = PlayerDisposition,
	RefreshGroup = RefreshGroup,
	Provoke = Provoke,
	Humans = function() return humans end,
	JoinGroup = function(npc, group)
		local old = npc.GFR_Group
		if old then table.RemoveByValue(old.members, npc) end
		npc.GFR_Group = group
		npc:SetKeyValue("squadname", group.squad)
		npc:SetNW2String("GFR_Faction", group.faction)
		group.members[#group.members + 1] = npc
		ApplyRelations(npc)
	end
}

-- Testing: gfr_spawn_group [military|bandit|survivor] spawns a group where you're looking
-- gfr_spawn_group <survivor|bandit|military|army> [size]
local groupAliases = {army = "military", soldier = "military", soldiers = "military", survivors = "survivor", bandits = "bandit"}
concommand.Add("gfr_spawn_group", function(ply, _, args)
	if !IsValid(ply) or !GFR.CanCheat(ply) then return end
	if !survivorModels then BuildModelLists() end
	local faction = string.lower(args[1] or "")
	faction = groupAliases[faction] or faction
	local size = tonumber(args[2] or "")
	local g = SpawnGroup(factions[faction] and faction or nil, ply:GetEyeTrace().HitPos, size and {size = math.Clamp(math.floor(size), 1, 20)} or nil)
	if g then ply:PrintMessage(HUD_PRINTCONSOLE, string.format("[GFR] Spawned %d %s", #g.members, g.faction)) end
end, function(cmd) return {cmd .. " survivor 3", cmd .. " bandit 3", cmd .. " military 3"} end, "Spawn a human group where you look: gfr_spawn_group <survivor|bandit|military> [how many, 1-20]")

-- gfr_spawn_zombie [count]: zombies where you look (counted in the population like any other)
concommand.Add("gfr_spawn_zombie", function(ply, _, args)
	if !IsValid(ply) or !GFR.CanCheat(ply) then return end
	local pos = ply:GetEyeTrace().HitPos
	local n = math.Clamp(math.floor(tonumber(args[1] or "") or 1), 1, 30)
	for i = 1, n do
		local p = i == 1 and pos or (FreeSpotNear(pos) or pos)
		SpawnZombie(p + Vector(0, 0, 4))
	end
end, nil, "Spawn zombies where you look: gfr_spawn_zombie [count]")
