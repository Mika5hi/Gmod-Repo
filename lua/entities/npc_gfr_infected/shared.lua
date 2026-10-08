ENT.Base 			= "npc_vj_creature_base"
ENT.Type 			= "ai"
ENT.PrintName 		= "Infected"
ENT.Author 			= "Green Flu: Reimagined"
ENT.Category		= "Green Flu: Reimagined"

-- Left 4 Dead common infected (needs [Left 4 Dead Common Infected SNPCs]) with our grab / eat / crawl / rise
ENT.IsVJL4DCommonInfected = true
ENT.VJ_ID_Undead = true

if CLIENT then
	-- A player driving their own zombie (Custom Apocalypse self-injection): a close camera centred on the body,
	-- instead of the VJ controller's far, off-centre one. Scroll wheel still zooms in and out.
	function ENT:Controller_OnCalcView(cont, ply, origin, angles, fov)
		if !self:GetNW2Bool("GFR_PlayerZombie") then return false end
		-- The gamemode's camera (head height of the actual body): sh_zombieplayer.lua
		if GFR && GFR.ZombieCalcView then return GFR.ZombieCalcView(self, cont, ply, origin, angles, fov) end
		local dist = math.Clamp((cont.VJC_Camera_Zoom or 100) * 0.75, 30, 220)
		-- Shoulder height (eye level of the body), a bit lower while feeding; the camera sits a little above it
		local pivot = self:GetPos() + Vector(0, 0, self:GetNW2Bool("GFR_ZEating") and 44 or 68)
		local tr = util.TraceHull({
			start = pivot,
			endpos = pivot - angles:Forward() * dist + angles:Up() * 16,
			filter = {self, ply},
			mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
			mask = MASK_SOLID_BRUSHONLY
		})
		return {origin = tr.HitPos, angles = angles, fov = fov, speed = 14}
	end
end
