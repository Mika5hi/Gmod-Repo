--[[
	Custom Apocalypse - day/night cycle (client)
	Reloads lightmaps when the server's light level changes, adds night fog/tint and draws the clock.
]]
local applied

timer.Create("GFR_DayNight_Lightmaps", 1, 0, function()
	local letter = GetGlobal2String("GFR_Light", "")
	if letter != "" && letter != applied then
		applied = letter
		render.RedownloadAllLightmaps(true)
	end
end)

local function Darkness() return 1 - GFR.Daylight() end

-- Night fog: hides how far you can see, in a dark blue
local function Fog(scale)
	local d = Darkness()
	if d <= 0 then return end
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(200 * scale)
	render.FogEnd((6000 - 4500 * d) * scale)
	render.FogMaxDensity(0.85 * d)
	render.FogColor(6, 8, 14)
	return true
end
hook.Add("SetupWorldFog", "GFR_DayNight_Fog", function() return Fog(1) end)
hook.Add("SetupSkyboxFog", "GFR_DayNight_SkyFog", function(scale) return Fog(scale) end)

-- Moonlight tint: darker, colder, less saturated
hook.Add("RenderScreenspaceEffects", "GFR_DayNight_Tint", function()
	local d = Darkness()
	if d <= 0 then return end
	DrawColorModify({
		["$pp_colour_addr"] = 0,
		["$pp_colour_addg"] = 0,
		["$pp_colour_addb"] = 0.015 * d,
		["$pp_colour_brightness"] = -0.04 * d,
		["$pp_colour_contrast"] = 1 - 0.08 * d,
		["$pp_colour_colour"] = 1 - 0.45 * d,
		["$pp_colour_mulr"] = 0,
		["$pp_colour_mulg"] = 0,
		["$pp_colour_mulb"] = 0
	})
end)

-- Clock, top centre: only while your inventory is open, fading in and out (drawn over the menus, not under them)
surface.CreateFont("GFR_Clock", {font = "Roboto", size = math.Round(18 * ScrH() / 1080), weight = 700, extended = true})

local clockA = 0
hook.Add("DrawOverlay", "GFR_DayNight_Clock", function()
	local ply = LocalPlayer()
	if !IsValid(ply) then return end
	local want = ply:Alive() && GFR.InventoryOpen && GFR.InventoryOpen() and 1 or 0
	clockA = math.Approach(clockA, want, FrameTime() * 4) -- (about a quarter of a second)
	if clockA <= 0 then return end
	local h = GFR.Hour()
	local text = string.format("Day %d   %02d:%02d", GFR.Day(), math.floor(h), math.floor((h % 1) * 60))
	local col = GFR.IsNight(h) and Color(140, 160, 220) or Color(235, 215, 160)
	draw.SimpleTextOutlined(text, "GFR_Clock", ScrW() / 2, math.Round(14 * ScrH() / 1080), ColorAlpha(col, 255 * clockA), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 170 * clockA))
end)
