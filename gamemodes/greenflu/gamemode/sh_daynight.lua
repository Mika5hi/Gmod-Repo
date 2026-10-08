--[[
	Custom Apocalypse - day/night cycle (shared helpers)
	Server: sv_daynight.lua drives the clock, map lighting and the painted sky.
	Client: cl_daynight.lua does night fog/colour and the clock.
	Global2 vars: GFR_Hour (0-24), GFR_Day, GFR_Light (light style letter)
]]
GFR = GFR or {}

function GFR.Hour() return GetGlobal2Float("GFR_Hour", 12) end
function GFR.Day() return GetGlobal2Int("GFR_Day", 1) end

-- 1 = full daylight, 0 = deep night. Dawn 5-7, dusk 18-21.
function GFR.Daylight(h)
	h = h or GFR.Hour()
	if h >= 7 && h < 18 then return 1 end
	if h >= 5 && h < 7 then return (h - 5) / 2 end
	if h >= 18 && h < 21 then return 1 - (h - 18) / 3 end
	return 0
end

function GFR.IsNight(h)
	h = h or GFR.Hour()
	return h >= 20 or h < 5.5
end
