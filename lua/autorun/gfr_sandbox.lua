--[[
	Green Flu: Reimagined in Sandbox - the infection and playing as your own zombie, without the rest of the gamemode
	(no inventory, loot, factions, day/night, crafting or its HUD). The gamemode's own files are loaded as they are, so
	both stay the same: nothing here is a second copy.
		sv_infection   catching it (bites, claws, splashes, wounds), stages, turning at 100% / dying while turning
		sv_extract     turning into your zombie: collapse, twitch, get up and play it; killed by the dead / giving in (J)
		sv_zombiehunger, sh_zombieplayer, cl_zombietame   its hunger, eating, camera, sitting, leaning, night vision,
		               drifting when left alone
		sv_rise, sv_parasite, sv_headshots   the dead get back up unless the head's destroyed; head pops, melee rules
		cl_infection   symptoms, blood splashes, notices
	Only in Sandbox (and its own gamemode loads all of this itself). gfr_sandbox_zombies 0 turns it off (map restart).
	What the gamemode had and Sandbox doesn't is stood in for below: your zombie keeps no gear (Sandbox gives you your
	loadout again when you respawn), the drifting time-skip has no clock to skip.
]]
if engine.ActiveGamemode() != "sandbox" then return end

local cvOn = CreateConVar("gfr_sandbox_zombies", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Green Flu: Reimagined's infection and playable zombie in Sandbox (takes effect on map restart)")
if !cvOn:GetBool() then return end

GFR = GFR or {}
GFR.Sandbox = true

-- Stand-ins for gamemode parts that aren't here
GFR.CustomItems = GFR.CustomItems or {}
GFR.Hour = GFR.Hour or function() return 12 end
if SERVER then
	GFR.InvSync = GFR.InvSync or function() end
	GFR.SkipHours = GFR.SkipHours or function() end
end

local BASE = "greenflu/gamemode/"
local server = {"sv_infection.lua", "sv_extract.lua", "sv_zombiehunger.lua", "sv_rise.lua", "sv_parasite.lua", "sv_headshots.lua"}
local client = {"cl_zombietame.lua", "cl_infection.lua"}

if SERVER then
	AddCSLuaFile(BASE .. "sh_zombieplayer.lua")
	for _, f in ipairs(client) do AddCSLuaFile(BASE .. f) end
	for _, f in ipairs(server) do include(BASE .. f) end
	include(BASE .. "sh_zombieplayer.lua")
	return
end

include(BASE .. "sh_zombieplayer.lua")
for _, f in ipairs(client) do include(BASE .. f) end

-- How far gone you are (the gamemode shows it in its HUD; Sandbox has HL2's): a line above the health panel, once
-- there are symptoms
surface.CreateFont("GFR_SbxInfect", {font = "Roboto", size = math.Round(18 * ScrH() / 1080), weight = 800, extended = true})
local stages = {"Infected", "Fever", "Turning"}
hook.Add("HUDPaint", "GFR_Sandbox_Infection", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	local f = ply:GetNW2Float("GFR_Infection", 0)
	if f <= 0 then return end
	local stage = stages[(f < 0.34 and 1) or (f < 0.67 and 2) or 3]
	if ply:GetNW2Bool("GFR_InfSuppressed") then stage = stage .. " (treated)" end
	local pulse = f >= 0.67 and (0.6 + 0.4 * math.abs(math.sin(CurTime() * 3))) or 1
	draw.SimpleTextOutlined(string.upper(stage) .. "   " .. math.floor(f * 100) .. "%", "GFR_SbxInfect", math.Round(32 * ScrH() / 1080),
		ScrH() - math.Round(140 * ScrH() / 1080), Color(150, 210, 70, 255 * pulse), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
end)
