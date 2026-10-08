--[[
	Custom Apocalypse - moving props and bodies
	Tap E: picks up items / uses things as before.
	Hold E on a loose prop or a body: you take hold of it.
		- light props are carried in front of you
		- heavy props and bodies are dragged along the ground (you walk slower)
	Let go of E to drop it. Frozen/fixed props won't budge; really heavy ones are too much for one person.
	Source's own +use pickup is switched off (it fought with this and the item pickups).
]]
AddCSLuaFile()
GFR = GFR or {}

local HOLD = 0.3        -- seconds E has to be held
local REACH = 100
local MAX_MASS = 500    -- heavier props can't be moved by hand
local LIGHT_MASS = 35   -- up to this is carried, above it's dragged

local draggable = {prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true, prop_ragdoll = true}

function GFR.CanDrag(ent)
	if !IsValid(ent) or !draggable[ent:GetClass()] then return false end
	if GFR.IsPickup && GFR.IsPickup(ent) then return false end -- items are picked up with a tap
	-- Your own builds (barricades, benches, storage) are taken down with Crouch+E instead
	if ent:GetNW2Bool("GFR_Placed") or ent:GetNW2Int("GFR_BarMax", 0) > 0 or ent:GetNW2Bool("GFR_Workbench") or ent:GetNW2Bool("GFR_Fire") then return false end
	return true
end

if SERVER then
	local function StopDrag(ply)
		local d = ply.GFR_Drag
		if !d then return end
		ply.GFR_Drag = nil
		ply:SetNW2Bool("GFR_Dragging", false)
		ply:SetLaggedMovementValue(1)
		if IsValid(d.ent) then d.ent.GFR_DraggedBy = nil end
	end
	GFR.StopDrag = StopDrag

	local function Busy(ply)
		return !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied or ply.GOTDR_Grappled or ply.GFR_ParasiteLatch or ply:InVehicle()
	end

	local function TryStart(ply)
		if Busy(ply) then return end
		local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = ply, mask = MASK_SHOT})
		local ent = tr.Entity
		if !GFR.CanDrag(ent) or ent.GFR_DraggedBy then return end
		local isRag = ent:GetClass() == "prop_ragdoll"
		local phys = isRag and ent:GetPhysicsObjectNum(math.max(tr.PhysicsBone or 0, 0)) or ent:GetPhysicsObject()
		if !IsValid(phys) then return end
		if !phys:IsMotionEnabled() then
			if (ply.GFR_NextDragMsg or 0) < CurTime() then
				ply.GFR_NextDragMsg = CurTime() + 2
				GFR.Notify(ply, "It won't budge.")
			end
			return
		end
		local heavy = isRag or phys:GetMass() > LIGHT_MASS
		if !isRag && phys:GetMass() > MAX_MASS then
			if (ply.GFR_NextDragMsg or 0) < CurTime() then
				ply.GFR_NextDragMsg = CurTime() + 2
				GFR.Notify(ply, "Too heavy to move on your own.")
			end
			return
		end
		ply.GFR_Drag = {
			ent = ent, phys = phys, heavy = heavy, ragdoll = isRag,
			grip = phys:WorldToLocal(tr.HitPos),
			dist = math.Clamp(tr.HitPos:Distance(ply:EyePos()), 45, 85)
		}
		ent.GFR_DraggedBy = ply
		ply:SetNW2Bool("GFR_Dragging", true)
		ply:SetLaggedMovementValue(heavy and 0.6 or 0.85)
		ent:EmitSound(isRag and "physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav" or "physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 60)
	end

	hook.Add("KeyPress", "GFR_Drag_Press", function(ply, key)
		if key == IN_USE && !ply.GFR_Drag then ply.GFR_DragPress = CurTime() end
	end)

	hook.Add("KeyRelease", "GFR_Drag_Release", function(ply, key)
		if key != IN_USE then return end
		ply.GFR_DragPress = nil
		StopDrag(ply)
	end)

	hook.Add("Think", "GFR_Drag_Think", function()
		for _, ply in ipairs(player.GetAll()) do
			if ply.GFR_DragPress && !ply.GFR_Drag && CurTime() - ply.GFR_DragPress >= HOLD then
				ply.GFR_DragPress = nil
				if ply:KeyDown(IN_USE) then TryStart(ply) end
			end
			local d = ply.GFR_Drag
			if !d then continue end
			if Busy(ply) or !IsValid(d.ent) or !IsValid(d.phys) or !ply:KeyDown(IN_USE) then StopDrag(ply) continue end
			local target = ply:EyePos() + ply:GetAimVector() * d.dist
			if d.heavy then
				-- Dragged along the floor, not lifted
				target.z = math.min(target.z, ply:GetPos().z + (d.ragdoll and 30 or 20))
			end
			local grip = d.phys:LocalToWorld(d.grip)
			local delta = target - grip
			if delta:Length() > 140 then StopDrag(ply) continue end -- snagged on something
			local speed = d.heavy and 260 or 420
			local vel = delta * (d.heavy and 6 or 10)
			if vel:Length() > speed then vel = vel:GetNormalized() * speed end
			if d.heavy then vel = d.phys:GetVelocity() * 0.4 + vel * 0.6 end
			d.phys:Wake()
			d.phys:SetVelocity(vel)
			if !d.heavy then d.phys:AddAngleVelocity(-d.phys:GetAngleVelocity() * 0.3) end
		end
	end)

	hook.Add("PlayerDeath", "GFR_Drag_Death", StopDrag)
	hook.Add("PlayerSpawn", "GFR_Drag_Spawn", StopDrag)

	-- Source's +use pickup is replaced by the above
	hook.Add("AllowPlayerPickup", "GFR_Drag_NoEnginePickup", function() return false end)
	return
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Client: hint
local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_DragHint", {font = "Roboto", size = S(17), weight = 700, extended = true})

hook.Add("HUDPaint", "GFR_Drag_Hint", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	local text
	if ply:GetNW2Bool("GFR_Dragging") then
		text = "Let go of [E] to drop"
	else
		local tr = ply:GetEyeTrace()
		local ent = tr.Entity
		if IsValid(ent) && tr.HitPos:DistToSqr(ply:EyePos()) < REACH * REACH && GFR.CanDrag(ent) && !(GFR.ContainerType && GFR.ContainerType(ent)) then
			text = ent:GetClass() == "prop_ragdoll" and "[Hold E] Drag body" or "[Hold E] Move"
		end
	end
	if text then
		draw.SimpleTextOutlined(text, "GFR_DragHint", ScrW() / 2, ScrH() / 2 + S(90), Color(215, 215, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
	end
end)
