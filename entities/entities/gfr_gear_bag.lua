-- Custom Apocalypse Project - belongings dropped by a turned player's zombie when it dies
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Belongings"
ENT.Spawnable = false

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "OwnerName")
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_c17/BriefCase001a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() end
	end

	function ENT:Use(ply)
		if !IsValid(ply) or !ply:IsPlayer() then return end
		local gear = self.Gear or {weapons = {}, ammo = {}}
		-- Inventory items first; whatever doesn't fit stays in the bag
		local left = {}
		for _, e in ipairs(gear.items or {}) do
			local added
			if e.wep then
				-- A gun from your bag, magazine and parts kept
				added = (GFR && GFR.InvAddEntry && GFR.InvAddEntry(ply, e)) and 1 or 0
			else
				added = GFR && GFR.InvAdd && GFR.InvAdd(ply, e.class, e.count, e.contaminated, e.model) or 0
			end
			if added < e.count then
				e.count = e.count - added
				left[#left + 1] = e
			end
		end
		gear.items = left
		-- ARC9 hands out free reserve ammo when a gun is equipped, so remember what we had
		-- and set the totals exactly (what you carried + what was in the bag) once the guns settle
		local target = {}
		for id, count in pairs(ply:GetAmmo()) do target[id] = count end
		for id, count in pairs(gear.ammo) do target[id] = (target[id] or 0) + count end
		local given = {}
		for _, w in ipairs(gear.weapons) do
			if !ply:HasWeapon(w.class) then
				local wep = ply:Give(w.class, true)
				if IsValid(wep) then
					wep.GaveDefaultAmmo = true -- ARC9: don't add starter ammo on a later deploy either
					given[#given + 1] = {wep = wep, clip1 = w.clip1, clip2 = w.clip2}
					-- The parts that were fitted to it (sh_attachments.lua)
					if w.atts && GFR.RestoreWeaponAtts then
						timer.Simple(0.2, function() GFR.RestoreWeaponAtts(wep, w.atts) end)
					end
					for _, id in ipairs({wep:GetPrimaryAmmoType(), wep:GetSecondaryAmmoType()}) do
						if id >= 0 then target[id] = target[id] or 0 end
					end
				end
			end
		end
		local function Settle()
			if !IsValid(ply) then return end
			for _, g in ipairs(given) do
				if IsValid(g.wep) then
					if g.clip1 && g.clip1 >= 0 then g.wep:SetClip1(g.clip1) end
					if g.clip2 && g.clip2 >= 0 then g.wep:SetClip2(g.clip2) end
				end
			end
			for id, count in pairs(target) do ply:SetAmmo(count, id) end
		end
		Settle()
		timer.Simple(0, Settle)
		timer.Simple(0.3, Settle)
		if (gear.caps or 0) > 0 && GFR && GFR.AddCaps then
			GFR.AddCaps(ply, gear.caps)
			GFR.Notify(ply, "+ " .. gear.caps .. " caps")
		end
		if gear.attstash && GFR && GFR.GiveAttStash then
			local n = GFR.GiveAttStash(ply, gear.attstash)
			if n > 0 then GFR.Notify(ply, "+ " .. n .. " weapon attachments") end
		end
		gear.weapons, gear.ammo, gear.caps, gear.attstash = {}, {}, 0, nil
		self:EmitSound("items/ammopickup.wav")
		if #left > 0 then
			if GFR && GFR.Notify then GFR.Notify(ply, "You can't carry everything. The rest is still in the bag.") end
		else
			self:Remove()
		end
	end
else
	function ENT:Draw()
		self:DrawModel()
		local ply = LocalPlayer()
		if ply:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
		local ang = ply:EyeAngles()
		ang:RotateAroundAxis(ang:Forward(), 90)
		ang:RotateAroundAxis(ang:Right(), 90)
		cam.Start3D2D(self:GetPos() + Vector(0, 0, 22), Angle(0, ang.y, 90), 0.08)
			local name = self:GetOwnerName()
			draw.SimpleTextOutlined((name != "" and name .. "'s" or "Someone's") .. " belongings", "DermaLarge", 0, 0, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
		cam.End3D2D()
	end
end
