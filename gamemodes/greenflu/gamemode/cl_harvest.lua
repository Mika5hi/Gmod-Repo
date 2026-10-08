--[[
	Custom Apocalypse - harvest prompt/progress and camouflage indicator
	Server side: sv_harvest.lua
]]
local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Harvest", {font = "Roboto", size = S(18), weight = 700, extended = true})

local progress -- {text, start, duration}
net.Receive("GFR_Progress", function()
	local text, duration = net.ReadString(), net.ReadFloat()
	progress = duration > 0 and {text = text, start = CurTime(), duration = duration} or nil
end)

hook.Add("HUDPaint", "GFR_Harvest_Draw", function()
	local ply = LocalPlayer()
	-- (none of it while you're a zombie: you eat bodies, you don't search or carve them)
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	local cx, cy = ScrW() / 2, ScrH() / 2

	if progress then
		local frac = math.Clamp((CurTime() - progress.start) / progress.duration, 0, 1)
		local w, h = S(260), S(8)
		draw.SimpleTextOutlined(progress.text, "GFR_Harvest", cx, cy + S(46), Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 180))
		draw.RoundedBox(h / 2, cx - w / 2, cy + S(60), w, h, Color(0, 0, 0, 160))
		draw.RoundedBox(h / 2, cx - w / 2, cy + S(60), math.max(w * frac, h), h, Color(170, 50, 40))
	else
		local ent = GFR.LookedAtBody(ply)
		if IsValid(ent) then
			local text, col
			if ent:GetNW2Bool("GFR_HasPockets") then
				text, col = "[Q] Search body", Color(235, 225, 200)
			elseif GFR.HoldingBlade && GFR.HoldingBlade(ply) then
				-- Butchering only comes up with a knife in your hand
				if ent:GetNW2Bool("GFR_Burned") then
					text, col = "Burned corpse", Color(150, 150, 150)
				elseif ent:GetNW2Bool("GFR_Harvested") then
					text, col = "Zombie corpse (harvested)", Color(150, 150, 150)
				else
					text, col = "[Q] Harvest zombie corpse", Color(220, 160, 150)
				end
			end
			if text then draw.SimpleTextOutlined(text, "GFR_Harvest", cx, cy + S(40), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180)) end
		end
	end

	-- Camouflage timer under the clock
	local left = ply:GetNW2Float("GFR_CamoUntil", 0) - CurTime()
	if left > 0 then
		draw.SimpleTextOutlined(string.format("Camouflaged  %d:%02d", math.floor(left / 60), math.floor(left % 60)), "GFR_Harvest",
			cx, S(40), Color(160, 190, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 180))
	end
end)

-- Covered in gore: a dirty brown-green tint at the edges of the screen
local gradL, gradR = Material("vgui/gradient-l"), Material("vgui/gradient-r")
hook.Add("HUDPaintBackground", "GFR_Camo_Overlay", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or ply:GetNW2Float("GFR_CamoUntil", 0) <= CurTime() then return end
	local w, h = ScrW(), ScrH()
	surface.SetDrawColor(60, 50, 20, 70)
	surface.SetMaterial(gradL) surface.DrawTexturedRect(0, 0, w * 0.25, h)
	surface.SetMaterial(gradR) surface.DrawTexturedRect(w * 0.75, 0, w * 0.25, h)
end)
