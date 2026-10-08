--[[
	Custom Apocalypse - weapons
	Spawn with fists only; everything else is looted.
	Looted weapons (GFR_Loot) are picked up with E instead of by walking over them.
	If you already have that gun, pressing E strips the rounds out of it instead.
]]

function GM:PlayerLoadout(ply)
	ply:RemoveAllAmmo()
	local fists = GFR.Fists()
	ply:Give(fists)
	ply:SelectWeapon(fists)
	return true
end

hook.Add("PlayerCanPickupWeapon", "GFR_Weapons_PressE", function(ply, wep)
	-- Our own unarmed weapon is always allowed (other addons' pickup rules would otherwise block the loadout)
	if GFR.IsFists(wep:GetClass()) && !wep.GFR_Loot then return true end
	if wep.GFR_Loot && wep.GFR_PickupBy != ply then return false end
end)

-- Safety net: the loadout can miss (first spawn before ARC9 is ready, another addon stripping weapons).
-- Anyone alive and human without fists gets them back, falling back to GMod's fists if MW2019's won't stick.
local function EnsureFists(ply)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_IsZombie or ply.VJ_IsControllingNPC then return end
	if ply:HasWeapon("arc9_cod2019_me_fist") or ply:HasWeapon("weapon_fists") then return end
	local fists = GFR.Fists()
	ply:Give(fists)
	if !ply:HasWeapon(fists) then
		print("[Green Flu: Reimagined] Couldn't give " .. fists .. " to " .. ply:Nick() .. ", using weapon_fists")
		fists = "weapon_fists"
		ply:Give(fists)
	end
	if !IsValid(ply:GetActiveWeapon()) then ply:SelectWeapon(fists) end
end

hook.Add("PlayerSpawn", "GFR_Weapons_EnsureFists", function(ply)
	timer.Simple(0.5, function() EnsureFists(ply) end)
	timer.Simple(2, function() EnsureFists(ply) end)
end)

timer.Create("GFR_Weapons_EnsureFists", 3, 0, function()
	for _, ply in ipairs(player.GetAll()) do EnsureFists(ply) end
end)

-- Bare fists hit too hard for an apocalypse: half damage (gfr_fist_damage_mult)
local cvFistMult = CreateConVar("gfr_fist_damage_mult", "0.5", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Damage multiplier for punches")
hook.Add("EntityTakeDamage", "GFR_Fists_Damage", function(target, dmg)
	local att = dmg:GetAttacker()
	if !IsValid(att) or !att:IsPlayer() or dmg:IsBulletDamage() then return end
	local w = att:GetActiveWeapon()
	if IsValid(w) && GFR.IsFists(w:GetClass()) then dmg:ScaleDamage(cvFistMult:GetFloat()) end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Weapon slots (sh_equipment.lua): one primary, one secondary, one melee, one throwable.
-- The loot pools know what each gun is better than its name does, so they win over the guesswork.
util.AddNetworkString("GFR_WepAction")

local poolSlot = {gun_pistol = "secondary", gun_smg = "primary", gun_shotgun = "primary", gun_rifle = "primary",
	gun_military = "primary", gun_rare = "primary", melee = "melee", grenade = "throwable"}

function GFR.SlotOfClass(class)
	if GFR.Loot && GFR.Loot.GunPools then
		for pool, list in pairs(GFR.Loot.AllPools or {}) do
			if poolSlot[pool] && table.HasValue(list, class) then return poolSlot[pool] end
		end
	end
	return GFR.WeaponSlot(class)
end

local function SlotOf(wep)
	return GFR.SlotOfClass(wep:GetClass())
end
GFR.SlotOfWeapon = SlotOf

-- Drop it in front of you; it keeps the rounds in its magazine and is picked back up with E
-- Throwables and one-use items: no magazine (what's left is your ammo of its type), or an ARC9 throwable (it throws
-- from its magazine, refilled from that ammo)
local function OneUse(wep)
	if wep.ARC9 && wep.GetProcessedValue && wep:GetProcessedValue("Throwable", true) then return true end
	return wep:GetMaxClip1() <= 0
end
local function UsesLeft(ply, wep)
	local at = wep:GetPrimaryAmmoType()
	return math.max(wep:Clip1(), 0) + (at >= 0 and ply:GetAmmoCount(at) or 0)
end

-- A throwable / one-use item with nothing left: there's nothing to put down or away - it's just gone (put back as a
-- whole one, it would come with a fresh use: GFR_OneUseAmmo below)
function GFR.SpentOneUse(ply, wep)
	if !OneUse(wep) or wep:GetPrimaryAmmoType() < 0 or UsesLeft(ply, wep) > 0 then return false end
	if ply:GetActiveWeapon() == wep then ply:SelectWeapon(GFR.Fists()) end
	ply:StripWeapon(wep:GetClass())
	return true
end

function GFR.DropPlayerWeapon(ply, wep)
	if !IsValid(wep) or wep:GetOwner() != ply then return end
	if GFR.SpentOneUse(ply, wep) then return end
	if ply:GetActiveWeapon() == wep then ply:SelectWeapon(GFR.Fists()) end
	ply:DropWeapon(wep, nil, ply:GetAimVector() * 160 + Vector(0, 0, 60))
	wep.GFR_Loot = true
	wep.GFR_PickupBy = nil
end

-- Took a weapon some other way (crafted, from pockets, a trader, your belongings bag...) while that slot was already
-- full: the new one goes into your bag instead (or onto the ground if the bag is full)
hook.Add("WeaponEquip", "GFR_Weapons_Slots", function(wep, ply)
	timer.Simple(0, function()
		if !IsValid(wep) or !IsValid(ply) or !ply:IsPlayer() or wep:GetOwner() != ply or ply.GFR_IsZombie then return end
		local slot = SlotOf(wep)
		wep:SetNW2String("GFR_WSlot", slot or "")
		if !slot then return end
		for _, other in ipairs(ply:GetWeapons()) do
			if other != wep && (other:GetNW2String("GFR_WSlot", "") != "" and other:GetNW2String("GFR_WSlot") or SlotOf(other)) == slot then
				local name = wep.GetPrintName && wep:GetPrintName() or wep:GetClass()
				if GFR.StashWeapon && GFR.StashWeapon(ply, wep) then
					GFR.Notify(ply, name .. " went into your bag (your " .. slot .. " slot is in use).")
				else
					GFR.DropPlayerWeapon(ply, wep)
					GFR.Notify(ply, "Your " .. slot .. " slot and bag are full - dropped the " .. name .. ".")
				end
				return
			end
		end
	end)
end)

-- From the inventory screen: draw a weapon, or drop it
net.Receive("GFR_WepAction", function(_, ply)
	local action = net.ReadString()
	local wep = net.ReadEntity()
	if !IsValid(ply) or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied or !IsValid(wep) or wep:GetOwner() != ply then return end
	if action == "select" then
		ply:SelectWeapon(wep:GetClass())
	elseif action == "drop" && !GFR.IsFists(wep:GetClass()) then
		GFR.DropPlayerWeapon(ply, wep)
	elseif action == "stash" && !GFR.IsFists(wep:GetClass()) then
		GFR.StashWeapon(ply, wep)
	end
end)

-- A throwable / flare / one-use item has no magazine: what it has left is its ammo. One picked up (or taken out of the
-- bag) came with none of it - 0 / 0, couldn't be used. It comes with one.
hook.Add("WeaponEquip", "GFR_OneUseAmmo", function(wep, ply)
	timer.Simple(0, function()
		if !IsValid(wep) or !IsValid(ply) or wep:GetOwner() != ply then return end
		local at = wep:GetPrimaryAmmoType()
		if !OneUse(wep) or at < 0 or UsesLeft(ply, wep) > 0 then return end
		-- (ARC9 throwables throw from the magazine: one in it; otherwise one of its ammo)
		if wep:GetMaxClip1() > 0 then wep:SetClip1(1) else ply:GiveAmmo(1, at, true) end
	end)
end)

-- E on a looted weapon (the one under the crosshair is picked by sh_pickup.lua)
function GFR.PickupLootWeapon(ply, wep)
	if !IsValid(wep) or !wep.GFR_Loot or IsValid(wep:GetOwner()) then return end
	local name = wep.GetPrintName && wep:GetPrintName() or wep:GetClass()

	-- A STALKER 2 / SCP consumable lying around: it's an inventory item (sv_consumables.lua)
	local item = GFR.ConsumableForSwep && GFR.ConsumableForSwep(wep:GetClass())
	if item then
		if GFR.InvAdd(ply, item, 1, false, GFR.CustomItems[item].model) == 0 then
			GFR.Notify(ply, "You can't carry any more.")
			return
		end
		ply:EmitSound("items/itempickup.wav", 60)
		wep:Remove()
		GFR.Notify(ply, "+ " .. GFR.CustomItems[item].name)
		return
	end

	-- Its weapon slot is already in use (or you already carry that gun): into your bag, magazine and parts and all
	local slot = GFR.SlotOfClass(wep:GetClass())
	local inSlot = slot && GFR.WeaponInSlot(ply, slot)
	local isGun = slot && !(OneUse(wep) && wep:GetPrimaryAmmoType() >= 0 && ply:HasWeapon(wep:GetClass()))
	if isGun && (IsValid(inSlot) or ply:HasWeapon(wep:GetClass())) then
		if GFR.InvAddEntry(ply, GFR.WeaponEntry(wep)) then
			ply:EmitSound("items/ammo_pickup.wav", 60)
			wep:Remove()
			GFR.Notify(ply, "+ " .. name .. " (in your bag - Tab to equip)")
			return
		end
		if !ply:HasWeapon(wep:GetClass()) then
			GFR.Notify(ply, "Your bag is full. Drop or stash your " .. slot .. " weapon first.")
			return
		end
	end

	if ply:HasWeapon(wep:GetClass()) then
		-- Consumables (EFT meds, grenades, flares) with no magazine: picking another up adds a use
		if OneUse(wep) && wep:GetPrimaryAmmoType() >= 0 then
			ply:GiveAmmo(1, wep:GetPrimaryAmmoType(), true)
			GFR.Notify(ply, "+ 1 " .. name)
			ply:EmitSound("items/itempickup.wav", 60)
			wep:Remove()
			return
		end
		-- Bag full: at least strip the rounds out of it
		local clip = math.max(wep:Clip1(), 0)
		if clip > 0 && wep:GetPrimaryAmmoType() >= 0 then
			ply:GiveAmmo(clip, wep:GetPrimaryAmmoType(), true)
			GFR.Notify(ply, "+ " .. clip .. " rounds from " .. name)
		else
			GFR.Notify(ply, "You already have a " .. name .. ".")
			return
		end
		ply:EmitSound("items/ammo_pickup.wav", 60)
		wep:Remove()
		return
	end

	wep.GFR_PickupBy = ply
	ply:PickupWeapon(wep)
	if IsValid(wep) && wep:GetOwner() == ply then
		GFR.Notify(ply, "+ " .. name)
	end
end
