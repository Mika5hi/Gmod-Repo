--[[
	Custom Apocalypse - SFW mode

	gfr_sfw 1   only stock Garry's Mod looks:
	              - the infected spawn as plain Left 4 Dead common infected (no playermodels worn on them)
	              - survivors / bandits / soldiers wear only GMod's own playermodels (HL2 citizens, rebels, medics,
	                refugees, CS:S hostages and terrorists; CS:S counter-terrorists for the military)
	              - the character creator only offers those same models
	            (default)
	gfr_sfw 0   back to every installed playermodel

	The character creator can be set apart from the world:
	gfr_sfw_character -1   follows gfr_sfw (default)
	gfr_sfw_character 0    every installed playermodel for your character, whatever the NPCs wear
	gfr_sfw_character 1    stock models only for your character
]]

local cv = CreateConVar("gfr_sfw", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"SFW mode: infected spawn as plain L4D infected, and NPC humans wear only GMod's stock playermodels (your character too, unless gfr_sfw_character says otherwise)")
local cvChar = CreateConVar("gfr_sfw_character", "-1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Character creator models: -1 = follow gfr_sfw, 0 = every installed playermodel, 1 = stock models only")

-- The client reads them from networked globals the server keeps in step (a replicated convar didn't always reach the
-- client when toggled, so the character list kept the old models)
-- Staff can set it per player (!gfr menu, sv_admin.lua): GFR_ModelPerm 1 = any model, -1 = stock only, 0 = as above
local function PlayerOverride(ply)
	if CLIENT then ply = ply or LocalPlayer() end
	local v = IsValid(ply) and ply:GetNW2Int("GFR_ModelPerm", 0) or 0
	if v > 0 then return false elseif v < 0 then return true end
end

if SERVER then
	SetGlobal2Bool("GFR_SFW", cv:GetBool())
	-- (kept as a string: a networked int set to 0 could read back as the fallback on the client)
	SetGlobal2String("GFR_SFWChar", tostring(cvChar:GetInt()))
	cvars.AddChangeCallback("gfr_sfw", function(_, _, new) SetGlobal2Bool("GFR_SFW", tobool(new)) end, "GFR_SFW_Global")
	cvars.AddChangeCallback("gfr_sfw_character", function(_, _, new) SetGlobal2String("GFR_SFWChar", tostring(tonumber(new) or -1)) end, "GFR_SFW_Global")
	function GFR.SFW() return cv:GetBool() end
	function GFR.SFWCharacter(ply)
		local o = PlayerOverride(ply)
		if o != nil then return o end
		local v = cvChar:GetInt()
		if v < 0 then return GFR.SFW() end
		return v == 1
	end
else
	function GFR.SFW() return GetGlobal2Bool("GFR_SFW", cv:GetBool()) end
	function GFR.SFWCharacter(ply)
		local o = PlayerOverride(ply)
		if o != nil then return o end
		local v = tonumber(GetGlobal2String("GFR_SFWChar", "")) or cvChar:GetInt()
		if v < 0 then return GFR.SFW() end
		return v == 1
	end
end

local function Range(prefix, a, b, out)
	for i = a, b do out[#out + 1] = string.format("%s%02d", prefix, i) end
	return out
end

-- player_manager names (garrysmod/lua/includes/modules/player_manager.lua)
local survivors = Range("female", 1, 12, Range("male", 1, 18, Range("medic", 1, 15, Range("refugee", 1, 4, Range("hostage", 1, 4, {})))))
for _, n in ipairs({"css_guerilla", "css_leet", "css_phoenix", "css_arctic"}) do survivors[#survivors + 1] = n end
local military = {"css_swat", "css_urban", "css_riot", "css_gasmask"}

GFR.SFWNames = {survivor = survivors, military = military}
GFR.SFWAllowed = {}
for _, n in ipairs(survivors) do GFR.SFWAllowed[n] = true end
for _, n in ipairs(military) do GFR.SFWAllowed[n] = true end

-- The model paths for one of the lists (only those that exist)
function GFR.SFWModels(kind)
	local out = {}
	local valid = player_manager.AllValidModels()
	for _, n in ipairs(GFR.SFWNames[kind] or survivors) do
		if valid[n] then out[#out + 1] = valid[n] end
	end
	return out
end

-- A model your character may wear right now (character SFW: stock only). ply: whose (the local player on the client)
function GFR.ModelAllowed(name, ply)
	return !GFR.SFWCharacter(ply) or GFR.SFWAllowed[name] == true
end
