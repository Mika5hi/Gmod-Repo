--[[
	Custom Apocalypse - picking things up
	E picks up exactly the one item under your crosshair, and the HUD names it first ("[E] Baked Beans").
	Crunchy's items default to continuous use, so holding E used to vacuum up everything near the cursor;
	the engine's own use is blocked for items and this decides what you get instead.
	Covers Crunchy pickups, our own items (materials, kits...), caps, belongings bags and dropped guns.
]]
AddCSLuaFile()
GFR = GFR or {}

local REACH = 110

function GFR.IsPickup(ent)
	if !IsValid(ent) then return false end
	if ent:IsWeapon() then return !IsValid(ent:GetOwner()) end
	local class = ent:GetClass()
	if (GFR.CustomItems && GFR.CustomItems[class]) or class == "gfr_currency" or class == "gfr_gear_bag" or class == "gfr_att_box" then return true end
	if GFR.JunkItem && GFR.JunkItem(ent) then return true end -- loose junk props (sh_junk.lua)
	local stored = scripted_ents.GetStored(class)
	return stored != nil && stored.t.Category == "Crunchy's Ultimate Pickups"
end

-- The item you're aiming at: a direct hit, or else the closest one to the crosshair in a narrow cone
function GFR.FindPickup(ply)
	local eye, aim = ply:EyePos(), ply:GetAimVector()
	local tr = util.TraceLine({start = eye, endpos = eye + aim * REACH, filter = ply, mask = MASK_SHOT})
	if GFR.IsPickup(tr.Entity) then return tr.Entity end
	local best, bestDot
	for _, ent in ipairs(ents.FindInSphere(tr.HitPos, 45)) do
		if GFR.IsPickup(ent) then
			local center = ent:WorldSpaceCenter()
			if eye:DistToSqr(center) < (REACH + 20) ^ 2 then
				local dot = aim:Dot((center - eye):GetNormalized())
				if dot > 0.965 && (!best or dot > bestDot) then best, bestDot = ent, dot end
			end
		end
	end
	return best
end

if SERVER then
	-- The engine's +use would grab whatever is nearest; items only respond to our E below
	hook.Add("PlayerUse", "GFR_Pickup_BlockEngineUse", function(ply, ent)
		if GFR.IsPickup(ent) && !ent:IsWeapon() then return false end
	end)

	hook.Add("KeyPress", "GFR_Pickup_Use", function(ply, key)
		if key != IN_USE or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied then return end
		if (ply.GFR_NextPickup or 0) > CurTime() then return end
		local ent = GFR.FindPickup(ply)
		if !IsValid(ent) then return end
		ply.GFR_NextPickup = CurTime() + 0.15
		if ent:IsWeapon() then
			ent.GFR_Loot = true
			if GFR.PickupLootWeapon then GFR.PickupLootWeapon(ply, ent) end
		elseif GFR.JunkItem(ent) then
			GFR.PickupJunk(ply, ent)
		else
			ent:Use(ply, ply, USE_ON, 1)
		end
	end)
	return
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Client: name what you'd pick up
local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Pickup", {font = "Roboto", size = S(19), weight = 700, extended = true})

local function ItemName(ent)
	local class = ent:GetClass()
	if ent:IsWeapon() then return ent.GetPrintName && ent:GetPrintName() or class end
	if class == "gfr_currency" then return "Caps" end
	if class == "gfr_att_box" then return "Attachment: " .. (GFR.AttName && GFR.AttName(ent:GetAtt()) or ent:GetAtt()) end
	if class == "gfr_gear_bag" then
		local owner = ent.GetOwnerName && ent:GetOwnerName() or ""
		return (owner != "" and owner .. "'s" or "Someone's") .. " belongings"
	end
	if GFR.CustomItems && GFR.CustomItems[class] then return GFR.CustomItems[class].name end
	local junk = GFR.JunkItem && GFR.JunkItem(ent)
	if junk then return GFR.CustomItems[junk].name end
	local stored = scripted_ents.GetStored(class)
	local name = stored && stored.t.PrintName or class
	name = string.gsub(name, "%s*%(%+*%d+%a*P%)", "")
	return string.match(name, "^.-%s%-%s(.+)$") or name
end

local lookEnt, nextFind = nil, 0

hook.Add("HUDPaint", "GFR_Pickup_Prompt", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	if CurTime() > nextFind then
		nextFind = CurTime() + 0.05
		lookEnt = GFR.FindPickup(ply)
	end
	if !IsValid(lookEnt) then return end
	local text = "[E] " .. ItemName(lookEnt)
	draw.SimpleTextOutlined(text, "GFR_Pickup", ScrW() / 2, ScrH() / 2 + S(64), Color(240, 230, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)

-- Outline it so you know which one of a pile you're about to take
hook.Add("PreDrawHalos", "GFR_Pickup_Halo", function()
	if IsValid(lookEnt) then halo.Add({lookEnt}, Color(240, 225, 170), 1, 1, 1, true, false) end
end)
