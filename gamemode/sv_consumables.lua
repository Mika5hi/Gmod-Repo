--[[
	Custom Apocalypse - consumables you hold to use
	Items in sh_items.lua with a swep (S.T.A.L.K.E.R. 2 Consumables, SCP: SL painkillers/adrenaline) live in the inventory
	like anything else. Using one gives you its weapon with exactly one use loaded and draws it:
		STALKER 2 items start their animation as soon as they're out
		SCP items wait for a left click (right click puts it away again)
	The pack's weapon applies its own effect (Status Effect Framework healing etc.) and spends its one use. When that use
	is gone we run GFR_ItemUsed, so hunger/thirst (sh_stats.lua), bleeding and infection treatment (sv_infection.lua) apply.
	Put away without using it: it goes back into the inventory (or at your feet if there's no room).
]]
util.AddNetworkString("GFR_InvClose")

local function Def(class) return GFR.CustomItems && GFR.CustomItems[class] end

local function Finish(ply)
	local c = ply.GFR_Consume
	ply.GFR_Consume = nil
	return c
end

local function GiveBack(ply, class)
	local def = Def(class)
	if GFR.InvAdd(ply, class, 1, false, def && def.model) == 0 then
		local ent = ents.Create(class)
		if IsValid(ent) then
			ent:SetPos(ply:GetPos() + ply:GetForward() * 25 + Vector(0, 0, 30))
			ent:Spawn()
		end
	end
end

local function BackToWeapon(ply, prev)
	if !IsValid(ply) or !ply:Alive() then return end
	local active = ply:GetActiveWeapon()
	if IsValid(active) && !string.StartWith(active:GetClass(), "weapon_stalker2_") && !string.StartWith(active:GetClass(), "weapon_scpsl_") then return end
	if prev && ply:HasWeapon(prev) then ply:SelectWeapon(prev) else ply:SelectWeapon(GFR.Fists()) end
end

function GFR.StartConsumable(ply, class)
	local def = Def(class)
	if !def or !def.swep then return false end
	if !weapons.GetStored(def.swep) then
		GFR.Notify(ply, "Can't use that: its addon (" .. def.swep .. ") isn't installed.")
		return false
	end
	local cur = ply.GFR_Consume
	if cur then
		-- The last one is used and just finishing its animation: this one comes out right after it
		if cur.used && !cur.next then
			cur.next = class
			net.Start("GFR_InvClose")
			net.Send(ply)
			return true
		end
		GFR.Notify(ply, "You're already using something.")
		return false
	end
	if ply.GFR_Tied or ply:GetNW2Bool("GFR_HandsUp") or ply:InVehicle() then
		GFR.Notify(ply, "Not now.")
		return false
	end

	local active = ply:GetActiveWeapon()
	local prev = IsValid(active) && active:GetClass() or nil
	if ply:HasWeapon(def.swep) then ply:StripWeapon(def.swep) end
	ply:Give(def.swep, true)
	ply:SetAmmo(1, def.ammo)
	ply.GFR_Consume = {class = class, swep = def.swep, ammo = def.ammo, prev = prev, started = CurTime()}
	ply:SelectWeapon(def.swep)

	net.Start("GFR_InvClose")
	net.Send(ply)
	if def.click then GFR.Notify(ply, def.name .. ": left click to use, right click to put it away.") end
	return true
end

-- SCP items drop a copy on the floor with right click; for us right click just puts it away (unless it's mid-use,
-- where right click cancels the use as it normally does)
hook.Add("InitPostEntity", "GFR_Consumables_Patch", function()
	for _, def in pairs(GFR.CustomItems or {}) do
		local t = def.swep && def.click && weapons.GetStored(def.swep)
		if t && !t.GFR_Patched then
			local orig = t.SecondaryAttack
			t.SecondaryAttack = function(self, ...)
				if self.InitializeHealing == 1 then return orig(self, ...) end
				if CLIENT then return end
				local owner = self:GetOwner()
				if IsValid(owner) && owner.GFR_Consume then BackToWeapon(owner, owner.GFR_Consume.prev) end
			end
			t.GFR_Patched = true
		end
	end
end)

timer.Create("GFR_Consumables_Watch", 0.1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local c = ply.GFR_Consume
		if !c then continue end
		if !ply:Alive() then Finish(ply) continue end

		if !c.used && ply:GetAmmoCount(c.ammo) <= 0 then
			-- Its one use is spent: the effect happened
			c.used = CurTime()
			hook.Run("GFR_ItemUsed", ply, c.class, NULL)
		end

		local active = ply:GetActiveWeapon()
		local holding = IsValid(active) && active:GetClass() == c.swep

		if holding then c.held = true end

		if c.used then
			-- Wait for the animation to finish (the pack strips its weapon), then back to what you had out,
			-- or straight on to the next thing you picked meanwhile
			if !ply:HasWeapon(c.swep) or CurTime() - c.used > 8 then
				if ply:HasWeapon(c.swep) && !holding then ply:StripWeapon(c.swep) end
				Finish(ply)
				if c.next then
					local nextClass = c.next
					timer.Simple(0.2, function()
						if !IsValid(ply) or !ply:Alive() then return end -- died: it went into your belongings (sv_infection.lua)
						if !GFR.StartConsumable(ply, nextClass) then GiveBack(ply, nextClass) return end
						if ply.GFR_Consume then ply.GFR_Consume.prev = c.prev end -- end up back on your gun, not the last item
					end)
				else
					timer.Simple(0.2, function() BackToWeapon(ply, c.prev) end)
				end
			end
		elseif !c.held then
			-- Still switching to it: guns play a holster animation first and the switch only goes through once it's
			-- done, so keep asking for a few seconds instead of deciding you changed your mind
			if CurTime() - c.started < 4 then
				if (c.nextSelect or 0) < CurTime() then
					c.nextSelect = CurTime() + 0.3
					ply:SelectWeapon(c.swep)
				end
			else
				if ply:HasWeapon(c.swep) then ply:StripWeapon(c.swep) end
				ply:SetAmmo(0, c.ammo)
				Finish(ply)
				GiveBack(ply, c.class)
			end
		elseif !holding then
			-- Had it out, then switched away without using it: back in the bag
			if ply:HasWeapon(c.swep) then ply:StripWeapon(c.swep) end
			ply:SetAmmo(0, c.ammo)
			Finish(ply)
			GiveBack(ply, c.class)
		end
	end
end)

hook.Add("PlayerSpawn", "GFR_Consumables_Spawn", function(ply)
	ply.GFR_Consume = nil
end)

-- The packs' own weapons found lying around (dropped, spawned) go into the inventory as the matching item
local bySwep = {}
hook.Add("InitPostEntity", "GFR_Consumables_Map", function()
	for class, def in pairs(GFR.CustomItems or {}) do
		if def.swep then bySwep[def.swep] = class end
	end
end)
function GFR.ConsumableForSwep(swep) return bySwep[swep] end
