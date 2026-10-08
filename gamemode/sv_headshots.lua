--[[
	Custom Apocalypse - headshots
	A bullet to the head has a chance to blow it apart - an instant kill - and the bigger the round, the better the
	chance: 5% pistol, 10% SMG, 20% 5.45/5.56, 30% 7.62, 50% magnum handgun, 100% .338/12.7 sniper, 5% a shotgun
	pellet (GFR.HeadPopChance, by the round the gun fires: popByAmmo; unknown rounds by damage: popTiers).
	Only a popped head (or a heavy blade) shows the head blown apart; killed by an ordinary headshot, it keeps it. Shotgun pellets count for half each, but a close blast puts several
	in. A headshot that doesn't pop it still hurts badly (the base game doubles head damage).
	Helmets (npc.GFR_Helmet: soldiers) stop the instant kill: heavy damage instead.
	Killed by a hit to the head either way, a zombie stays down (sv_rise.lua). Downed bodies use the same chance.
	Melee and heads: sv_rise.lua.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_headshot_kills", "1", flags, "Bullet headshots can blow the head apart (instant kill), more likely with bigger rounds")

-- The chance by the bullet's damage: {up to this damage, % chance}. Above the last: always.
local popTiers = {
	{25, 5},   -- weak pistol rounds
	{35, 10},  -- strong pistol / SMG
	{45, 20},  -- intermediate rifle (5.45 / 5.56)
	{55, 30},  -- full-power rifle (7.62)
	{79, 50},  -- heavy rifle / magnum
	-- 80+: 100 (snipers, .50)
}

-- A head hit that doesn't blow it apart does at most this much of a full-health target's health, so it never kills in
-- one shot on its own: ARC9 multiplies head hits by 2.5 (x the gun's own headshot bonus) and the base game doubles
-- them again, which made every headshot a kill anyway
local cvCap = CreateConVar("gfr_headshot_cap", "0.6", flags, "Most of a full-health target's health a headshot that doesn't pop the head can take (0-1)")

local bodyCancel = GetConVar("arc9_mod_bodydamagecancel")

-- The bullet's own damage, before anything multiplied it for hitting the head (ARC9's BodyDamageMults x HeadshotDamage,
-- and its "cancel the base game's x2" division) - what the tiers below are about
local function RawDamage(dmginfo, head)
	local dmg = dmginfo:GetDamage()
	if !head then return dmg end
	local inf, att = dmginfo:GetInflictor(), dmginfo:GetAttacker()
	local wep = (IsValid(inf) && inf:IsWeapon() && inf) or (IsValid(att) && att.GetActiveWeapon && att:GetActiveWeapon()) or nil
	if !IsValid(wep) or !wep.ARC9 or !wep.GetProcessedValue then return dmg end
	local mults = wep:GetProcessedValue("BodyDamageMults", true)
	local mult = (istable(mults) && mults[HITGROUP_HEAD] or 1) * (wep:GetProcessedValue("HeadshotDamage", true) or 1)
	bodyCancel = bodyCancel or GetConVar("arc9_mod_bodydamagecancel")
	if bodyCancel && bodyCancel:GetBool() then mult = mult / 2 end
	return dmg / math.max(mult, 0.1)
end

-- By the round the gun fires (its ammo pool, sh_ammo.lua) - damage numbers differ too much between gun packs (the EFT
-- guns' 9mm hits as hard as a rifle round) to tell calibers apart. Pistol & magnum rounds: handguns get the lower %.
local popByAmmo = {
	pistol = {5, 10},    -- 9mm / .45 / 5.7: handgun 5, SMG 10
	smg1 = 20,           -- 5.45 / 5.56
	ar2 = 30,            -- 7.62
	["357"] = {50, 100}, -- .357 / .50 AE handgun 50, .338 / 12.7 rifle 100
	buckshot = 5,        -- per pellet
	xbowbolt = 50,
	sniperpenetratedround = 100, sniperround = 100
}

local function BulletWeapon(dmginfo)
	local inf, att = dmginfo:GetInflictor(), dmginfo:GetAttacker()
	if IsValid(inf) && inf:IsWeapon() then return inf end
	if IsValid(att) && att.GetActiveWeapon then
		local w = att:GetActiveWeapon()
		if IsValid(w) then return w end
	end
end

-- 0-1: the chance this bullet blows a head apart (head: it's an engine head hit, multiplied up by the gun)
function GFR.HeadPopChance(dmginfo, head)
	if !cvEnabled:GetBool() then return 0 end
	local chance
	local w = BulletWeapon(dmginfo)
	local ammoId = IsValid(w) && w.GetPrimaryAmmoType && w:GetPrimaryAmmoType() or -1
	local tier = ammoId >= 0 && popByAmmo[string.lower(game.GetAmmoName(ammoId) or "")]
	if istable(tier) then
		local handgun = GFR.SlotOfClass && GFR.SlotOfClass(w:GetClass()) == "secondary"
		chance = (handgun and tier[1] or tier[2]) / 100
	elseif tier then
		chance = tier / 100
	else
		-- (a round we don't know: by its damage)
		local dmg = RawDamage(dmginfo, head)
		chance = 1
		for _, t in ipairs(popTiers) do
			if dmg <= t[1] then chance = t[2] / 100 break end
		end
		if dmginfo:IsDamageType(DMG_BUCKSHOT) then chance = chance * 0.5 end -- (one pellet of many)
	end
	return chance
end

local function Burst(npc)
	if GFR.Gore && !GFR.Gore() then return end -- (gfr_infected_gore 0)
	local id = npc:LookupBone("ValveBiped.Bip01_Head1")
	local pos = id && npc:GetBonePosition(id) or npc:EyePos()
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetScale(6)
	fx:SetFlags(3)
	fx:SetColor(0)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	sound.Play("physics/flesh/flesh_bloody_break.wav", pos, 75, math.random(90, 105))
end

hook.Add("ScaleNPCDamage", "GFR_Headshots", function(npc, hitgroup, dmginfo)
	if hitgroup != HITGROUP_HEAD or !cvEnabled:GetBool() or !dmginfo:IsBulletDamage() then return end
	if npc:Health() <= 0 or !npc:LookupBone("ValveBiped.Bip01_Head1") then return end -- only things with a human head
	if !GFR.IsZombie(npc) && npc.GFR_Helmet then
		dmginfo:ScaleDamage(1.5)
		return
	end
	if math.Rand(0, 1) < GFR.HeadPopChance(dmginfo, true) then
		npc.GFR_HeadPopped = true
		dmginfo:SetDamage(npc:Health() + 100)
		Burst(npc)
		return
	end
	-- Otherwise a bad wound, not a kill on its own: capped (the base game doubles it after this, hence the / 2)
	local most = npc:GetMaxHealth() * math.Clamp(cvCap:GetFloat(), 0, 1)
	if dmginfo:GetDamage() * 2 > most then dmginfo:SetDamage(most / 2) end
end)
