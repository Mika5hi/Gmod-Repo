--[[
	Custom Apocalypse - placing what you build
	Using a kit (barricade, wall, workbench, crate, bed, lamp...) from the inventory puts a see-through ghost of it
	where you're looking:
		green = it fits there, red = it doesn't (too far, too steep, or inside something)
		scroll wheel = turn it a bit, R = turn it a quarter, left click = put it down, right click = cancel
	The server checks the spot again (sv_crafting.lua) and uses up the kit once it's down.
]]
local REACH = 240
local placing -- {class, place, ghost, yaw}

local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Place", {font = "Roboto", size = S(18), weight = 700, extended = true})
surface.CreateFont("GFR_PlaceSmall", {font = "Roboto", size = S(15), weight = 600, extended = true})

local function Stop(tellServer)
	if !placing then return end
	if IsValid(placing.ghost) then placing.ghost:Remove() end
	placing = nil
	if tellServer then
		net.Start("GFR_PlaceCancel")
		net.SendToServer()
	end
end

net.Receive("GFR_PlaceStart", function()
	local class = net.ReadString()
	local def = GFR.CustomItems && GFR.CustomItems[class]
	if !def or !def.place then return end
	Stop(false)
	local ghost = ClientsideModel(def.place.model, RENDERGROUP_TRANSLUCENT)
	if !IsValid(ghost) then return end
	ghost:SetRenderMode(RENDERMODE_TRANSCOLOR)
	ghost:SetNoDraw(false)
	placing = {class = class, place = def.place, name = def.place.name or def.name, ghost = ghost, yaw = LocalPlayer():EyeAngles().y + 90}
	if GFR.CloseInventory then GFR.CloseInventory() end
end)

-- Where the ghost goes right now, and whether it fits
local function Solve()
	local ply = LocalPlayer()
	local ghost = placing.ghost
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = {ply, ghost}, mask = MASK_SOLID})
	local hitPos = tr.HitPos
	-- Aiming at nothing: drop it to the floor at the end of reach
	if !tr.Hit then
		local down = util.TraceLine({start = hitPos, endpos = hitPos - Vector(0, 0, 200), filter = {ply, ghost}, mask = MASK_SOLID})
		tr, hitPos = down, down.HitPos
	end
	ghost:SetAngles(Angle(0, placing.yaw, 0))
	local pos = hitPos - Vector(0, 0, ghost:OBBMins().z)
	ghost:SetPos(pos)

	local ok, why = true, nil
	if !tr.Hit or tr.HitNormal.z < 0.6 then ok, why = false, "Needs flat ground"
	elseif hitPos:Distance(ply:GetPos()) > REACH then ok, why = false, "Too far"
	else
		local mins, maxs = ghost:OBBMins() * 0.85, ghost:OBBMaxs() * 0.85
		mins.z = math.max(mins.z, ghost:OBBMins().z + 4)
		local hull = util.TraceHull({start = pos + Vector(0, 0, 2), endpos = pos + Vector(0, 0, 3), mins = mins, maxs = maxs, filter = {ghost}, mask = MASK_SOLID})
		if hull.Hit then ok, why = false, "Something's in the way" end
	end
	placing.pos, placing.ok, placing.why = hitPos, ok, why
	ghost:SetColor(ok and Color(120, 255, 140, 150) or Color(255, 90, 80, 150))
end

hook.Add("Think", "GFR_Place_Think", function()
	if !placing then return end
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") or !IsValid(placing.ghost) then Stop(true) return end
	Solve()
end)

-- Mouse and keys while placing (they don't fire your weapon or switch it)
hook.Add("PlayerBindPress", "GFR_Place_Input", function(ply, bind, pressed)
	if !placing or !pressed then return end
	if string.find(bind, "+attack2", 1, true) then
		Stop(true)
		surface.PlaySound("buttons/button10.wav")
		return true
	elseif string.find(bind, "+attack", 1, true) then
		if !placing.ok then
			surface.PlaySound("buttons/button10.wav")
			return true
		end
		net.Start("GFR_PlaceConfirm")
		net.WriteString(placing.class)
		net.WriteVector(placing.pos)
		net.WriteFloat(placing.yaw)
		net.SendToServer()
		Stop(false)
		return true
	elseif string.find(bind, "invnext", 1, true) then
		placing.yaw = placing.yaw - 15
		return true
	elseif string.find(bind, "invprev", 1, true) then
		placing.yaw = placing.yaw + 15
		return true
	elseif string.find(bind, "+reload", 1, true) then
		placing.yaw = placing.yaw + 90
		return true
	end
end)

hook.Add("HUDPaint", "GFR_Place_HUD", function()
	if !placing then return end
	local cx, cy = ScrW() / 2, ScrH() * 0.78
	draw.SimpleTextOutlined("Placing: " .. (placing.name or "?"), "GFR_Place", cx, cy, Color(235, 225, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
	if placing.why then
		draw.SimpleTextOutlined(placing.why, "GFR_PlaceSmall", cx, cy + S(22), Color(240, 110, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
	end
	draw.SimpleTextOutlined("[LMB] Place    [Scroll] Turn    [R] Turn 90°    [RMB] Cancel", "GFR_PlaceSmall", cx, cy + S(44), Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
end)
