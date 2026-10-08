--[[
	Custom Apocalypse - day/night cycle (server)
	- Clock: a full day takes gfr_day_length real minutes (default 24: a real second is an in-game minute)
	- Map lighting dims through light style 0 (affects the map's baked lights)
	- Sky: uses the map's env_skypaint, or switches the map to GMod's painted sky so it works on any map
	- Night: more zombies and some of them run (see sv_spawner.lua)
]]

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_daynight_enabled", "1", flags, "Enable the day/night cycle")
local cvLength  = CreateConVar("gfr_day_length", "24", flags, "Real minutes for a full 24 hour day (24 = one real second per in-game minute)")
-- The old default (40) moves to the new one once; a length you picked yourself stays
if !cookie.GetString("gfr_daylen_v2") then
	cookie.Set("gfr_daylen_v2", "1")
	if cvLength:GetFloat() == 40 then RunConsoleCommand("gfr_day_length", "24") end
end
local cvStart   = CreateConVar("gfr_start_hour", "8", flags, "Hour the game starts at")
local cvDarkest = CreateConVar("gfr_night_darkness", "b", flags, "Light style letter at midnight (a = pitch black, m = normal)")

local hour, day = cvStart:GetFloat(), 1
local sky, sun
local lastLetter, wasNight, lastSun

local dayTop, dayBottom, dayDusk = Vector(0.2, 0.5, 1), Vector(0.8, 1, 1), Vector(1, 0.2, 0)
local nightTop, nightBottom = Vector(0, 0.002, 0.01), Vector(0.005, 0.01, 0.025)

local function SetupSky()
	sky = ents.FindByClass("env_skypaint")[1]
	if !IsValid(sky) then
		-- No painted sky on this map: make one and switch the skybox to it
		sky = ents.Create("env_skypaint")
		sky:Spawn()
		sky:Activate()
		RunConsoleCommand("sv_skyname", "painted")
	end
	sun = ents.FindByClass("env_sun")[1]
end

local function LerpVec(t, a, b) return a + (b - a) * t end

local function Apply()
	local light = GFR.Daylight(hour)

	-- Map lighting, in steps (each change makes clients reload lightmaps)
	local dark = string.byte(string.lower(cvDarkest:GetString())) or string.byte("b")
	local letter = string.char(math.Round(dark + (string.byte("m") - dark) * light))
	if letter != lastLetter then
		lastLetter = letter
		engine.LightStyle(0, letter)
		SetGlobal2String("GFR_Light", letter)
	end

	-- Sky colours, stars at night, a red-orange horizon at dawn/dusk
	if IsValid(sky) then
		sky:SetTopColor(LerpVec(light, nightTop, dayTop))
		sky:SetBottomColor(LerpVec(light, nightBottom, dayBottom))
		local dusk = (light > 0 && light < 1) and (1 - math.abs(light - 0.5) * 2) or 0
		sky:SetDuskColor(dayDusk)
		sky:SetDuskIntensity(dusk * 1.5)
		sky:SetDuskScale(1)
		sky:SetDrawStars(light < 0.6)
		sky:SetStarFade(1.5 * (1 - light))
		sky:SetSunSize(light > 0.1 and 2 or 0)
	end
	local sunOn = light > 0.15
	if IsValid(sun) && sunOn != lastSun then
		lastSun = sunOn
		sun:Fire(sunOn and "TurnOn" or "TurnOff")
	end

	local night = GFR.IsNight(hour)
	if night != wasNight then
		if wasNight != nil then
			for _, ply in ipairs(player.GetAll()) do
				GFR.Notify(ply, night and "Night falls. The dead grow restless..." or ("Dawn. You survived night " .. math.max(day - 1, 1) .. "."))
			end
		end
		wasNight = night
	end
end

-- In-game hours gone by since the map started: only ever goes up, sleeping skips it forward too (GFR.SkipHours).
-- Loot refills run on it (sv_containers.lua, sv_loot.lua). Keeps going with the day/night cycle switched off.
local clock = 0
function GFR.GameHours() return clock end

timer.Create("GFR_DayNight", 1, 0, function()
	clock = clock + 24 / math.max(cvLength:GetFloat() * 60, 1)
	if !cvEnabled:GetBool() then return end
	hour = hour + 24 / math.max(cvLength:GetFloat() * 60, 1)
	if hour >= 24 then
		hour = hour - 24
		day = day + 1
	end
	SetGlobal2Float("GFR_Hour", hour)
	SetGlobal2Int("GFR_Day", day)
	Apply()
end)

hook.Add("InitPostEntity", "GFR_DayNight_Init", function()
	SetupSky()
	hour, day = cvStart:GetFloat(), 1
	SetGlobal2Float("GFR_Hour", hour)
	SetGlobal2Int("GFR_Day", day)
	Apply()
end)

hook.Add("PostCleanupMap", "GFR_DayNight_Cleanup", function()
	timer.Simple(0.5, function()
		SetupSky()
		lastLetter = nil
		Apply()
	end)
end)

-- Move the clock forward (sleeping, sv_base.lua). Crossing midnight counts as a new day.
function GFR.SkipHours(h)
	clock = clock + h
	hour = hour + h
	while hour >= 24 do
		hour = hour - 24
		day = day + 1
	end
	SetGlobal2Float("GFR_Hour", hour)
	SetGlobal2Int("GFR_Day", day)
	Apply()
end

-- Real seconds one in-game hour lasts
function GFR.RealSecondsPerHour()
	return math.max(cvLength:GetFloat() * 60, 1) / 24
end

-- gfr_settime 22  -> jump to 22:00
concommand.Add("gfr_settime", function(ply, _, args)
	if IsValid(ply) && !GFR.CanCheat(ply) then return end
	local h = tonumber(args[1] or "")
	if !h then print("Usage: gfr_settime <0-24>") return end
	hour = h % 24
	SetGlobal2Float("GFR_Hour", hour)
	Apply()
end)
